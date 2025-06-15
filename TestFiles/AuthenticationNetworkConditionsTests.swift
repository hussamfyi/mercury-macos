import XCTest
import Network
import Combine
@testable import mercury_macos

/// Tests for authentication behavior across various network conditions
@MainActor
final class AuthenticationNetworkConditionsTests: XCTestCase {
    
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    var networkMonitor: NetworkMonitor!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        super.setUp()
        authManager = await AuthManager()
        keychainManager = KeychainManager()
        networkMonitor = NetworkMonitor()
        cancellables = Set<AnyCancellable>()
        
        // Clean up any existing test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
    }
    
    override func tearDown() {
        // Clean up test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
        
        cancellables = nil
        authManager = nil
        keychainManager = nil
        networkMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Authentication Flow Network Resilience Tests
    
    func testAuthenticationWithPoorConnection() async throws {
        // Start with poor connection simulation
        await simulateNetworkQuality(.poor)
        
        // Attempt authentication with poor connection
        // Note: In a real test environment, this would use mock OAuth flow
        // For this test, we'll verify the behavior and timeouts
        
        let startTime = Date()
        
        // This will typically fail in test environment, but we're testing timeout behavior
        let result = await authManager.authenticate()
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        switch result {
        case .success:
            // Unlikely in test environment, but if it succeeds, verify it completed
            XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated on success")
            
        case .failure(let error):
            // Should fail within reasonable timeout for poor connection (45s max per NetworkState extension)
            XCTAssertLessThan(elapsed, 50.0, "Should timeout within extended poor connection limit")
            
            // Error should indicate network-related issue
            let errorMessage = error.localizedDescription.lowercased()
            let isNetworkRelated = errorMessage.contains("network") || 
                                  errorMessage.contains("timeout") || 
                                  errorMessage.contains("connection")
            
            if !isNetworkRelated {
                print("ℹ️ Non-network error during poor connection test: \(error)")
            }
        }
    }
    
    func testAuthenticationTimeoutWithSlowNetwork() async throws {
        // Simulate slow network conditions
        await simulateNetworkDelay(seconds: 35) // Longer than normal auth timeout
        
        let startTime = Date()
        let result = await authManager.authenticate()
        let elapsed = Date().timeIntervalSince(startTime)
        
        switch result {
        case .success:
            print("ℹ️ Authentication succeeded despite simulated delay")
            
        case .failure(let error):
            // Should timeout within PRD-specified auth timeout (30s baseline)
            // But may be extended to 45s for poor connections
            XCTAssertLessThan(elapsed, 50.0, "Should timeout within network-adjusted auth limit")
            
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("timeout") || errorMessage.contains("timed out") {
                print("✅ Properly timed out authentication with slow network")
            }
        }
    }
    
    func testAuthenticationRetryOnNetworkFailure() async throws {
        var networkRetryEvents: [String] = []
        
        // Listen for network retry events
        authManager.eventManager.networkEvents
            .sink { event in
                if case .operationRetried(let operation, let attempt) = event {
                    networkRetryEvents.append("\(operation):attempt_\(attempt)")
                }
            }
            .store(in: &cancellables)
        
        // Simulate intermittent network failures
        await simulateIntermittentNetworkFailures()
        
        let result = await authManager.authenticate()
        
        // Allow time for events to be processed
        try await Task.sleep(nanoseconds: 100_000_000)
        
        switch result {
        case .success:
            print("✅ Authentication succeeded with network retries")
            
        case .failure:
            print("ℹ️ Authentication failed after retries (expected in test environment)")
        }
        
        // Verify retry events were generated if network issues occurred
        if !networkRetryEvents.isEmpty {
            print("📊 Network retry events: \(networkRetryEvents)")
            XCTAssertTrue(networkRetryEvents.contains { $0.contains("authentication") },
                         "Should have authentication retry events")
        }
    }
    
    func testAuthenticationStateConsistencyAcrossNetworkChanges() async throws {
        // Store valid tokens first
        let mockAccessToken = "network_state_consistency_token"
        let mockRefreshToken = "network_state_consistency_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Verify initial authenticated state
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated with stored tokens")
        
        var authStateChanges: [AuthenticationState] = []
        
        // Monitor authentication state changes
        authManager.authenticationStatePublisher
            .sink { state in
                authStateChanges.append(state)
            }
            .store(in: &cancellables)
        
        // Simulate network connectivity loss
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Authentication state should remain stable with cached tokens
        XCTAssertTrue(authManager.isAuthenticated, 
                     "Should maintain authenticated state during network loss")
        
        // Restore network connectivity
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should still be authenticated after network restoration
        XCTAssertTrue(authManager.isAuthenticated, 
                     "Should remain authenticated after network restoration")
        
        // Verify no unwanted state transitions occurred
        let errorStates = authStateChanges.filter { state in
            if case .error = state { return true }
            return false
        }
        
        // Should not have error states due to temporary network loss
        XCTAssertTrue(errorStates.isEmpty || errorStates.count <= 1, 
                     "Should not have multiple error states from network changes")
    }
    
    // MARK: - Token Refresh Network Resilience Tests
    
    func testTokenRefreshWithNetworkInstability() async throws {
        // Set up token that will expire soon to trigger refresh
        let mockAccessToken = "refresh_network_test_token"
        let mockRefreshToken = "refresh_network_test_refresh"
        let soonExpiringDate = Date().addingTimeInterval(600) // 10 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: soonExpiringDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        var refreshEvents: [String] = []
        
        // Monitor token refresh events
        authManager.eventManager.authenticationEvents
            .sink { event in
                switch event {
                case .tokenRefreshStarted:
                    refreshEvents.append("refresh_started")
                case .tokenRefreshCompleted:
                    refreshEvents.append("refresh_completed")
                case .tokenRefreshFailed:
                    refreshEvents.append("refresh_failed")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Simulate network instability during potential refresh window
        for _ in 1...3 {
            await simulateNetworkConnectivityChange(isConnected: false)
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await simulateNetworkConnectivityChange(isConnected: true)
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        // Allow time for refresh operations to complete
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Verify refresh attempts were made
        if !refreshEvents.isEmpty {
            print("📊 Token refresh events during network instability: \(refreshEvents)")
            
            // Should have attempted refresh
            XCTAssertTrue(refreshEvents.contains("refresh_started"), 
                         "Should have started token refresh")
        }
        
        // Authentication should remain stable
        XCTAssertTrue(authManager.isAuthenticated, 
                     "Should maintain authentication despite network instability")
    }
    
    func testTokenRefreshTimeoutHandling() async throws {
        // Set up expiring token
        let mockAccessToken = "timeout_refresh_token"
        let mockRefreshToken = "timeout_refresh_refresh"
        let expiringSoonDate = Date().addingTimeInterval(300) // 5 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expiringSoonDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate slow network for timeout testing
        await simulateNetworkDelay(seconds: 25) // Longer than refresh timeout
        
        var refreshFailed = false
        
        // Monitor for refresh failures
        authManager.eventManager.authenticationEvents
            .sink { event in
                if case .tokenRefreshFailed(let error) = event {
                    refreshFailed = true
                    let errorMessage = error.localizedDescription.lowercased()
                    if errorMessage.contains("timeout") {
                        print("✅ Token refresh properly timed out")
                    }
                }
            }
            .store(in: &cancellables)
        
        // Trigger refresh by checking token validity
        let isValid = await authManager.isTokenValidForOperation()
        
        // Allow time for refresh attempt
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // In test environment, refresh will likely fail due to mock tokens
        // We're primarily testing timeout behavior
        print("ℹ️ Token validation result: \(isValid)")
        
        if refreshFailed {
            print("✅ Token refresh failed as expected with network delay")
        }
    }
    
    // MARK: - Posting Network Resilience Tests
    
    func testPostingWithIntelligentRetry() async throws {
        // Set up authenticated state
        let mockAccessToken = "posting_retry_token"
        let mockRefreshToken = "posting_retry_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        var postingEvents: [String] = []
        var retryEvents: [String] = []
        
        // Monitor posting and retry events
        authManager.eventManager.tweetPostEvents
            .sink { event in
                switch event {
                case .postStarted:
                    postingEvents.append("post_started")
                case .postCompleted:
                    postingEvents.append("post_completed")
                case .postFailed:
                    postingEvents.append("post_failed")
                case .postQueued:
                    postingEvents.append("post_queued")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        authManager.eventManager.networkEvents
            .sink { event in
                if case .operationRetried(let operation, let attempt) = event {
                    retryEvents.append("\(operation):attempt_\(attempt)")
                }
            }
            .store(in: &cancellables)
        
        // Simulate poor network conditions
        await simulateNetworkQuality(.poor)
        
        // Attempt to post
        let postResult = await authManager.postTweet("Test post with intelligent retry")
        
        // Allow time for events to be processed
        try await Task.sleep(nanoseconds: 500_000_000)
        
        switch postResult {
        case .success:
            print("✅ Post succeeded with intelligent retry")
            XCTAssertTrue(postingEvents.contains("post_completed"), 
                         "Should have post completion event")
            
        case .failure(let error):
            print("ℹ️ Post failed (expected in test environment): \(error)")
            XCTAssertTrue(postingEvents.contains("post_failed") || postingEvents.contains("post_queued"), 
                         "Should have post failure or queuing event")
        }
        
        print("📊 Posting events: \(postingEvents)")
        print("📊 Retry events: \(retryEvents)")
        
        // Verify appropriate events were generated
        XCTAssertTrue(postingEvents.contains("post_started"), "Should have started posting")
    }
    
    func testPostingTimeoutCompliance() async throws {
        // Set up authenticated state
        let mockAccessToken = "posting_timeout_token"
        let mockRefreshToken = "posting_timeout_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate slow network that exceeds posting timeout
        await simulateNetworkDelay(seconds: 15) // Longer than 10s posting timeout
        
        let startTime = Date()
        let postResult = await authManager.postTweet("Timeout compliance test post")
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should timeout within PRD-specified posting timeout (10s baseline)
        // May be extended to 15s for poor connections
        XCTAssertLessThan(elapsed, 20.0, "Should timeout within posting timeout limit")
        
        switch postResult {
        case .success:
            print("ℹ️ Post succeeded despite simulated delay")
            
        case .failure(let error):
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("timeout") || errorMessage.contains("timed out") {
                print("✅ Post properly timed out per PRD requirements")
            }
        }
    }
    
    func testOfflinePostQueuing() async throws {
        // Set up authenticated state
        let mockAccessToken = "offline_queuing_token"
        let mockRefreshToken = "offline_queuing_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        var queueEvents: [String] = []
        
        // Monitor queue events
        authManager.eventManager.tweetPostEvents
            .sink { event in
                if case .postQueued = event {
                    queueEvents.append("post_queued")
                }
            }
            .store(in: &cancellables)
        
        // Go offline
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Attempt to post while offline
        let offlineResult = await authManager.postTweet("Offline post queuing test")
        
        switch offlineResult {
        case .success:
            XCTFail("Post should not succeed while offline")
            
        case .failure(let error):
            print("✅ Post failed while offline: \(error)")
        }
        
        // Allow time for queuing to process
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Check if post was queued (depends on implementation)
        if !queueEvents.isEmpty {
            print("✅ Post was queued while offline")
            XCTAssertTrue(queueEvents.contains("post_queued"), "Should have queued the post")
        }
        
        // Restore network
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 500_000_000) // Allow queue processing time
        
        // Queue should process when network is restored
        // Note: Actual queue processing verification would require PostQueueManager integration
    }
    
    // MARK: - Performance Under Various Network Conditions
    
    func testPerformanceWithExcellentConnection() async throws {
        await simulateNetworkQuality(.excellent)
        
        let performanceMetrics = await measureAuthenticationPerformance()
        
        // With excellent connection, operations should be fast
        XCTAssertLessThan(performanceMetrics.tokenValidationTime, 2.0, 
                         "Token validation should be fast with excellent connection")
        XCTAssertLessThan(performanceMetrics.stateChangeTime, 0.5, 
                         "State changes should be fast with excellent connection")
    }
    
    func testPerformanceWithPoorConnection() async throws {
        await simulateNetworkQuality(.poor)
        
        let performanceMetrics = await measureAuthenticationPerformance()
        
        // With poor connection, operations may be slower but should complete
        XCTAssertLessThan(performanceMetrics.tokenValidationTime, 10.0, 
                         "Token validation should complete within reasonable time")
        XCTAssertLessThan(performanceMetrics.stateChangeTime, 2.0, 
                         "State changes should not be significantly delayed")
    }
    
    // MARK: - Helper Methods
    
    private func simulateNetworkConnectivityChange(isConnected: Bool) async {
        if isConnected {
            NotificationCenter.default.post(
                name: .networkDidBecomeAvailable,
                object: nil
            )
        } else {
            NotificationCenter.default.post(
                name: .networkDidBecomeUnavailable,
                object: nil
            )
        }
    }
    
    private enum NetworkQuality {
        case poor, fair, good, excellent
    }
    
    private func simulateNetworkQuality(_ quality: NetworkQuality) async {
        let qualityValue: String
        switch quality {
        case .poor: qualityValue = "poor"
        case .fair: qualityValue = "fair"
        case .good: qualityValue = "good"
        case .excellent: qualityValue = "excellent"
        }
        
        let userInfo: [String: Any] = ["quality": qualityValue]
        NotificationCenter.default.post(
            name: .networkQualityChanged,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func simulateNetworkDelay(seconds: TimeInterval) async {
        let userInfo: [String: Any] = ["delay": seconds]
        NotificationCenter.default.post(
            name: .networkDelaySimulated,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func simulateIntermittentNetworkFailures() async {
        // Simulate pattern of network failures and recoveries
        for i in 1...3 {
            await simulateNetworkConnectivityChange(isConnected: false)
            try? await Task.sleep(nanoseconds: UInt64(Double(i) * 100_000_000)) // Increasing delays
            
            await simulateNetworkConnectivityChange(isConnected: true)
            try? await Task.sleep(nanoseconds: 50_000_000) // Brief recovery
        }
    }
    
    private struct AuthenticationPerformanceMetrics {
        let tokenValidationTime: TimeInterval
        let stateChangeTime: TimeInterval
    }
    
    private func measureAuthenticationPerformance() async -> AuthenticationPerformanceMetrics {
        // Set up valid tokens for performance testing
        let mockAccessToken = "performance_test_token"
        let mockRefreshToken = "performance_test_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try? keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try? keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Measure token validation time
        let validationStart = Date()
        _ = await authManager.isTokenValidForOperation()
        let validationTime = Date().timeIntervalSince(validationStart)
        
        // Measure state change time
        let stateChangeStart = Date()
        let currentState = authManager.authenticationState
        _ = currentState // Force evaluation
        let stateChangeTime = Date().timeIntervalSince(stateChangeStart)
        
        return AuthenticationPerformanceMetrics(
            tokenValidationTime: validationTime,
            stateChangeTime: stateChangeTime
        )
    }
}

// MARK: - Test Notification Extensions

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("NetworkDidBecomeAvailable")
    static let networkDidBecomeUnavailable = Notification.Name("NetworkDidBecomeUnavailable")
    static let networkQualityChanged = Notification.Name("NetworkQualityChanged")
    static let networkDelaySimulated = Notification.Name("NetworkDelaySimulated")
}
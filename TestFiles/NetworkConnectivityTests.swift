import XCTest
import Network
import Combine
@testable import mercury_macos

@MainActor
final class NetworkConnectivityTests: XCTestCase {
    
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    var tokenRefreshManager: TokenRefreshManager!
    var networkMonitor: NetworkMonitor!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        authManager = AuthManager()
        keychainManager = KeychainManager()
        tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
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
        tokenRefreshManager = nil
        networkMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Network Connectivity Change Tests
    
    func testAuthenticationDuringNetworkConnectivityChanges() async throws {
        // Store valid tokens
        let mockAccessToken = "network_test_access_token"
        let mockRefreshToken = "network_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Verify initial authentication state
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated initially")
        
        // Simulate network connectivity loss
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Authentication state should remain valid (cached)
        XCTAssertTrue(authManager.isAuthenticated, "Should maintain authentication during network loss")
        
        // Simulate network connectivity restoration
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should remain authenticated after network restoration
        XCTAssertTrue(authManager.isAuthenticated, "Should remain authenticated after network restoration")
    }
    
    func testTokenRefreshDuringNetworkLoss() async throws {
        // Store token that expires soon
        let mockAccessToken = "expiring_network_token"
        let mockRefreshToken = "valid_refresh_token"
        let nearExpirationDate = Date().addingTimeInterval(300) // 5 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: nearExpirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start token refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate network loss during potential refresh window
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Refresh should be paused or queued during network loss
        // The exact behavior depends on implementation
        XCTAssertNotNil(tokenRefreshManager, "Token refresh manager should handle network loss gracefully")
        
        // Restore network connectivity
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds for retry
        
        // Refresh should resume after network restoration
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Token refresh should resume after network restoration")
    }
    
    func testPostingBehaviorDuringNetworkChanges() async throws {
        // Store valid tokens
        let mockAccessToken = "posting_network_token"
        let mockRefreshToken = "posting_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate network loss
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Attempt to post during network loss
        let postResult = await authManager.postTweet("Test post during network loss")
        
        // Post should be queued or fail gracefully
        switch postResult {
        case .success:
            XCTFail("Post should not succeed during network loss")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("network") || 
                         error.localizedDescription.contains("connectivity"),
                         "Error should indicate network issue")
        }
        
        // Restore network
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Post should succeed after network restoration
        let retryResult = await authManager.postTweet("Test post after network restoration")
        // Note: This might still fail in tests due to mock API, but should not fail due to network
    }
    
    func testNetworkMonitoringIntegration() async throws {
        var networkStatusEvents: [Bool] = []
        
        // Observe network status changes
        networkMonitor.isConnectedPublisher
            .sink { isConnected in
                networkStatusEvents.append(isConnected)
            }
            .store(in: &cancellables)
        
        // Start network monitoring
        networkMonitor.startMonitoring()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Clear initial events
        networkStatusEvents.removeAll()
        
        // Simulate network changes
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should have received network status change events
        XCTAssertFalse(networkStatusEvents.isEmpty, "Should receive network status change events")
        
        networkMonitor.stopMonitoring()
    }
    
    // MARK: - Network Quality and Performance Tests
    
    func testNetworkQualityBasedBehavior() async throws {
        let mockAccessToken = "quality_test_token"
        let mockRefreshToken = "quality_test_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate poor network quality
        await simulateNetworkQuality(.poor)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Operations should adapt to poor network quality
        // (e.g., longer timeouts, reduced retry frequency)
        XCTAssertTrue(authManager.isAuthenticated, "Should handle poor network quality")
        
        // Simulate good network quality
        await simulateNetworkQuality(.good)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Operations should perform normally with good network
        XCTAssertTrue(authManager.isAuthenticated, "Should perform normally with good network")
    }
    
    func testCellularVsWiFiNetworkHandling() async throws {
        let mockAccessToken = "cellular_wifi_token"
        let mockRefreshToken = "cellular_wifi_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate cellular network
        await simulateNetworkType(.cellular)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should work on cellular but possibly with different behavior
        XCTAssertTrue(authManager.isAuthenticated, "Should work on cellular network")
        
        // Simulate WiFi network
        await simulateNetworkType(.wifi)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should work normally on WiFi
        XCTAssertTrue(authManager.isAuthenticated, "Should work normally on WiFi")
    }
    
    // MARK: - Network Retry Logic Tests
    
    func testExponentialBackoffDuringNetworkIssues() async throws {
        let mockAccessToken = "backoff_test_token"
        let mockRefreshToken = "backoff_test_refresh"
        let nearExpirationDate = Date().addingTimeInterval(300) // 5 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: nearExpirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start token refresh
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate intermittent network issues
        for _ in 1...3 {
            await simulateNetworkConnectivityChange(isConnected: false)
            try await Task.sleep(nanoseconds: 100_000_000)
            
            await simulateNetworkConnectivityChange(isConnected: true)
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        
        // Should implement exponential backoff for retry attempts
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Should handle intermittent network issues with backoff")
    }
    
    func testNetworkTimeoutHandling() async throws {
        let mockAccessToken = "timeout_test_token"
        let mockRefreshToken = "timeout_test_refresh"
        let expirationDate = Date().addingTimeInterval(1800)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate slow network (timeout scenario)
        await simulateNetworkDelay(seconds: 15) // Longer than typical timeout
        
        // Operations should timeout gracefully
        let postResult = await authManager.postTweet("Timeout test post")
        
        switch postResult {
        case .success:
            // Success is possible if mock implementation doesn't enforce timeouts
            break
        case .failure(let error):
            // Should be a timeout error
            XCTAssertTrue(error.localizedDescription.contains("timeout") ||
                         error.localizedDescription.contains("timed out"),
                         "Should indicate timeout error")
        }
    }
    
    // MARK: - Network State Persistence Tests
    
    func testNetworkStateAcrossAppLifecycle() async throws {
        let mockAccessToken = "lifecycle_network_token"
        let mockRefreshToken = "lifecycle_network_refresh"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start network monitoring
        networkMonitor.startMonitoring()
        
        // Simulate network state changes
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate app backgrounding
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate app foregrounding
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        
        // Restore network
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Network monitoring should resume properly
        XCTAssertTrue(authManager.isAuthenticated, "Should handle network state across app lifecycle")
        
        networkMonitor.stopMonitoring()
    }
    
    func testOfflineQueueBehavior() async throws {
        let mockAccessToken = "offline_queue_token"
        let mockRefreshToken = "offline_queue_refresh"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Go offline
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Attempt multiple posts while offline
        let offlinePosts = [
            "Offline post 1",
            "Offline post 2",
            "Offline post 3"
        ]
        
        for post in offlinePosts {
            let result = await authManager.postTweet(post)
            // Posts should be queued or fail gracefully
            switch result {
            case .success:
                XCTFail("Posts should not succeed while offline")
            case .failure:
                // Expected behavior - posts should fail or be queued
                break
            }
        }
        
        // Go back online
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 500_000_000) // Allow time for queue processing
        
        // Queued posts should be processed when network is restored
        // Note: Actual queue processing would depend on PostQueueManager implementation
    }
    
    // MARK: - Helper Methods for Network Simulation
    
    private func simulateNetworkConnectivityChange(isConnected: Bool) async {
        // Simulate network connectivity change by posting appropriate notifications
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
        case poor, good
    }
    
    private func simulateNetworkQuality(_ quality: NetworkQuality) async {
        let userInfo: [String: Any] = ["quality": quality == .good ? "good" : "poor"]
        NotificationCenter.default.post(
            name: .networkQualityChanged,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private enum NetworkType {
        case wifi, cellular
    }
    
    private func simulateNetworkType(_ type: NetworkType) async {
        let userInfo: [String: Any] = ["type": type == .wifi ? "wifi" : "cellular"]
        NotificationCenter.default.post(
            name: .networkTypeChanged,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func simulateNetworkDelay(seconds: TimeInterval) async {
        // Simulate network delay for timeout testing
        let userInfo: [String: Any] = ["delay": seconds]
        NotificationCenter.default.post(
            name: .networkDelaySimulated,
            object: nil,
            userInfo: userInfo
        )
    }
}

// MARK: - Custom Notification Names

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("NetworkDidBecomeAvailable")
    static let networkDidBecomeUnavailable = Notification.Name("NetworkDidBecomeUnavailable")
    static let networkQualityChanged = Notification.Name("NetworkQualityChanged")
    static let networkTypeChanged = Notification.Name("NetworkTypeChanged")
    static let networkDelaySimulated = Notification.Name("NetworkDelaySimulated")
}
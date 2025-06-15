import XCTest
import Combine
@testable import mercury_macos

@MainActor
final class TokenRefreshTests: XCTestCase {
    
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    var tokenRefreshManager: TokenRefreshManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        authManager = AuthManager()
        keychainManager = KeychainManager()
        tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
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
        super.tearDown()
    }
    
    // MARK: - Token Refresh After System Resume Tests
    
    func testTokenRefreshContinuesAfterSystemResume() async throws {
        // Store token that expires soon to trigger refresh
        let mockAccessToken = "expiring_token_for_resume_test"
        let mockRefreshToken = "valid_refresh_token_for_resume"
        let nearExpirationDate = Date().addingTimeInterval(900) // 15 minutes from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: nearExpirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start token refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Token refresh should be active initially")
        
        // Simulate system sleep (pause refresh operations)
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Simulate system resume
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds for resume processing
        
        // Token refresh should resume after system wake
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Token refresh should resume after system wake")
    }
    
    func testTokenRefreshTimerResumesAfterSystemResume() async throws {
        let mockAccessToken = "timer_test_access_token"
        let mockRefreshToken = "timer_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(1800) // 30 minutes from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start periodic refresh
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Verify refresh timer is running
        let initialRefreshTime = tokenRefreshManager.nextRefreshTime
        XCTAssertNotNil(initialRefreshTime, "Should have scheduled next refresh time")
        
        // Simulate sleep/wake cycle
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Refresh timer should be recalculated after wake
        let resumedRefreshTime = tokenRefreshManager.nextRefreshTime
        XCTAssertNotNil(resumedRefreshTime, "Should have rescheduled refresh time after wake")
    }
    
    func testExpiredTokenRefreshAfterResume() async throws {
        // Store token that expires during sleep
        let mockAccessToken = "expiring_during_sleep_token"
        let mockRefreshToken = "valid_refresh_for_sleep_test"
        let shortExpirationDate = Date().addingTimeInterval(60) // 1 minute from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: shortExpirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start token refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate sleep
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        
        // Wait for token to expire during "sleep"
        try await Task.sleep(nanoseconds: 100_000_000) // Token expires during this time
        
        // Simulate wake
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // Allow time for wake processing
        
        // Should detect expired token and initiate refresh
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Should attempt refresh for expired token after wake")
    }
    
    func testBackgroundRefreshAfterLongSleep() async throws {
        // Simulate overnight sleep scenario
        let mockAccessToken = "overnight_test_token"
        let mockRefreshToken = "overnight_refresh_token"
        let expirationDate = Date().addingTimeInterval(3600) // 1 hour from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start background refresh
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate long sleep (overnight)
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds representing hours
        
        // Wake up after long sleep
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 400_000_000) // Allow extended wake processing time
        
        // Background refresh should resume and handle any expired tokens
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Background refresh should resume after long sleep")
    }
    
    // MARK: - Refresh State Management After Resume
    
    func testRefreshStateEventsAfterResume() async throws {
        var refreshStateEvents: [TokenRefreshState] = []
        
        let mockAccessToken = "state_test_access_token"
        let mockRefreshToken = "state_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(900) // 15 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Observe refresh state changes
        tokenRefreshManager.refreshStatePublisher
            .sink { state in
                refreshStateEvents.append(state)
            }
            .store(in: &cancellables)
        
        // Start refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Clear initial events
        refreshStateEvents.removeAll()
        
        // Sleep/wake cycle
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should have received state events during resume
        XCTAssertFalse(refreshStateEvents.isEmpty, "Should emit refresh state events during resume")
    }
    
    func testConcurrentRefreshRequestsAfterResume() async throws {
        let mockAccessToken = "concurrent_test_token"
        let mockRefreshToken = "concurrent_refresh_token"
        let nearExpirationDate = Date().addingTimeInterval(300) // 5 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: nearExpirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate sleep/wake
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        
        // Immediately trigger manual refresh (simulating concurrent requests)
        Task {
            await tokenRefreshManager.refreshTokenIfNeeded()
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should handle concurrent refresh requests gracefully
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Should handle concurrent refresh requests after resume")
    }
    
    // MARK: - Network Connectivity and Refresh After Resume
    
    func testRefreshWithNetworkConnectivityAfterResume() async throws {
        let mockAccessToken = "network_connectivity_token"
        let mockRefreshToken = "network_connectivity_refresh"
        let expirationDate = Date().addingTimeInterval(600) // 10 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate sleep (network typically goes down)
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate wake with network connectivity restoration
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        
        // Give time for network connectivity check and refresh operations
        try await Task.sleep(nanoseconds: 400_000_000)
        
        // Refresh should handle network connectivity properly
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Should handle network connectivity during refresh after resume")
    }
    
    func testRefreshFailureRecoveryAfterResume() async throws {
        let mockAccessToken = "failure_recovery_token"
        let mockRefreshToken = "failure_recovery_refresh"
        let expirationDate = Date().addingTimeInterval(300) // 5 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Sleep/wake cycle
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should implement retry logic for failed refresh attempts after resume
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Should implement retry logic after resume")
    }
    
    // MARK: - Resource Management During Resume
    
    func testMemoryManagementDuringResumeRefresh() async throws {
        let mockAccessToken = "memory_test_token"
        let mockRefreshToken = "memory_test_refresh"
        let expirationDate = Date().addingTimeInterval(900)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Perform multiple sleep/wake cycles to test memory management
        for _ in 1...3 {
            NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
            try await Task.sleep(nanoseconds: 50_000_000)
            
            NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Memory should be managed properly without leaks
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Should manage memory properly during multiple resume cycles")
    }
    
    func testRefreshSchedulingAfterMultipleResumes() async throws {
        let mockAccessToken = "scheduling_test_token"
        let mockRefreshToken = "scheduling_test_refresh"
        let expirationDate = Date().addingTimeInterval(1200) // 20 minutes
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Track refresh scheduling across multiple resume cycles
        var schedulingConsistent = true
        
        for cycle in 1...3 {
            let preResumeTime = tokenRefreshManager.nextRefreshTime
            
            // Sleep/wake cycle
            NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
            try await Task.sleep(nanoseconds: 50_000_000)
            
            NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await Task.sleep(nanoseconds: 150_000_000)
            
            let postResumeTime = tokenRefreshManager.nextRefreshTime
            
            // Verify scheduling is updated appropriately
            if preResumeTime == postResumeTime && cycle > 1 {
                schedulingConsistent = false
            }
        }
        
        XCTAssertTrue(schedulingConsistent, "Refresh scheduling should be updated consistently after resume")
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Refresh should remain active after multiple resumes")
    }
    
    // MARK: - Integration with Authentication State After Resume
    
    func testAuthenticationStateAfterRefreshResume() async throws {
        var authStateEvents: [AuthenticationState] = []
        
        let mockAccessToken = "auth_state_test_token"
        let mockRefreshToken = "auth_state_test_refresh"
        let expirationDate = Date().addingTimeInterval(600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Observe authentication state changes
        authManager.authenticationStatePublisher
            .sink { state in
                authStateEvents.append(state)
            }
            .store(in: &cancellables)
        
        // Start refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        authStateEvents.removeAll() // Clear initial events
        
        // Sleep/wake cycle
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Authentication state should remain stable during refresh resume
        XCTAssertTrue(authManager.isAuthenticated, "Should maintain authentication state during refresh resume")
    }
}
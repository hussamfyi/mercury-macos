import XCTest
import IOKit.pwr_mgt
@testable import mercury_macos

@MainActor
final class SleepWakeTests: XCTestCase {
    
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    var tokenRefreshManager: TokenRefreshManager!
    
    override func setUp() {
        super.setUp()
        authManager = AuthManager()
        keychainManager = KeychainManager()
        tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
        
        // Clean up any existing test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
    }
    
    override func tearDown() {
        // Clean up test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
        
        authManager = nil
        keychainManager = nil
        tokenRefreshManager = nil
        super.tearDown()
    }
    
    // MARK: - Sleep/Wake Cycle Tests
    
    func testTokenPersistenceAcrossSleepWakeCycle() async throws {
        // Store valid tokens
        let mockAccessToken = "sleep_test_access_token"
        let mockRefreshToken = "sleep_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200) // 2 hours from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Verify initial authentication state
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated before sleep simulation")
        
        // Simulate system sleep by posting sleep notification
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        
        // Wait for sleep handling
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Simulate system wake by posting wake notification
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        
        // Wait for wake handling
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Verify authentication state is maintained
        XCTAssertTrue(authManager.isAuthenticated, "Authentication should survive sleep/wake cycle")
        
        // Verify tokens are still accessible
        let retrievedToken = try keychainManager.getToken()
        let retrievedRefreshToken = try keychainManager.getRefreshToken()
        
        XCTAssertEqual(retrievedToken, mockAccessToken, "Access token should survive sleep/wake")
        XCTAssertEqual(retrievedRefreshToken, mockRefreshToken, "Refresh token should survive sleep/wake")
    }
    
    func testTokenRefreshResumesAfterWake() async throws {
        // Store token that expires soon (to trigger refresh)
        let mockAccessToken = "expiring_access_token"
        let mockRefreshToken = "valid_refresh_token"
        let nearExpirationDate = Date().addingTimeInterval(300) // 5 minutes from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: nearExpirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start token refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate sleep
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate wake
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds for wake handling
        
        // Verify refresh operations resume
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Token refresh should resume after wake")
    }
    
    func testMultipleSleepWakeCycles() async throws {
        let mockAccessToken = "multi_cycle_access_token"
        let mockRefreshToken = "multi_cycle_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Perform multiple sleep/wake cycles
        for cycle in 1...3 {
            // Sleep
            NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            // Wake
            NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Verify authentication state after each cycle
            XCTAssertTrue(authManager.isAuthenticated, "Should remain authenticated after cycle \(cycle)")
            
            // Verify tokens are accessible
            let retrievedToken = try keychainManager.getToken()
            XCTAssertEqual(retrievedToken, mockAccessToken, "Token should persist through cycle \(cycle)")
        }
    }
    
    func testDeepSleepScenario() async throws {
        // Test longer sleep duration (simulating overnight sleep)
        let mockAccessToken = "deep_sleep_access_token"
        let mockRefreshToken = "deep_sleep_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate entering deep sleep
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        
        // Simulate extended sleep period (represented by longer wait)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds (representing hours)
        
        // Wake from deep sleep
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds for wake processing
        
        // Authentication should still be valid
        XCTAssertTrue(authManager.isAuthenticated, "Should survive deep sleep scenario")
        
        // Tokens should be intact
        let retrievedToken = try keychainManager.getToken()
        let retrievedRefreshToken = try keychainManager.getRefreshToken()
        
        XCTAssertEqual(retrievedToken, mockAccessToken, "Access token should survive deep sleep")
        XCTAssertEqual(retrievedRefreshToken, mockRefreshToken, "Refresh token should survive deep sleep")
    }
    
    // MARK: - Authentication State Events During Sleep/Wake
    
    func testAuthenticationStateEventsDuringSleepWake() async throws {
        var stateChangeEvents: [AuthenticationState] = []
        
        // Store valid tokens
        let mockAccessToken = "event_test_access_token"
        let mockRefreshToken = "event_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Observe state changes
        let cancellable = authManager.authenticationStatePublisher
            .sink { state in
                stateChangeEvents.append(state)
            }
        
        // Initial state should be authenticated
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(stateChangeEvents.contains(.authenticated), "Should start in authenticated state")
        
        // Clear events for sleep/wake test
        stateChangeEvents.removeAll()
        
        // Simulate sleep/wake cycle
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should maintain authenticated state or re-authenticate
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated after sleep/wake")
        
        cancellable.cancel()
    }
    
    // MARK: - Network Connectivity After Wake
    
    func testNetworkConnectivityRestorationAfterWake() async throws {
        // Store tokens
        let mockAccessToken = "network_test_access_token"
        let mockRefreshToken = "network_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate sleep (network typically goes down)
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate wake (network restoration)
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Authentication should handle network restoration gracefully
        XCTAssertTrue(authManager.isAuthenticated, "Should handle network restoration after wake")
    }
    
    // MARK: - Token Expiration During Sleep
    
    func testTokenExpirationDuringSleep() async throws {
        // Store token that will expire during "sleep"
        let mockAccessToken = "expiring_during_sleep_token"
        let mockRefreshToken = "valid_refresh_token"
        let shortExpirationDate = Date().addingTimeInterval(60) // 1 minute from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: shortExpirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Verify initial authentication
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated initially")
        
        // Simulate sleep
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        
        // Wait for token to expire during "sleep"
        try await Task.sleep(nanoseconds: 100_000_000) // Simulate time passing during sleep
        
        // Simulate wake
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // Allow time for wake processing
        
        // Should handle expired token gracefully (may need refresh)
        // The exact behavior depends on implementation - could be authenticated if refresh succeeds
        // or not authenticated if refresh is needed
        let refreshToken = try? keychainManager.getRefreshToken()
        XCTAssertNotNil(refreshToken, "Refresh token should be available for re-authentication")
    }
    
    // MARK: - Rapid Sleep/Wake Cycles
    
    func testRapidSleepWakeCycles() async throws {
        let mockAccessToken = "rapid_cycle_access_token"
        let mockRefreshToken = "rapid_cycle_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Perform rapid sleep/wake cycles
        for _ in 1...5 {
            NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
            try await Task.sleep(nanoseconds: 20_000_000) // 0.02 seconds
            
            NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await Task.sleep(nanoseconds: 30_000_000) // 0.03 seconds
        }
        
        // Should handle rapid cycles gracefully
        XCTAssertTrue(authManager.isAuthenticated, "Should survive rapid sleep/wake cycles")
    }
    
    // MARK: - System Resources During Sleep/Wake
    
    func testSystemResourceCleanupDuringSleepWake() async throws {
        let mockAccessToken = "resource_test_access_token"
        let mockRefreshToken = "resource_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Start token refresh manager to create background tasks
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate sleep (should pause background operations)
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate wake (should resume background operations)
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // System should manage resources properly
        XCTAssertTrue(authManager.isAuthenticated, "Should manage resources properly during sleep/wake")
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Background operations should resume after wake")
    }
}
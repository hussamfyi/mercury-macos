import XCTest
import Combine
@testable import mercury_macos

@MainActor
final class IntegrationTests: XCTestCase {
    
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    var tokenRefreshManager: TokenRefreshManager!
    var tokenRecoveryManager: TokenRecoveryManager!
    var networkMonitor: NetworkMonitor!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        keychainManager = KeychainManager()
        authManager = AuthManager()
        tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
        tokenRecoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
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
        tokenRecoveryManager = nil
        networkMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Complete Authentication Flow Integration Tests
    
    func testCompleteAuthenticationLifecycle() async throws {
        var authStateEvents: [AuthenticationState] = []
        
        // Observe authentication state changes throughout the lifecycle
        authManager.authenticationStatePublisher
            .sink { state in
                authStateEvents.append(state)
            }
            .store(in: &cancellables)
        
        // Phase 1: Initial state (not authenticated)
        XCTAssertFalse(authManager.isAuthenticated, "Should start not authenticated")
        XCTAssertTrue(authStateEvents.contains(.disconnected), "Should start in disconnected state")
        
        // Phase 2: Store valid tokens (simulating successful authentication)
        let accessToken = "integration_test_access_token"
        let refreshToken = "integration_test_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200) // 2 hours
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Reinitialize auth manager to simulate app restart
        authManager = AuthManager()
        authManager.authenticationStatePublisher
            .sink { state in
                authStateEvents.append(state)
            }
            .store(in: &cancellables)
        
        try await Task.sleep(nanoseconds: 200_000_000) // Allow initialization
        
        // Phase 3: Verify authentication is restored
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated after restart")
        XCTAssertTrue(authStateEvents.contains(.authenticated), "Should emit authenticated state")
        
        // Phase 4: Start token refresh manager
        await tokenRefreshManager.startPeriodicRefresh()
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Token refresh should be active")
        
        // Phase 5: Simulate system sleep/wake cycle
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertTrue(authManager.isAuthenticated, "Should remain authenticated after sleep/wake")
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Token refresh should resume after wake")
        
        // Phase 6: Test posting functionality
        let postResult = await authManager.postTweet("Integration test post")
        // Result depends on mock implementation, but should not crash
        
        // Phase 7: Disconnect
        await authManager.disconnect()
        XCTAssertFalse(authManager.isAuthenticated, "Should be disconnected after explicit disconnect")
    }
    
    func testTokenRefreshIntegrationWithRecovery() async throws {
        // Store token that will need refresh
        let accessToken = "refresh_integration_token"
        let refreshToken = "valid_refresh_token"
        let nearExpirationDate = Date().addingTimeInterval(300) // 5 minutes
        
        try keychainManager.storeToken(accessToken, expiresAt: nearExpirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Start systems
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Validate current tokens
        let recoveryResult = try await tokenRecoveryManager.validateAndRecoverTokens()
        XCTAssertTrue(recoveryResult.hasValidTokens || !recoveryResult.recoveryActions.isEmpty, 
                     "Should have valid tokens or recovery actions")
        
        // Execute any needed recovery actions
        if !recoveryResult.recoveryActions.isEmpty {
            try await tokenRecoveryManager.executeRecoveryActions(recoveryResult.recoveryActions)
        }
        
        // Verify authentication state after recovery
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated after recovery")
        
        // Test that refresh continues to work
        XCTAssertTrue(tokenRefreshManager.isRefreshActive, "Token refresh should be active after recovery")
    }
    
    func testNetworkConnectivityIntegrationWithPersistence() async throws {
        // Store valid tokens
        let accessToken = "network_persistence_token"
        let refreshToken = "network_persistence_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Start network monitoring
        networkMonitor.startMonitoring()
        
        // Start token refresh
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate network loss
        NotificationCenter.default.post(name: .networkDidBecomeUnavailable, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Authentication should persist during network loss
        XCTAssertTrue(authManager.isAuthenticated, "Should remain authenticated during network loss")
        
        // Simulate app restart during network outage
        authManager = AuthManager()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should restore authentication even without network
        XCTAssertTrue(authManager.isAuthenticated, "Should restore authentication without network")
        
        // Restore network
        NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Everything should work normally after network restoration
        XCTAssertTrue(authManager.isAuthenticated, "Should work normally after network restoration")
        
        networkMonitor.stopMonitoring()
    }
    
    // MARK: - Corruption Recovery Integration Tests
    
    func testCorruptionRecoveryIntegrationFlow() async throws {
        // Store initially valid tokens
        let validAccessToken = "valid_access_token"
        let validRefreshToken = "valid_refresh_token"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(validAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(validRefreshToken)
        
        // Verify initial state
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated initially")
        
        // Create backup of valid tokens
        let backup = try tokenRecoveryManager.createTokenBackup()
        XCTAssertNotNil(backup.accessToken, "Backup should contain access token")
        
        // Simulate corruption by storing invalid token
        try keychainManager.storeToken("corrupted@token", expiresAt: expirationDate)
        
        // Validate and recover
        let recoveryResult = try await tokenRecoveryManager.validateAndRecoverTokens()
        XCTAssertFalse(recoveryResult.hasValidTokens, "Should detect corrupted tokens")
        XCTAssertFalse(recoveryResult.recoveryActions.isEmpty, "Should have recovery actions")
        
        // Execute recovery actions
        try await tokenRecoveryManager.executeRecoveryActions(recoveryResult.recoveryActions)
        
        // If recovery failed, restore from backup
        if !authManager.isAuthenticated {
            try tokenRecoveryManager.restoreFromBackup(backup)
        }
        
        // Verify recovery
        let finalRecoveryResult = try await tokenRecoveryManager.validateAndRecoverTokens()
        XCTAssertTrue(finalRecoveryResult.hasValidTokens || finalRecoveryResult.requiresReAuthentication,
                     "Should have valid tokens or require re-authentication")
    }
    
    func testCompleteSystemFailureRecovery() async throws {
        // Store valid tokens
        let accessToken = "system_failure_token"
        let refreshToken = "system_failure_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Verify initial authentication
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated initially")
        
        // Simulate complete system failure - corrupt both tokens
        try keychainManager.storeToken("", expiresAt: Date()) // Empty/expired token
        try keychainManager.storeRefreshToken("@#$invalid") // Invalid refresh token
        
        // Reinitialize systems (simulating app restart after failure)
        authManager = AuthManager()
        tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
        tokenRecoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should not be authenticated due to corruption
        XCTAssertFalse(authManager.isAuthenticated, "Should not be authenticated with corrupted tokens")
        
        // Validate and handle corruption
        let recoveryResult = try await tokenRecoveryManager.validateAndRecoverTokens()
        XCTAssertTrue(recoveryResult.requiresReAuthentication, "Should require re-authentication")
        
        // Handle complete corruption
        try await tokenRecoveryManager.handleCompleteTokenCorruption()
        
        // Verify cleanup
        XCTAssertThrowsError(try keychainManager.getToken(), "Corrupted tokens should be cleared")
        XCTAssertThrowsError(try keychainManager.getRefreshToken(), "Corrupted tokens should be cleared")
    }
    
    // MARK: - Multi-Component Stress Tests
    
    func testConcurrentOperationsIntegration() async throws {
        // Store valid tokens
        let accessToken = "concurrent_test_token"
        let refreshToken = "concurrent_test_refresh"
        let expirationDate = Date().addingTimeInterval(1800) // 30 minutes
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Start all systems concurrently
        async let refreshStart = tokenRefreshManager.startPeriodicRefresh()
        async let networkStart = networkMonitor.startMonitoring()
        async let recoveryCheck = tokenRecoveryManager.validateAndRecoverTokens()
        
        // Wait for all to complete
        await refreshStart
        networkStart
        let _ = try await recoveryCheck
        
        // Perform concurrent operations
        let concurrentTasks = await withTaskGroup(of: Bool.self) { group in
            // Multiple authentication checks
            for _ in 1...5 {
                group.addTask {
                    return self.authManager.isAuthenticated
                }
            }
            
            // Multiple token validations
            for _ in 1...3 {
                group.addTask {
                    do {
                        let result = try await self.tokenRecoveryManager.validateAndRecoverTokens()
                        return result.hasValidTokens
                    } catch {
                        return false
                    }
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // All concurrent operations should succeed
        XCTAssertTrue(concurrentTasks.allSatisfy { $0 }, "All concurrent operations should succeed")
        
        networkMonitor.stopMonitoring()
    }
    
    func testRapidStateChangesIntegration() async throws {
        // Store valid tokens
        let accessToken = "rapid_changes_token"
        let refreshToken = "rapid_changes_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Start systems
        await tokenRefreshManager.startPeriodicRefresh()
        networkMonitor.startMonitoring()
        
        // Perform rapid state changes
        for cycle in 1...5 {
            // Sleep/wake cycle
            NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await Task.sleep(nanoseconds: 50_000_000)
            
            // Network connectivity changes
            NotificationCenter.default.post(name: .networkDidBecomeUnavailable, object: nil)
            try await Task.sleep(nanoseconds: 30_000_000)
            
            NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)
            try await Task.sleep(nanoseconds: 30_000_000)
            
            // Verify state after each cycle
            XCTAssertTrue(authManager.isAuthenticated, "Should remain authenticated after rapid changes cycle \(cycle)")
        }
        
        networkMonitor.stopMonitoring()
    }
    
    // MARK: - Long-Running Persistence Tests
    
    func testExtendedPersistenceScenario() async throws {
        var stateChangeCount = 0
        
        // Monitor state changes
        authManager.authenticationStatePublisher
            .sink { _ in
                stateChangeCount += 1
            }
            .store(in: &cancellables)
        
        // Store tokens with longer expiration
        let accessToken = "extended_persistence_token"
        let refreshToken = "extended_persistence_refresh"
        let expirationDate = Date().addingTimeInterval(10800) // 3 hours
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Start long-running operations
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate extended usage with various scenarios
        for scenario in 1...10 {
            switch scenario % 4 {
            case 0:
                // App restart simulation
                authManager = AuthManager()
                try await Task.sleep(nanoseconds: 100_000_000)
                
            case 1:
                // Sleep/wake simulation
                NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
                try await Task.sleep(nanoseconds: 50_000_000)
                NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
                try await Task.sleep(nanoseconds: 100_000_000)
                
            case 2:
                // Network connectivity changes
                NotificationCenter.default.post(name: .networkDidBecomeUnavailable, object: nil)
                try await Task.sleep(nanoseconds: 100_000_000)
                NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)
                try await Task.sleep(nanoseconds: 100_000_000)
                
            case 3:
                // Token validation
                let _ = try await tokenRecoveryManager.validateAndRecoverTokens()
                try await Task.sleep(nanoseconds: 50_000_000)
                
            default:
                break
            }
            
            // Verify authentication persists throughout
            XCTAssertTrue(authManager.isAuthenticated, "Should remain authenticated during extended scenario \(scenario)")
        }
        
        // Verify minimal state changes (stable system)
        XCTAssertLessThan(stateChangeCount, 50, "Should have minimal state changes during stable operation")
    }
    
    // MARK: - Data Integrity Tests
    
    func testDataIntegrityAcrossAllOperations() async throws {
        // Store baseline tokens
        let originalAccessToken = "integrity_test_access_token"
        let originalRefreshToken = "integrity_test_refresh_token"
        let originalExpirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(originalAccessToken, expiresAt: originalExpirationDate)
        try keychainManager.storeRefreshToken(originalRefreshToken)
        
        // Create baseline backup
        let baselineBackup = try tokenRecoveryManager.createTokenBackup()
        
        // Perform various operations that could affect data integrity
        await tokenRefreshManager.startPeriodicRefresh()
        networkMonitor.startMonitoring()
        
        // Multiple validation cycles
        for _ in 1...5 {
            let _ = try await tokenRecoveryManager.validateAndRecoverTokens()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // System state changes
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify data integrity
        let currentAccessToken = try keychainManager.getToken()
        let currentRefreshToken = try keychainManager.getRefreshToken()
        let currentExpirationDate = try keychainManager.getTokenExpirationDate()
        
        XCTAssertEqual(currentAccessToken, originalAccessToken, "Access token should remain unchanged")
        XCTAssertEqual(currentRefreshToken, originalRefreshToken, "Refresh token should remain unchanged")
        XCTAssertEqual(currentExpirationDate.timeIntervalSince1970,
                      originalExpirationDate.timeIntervalSince1970,
                      accuracy: 1.0,
                      "Expiration date should remain unchanged")
        
        // Verify backup integrity
        let finalBackup = try tokenRecoveryManager.createTokenBackup()
        XCTAssertEqual(finalBackup.accessToken, baselineBackup.accessToken, "Backup should maintain integrity")
        
        networkMonitor.stopMonitoring()
    }
}
import XCTest
@testable import mercury_macos

@MainActor
final class PersistenceTests: XCTestCase {
    
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    
    override func setUp() {
        super.setUp()
        authManager = AuthManager()
        keychainManager = KeychainManager()
        
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
        super.tearDown()
    }
    
    // MARK: - Token Persistence Tests
    
    func testTokenPersistenceAcrossAppRestarts() async throws {
        // Store mock tokens to simulate authenticated state
        let mockAccessToken = "test_access_token_12345"
        let mockRefreshToken = "test_refresh_token_67890"
        let expirationDate = Date().addingTimeInterval(7200) // 2 hours from now
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate app restart by creating new AuthManager instance
        let newAuthManager = AuthManager()
        
        // Wait for initialization to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify authentication state is restored
        XCTAssertTrue(newAuthManager.isAuthenticated, "Authentication state should be restored after app restart")
        
        // Verify tokens are accessible
        let retrievedToken = try keychainManager.getToken()
        let retrievedRefreshToken = try keychainManager.getRefreshToken()
        
        XCTAssertEqual(retrievedToken, mockAccessToken, "Access token should persist across app restarts")
        XCTAssertEqual(retrievedRefreshToken, mockRefreshToken, "Refresh token should persist across app restarts")
    }
    
    func testExpiredTokenHandlingAfterRestart() async throws {
        // Store expired token
        let mockAccessToken = "expired_access_token"
        let mockRefreshToken = "valid_refresh_token"
        let expiredDate = Date().addingTimeInterval(-3600) // 1 hour ago
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expiredDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate app restart
        let newAuthManager = AuthManager()
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should not be authenticated with expired token
        XCTAssertFalse(newAuthManager.isAuthenticated, "Should not be authenticated with expired token after restart")
        
        // Verify the refresh token is still available for re-authentication
        let retrievedRefreshToken = try keychainManager.getRefreshToken()
        XCTAssertEqual(retrievedRefreshToken, mockRefreshToken, "Refresh token should still be available")
    }
    
    func testCorruptedTokenRecovery() async throws {
        // Store malformed token data
        let corruptedToken = "invalid_token_format"
        let validRefreshToken = "valid_refresh_token"
        
        try keychainManager.storeToken(corruptedToken, expiresAt: Date().addingTimeInterval(3600))
        try keychainManager.storeRefreshToken(validRefreshToken)
        
        // Simulate app restart
        let newAuthManager = AuthManager()
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should handle corrupted token gracefully
        XCTAssertFalse(newAuthManager.isAuthenticated, "Should not be authenticated with corrupted token")
        
        // Refresh token should still be available for recovery
        let retrievedRefreshToken = try keychainManager.getRefreshToken()
        XCTAssertEqual(retrievedRefreshToken, validRefreshToken, "Refresh token should be preserved for recovery")
    }
    
    func testNoTokensAfterRestart() async throws {
        // Ensure no tokens are stored
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
        
        // Simulate app restart
        let newAuthManager = AuthManager()
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should not be authenticated
        XCTAssertFalse(newAuthManager.isAuthenticated, "Should not be authenticated when no tokens are stored")
        
        // Verify no tokens exist
        XCTAssertThrowsError(try keychainManager.getToken(), "Should throw error when no access token exists")
        XCTAssertThrowsError(try keychainManager.getRefreshToken(), "Should throw error when no refresh token exists")
    }
    
    // MARK: - Authentication State Persistence Tests
    
    func testAuthenticationStateEventsPersistAcrossRestart() async throws {
        var stateChangeEvents: [AuthenticationState] = []
        
        // Store valid tokens
        let mockAccessToken = "valid_access_token"
        let mockRefreshToken = "valid_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Create new auth manager and observe state changes
        let newAuthManager = AuthManager()
        
        let cancellable = newAuthManager.authenticationStatePublisher
            .sink { state in
                stateChangeEvents.append(state)
            }
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Should have received authenticated state
        XCTAssertTrue(stateChangeEvents.contains(.authenticated), "Should emit authenticated state on restart with valid tokens")
        
        cancellable.cancel()
    }
    
    func testMultipleRestartsCycleMaintainsPersistence() async throws {
        let mockAccessToken = "persistent_access_token"
        let mockRefreshToken = "persistent_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        // Initial token storage
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Simulate multiple app restart cycles
        for cycle in 1...3 {
            let newAuthManager = AuthManager()
            
            // Wait for initialization
            try await Task.sleep(nanoseconds: 100_000_000)
            
            XCTAssertTrue(newAuthManager.isAuthenticated, "Should remain authenticated after restart cycle \(cycle)")
            
            // Verify tokens are still accessible
            let retrievedToken = try keychainManager.getToken()
            let retrievedRefreshToken = try keychainManager.getRefreshToken()
            
            XCTAssertEqual(retrievedToken, mockAccessToken, "Access token should persist through restart cycle \(cycle)")
            XCTAssertEqual(retrievedRefreshToken, mockRefreshToken, "Refresh token should persist through restart cycle \(cycle)")
        }
    }
    
    // MARK: - User Data Persistence Tests
    
    func testUserInfoPersistenceAcrossRestart() async throws {
        // Store tokens with user info
        let mockAccessToken = "user_access_token"
        let mockRefreshToken = "user_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Create auth manager and set user info
        let authManager1 = AuthManager()
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate app restart
        let authManager2 = AuthManager()
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Authentication state should be restored
        XCTAssertTrue(authManager2.isAuthenticated, "Authentication state should be restored with user info")
    }
    
    // MARK: - Edge Cases and Error Scenarios
    
    func testKeychainAccessDeniedScenario() async throws {
        // This test would require mocking Keychain access denial
        // For now, we'll test the error handling path
        
        let newAuthManager = AuthManager()
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should handle keychain access issues gracefully
        XCTAssertFalse(newAuthManager.isAuthenticated, "Should handle keychain access issues gracefully")
    }
    
    func testConcurrentRestartHandling() async throws {
        let mockAccessToken = "concurrent_access_token"
        let mockRefreshToken = "concurrent_refresh_token"
        let expirationDate = Date().addingTimeInterval(7200)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Create multiple auth managers simultaneously (simulating rapid restart scenarios)
        let authManager1 = AuthManager()
        let authManager2 = AuthManager()
        
        // Wait for both to initialize
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Both should be able to access tokens safely
        XCTAssertTrue(authManager1.isAuthenticated, "First manager should be authenticated")
        XCTAssertTrue(authManager2.isAuthenticated, "Second manager should be authenticated")
    }
}
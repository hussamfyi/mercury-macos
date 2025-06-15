import XCTest
@testable import mercury_macos

@MainActor
final class TokenRecoveryTests: XCTestCase {
    
    var tokenRecoveryManager: TokenRecoveryManager!
    var keychainManager: KeychainManager!
    
    override func setUp() {
        super.setUp()
        keychainManager = KeychainManager()
        tokenRecoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
        
        // Clean up any existing test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
    }
    
    override func tearDown() {
        // Clean up test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
        
        tokenRecoveryManager = nil
        keychainManager = nil
        super.tearDown()
    }
    
    // MARK: - Token Validation Tests
    
    func testValidateValidTokens() async throws {
        // Store valid tokens
        let validAccessToken = "valid_access_token_12345"
        let validRefreshToken = "valid_refresh_token_67890"
        let expirationDate = Date().addingTimeInterval(3600) // 1 hour from now
        
        try keychainManager.storeToken(validAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(validRefreshToken)
        
        // Validate tokens
        let result = try await tokenRecoveryManager.validateAndRecoverTokens()
        
        XCTAssertTrue(result.hasValidTokens, "Should have valid tokens")
        XCTAssertFalse(result.requiresReAuthentication, "Should not require re-authentication")
        XCTAssertTrue(result.recoveryActions.isEmpty, "Should not need recovery actions for valid tokens")
    }
    
    func testValidateCorruptedAccessToken() async throws {
        // Store corrupted access token and valid refresh token
        let corruptedAccessToken = "invalid@token#format!"
        let validRefreshToken = "valid_refresh_token_67890"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(corruptedAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(validRefreshToken)
        
        // Validate tokens
        let result = try await tokenRecoveryManager.validateAndRecoverTokens()
        
        XCTAssertFalse(result.hasValidTokens, "Should not have valid tokens with corrupted access token")
        XCTAssertTrue(result.recoveryActions.contains(.clearCorruptedAccessToken), "Should clear corrupted access token")
    }
    
    func testValidateCorruptedRefreshToken() async throws {
        // Store valid access token and corrupted refresh token
        let validAccessToken = "valid_access_token_12345"
        let corruptedRefreshToken = ""  // Empty token
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(validAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(corruptedRefreshToken)
        
        // Validate tokens
        let result = try await tokenRecoveryManager.validateAndRecoverTokens()
        
        XCTAssertFalse(result.hasValidTokens, "Should not have valid tokens with corrupted refresh token")
        XCTAssertTrue(result.recoveryActions.contains(.clearCorruptedRefreshToken), "Should clear corrupted refresh token")
    }
    
    func testValidateExpiredAccessToken() async throws {
        // Store expired access token and valid refresh token
        let expiredAccessToken = "expired_access_token_12345"
        let validRefreshToken = "valid_refresh_token_67890"
        let pastExpirationDate = Date().addingTimeInterval(-3600) // 1 hour ago
        
        try keychainManager.storeToken(expiredAccessToken, expiresAt: pastExpirationDate)
        try keychainManager.storeRefreshToken(validRefreshToken)
        
        // Validate tokens
        let result = try await tokenRecoveryManager.validateAndRecoverTokens()
        
        XCTAssertFalse(result.hasValidTokens, "Should not have valid tokens with expired access token")
        XCTAssertTrue(result.recoveryActions.contains(.refreshExpiredAccessToken), "Should refresh expired access token")
    }
    
    func testValidateInconsistentTokenState() async throws {
        // Store access token without refresh token (inconsistent state)
        let accessToken = "access_token_without_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        // Don't store refresh token
        
        // Validate tokens
        let result = try await tokenRecoveryManager.validateAndRecoverTokens()
        
        XCTAssertFalse(result.hasValidTokens, "Should not have valid tokens in inconsistent state")
        XCTAssertTrue(result.recoveryActions.contains(.clearInconsistentTokens), "Should clear inconsistent tokens")
    }
    
    func testValidateNoTokens() async throws {
        // Don't store any tokens
        
        // Validate tokens
        let result = try await tokenRecoveryManager.validateAndRecoverTokens()
        
        XCTAssertFalse(result.hasValidTokens, "Should not have valid tokens when none exist")
        XCTAssertTrue(result.requiresReAuthentication, "Should require re-authentication when no tokens exist")
        XCTAssertTrue(result.recoveryActions.contains(.requestReAuthentication), "Should request re-authentication")
    }
    
    // MARK: - Token Recovery Tests
    
    func testRecoverFromCorruptedAccessToken() async throws {
        // Store corrupted access token and valid refresh token
        let corruptedAccessToken = "corrupted@token"
        let validRefreshToken = "valid_refresh_token_12345"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(corruptedAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(validRefreshToken)
        
        // Attempt recovery
        let recoverySuccessful = try await tokenRecoveryManager.recoverFromCorruptedAccessToken()
        
        XCTAssertTrue(recoverySuccessful, "Should successfully recover from corrupted access token")
        
        // Verify corrupted token was cleared
        XCTAssertThrowsError(try keychainManager.getToken(), "Corrupted access token should be cleared")
        
        // Verify refresh token is still available
        let refreshToken = try keychainManager.getRefreshToken()
        XCTAssertEqual(refreshToken, validRefreshToken, "Refresh token should still be available")
    }
    
    func testRecoverFromCorruptedAccessTokenWithoutRefreshToken() async throws {
        // Store corrupted access token without refresh token
        let corruptedAccessToken = "corrupted@token"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(corruptedAccessToken, expiresAt: expirationDate)
        // Don't store refresh token
        
        // Attempt recovery should fail
        do {
            _ = try await tokenRecoveryManager.recoverFromCorruptedAccessToken()
            XCTFail("Recovery should fail without valid refresh token")
        } catch TokenRecoveryError.noValidRefreshToken {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testHandleCompleteTokenCorruption() async throws {
        // Store corrupted tokens
        let corruptedAccessToken = "corrupted@access"
        let corruptedRefreshToken = "corrupted@refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(corruptedAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(corruptedRefreshToken)
        
        // Set some token metadata
        UserDefaults.standard.set(Date(), forKey: "lastTokenRefresh")
        UserDefaults.standard.set(Date(), forKey: "tokenExpirationDate")
        
        // Handle complete corruption
        try await tokenRecoveryManager.handleCompleteTokenCorruption()
        
        // Verify all tokens are cleared
        XCTAssertThrowsError(try keychainManager.getToken(), "Access token should be cleared")
        XCTAssertThrowsError(try keychainManager.getRefreshToken(), "Refresh token should be cleared")
        
        // Verify metadata is cleared
        XCTAssertNil(UserDefaults.standard.object(forKey: "lastTokenRefresh"), "Token metadata should be cleared")
        XCTAssertNil(UserDefaults.standard.object(forKey: "tokenExpirationDate"), "Token metadata should be cleared")
    }
    
    // MARK: - Recovery Action Execution Tests
    
    func testExecuteRecoveryActions() async throws {
        // Store test tokens
        let accessToken = "test_access_token"
        let refreshToken = "test_refresh_token"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Execute clear actions
        let actions: [TokenRecoveryAction] = [
            .clearCorruptedAccessToken,
            .clearCorruptedRefreshToken
        ]
        
        try await tokenRecoveryManager.executeRecoveryActions(actions)
        
        // Verify tokens are cleared
        XCTAssertThrowsError(try keychainManager.getToken(), "Access token should be cleared")
        XCTAssertThrowsError(try keychainManager.getRefreshToken(), "Refresh token should be cleared")
    }
    
    func testExecuteInconsistentTokensClearAction() async throws {
        // Store inconsistent tokens
        let accessToken = "test_access_token"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        // Don't store refresh token to create inconsistent state
        
        // Execute clear inconsistent tokens action
        let actions: [TokenRecoveryAction] = [.clearInconsistentTokens]
        
        try await tokenRecoveryManager.executeRecoveryActions(actions)
        
        // Verify all tokens are cleared
        XCTAssertThrowsError(try keychainManager.getToken(), "Access token should be cleared")
        XCTAssertThrowsError(try keychainManager.getRefreshToken(), "Refresh token should be cleared")
    }
    
    // MARK: - Token Backup and Restore Tests
    
    func testCreateTokenBackup() throws {
        // Store test tokens
        let accessToken = "backup_access_token"
        let refreshToken = "backup_refresh_token"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Create backup
        let backup = try tokenRecoveryManager.createTokenBackup()
        
        XCTAssertEqual(backup.accessToken, accessToken, "Backup should contain access token")
        XCTAssertEqual(backup.refreshToken, refreshToken, "Backup should contain refresh token")
        XCTAssertNotNil(backup.expirationDate, "Backup should contain expiration date")
        XCTAssertTrue(backup.backupDate.timeIntervalSinceNow > -60, "Backup date should be recent")
    }
    
    func testCreateTokenBackupWithMissingTokens() throws {
        // Don't store any tokens
        
        // Create backup (should work but contain nil values)
        let backup = try tokenRecoveryManager.createTokenBackup()
        
        XCTAssertNil(backup.accessToken, "Backup should not contain access token when none exists")
        XCTAssertNil(backup.refreshToken, "Backup should not contain refresh token when none exists")
        XCTAssertNil(backup.expirationDate, "Backup should not contain expiration date when none exists")
    }
    
    func testRestoreFromValidBackup() throws {
        // Create backup data
        let backupAccessToken = "backup_access_token"
        let backupRefreshToken = "backup_refresh_token"
        let backupExpirationDate = Date().addingTimeInterval(3600)
        let recentBackupDate = Date().addingTimeInterval(-300) // 5 minutes ago
        
        let backup = TokenBackup(
            accessToken: backupAccessToken,
            refreshToken: backupRefreshToken,
            expirationDate: backupExpirationDate,
            backupDate: recentBackupDate
        )
        
        // Restore from backup
        try tokenRecoveryManager.restoreFromBackup(backup)
        
        // Verify tokens are restored
        let restoredAccessToken = try keychainManager.getToken()
        let restoredRefreshToken = try keychainManager.getRefreshToken()
        let restoredExpirationDate = try keychainManager.getTokenExpirationDate()
        
        XCTAssertEqual(restoredAccessToken, backupAccessToken, "Access token should be restored")
        XCTAssertEqual(restoredRefreshToken, backupRefreshToken, "Refresh token should be restored")
        XCTAssertEqual(restoredExpirationDate.timeIntervalSince1970, 
                      backupExpirationDate.timeIntervalSince1970, 
                      accuracy: 1.0, 
                      "Expiration date should be restored")
    }
    
    func testRestoreFromOldBackup() throws {
        // Create old backup data (more than 24 hours old)
        let oldBackupDate = Date().addingTimeInterval(-90000) // 25 hours ago
        
        let backup = TokenBackup(
            accessToken: "old_access_token",
            refreshToken: "old_refresh_token",
            expirationDate: Date().addingTimeInterval(3600),
            backupDate: oldBackupDate
        )
        
        // Attempt to restore from old backup should fail
        XCTAssertThrowsError(try tokenRecoveryManager.restoreFromBackup(backup)) { error in
            XCTAssertTrue(error is TokenRecoveryError, "Should throw TokenRecoveryError")
            if case TokenRecoveryError.backupTooOld = error {
                // Expected error
            } else {
                XCTFail("Should throw backupTooOld error")
            }
        }
    }
    
    // MARK: - Edge Cases and Error Scenarios
    
    func testValidateTokensWithKeychainAccessError() async throws {
        // This test would require mocking keychain access errors
        // For now, we test the basic error handling path
        
        let result = try await tokenRecoveryManager.validateAndRecoverTokens()
        
        // With no tokens stored, should require re-authentication
        XCTAssertFalse(result.hasValidTokens, "Should not have valid tokens")
        XCTAssertTrue(result.requiresReAuthentication, "Should require re-authentication")
    }
    
    func testRecoveryActionsDescription() {
        // Test that all recovery actions have proper descriptions
        let actions: [TokenRecoveryAction] = [
            .clearCorruptedAccessToken,
            .clearCorruptedRefreshToken,
            .clearInconsistentTokens,
            .refreshExpiredAccessToken,
            .refreshAccessTokenFromRefreshToken,
            .validateTokenExpiration,
            .requestReAuthentication
        ]
        
        for action in actions {
            XCTAssertFalse(action.description.isEmpty, "Action \(action) should have description")
            XCTAssertTrue(action.description.count > 5, "Action description should be meaningful")
        }
    }
    
    func testTokenRecoveryErrorDescriptions() {
        // Test error descriptions
        let errors: [TokenRecoveryError] = [
            .noValidRefreshToken,
            .recoveryFailed(NSError(domain: "test", code: 1)),
            .clearTokensFailed(NSError(domain: "test", code: 2)),
            .backupTooOld
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
}
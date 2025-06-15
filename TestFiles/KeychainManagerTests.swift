import XCTest
import Foundation
import Security
@testable import mercury_macos

final class KeychainManagerTests: XCTestCase {
    
    private var keychainManager: KeychainManager!
    private let testAccessToken = "valid_access_token_aB3xY9mK7pQ2wN5tR8uI1oL6eH4vZ0cS9dF2gJ5kM8nP1qR4sT7vX0yA"
    private let testRefreshToken = "valid_refresh_token_xK8Pq2mN9vR7sT4wE6yU1iO5pH3jL0aC9bF8dG2kM7nV4xZ1qS6wE9tY"
    private let testUserInfo = AuthenticatedUser(
        id: "12345",
        username: "testuser",
        name: "Test User",
        profileImageUrl: "https://example.com/profile.jpg",
        followersCount: 100,
        followingCount: 50,
        tweetCount: 25,
        verified: false
    )
    
    override func setUpWithResult() throws {
        try super.setUpWithResult()
        keychainManager = KeychainManager()
        
        // Clean up any existing test data
        try await cleanupKeychain()
    }
    
    override func tearDownWithResult() throws {
        // Clean up test data
        try await cleanupKeychain()
        keychainManager = nil
        try super.tearDownWithResult()
    }
    
    private func cleanupKeychain() async throws {
        // Use non-throwing versions to avoid test failures during cleanup
        try? await keychainManager.clearAllTokens()
    }
    
    // MARK: - Access Token Tests
    
    func testStoreAndRetrieveAccessToken() async throws {
        // Store access token
        try await keychainManager.storeAccessToken(testAccessToken)
        
        // Retrieve access token
        let retrievedToken = try await keychainManager.getAccessToken()
        
        XCTAssertEqual(retrievedToken, testAccessToken, "Retrieved access token should match stored token")
    }
    
    func testStoreAccessTokenWithInvalidFormat() async throws {
        // Test with empty token
        do {
            try await keychainManager.storeAccessToken("")
            XCTFail("Should have thrown error for empty token")
        } catch KeychainError.invalidData {
            // Expected behavior
        }
        
        // Test with too short token
        do {
            try await keychainManager.storeAccessToken("short")
            XCTFail("Should have thrown error for short token")
        } catch KeychainError.invalidData {
            // Expected behavior
        }
        
        // Test with suspicious patterns
        do {
            try await keychainManager.storeAccessToken("test_token_with_test_pattern_12345678901234567890")
            XCTFail("Should have thrown error for token with test pattern")
        } catch KeychainError.invalidData {
            // Expected behavior
        }
    }
    
    func testUpdateAccessToken() async throws {
        // Store initial token
        try await keychainManager.storeAccessToken(testAccessToken)
        
        // Update with new token
        let newToken = "new_access_token_98765432109876543210987654321098765432109876543210"
        try await keychainManager.updateAccessToken(newToken)
        
        // Verify updated token
        let retrievedToken = try await keychainManager.getAccessToken()
        XCTAssertEqual(retrievedToken, newToken, "Updated token should be retrieved")
    }
    
    func testGetAccessTokenNotFound() async throws {
        // Try to get token when none exists
        do {
            _ = try await keychainManager.getAccessToken()
            XCTFail("Should have thrown itemNotFound error")
        } catch KeychainError.itemNotFound {
            // Expected behavior
        }
    }
    
    func testClearAccessToken() async throws {
        // Store and verify token exists
        try await keychainManager.storeAccessToken(testAccessToken)
        let _ = try await keychainManager.getAccessToken() // Should not throw
        
        // Clear token
        try await keychainManager.clearAccessToken()
        
        // Verify token is removed
        do {
            _ = try await keychainManager.getAccessToken()
            XCTFail("Should have thrown itemNotFound error after clearing")
        } catch KeychainError.itemNotFound {
            // Expected behavior
        }
    }
    
    // MARK: - Refresh Token Tests
    
    func testStoreAndRetrieveRefreshToken() async throws {
        // Store refresh token (encrypted)
        try await keychainManager.storeRefreshToken(testRefreshToken)
        
        // Retrieve and decrypt refresh token
        let retrievedToken = try await keychainManager.getRefreshToken()
        
        XCTAssertEqual(retrievedToken, testRefreshToken, "Retrieved refresh token should match stored token")
    }
    
    func testStoreRefreshTokenWithInvalidFormat() async throws {
        // Test with token that doesn't meet refresh token requirements
        do {
            try await keychainManager.storeRefreshToken("short_refresh_token")
            XCTFail("Should have thrown error for short refresh token")
        } catch KeychainError.invalidData {
            // Expected behavior
        }
    }
    
    func testUpdateRefreshToken() async throws {
        // Store initial token
        try await keychainManager.storeRefreshToken(testRefreshToken)
        
        // Update with new token
        let newToken = "new_refresh_token_987654321098765432109876543210987654321098765432109876543210"
        try await keychainManager.updateRefreshToken(newToken)
        
        // Verify updated token
        let retrievedToken = try await keychainManager.getRefreshToken()
        XCTAssertEqual(retrievedToken, newToken, "Updated refresh token should be retrieved")
    }
    
    func testClearRefreshToken() async throws {
        // Store and verify token exists
        try await keychainManager.storeRefreshToken(testRefreshToken)
        let _ = try await keychainManager.getRefreshToken() // Should not throw
        
        // Clear token
        try await keychainManager.clearRefreshToken()
        
        // Verify token is removed
        do {
            _ = try await keychainManager.getRefreshToken()
            XCTFail("Should have thrown itemNotFound error after clearing")
        } catch KeychainError.itemNotFound {
            // Expected behavior
        }
    }
    
    // MARK: - User Info Tests
    
    func testStoreAndRetrieveUserInfo() async throws {
        // Store user info
        try await keychainManager.storeUserInfo(testUserInfo)
        
        // Retrieve user info
        let retrievedUser = try await keychainManager.getUserInfo()
        
        XCTAssertEqual(retrievedUser.id, testUserInfo.id, "User ID should match")
        XCTAssertEqual(retrievedUser.username, testUserInfo.username, "Username should match")
        XCTAssertEqual(retrievedUser.name, testUserInfo.name, "Name should match")
        XCTAssertEqual(retrievedUser.profileImageUrl, testUserInfo.profileImageUrl, "Profile image URL should match")
    }
    
    func testStoreUserInfoWithInvalidData() async throws {
        // Test with invalid user info (empty ID)
        let invalidUser = AuthenticatedUser(id: "", username: "test", name: "Test")
        
        do {
            try await keychainManager.storeUserInfo(invalidUser)
            XCTFail("Should have thrown error for invalid user info")
        } catch KeychainError.invalidData {
            // Expected behavior
        }
    }
    
    func testClearUserInfo() async throws {
        // Store and verify user info exists
        try await keychainManager.storeUserInfo(testUserInfo)
        let _ = try await keychainManager.getUserInfo() // Should not throw
        
        // Clear user info
        try await keychainManager.clearUserInfo()
        
        // Verify user info is removed
        do {
            _ = try await keychainManager.getUserInfo()
            XCTFail("Should have thrown itemNotFound error after clearing")
        } catch KeychainError.itemNotFound {
            // Expected behavior
        }
    }
    
    // MARK: - Token Expiry Tests
    
    func testStoreAndRetrieveTokenExpiry() async throws {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        
        // Store token expiry
        try await keychainManager.storeTokenExpiry(futureDate)
        
        // Retrieve token expiry
        let retrievedExpiry = try await keychainManager.getTokenExpiry()
        
        // Compare with small tolerance for encoding/decoding time differences
        XCTAssertEqual(
            Int(retrievedExpiry.timeIntervalSince1970),
            Int(futureDate.timeIntervalSince1970),
            "Retrieved expiry should match stored expiry"
        )
    }
    
    func testStoreTokenExpiryWithInvalidDate() async throws {
        // Test with past date
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        
        do {
            try await keychainManager.storeTokenExpiry(pastDate)
            XCTFail("Should have thrown error for past expiry date")
        } catch KeychainError.invalidData {
            // Expected behavior
        }
        
        // Test with too far future date
        let tooFarFuture = Date().addingTimeInterval(365 * 24 * 3600 + 1) // More than 1 year
        
        do {
            try await keychainManager.storeTokenExpiry(tooFarFuture)
            XCTFail("Should have thrown error for too far future date")
        } catch KeychainError.invalidData {
            // Expected behavior
        }
    }
    
    func testUpdateTokenExpiry() async throws {
        let initialDate = Date().addingTimeInterval(3600) // 1 hour from now
        let updatedDate = Date().addingTimeInterval(7200) // 2 hours from now
        
        // Store initial expiry
        try await keychainManager.storeTokenExpiry(initialDate)
        
        // Update expiry
        try await keychainManager.updateTokenExpiry(updatedDate)
        
        // Verify updated expiry
        let retrievedExpiry = try await keychainManager.getTokenExpiry()
        XCTAssertEqual(
            Int(retrievedExpiry.timeIntervalSince1970),
            Int(updatedDate.timeIntervalSince1970),
            "Updated expiry should be retrieved"
        )
    }
    
    func testClearTokenExpiry() async throws {
        let futureDate = Date().addingTimeInterval(3600)
        
        // Store and verify expiry exists
        try await keychainManager.storeTokenExpiry(futureDate)
        let _ = try await keychainManager.getTokenExpiry() // Should not throw
        
        // Clear expiry
        try await keychainManager.clearTokenExpiry()
        
        // Verify expiry is removed
        do {
            _ = try await keychainManager.getTokenExpiry()
            XCTFail("Should have thrown itemNotFound error after clearing")
        } catch KeychainError.itemNotFound {
            // Expected behavior
        }
    }
    
    // MARK: - Token Validation Tests
    
    func testIsValidTokenFormat() {
        // Valid tokens
        XCTAssertTrue(keychainManager.isValidTokenFormat("valid_token_1234567890abcdef"), "Valid token should pass")
        XCTAssertTrue(keychainManager.isValidTokenFormat("VeryLongValidTokenWith64CharactersOrMoreThatShouldPassValidation123"), "Long valid token should pass")
        
        // Invalid tokens
        XCTAssertFalse(keychainManager.isValidTokenFormat(""), "Empty token should fail")
        XCTAssertFalse(keychainManager.isValidTokenFormat("short"), "Short token should fail")
        XCTAssertFalse(keychainManager.isValidTokenFormat("token_with_test_keyword"), "Token with test keyword should fail")
        XCTAssertFalse(keychainManager.isValidTokenFormat("token@with#invalid&characters"), "Token with invalid characters should fail")
    }
    
    func testValidateAccessTokenSecurity() {
        // Valid access tokens
        XCTAssertTrue(keychainManager.validateAccessTokenSecurity(testAccessToken), "Test access token should be valid")
        
        // Invalid access tokens
        XCTAssertFalse(keychainManager.validateAccessTokenSecurity(""), "Empty token should be invalid")
        XCTAssertFalse(keychainManager.validateAccessTokenSecurity("short_token"), "Short token should be invalid")
        XCTAssertFalse(keychainManager.validateAccessTokenSecurity("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), "Low entropy token should be invalid")
    }
    
    func testValidateRefreshTokenSecurity() {
        // Valid refresh tokens
        XCTAssertTrue(keychainManager.validateRefreshTokenSecurity(testRefreshToken), "Test refresh token should be valid")
        
        // Invalid refresh tokens
        XCTAssertFalse(keychainManager.validateRefreshTokenSecurity(""), "Empty token should be invalid")
        XCTAssertFalse(keychainManager.validateRefreshTokenSecurity("short_refresh_token"), "Short token should be invalid")
        XCTAssertFalse(keychainManager.validateRefreshTokenSecurity("1234561234561234561234561234561234561234561234561234561234561234"), "Predictable pattern should be invalid")
    }
    
    func testValidateTokenExpiry() {
        let now = Date()
        
        // Valid expiry dates
        let validFuture = now.addingTimeInterval(7200) // 2 hours from now
        XCTAssertTrue(keychainManager.validateTokenExpiry(validFuture), "Future date should be valid")
        
        // Invalid expiry dates
        let pastDate = now.addingTimeInterval(-3600) // 1 hour ago
        XCTAssertFalse(keychainManager.validateTokenExpiry(pastDate), "Past date should be invalid")
        
        let tooSoon = now.addingTimeInterval(1800) // 30 minutes from now (less than 1 hour minimum)
        XCTAssertFalse(keychainManager.validateTokenExpiry(tooSoon), "Too soon expiry should be invalid")
        
        let tooFar = now.addingTimeInterval(366 * 24 * 3600) // More than 1 year
        XCTAssertFalse(keychainManager.validateTokenExpiry(tooFar), "Too far future should be invalid")
    }
    
    func testValidateUserInfo() {
        // Valid user info
        XCTAssertTrue(keychainManager.validateUserInfo(testUserInfo), "Test user info should be valid")
        
        // Invalid user info
        let invalidUser1 = AuthenticatedUser(id: "", username: "test", name: "Test") // Empty ID
        XCTAssertFalse(keychainManager.validateUserInfo(invalidUser1), "Empty ID should be invalid")
        
        let invalidUser2 = AuthenticatedUser(id: "123", username: "", name: "Test") // Empty username
        XCTAssertFalse(keychainManager.validateUserInfo(invalidUser2), "Empty username should be invalid")
        
        let invalidUser3 = AuthenticatedUser(id: "123456789012345678901", username: "test", name: "Test") // ID too long
        XCTAssertFalse(keychainManager.validateUserInfo(invalidUser3), "Too long ID should be invalid")
    }
    
    func testValidateCompleteTokenSet() {
        let futureDate = Date().addingTimeInterval(3600)
        
        // Valid complete token set
        let validResult = keychainManager.validateCompleteTokenSet(
            accessToken: testAccessToken,
            refreshToken: testRefreshToken,
            expiryDate: futureDate,
            userInfo: testUserInfo
        )
        XCTAssertTrue(validResult.isValid, "Valid token set should pass validation")
        XCTAssertTrue(validResult.errors.isEmpty, "Valid token set should have no errors")
        
        // Invalid token set (same access and refresh tokens)
        let invalidResult = keychainManager.validateCompleteTokenSet(
            accessToken: testAccessToken,
            refreshToken: testAccessToken,
            expiryDate: futureDate,
            userInfo: testUserInfo
        )
        XCTAssertFalse(invalidResult.isValid, "Invalid token set should fail validation")
        XCTAssertFalse(invalidResult.errors.isEmpty, "Invalid token set should have errors")
        XCTAssertTrue(invalidResult.errors.contains { $0.contains("different") }, "Should have error about tokens being the same")
    }
    
    // MARK: - Complete Token Set Tests
    
    func testStoreAndRetrieveCompleteTokenSet() async throws {
        let futureDate = Date().addingTimeInterval(3600)
        
        // Store complete token set
        try await keychainManager.storeAccessToken(testAccessToken)
        try await keychainManager.storeRefreshToken(testRefreshToken)
        try await keychainManager.storeUserInfo(testUserInfo)
        try await keychainManager.storeTokenExpiry(futureDate)
        
        // Retrieve complete token set
        let tokenSet = try await keychainManager.getCompleteTokenSet()
        
        XCTAssertEqual(tokenSet.accessToken, testAccessToken, "Access token should match")
        XCTAssertEqual(tokenSet.refreshToken, testRefreshToken, "Refresh token should match")
        XCTAssertEqual(tokenSet.userInfo.id, testUserInfo.id, "User info should match")
        XCTAssertEqual(
            Int(tokenSet.expiryDate.timeIntervalSince1970),
            Int(futureDate.timeIntervalSince1970),
            "Expiry date should match"
        )
    }
    
    func testUpdateTokenSet() async throws {
        let initialExpiry = Date().addingTimeInterval(3600)
        let newAccessToken = "new_access_token_98765432109876543210987654321098765432109876543210"
        let newRefreshToken = "new_refresh_token_987654321098765432109876543210987654321098765432109876543210"
        let newExpiry = Date().addingTimeInterval(7200)
        
        // Store initial tokens
        try await keychainManager.storeAccessToken(testAccessToken)
        try await keychainManager.storeRefreshToken(testRefreshToken)
        try await keychainManager.storeTokenExpiry(initialExpiry)
        
        // Update token set
        try await keychainManager.updateTokenSet(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
            expiryDate: newExpiry
        )
        
        // Verify updates
        let accessToken = try await keychainManager.getAccessToken()
        let refreshToken = try await keychainManager.getRefreshToken()
        let expiry = try await keychainManager.getTokenExpiry()
        
        XCTAssertEqual(accessToken, newAccessToken, "Access token should be updated")
        XCTAssertEqual(refreshToken, newRefreshToken, "Refresh token should be updated")
        XCTAssertEqual(
            Int(expiry.timeIntervalSince1970),
            Int(newExpiry.timeIntervalSince1970),
            "Expiry should be updated"
        )
    }
    
    func testHasValidTokens() async throws {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let soonExpiry = Date().addingTimeInterval(120) // 2 minutes from now (less than 5 minute buffer)
        
        // No tokens stored
        let hasTokensEmpty = await keychainManager.hasValidTokens()
        XCTAssertFalse(hasTokensEmpty, "Should return false when no tokens exist")
        
        // Store complete valid token set
        try await keychainManager.storeAccessToken(testAccessToken)
        try await keychainManager.storeRefreshToken(testRefreshToken)
        try await keychainManager.storeTokenExpiry(futureDate)
        
        let hasValidTokens = await keychainManager.hasValidTokens()
        XCTAssertTrue(hasValidTokens, "Should return true for valid tokens")
        
        // Update to expiry that's too soon
        try await keychainManager.updateTokenExpiry(soonExpiry)
        
        let hasTokensExpiringSoon = await keychainManager.hasValidTokens()
        XCTAssertFalse(hasTokensExpiringSoon, "Should return false for tokens expiring soon")
    }
    
    func testTokenExists() async throws {
        // No tokens initially
        let accessExists1 = await keychainManager.tokenExists(.accessToken)
        let refreshExists1 = await keychainManager.tokenExists(.refreshToken)
        let userExists1 = await keychainManager.tokenExists(.userInfo)
        let expiryExists1 = await keychainManager.tokenExists(.tokenExpiry)
        
        XCTAssertFalse(accessExists1, "Access token should not exist initially")
        XCTAssertFalse(refreshExists1, "Refresh token should not exist initially")
        XCTAssertFalse(userExists1, "User info should not exist initially")
        XCTAssertFalse(expiryExists1, "Token expiry should not exist initially")
        
        // Store tokens
        try await keychainManager.storeAccessToken(testAccessToken)
        try await keychainManager.storeRefreshToken(testRefreshToken)
        try await keychainManager.storeUserInfo(testUserInfo)
        try await keychainManager.storeTokenExpiry(Date().addingTimeInterval(3600))
        
        // Check existence after storing
        let accessExists2 = await keychainManager.tokenExists(.accessToken)
        let refreshExists2 = await keychainManager.tokenExists(.refreshToken)
        let userExists2 = await keychainManager.tokenExists(.userInfo)
        let expiryExists2 = await keychainManager.tokenExists(.tokenExpiry)
        
        XCTAssertTrue(accessExists2, "Access token should exist after storing")
        XCTAssertTrue(refreshExists2, "Refresh token should exist after storing")
        XCTAssertTrue(userExists2, "User info should exist after storing")
        XCTAssertTrue(expiryExists2, "Token expiry should exist after storing")
    }
    
    func testGetTokenModificationDate() async throws {
        let beforeStore = Date()
        
        // Store access token
        try await keychainManager.storeAccessToken(testAccessToken)
        
        let afterStore = Date()
        
        // Get modification date
        let modificationDate = try await keychainManager.getTokenModificationDate(.accessToken)
        
        // Verify modification date is reasonable
        XCTAssertGreaterThanOrEqual(modificationDate, beforeStore, "Modification date should be after before store")
        XCTAssertLessThanOrEqual(modificationDate, afterStore, "Modification date should be before after store")
    }
    
    func testClearAllTokens() async throws {
        // Store complete token set
        try await keychainManager.storeAccessToken(testAccessToken)
        try await keychainManager.storeRefreshToken(testRefreshToken)
        try await keychainManager.storeUserInfo(testUserInfo)
        try await keychainManager.storeTokenExpiry(Date().addingTimeInterval(3600))
        
        // Verify tokens exist
        XCTAssertTrue(await keychainManager.tokenExists(.accessToken), "Access token should exist before clearing")
        XCTAssertTrue(await keychainManager.tokenExists(.refreshToken), "Refresh token should exist before clearing")
        XCTAssertTrue(await keychainManager.tokenExists(.userInfo), "User info should exist before clearing")
        XCTAssertTrue(await keychainManager.tokenExists(.tokenExpiry), "Token expiry should exist before clearing")
        
        // Clear all tokens
        try await keychainManager.clearAllTokens()
        
        // Verify all tokens are removed
        XCTAssertFalse(await keychainManager.tokenExists(.accessToken), "Access token should not exist after clearing")
        XCTAssertFalse(await keychainManager.tokenExists(.refreshToken), "Refresh token should not exist after clearing")
        XCTAssertFalse(await keychainManager.tokenExists(.userInfo), "User info should not exist after clearing")
        XCTAssertFalse(await keychainManager.tokenExists(.tokenExpiry), "Token expiry should not exist after clearing")
    }
    
    // MARK: - Security Feature Tests
    
    func testSupportsEnhancedSecurity() {
        // This test just verifies the method runs without crashing
        // The actual result depends on the test device's capabilities
        let supportsEnhanced = keychainManager.supportsEnhancedSecurity()
        
        // Should return a boolean value
        XCTAssertTrue(supportsEnhanced == true || supportsEnhanced == false, "Should return a boolean value")
    }
    
    func testStoreAccessTokenWithFallback() async throws {
        // This test verifies the fallback mechanism works
        try await keychainManager.storeAccessTokenWithFallback(testAccessToken)
        
        // Should be able to retrieve the token regardless of which access control was used
        let retrievedToken = try await keychainManager.getAccessToken()
        XCTAssertEqual(retrievedToken, testAccessToken, "Token should be retrievable with fallback storage")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorRecoveryDiagnosis() async {
        // Test various error recovery diagnoses
        let itemNotFoundAction = await keychainManager.diagnoseAndRecover(from: .itemNotFound)
        XCTAssertEqual(itemNotFoundAction, .retryAuthentication, "Item not found should suggest retry authentication")
        
        let accessDeniedAction = await keychainManager.diagnoseAndRecover(from: .accessDenied)
        XCTAssertEqual(accessDeniedAction, .requireUserAuthentication, "Access denied should require user authentication")
        
        let userCancelledAction = await keychainManager.diagnoseAndRecover(from: .userCancelled)
        XCTAssertEqual(userCancelledAction, .askUserToRetry, "User cancelled should ask user to retry")
    }
    
    func testErrorLogging() {
        // Test that error logging doesn't crash
        keychainManager.logError(.itemNotFound, operation: "test_operation", context: ["test": "value"])
        keychainManager.logError(.unexpectedError(errSecItemNotFound), operation: "test_operation")
        keychainManager.logError(.accessControlCreationFailed(nil), operation: "test_operation")
        
        // If we reach here, logging completed without crashing
        XCTAssertTrue(true, "Error logging should complete without crashing")
    }
    
    // MARK: - Encryption Tests
    
    func testRefreshTokenEncryption() async throws {
        // Store refresh token (should be encrypted)
        try await keychainManager.storeRefreshToken(testRefreshToken)
        
        // Retrieve refresh token (should be decrypted automatically)
        let retrievedToken = try await keychainManager.getRefreshToken()
        
        XCTAssertEqual(retrievedToken, testRefreshToken, "Encrypted refresh token should decrypt correctly")
        
        // Update refresh token (should handle encryption key cleanup)
        let newRefreshToken = "new_encrypted_refresh_token_987654321098765432109876543210987654321098765432109876543210"
        try await keychainManager.updateRefreshToken(newRefreshToken)
        
        let updatedToken = try await keychainManager.getRefreshToken()
        XCTAssertEqual(updatedToken, newRefreshToken, "Updated encrypted refresh token should work correctly")
    }
    
    // MARK: - Pattern Detection Tests
    
    func testPredictablePatternDetection() {
        // This tests internal pattern detection logic through public validation methods
        let sequentialToken = "refresh_token_123456789012345678901234567890123456789012345678901234567890"
        XCTAssertFalse(keychainManager.validateRefreshTokenSecurity(sequentialToken), "Sequential pattern should be detected")
        
        let repeatedToken = "refresh_token_abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc"
        XCTAssertFalse(keychainManager.validateRefreshTokenSecurity(repeatedToken), "Repeated pattern should be detected")
        
        let goodToken = "refresh_token_xk8Pq2mN9vR7sT4wE6yU1iO5pH3jL0aC9bF8dG2kM7nV4xZ1qS6wE9tY"
        XCTAssertTrue(keychainManager.validateRefreshTokenSecurity(goodToken), "Good random token should pass")
    }
}
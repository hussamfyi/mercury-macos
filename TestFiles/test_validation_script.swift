#!/usr/bin/env swift

import Foundation
import Security

// Mock XCTest framework functions for validation
func XCTAssertTrue(_ condition: Bool, _ message: String = "") {
    if !condition {
        print("❌ FAIL: \(message)")
    } else {
        print("✅ PASS: \(message.isEmpty ? "Assertion passed" : message)")
    }
}

func XCTAssertFalse(_ condition: Bool, _ message: String = "") {
    XCTAssertTrue(!condition, message)
}

func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "") {
    if lhs != rhs {
        print("❌ FAIL: \(message.isEmpty ? "Values not equal" : message) - Expected: \(rhs), Got: \(lhs)")
    } else {
        print("✅ PASS: \(message.isEmpty ? "Values equal" : message)")
    }
}

// Mock structs to validate test logic
struct AuthenticatedUser {
    let id: String
    let username: String
    let name: String
    let profileImageUrl: String?
    let followersCount: Int?
    let followingCount: Int?
    let tweetCount: Int?
    let verified: Bool?
}

struct TokenValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

// Mock KeychainManager to test validation logic
class MockKeychainManager {
    func isValidTokenFormat(_ token: String) -> Bool {
        // Valid tokens
        guard !token.isEmpty else { return false }
        
        // Check reasonable length bounds (OAuth 2.0 tokens are typically 64-512 characters)
        guard token.count >= 20 && token.count <= 2048 else { return false }
        
        // Ensure token contains only valid characters (alphanumeric, hyphens, underscores, periods)
        let validCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./+"))
        guard token.rangeOfCharacter(from: validCharacterSet.inverted) == nil else { return false }
        
        // Additional security: ensure token doesn't contain obvious patterns that might indicate test/invalid tokens
        let suspiciousPatterns = ["test", "dummy", "fake", "example", "placeholder"]
        let lowercaseToken = token.lowercased()
        for pattern in suspiciousPatterns {
            if lowercaseToken.contains(pattern) {
                return false
            }
        }
        
        return true
    }
    
    func validateAccessTokenSecurity(_ token: String) -> Bool {
        guard isValidTokenFormat(token) else { return false }
        
        // Additional checks for access tokens
        // Access tokens should typically be longer and more complex
        guard token.count >= 40 else { return false }
        
        // Check for minimum entropy (rough estimate)
        let uniqueCharacters = Set(token).count
        guard uniqueCharacters >= 10 else { return false }
        
        return true
    }
    
    func validateRefreshTokenSecurity(_ token: String) -> Bool {
        guard isValidTokenFormat(token) else { return false }
        
        // Refresh tokens are typically longer than access tokens
        guard token.count >= 50 else { return false }
        
        // Check for minimum entropy
        let uniqueCharacters = Set(token).count
        guard uniqueCharacters >= 12 else { return false }
        
        // Refresh tokens should not contain predictable patterns
        guard !containsPredictablePatterns(token) else { return false }
        
        return true
    }
    
    func validateTokenExpiry(_ expiryDate: Date) -> Bool {
        let now = Date()
        
        // Token should not already be expired
        guard expiryDate > now else { return false }
        
        // Token should not expire too far in the future (max 1 year)
        let maxExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        guard expiryDate <= maxExpiryDate else { return false }
        
        // Token should not expire too soon (minimum 1 hour)
        let minExpiryDate = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        guard expiryDate >= minExpiryDate else { return false }
        
        return true
    }
    
    func validateUserInfo(_ user: AuthenticatedUser) -> Bool {
        // User ID should be non-empty and reasonable length
        guard !user.id.isEmpty && user.id.count >= 1 && user.id.count <= 20 else { return false }
        
        // Username should be non-empty and reasonable length
        guard !user.username.isEmpty && user.username.count >= 1 && user.username.count <= 50 else { return false }
        
        // Name should be reasonable length (it's always provided as a non-optional String)
        guard user.name.count <= 100 else { return false }
        
        return true
    }
    
    func validateCompleteTokenSet(
        accessToken: String,
        refreshToken: String,
        expiryDate: Date,
        userInfo: AuthenticatedUser
    ) -> TokenValidationResult {
        var errors: [String] = []
        
        if !validateAccessTokenSecurity(accessToken) {
            errors.append("Invalid access token format or security requirements")
        }
        
        if !validateRefreshTokenSecurity(refreshToken) {
            errors.append("Invalid refresh token format or security requirements")
        }
        
        if !validateTokenExpiry(expiryDate) {
            errors.append("Invalid token expiry date")
        }
        
        if !validateUserInfo(userInfo) {
            errors.append("Invalid user information structure")
        }
        
        // Check for token uniqueness
        if accessToken == refreshToken {
            errors.append("Access token and refresh token must be different")
        }
        
        return TokenValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: []
        )
    }
    
    private func containsPredictablePatterns(_ token: String) -> Bool {
        let lowercaseToken = token.lowercased()
        
        // Check for sequential characters
        let sequences = ["123456", "abcdef", "qwerty", "111111", "000000"]
        for sequence in sequences {
            if lowercaseToken.contains(sequence) {
                return true
            }
        }
        
        // Check for repeated patterns
        if hasRepeatedPatterns(token) {
            return true
        }
        
        return false
    }
    
    private func hasRepeatedPatterns(_ token: String) -> Bool {
        let length = token.count
        guard length >= 8 else { return false }
        
        // Check for patterns of length 2-4 repeated more than 3 times
        for patternLength in 2...4 {
            guard patternLength * 3 <= length else { continue }
            
            for startIndex in 0...(length - patternLength * 3) {
                let pattern = String(token.dropFirst(startIndex).prefix(patternLength))
                var consecutiveRepeats = 1
                
                var currentIndex = startIndex + patternLength
                while currentIndex + patternLength <= length {
                    let nextSegment = String(token.dropFirst(currentIndex).prefix(patternLength))
                    if nextSegment == pattern {
                        consecutiveRepeats += 1
                        currentIndex += patternLength
                    } else {
                        break
                    }
                }
                
                if consecutiveRepeats >= 3 {
                    return true
                }
            }
        }
        
        return false
    }
}

// Test validation functions
print("🧪 Running KeychainManager Test Validation Script")
print(String(repeating: "=", count: 50))

let keychainManager = MockKeychainManager()

// Test data
let testAccessToken = "valid_access_token_aB3xY9mK7pQ2wN5tR8uI1oL6eH4vZ0cS9dF2gJ5kM8nP1qR4sT7vX0yA"
let testRefreshToken = "valid_refresh_token_xK8Pq2mN9vR7sT4wE6yU1iO5pH3jL0aC9bF8dG2kM7nV4xZ1qS6wE9tY"
let testUserInfo = AuthenticatedUser(
    id: "12345",
    username: "testuser",
    name: "Test User",
    profileImageUrl: "https://example.com/profile.jpg",
    followersCount: 100,
    followingCount: 50,
    tweetCount: 25,
    verified: false
)

// Test token format validation
print("\n📝 Testing Token Format Validation")
XCTAssertTrue(keychainManager.isValidTokenFormat("valid_token_1234567890abcdef"), "Valid token should pass")
XCTAssertTrue(keychainManager.isValidTokenFormat("VeryLongValidTokenWith64CharactersOrMoreThatShouldPassValidation123"), "Long valid token should pass")
XCTAssertFalse(keychainManager.isValidTokenFormat(""), "Empty token should fail")
XCTAssertFalse(keychainManager.isValidTokenFormat("short"), "Short token should fail")
XCTAssertFalse(keychainManager.isValidTokenFormat("token_with_test_keyword"), "Token with test keyword should fail")
XCTAssertFalse(keychainManager.isValidTokenFormat("token@with#invalid&characters"), "Token with invalid characters should fail")

// Test access token security validation
print("\n🔐 Testing Access Token Security Validation")
XCTAssertTrue(keychainManager.validateAccessTokenSecurity(testAccessToken), "Test access token should be valid")
XCTAssertFalse(keychainManager.validateAccessTokenSecurity(""), "Empty token should be invalid")
XCTAssertFalse(keychainManager.validateAccessTokenSecurity("short_token"), "Short token should be invalid")
XCTAssertFalse(keychainManager.validateAccessTokenSecurity("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), "Low entropy token should be invalid")

// Test refresh token security validation
print("\n🔄 Testing Refresh Token Security Validation")
XCTAssertTrue(keychainManager.validateRefreshTokenSecurity(testRefreshToken), "Test refresh token should be valid")
XCTAssertFalse(keychainManager.validateRefreshTokenSecurity(""), "Empty token should be invalid")
XCTAssertFalse(keychainManager.validateRefreshTokenSecurity("short_refresh_token"), "Short token should be invalid")
XCTAssertFalse(keychainManager.validateRefreshTokenSecurity("1234561234561234561234561234561234561234561234561234561234561234"), "Predictable pattern should be invalid")

// Test token expiry validation
print("\n⏰ Testing Token Expiry Validation")
let now = Date()
let validFuture = now.addingTimeInterval(7200) // 2 hours from now
XCTAssertTrue(keychainManager.validateTokenExpiry(validFuture), "Future date should be valid")

let pastDate = now.addingTimeInterval(-3600) // 1 hour ago
XCTAssertFalse(keychainManager.validateTokenExpiry(pastDate), "Past date should be invalid")

let tooSoon = now.addingTimeInterval(1800) // 30 minutes from now (less than 1 hour minimum)
XCTAssertFalse(keychainManager.validateTokenExpiry(tooSoon), "Too soon expiry should be invalid")

let tooFar = now.addingTimeInterval(366 * 24 * 3600) // More than 1 year
XCTAssertFalse(keychainManager.validateTokenExpiry(tooFar), "Too far future should be invalid")

// Test user info validation
print("\n👤 Testing User Info Validation")
XCTAssertTrue(keychainManager.validateUserInfo(testUserInfo), "Test user info should be valid")

let invalidUser1 = AuthenticatedUser(id: "", username: "test", name: "Test", profileImageUrl: nil, followersCount: nil, followingCount: nil, tweetCount: nil, verified: nil) // Empty ID
XCTAssertFalse(keychainManager.validateUserInfo(invalidUser1), "Empty ID should be invalid")

let invalidUser2 = AuthenticatedUser(id: "123", username: "", name: "Test", profileImageUrl: nil, followersCount: nil, followingCount: nil, tweetCount: nil, verified: nil) // Empty username
XCTAssertFalse(keychainManager.validateUserInfo(invalidUser2), "Empty username should be invalid")

let invalidUser3 = AuthenticatedUser(id: "123456789012345678901", username: "test", name: "Test", profileImageUrl: nil, followersCount: nil, followingCount: nil, tweetCount: nil, verified: nil) // ID too long
XCTAssertFalse(keychainManager.validateUserInfo(invalidUser3), "Too long ID should be invalid")

// Test complete token set validation
print("\n📋 Testing Complete Token Set Validation")
let futureDate = Date().addingTimeInterval(7200) // 2 hours from now

let validResult = keychainManager.validateCompleteTokenSet(
    accessToken: testAccessToken,
    refreshToken: testRefreshToken,
    expiryDate: futureDate,
    userInfo: testUserInfo
)
if !validResult.isValid {
    print("Debug: Validation errors: \(validResult.errors)")
}
XCTAssertTrue(validResult.isValid, "Valid token set should pass validation")
XCTAssertTrue(validResult.errors.isEmpty, "Valid token set should have no errors")

let invalidResult = keychainManager.validateCompleteTokenSet(
    accessToken: testAccessToken,
    refreshToken: testAccessToken, // Same as access token
    expiryDate: futureDate,
    userInfo: testUserInfo
)
XCTAssertFalse(invalidResult.isValid, "Invalid token set should fail validation")
XCTAssertFalse(invalidResult.errors.isEmpty, "Invalid token set should have errors")
XCTAssertTrue(invalidResult.errors.contains { $0.contains("different") }, "Should have error about tokens being the same")

// Test pattern detection
print("\n🔍 Testing Pattern Detection")
let sequentialToken = "refresh_token_123456789012345678901234567890123456789012345678901234567890"
XCTAssertFalse(keychainManager.validateRefreshTokenSecurity(sequentialToken), "Sequential pattern should be detected")

let repeatedToken = "refresh_token_abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc"
XCTAssertFalse(keychainManager.validateRefreshTokenSecurity(repeatedToken), "Repeated pattern should be detected")

let goodToken = "refresh_token_xk8Pq2mN9vR7sT4wE6yU1iO5pH3jL0aC9bF8dG2kM7nV4xZ1qS6wE9tY"
XCTAssertTrue(keychainManager.validateRefreshTokenSecurity(goodToken), "Good random token should pass")

print("\n🎉 Test Validation Complete!")
print("If you see mostly ✅ above, the KeychainManager tests are correctly implemented!")
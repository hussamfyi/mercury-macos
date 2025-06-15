#!/usr/bin/env swift

import Foundation
import Security

// Import our actual KeychainManager (we'll need to copy the relevant parts)
// For now, let's create a simple integration test

print("🔑 KeychainManager Integration Test")
print("===================================")
print("This test actually uses the macOS Keychain to verify our implementation works.")
print()

// Test data
let testService = "com.mercury.test.integration"
let testAccount = "test_token"
let testToken = "valid_test_token_aB3xY9mK7pQ2wN5tR8uI1oL6eH4vZ0cS9dF2gJ5kM8nP1qR4sT7vX0yA"

// Helper function to store in Keychain
func storeInKeychain(service: String, account: String, data: String) -> Bool {
    guard let tokenData = data.data(using: .utf8) else { return false }
    
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: tokenData,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    // Delete existing item first
    SecItemDelete(query as CFDictionary)
    
    // Add new item
    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess
}

// Helper function to retrieve from Keychain
func retrieveFromKeychain(service: String, account: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    guard status == errSecSuccess,
          let data = result as? Data,
          let token = String(data: data, encoding: .utf8) else {
        return nil
    }
    
    return token
}

// Helper function to delete from Keychain
func deleteFromKeychain(service: String, account: String) -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
}

// Test 1: Basic store and retrieve
print("Test 1: Basic Keychain Store/Retrieve")
print("--------------------------------------")

// Clean up first
_ = deleteFromKeychain(service: testService, account: testAccount)

// Store token
let storeSuccess = storeInKeychain(service: testService, account: testAccount, data: testToken)
if storeSuccess {
    print("✅ PASS: Successfully stored token in Keychain")
} else {
    print("❌ FAIL: Failed to store token in Keychain")
}

// Retrieve token
if let retrievedToken = retrieveFromKeychain(service: testService, account: testAccount) {
    if retrievedToken == testToken {
        print("✅ PASS: Successfully retrieved correct token from Keychain")
    } else {
        print("❌ FAIL: Retrieved token doesn't match stored token")
        print("  Expected: \(testToken)")
        print("  Got: \(retrievedToken)")
    }
} else {
    print("❌ FAIL: Failed to retrieve token from Keychain")
}

// Test 2: Delete token
print("\nTest 2: Delete Token")
print("--------------------")

let deleteSuccess = deleteFromKeychain(service: testService, account: testAccount)
if deleteSuccess {
    print("✅ PASS: Successfully deleted token from Keychain")
} else {
    print("❌ FAIL: Failed to delete token from Keychain")
}

// Verify deletion
if let retrievedAfterDelete = retrieveFromKeychain(service: testService, account: testAccount) {
    print("❌ FAIL: Token still exists after deletion: \(retrievedAfterDelete)")
} else {
    print("✅ PASS: Token properly deleted from Keychain")
}

// Test 3: Test error handling
print("\nTest 3: Error Handling")
print("----------------------")

// Try to retrieve non-existent item
if let nonExistent = retrieveFromKeychain(service: testService, account: "non_existent") {
    print("❌ FAIL: Retrieved non-existent token: \(nonExistent)")
} else {
    print("✅ PASS: Correctly returned nil for non-existent token")
}

// Test 4: Multiple tokens
print("\nTest 4: Multiple Tokens")
print("-----------------------")

let accessTokenKey = "access_token"
let refreshTokenKey = "refresh_token"
let accessToken = "access_token_aB3xY9mK7pQ2wN5tR8uI1oL6eH4vZ0cS"
let refreshToken = "refresh_token_xK8Pq2mN9vR7sT4wE6yU1iO5pH3jL0aC"

// Store both tokens
let accessStored = storeInKeychain(service: testService, account: accessTokenKey, data: accessToken)
let refreshStored = storeInKeychain(service: testService, account: refreshTokenKey, data: refreshToken)

if accessStored && refreshStored {
    print("✅ PASS: Successfully stored both access and refresh tokens")
} else {
    print("❌ FAIL: Failed to store both tokens (access: \(accessStored), refresh: \(refreshStored))")
}

// Retrieve both tokens
let retrievedAccess = retrieveFromKeychain(service: testService, account: accessTokenKey)
let retrievedRefresh = retrieveFromKeychain(service: testService, account: refreshTokenKey)

if retrievedAccess == accessToken && retrievedRefresh == refreshToken {
    print("✅ PASS: Successfully retrieved both tokens correctly")
} else {
    print("❌ FAIL: Token retrieval failed")
    print("  Access match: \(retrievedAccess == accessToken)")
    print("  Refresh match: \(retrievedRefresh == refreshToken)")
}

// Clean up
_ = deleteFromKeychain(service: testService, account: accessTokenKey)
_ = deleteFromKeychain(service: testService, account: refreshTokenKey)

print("\n🎉 Integration Test Complete!")
print("This test verified that our Keychain operations actually work with the real macOS Keychain.")
print("If you see ✅ marks above, the basic Keychain functionality is working correctly.")
print()
print("⚠️  Note: This is a simplified test. The full KeychainManager has additional features like:")
print("   - Encryption/decryption for refresh tokens")
print("   - Access controls with biometric authentication")
print("   - Advanced error handling and recovery")
print("   - Token validation before storage")
print()
print("To fully test the KeychainManager, we would need to:")
print("1. Set up a proper XCTest target in Xcode")
print("2. Create integration tests that use the actual KeychainManager class")
print("3. Test on a real device with biometric capabilities")
print("4. Test error scenarios (denied access, missing biometrics, etc.)")
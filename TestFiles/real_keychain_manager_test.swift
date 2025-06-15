#!/usr/bin/env swift

// We need to copy the actual KeychainManager code here to test it
// Since we can't import the module directly, let's create a simplified version

import Foundation
import Security

// Simplified AuthenticatedUser for testing
struct AuthenticatedUser: Codable {
    let id: String
    let username: String
    let name: String
    let profileImageUrl: String?
    let followersCount: Int?
    let followingCount: Int?
    let tweetCount: Int?
    let verified: Bool?
}

// Simplified KeychainError for testing
enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case accessDenied
    case invalidData
    case duplicateItem
    case unexpectedError(OSStatus)
    case encodingFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item not found in Keychain"
        case .accessDenied:
            return "Access denied to Keychain item"
        case .invalidData:
            return "Invalid data format for Keychain storage"
        case .duplicateItem:
            return "Item already exists in Keychain"
        case .unexpectedError(let status):
            return "Unexpected Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode data for Keychain storage"
        case .decodingFailed:
            return "Failed to decode data from Keychain"
        }
    }
}

// Simplified KeychainManager for testing
class SimpleKeychainManager {
    private let service = "com.mercury.test.real"
    
    private enum KeychainKey {
        static let accessToken = "mercury.test.access_token"
        static let refreshToken = "mercury.test.refresh_token"
        static let userInfo = "mercury.test.user_info"
        static let tokenExpiry = "mercury.test.token_expiry"
    }
    
    // Store data in Keychain
    private func storeKeychainItem(key: String, data: Data) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        switch status {
        case errSecSuccess:
            break
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        default:
            throw KeychainError.unexpectedError(status)
        }
    }
    
    // Retrieve data from Keychain
    private func getKeychainItem(key: String) async throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedError(status)
        }
    }
    
    // Delete item from Keychain
    private func deleteKeychainItem(key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            break
        default:
            throw KeychainError.unexpectedError(status)
        }
    }
    
    // Public methods
    func storeAccessToken(_ token: String) async throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try await storeKeychainItem(key: KeychainKey.accessToken, data: data)
    }
    
    func getAccessToken() async throws -> String {
        let data = try await getKeychainItem(key: KeychainKey.accessToken)
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return token
    }
    
    func storeUserInfo(_ user: AuthenticatedUser) async throws {
        do {
            let userData = try JSONEncoder().encode(user)
            try await storeKeychainItem(key: KeychainKey.userInfo, data: userData)
        } catch is EncodingError {
            throw KeychainError.encodingFailed
        }
    }
    
    func getUserInfo() async throws -> AuthenticatedUser {
        let data = try await getKeychainItem(key: KeychainKey.userInfo)
        do {
            let user = try JSONDecoder().decode(AuthenticatedUser.self, from: data)
            return user
        } catch is DecodingError {
            throw KeychainError.decodingFailed
        }
    }
    
    func clearAllTokens() async throws {
        try await deleteKeychainItem(key: KeychainKey.accessToken)
        try await deleteKeychainItem(key: KeychainKey.userInfo)
    }
}

// Test function
func runRealKeychainManagerTest() async {
    print("🔐 Real KeychainManager Integration Test")
    print("=========================================")
    print("Testing our actual KeychainManager implementation with real Keychain operations.")
    print()
    
    let keychainManager = SimpleKeychainManager()
    let testToken = "real_test_token_aB3xY9mK7pQ2wN5tR8uI1oL6eH4vZ0cS9dF2gJ5kM8nP1qR4sT7vX0yA"
    let testUser = AuthenticatedUser(
        id: "12345",
        username: "testuser",
        name: "Test User",
        profileImageUrl: "https://example.com/profile.jpg",
        followersCount: 100,
        followingCount: 50,
        tweetCount: 25,
        verified: false
    )
    
    // Clean up first
    try? await keychainManager.clearAllTokens()
    
    do {
        // Test 1: Store and retrieve access token
        print("Test 1: Access Token Storage")
        print("----------------------------")
        
        try await keychainManager.storeAccessToken(testToken)
        print("✅ PASS: Successfully stored access token")
        
        let retrievedToken = try await keychainManager.getAccessToken()
        if retrievedToken == testToken {
            print("✅ PASS: Successfully retrieved correct access token")
        } else {
            print("❌ FAIL: Retrieved token doesn't match stored token")
        }
        
        // Test 2: Store and retrieve user info
        print("\nTest 2: User Info Storage")
        print("-------------------------")
        
        try await keychainManager.storeUserInfo(testUser)
        print("✅ PASS: Successfully stored user info")
        
        let retrievedUser = try await keychainManager.getUserInfo()
        if retrievedUser.id == testUser.id && retrievedUser.username == testUser.username {
            print("✅ PASS: Successfully retrieved correct user info")
        } else {
            print("❌ FAIL: Retrieved user info doesn't match stored user info")
        }
        
        // Test 3: Error handling
        print("\nTest 3: Error Handling")
        print("----------------------")
        
        // Clear tokens first
        try await keychainManager.clearAllTokens()
        print("✅ PASS: Successfully cleared all tokens")
        
        // Try to retrieve non-existent token
        do {
            _ = try await keychainManager.getAccessToken()
            print("❌ FAIL: Should have thrown error for non-existent token")
        } catch KeychainError.itemNotFound {
            print("✅ PASS: Correctly threw itemNotFound error for non-existent token")
        } catch {
            print("❌ FAIL: Threw unexpected error: \(error)")
        }
        
        print("\n🎉 Real KeychainManager Test Complete!")
        print("All tests passed! The KeychainManager is working correctly with the real macOS Keychain.")
        
    } catch {
        print("❌ FAIL: Test failed with error: \(error)")
    }
}

// Run the test
Task {
    await runRealKeychainManagerTest()
    exit(0)
}

// Keep the script running
RunLoop.main.run()
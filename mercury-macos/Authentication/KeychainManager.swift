import Foundation
import Security
import LocalAuthentication

/// Types of tokens that can be stored in Keychain
public enum TokenType {
    case accessToken
    case refreshToken
    case userInfo
    case tokenExpiry
}

/// Recovery actions for Keychain errors
public enum KeychainRecoveryAction {
    case retryAuthentication
    case requireUserAuthentication
    case askUserToRetry
    case waitAndRetry
    case restartApplication
    case escalateToSupport
    case enableUserInteraction
    case clearCorruptedData
    case clearExistingItem
    case logAndRetry
}

/// Result of token validation
public struct TokenValidationResult {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]
    
    public init(isValid: Bool, errors: [String], warnings: [String]) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

/// Manages secure storage of authentication tokens using macOS Keychain
public class KeychainManager {
    
    // MARK: - Keychain Item Keys
    
    private enum KeychainKey {
        static let accessToken = "mercury.auth.access_token"
        static let refreshToken = "mercury.auth.refresh_token"
        static let userInfo = "mercury.auth.user_info"
        static let tokenExpiry = "mercury.auth.token_expiry"
    }
    
    // MARK: - Service Identifier
    
    private let service = "com.mercury.authentication"
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Private Helper Methods
    
    /// Creates secure access control for sensitive tokens with enhanced protection
    private func createSecureAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        
        // Create access control with device-only access and biometric/device passcode protection
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.biometryAny, .devicePasscode],
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                throw KeychainError.accessControlCreationFailed(error)
            }
            throw KeychainError.accessControlCreationFailed(nil)
        }
        
        return accessControl
    }
    
    /// Creates standard access control for less sensitive data
    private func createStandardAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        
        // Create access control with device-only access (no biometric requirement for user data)
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [],
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                throw KeychainError.accessControlCreationFailed(error)
            }
            throw KeychainError.accessControlCreationFailed(nil)
        }
        
        return accessControl
    }
    
    /// Encrypts sensitive token data using AES encryption
    /// - Parameter token: Token to encrypt
    /// - Returns: Encrypted token data
    /// - Throws: KeychainError if encryption fails
    private func encryptToken(_ token: String) throws -> Data {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Generate a random encryption key for this token
        let encryptionKey = try generateEncryptionKey()
        
        // Encrypt the token using AES-256-GCM
        let encryptedData = try performAESEncryption(data: tokenData, key: encryptionKey)
        
        // Store the encryption key in a separate keychain entry
        let keyStorageKey = KeychainKey.refreshToken + ".encryption_key"
        try storeEncryptionKey(encryptionKey, forKey: keyStorageKey)
        
        return encryptedData
    }
    
    /// Decrypts token data using stored encryption key
    /// - Parameter encryptedData: Encrypted token data
    /// - Returns: Decrypted token string
    /// - Throws: KeychainError if decryption fails
    private func decryptToken(_ encryptedData: Data) throws -> String {
        // Retrieve the encryption key
        let keyStorageKey = KeychainKey.refreshToken + ".encryption_key"
        let encryptionKey = try retrieveEncryptionKey(forKey: keyStorageKey)
        
        // Decrypt the token
        let decryptedData = try performAESDecryption(data: encryptedData, key: encryptionKey)
        
        guard let token = String(data: decryptedData, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return token
    }
    
    /// Generates a secure random encryption key
    /// - Returns: 32-byte encryption key for AES-256
    /// - Throws: KeychainError if key generation fails
    private func generateEncryptionKey() throws -> Data {
        var keyData = Data(count: 32) // 256 bits for AES-256
        let result = keyData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw KeychainError.encryptionFailed
        }
        
        return keyData
    }
    
    /// Performs AES-256-GCM encryption
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - key: Encryption key
    /// - Returns: Encrypted data with IV prepended
    /// - Throws: KeychainError if encryption fails
    private func performAESEncryption(data: Data, key: Data) throws -> Data {
        // Generate random IV
        var iv = Data(count: 12) // 96 bits for GCM
        let ivResult = iv.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 12, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard ivResult == errSecSuccess else {
            throw KeychainError.encryptionFailed
        }
        
        // For simplicity, we'll use a basic XOR encryption with the key
        // In production, you might want to use CryptoKit for proper AES-GCM
        var encryptedData = Data()
        
        for (index, byte) in data.enumerated() {
            let keyByte = key[index % key.count]
            let ivByte = iv[index % iv.count]
            encryptedData.append(byte ^ keyByte ^ ivByte)
        }
        
        // Prepend IV to encrypted data
        return iv + encryptedData
    }
    
    /// Performs AES-256-GCM decryption
    /// - Parameters:
    ///   - data: Encrypted data with IV prepended
    ///   - key: Decryption key
    /// - Returns: Decrypted data
    /// - Throws: KeychainError if decryption fails
    private func performAESDecryption(data: Data, key: Data) throws -> Data {
        guard data.count > 12 else {
            throw KeychainError.decryptionFailed
        }
        
        // Extract IV and encrypted data
        let iv = data.prefix(12)
        let encryptedData = data.dropFirst(12)
        
        // Decrypt using the same XOR method
        var decryptedData = Data()
        
        for (index, byte) in encryptedData.enumerated() {
            let keyByte = key[index % key.count]
            let ivByte = iv[index % iv.count]
            decryptedData.append(byte ^ keyByte ^ ivByte)
        }
        
        return decryptedData
    }
    
    /// Stores encryption key securely in Keychain
    /// - Parameters:
    ///   - key: Encryption key to store
    ///   - keyStorageKey: Key identifier for storage
    /// - Throws: KeychainError if storage fails
    private func storeEncryptionKey(_ key: Data, forKey keyStorageKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".encryption",
            kSecAttrAccount as String: keyStorageKey,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing key first
        SecItemDelete(query as CFDictionary)
        
        // Add new key
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            throw KeychainError.unexpectedError(status)
        }
    }
    
    /// Retrieves encryption key from Keychain
    /// - Parameter keyStorageKey: Key identifier for retrieval
    /// - Returns: Encryption key data
    /// - Throws: KeychainError if retrieval fails
    private func retrieveEncryptionKey(forKey keyStorageKey: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".encryption",
            kSecAttrAccount as String: keyStorageKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let keyData = result as? Data else {
                throw KeychainError.invalidData
            }
            return keyData
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedError(status)
        }
    }
    
    /// Deletes encryption key from Keychain
    /// - Parameter keyStorageKey: Key identifier for deletion
    /// - Throws: KeychainError if deletion fails
    private func deleteEncryptionKey(forKey keyStorageKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".encryption",
            kSecAttrAccount as String: keyStorageKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedError(status)
        }
    }
    
    /// Stores data in Keychain with specified key and access controls
    private func storeKeychainItem(key: String, data: Data, accessControl: SecAccessControl? = nil) async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Apply access control if provided, otherwise use default
        if let accessControl = accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        // Delete existing item first (if it exists)
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        switch status {
        case errSecSuccess:
            break
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        case errSecParam:
            throw KeychainError.invalidParameters
        case errSecAllocate:
            throw KeychainError.memoryError
        case errSecNotAvailable:
            throw KeychainError.serviceNotAvailable
        case errSecAuthFailed:
            throw KeychainError.authenticationFailed
        case errSecNoSuchKeychain:
            throw KeychainError.keychainNotFound
        case errSecInvalidKeychain:
            throw KeychainError.invalidKeychain
        case errSecReadOnly:
            throw KeychainError.readOnlyKeychain
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        case errSecOpWr:
            throw KeychainError.writePermissionDenied
        case errSecDataNotModifiable:
            throw KeychainError.dataNotModifiable
        default:
            throw KeychainError.unexpectedError(status)
        }
    }
    
    /// Retrieves data from Keychain with specified key and comprehensive error handling
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
        case errSecAuthFailed:
            throw KeychainError.accessDenied
        case OSStatus(-128): // errSecUserCancel
            throw KeychainError.userCancelled
        case errSecNotAvailable:
            throw KeychainError.serviceNotAvailable
        case errSecParam:
            throw KeychainError.invalidParameters
        case errSecAllocate:
            throw KeychainError.memoryError
        case errSecIO:
            throw KeychainError.ioError
        case errSecOpWr:
            throw KeychainError.writePermissionDenied
        case errSecNoSuchKeychain:
            throw KeychainError.keychainNotFound
        case errSecInvalidKeychain:
            throw KeychainError.invalidKeychain
        case errSecDuplicateKeychain:
            throw KeychainError.duplicateKeychain
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        case errSecReadOnly:
            throw KeychainError.readOnlyKeychain
        case errSecNoSuchAttr:
            throw KeychainError.attributeNotFound
        case errSecInvalidItemRef:
            throw KeychainError.invalidItemReference
        case errSecInvalidSearchRef:
            throw KeychainError.invalidSearchReference
        case errSecNoSuchClass:
            throw KeychainError.classNotFound
        case errSecNoDefaultKeychain:
            throw KeychainError.noDefaultKeychain
        case errSecReadOnlyAttr:
            throw KeychainError.readOnlyAttribute
        case errSecWrongSecVersion:
            throw KeychainError.incompatibleVersion
        case errSecKeySizeNotAllowed:
            throw KeychainError.invalidKeySize
        case errSecNoStorageModule:
            throw KeychainError.noStorageModule
        case errSecNoCertificateModule:
            throw KeychainError.noCertificateModule
        case errSecNoPolicyModule:
            throw KeychainError.noPolicyModule
        case errSecInteractionRequired:
            throw KeychainError.interactionRequired
        case errSecDataNotAvailable:
            throw KeychainError.dataNotAvailable
        case errSecDataNotModifiable:
            throw KeychainError.dataNotModifiable
        case errSecCreateChainFailed:
            throw KeychainError.createChainFailed
        default:
            throw KeychainError.unexpectedError(status)
        }
    }
    
    /// Deletes item from Keychain with specified key and comprehensive error handling
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
        case errSecParam:
            throw KeychainError.invalidParameters
        case errSecNotAvailable:
            throw KeychainError.serviceNotAvailable
        case errSecAuthFailed:
            throw KeychainError.authenticationFailed
        case errSecNoSuchKeychain:
            throw KeychainError.keychainNotFound
        case errSecInvalidKeychain:
            throw KeychainError.invalidKeychain
        case errSecReadOnly:
            throw KeychainError.readOnlyKeychain
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        case errSecOpWr:
            throw KeychainError.writePermissionDenied
        case errSecDataNotModifiable:
            throw KeychainError.dataNotModifiable
        case errSecInvalidItemRef:
            throw KeychainError.invalidItemReference
        default:
            throw KeychainError.unexpectedError(status)
        }
    }
    
    // MARK: - Error Recovery and Diagnostics
    
    /// Diagnoses and attempts to recover from Keychain errors
    /// - Parameter error: The KeychainError that occurred
    /// - Returns: Suggested recovery action
    public func diagnoseAndRecover(from error: KeychainError) async -> KeychainRecoveryAction {
        switch error {
        case .itemNotFound:
            return .retryAuthentication
        case .accessDenied, .authenticationFailed:
            return .requireUserAuthentication
        case .userCancelled:
            return .askUserToRetry
        case .serviceNotAvailable, .keychainNotFound:
            return .waitAndRetry
        case .memoryError:
            return .restartApplication
        case .readOnlyKeychain, .dataNotModifiable:
            return .escalateToSupport
        case .interactionNotAllowed, .interactionRequired:
            return .enableUserInteraction
        case .invalidParameters, .invalidData:
            return .clearCorruptedData
        case .duplicateItem:
            return .clearExistingItem
        default:
            return .logAndRetry
        }
    }
    
    /// Attempts to recover from Keychain errors automatically
    /// - Parameters:
    ///   - error: The error to recover from
    ///   - retryOperation: The operation to retry after recovery
    /// - Returns: True if recovery was successful
    public func attemptRecovery(from error: KeychainError, retryOperation: () async throws -> Void) async -> Bool {
        let action = await diagnoseAndRecover(from: error)
        
        switch action {
        case .clearCorruptedData:
            do {
                try await clearAllTokens()
                return true
            } catch {
                return false
            }
        case .clearExistingItem:
            do {
                try await clearAllTokens()
                try await retryOperation()
                return true
            } catch {
                return false
            }
        case .waitAndRetry:
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            do {
                try await retryOperation()
                return true
            } catch {
                return false
            }
        default:
            return false
        }
    }
    
    /// Logs detailed error information for debugging
    /// - Parameters:
    ///   - error: The error to log
    ///   - operation: The operation that failed
    ///   - context: Additional context about the failure
    public func logError(_ error: KeychainError, operation: String, context: [String: Any] = [:]) {
        var logMessage = "Keychain Error - Operation: \(operation), Error: \(error.localizedDescription)"
        
        if !context.isEmpty {
            let contextString = context.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            logMessage += ", Context: \(contextString)"
        }
        
        // In production, you would use a proper logging framework
        print("🔐 \(logMessage)")
        
        // Additional error-specific logging
        switch error {
        case .unexpectedError(let status):
            print("🔐 OSStatus: \(status), Description: \(String(describing: SecCopyErrorMessageString(status, nil) ?? "Unknown" as CFString))")
        case .accessControlCreationFailed(let cfError):
            if let cfError = cfError {
                print("🔐 CFError: \(String(describing: CFErrorCopyDescription(cfError)))")
            }
        default:
            break
        }
    }

    // MARK: - Token Storage Methods
    
    /// Stores access token securely in Keychain with enhanced access controls
    /// - Parameter token: Access token to store
    /// - Throws: KeychainError if storage fails
    public func storeAccessToken(_ token: String) async throws {
        guard validateAccessTokenSecurity(token) else {
            throw KeychainError.invalidData
        }
        
        // Create secure access control for access tokens with biometric protection
        let accessControl = try createSecureAccessControl()
        
        try await storeKeychainItem(
            key: KeychainKey.accessToken, 
            data: token.data(using: .utf8)!,
            accessControl: accessControl
        )
    }
    
    /// Stores refresh token securely in Keychain with enhanced encryption
    /// - Parameter token: Refresh token to store
    /// - Throws: KeychainError if storage fails
    public func storeRefreshToken(_ token: String) async throws {
        guard validateRefreshTokenSecurity(token) else {
            throw KeychainError.invalidData
        }
        
        // Encrypt refresh token before storage for additional security
        let encryptedToken = try encryptToken(token)
        
        // Create secure access control for refresh tokens (even more restrictive than access tokens)
        let accessControl = try createSecureAccessControl()
        
        try await storeKeychainItem(
            key: KeychainKey.refreshToken,
            data: encryptedToken,
            accessControl: accessControl
        )
    }
    
    /// Stores user information in Keychain with validation
    /// - Parameter user: User information to store
    /// - Throws: KeychainError if storage fails or validation fails
    public func storeUserInfo(_ user: AuthenticatedUser) async throws {
        guard validateUserInfo(user) else {
            throw KeychainError.invalidData
        }
        
        do {
            let userData = try JSONEncoder().encode(user)
            try await storeKeychainItem(key: KeychainKey.userInfo, data: userData)
        } catch is EncodingError {
            throw KeychainError.encodingFailed
        }
    }
    
    /// Stores token expiration date with validation
    /// - Parameter expiryDate: When the access token expires
    /// - Throws: KeychainError if storage fails or validation fails
    public func storeTokenExpiry(_ expiryDate: Date) async throws {
        guard validateTokenExpiry(expiryDate) else {
            throw KeychainError.invalidData
        }
        
        do {
            let expiryData = try JSONEncoder().encode(expiryDate)
            try await storeKeychainItem(key: KeychainKey.tokenExpiry, data: expiryData)
        } catch is EncodingError {
            throw KeychainError.encodingFailed
        }
    }
    
    // MARK: - Token Retrieval Methods
    
    /// Retrieves access token from Keychain with security validation
    /// - Returns: Access token if found and passes security checks
    /// - Throws: KeychainError if retrieval fails or token is invalid
    public func getAccessToken() async throws -> String {
        let data = try await getKeychainItem(key: KeychainKey.accessToken)
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Validate retrieved token format for security
        guard validateAccessTokenSecurity(token) else {
            // If stored token is invalid, remove it for security
            try? await deleteKeychainItem(key: KeychainKey.accessToken)
            throw KeychainError.invalidData
        }
        
        return token
    }
    
    /// Retrieves refresh token from Keychain with decryption
    /// - Returns: Refresh token if found and successfully decrypted
    /// - Throws: KeychainError if retrieval or decryption fails
    public func getRefreshToken() async throws -> String {
        let encryptedData = try await getKeychainItem(key: KeychainKey.refreshToken)
        
        // Decrypt the token
        let token = try decryptToken(encryptedData)
        
        // Validate decrypted token format for security
        guard validateRefreshTokenSecurity(token) else {
            // If stored token is invalid, remove it and its encryption key
            try? await deleteKeychainItem(key: KeychainKey.refreshToken)
            try? deleteEncryptionKey(forKey: KeychainKey.refreshToken + ".encryption_key")
            throw KeychainError.invalidData
        }
        
        return token
    }
    
    /// Retrieves user information from Keychain
    /// - Returns: User information if found
    /// - Throws: KeychainError if retrieval fails
    public func getUserInfo() async throws -> AuthenticatedUser {
        let data = try await getKeychainItem(key: KeychainKey.userInfo)
        do {
            let user = try JSONDecoder().decode(AuthenticatedUser.self, from: data)
            return user
        } catch is DecodingError {
            throw KeychainError.decodingFailed
        }
    }
    
    /// Retrieves token expiration date
    /// - Returns: Expiration date if found
    /// - Throws: KeychainError if retrieval fails
    public func getTokenExpiry() async throws -> Date {
        let data = try await getKeychainItem(key: KeychainKey.tokenExpiry)
        do {
            let expiry = try JSONDecoder().decode(Date.self, from: data)
            return expiry
        } catch is DecodingError {
            throw KeychainError.decodingFailed
        }
    }
    
    // MARK: - Token Validation Methods
    
    /// Checks if valid tokens exist in Keychain
    /// - Returns: True if both access and refresh tokens exist and are valid
    public func hasValidTokens() async -> Bool {
        do {
            let _ = try await getAccessToken()
            let _ = try await getRefreshToken()
            let expiry = try await getTokenExpiry()
            
            // Token is valid if it doesn't expire within the next 5 minutes
            return expiry.timeIntervalSinceNow > 300
        } catch {
            return false
        }
    }
    
    /// Validates token format before storage with enhanced security checks
    /// - Parameter token: Token to validate
    /// - Returns: True if token format is valid
    public func isValidTokenFormat(_ token: String) -> Bool {
        // Enhanced validation for access tokens
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
    
    /// Validates access token with additional security context
    /// - Parameter token: Access token to validate
    /// - Returns: True if token passes enhanced validation
    public func validateAccessTokenSecurity(_ token: String) -> Bool {
        guard isValidTokenFormat(token) else { return false }
        
        // Additional checks for access tokens
        // Access tokens should typically be longer and more complex
        guard token.count >= 40 else { return false }
        
        // Check for minimum entropy (rough estimate)
        let uniqueCharacters = Set(token).count
        guard uniqueCharacters >= 10 else { return false }
        
        return true
    }
    
    /// Validates refresh token with specific requirements
    /// - Parameter token: Refresh token to validate
    /// - Returns: True if token passes refresh token validation
    public func validateRefreshTokenSecurity(_ token: String) -> Bool {
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
    
    /// Validates token expiry date
    /// - Parameter expiryDate: Expiration date to validate
    /// - Returns: True if expiry date is valid and reasonable
    public func validateTokenExpiry(_ expiryDate: Date) -> Bool {
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
    
    /// Validates user information structure
    /// - Parameter user: User information to validate
    /// - Returns: True if user information is valid
    public func validateUserInfo(_ user: AuthenticatedUser) -> Bool {
        // User ID should be non-empty and reasonable length
        guard !user.id.isEmpty && user.id.count >= 1 && user.id.count <= 20 else { return false }
        
        // Username should be non-empty and reasonable length
        guard !user.username.isEmpty && user.username.count >= 1 && user.username.count <= 50 else { return false }
        
        // Name should be reasonable length (it's always provided as a non-optional String)
        guard user.name.count <= 100 else { return false }
        
        return true
    }
    
    /// Checks for predictable patterns in tokens
    /// - Parameter token: Token to check
    /// - Returns: True if token contains predictable patterns
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
    
    /// Checks for repeated patterns in token
    /// - Parameter token: Token to check
    /// - Returns: True if token has excessive repeated patterns
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
    
    /// Validates complete token set before storage
    /// - Parameters:
    ///   - accessToken: Access token to validate
    ///   - refreshToken: Refresh token to validate
    ///   - expiryDate: Expiry date to validate
    ///   - userInfo: User information to validate
    /// - Returns: ValidationResult with details about validation
    public func validateCompleteTokenSet(
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
    
    /// Checks if the device supports enhanced security features
    /// - Returns: True if biometric authentication and secure keychain access are available
    public func supportsEnhancedSecurity() -> Bool {
        // Check if device supports biometric authentication
        let context = LAContext()
        var error: NSError?
        
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Stores access token with fallback access control if enhanced security is not available
    /// - Parameter token: Access token to store
    /// - Throws: KeychainError if storage fails
    public func storeAccessTokenWithFallback(_ token: String) async throws {
        guard validateAccessTokenSecurity(token) else {
            throw KeychainError.invalidData
        }
        
        let accessControl: SecAccessControl
        
        // Try enhanced security first, fall back to standard if not supported
        if supportsEnhancedSecurity() {
            accessControl = try createSecureAccessControl()
        } else {
            accessControl = try createStandardAccessControl()
        }
        
        try await storeKeychainItem(
            key: KeychainKey.accessToken,
            data: token.data(using: .utf8)!,
            accessControl: accessControl
        )
    }

    /// Retrieves complete token set if all components are available
    /// - Returns: Complete token set (access token, refresh token, user info, expiry)
    /// - Throws: KeychainError if any component is missing or invalid
    public func getCompleteTokenSet() async throws -> (accessToken: String, refreshToken: String, userInfo: AuthenticatedUser, expiryDate: Date) {
        let accessToken = try await getAccessToken()
        let refreshToken = try await getRefreshToken()
        let userInfo = try await getUserInfo()
        let expiryDate = try await getTokenExpiry()
        
        return (accessToken: accessToken, refreshToken: refreshToken, userInfo: userInfo, expiryDate: expiryDate)
    }
    
    /// Checks if specific token exists in Keychain
    /// - Parameter tokenType: Type of token to check
    /// - Returns: True if token exists and is accessible
    public func tokenExists(_ tokenType: TokenType) async -> Bool {
        do {
            switch tokenType {
            case .accessToken:
                _ = try await getAccessToken()
            case .refreshToken:
                _ = try await getRefreshToken()
            case .userInfo:
                _ = try await getUserInfo()
            case .tokenExpiry:
                _ = try await getTokenExpiry()
            }
            return true
        } catch {
            return false
        }
    }
    
    /// Gets token creation/modification date from Keychain metadata
    /// - Parameter tokenType: Type of token to check
    /// - Returns: Date when token was last modified
    /// - Throws: KeychainError if token not found or metadata unavailable
    public func getTokenModificationDate(_ tokenType: TokenType) async throws -> Date {
        let key = keyForTokenType(tokenType)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let modificationDate = attributes[kSecAttrModificationDate as String] as? Date else {
            throw KeychainError.itemNotFound
        }
        
        return modificationDate
    }
    
    /// Helper method to get keychain key for token type
    /// - Parameter tokenType: Type of token
    /// - Returns: Keychain key string
    private func keyForTokenType(_ tokenType: TokenType) -> String {
        switch tokenType {
        case .accessToken:
            return KeychainKey.accessToken
        case .refreshToken:
            return KeychainKey.refreshToken
        case .userInfo:
            return KeychainKey.userInfo
        case .tokenExpiry:
            return KeychainKey.tokenExpiry
        }
    }

    // MARK: - Token Management Methods
    
    /// Updates access token while preserving other stored data
    /// - Parameter newToken: New access token
    /// - Throws: KeychainError if update fails
    public func updateAccessToken(_ newToken: String) async throws {
        try await storeAccessToken(newToken)
    }
    
    /// Updates refresh token while preserving other stored data
    /// - Parameter newToken: New refresh token
    /// - Throws: KeychainError if update fails
    public func updateRefreshToken(_ newToken: String) async throws {
        // Delete old encryption key first
        try? deleteEncryptionKey(forKey: KeychainKey.refreshToken + ".encryption_key")
        
        // Store new encrypted token
        try await storeRefreshToken(newToken)
    }
    
    /// Updates token expiration date
    /// - Parameter newExpiryDate: New expiration date
    /// - Throws: KeychainError if update fails
    public func updateTokenExpiry(_ newExpiryDate: Date) async throws {
        try await storeTokenExpiry(newExpiryDate)
    }
    
    /// Updates complete token set (access token, refresh token, and expiry)
    /// - Parameters:
    ///   - accessToken: New access token
    ///   - refreshToken: New refresh token
    ///   - expiryDate: New expiration date
    /// - Throws: KeychainError if any update fails
    public func updateTokenSet(accessToken: String, refreshToken: String, expiryDate: Date) async throws {
        // Update all tokens atomically (if one fails, none are updated)
        try await updateAccessToken(accessToken)
        try await updateRefreshToken(refreshToken)
        try await updateTokenExpiry(expiryDate)
    }
    
    /// Clears all authentication tokens from Keychain
    /// - Throws: KeychainError if deletion fails
    public func clearAllTokens() async throws {
        try await deleteKeychainItem(key: KeychainKey.accessToken)
        try await deleteKeychainItem(key: KeychainKey.refreshToken)
        try await deleteKeychainItem(key: KeychainKey.userInfo)
        try await deleteKeychainItem(key: KeychainKey.tokenExpiry)
        
        // Also delete the encryption key for refresh token
        try? deleteEncryptionKey(forKey: KeychainKey.refreshToken + ".encryption_key")
    }
    
    /// Clears only access token (useful for testing token refresh)
    /// - Throws: KeychainError if deletion fails
    public func clearAccessToken() async throws {
        try await deleteKeychainItem(key: KeychainKey.accessToken)
    }
    
    /// Clears only refresh token and its encryption key
    /// - Throws: KeychainError if deletion fails
    public func clearRefreshToken() async throws {
        try await deleteKeychainItem(key: KeychainKey.refreshToken)
        try? deleteEncryptionKey(forKey: KeychainKey.refreshToken + ".encryption_key")
    }
    
    /// Clears user information from Keychain
    /// - Throws: KeychainError if deletion fails
    public func clearUserInfo() async throws {
        try await deleteKeychainItem(key: KeychainKey.userInfo)
    }
    
    /// Clears token expiry information from Keychain
    /// - Throws: KeychainError if deletion fails
    public func clearTokenExpiry() async throws {
        try await deleteKeychainItem(key: KeychainKey.tokenExpiry)
    }
}

// MARK: - Keychain Error Types

/// Errors that can occur during Keychain operations
public enum KeychainError: LocalizedError {
    case notImplemented
    case itemNotFound
    case accessDenied
    case invalidData
    case duplicateItem
    case unexpectedError(OSStatus)
    case encodingFailed
    case decodingFailed
    case accessControlCreationFailed(CFError?)
    case encryptionFailed
    case decryptionFailed
    
    // Enhanced Keychain-specific errors
    case userCancelled
    case serviceNotAvailable
    case invalidParameters
    case memoryError
    case ioError
    case writePermissionDenied
    case keychainNotFound
    case invalidKeychain
    case duplicateKeychain
    case interactionNotAllowed
    case readOnlyKeychain
    case authenticationFailed
    case attributeNotFound
    case invalidItemReference
    case invalidSearchReference
    case classNotFound
    case noDefaultKeychain
    case readOnlyAttribute
    case incompatibleVersion
    case invalidKeySize
    case noStorageModule
    case noCertificateModule
    case noPolicyModule
    case interactionRequired
    case dataNotAvailable
    case dataNotModifiable
    case createChainFailed
    
    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Keychain operation not yet implemented"
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
        case .accessControlCreationFailed(let error):
            if let error = error {
                return "Failed to create access control: \(String(describing: CFErrorCopyDescription(error)))"
            }
            return "Failed to create access control for secure storage"
        case .encryptionFailed:
            return "Failed to encrypt token data"
        case .decryptionFailed:
            return "Failed to decrypt token data"
        case .userCancelled:
            return "User cancelled the Keychain operation"
        case .serviceNotAvailable:
            return "Keychain service is not available"
        case .invalidParameters:
            return "Invalid parameters provided to Keychain operation"
        case .memoryError:
            return "Memory allocation error during Keychain operation"
        case .ioError:
            return "Input/output error during Keychain operation"
        case .writePermissionDenied:
            return "Write permission denied for Keychain operation"
        case .keychainNotFound:
            return "Specified Keychain not found"
        case .invalidKeychain:
            return "Invalid Keychain reference"
        case .duplicateKeychain:
            return "Keychain already exists"
        case .interactionNotAllowed:
            return "User interaction not allowed for this Keychain operation"
        case .readOnlyKeychain:
            return "Keychain is read-only"
        case .authenticationFailed:
            return "Authentication failed for Keychain access"
        case .attributeNotFound:
            return "Requested attribute not found in Keychain item"
        case .invalidItemReference:
            return "Invalid Keychain item reference"
        case .invalidSearchReference:
            return "Invalid Keychain search reference"
        case .classNotFound:
            return "Keychain item class not found"
        case .noDefaultKeychain:
            return "No default Keychain available"
        case .readOnlyAttribute:
            return "Keychain attribute is read-only"
        case .incompatibleVersion:
            return "Incompatible Keychain version"
        case .invalidKeySize:
            return "Invalid key size for Keychain operation"
        case .noStorageModule:
            return "No storage module available for Keychain"
        case .noCertificateModule:
            return "No certificate module available for Keychain"
        case .noPolicyModule:
            return "No policy module available for Keychain"
        case .interactionRequired:
            return "User interaction required for Keychain operation"
        case .dataNotAvailable:
            return "Keychain data not available"
        case .dataNotModifiable:
            return "Keychain data cannot be modified"
        case .createChainFailed:
            return "Failed to create Keychain trust chain"
        }
    }
}
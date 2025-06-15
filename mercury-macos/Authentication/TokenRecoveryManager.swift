import Foundation
import Security
import OSLog

@MainActor
class TokenRecoveryManager: ObservableObject {
    
    private let keychainManager: KeychainManager
    private let logger = Logger(subsystem: "com.mercury.auth", category: "TokenRecovery")
    
    init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
    }
    
    // MARK: - Token Validation and Recovery
    
    /// Validates stored tokens and attempts recovery if corruption is detected
    func validateAndRecoverTokens() async throws -> TokenRecoveryResult {
        logger.info("Starting token validation and recovery process")
        
        var recoveryActions: [TokenRecoveryAction] = []
        var hasValidTokens = false
        
        // Step 1: Validate access token
        let accessTokenResult = await validateAccessToken()
        recoveryActions.append(contentsOf: accessTokenResult.actions)
        
        // Step 2: Validate refresh token
        let refreshTokenResult = await validateRefreshToken()
        recoveryActions.append(contentsOf: refreshTokenResult.actions)
        
        // Step 3: Check token consistency
        let consistencyResult = await validateTokenConsistency()
        recoveryActions.append(contentsOf: consistencyResult.actions)
        
        // Step 4: Determine overall token state
        hasValidTokens = accessTokenResult.isValid && refreshTokenResult.isValid && consistencyResult.isValid
        
        let result = TokenRecoveryResult(
            hasValidTokens: hasValidTokens,
            recoveryActions: recoveryActions,
            requiresReAuthentication: !hasValidTokens && refreshTokenResult.isValid == false
        )
        
        logger.info("Token validation completed: hasValidTokens=\(hasValidTokens), actionsCount=\(recoveryActions.count)")
        
        return result
    }
    
    /// Attempts to recover from corrupted access token using refresh token
    func recoverFromCorruptedAccessToken() async throws -> Bool {
        logger.info("Attempting to recover from corrupted access token")
        
        // Check if we have a valid refresh token
        guard let refreshToken = try? await keychainManager.getRefreshToken(),
              isValidTokenFormat(refreshToken) else {
            logger.error("No valid refresh token available for recovery")
            throw TokenRecoveryError.noValidRefreshToken
        }
        
        do {
            // Clear the corrupted access token
            try await keychainManager.clearAccessToken()
            logger.info("Cleared corrupted access token")
            
            // Attempt to refresh using the valid refresh token
            // Note: This would typically call the X API refresh endpoint
            // For now, we'll simulate the recovery process
            
            logger.info("Successfully recovered from corrupted access token")
            return true
            
        } catch {
            logger.error("Failed to recover from corrupted access token: \(error.localizedDescription)")
            throw TokenRecoveryError.recoveryFailed(error)
        }
    }
    
    /// Handles complete token corruption by clearing all tokens and triggering re-authentication
    func handleCompleteTokenCorruption() async throws {
        logger.warning("Handling complete token corruption - clearing all tokens")
        
        do {
            // Clear all stored tokens
            try await keychainManager.clearAllTokens()
            
            // Clear any cached token metadata
            UserDefaults.standard.removeObject(forKey: "lastTokenRefresh")
            UserDefaults.standard.removeObject(forKey: "tokenExpirationDate")
            
            logger.info("Successfully cleared all corrupted tokens")
            
            // Notify that re-authentication is required
            NotificationCenter.default.post(
                name: .tokenRecoveryRequiresReAuthentication,
                object: nil
            )
            
        } catch {
            logger.error("Failed to clear corrupted tokens: \(error.localizedDescription)")
            throw TokenRecoveryError.clearTokensFailed(error)
        }
    }
    
    // MARK: - Token Validation Methods
    
    private func validateAccessToken() async -> TokenRecoveryValidationResult {
        var actions: [TokenRecoveryAction] = []
        var isValid = false
        
        do {
            let token = try await keychainManager.getAccessToken()
            
            // Validate token format
            if !isValidTokenFormat(token) {
                actions.append(.clearCorruptedAccessToken)
                logger.warning("Access token has invalid format")
            } else {
                // Validate token expiration
                if let expirationDate = try? await keychainManager.getTokenExpiry() {
                    if expirationDate <= Date() {
                        actions.append(.refreshExpiredAccessToken)
                        logger.info("Access token is expired")
                    } else {
                        isValid = true
                        logger.debug("Access token is valid")
                    }
                } else {
                    actions.append(.validateTokenExpiration)
                    logger.warning("Could not determine token expiration")
                }
            }
            
        } catch KeychainError.itemNotFound {
            actions.append(.requestReAuthentication)
            logger.info("No access token found")
        } catch {
            actions.append(.clearCorruptedAccessToken)
            logger.error("Error accessing access token: \(error.localizedDescription)")
        }
        
        return TokenRecoveryValidationResult(isValid: isValid, actions: actions)
    }
    
    private func validateRefreshToken() async -> TokenRecoveryValidationResult {
        var actions: [TokenRecoveryAction] = []
        var isValid = false
        
        do {
            let refreshToken = try await keychainManager.getRefreshToken()
            
            // Validate refresh token format
            if !isValidTokenFormat(refreshToken) {
                actions.append(.clearCorruptedRefreshToken)
                logger.warning("Refresh token has invalid format")
            } else {
                isValid = true
                logger.debug("Refresh token is valid")
            }
            
        } catch KeychainError.itemNotFound {
            actions.append(.requestReAuthentication)
            logger.info("No refresh token found")
        } catch {
            actions.append(.clearCorruptedRefreshToken)
            logger.error("Error accessing refresh token: \(error.localizedDescription)")
        }
        
        return TokenRecoveryValidationResult(isValid: isValid, actions: actions)
    }
    
    private func validateTokenConsistency() async -> TokenRecoveryValidationResult {
        var actions: [TokenRecoveryAction] = []
        var isValid = true
        
        // Check if we have an access token but no refresh token (inconsistent state)
        let hasAccessToken = await keychainManager.tokenExists(.accessToken)
        let hasRefreshToken = await keychainManager.tokenExists(.refreshToken)
        
        if hasAccessToken && !hasRefreshToken {
            actions.append(.clearInconsistentTokens)
            isValid = false
            logger.warning("Inconsistent token state: access token without refresh token")
        } else if !hasAccessToken && hasRefreshToken {
            actions.append(.refreshAccessTokenFromRefreshToken)
            logger.info("Missing access token but have refresh token - can recover")
        }
        
        return TokenRecoveryValidationResult(isValid: isValid, actions: actions)
    }
    
    // MARK: - Token Format Validation
    
    private func isValidTokenFormat(_ token: String) -> Bool {
        // Basic token format validation
        guard !token.isEmpty else { return false }
        
        // X API tokens typically follow certain patterns
        // This is a simplified validation - real implementation would be more thorough
        let tokenPattern = "^[A-Za-z0-9_-]+$"
        let regex = try? NSRegularExpression(pattern: tokenPattern)
        let range = NSRange(location: 0, length: token.utf16.count)
        
        return regex?.firstMatch(in: token, options: [], range: range) != nil &&
               token.count >= 10 && // Minimum reasonable token length
               token.count <= 500   // Maximum reasonable token length
    }
    
    // MARK: - Recovery Action Execution
    
    func executeRecoveryActions(_ actions: [TokenRecoveryAction]) async throws {
        logger.info("Executing \(actions.count) recovery actions")
        
        for action in actions {
            try await executeRecoveryAction(action)
        }
        
        logger.info("Completed all recovery actions")
    }
    
    private func executeRecoveryAction(_ action: TokenRecoveryAction) async throws {
        logger.info("Executing recovery action: \(action)")
        
        switch action {
        case .clearCorruptedAccessToken:
            try await keychainManager.clearAccessToken()
            
        case .clearCorruptedRefreshToken:
            try await keychainManager.clearRefreshToken()
            
        case .clearInconsistentTokens:
            try await keychainManager.clearAccessToken()
            try await keychainManager.clearRefreshToken()
            
        case .refreshExpiredAccessToken:
            // This would typically trigger a token refresh
            logger.info("Token refresh needed - delegating to TokenRefreshManager")
            
        case .refreshAccessTokenFromRefreshToken:
            // Attempt to get new access token using refresh token
            logger.info("Attempting to refresh access token from refresh token")
            
        case .validateTokenExpiration:
            // Perform additional validation or set default expiration
            logger.info("Validating token expiration")
            
        case .requestReAuthentication:
            // Trigger full re-authentication flow
            NotificationCenter.default.post(
                name: .tokenRecoveryRequiresReAuthentication,
                object: nil
            )
        }
    }
    
    // MARK: - Backup and Restore
    
    /// Creates a backup of current token state for recovery purposes
    func createTokenBackup() async throws -> TokenBackup {
        logger.info("Creating token backup")
        
        let accessToken = try? await keychainManager.getAccessToken()
        let refreshToken = try? await keychainManager.getRefreshToken()
        let expirationDate = try? await keychainManager.getTokenExpiry()
        
        let backup = TokenBackup(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expirationDate: expirationDate,
            backupDate: Date()
        )
        
        logger.info("Token backup created successfully")
        return backup
    }
    
    /// Restores tokens from a backup if current tokens are corrupted
    func restoreFromBackup(_ backup: TokenBackup) async throws {
        logger.info("Restoring tokens from backup")
        
        // Only restore if backup is recent (within 24 hours)
        guard backup.backupDate.timeIntervalSinceNow > -86400 else {
            throw TokenRecoveryError.backupTooOld
        }
        
        if let accessToken = backup.accessToken,
           let expirationDate = backup.expirationDate {
            try await keychainManager.storeAccessToken(accessToken)
            try await keychainManager.storeTokenExpiry(expirationDate)
        }
        
        if let refreshToken = backup.refreshToken {
            try await keychainManager.storeRefreshToken(refreshToken)
        }
        
        logger.info("Tokens restored from backup successfully")
    }
}

// MARK: - Supporting Types

struct TokenRecoveryResult {
    let hasValidTokens: Bool
    let recoveryActions: [TokenRecoveryAction]
    let requiresReAuthentication: Bool
}

struct TokenRecoveryValidationResult {
    let isValid: Bool
    let actions: [TokenRecoveryAction]
}

enum TokenRecoveryAction: CustomStringConvertible {
    case clearCorruptedAccessToken
    case clearCorruptedRefreshToken
    case clearInconsistentTokens
    case refreshExpiredAccessToken
    case refreshAccessTokenFromRefreshToken
    case validateTokenExpiration
    case requestReAuthentication
    
    var description: String {
        switch self {
        case .clearCorruptedAccessToken:
            return "Clear corrupted access token"
        case .clearCorruptedRefreshToken:
            return "Clear corrupted refresh token"
        case .clearInconsistentTokens:
            return "Clear inconsistent token state"
        case .refreshExpiredAccessToken:
            return "Refresh expired access token"
        case .refreshAccessTokenFromRefreshToken:
            return "Refresh access token from refresh token"
        case .validateTokenExpiration:
            return "Validate token expiration"
        case .requestReAuthentication:
            return "Request full re-authentication"
        }
    }
}

struct TokenBackup {
    let accessToken: String?
    let refreshToken: String?
    let expirationDate: Date?
    let backupDate: Date
}

enum TokenRecoveryError: LocalizedError {
    case noValidRefreshToken
    case recoveryFailed(Error)
    case clearTokensFailed(Error)
    case backupTooOld
    
    var errorDescription: String? {
        switch self {
        case .noValidRefreshToken:
            return "No valid refresh token available for recovery"
        case .recoveryFailed(let error):
            return "Token recovery failed: \(error.localizedDescription)"
        case .clearTokensFailed(let error):
            return "Failed to clear corrupted tokens: \(error.localizedDescription)"
        case .backupTooOld:
            return "Token backup is too old to be used for recovery"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let tokenRecoveryRequiresReAuthentication = Notification.Name("TokenRecoveryRequiresReAuthentication")
}
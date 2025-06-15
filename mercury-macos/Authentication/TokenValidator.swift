import Foundation
import Combine

// MARK: - Token Validator

/// Comprehensive token validation system for critical operations
/// Provides multi-level validation with different strategies based on operation criticality
@MainActor
public class TokenValidator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let keychainManager: KeychainManager
    private let tokenRefreshManager: TokenRefreshManager
    private weak var authManager: AuthManager?
    
    // MARK: - Validation Configuration
    
    /// Configuration for different validation levels
    public struct ValidationConfig {
        public let level: ValidationLevel
        public let allowCachedResults: Bool
        public let maxCacheAge: TimeInterval
        public let performAPIValidation: Bool
        public let retryOnFailure: Bool
        
        public init(
            level: ValidationLevel = .standard,
            allowCachedResults: Bool = true,
            maxCacheAge: TimeInterval = 60, // 1 minute
            performAPIValidation: Bool = false,
            retryOnFailure: Bool = true
        ) {
            self.level = level
            self.allowCachedResults = allowCachedResults
            self.maxCacheAge = maxCacheAge
            self.performAPIValidation = performAPIValidation
            self.retryOnFailure = retryOnFailure
        }
        
        /// Quick validation for non-critical operations
        public static let quick = ValidationConfig(
            level: .basic,
            allowCachedResults: true,
            maxCacheAge: 300, // 5 minutes
            performAPIValidation: false,
            retryOnFailure: false
        )
        
        /// Standard validation for normal operations
        public static let standard = ValidationConfig(
            level: .standard,
            allowCachedResults: true,
            maxCacheAge: 60, // 1 minute
            performAPIValidation: false,
            retryOnFailure: true
        )
        
        /// Comprehensive validation for critical operations
        public static let critical = ValidationConfig(
            level: .comprehensive,
            allowCachedResults: false,
            maxCacheAge: 0,
            performAPIValidation: true,
            retryOnFailure: true
        )
    }
    
    /// Validation depth levels
    public enum ValidationLevel: Int, CaseIterable {
        case basic = 1          // Token exists and format check
        case standard = 2       // Basic + expiry check
        case comprehensive = 3  // Standard + API validation
    }
    
    // MARK: - Validation Results
    
    /// Comprehensive validation result
    public struct ValidationResult {
        public let isValid: Bool
        public let status: ValidationStatus
        public let details: ValidationDetails
        public let timestamp: Date
        public let recommendations: [ValidationRecommendation]
        
        public init(
            isValid: Bool,
            status: ValidationStatus,
            details: ValidationDetails,
            timestamp: Date = Date(),
            recommendations: [ValidationRecommendation] = []
        ) {
            self.isValid = isValid
            self.status = status
            self.details = details
            self.timestamp = timestamp
            self.recommendations = recommendations
        }
    }
    
    /// Validation status types
    public enum ValidationStatus {
        case valid
        case expired
        case invalid
        case missing
        case networkError
        case refreshRequired
        case authenticationRequired
    }
    
    /// Detailed validation information
    public struct ValidationDetails {
        public let hasAccessToken: Bool
        public let hasRefreshToken: Bool
        public let accessTokenExpiry: Date?
        public let timeUntilExpiry: TimeInterval?
        public let lastValidation: Date?
        public let validationLevel: ValidationLevel
        public let apiValidationPerformed: Bool
        public let cacheUsed: Bool
        
        public init(
            hasAccessToken: Bool,
            hasRefreshToken: Bool,
            accessTokenExpiry: Date? = nil,
            timeUntilExpiry: TimeInterval? = nil,
            lastValidation: Date? = nil,
            validationLevel: ValidationLevel,
            apiValidationPerformed: Bool = false,
            cacheUsed: Bool = false
        ) {
            self.hasAccessToken = hasAccessToken
            self.hasRefreshToken = hasRefreshToken
            self.accessTokenExpiry = accessTokenExpiry
            self.timeUntilExpiry = timeUntilExpiry
            self.lastValidation = lastValidation
            self.validationLevel = validationLevel
            self.apiValidationPerformed = apiValidationPerformed
            self.cacheUsed = cacheUsed
        }
    }
    
    /// Validation recommendations
    public enum ValidationRecommendation {
        case refreshTokenNow
        case reauthenticateRequired
        case waitForNetwork
        case retryOperation
        case proceedWithCaution
        case operationBlocked
        
        public var description: String {
            switch self {
            case .refreshTokenNow:
                return "Token should be refreshed before proceeding"
            case .reauthenticateRequired:
                return "Full re-authentication is required"
            case .waitForNetwork:
                return "Wait for network connectivity before proceeding"
            case .retryOperation:
                return "Retry the validation operation"
            case .proceedWithCaution:
                return "Proceed but monitor for authentication errors"
            case .operationBlocked:
                return "Operation should not proceed"
            }
        }
    }
    
    // MARK: - Cache Management
    
    private struct ValidationCache {
        let result: ValidationResult
        let timestamp: Date
        let config: ValidationConfig
    }
    
    private var validationCache: ValidationCache?
    private let cacheQueue = DispatchQueue(label: "com.mercury.tokenvalidator.cache", qos: .utility)
    
    // MARK: - Initialization
    
    public init(keychainManager: KeychainManager, tokenRefreshManager: TokenRefreshManager, authManager: AuthManager? = nil) {
        self.keychainManager = keychainManager
        self.tokenRefreshManager = tokenRefreshManager
        self.authManager = authManager
    }
    
    // MARK: - Main Validation Methods
    
    /// Validates token for critical operations (posting tweets)
    /// - Parameter config: Validation configuration
    /// - Returns: Comprehensive validation result
    public func validateForCriticalOperation(config: ValidationConfig = .critical) async -> ValidationResult {
        print("🔍 Starting critical operation token validation (level: \(config.level))")
        
        // Check cache first if allowed
        if config.allowCachedResults, let cachedResult = getCachedResult(maxAge: config.maxCacheAge, level: config.level) {
            print("✅ Using cached validation result")
            return cachedResult
        }
        
        // Perform fresh validation
        let result = await performValidation(config: config)
        
        // Cache the result
        cacheResult(result, config: config)
        
        // Log result
        logValidationResult(result)
        
        return result
    }
    
    /// Quick validation for non-critical operations
    /// - Returns: Simple boolean result
    public func isTokenValid() async -> Bool {
        let result = await validateForCriticalOperation(config: .quick)
        return result.isValid
    }
    
    /// Validates token with automatic refresh if needed
    /// - Parameter config: Validation configuration
    /// - Returns: Validation result after potential refresh
    public func validateWithAutoRefresh(config: ValidationConfig = .standard) async -> ValidationResult {
        print("🔄 Validating token with auto-refresh capability")
        
        let initialResult = await validateForCriticalOperation(config: config)
        
        // If token is expired but refresh is available, attempt refresh
        if initialResult.status == .expired || initialResult.status == .refreshRequired {
            if initialResult.details.hasRefreshToken && config.retryOnFailure {
                print("🔄 Token expired, attempting automatic refresh...")
                
                // Attempt token refresh
                if let authManager = authManager {
                    let refreshResult = await authManager.refreshTokens()
                    
                    switch refreshResult {
                    case .success:
                        print("✅ Token refresh successful, re-validating...")
                        // Re-validate after successful refresh
                        return await validateForCriticalOperation(config: config)
                        
                    case .failure(let error):
                        print("❌ Token refresh failed: \(error)")
                        return ValidationResult(
                            isValid: false,
                            status: .authenticationRequired,
                            details: initialResult.details,
                            recommendations: [.reauthenticateRequired]
                        )
                    }
                } else {
                    return ValidationResult(
                        isValid: false,
                        status: .authenticationRequired,
                        details: initialResult.details,
                        recommendations: [.reauthenticateRequired]
                    )
                }
            }
        }
        
        return initialResult
    }
    
    /// Validates token and gets recommendations for next steps
    /// - Parameter config: Validation configuration
    /// - Returns: Validation result with actionable recommendations
    public func validateWithRecommendations(config: ValidationConfig = .standard) async -> ValidationResult {
        let result = await validateForCriticalOperation(config: config)
        let recommendations = generateRecommendations(from: result)
        
        return ValidationResult(
            isValid: result.isValid,
            status: result.status,
            details: result.details,
            timestamp: result.timestamp,
            recommendations: recommendations
        )
    }
    
    // MARK: - Validation Implementation
    
    private func performValidation(config: ValidationConfig) async -> ValidationResult {
        var hasAccessToken = false
        var hasRefreshToken = false
        var accessTokenExpiry: Date?
        var timeUntilExpiry: TimeInterval?
        var apiValidationPerformed = false
        
        do {
            // Step 1: Check for access token existence
            let accessToken = try await keychainManager.getAccessToken()
            hasAccessToken = !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            if config.level == .basic {
                // Basic validation: just check token exists
                let status: ValidationStatus = hasAccessToken ? .valid : .missing
                let details = ValidationDetails(
                    hasAccessToken: hasAccessToken,
                    hasRefreshToken: false, // Not checked in basic mode
                    validationLevel: .basic
                )
                return ValidationResult(isValid: hasAccessToken, status: status, details: details)
            }
            
            // Step 2: Check refresh token (for standard and comprehensive)
            do {
                let refreshToken = try await keychainManager.getRefreshToken()
                hasRefreshToken = !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } catch {
                hasRefreshToken = false
            }
            
            // Step 3: Check token expiry
            do {
                accessTokenExpiry = try await tokenRefreshManager.getTokenExpiry()
                if let expiry = accessTokenExpiry {
                    timeUntilExpiry = expiry.timeIntervalSinceNow
                    
                    // Check if token is expired
                    if timeUntilExpiry! <= 0 {
                        let details = ValidationDetails(
                            hasAccessToken: hasAccessToken,
                            hasRefreshToken: hasRefreshToken,
                            accessTokenExpiry: accessTokenExpiry,
                            timeUntilExpiry: timeUntilExpiry,
                            validationLevel: config.level
                        )
                        return ValidationResult(isValid: false, status: .expired, details: details)
                    }
                    
                    // Check if token needs refresh soon (within 15 minutes)
                    if timeUntilExpiry! <= 15 * 60 {
                        let details = ValidationDetails(
                            hasAccessToken: hasAccessToken,
                            hasRefreshToken: hasRefreshToken,
                            accessTokenExpiry: accessTokenExpiry,
                            timeUntilExpiry: timeUntilExpiry,
                            validationLevel: config.level
                        )
                        return ValidationResult(isValid: false, status: .refreshRequired, details: details)
                    }
                }
            } catch {
                print("⚠️ Unable to check token expiry: \(error)")
            }
            
            // Step 4: API validation for comprehensive level
            if config.level == .comprehensive && config.performAPIValidation {
                apiValidationPerformed = true
                let apiValidationResult = await performAPIValidation(accessToken: accessToken)
                
                if !apiValidationResult {
                    let details = ValidationDetails(
                        hasAccessToken: hasAccessToken,
                        hasRefreshToken: hasRefreshToken,
                        accessTokenExpiry: accessTokenExpiry,
                        timeUntilExpiry: timeUntilExpiry,
                        validationLevel: config.level,
                        apiValidationPerformed: true
                    )
                    return ValidationResult(isValid: false, status: .invalid, details: details)
                }
            }
            
            // Token is valid
            let details = ValidationDetails(
                hasAccessToken: hasAccessToken,
                hasRefreshToken: hasRefreshToken,
                accessTokenExpiry: accessTokenExpiry,
                timeUntilExpiry: timeUntilExpiry,
                lastValidation: Date(),
                validationLevel: config.level,
                apiValidationPerformed: apiValidationPerformed
            )
            
            return ValidationResult(isValid: true, status: .valid, details: details)
            
        } catch {
            print("❌ Token validation failed: \(error)")
            
            // Determine appropriate status based on error
            let status: ValidationStatus = hasAccessToken ? .invalid : .missing
            
            let details = ValidationDetails(
                hasAccessToken: hasAccessToken,
                hasRefreshToken: hasRefreshToken,
                accessTokenExpiry: accessTokenExpiry,
                timeUntilExpiry: timeUntilExpiry,
                validationLevel: config.level,
                apiValidationPerformed: apiValidationPerformed
            )
            
            return ValidationResult(isValid: false, status: status, details: details)
        }
    }
    
    /// Performs API validation by making a test call
    private func performAPIValidation(accessToken: String) async -> Bool {
        do {
            guard let authManager = authManager else {
                print("⚠️ AuthManager not available for API validation")
                return false
            }
            
            // Create API client and test token
            let apiClient = authManager.createXAPIClient()
            try apiClient.setAccessToken(accessToken)
            let _ = try await apiClient.getCurrentUser()
            
            print("✅ API validation successful")
            return true
            
        } catch {
            print("❌ API validation failed: \(error)")
            return false
        }
    }
    
    // MARK: - Cache Management
    
    private func getCachedResult(maxAge: TimeInterval, level: ValidationLevel) -> ValidationResult? {
        return cacheQueue.sync { () -> ValidationResult? in
            guard let cache = validationCache else { return nil }
            
            let age = Date().timeIntervalSince(cache.timestamp)
            guard age <= maxAge else {
                // Cache is too old
                validationCache = nil
                return nil
            }
            
            // Ensure cache level matches or exceeds required level
            guard cache.config.level.rawValue >= level.rawValue else {
                return nil
            }
            
            let updatedDetails = ValidationDetails(
                hasAccessToken: cache.result.details.hasAccessToken,
                hasRefreshToken: cache.result.details.hasRefreshToken,
                accessTokenExpiry: cache.result.details.accessTokenExpiry,
                timeUntilExpiry: cache.result.details.timeUntilExpiry,
                lastValidation: cache.result.details.lastValidation,
                validationLevel: cache.result.details.validationLevel,
                apiValidationPerformed: cache.result.details.apiValidationPerformed,
                cacheUsed: true
            )
            
            let cachedResult = ValidationResult(
                isValid: cache.result.isValid,
                status: cache.result.status,
                details: updatedDetails,
                timestamp: cache.result.timestamp,
                recommendations: cache.result.recommendations
            )
            
            return cachedResult
        }
    }
    
    private func cacheResult(_ result: ValidationResult, config: ValidationConfig) {
        cacheQueue.async {
            self.validationCache = ValidationCache(
                result: result,
                timestamp: Date(),
                config: config
            )
        }
    }
    
    /// Clears validation cache (useful when tokens are refreshed)
    public func clearCache() {
        cacheQueue.async {
            self.validationCache = nil
        }
    }
    
    // MARK: - Recommendation Generation
    
    private func generateRecommendations(from result: ValidationResult) -> [ValidationRecommendation] {
        var recommendations: [ValidationRecommendation] = []
        
        switch result.status {
        case .valid:
            if let timeUntilExpiry = result.details.timeUntilExpiry, timeUntilExpiry <= 30 * 60 { // 30 minutes
                recommendations.append(.proceedWithCaution)
            }
            
        case .expired:
            if result.details.hasRefreshToken {
                recommendations.append(.refreshTokenNow)
            } else {
                recommendations.append(.reauthenticateRequired)
            }
            
        case .refreshRequired:
            recommendations.append(.refreshTokenNow)
            
        case .invalid:
            if result.details.hasRefreshToken {
                recommendations.append(.refreshTokenNow)
            } else {
                recommendations.append(.reauthenticateRequired)
            }
            
        case .missing:
            recommendations.append(.reauthenticateRequired)
            recommendations.append(.operationBlocked)
            
        case .networkError:
            recommendations.append(.waitForNetwork)
            recommendations.append(.retryOperation)
            
        case .authenticationRequired:
            recommendations.append(.reauthenticateRequired)
            recommendations.append(.operationBlocked)
        }
        
        return recommendations
    }
    
    // MARK: - Logging and Monitoring
    
    private func logValidationResult(_ result: ValidationResult) {
        let statusEmoji: String
        switch result.status {
        case .valid:
            statusEmoji = "✅"
        case .expired, .refreshRequired:
            statusEmoji = "⏰"
        case .invalid, .missing, .authenticationRequired:
            statusEmoji = "❌"
        case .networkError:
            statusEmoji = "🌐"
        }
        
        print("\(statusEmoji) Token validation complete:")
        print("  Status: \(result.status)")
        print("  Valid: \(result.isValid)")
        print("  Level: \(result.details.validationLevel)")
        print("  Has Access Token: \(result.details.hasAccessToken)")
        print("  Has Refresh Token: \(result.details.hasRefreshToken)")
        
        if let expiry = result.details.accessTokenExpiry, let timeUntil = result.details.timeUntilExpiry {
            print("  Expires: \(expiry.formatted(.relative(presentation: .named)))")
            print("  Time Until Expiry: \(Int(timeUntil / 60)) minutes")
        }
        
        if !result.recommendations.isEmpty {
            print("  Recommendations:")
            for recommendation in result.recommendations {
                print("    - \(recommendation.description)")
            }
        }
    }
}

// MARK: - Validation Level Comparable

extension TokenValidator.ValidationLevel: Comparable {
    public static func < (lhs: TokenValidator.ValidationLevel, rhs: TokenValidator.ValidationLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
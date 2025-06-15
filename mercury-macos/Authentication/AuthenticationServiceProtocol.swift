import Foundation
import Combine

/// Protocol defining the authentication service interface for dependency injection in the core Mercury app
/// This protocol abstracts the authentication implementation details and provides a clean interface
/// for the core app to interact with authentication functionality without tight coupling
@MainActor
public protocol AuthenticationServiceProtocol: ObservableObject, PostingQueueCoordinationProtocol, ErrorEventEmissionProtocol, NetworkStateCoordinationProtocol, RateLimitStatusCoordinationProtocol {
    
    // MARK: - Published Properties for Reactive UI
    
    /// Current authentication state for reactive UI updates
    var authenticationState: AuthenticationState { get }
    
    /// Current authenticated user information
    var currentUser: AuthenticatedUser? { get }
    
    /// Rate limit information for user awareness
    var rateLimitInfo: RateLimitInfo { get }
    
    /// Number of queued posts waiting for retry
    var queuedPostsCount: Int { get }
    
    // MARK: - Combine Publishers for State Observation
    
    /// Publisher for authentication state changes
    var authenticationStatePublisher: AnyPublisher<AuthenticationState, Never> { get }
    
    /// Publisher for current user changes
    var currentUserPublisher: AnyPublisher<AuthenticatedUser?, Never> { get }
    
    /// Publisher for rate limit information changes
    var rateLimitInfoPublisher: AnyPublisher<RateLimitInfo, Never> { get }
    
    /// Publisher for queued posts count changes
    var queuedPostsCountPublisher: AnyPublisher<Int, Never> { get }
    
    /// Combined state publisher for comprehensive state monitoring
    var combinedStatePublisher: AnyPublisher<(AuthenticationState, AuthenticatedUser?, RateLimitInfo, Int), Never> { get }
    
    /// Publisher for authentication state change notifications with detailed context
    var stateChangeNotifications: AnyPublisher<AuthenticationStateChangeNotification, Never> { get }
    
    /// Publisher for critical authentication events requiring immediate attention
    var criticalNotifications: AnyPublisher<AuthenticationStateChangeNotification, Never> { get }
    
    // MARK: - Core Authentication Methods
    
    /// Initiates the OAuth 2.0 + PKCE authentication flow
    /// - Returns: Result indicating success with user info or failure with error details
    func authenticate() async -> AuthenticationResult
    
    /// Posts a tweet to X API with automatic retry and queuing
    /// - Parameter text: Tweet content (max 280 characters)
    /// - Returns: Result indicating success with tweet details or failure with error
    func postTweet(_ text: String) async -> TweetPostResult
    
    /// Checks if user is currently authenticated with valid tokens
    /// - Returns: True if authenticated and tokens are valid
    func isAuthenticated() -> Bool
    
    /// Disconnects the user and clears all stored authentication data
    /// - Returns: Result indicating success or failure with error details
    func disconnect() async -> DisconnectionResult
    
    // MARK: - User Information Methods
    
    /// Gets current user information if authenticated
    /// - Returns: User information or nil if not authenticated
    func getCurrentUser() -> AuthenticatedUser?
    
    /// Gets current rate limit information
    /// - Returns: Rate limit details including remaining quota
    func getRateLimitInfo() -> RateLimitInfo
    
    // MARK: - State Observation Methods
    
    /// Subscribe to authentication state changes with a completion handler
    /// - Parameter handler: Called whenever authentication state changes
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeAuthenticationState(_ handler: @escaping (AuthenticationState) -> Void) -> AnyCancellable
    
    /// Subscribe to state changes for specific states
    /// - Parameters:
    ///   - states: Array of states to watch for
    ///   - handler: Called when state changes to one of the specified states
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeStates(_ states: [AuthenticationState], handler: @escaping (AuthenticationState) -> Void) -> AnyCancellable
    
    /// Subscribe to authentication success events
    /// - Parameter handler: Called when authentication succeeds with user info
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeAuthenticationSuccess(_ handler: @escaping (AuthenticatedUser) -> Void) -> AnyCancellable
    
    /// Subscribe to authentication errors
    /// - Parameter handler: Called when authentication fails with error details
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeAuthenticationErrors(_ handler: @escaping (AuthenticationError) -> Void) -> AnyCancellable
    
    /// Subscribe to disconnection events
    /// - Parameter handler: Called when user is disconnected
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeDisconnection(_ handler: @escaping () -> Void) -> AnyCancellable
    
    // MARK: - Queue Management Methods
    // Note: Queue management methods are inherited from PostingQueueCoordinationProtocol
    
    // MARK: - Re-authentication Methods
    
    /// Starts user-initiated re-authentication flow
    /// - Returns: Result indicating success with user info or failure with error
    func startReauthentication() async -> AuthenticationResult
    
    /// Performs fallback authentication flow for expired refresh tokens
    /// - Parameters:
    ///   - reason: Reason for the fallback authentication
    ///   - preserveQueuedPosts: Whether to preserve queued posts during re-auth
    /// - Returns: Result indicating success or need for manual intervention
    func performFallbackAuthentication(reason: String, preserveQueuedPosts: Bool) async -> AuthenticationResult
    
    /// Checks if fallback authentication flow is recommended
    /// - Returns: True if fallback flow should be initiated
    func shouldUseFallbackAuthentication() -> Bool
    
    /// Restores preserved posts after successful manual re-authentication
    func restorePreservedPosts() async
    
    // MARK: - Error Messaging Methods
    
    /// Gets user-friendly error message for the current authentication state
    /// - Returns: Error message if in error state, nil otherwise
    func getCurrentErrorMessage() -> AuthenticationErrorMessaging.ErrorMessage?
    
    /// Gets user-friendly error message for a specific authentication error
    /// - Parameter error: The authentication error
    /// - Returns: User-friendly error message
    func getErrorMessage(for error: AuthenticationError) -> AuthenticationErrorMessaging.ErrorMessage
    
    /// Gets user-friendly error message for a specific tweet posting error
    /// - Parameter error: The tweet posting error
    /// - Returns: User-friendly error message
    func getErrorMessage(for error: TweetPostError) -> AuthenticationErrorMessaging.ErrorMessage
    
    /// Gets user-friendly error message for a specific token refresh error
    /// - Parameter error: The token refresh error
    /// - Returns: User-friendly error message
    func getErrorMessage(for error: TokenRefreshError) -> AuthenticationErrorMessaging.ErrorMessage
    
    /// Gets a comprehensive status message for the current authentication state
    /// - Returns: Status message describing current state and any issues
    func getStatusMessage() -> String
    
    /// Gets detailed expiration information for current tokens
    /// - Returns: Expiration status message
    func getTokenExpirationMessage() -> String?
    
    // MARK: - Token Validation Methods
    
    /// Validates token for critical operations with comprehensive checks
    /// - Parameter operationType: Type of operation being performed
    /// - Returns: Validation result with recommendations
    func validateTokenForCriticalOperation(_ operationType: CriticalOperationType) async -> TokenValidator.ValidationResult
    
    /// Quick token validation for non-critical operations
    /// - Returns: Simple boolean indicating if token is valid
    func isTokenValidForOperation() async -> Bool
    
    /// Validates token and provides recommendations for next steps
    /// - Returns: Validation result with actionable recommendations
    func validateTokenWithRecommendations() async -> TokenValidator.ValidationResult
    
    /// Pre-validates token before starting a critical operation
    /// - Parameter operationType: Type of operation being planned
    /// - Returns: Pre-validation result indicating readiness
    func preValidateTokenForOperation(_ operationType: CriticalOperationType) async -> TokenPreValidationResult
    
    /// Ensures token is valid for immediate use with automatic remediation
    /// - Parameter operationType: Type of operation requiring valid token
    /// - Returns: Final validation result after all remediation attempts
    func ensureTokenValidForOperation(_ operationType: CriticalOperationType) async -> TokenValidator.ValidationResult
    
    /// Clears token validation cache (useful after token changes)
    func clearTokenValidationCache()
    
    /// Gets the current token validation status for UI display
    /// - Returns: Current validation details for status display
    func getCurrentTokenValidationStatus() async -> TokenValidator.ValidationResult
    
    /// Validates token with detailed information for debugging/monitoring
    /// - Returns: Comprehensive validation result with all details
    func getDetailedTokenValidation() async -> TokenValidator.ValidationResult
    
    /// Checks if a specific operation can proceed based on current token state
    /// - Parameter operationType: Type of operation to check
    /// - Returns: Whether the operation can proceed
    func canPerformOperation(_ operationType: CriticalOperationType) async -> Bool
    
    // MARK: - App Lifecycle Coordination Methods
    
    /// Prepares the authentication service for app backgrounding
    /// Ensures critical operations are completed and background refresh is configured
    func prepareForBackground() async
    
    /// Handles app returning to foreground
    /// Resumes normal operations and checks for needed refreshes
    func handleForegroundRestore() async
    
    /// Prepares the authentication service for app termination
    /// Ensures critical state is saved before app exits
    func prepareForTermination() async
    
    /// Handles system sleep events
    /// Coordinates authentication operations with system power management
    func handleSystemSleep() async
    
    /// Handles system wake events
    /// Resumes authentication operations after system wake
    func handleSystemWake() async
    
    /// Gets the current app lifecycle state
    /// - Returns: Current app lifecycle state
    func getAppLifecycleState() -> AppLifecycleState?
    
    /// Checks if the authentication service is currently in background mode
    /// - Returns: True if in background mode
    func isInBackgroundMode() -> Bool
    
    // MARK: - Authentication State Persistence Coordination Methods
    
    /// Saves authentication state in a coordinated manner across all components
    /// - Parameter reason: Reason for the save operation
    /// - Parameter isEmergency: Whether this is an emergency save before app termination
    /// - Returns: True if save was successful
    func saveAuthenticationState(reason: String, isEmergency: Bool) async -> Bool
    
    /// Restores authentication state in a coordinated manner across all components
    /// - Parameter reason: Reason for the restore operation
    /// - Returns: True if restore was successful
    func restoreAuthenticationState(reason: String) async -> Bool
    
    /// Creates an emergency backup of critical authentication state
    /// - Returns: True if emergency backup was successful
    func createEmergencyBackup() async -> Bool
    
    /// Restores from emergency backup if available
    /// - Returns: True if emergency restore was successful
    func restoreFromEmergencyBackup() async -> Bool
    
    /// Checks if persisted authentication state exists and is valid
    /// - Returns: True if valid persisted state exists
    func hasValidPersistedAuthenticationState() async -> Bool
    
    /// Clears all persisted authentication state
    /// - Returns: True if clear was successful
    func clearPersistedAuthenticationState() async -> Bool
    
    /// Gets the size of persisted authentication data (for monitoring)
    /// - Returns: Size in bytes, or nil if unable to determine
    func getPersistedAuthenticationDataSize() async -> Int?
    
    /// Validates the integrity of persisted authentication state
    /// - Returns: True if persisted state is valid and uncorrupted
    func validatePersistedAuthenticationState() async -> Bool
    
    /// Gets comprehensive persistence status information
    /// - Returns: Dictionary with persistence coordination status
    func getPersistenceStatus() -> [String: Any]

// MARK: - Extension Providing Default Implementations

/// Extension providing default implementations for optional protocol methods
public extension AuthenticationServiceProtocol {
    
    /// Default implementation for preserveQueuedPosts parameter
    func performFallbackAuthentication(reason: String) async -> AuthenticationResult {
        return await performFallbackAuthentication(reason: reason, preserveQueuedPosts: true)
    }
    
    /// Default implementation for quick token validation
    func validateTokenForCriticalOperation() async -> TokenValidator.ValidationResult {
        return await validateTokenForCriticalOperation(.tweetPost)
    }
    
    /// Default implementation for operation pre-validation
    func preValidateTokenForOperation() async -> TokenPreValidationResult {
        return await preValidateTokenForOperation(.tweetPost)
    }
    
    /// Default implementation for ensuring token validity
    func ensureTokenValidForOperation() async -> TokenValidator.ValidationResult {
        return await ensureTokenValidForOperation(.tweetPost)
    }
    
    /// Default implementation for operation capability checking
    func canPerformOperation() async -> Bool {
        return await canPerformOperation(.tweetPost)
    }
    
    /// Default implementation for app lifecycle methods
    func prepareForBackground() async {
        // Default: no-op - services can override if needed
    }
    
    func handleForegroundRestore() async {
        // Default: no-op - services can override if needed
    }
    
    func prepareForTermination() async {
        // Default: no-op - services can override if needed
    }
    
    func handleSystemSleep() async {
        // Default: no-op - services can override if needed
    }
    
    func handleSystemWake() async {
        // Default: no-op - services can override if needed
    }
    
    func getAppLifecycleState() -> AppLifecycleState? {
        // Default: return nil - services can override to provide state
        return nil
    }
    
    func isInBackgroundMode() -> Bool {
        // Default: return false - services can override to provide state
        return false
    }
    
    /// Default implementation for authentication state persistence methods
    func saveAuthenticationState(reason: String, isEmergency: Bool) async -> Bool {
        // Default: no-op - services can override to provide persistence
        return true
    }
    
    func restoreAuthenticationState(reason: String) async -> Bool {
        // Default: no-op - services can override to provide persistence
        return true
    }
    
    func createEmergencyBackup() async -> Bool {
        // Default: no-op - services can override to provide emergency backup
        return true
    }
    
    func restoreFromEmergencyBackup() async -> Bool {
        // Default: no-op - services can override to provide emergency restore
        return false
    }
    
    func hasValidPersistedAuthenticationState() async -> Bool {
        // Default: return false - services can override to check persistence
        return false
    }
    
    func clearPersistedAuthenticationState() async -> Bool {
        // Default: no-op - services can override to clear persistence
        return true
    }
    
    func getPersistedAuthenticationDataSize() async -> Int? {
        // Default: return nil - services can override to provide size
        return nil
    }
    
    func validatePersistedAuthenticationState() async -> Bool {
        // Default: return true - services can override to validate
        return true
    }
    
    func getPersistenceStatus() -> [String: Any] {
        // Default: return empty status - services can override to provide status
        return [:]
    }
}

// MARK: - Supporting Types for Protocol

/// Extension making critical operation types available for protocol consumers
public extension AuthenticationServiceProtocol {
    
    /// Types of critical operations that require token validation
    typealias CriticalOperationType = AuthManager.CriticalOperationType
    
    /// Pre-validation results indicating what needs to be done before operation
    typealias TokenPreValidationResult = AuthManager.TokenPreValidationResult
}

// MARK: - Protocol Extension for Convenience Methods

/// Extension providing convenience methods for common authentication service operations
public extension AuthenticationServiceProtocol {
    
    /// Convenience method to check if user is authenticated and ready to post
    /// - Returns: True if authenticated and not rate limited
    func canPostTweet() -> Bool {
        return isAuthenticated() && !rateLimitInfo.isLimited
    }
    
    /// Convenience method to get authentication status as a simple enum
    /// - Returns: Simplified authentication status
    func getSimpleAuthenticationStatus() -> SimpleAuthenticationStatus {
        switch authenticationState {
        case .disconnected:
            return .disconnected
        case .authenticating:
            return .authenticating
        case .authenticated:
            return .authenticated
        case .refreshing:
            return .refreshing
        case .error:
            return .error
        }
    }
    
    /// Convenience method to check if there are any pending operations
    /// - Returns: True if there are queued posts or preserved posts
    func hasPendingOperations() -> Bool {
        return queuedPostsCount > 0 || getPreservedPostsCount() > 0
    }
    
    /// Convenience method to get total posts pending (queued + preserved)
    /// - Returns: Total number of posts waiting to be processed
    func getTotalPendingPosts() -> Int {
        return queuedPostsCount + getPreservedPostsCount()
    }
    
    /// Convenience method to check if manual intervention is required
    /// - Returns: True if user needs to take action (re-authenticate, etc.)
    func requiresManualIntervention() -> Bool {
        switch authenticationState {
        case .error(let error):
            // Check if the error requires manual intervention
            switch error {
            case .invalidCredentials, .authenticationInProgress:
                return true
            default:
                return false
            }
        case .disconnected:
            return shouldUseFallbackAuthentication()
        default:
            return false
        }
    }
}

// MARK: - Simplified Authentication Status

/// Simplified authentication status for easier UI consumption
public enum SimpleAuthenticationStatus: CaseIterable {
    case disconnected
    case authenticating
    case authenticated
    case refreshing
    case error
    
    /// Human-readable description of the status
    public var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .authenticating:
            return "Connecting..."
        case .authenticated:
            return "Connected"
        case .refreshing:
            return "Refreshing..."
        case .error:
            return "Error"
        }
    }
    
    /// Whether this status indicates the service is ready for posting
    public var isReadyForPosting: Bool {
        return self == .authenticated
    }
    
    /// Whether this status indicates an active operation is in progress
    public var isOperationInProgress: Bool {
        return self == .authenticating || self == .refreshing
    }
    
    /// Whether this status indicates user intervention may be required
    public var mayRequireIntervention: Bool {
        return self == .disconnected || self == .error
    }
}
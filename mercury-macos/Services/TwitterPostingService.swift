import Foundation
import Combine
import SwiftUI

/// Service that handles all X (Twitter) API operations for Mercury Core App
/// Acts as a bridge between Mercury UI components and AuthManager
/// Provides simple posting interface while leveraging AuthManager's comprehensive authentication and posting capabilities
@MainActor
public class TwitterPostingService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current posting state for UI updates
    @Published public private(set) var postingState: PostingState = .idle
    
    /// Whether the service is currently authenticated
    @Published public private(set) var isAuthenticated: Bool = false
    
    /// Current authenticated user information
    @Published public private(set) var currentUser: AuthenticatedUser?
    
    /// Current connection status for status indicators
    @Published public private(set) var connectionStatus: ConnectionStatus = .disconnected
    
    /// Number of posts queued for retry
    @Published public private(set) var queuedPostsCount: Int = 0
    
    /// Rate limit information for user awareness
    @Published public private(set) var rateLimitInfo: RateLimitInfo = RateLimitInfo.empty
    
    /// Latest posting result for UI feedback
    @Published public private(set) var lastPostingResult: TweetPostResult?
    
    // MARK: - Dependencies
    
    private let authManager: AuthManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    
    /// Configuration for posting service behavior
    public struct Configuration {
        /// Whether to show detailed error information in UI
        public let showDetailedErrors: Bool
        
        /// Whether to automatically retry failed posts
        public let enableAutoRetry: Bool
        
        /// Maximum time to wait for posting operations (seconds)
        public let postingTimeout: TimeInterval
        
        /// Whether to preserve text during authentication errors
        public let preserveTextOnError: Bool
        
        /// Default configuration for Mercury Core App
        public static let `default` = Configuration(
            showDetailedErrors: false,
            enableAutoRetry: true,
            postingTimeout: 10.0,
            preserveTextOnError: true
        )
        
        /// Development configuration with more detailed error information
        public static let development = Configuration(
            showDetailedErrors: true,
            enableAutoRetry: true,
            postingTimeout: 15.0,
            preserveTextOnError: true
        )
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    
    /// Initializes TwitterPostingService with AuthManager dependency
    /// - Parameters:
    ///   - authManager: AuthManager instance for all authentication operations
    ///   - configuration: Service configuration options
    public init(authManager: AuthManager, configuration: Configuration = .default) {
        self.authManager = authManager
        self.configuration = configuration
        
        setupAuthManagerObservation()
        initializeFromAuthManager()
    }
    
    // MARK: - Public Posting Interface
    
    /// Posts a tweet using AuthManager's comprehensive posting capabilities
    /// - Parameter text: Tweet content (max 280 characters)
    /// - Returns: Success status and any error information
    /// - Note: This method handles all authentication, rate limiting, and retry logic through AuthManager
    public func postTweet(_ text: String) async -> TweetPostResult {
        // Clear previous result
        lastPostingResult = nil
        
        // Update posting state with validation phase
        setPostingState(.loading(PostingProgress(phase: .validating)))
        
        // Validate text length before sending to AuthManager
        guard !text.isEmpty else {
            let error = TweetPostError.invalidTweetText("Tweet text cannot be empty")
            let result = TweetPostResult.failure(error)
            handlePostingResult(result, for: text)
            return result
        }
        
        guard text.count <= 280 else {
            let error = TweetPostError.invalidTweetText("Tweet text exceeds 280 character limit")
            let result = TweetPostResult.failure(error)
            handlePostingResult(result, for: text)
            return result
        }
        
        // Use AuthManager for actual posting (includes authentication validation, rate limiting, queuing)
        let result = await authManager.postTweet(text)
        
        // Handle the result and update UI state
        handlePostingResult(result, for: text)
        
        return result
    }
    
    /// Starts the authentication flow using AuthManager
    /// - Returns: Authentication result with user information
    public func authenticate() async -> AuthenticationResult {
        setConnectionStatus(.connecting(phase: .starting))
        
        let result = await authManager.authenticate()
        
        switch result {
        case .success(let user):
            setConnectionStatus(.connected(from: user))
            
        case .failure(let error):
            setConnectionStatus(.error(from: error))
        }
        
        return result
    }
    
    /// Disconnects from X using AuthManager
    /// - Returns: Disconnection result
    public func disconnect() async -> DisconnectionResult {
        setConnectionStatus(.disconnecting)
        
        let result = await authManager.disconnect()
        
        switch result {
        case .success:
            setConnectionStatus(.disconnected)
            
        case .failure(let error):
            setConnectionStatus(.error(AuthenticationError.unknown(error)))
        }
        
        return result
    }
    
    /// Manually processes queued posts (useful for retry button in UI)
    /// - Returns: Number of posts successfully processed
    @discardableResult
    public func processQueuedPosts() async -> Int {
        return await authManager.processQueuedPosts()
    }
    
    /// Starts re-authentication flow (for UI reconnect buttons)
    /// - Returns: Re-authentication result
    public func reconnect() async -> AuthenticationResult {
        return await authManager.startReauthentication()
    }
    
    // MARK: - State Query Methods
    
    /// Gets current authentication status
    public func getAuthenticationStatus() -> AuthenticationState {
        return authManager.authenticationState
    }
    
    /// Gets current user information if authenticated
    public func getCurrentUser() -> AuthenticatedUser? {
        return authManager.getCurrentUser()
    }
    
    /// Gets current rate limit information
    public func getRateLimitInfo() -> RateLimitInfo {
        return authManager.getRateLimitInfo()
    }
    
    /// Gets user-friendly status message for UI display
    public func getStatusMessage() -> String {
        return authManager.getStatusMessage()
    }
    
    /// Gets error message for current authentication state (if any)
    public func getCurrentErrorMessage() -> String? {
        return authManager.getCurrentErrorMessage()?.description
    }
    
    /// Checks if posting is currently allowed (authenticated, not rate limited, etc.)
    public func canPost() -> Bool {
        return isAuthenticated && !rateLimitInfo.isLimited && postingState != .loading
    }
    
    /// Gets detailed validation status for debugging
    public func getValidationStatus() async -> String {
        let tokenValidation = await authManager.getCurrentTokenValidationStatus()
        let authState = authManager.authenticationState
        let rateLimit = authManager.getRateLimitInfo()
        
        return """
        Authentication: \(authState)
        Token Valid: \(tokenValidation.isValid)
        Rate Limited: \(rateLimit.isLimited)
        Queue Count: \(queuedPostsCount)
        """
    }
    
    // MARK: - Publisher Access for Advanced UI Integration
    
    /// Publisher for authentication state changes
    public var authenticationStatePublisher: AnyPublisher<AuthenticationState, Never> {
        authManager.authenticationStatePublisher
    }
    
    /// Publisher for rate limit changes
    public var rateLimitPublisher: AnyPublisher<RateLimitInfo, Never> {
        authManager.rateLimitInfoPublisher
    }
    
    /// Publisher for queue count changes
    public var queueCountPublisher: AnyPublisher<Int, Never> {
        authManager.queuedPostsCountPublisher
    }
    
    /// Publisher for critical authentication events requiring UI attention
    public var criticalNotificationsPublisher: AnyPublisher<AuthenticationStateChangeNotification, Never> {
        authManager.criticalNotifications
    }
    
    /// Combined state publisher for reactive UI updates
    public var combinedStatePublisher: AnyPublisher<(AuthenticationState, AuthenticatedUser?, RateLimitInfo, Int), Never> {
        authManager.combinedStatePublisher
    }
    
    // MARK: - Private State Management
    
    private func setupAuthManagerObservation() {
        // Observe authentication state changes
        authManager.authenticationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                self?.handleAuthenticationStateChange(authState)
            }
            .store(in: &cancellables)
        
        // Observe user changes
        authManager.currentUserPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.currentUser = user
            }
            .store(in: &cancellables)
        
        // Observe rate limit changes
        authManager.rateLimitInfoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rateLimitInfo in
                self?.rateLimitInfo = rateLimitInfo
            }
            .store(in: &cancellables)
        
        // Observe queued posts count changes
        authManager.queuedPostsCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.queuedPostsCount = count
            }
            .store(in: &cancellables)
        
        // Observe critical notifications for UI alerts
        authManager.criticalNotifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCriticalNotification(notification)
            }
            .store(in: &cancellables)
    }
    
    private func initializeFromAuthManager() {
        // Initialize current state from AuthManager
        isAuthenticated = authManager.isAuthenticated()
        currentUser = authManager.getCurrentUser()
        rateLimitInfo = authManager.getRateLimitInfo()
        
        // Set initial connection status
        if isAuthenticated, let user = currentUser {
            connectionStatus = .connected(from: user)
        } else {
            connectionStatus = .disconnected
        }
    }
    
    private func handleAuthenticationStateChange(_ authState: AuthenticationState) {
        switch authState {
        case .disconnected:
            isAuthenticated = false
            setConnectionStatus(.disconnected)
            
        case .authenticating:
            setConnectionStatus(.connecting(phase: .starting))
            
        case .authenticated:
            isAuthenticated = true
            if let user = authManager.getCurrentUser() {
                setConnectionStatus(.connected(from: user))
            }
            
        case .refreshing:
            setConnectionStatus(.refreshing(reason: .automatic))
            
        case .error(let error):
            isAuthenticated = false
            setConnectionStatus(.error(from: error))
        }
    }
    
    private func handlePostingResult(_ result: TweetPostResult, for text: String) {
        lastPostingResult = result
        
        switch result {
        case .success(let success):
            setPostingState(.success(success))
            
            // Auto-clear success state after brief display
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if case .success = self?.postingState {
                    self?.setPostingState(.idle)
                }
            }
            
        case .failure(let error):
            // Determine if this is a recoverable error and get suggested actions
            let suggestedActions = getSuggestedActions(for: error)
            let errorState = PostingErrorState(
                error: error,
                isRecoverable: isRecoverableError(error),
                preservedText: configuration.preserveTextOnError ? text : nil,
                canRetry: configuration.enableAutoRetry && isRetryableError(error),
                authenticationState: authManager.authenticationState,
                suggestedActions: suggestedActions
            )
            
            setPostingState(.error(errorState))
        }
    }
    
    private func handleCriticalNotification(_ notification: AuthenticationStateChangeNotification) {
        // Handle critical authentication events that require immediate UI attention
        switch notification.newState {
        case .error(let error):
            // Set appropriate connection status for UI
            setConnectionStatus(.error(error))
            
        case .disconnected:
            // If we were previously authenticated, this might be unexpected
            if notification.previousState == .authenticated {
                print("⚠️ Unexpected disconnection from authenticated state")
            }
            
        default:
            break
        }
    }
    
    private func setPostingState(_ newState: PostingState) {
        postingState = newState
    }
    
    private func setConnectionStatus(_ newStatus: ConnectionStatus) {
        connectionStatus = newStatus
    }
    
    // MARK: - Error Analysis
    
    private func isRecoverableError(_ error: TweetPostError) -> Bool {
        switch error {
        case .notAuthenticated:
            return true // Can reconnect
        case .rateLimitExceeded:
            return true // Will reset eventually
        case .networkError:
            return true // Network might come back
        case .invalidTweetText:
            return false // User needs to fix text
        case .serverError(let code, _):
            return code >= 500 // 5xx errors might be temporary
        case .unknown:
            return true // Default to recoverable
        }
    }
    
    private func isRetryableError(_ error: TweetPostError) -> Bool {
        switch error {
        case .notAuthenticated:
            return false // Needs user action
        case .rateLimitExceeded:
            return false // Will be auto-retried when limit resets
        case .networkError:
            return true // Can retry network operations
        case .invalidTweetText:
            return false // User needs to fix text
        case .serverError(let code, _):
            return code >= 500 // 5xx errors might succeed on retry
        case .unknown:
            return true // Default to retryable
        }
    }
    
    private func getSuggestedActions(for error: TweetPostError) -> [ErrorAction] {
        switch error {
        case .notAuthenticated:
            return [.reconnect, .dismiss]
        case .invalidTweetText:
            return [.editText, .dismiss]
        case .rateLimitExceeded:
            return [.viewUsage, .dismiss]
        case .networkError:
            return [.retry, .dismiss]
        case .serverError:
            return [.retry, .copyError, .dismiss]
        case .unknown:
            return [.retry, .copyError, .dismiss]
        }
    }
    
    // MARK: - Helper Methods for UI Integration
    
    /// Gets user-friendly error message for posting errors
    public func getErrorMessage(for error: TweetPostError) -> String {
        if configuration.showDetailedErrors {
            return authManager.getErrorMessage(for: error).description
        } else {
            // Simplified messages for production UI
            switch error {
            case .notAuthenticated:
                return "Please connect your X account to post"
            case .invalidTweetText(let reason):
                return reason
            case .rateLimitExceeded:
                return "Rate limit reached. Try again later."
            case .networkError:
                return "Network error. Check your connection."
            case .serverError:
                return "X is experiencing issues. Try again later."
            case .unknown:
                return "Something went wrong. Please try again."
            }
        }
    }
    
    /// Gets appropriate action buttons for current error state
    public func getErrorActions() -> [ErrorAction] {
        guard case .error(let errorState) = postingState else { return [] }
        
        // Use the suggested actions from the error state
        return errorState.suggestedActions
    }
    
    /// Executes error action from UI
    public func executeErrorAction(_ action: ErrorAction, with text: String? = nil) async {
        switch action {
        case .retry:
            if let text = text {
                await postTweet(text)
            }
            
        case .reconnect:
            await authenticate()
            
        case .viewUsage:
            // This would typically open usage/settings view
            // Implementation depends on app navigation structure
            break
            
        case .editText:
            // UI should handle text editing - just clear error state
            setPostingState(.idle)
            
        case .copyError:
            // Copy error details to clipboard for debugging
            if case .error(let errorState) = postingState {
                let errorText = errorState.detailedDescription
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(errorText, forType: .string)
                #endif
            }
            
        case .dismiss:
            setPostingState(.idle)
        }
    }
}
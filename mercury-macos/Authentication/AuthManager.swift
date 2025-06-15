import Foundation
import Combine

/// Main authentication manager for Mercury macOS app
/// Provides a clean interface for all authentication operations while handling complexity internally
@MainActor
public class AuthManager: ObservableObject, TokenRefreshDelegate, ObservableAuthenticationManager {
    
    // MARK: - Published Properties
    
    /// Current authentication state - published for reactive UI updates
    @Published public internal(set) var authenticationState: AuthenticationState = .disconnected
    
    /// Current user information when authenticated
    @Published public internal(set) var currentUser: AuthenticatedUser?
    
    /// Rate limit information for user awareness
    @Published public private(set) var rateLimitInfo: RateLimitInfo = RateLimitInfo.empty
    
    /// Queued posts count for user visibility
    @Published public private(set) var queuedPostsCount: Int = 0
    
    // MARK: - Dependencies
    
    internal let keychainManager: KeychainManager
    internal let tokenRefreshManager: TokenRefreshManager
    private let postQueueManager: PostQueueManager
    internal let rateLimitManager: RateLimitManager
    internal let networkMonitor: NetworkMonitor
    private let tokenValidator: TokenValidator
    
    // MARK: - Event-Driven State Management
    
    public let eventManager: AuthenticationEventManager
    public let coordinator: AuthenticationCoordinator
    
    // MARK: - Combine Cancellables
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Event Publishers
    
    /// Publisher for authentication state changes
    public var authenticationStatePublisher: AnyPublisher<AuthenticationState, Never> {
        $authenticationState.eraseToAnyPublisher()
    }
    
    /// Publisher for user changes
    public var currentUserPublisher: AnyPublisher<AuthenticatedUser?, Never> {
        $currentUser.eraseToAnyPublisher()
    }
    
    /// Publisher for rate limit changes
    public var rateLimitInfoPublisher: AnyPublisher<RateLimitInfo, Never> {
        $rateLimitInfo.eraseToAnyPublisher()
    }
    
    /// Publisher for queue count changes
    public var queuedPostsCountPublisher: AnyPublisher<Int, Never> {
        $queuedPostsCount.eraseToAnyPublisher()
    }
    
    /// Combined state publisher for reactive UI updates
    public var combinedStatePublisher: AnyPublisher<(AuthenticationState, AuthenticatedUser?, RateLimitInfo, Int), Never> {
        Publishers.CombineLatest4(
            authenticationStatePublisher,
            currentUserPublisher,
            rateLimitInfoPublisher,
            queuedPostsCountPublisher
        )
        .eraseToAnyPublisher()
    }
    
    /// Publisher for authentication state change notifications with detailed context
    public var stateChangeNotifications: AnyPublisher<AuthenticationStateChangeNotification, Never> {
        coordinator.stateChanges
    }
    
    /// Publisher for critical authentication events that require immediate attention
    public var criticalNotifications: AnyPublisher<AuthenticationStateChangeNotification, Never> {
        stateChangeNotifications
            .filter { notification in
                switch notification.newState {
                case .error:
                    return true
                case .disconnected:
                    // Only critical if we were previously authenticated
                    return notification.previousState == .authenticated
                default:
                    return false
                }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Configuration
    
    /// Configuration options for AuthManager initialization
    public struct Configuration {
        /// Keychain service identifier for token storage
        public let keychainService: String
        
        /// Whether to enable automatic token refresh
        public let enableAutomaticTokenRefresh: Bool
        
        /// Token refresh timing in minutes before expiration
        public let tokenRefreshLeadTime: Int
        
        /// Maximum retry attempts for failed operations
        public let maxRetryAttempts: Int
        
        /// Whether to enable network monitoring
        public let enableNetworkMonitoring: Bool
        
        /// Whether to enable post queuing for offline scenarios
        public let enablePostQueuing: Bool
        
        /// Maximum number of posts to queue
        public let maxQueuedPosts: Int
        
        /// Whether to enable rate limit tracking
        public let enableRateLimiting: Bool
        
        /// Rate limit (posts per month for X API Free tier)
        public let monthlyPostLimit: Int
        
        /// Whether to enable debug logging
        public let enableDebugLogging: Bool
        
        /// Whether to enable notification broadcasting
        public let enableNotificationBroadcasting: Bool
        
        /// Custom dependency injection options
        public let customDependencies: DependencyOverrides?
        
        /// Default configuration for typical Mercury usage
        public static let `default` = Configuration(
            keychainService: "com.mercury.authentication",
            enableAutomaticTokenRefresh: true,
            tokenRefreshLeadTime: 15, // 15 minutes before expiration
            maxRetryAttempts: 3,
            enableNetworkMonitoring: true,
            enablePostQueuing: true,
            maxQueuedPosts: 100,
            enableRateLimiting: true,
            monthlyPostLimit: 500, // X API Free tier limit
            enableDebugLogging: false,
            enableNotificationBroadcasting: true,
            customDependencies: nil
        )
        
        /// Production configuration with optimized settings
        public static let production = Configuration(
            keychainService: "com.mercury.authentication",
            enableAutomaticTokenRefresh: true,
            tokenRefreshLeadTime: 10, // More conservative for production
            maxRetryAttempts: 5, // More retries for production
            enableNetworkMonitoring: true,
            enablePostQueuing: true,
            maxQueuedPosts: 200, // Higher queue limit for production
            enableRateLimiting: true,
            monthlyPostLimit: 500,
            enableDebugLogging: false,
            enableNotificationBroadcasting: true,
            customDependencies: nil
        )
        
        /// Development configuration with debugging enabled
        public static let development = Configuration(
            keychainService: "com.mercury.authentication.dev",
            enableAutomaticTokenRefresh: true,
            tokenRefreshLeadTime: 20, // Longer lead time for development
            maxRetryAttempts: 2, // Fewer retries for faster feedback
            enableNetworkMonitoring: true,
            enablePostQueuing: true,
            maxQueuedPosts: 50, // Smaller queue for development
            enableRateLimiting: false, // Disable for easier testing
            monthlyPostLimit: 500,
            enableDebugLogging: true,
            enableNotificationBroadcasting: true,
            customDependencies: nil
        )
        
        /// Testing configuration with minimal features
        public static let testing = Configuration(
            keychainService: "com.mercury.authentication.test",
            enableAutomaticTokenRefresh: false, // Manual control for tests
            tokenRefreshLeadTime: 5, // Short lead time for fast tests
            maxRetryAttempts: 1, // No retries for deterministic tests
            enableNetworkMonitoring: false, // Disable for unit tests
            enablePostQueuing: false, // Disable for unit tests
            maxQueuedPosts: 10,
            enableRateLimiting: false, // Disable for testing
            monthlyPostLimit: 500,
            enableDebugLogging: true,
            enableNotificationBroadcasting: false, // Disable for tests
            customDependencies: nil
        )
        
        public init(
            keychainService: String = "com.mercury.authentication",
            enableAutomaticTokenRefresh: Bool = true,
            tokenRefreshLeadTime: Int = 15,
            maxRetryAttempts: Int = 3,
            enableNetworkMonitoring: Bool = true,
            enablePostQueuing: Bool = true,
            maxQueuedPosts: Int = 100,
            enableRateLimiting: Bool = true,
            monthlyPostLimit: Int = 500,
            enableDebugLogging: Bool = false,
            enableNotificationBroadcasting: Bool = true,
            customDependencies: DependencyOverrides? = nil
        ) {
            self.keychainService = keychainService
            self.enableAutomaticTokenRefresh = enableAutomaticTokenRefresh
            self.tokenRefreshLeadTime = tokenRefreshLeadTime
            self.maxRetryAttempts = maxRetryAttempts
            self.enableNetworkMonitoring = enableNetworkMonitoring
            self.enablePostQueuing = enablePostQueuing
            self.maxQueuedPosts = maxQueuedPosts
            self.enableRateLimiting = enableRateLimiting
            self.monthlyPostLimit = monthlyPostLimit
            self.enableDebugLogging = enableDebugLogging
            self.enableNotificationBroadcasting = enableNotificationBroadcasting
            self.customDependencies = customDependencies
        }
    }
    
    /// Dependency overrides for testing and custom implementations
    public struct DependencyOverrides {
        public let keychainManager: KeychainManager?
        public let networkMonitor: NetworkMonitor?
        public let rateLimitManager: RateLimitManager?
        public let eventManager: AuthenticationEventManager?
        
        public init(
            keychainManager: KeychainManager? = nil,
            networkMonitor: NetworkMonitor? = nil,
            rateLimitManager: RateLimitManager? = nil,
            eventManager: AuthenticationEventManager? = nil
        ) {
            self.keychainManager = keychainManager
            self.networkMonitor = networkMonitor
            self.rateLimitManager = rateLimitManager
            self.eventManager = eventManager
        }
    }
    
    /// Current configuration used by this AuthManager instance
    public let configuration: Configuration
    
    // MARK: - Initialization
    
    /// Initializes AuthManager with default configuration
    public convenience init() async {
        await self.init(configuration: .default)
    }
    
    /// Initializes AuthManager with custom configuration
    /// - Parameter configuration: Configuration options for initialization
    public init(configuration: Configuration) async {
        self.configuration = configuration
        
        // Initialize dependencies with custom overrides or defaults
        self.keychainManager = configuration.customDependencies?.keychainManager ?? KeychainManager(serviceIdentifier: configuration.keychainService)
        self.networkMonitor = configuration.customDependencies?.networkMonitor ?? NetworkMonitor(enabled: configuration.enableNetworkMonitoring)
        self.rateLimitManager = configuration.customDependencies?.rateLimitManager ?? RateLimitManager(
            enabled: configuration.enableRateLimiting,
            monthlyLimit: configuration.monthlyPostLimit
        )
        self.eventManager = configuration.customDependencies?.eventManager ?? AuthenticationEventManager(debugLogging: configuration.enableDebugLogging)
        
        self.tokenRefreshManager = TokenRefreshManager(
            keychainManager: keychainManager,
            networkMonitor: networkMonitor,
            enabled: configuration.enableAutomaticTokenRefresh,
            leadTimeMinutes: configuration.tokenRefreshLeadTime,
            maxRetryAttempts: configuration.maxRetryAttempts
        )
        
        self.postQueueManager = PostQueueManager(
            networkMonitor: networkMonitor,
            enabled: configuration.enablePostQueuing,
            maxQueueSize: configuration.maxQueuedPosts
        )
        
        self.coordinator = AuthenticationCoordinator(eventManager: self.eventManager)
        
        // Initialize token validator with dependencies
        self.tokenValidator = TokenValidator(
            keychainManager: keychainManager,
            tokenRefreshManager: tokenRefreshManager,
            authManager: nil // Will be set after initialization
        )
        
        // Set up token refresh delegate connection
        self.tokenRefreshManager.setDelegate(self)
        
        setupStateObservation()
        setupEventDrivenStateManagement()
        
        // Only set up notification broadcasting if enabled
        if configuration.enableNotificationBroadcasting {
            setupNotificationBroadcasting()
        }
        
        initializeAuthenticationState()
        
        // Only set up post queue integration if enabled
        if configuration.enablePostQueuing {
            setupPostQueueIntegration()
        }
        
        // Only set up network event integration if network monitoring is enabled
        if configuration.enableNetworkMonitoring {
            setupNetworkEventIntegration()
            
            // Set up network notification observers only in debug mode
            if configuration.enableDebugLogging {
                setupNetworkNotificationObservers()
            }
        }
        
        // Set up circular reference for token validator
        await setupTokenValidatorReference()
        
        // Set up app lifecycle coordination
        setupAppLifecycleCoordination()
        
        // Set up authentication state persistence coordination
        setupAuthenticationStatePersistence()
    }
    
    /// Sets up integration between PostQueueManager and AuthManager for actual posting
    private func setupPostQueueIntegration() {
        postQueueManager.postSender = { [weak self] text in
            guard let self = self else { return false }
            
            // Attempt to post through this AuthManager
            let result = await self.performDirectPost(text)
            
            switch result {
            case .success:
                return true
            case .failure:
                return false
            }
        }
        
        // Connect PostQueueManager's network event publisher to EventManager
        postQueueManager.networkEventPublisher = { [weak self] networkEvent in
            Task { @MainActor in
                self?.eventManager.publish(networkEvent: networkEvent)
            }
        }
    }
    
    /// Performs a direct post without additional queuing (used by PostQueueManager)
    /// - Parameter text: Tweet text to post
    /// - Returns: Result of the posting attempt
    private func performDirectPost(_ text: String) async -> TweetPostResult {
        // Skip text validation and queuing since PostQueueManager handles that
        // Just check auth state and rate limits then post directly
        
        guard authenticationState == .authenticated else {
            return .failure(.notAuthenticated)
        }
        
        guard !rateLimitManager.isRateLimited else {
            return .failure(.rateLimitExceeded(rateLimitInfo))
        }
        
        // Use integrated Phase 1 XAPIClient for posting
        return await performTweetPost(text)
    }
    
    /// Sets up network event integration between NetworkMonitor and EventManager
    private func setupNetworkEventIntegration() {
        networkMonitor.eventPublisher = { [weak self] networkEvent in
            Task { @MainActor in
                self?.eventManager.publish(networkEvent: networkEvent)
                self?.handleNetworkEvent(networkEvent)
            }
        }
    }
    
    /// Handles network events for automatic retry and user notifications
    private func handleNetworkEvent(_ event: NetworkEvent) {
        switch event {
        case .connectionEstablished:
            handleConnectionRestored()
            
        case .connectionLost:
            handleConnectionLost()
            
        case .connectionQualityChanged(let quality):
            handleConnectionQualityChange(quality)
            
        case .operationRetried(let operation, let attempt):
            print("🔄 Retrying \(operation) (attempt \(attempt))")
        }
    }
    
    /// Handles connection being restored
    private func handleConnectionRestored() {
        print("🌐 Internet connection restored")
        
        // Process queued posts when network becomes available
        if isAuthenticated() {
            Task {
                let processedCount = await postQueueManager.processQueueOnNetworkRestored()
                if processedCount > 0 {
                    print("✅ Successfully processed \(processedCount) queued posts after network restoration")
                    
                    // Publish completion notification with processed count
                    NotificationCenter.default.post(
                        name: AuthenticationNotificationBroadcaster.NotificationName.automaticRetryCompleted,
                        object: nil,
                        userInfo: [
                            AuthenticationNotificationBroadcaster.UserInfoKey.postsProcessed: processedCount,
                            AuthenticationNotificationBroadcaster.UserInfoKey.operation: "queue processing",
                            AuthenticationNotificationBroadcaster.UserInfoKey.timestamp: Date()
                        ]
                    )
                }
            }
        } else {
            print("⚠️ Network restored but not authenticated - posts remain queued")
        }
    }
    
    /// Handles connection being lost
    private func handleConnectionLost() {
        print("📴 Internet connection lost - future posts will be queued automatically")
    }
    
    /// Handles connection quality changes
    private func handleConnectionQualityChange(_ quality: ConnectionQuality) {
        print("📊 Connection quality: \(quality.description)")
        
        // Adjust retry strategies based on connection quality
        if quality == .poor || quality == .fair {
            print("⚠️ Poor connection detected - using conservative retry strategy")
        } else if quality == .good || quality == .excellent {
            print("✅ Good connection detected - using aggressive retry strategy")
            
            // If we have connection quality improvement and are authenticated,
            // check if there are any pending operations that can now proceed
            if isAuthenticated() {
                Task {
                    // Check if token refresh is needed and network conditions are now suitable
                    if await tokenRefreshManager.shouldRefreshSoon() {
                        print("🔄 Good connection restored - attempting pending token refresh")
                        await tokenRefreshManager.refreshTokenNow()
                    }
                }
            }
        }
    }
    
    /// Sets up notification observers for network events (for demonstration and UI integration)
    private func setupNetworkNotificationObservers() {
        // Observe network connection restored
        NotificationCenter.default.addObserver(
            forName: AuthenticationNotificationBroadcaster.NotificationName.networkConnectionRestored,
            object: nil,
            queue: .main
        ) { notification in
            let timestamp = notification.userInfo?[AuthenticationNotificationBroadcaster.UserInfoKey.timestamp] as? Date ?? Date()
            print("📢 NOTIFICATION: Network connection restored at \(timestamp.formatted(.dateTime.hour().minute().second()))")
        }
        
        // Observe network connection lost
        NotificationCenter.default.addObserver(
            forName: AuthenticationNotificationBroadcaster.NotificationName.networkConnectionLost,
            object: nil,
            queue: .main
        ) { notification in
            let timestamp = notification.userInfo?[AuthenticationNotificationBroadcaster.UserInfoKey.timestamp] as? Date ?? Date()
            print("📢 NOTIFICATION: Network connection lost at \(timestamp.formatted(.dateTime.hour().minute().second()))")
        }
        
        // Observe automatic retry started
        NotificationCenter.default.addObserver(
            forName: AuthenticationNotificationBroadcaster.NotificationName.automaticRetryStarted,
            object: nil,
            queue: .main
        ) { notification in
            let operation = notification.userInfo?[AuthenticationNotificationBroadcaster.UserInfoKey.operation] as? String ?? "unknown"
            let retryCount = notification.userInfo?[AuthenticationNotificationBroadcaster.UserInfoKey.retryCount] as? Int ?? 0
            print("📢 NOTIFICATION: Automatic retry started for \(operation) (attempt \(retryCount))")
        }
        
        // Observe automatic retry completed
        NotificationCenter.default.addObserver(
            forName: AuthenticationNotificationBroadcaster.NotificationName.automaticRetryCompleted,
            object: nil,
            queue: .main
        ) { notification in
            let operation = notification.userInfo?[AuthenticationNotificationBroadcaster.UserInfoKey.operation] as? String ?? "unknown"
            let postsProcessed = notification.userInfo?[AuthenticationNotificationBroadcaster.UserInfoKey.postsProcessed] as? Int ?? 0
            print("📢 NOTIFICATION: Automatic retry completed for \(operation) - \(postsProcessed) posts processed")
        }
    }
    
    /// Sets up the circular reference for token validator after initialization
    private func setupTokenValidatorReference() async {
        // Note: In a real implementation, we'd use dependency injection to avoid this
        // For now, we'll access the validator through the authManager when needed
    }
    
    // MARK: - Public Interface Methods
    
    /// Initiates the OAuth 2.0 + PKCE authentication flow with intelligent network handling
    /// - Returns: Success status and any error information
    /// - Note: This method handles the complete flow including browser opening and callback handling
    public func authenticate() async -> AuthenticationResult {
        guard authenticationState != .authenticating else {
            return .failure(.authenticationInProgress)
        }
        
        // Check network conditions before starting authentication
        guard networkMonitor.shouldAttemptOperation(.authentication) else {
            let networkAdvice = networkMonitor.getNetworkAdvice(for: .authentication)
            let networkError = AuthenticationError.networkError(
                NSError(domain: "NetworkError", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: networkAdvice ?? "Network connection not suitable for authentication"
                ])
            )
            setAuthenticationState(.error(networkError))
            return .failure(networkError)
        }
        
        setAuthenticationState(.authenticating)
        eventManager.publish(authenticationEvent: .authenticationStarted)
        
        // Use intelligent retry for authentication with network awareness
        do {
            let result = try await networkMonitor.performOperationWithIntelligentRetry(
                operation: { [weak self] in
                    guard let self = self else { 
                        throw AuthenticationError.unknown(NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "AuthManager deallocated"]))
                    }
                    return try await self.performOAuthAuthenticationWithResult()
                },
                operationType: .authentication,
                operationName: "oauth_authentication"
            )
            
            // Handle successful authentication
            setAuthenticationState(.authenticated, context: ["user": result])
            currentUser = result
            
            // Store successful authentication timestamp
            storeLastSuccessfulAuthDate()
            
            eventManager.publish(authenticationEvent: .authenticationCompleted(result))
            
            // Clear token validation cache since we have fresh tokens
            clearTokenValidationCache()
            
            // Restore any preserved posts from fallback authentication
            await restorePreservedPosts()
            
            return .success(result)
            
        } catch {
            let authError = error as? AuthenticationError ?? .networkError(error)
            setAuthenticationState(.error(authError))
            eventManager.publish(authenticationEvent: .authenticationFailed(authError))
            return .failure(authError)
        }
    }
    
    /// Posts a tweet to X API with automatic retry and queuing
    /// - Parameter text: Tweet content (max 280 characters)
    /// - Returns: Success status, tweet ID if successful, or error information
    public func postTweet(_ text: String) async -> TweetPostResult {
        // Publish post start event
        eventManager.publish(tweetPostEvent: .postStarted(text: text))
        
        // Validate tweet text
        guard !text.isEmpty else {
            let error = TweetPostError.invalidTweetText("Tweet text cannot be empty")
            eventManager.publish(tweetPostEvent: .postFailed(error, text: text))
            return .failure(error)
        }
        
        guard text.count <= 280 else {
            let error = TweetPostError.invalidTweetText("Tweet text exceeds 280 character limit")
            eventManager.publish(tweetPostEvent: .postFailed(error, text: text))
            return .failure(error)
        }
        
        // Check network conditions first
        guard networkMonitor.shouldAttemptOperation(.posting) else {
            // Queue the post when network conditions are not suitable
            await postQueueManager.queuePost(text)
            eventManager.publish(tweetPostEvent: .postQueued(text: text))
            updateQueuedPostsCount()
            
            let networkAdvice = networkMonitor.getNetworkAdvice(for: .posting) ?? 
                               "Network connection not suitable for posting. Post queued for retry."
            let networkError = TweetPostError.networkError(
                NSError(domain: "NetworkError", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: networkAdvice
                ])
            )
            return .failure(networkError)
        }
        
        // Check authentication state
        guard authenticationState == .authenticated else {
            // Queue the post for later if not authenticated
            await postQueueManager.queuePost(text)
            eventManager.publish(tweetPostEvent: .postQueued(text: text))
            updateQueuedPostsCount()
            return .failure(.notAuthenticated)
        }
        
        // Check rate limits
        if rateLimitManager.isRateLimited {
            await postQueueManager.queuePost(text)
            eventManager.publish(tweetPostEvent: .postQueued(text: text))
            updateQueuedPostsCount()
            return .failure(.rateLimitExceeded(rateLimitInfo))
        }
        
        // Use integrated Phase 1 XAPIClient for posting
        let result = await performTweetPost(text)
        
        // Handle result and publish events
        switch result {
        case .success(let success):
            eventManager.publish(tweetPostEvent: .postCompleted(success))
            // Update rate limit info
            await rateLimitManager.recordRequest()
            return .success(success)
            
        case .failure(let error):
            eventManager.publish(tweetPostEvent: .postFailed(error, text: text))
            
            // Queue failed post for retry unless it's a validation error
            if !isValidationError(error) {
                await postQueueManager.queuePost(text)
                eventManager.publish(tweetPostEvent: .postQueued(text: text))
                updateQueuedPostsCount()
            }
            return .failure(error)
        }
    }
    
    /// Checks if user is currently authenticated with valid tokens
    /// - Returns: True if authenticated and tokens are valid
    public func isAuthenticated() -> Bool {
        return authenticationState == .authenticated
    }
    
    /// Disconnects the user and clears all stored authentication data
    /// - Returns: Success status
    public func disconnect() async -> DisconnectionResult {
        do {
            // Clear keychain data
            try await keychainManager.clearAllTokens()
            
            // Stop token refresh
            await tokenRefreshManager.stopRefresh()
            
            // Clear user info
            currentUser = nil
            setAuthenticationState(.disconnected)
            
            // Publish disconnection event
            eventManager.publish(authenticationEvent: .userDisconnected)
            
            return .success
            
        } catch {
            let disconnectError = error as? AuthenticationError ?? .unknown(error)
            setAuthenticationState(.error(disconnectError))
            return .failure(disconnectError)
        }
    }
    
    /// Gets current user information if authenticated
    /// - Returns: User information or nil if not authenticated
    public func getCurrentUser() -> AuthenticatedUser? {
        return currentUser
    }
    
    /// Gets current rate limit information
    /// - Returns: Rate limit details including remaining quota
    public func getRateLimitInfo() -> RateLimitInfo {
        return rateLimitInfo
    }
    
    // MARK: - State Change Notification Methods
    
    /// Subscribe to authentication state changes with a completion handler
    /// - Parameter handler: Called whenever authentication state changes
    /// - Returns: AnyCancellable to store and manage the subscription
    public func observeAuthenticationState(_ handler: @escaping (AuthenticationState) -> Void) -> AnyCancellable {
        return authenticationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to state changes for specific states
    /// - Parameters:
    ///   - states: Array of states to watch for
    ///   - handler: Called when state changes to one of the specified states
    /// - Returns: AnyCancellable to store and manage the subscription
    public func observeStates(_ states: [AuthenticationState], handler: @escaping (AuthenticationState) -> Void) -> AnyCancellable {
        return authenticationStatePublisher
            .filter { newState in
                states.contains { targetState in
                    switch (newState, targetState) {
                    case (.disconnected, .disconnected),
                         (.authenticating, .authenticating),
                         (.authenticated, .authenticated),
                         (.refreshing, .refreshing):
                        return true
                    case (.error, .error):
                        return true
                    default:
                        return false
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to authentication success events
    /// - Parameter handler: Called when authentication succeeds with user info
    /// - Returns: AnyCancellable to store and manage the subscription
    public func observeAuthenticationSuccess(_ handler: @escaping (AuthenticatedUser) -> Void) -> AnyCancellable {
        return stateChangeNotifications
            .compactMap { notification in
                switch notification.newState {
                case .authenticated:
                    return notification.context?["user"] as? AuthenticatedUser
                default:
                    return nil
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to authentication errors
    /// - Parameter handler: Called when authentication fails with error details
    /// - Returns: AnyCancellable to store and manage the subscription
    public func observeAuthenticationErrors(_ handler: @escaping (AuthenticationError) -> Void) -> AnyCancellable {
        return authenticationStatePublisher
            .compactMap { state in
                switch state {
                case .error(let error):
                    return error
                default:
                    return nil
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to disconnection events
    /// - Parameter handler: Called when user is disconnected
    /// - Returns: AnyCancellable to store and manage the subscription
    public func observeDisconnection(_ handler: @escaping () -> Void) -> AnyCancellable {
        return observeStates([.disconnected]) { _ in
            handler()
        }
    }
    
    /// Manually triggers processing of queued posts (useful for testing or user-initiated retry)
    /// - Returns: Number of posts successfully processed
    @discardableResult
    public func processQueuedPosts() async -> Int {
        guard isAuthenticated() && !rateLimitManager.isRateLimited else {
            return 0
        }
        
        let processedCount = await postQueueManager.processQueue()
        updateQueuedPostsCount()
        return processedCount
    }
    
    /// Starts re-authentication flow when called by user (e.g., from UI)
    /// - Returns: Success status and user information
    public func startReauthentication() async -> AuthenticationResult {
        print("🔐 Starting user-initiated re-authentication flow")
        
        // Clear existing tokens and state
        do {
            try await keychainManager.clearAllTokens()
        } catch {
            print("⚠️ Failed to clear tokens during re-authentication: \(error)")
        }
        
        // Reset token refresh state
        await tokenRefreshManager.stopRefresh()
        await tokenRefreshManager.resetRetryTracking()
        
        // Start fresh authentication
        return await authenticate()
    }
    
    /// Comprehensive fallback authentication flow for expired refresh tokens
    /// Handles various scenarios and provides graceful user experience
    /// - Parameters:
    ///   - reason: Reason for the fallback (e.g., "refresh_token_expired")
    ///   - preserveQueuedPosts: Whether to preserve queued posts during re-auth
    /// - Returns: Authentication result after fallback flow
    public func performFallbackAuthentication(reason: String, preserveQueuedPosts: Bool = true) async -> AuthenticationResult {
        print("🔄 Starting fallback authentication flow. Reason: \(reason)")
        
        // Publish fallback start event
        eventManager.publish(authenticationEvent: .authenticationStarted)
        
        // Step 1: Preserve queued posts if requested
        var preservedPosts: [String] = []
        if preserveQueuedPosts {
            preservedPosts = await postQueueManager.getAllQueuedPosts()
            print("📝 Preserved \(preservedPosts.count) queued posts during fallback authentication")
        }
        
        // Step 2: Clear expired/invalid authentication state
        await clearAuthenticationState(reason: reason)
        
        // Step 3: Attempt token recovery first (check for corrupted storage)
        let recoveryResult = await attemptTokenRecovery()
        if case .success(let user) = recoveryResult {
            print("✅ Token recovery successful during fallback authentication")
            
            // Restore queued posts
            if preserveQueuedPosts && !preservedPosts.isEmpty {
                await restoreQueuedPosts(preservedPosts)
            }
            
            return .success(user)
        }
        
        // Step 4: Attempt automatic re-authentication with exponential backoff
        let autoReauthResult = await attemptAutomaticReauthentication()
        if case .success(let user) = autoReauthResult {
            print("✅ Automatic re-authentication successful during fallback")
            
            // Restore queued posts
            if preserveQueuedPosts && !preservedPosts.isEmpty {
                await restoreQueuedPosts(preservedPosts)
            }
            
            return .success(user)
        }
        
        // Step 5: Set up for manual re-authentication
        await setupManualReauthentication(reason: reason, preservedPosts: preservedPosts)
        
        // Return failure indicating manual intervention is needed
        return .failure(.authenticationInProgress)
    }
    
    /// Clears authentication state during fallback flow
    /// - Parameter reason: Reason for clearing state
    private func clearAuthenticationState(reason: String) async {
        // Update state to show we're handling fallback
        setAuthenticationState(.disconnected, context: ["reason": reason, "fallback_in_progress": true])
        
        // Clear current user info
        currentUser = nil
        
        // Stop token refresh timer
        await tokenRefreshManager.stopRefresh()
        
        // Reset retry tracking for clean slate
        await tokenRefreshManager.resetRetryTracking()
        
        print("🧹 Authentication state cleared for fallback flow")
    }
    
    /// Attempts to recover from corrupted token storage
    /// - Returns: Authentication result if recovery succeeds
    private func attemptTokenRecovery() async -> AuthenticationResult {
        print("🔧 Attempting token recovery...")
        
        // Use TokenRecoveryManager if available
        // For now, we'll implement basic recovery logic
        do {
            // Check if we can recover stored tokens
            if await keychainManager.hasValidTokens() {
                let accessToken = try await keychainManager.getAccessToken()
                
                // Test the token by making an API call
                let apiClient = createXAPIClient()
                try apiClient.setAccessToken(accessToken)
                let userResponse = try await apiClient.getCurrentUser()
                
                // Create authenticated user
                let authenticatedUser = AuthenticatedUser(
                    id: userResponse.data.id,
                    username: userResponse.data.username,
                    name: userResponse.data.name,
                    profileImageUrl: userResponse.data.profileImageUrl,
                    followersCount: userResponse.data.publicMetrics?.followersCount,
                    followingCount: userResponse.data.publicMetrics?.followingCount,
                    tweetCount: userResponse.data.publicMetrics?.tweetCount,
                    verified: userResponse.data.verified
                )
                
                // Update state
                currentUser = authenticatedUser
                setAuthenticationState(.authenticated, context: ["recovered": true])
                
                // Restart token refresh
                await tokenRefreshManager.startRefreshTimer()
                
                eventManager.publish(authenticationEvent: .stateRestored(authenticatedUser))
                
                return .success(authenticatedUser)
            }
            
        } catch {
            print("⚠️ Token recovery failed: \(error)")
            // Clear potentially corrupted tokens
            try? await keychainManager.clearAllTokens()
        }
        
        return .failure(.invalidCredentials)
    }
    
    /// Attempts automatic re-authentication with stored preferences
    /// - Returns: Authentication result if automatic re-auth succeeds
    private func attemptAutomaticReauthentication() async -> AuthenticationResult {
        print("🤖 Attempting automatic re-authentication...")
        
        // For now, automatic re-authentication is not implemented
        // This would require storing user preferences for automatic re-auth
        // or using stored OAuth refresh tokens from a different source
        
        print("ℹ️ Automatic re-authentication not available - manual intervention required")
        return .failure(.authenticationInProgress)
    }
    
    /// Sets up for manual re-authentication by user
    /// - Parameters:
    ///   - reason: Reason for requiring manual re-auth
    ///   - preservedPosts: Posts to restore after re-auth
    private func setupManualReauthentication(reason: String, preservedPosts: [String]) async {
        // Store preserved posts for restoration after manual re-auth
        await storePreservedPosts(preservedPosts)
        
        // Set state to require manual intervention
        setAuthenticationState(.disconnected, context: [
            "reason": reason,
            "requires_manual_intervention": true,
            "preserved_posts_count": preservedPosts.count
        ])
        
        // Publish re-authentication required event with detailed context
        let detailedReason = createDetailedReauthenticationReason(reason: reason, preservedPostsCount: preservedPosts.count)
        eventManager.publish(authenticationEvent: .reauthenticationRequired(detailedReason))
        
        print("👤 Manual re-authentication required. Reason: \(detailedReason)")
    }
    
    /// Stores preserved posts during fallback authentication
    /// - Parameter posts: Posts to preserve
    private func storePreservedPosts(_ posts: [String]) async {
        if !posts.isEmpty {
            // Store in UserDefaults for retrieval after re-authentication
            let preservedData = posts.joined(separator: "\n---MERCURY_POST_SEPARATOR---\n")
            UserDefaults.standard.set(preservedData, forKey: "mercury.fallback.preserved_posts")
            print("💾 Stored \(posts.count) preserved posts")
        }
    }
    
    /// Restores queued posts after successful re-authentication
    /// - Parameter posts: Posts to restore
    private func restoreQueuedPosts(_ posts: [String]) async {
        for post in posts {
            await postQueueManager.queuePost(post)
        }
        updateQueuedPostsCount()
        print("📮 Restored \(posts.count) posts to queue")
    }
    
    /// Retrieves and restores preserved posts after manual re-authentication
    /// Called automatically after successful authentication
    public func restorePreservedPosts() async {
        guard let preservedData = UserDefaults.standard.string(forKey: "mercury.fallback.preserved_posts") else {
            return
        }
        
        let posts = preservedData.components(separatedBy: "\n---MERCURY_POST_SEPARATOR---\n")
        await restoreQueuedPosts(posts)
        
        // Clear preserved posts after restoration
        UserDefaults.standard.removeObject(forKey: "mercury.fallback.preserved_posts")
        
        print("🔄 Restored \(posts.count) preserved posts after manual re-authentication")
    }
    
    /// Creates detailed reason for re-authentication requirement using the error messaging system
    /// - Parameters:
    ///   - reason: Base reason
    ///   - preservedPostsCount: Number of preserved posts
    /// - Returns: Detailed reason string
    private func createDetailedReauthenticationReason(reason: String, preservedPostsCount: Int) -> String {
        // Create context for error messaging
        let context = AuthenticationErrorMessaging.ErrorContext(
            userDisplayName: currentUser?.displayName,
            lastSuccessfulAuth: getLastSuccessfulAuthDate(),
            queuedPostsCount: preservedPostsCount,
            networkStatus: getNetworkStatus(),
            previousState: authenticationState
        )
        
        // Generate appropriate error message based on reason
        let errorMessage: AuthenticationErrorMessaging.ErrorMessage
        
        switch reason {
        case "refresh_token_expired":
            let tokenError = TokenRefreshError.refreshTokenExpired
            errorMessage = tokenError.userMessage(context: context)
        case "invalid_credentials":
            let authError = AuthenticationError.invalidCredentials
            errorMessage = authError.userMessage(context: context)
        case "token_corruption":
            let keychainError = AuthenticationError.keychainError(NSError(domain: "TokenCorruption", code: 1))
            errorMessage = keychainError.userMessage(context: context)
        case "network_error":
            let networkError = AuthenticationError.networkError(NSError(domain: "NetworkError", code: 1))
            errorMessage = networkError.userMessage(context: context)
        default:
            let unknownError = AuthenticationError.unknown(NSError(domain: "UnknownError", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
            errorMessage = unknownError.userMessage(context: context)
        }
        
        return errorMessage.description
    }
    
    /// Checks if there are preserved posts waiting for restoration
    /// - Returns: Number of preserved posts waiting
    public func getPreservedPostsCount() -> Int {
        guard let preservedData = UserDefaults.standard.string(forKey: "mercury.fallback.preserved_posts") else {
            return 0
        }
        
        let posts = preservedData.components(separatedBy: "\n---MERCURY_POST_SEPARATOR---\n")
        return posts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    
    /// Checks if fallback authentication flow is recommended based on authentication state
    /// - Returns: True if fallback flow should be initiated
    public func shouldUseFallbackAuthentication() -> Bool {
        switch authenticationState {
        case .error(let error):
            // Use fallback for certain types of errors
            switch error {
            case .tokenRefreshFailed, .invalidCredentials:
                return true
            default:
                return false
            }
        case .disconnected:
            // Check if we were previously authenticated (context may indicate fallback needed)
            return true
        default:
            return false
        }
    }
    
    // MARK: - Error Messaging Methods
    
    /// Gets current error context for generating appropriate user messages
    /// - Returns: Error context with current authentication state
    private func getCurrentErrorContext() -> AuthenticationErrorMessaging.ErrorContext {
        return AuthenticationErrorMessaging.ErrorContext(
            userDisplayName: currentUser?.displayName,
            lastSuccessfulAuth: getLastSuccessfulAuthDate(),
            queuedPostsCount: queuedPostsCount,
            networkStatus: getNetworkStatus(),
            previousState: authenticationState
        )
    }
    
    /// Gets user-friendly error message for the current authentication state
    /// - Returns: Error message if in error state, nil otherwise
    public func getCurrentErrorMessage() -> AuthenticationErrorMessaging.ErrorMessage? {
        guard case .error(let error) = authenticationState else {
            return nil
        }
        
        let context = getCurrentErrorContext()
        return error.userMessage(context: context)
    }
    
    /// Gets user-friendly error message for a specific authentication error
    /// - Parameter error: The authentication error
    /// - Returns: User-friendly error message
    public func getErrorMessage(for error: AuthenticationError) -> AuthenticationErrorMessaging.ErrorMessage {
        let context = getCurrentErrorContext()
        return error.userMessage(context: context)
    }
    
    /// Gets user-friendly error message for a specific tweet posting error
    /// - Parameter error: The tweet posting error
    /// - Returns: User-friendly error message
    public func getErrorMessage(for error: TweetPostError) -> AuthenticationErrorMessaging.ErrorMessage {
        let context = getCurrentErrorContext()
        return error.userMessage(context: context)
    }
    
    /// Gets user-friendly error message for a specific token refresh error
    /// - Parameter error: The token refresh error
    /// - Returns: User-friendly error message
    public func getErrorMessage(for error: TokenRefreshError) -> AuthenticationErrorMessaging.ErrorMessage {
        let context = getCurrentErrorContext()
        return error.userMessage(context: context)
    }
    
    /// Gets a comprehensive status message for the current authentication state
    /// - Returns: Status message describing current state and any issues
    public func getStatusMessage() -> String {
        switch authenticationState {
        case .disconnected:
            let preservedCount = getPreservedPostsCount()
            if preservedCount > 0 {
                return "Disconnected from X. \(preservedCount) posts preserved and ready to send after reconnection."
            } else {
                return "Not connected to X. Connect your account to start posting."
            }
            
        case .authenticating:
            return "Connecting to X..."
            
        case .authenticated:
            if let user = currentUser {
                let queueInfo = queuedPostsCount > 0 ? " (\(queuedPostsCount) posts queued)" : ""
                return "Connected as @\(user.username)\(queueInfo)"
            } else {
                return "Connected to X"
            }
            
        case .refreshing:
            return "Refreshing X connection..."
            
        case .error(let error):
            let errorMessage = getErrorMessage(for: error)
            return errorMessage.description
        }
    }
    
    /// Gets detailed expiration information for current tokens
    /// - Returns: Expiration status message
    public func getTokenExpirationMessage() -> String? {
        // For now, return a placeholder message since token expiry tracking needs implementation
        return "Token expiry tracking not yet implemented"
    }
    
    // MARK: - Helper Methods for Error Context
    
    private func getLastSuccessfulAuthDate() -> Date? {
        // Try to get from UserDefaults or keychain metadata
        return UserDefaults.standard.object(forKey: "mercury.auth.last_success") as? Date
    }
    
    private func getNetworkStatus() -> AuthenticationErrorMessaging.NetworkStatus {
        if networkMonitor.isConnected {
            return .connected
        } else {
            return .disconnected
        }
    }
    
    /// Stores last successful authentication date for error context
    private func storeLastSuccessfulAuthDate() {
        UserDefaults.standard.set(Date(), forKey: "mercury.auth.last_success")
    }
    
    // MARK: - Token Validation Methods
    
    /// Validates token for critical operations with comprehensive checks
    /// - Parameter operationType: Type of operation being performed
    /// - Returns: Validation result with recommendations
    public func validateTokenForCriticalOperation(_ operationType: CriticalOperationType = .tweetPost) async -> TokenValidator.ValidationResult {
        print("🔍 Validating token for critical operation: \(operationType)")
        
        // Use appropriate validation config based on operation type
        let config = getValidationConfig(for: operationType)
        
        // Perform validation with auto-refresh capability
        let result = await tokenValidator.validateWithAutoRefresh(config: config)
        
        // Handle validation result
        await handleValidationResult(result, for: operationType)
        
        return result
    }
    
    /// Quick token validation for non-critical operations
    /// - Returns: Simple boolean indicating if token is valid
    public func isTokenValidForOperation() async -> Bool {
        return await tokenValidator.isTokenValid()
    }
    
    /// Validates token and provides recommendations for next steps
    /// - Returns: Validation result with actionable recommendations
    public func validateTokenWithRecommendations() async -> TokenValidator.ValidationResult {
        return await tokenValidator.validateWithRecommendations()
    }
    
    /// Pre-validates token before starting a critical operation
    /// Attempts to ensure token will be valid when the operation executes
    /// - Parameter operationType: Type of operation being planned
    /// - Returns: Pre-validation result
    public func preValidateTokenForOperation(_ operationType: CriticalOperationType) async -> TokenPreValidationResult {
        print("⏳ Pre-validating token for operation: \(operationType)")
        
        let result = await validateTokenForCriticalOperation(operationType)
        
        if result.isValid {
            return .readyToProceed(result)
        } else {
            // Analyze what needs to be done
            if result.recommendations.contains(.refreshTokenNow) {
                return .refreshRequired(result)
            } else if result.recommendations.contains(.reauthenticateRequired) {
                return .reauthenticationRequired(result)
            } else if result.recommendations.contains(.waitForNetwork) {
                return .networkIssue(result)
            } else {
                return .operationBlocked(result)
            }
        }
    }
    
    /// Ensures token is valid for immediate use with automatic remediation
    /// - Parameter operationType: Type of operation requiring valid token
    /// - Returns: Final validation result after all remediation attempts
    public func ensureTokenValidForOperation(_ operationType: CriticalOperationType) async -> TokenValidator.ValidationResult {
        print("🛡️ Ensuring token validity for operation: \(operationType)")
        
        // First, try validation with auto-refresh
        var result = await validateTokenForCriticalOperation(operationType)
        
        if result.isValid {
            return result
        }
        
        // If still not valid, try more aggressive remediation
        if result.recommendations.contains(.reauthenticateRequired) {
            print("🔄 Token validation failed, initiating fallback authentication...")
            
            let fallbackResult = await performFallbackAuthentication(
                reason: "token_validation_failed",
                preserveQueuedPosts: true
            )
            
            switch fallbackResult {
            case .success:
                // Re-validate after fallback authentication
                result = await validateTokenForCriticalOperation(operationType)
            case .failure:
                // Fallback failed, return final failure result
                break
            }
        }
        
        return result
    }
    
    /// Clears token validation cache (useful after token changes)
    public func clearTokenValidationCache() {
        tokenValidator.clearCache()
    }
    
    /// Gets the current token validation status for UI display
    /// - Returns: Current validation details for status display
    public func getCurrentTokenValidationStatus() async -> TokenValidator.ValidationResult {
        return await tokenValidator.validateForCriticalOperation(config: .quick)
    }
    
    /// Validates token with detailed information for debugging/monitoring
    /// - Returns: Comprehensive validation result with all details
    public func getDetailedTokenValidation() async -> TokenValidator.ValidationResult {
        return await tokenValidator.validateForCriticalOperation(config: .critical)
    }
    
    /// Checks if a specific operation can proceed based on current token state
    /// - Parameter operationType: Type of operation to check
    /// - Returns: Whether the operation can proceed
    public func canPerformOperation(_ operationType: CriticalOperationType) async -> Bool {
        let preValidation = await preValidateTokenForOperation(operationType)
        return preValidation.canProceed
    }
    
    // MARK: - Token Validation Configuration
    
    /// Types of critical operations that require token validation
    public enum CriticalOperationType {
        case tweetPost
        case userInfoRetrieval
        case apiCall
        case backgroundOperation
        
        public var description: String {
            switch self {
            case .tweetPost:
                return "Tweet posting"
            case .userInfoRetrieval:
                return "User information retrieval"
            case .apiCall:
                return "API call"
            case .backgroundOperation:
                return "Background operation"
            }
        }
    }
    
    /// Pre-validation results indicating what needs to be done before operation
    public enum TokenPreValidationResult {
        case readyToProceed(TokenValidator.ValidationResult)
        case refreshRequired(TokenValidator.ValidationResult)
        case reauthenticationRequired(TokenValidator.ValidationResult)
        case networkIssue(TokenValidator.ValidationResult)
        case operationBlocked(TokenValidator.ValidationResult)
        
        public var canProceed: Bool {
            switch self {
            case .readyToProceed:
                return true
            default:
                return false
            }
        }
        
        public var validationResult: TokenValidator.ValidationResult {
            switch self {
            case .readyToProceed(let result),
                 .refreshRequired(let result),
                 .reauthenticationRequired(let result),
                 .networkIssue(let result),
                 .operationBlocked(let result):
                return result
            }
        }
    }
    
    /// Gets appropriate validation configuration for operation type
    private func getValidationConfig(for operationType: CriticalOperationType) -> TokenValidator.ValidationConfig {
        switch operationType {
        case .tweetPost:
            // Tweet posting requires comprehensive validation
            return .critical
        case .userInfoRetrieval:
            // User info retrieval requires standard validation
            return .standard
        case .apiCall:
            // General API calls require standard validation
            return .standard
        case .backgroundOperation:
            // Background operations can use quick validation
            return .quick
        }
    }
    
    /// Handles validation results and takes appropriate actions
    private func handleValidationResult(_ result: TokenValidator.ValidationResult, for operationType: CriticalOperationType) async {
        // Log detailed validation info
        print("📊 Token validation result for \(operationType.description):")
        print("  Valid: \(result.isValid)")
        print("  Status: \(result.status)")
        
        // Update authentication state if needed
        switch result.status {
        case .valid:
            // Ensure we're in authenticated state
            if authenticationState != .authenticated {
                setAuthenticationState(.authenticated)
            }
            
        case .expired, .refreshRequired:
            // Set refreshing state temporarily
            if authenticationState == .authenticated {
                setAuthenticationState(.refreshing)
            }
            
        case .invalid, .missing, .authenticationRequired:
            // Set error state
            let error = AuthenticationError.invalidCredentials
            setAuthenticationState(.error(error))
            
        case .networkError:
            // Don't change state for network errors - they're temporary
            break
        }
        
        // Clear validation cache if token was found to be invalid
        if !result.isValid && result.status != .networkError {
            tokenValidator.clearCache()
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func setupNotificationBroadcasting() {
        // Setup notification broadcasting for this AuthManager instance
        AuthenticationNotificationBroadcaster.shared.setupBroadcasting(for: self)
    }
    
    private func setupEventDrivenStateManagement() {
        // Observe authentication state changes and publish events
        authenticationStatePublisher
            .removeDuplicates()
            .sink { [weak self] newState in
                guard let self = self else { return }
                // State change events are handled by the coordinator
            }
            .store(in: &cancellables)
        
        // React to authentication events
        eventManager.authenticationEvents
            .sink { [weak self] event in
                self?.handleAuthenticationEvent(event)
            }
            .store(in: &cancellables)
        
        // React to tweet post events
        eventManager.tweetPostEvents
            .sink { [weak self] event in
                self?.handleTweetPostEvent(event)
            }
            .store(in: &cancellables)
        
        // React to rate limit events
        eventManager.rateLimitEvents
            .sink { [weak self] event in
                self?.handleRateLimitEvent(event)
            }
            .store(in: &cancellables)
        
        // React to network events
        eventManager.networkEvents
            .sink { [weak self] event in
                self?.handleNetworkEvent(event)
            }
            .store(in: &cancellables)
        
        // Setup automatic queue processing triggers
        setupAutomaticQueueProcessing()
    }
    
    private func setupStateObservation() {
        // Observe token refresh state changes
        tokenRefreshManager.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] refreshState in
                self?.handleTokenRefreshStateChange(refreshState)
            }
            .store(in: &cancellables)
        
        // Observe network connectivity changes
        networkMonitor.isConnectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.handleNetworkStateChange(isConnected)
            }
            .store(in: &cancellables)
        
        // Observe rate limit changes
        rateLimitManager.rateLimitInfoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rateLimitInfo in
                self?.rateLimitInfo = rateLimitInfo
            }
            .store(in: &cancellables)
        
        // Observe queue changes
        postQueueManager.queueCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.queuedPostsCount = count
            }
            .store(in: &cancellables)
    }
    
    private func initializeAuthenticationState() {
        Task { @MainActor in
            // Check for existing valid tokens on startup
            if await keychainManager.hasValidTokens() {
                // Try to load user info from keychain
                do {
                    let storedUser = try await keychainManager.getUserInfo()
                    currentUser = storedUser
                    authenticationState = .authenticated
                    eventManager.publish(authenticationEvent: .stateRestored(storedUser))
                } catch {
                    // Tokens exist but no user info - verify tokens
                    await verifyStoredTokens()
                }
            } else {
                authenticationState = .disconnected
            }
        }
    }
    
    /// Verify stored tokens are still valid by making an API call
    private func verifyStoredTokens() async {
        do {
            let accessToken = try await keychainManager.getAccessToken()
            let apiClient = createXAPIClient()
            try apiClient.setAccessToken(accessToken)
            let userResponse = try await apiClient.getCurrentUser()
            
            // Create and store user info
            let authenticatedUser = AuthenticatedUser(
                id: userResponse.data.id,
                username: userResponse.data.username,
                name: userResponse.data.name,
                profileImageUrl: userResponse.data.profileImageUrl,
                followersCount: userResponse.data.publicMetrics?.followersCount,
                followingCount: userResponse.data.publicMetrics?.followingCount,
                tweetCount: userResponse.data.publicMetrics?.tweetCount,
                verified: userResponse.data.verified
            )
            
            try await keychainManager.storeUserInfo(authenticatedUser)
            currentUser = authenticatedUser
            authenticationState = .authenticated
            eventManager.publish(authenticationEvent: .stateRestored(authenticatedUser))
            
        } catch {
            // Tokens are invalid, clear them
            try? await keychainManager.clearAllTokens()
            authenticationState = .disconnected
        }
    }
    
    private func handleTokenRefreshStateChange(_ refreshState: TokenRefreshState) {
        switch refreshState {
        case .refreshing:
            if authenticationState == .authenticated {
                authenticationState = .refreshing
            }
        case .success:
            authenticationState = .authenticated
        case .failure(let error):
            authenticationState = .error(.tokenRefreshFailed(error))
        case .idle:
            if case .refreshing = authenticationState {
                authenticationState = .authenticated
            }
        }
    }
    
    private func handleNetworkStateChange(_ isConnected: Bool) {
        // This method is now handled by the new event-driven system
        // Network events are published by NetworkMonitor and handled by handleNetworkEvent
        // This legacy handler is kept for backward compatibility but does minimal work
        
        if isConnected {
            print("🔄 Legacy network state change handler - connection restored")
        } else {
            print("🔄 Legacy network state change handler - connection lost")
        }
    }
    
    private func updateQueuedPostsCount() {
        Task {
            let count = await postQueueManager.getQueuedPostsCount()
            await MainActor.run {
                self.queuedPostsCount = count
            }
        }
    }
    
    // MARK: - OAuth Integration Methods
    
    /// Performs OAuth authentication with result that can be used with intelligent retry
    /// - Returns: Authenticated user information
    /// - Throws: AuthenticationError on failure
    private func performOAuthAuthenticationWithResult() async throws -> AuthenticatedUser {
        // Note: This is a placeholder for Phase 1 OAuth integration
        // In the actual implementation, this would use the Phase 1 OAuth components
        
        // For now, we'll simulate the OAuth flow with appropriate network-aware timing
        let timeout = networkMonitor.getTimeoutForOperation(.authentication)
        
        // Check network conditions one more time before proceeding
        guard networkMonitor.isConnected else {
            throw AuthenticationError.networkError(
                NSError(domain: "NetworkError", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "No internet connection available for authentication"
                ])
            )
        }
        
        // Create URLSession with appropriate timeout for authentication
        let sessionConfig = networkMonitor.createSessionConfiguration(operationType: .authentication)
        let session = URLSession(configuration: sessionConfig)
        
        // Placeholder OAuth flow - in actual implementation this would:
        // 1. Create OAuth manager with PKCE
        // 2. Start local HTTP server for callback
        // 3. Open browser with authorization URL
        // 4. Wait for callback with authorization code
        // 5. Exchange code for tokens
        // 6. Validate tokens and get user info
        
        throw AuthenticationError.unknown(
            NSError(domain: "OAuth", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "OAuth integration placeholder - Phase 1 components not yet integrated"
            ])
        )
    }
    
    /// Creates an X API client with appropriate network configuration
    /// - Returns: Configured XAPIClient
    private func createXAPIClient() -> XAPIClientType {
        // Note: This is a placeholder for Phase 1 XAPIClient integration
        // In the actual implementation, this would create and configure XAPIClient
        
        // Create with network-aware session configuration
        let sessionConfig = networkMonitor.createSessionConfiguration(operationType: .posting)
        
        // Placeholder return - in actual implementation this would:
        // 1. Create XAPIClient with session configuration
        // 2. Set appropriate base URL and endpoints
        // 3. Configure request/response handling
        // 4. Set up error handling and retry logic
        
        return PlaceholderXAPIClient(sessionConfig: sessionConfig)
    }
    
    /// Performs actual tweet posting using X API
    /// - Parameter text: Tweet text to post
    /// - Returns: Result of the posting operation
    private func performTweetPost(_ text: String) async -> TweetPostResult {
        do {
            let client = createXAPIClient()
            
            // Set access token from keychain
            let accessToken = try await keychainManager.getAccessToken()
            try client.setAccessToken(accessToken)
            
            // Use intelligent retry for posting
            let response = try await networkMonitor.performOperationWithIntelligentRetry(
                operation: {
                    return try await client.postTweet(text)
                },
                operationType: .posting,
                operationName: "tweet_post"
            )
            
            return .success(response)
            
        } catch {
            return .failure(.networkError(error))
        }
    }
    
    // MARK: - Event Handling Methods
    
    private func handleAuthenticationEvent(_ event: AuthenticationEvent) {
        Task {
            switch event {
            case .authenticationCompleted(let user):
                // Start token refresh timer when authenticated
                await tokenRefreshManager.startRefreshTimer()
                
                // Process any queued posts
                await processQueuedPosts()
                
            case .tokenRefreshCompleted:
                // Clear token validation cache since we have fresh tokens
                clearTokenValidationCache()
                
                // Process queued posts after successful token refresh
                await processQueuedPosts()
                
            case .userDisconnected:
                // Stop token refresh when disconnected
                await tokenRefreshManager.stopRefresh()
                
            case .reauthenticationRequired(let reason):
                // Handle refresh token expiration requiring re-authentication
                print("🔐 Re-authentication required: \(reason)")
                // The UI should observe this event to prompt user for re-authentication
                
            default:
                break
            }
        }
    }
    
    private func handleTweetPostEvent(_ event: TweetPostEvent) {
        switch event {
        case .postQueued:
            updateQueuedPostsCount()
            
        case .queueProcessingStarted:
            Task {
                await processQueuedPosts()
            }
            
        case .queueProcessingCompleted(let successCount, let failureCount):
            updateQueuedPostsCount()
            if successCount > 0 {
                // Update rate limit info after successful posts
                Task {
                    await rateLimitManager.recordRequest()
                }
            }
            
        default:
            break
        }
    }
    
    private func handleRateLimitEvent(_ event: RateLimitEvent) {
        switch event {
        case .usageUpdated(let info):
            rateLimitInfo = info
            
        case .warningTriggered(let info):
            rateLimitInfo = info
            // Could trigger UI notification here
            
        case .limitExceeded(let info):
            rateLimitInfo = info
            // Stop processing queue when rate limited
            
        case .limitReset(let info):
            rateLimitInfo = info
            // Resume queue processing when limit resets
            eventManager.publish(tweetPostEvent: .queueProcessingStarted)
            
        }
    }
    
// Removed duplicate handleNetworkEvent method - using the one defined earlier
    
    private func setupAutomaticQueueProcessing() {
        // Process queue when authentication state becomes authenticated
        authenticationStatePublisher
            .filter { $0 == .authenticated }
            .sink { [weak self] _ in
                self?.eventManager.publish(tweetPostEvent: .queueProcessingStarted)
            }
            .store(in: &cancellables)
        
        // Process queue when rate limit resets
        rateLimitInfoPublisher
            .removeDuplicates { $0.isLimited == $1.isLimited }
            .filter { !$0.isLimited }
            .sink { [weak self] _ in
                guard let self = self, self.isAuthenticated() else { return }
                self.eventManager.publish(tweetPostEvent: .queueProcessingStarted)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Enhanced State Management Methods
    
    /// Publishes state change events through the coordinator
    private func publishStateChange(from oldState: AuthenticationState, to newState: AuthenticationState, context: [String: Any]? = nil) {
        coordinator.notifyStateChange(from: oldState, to: newState, context: context)
    }
    
    /// Enhanced authentication state setter that publishes events
    private func setAuthenticationState(_ newState: AuthenticationState, context: [String: Any]? = nil) {
        let oldState = authenticationState
        authenticationState = newState
        publishStateChange(from: oldState, to: newState, context: context)
    }
    
    /// Checks if an error is a validation error that shouldn't be queued for retry
    private func isValidationError(_ error: TweetPostError) -> Bool {
        switch error {
        case .invalidTweetText:
            return true
        case .serverError(let statusCode, _):
            // 400-level errors are typically validation errors
            return statusCode >= 400 && statusCode < 500
        default:
            return false
        }
    }
    
    // MARK: - TokenRefreshDelegate Implementation
    
    /// Implements token refresh delegation from TokenRefreshManager
    public func refreshTokens() async -> TokenRefreshResult {
        // Call the internal extension method that contains the actual implementation
        return await performTokenRefresh()
    }
    
    /// Implements re-authentication delegation from TokenRefreshManager
    public func triggerReauthentication() async {
        print("🔐 TokenRefreshManager requested re-authentication due to expired refresh token")
        
        // Use the comprehensive fallback authentication flow
        let result = await performFallbackAuthentication(reason: "refresh_token_expired", preserveQueuedPosts: true)
        
        switch result {
        case .success(let user):
            print("✅ Fallback authentication succeeded for user: \(user.username)")
            
        case .failure(let error):
            print("❌ Fallback authentication failed: \(error.localizedDescription)")
            
            // The fallback flow has already set up for manual re-authentication
            // Events have been published for UI to handle
        }
    }
}

// MARK: - Placeholder Types for Phase 1 Integration

/// Protocol for X API client - placeholder for Phase 1 integration
protocol XAPIClientType {
    func setAccessToken(_ token: String) throws
    func postTweet(_ text: String) async throws -> TweetPostSuccess
    func getCurrentUser() async throws -> UserResponse
}

/// Placeholder X API client implementation
struct PlaceholderXAPIClient: XAPIClientType {
    let sessionConfig: URLSessionConfiguration
    
    func setAccessToken(_ token: String) throws {
        // Placeholder implementation
    }
    
    func postTweet(_ text: String) async throws -> TweetPostSuccess {
        // Placeholder implementation - would use actual X API
        throw TweetPostError.unknown(
            NSError(domain: "XAPIClient", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Placeholder XAPIClient - Phase 1 integration pending"
            ])
        )
    }
    
    func getCurrentUser() async throws -> UserResponse {
        // Placeholder implementation - would use actual X API
        throw AuthenticationError.unknown(
            NSError(domain: "XAPIClient", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Placeholder XAPIClient - Phase 1 integration pending"
            ])
        )
    }
}


// MARK: - Result Types

/// Result type for authentication operations
public enum AuthenticationResult {
    case success(AuthenticatedUser)
    case failure(AuthenticationError)
}

/// Result type for tweet posting operations
public enum TweetPostResult {
    case success(TweetPostSuccess)
    case failure(TweetPostError)
}

/// Result type for disconnection operations
public enum DisconnectionResult {
    case success
    case failure(AuthenticationError)
}

/// Success information for tweet posting
public struct TweetPostSuccess {
    public let tweetId: String
    public let text: String
    public let createdAt: Date
    
    public init(tweetId: String, text: String, createdAt: Date = Date()) {
        self.tweetId = tweetId
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - Error Types

/// Authentication-related errors
public enum AuthenticationError: LocalizedError {
    case authenticationInProgress
    case invalidCredentials
    case networkError(Error)
    case tokenRefreshFailed(Error)
    case keychainError(Error)
    case serverError(Int, String?)
    case rateLimitExceeded
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .authenticationInProgress:
            return "Authentication is already in progress"
        case .invalidCredentials:
            return "Invalid authentication credentials"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .tokenRefreshFailed(let error):
            return "Token refresh failed: \(error.localizedDescription)"
        case .keychainError(let error):
            return "Keychain error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

/// Tweet posting errors
public enum TweetPostError: LocalizedError {
    case notAuthenticated
    case invalidTweetText(String)
    case rateLimitExceeded(RateLimitInfo)
    case networkError(Error)
    case serverError(Int, String?)
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in first."
        case .invalidTweetText(let reason):
            return "Invalid tweet text: \(reason)"
        case .rateLimitExceeded(let info):
            return "Rate limit exceeded. \(info.remainingRequests) requests remaining until \(info.resetDate?.formatted() ?? "unknown")"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
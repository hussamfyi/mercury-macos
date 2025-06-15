import Foundation
import Combine

// MARK: - Authentication Events

/// Events that can occur during authentication operations
public enum AuthenticationEvent {
    case authenticationStarted
    case authenticationCompleted(AuthenticatedUser)
    case authenticationFailed(AuthenticationError)
    case authenticationCancelled
    case tokenRefreshStarted
    case tokenRefreshCompleted
    case tokenRefreshFailed(Error)
    case userDisconnected
    case stateRestored(AuthenticatedUser)
    case reauthenticationRequired(String)
}

/// Events that can occur during tweet posting operations
public enum TweetPostEvent {
    case postStarted(text: String)
    case postCompleted(TweetPostSuccess)
    case postFailed(TweetPostError, text: String)
    case postQueued(text: String)
    case queueProcessingStarted
    case queueProcessingCompleted(successCount: Int, failureCount: Int)
}

/// Events related to rate limiting
public enum RateLimitEvent {
    case usageUpdated(RateLimitInfo)
    case warningTriggered(RateLimitInfo)
    case limitExceeded(RateLimitInfo)
    case limitReset(RateLimitInfo)
}

/// Events related to network connectivity
public enum NetworkEvent {
    case connectionEstablished
    case connectionLost
    case connectionQualityChanged(ConnectionQuality)
    case operationRetried(operation: String, attempt: Int)
}

// MARK: - Authentication State Change Protocols

/// Protocol for observing authentication state changes
public protocol AuthenticationStateObserver: AnyObject {
    /// Called when authentication state changes
    /// - Parameters:
    ///   - previousState: The previous authentication state
    ///   - newState: The new authentication state
    ///   - context: Additional context about the state change
    func authenticationStateDidChange(from previousState: AuthenticationState, to newState: AuthenticationState, context: [String: Any]?)
    
    /// Called when authentication succeeds
    /// - Parameter user: The authenticated user information
    func authenticationDidSucceed(user: AuthenticatedUser)
    
    /// Called when authentication fails
    /// - Parameter error: The authentication error
    func authenticationDidFail(error: AuthenticationError)
    
    /// Called when user is disconnected
    func userDidDisconnect()
    
    /// Called when token refresh completes successfully
    func tokenRefreshDidComplete()
    
    /// Called when token refresh fails
    /// - Parameter error: The token refresh error
    func tokenRefreshDidFail(error: Error)
    
    /// Called when re-authentication is required
    /// - Parameter reason: The reason re-authentication is required
    func reauthenticationRequired(reason: String)
}

/// Protocol for observing tweet posting events
public protocol TweetPostObserver: AnyObject {
    /// Called when a tweet post starts
    /// - Parameter text: The tweet text being posted
    func tweetPostDidStart(text: String)
    
    /// Called when a tweet post succeeds
    /// - Parameter success: The successful post information
    func tweetPostDidSucceed(success: TweetPostSuccess)
    
    /// Called when a tweet post fails
    /// - Parameters:
    ///   - error: The posting error
    ///   - text: The tweet text that failed to post
    func tweetPostDidFail(error: TweetPostError, text: String)
    
    /// Called when a tweet is queued for later posting
    /// - Parameter text: The tweet text that was queued
    func tweetWasQueued(text: String)
    
    /// Called when queue processing starts
    func queueProcessingDidStart()
    
    /// Called when queue processing completes
    /// - Parameters:
    ///   - successCount: Number of posts that succeeded
    ///   - failureCount: Number of posts that failed
    func queueProcessingDidComplete(successCount: Int, failureCount: Int)
}

/// Protocol for observing rate limit events
public protocol RateLimitObserver: AnyObject {
    /// Called when usage information is updated
    /// - Parameter info: Current rate limit information
    func rateLimitUsageDidUpdate(info: RateLimitInfo)
    
    /// Called when approaching rate limit
    /// - Parameter info: Current rate limit information
    func rateLimitWarningTriggered(info: RateLimitInfo)
    
    /// Called when rate limit is exceeded
    /// - Parameter info: Current rate limit information
    func rateLimitDidExceed(info: RateLimitInfo)
    
    /// Called when rate limit resets
    /// - Parameter info: Updated rate limit information
    func rateLimitDidReset(info: RateLimitInfo)
}

/// Protocol for observing network events
public protocol NetworkObserver: AnyObject {
    /// Called when network connection is established
    func networkConnectionDidEstablish()
    
    /// Called when network connection is lost
    func networkConnectionWasLost()
    
    /// Called when network connection quality changes
    /// - Parameter quality: New connection quality
    func networkConnectionQualityDidChange(quality: ConnectionQuality)
    
    /// Called when an operation is retried due to network issues
    /// - Parameters:
    ///   - operation: The operation being retried
    ///   - attempt: The retry attempt number
    func networkOperationWasRetried(operation: String, attempt: Int)
}

/// Comprehensive protocol for components that need to observe all authentication-related events
public protocol AuthenticationEventObserver: AuthenticationStateObserver, TweetPostObserver, RateLimitObserver, NetworkObserver {
    /// Called for any critical event that requires immediate attention
    /// - Parameter event: The critical event
    func criticalEventOccurred(event: Any)
}

/// Protocol for components that delegate authentication operations
public protocol AuthenticationDelegate: AnyObject {
    /// Called to request user interaction for authentication
    /// - Parameters:
    ///   - reason: Reason authentication is needed
    ///   - completion: Completion handler to call with result
    func requestAuthentication(reason: String, completion: @escaping (AuthenticationResult) -> Void)
    
    /// Called to request user confirmation for a sensitive operation
    /// - Parameters:
    ///   - operation: Description of the operation
    ///   - completion: Completion handler with user's decision
    func requestUserConfirmation(for operation: String, completion: @escaping (Bool) -> Void)
    
    /// Called to display an error message to the user
    /// - Parameters:
    ///   - error: The error to display
    ///   - context: Additional context about the error
    func displayError(_ error: Error, context: [String: Any]?)
    
    /// Called to display a success message to the user
    /// - Parameters:
    ///   - message: The success message
    ///   - context: Additional context
    func displaySuccess(message: String, context: [String: Any]?)
}

// MARK: - Observable Pattern Protocols

/// Protocol for authentication managers that provide observable state
public protocol ObservableAuthenticationManager: AnyObject {
    /// Publisher for authentication state changes
    var authenticationStatePublisher: AnyPublisher<AuthenticationState, Never> { get }
    
    /// Publisher for user changes
    var currentUserPublisher: AnyPublisher<AuthenticatedUser?, Never> { get }
    
    /// Publisher for rate limit changes
    var rateLimitInfoPublisher: AnyPublisher<RateLimitInfo, Never> { get }
    
    /// Publisher for queued posts count changes
    var queuedPostsCountPublisher: AnyPublisher<Int, Never> { get }
    
    /// Publisher for critical notifications
    var criticalNotifications: AnyPublisher<AuthenticationStateChangeNotification, Never> { get }
    
    /// Subscribe to authentication state changes
    /// - Parameter handler: Handler for state changes
    /// - Returns: Cancellable subscription
    func observeAuthenticationState(_ handler: @escaping (AuthenticationState) -> Void) -> AnyCancellable
    
    /// Subscribe to authentication errors
    /// - Parameter handler: Handler for authentication errors
    /// - Returns: Cancellable subscription
    func observeAuthenticationErrors(_ handler: @escaping (AuthenticationError) -> Void) -> AnyCancellable
    
    /// Subscribe to authentication success
    /// - Parameter handler: Handler for authentication success
    /// - Returns: Cancellable subscription
    func observeAuthenticationSuccess(_ handler: @escaping (AuthenticatedUser) -> Void) -> AnyCancellable
}

// MARK: - Event Publisher Protocol

/// Protocol for components that publish events
public protocol EventPublisher {
    associatedtype EventType
    var eventPublisher: AnyPublisher<EventType, Never> { get }
}

// MARK: - Authentication Event Manager

/// Centralized event management for authentication system
@MainActor
public class AuthenticationEventManager: ObservableObject {
    
    // MARK: - Event Publishers
    
    private let authEventSubject = PassthroughSubject<AuthenticationEvent, Never>()
    private let tweetEventSubject = PassthroughSubject<TweetPostEvent, Never>()
    private let rateLimitEventSubject = PassthroughSubject<RateLimitEvent, Never>()
    private let networkEventSubject = PassthroughSubject<NetworkEvent, Never>()
    
    public var authenticationEvents: AnyPublisher<AuthenticationEvent, Never> {
        authEventSubject.eraseToAnyPublisher()
    }
    
    public var tweetPostEvents: AnyPublisher<TweetPostEvent, Never> {
        tweetEventSubject.eraseToAnyPublisher()
    }
    
    public var rateLimitEvents: AnyPublisher<RateLimitEvent, Never> {
        rateLimitEventSubject.eraseToAnyPublisher()
    }
    
    public var networkEvents: AnyPublisher<NetworkEvent, Never> {
        networkEventSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Combined Event Streams
    
    /// All events combined into a single stream
    public var allEvents: AnyPublisher<Any, Never> {
        Publishers.Merge4(
            authenticationEvents.map { $0 as Any },
            tweetPostEvents.map { $0 as Any },
            rateLimitEvents.map { $0 as Any },
            networkEvents.map { $0 as Any }
        )
        .eraseToAnyPublisher()
    }
    
    /// Critical events that require immediate attention
    public var criticalEvents: AnyPublisher<Any, Never> {
        allEvents
            .filter { event in
                switch event {
                case let authEvent as AuthenticationEvent:
                    return authEvent.isCritical
                case let tweetEvent as TweetPostEvent:
                    return tweetEvent.isCritical
                case let rateLimitEvent as RateLimitEvent:
                    return rateLimitEvent.isCritical
                case let networkEvent as NetworkEvent:
                    return networkEvent.isCritical
                default:
                    return false
                }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Event Publishing Methods
    
    public func publish(authenticationEvent: AuthenticationEvent) {
        authEventSubject.send(authenticationEvent)
    }
    
    public func publish(tweetPostEvent: TweetPostEvent) {
        tweetEventSubject.send(tweetPostEvent)
    }
    
    public func publish(rateLimitEvent: RateLimitEvent) {
        rateLimitEventSubject.send(rateLimitEvent)
    }
    
    public func publish(networkEvent: NetworkEvent) {
        networkEventSubject.send(networkEvent)
    }
    
    // MARK: - Event History
    
    private var eventHistory: [TimestampedEvent] = []
    private let maxHistoryCount = 100
    
    /// Get recent events for debugging or UI display
    public func getRecentEvents(count: Int = 10) -> [TimestampedEvent] {
        return Array(eventHistory.suffix(count))
    }
    
    /// Clear event history
    public func clearHistory() {
        eventHistory.removeAll()
    }
    
    // MARK: - Initialization
    
    public init(debugLogging: Bool = false) {
        self.debugLoggingEnabled = debugLogging
        setupEventLogging()
    }
    
    private let debugLoggingEnabled: Bool
    
    private func setupEventLogging() {
        // Log all events to history
        allEvents
            .sink { [weak self] event in
                let timestampedEvent = TimestampedEvent(event: event, timestamp: Date())
                self?.eventHistory.append(timestampedEvent)
                
                // Maintain history limit
                if let self = self, self.eventHistory.count > self.maxHistoryCount {
                    self.eventHistory.removeFirst(self.eventHistory.count - self.maxHistoryCount)
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Notification Broadcasting

/// Broadcaster for authentication state change notifications that integrates with NotificationCenter
@MainActor
public class AuthenticationNotificationBroadcaster: ObservableObject {
    
    public static let shared = AuthenticationNotificationBroadcaster()
    
    /// NotificationCenter notification names for authentication events
    public enum NotificationName {
        public static let authenticationStateChanged = Notification.Name("Mercury.AuthenticationStateChanged")
        public static let authenticationSuccess = Notification.Name("Mercury.AuthenticationSuccess")
        public static let authenticationError = Notification.Name("Mercury.AuthenticationError")
        public static let userDisconnected = Notification.Name("Mercury.UserDisconnected")
        public static let tokenRefreshCompleted = Notification.Name("Mercury.TokenRefreshCompleted")
        public static let networkConnectionRestored = Notification.Name("Mercury.NetworkConnectionRestored")
        public static let networkConnectionLost = Notification.Name("Mercury.NetworkConnectionLost")
        public static let automaticRetryStarted = Notification.Name("Mercury.AutomaticRetryStarted")
        public static let automaticRetryCompleted = Notification.Name("Mercury.AutomaticRetryCompleted")
    }
    
    /// UserInfo keys for notification data
    public enum UserInfoKey {
        public static let previousState = "previousState"
        public static let newState = "newState"
        public static let user = "user"
        public static let error = "error"
        public static let timestamp = "timestamp"
        public static let context = "context"
        public static let networkState = "networkState"
        public static let connectionQuality = "connectionQuality"
        public static let retryCount = "retryCount"
        public static let operation = "operation"
        public static let postsProcessed = "postsProcessed"
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    /// Setup broadcasting for an AuthManager instance
    public func setupBroadcasting(for authManager: AuthManager) {
        // Broadcast all state changes
        authManager.stateChangeNotifications
            .sink { [weak self] notification in
                self?.broadcastStateChange(notification)
            }
            .store(in: &cancellables)
        
        // Broadcast specific events
        authManager.stateChangeNotifications
            .sink { [weak self] notification in
                self?.broadcastSpecificEvents(notification)
            }
            .store(in: &cancellables)
        
        // Broadcast network events
        authManager.eventManager.networkEvents
            .sink { [weak self] networkEvent in
                self?.broadcastNetworkEvent(networkEvent)
            }
            .store(in: &cancellables)
    }
    
    private func broadcastStateChange(_ notification: AuthenticationStateChangeNotification) {
        let userInfo: [String: Any] = [
            UserInfoKey.previousState: notification.previousState,
            UserInfoKey.newState: notification.newState,
            UserInfoKey.timestamp: notification.timestamp,
            UserInfoKey.context: notification.context as Any
        ]
        
        NotificationCenter.default.post(
            name: NotificationName.authenticationStateChanged,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func broadcastSpecificEvents(_ notification: AuthenticationStateChangeNotification) {
        if notification.isAuthenticationSuccess {
            var userInfo: [String: Any] = [
                UserInfoKey.newState: notification.newState,
                UserInfoKey.timestamp: notification.timestamp
            ]
            
            if let user = notification.context?["user"] as? AuthenticatedUser {
                userInfo[UserInfoKey.user] = user
            }
            
            NotificationCenter.default.post(
                name: NotificationName.authenticationSuccess,
                object: nil,
                userInfo: userInfo
            )
        }
        
        if notification.isError {
            var userInfo: [String: Any] = [
                UserInfoKey.newState: notification.newState,
                UserInfoKey.timestamp: notification.timestamp
            ]
            
            if case .error(let error) = notification.newState {
                userInfo[UserInfoKey.error] = error
            }
            
            NotificationCenter.default.post(
                name: NotificationName.authenticationError,
                object: nil,
                userInfo: userInfo
            )
        }
        
        if notification.isDisconnection {
            let userInfo: [String: Any] = [
                UserInfoKey.previousState: notification.previousState,
                UserInfoKey.timestamp: notification.timestamp
            ]
            
            NotificationCenter.default.post(
                name: NotificationName.userDisconnected,
                object: nil,
                userInfo: userInfo
            )
        }
        
        if notification.isTokenRefreshSuccess {
            let userInfo: [String: Any] = [
                UserInfoKey.newState: notification.newState,
                UserInfoKey.timestamp: notification.timestamp
            ]
            
            NotificationCenter.default.post(
                name: NotificationName.tokenRefreshCompleted,
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    private func broadcastNetworkEvent(_ networkEvent: NetworkEvent) {
        var userInfo: [String: Any] = [
            UserInfoKey.timestamp: Date()
        ]
        
        switch networkEvent {
        case .connectionEstablished:
            NotificationCenter.default.post(
                name: NotificationName.networkConnectionRestored,
                object: nil,
                userInfo: userInfo
            )
            
        case .connectionLost:
            NotificationCenter.default.post(
                name: NotificationName.networkConnectionLost,
                object: nil,
                userInfo: userInfo
            )
            
        case .connectionQualityChanged(let quality):
            userInfo[UserInfoKey.connectionQuality] = quality
            // Note: We could add a specific notification for quality changes if needed
            
        case .operationRetried(let operation, let attempt):
            userInfo[UserInfoKey.operation] = operation
            userInfo[UserInfoKey.retryCount] = attempt
            
            if operation.contains("queue processing") {
                NotificationCenter.default.post(
                    name: NotificationName.automaticRetryStarted,
                    object: nil,
                    userInfo: userInfo
                )
            }
        }
    }
    
    /// Convenience method to observe authentication state changes via NotificationCenter
    public static func observeStateChanges(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.authenticationStateChanged,
            object: nil
        )
    }
    
    /// Convenience method to observe authentication success via NotificationCenter
    public static func observeAuthenticationSuccess(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.authenticationSuccess,
            object: nil
        )
    }
    
    /// Convenience method to observe authentication errors via NotificationCenter
    public static func observeAuthenticationErrors(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.authenticationError,
            object: nil
        )
    }
    
    /// Convenience method to observe user disconnection via NotificationCenter
    public static func observeDisconnection(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.userDisconnected,
            object: nil
        )
    }
    
    /// Convenience method to observe network connection restored via NotificationCenter
    public static func observeNetworkConnectionRestored(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.networkConnectionRestored,
            object: nil
        )
    }
    
    /// Convenience method to observe network connection lost via NotificationCenter
    public static func observeNetworkConnectionLost(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.networkConnectionLost,
            object: nil
        )
    }
    
    /// Convenience method to observe automatic retry events via NotificationCenter
    public static func observeAutomaticRetry(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.automaticRetryStarted,
            object: nil
        )
    }
    
    /// Convenience method to observe automatic retry completion via NotificationCenter
    public static func observeAutomaticRetryCompleted(
        _ observer: Any,
        selector: Selector
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: NotificationName.automaticRetryCompleted,
            object: nil
        )
    }
}

// MARK: - Event Extensions

extension AuthenticationEvent {
    /// Whether this event represents a critical state that needs immediate attention
    var isCritical: Bool {
        switch self {
        case .authenticationFailed, .tokenRefreshFailed:
            return true
        default:
            return false
        }
    }
    
    /// User-friendly description of the event
    var description: String {
        switch self {
        case .authenticationStarted:
            return "Authentication started"
        case .authenticationCompleted(let user):
            return "Authenticated as \(user.displayName)"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .authenticationCancelled:
            return "Authentication cancelled"
        case .tokenRefreshStarted:
            return "Token refresh started"
        case .tokenRefreshCompleted:
            return "Token refresh completed"
        case .tokenRefreshFailed(let error):
            return "Token refresh failed: \(error.localizedDescription)"
        case .userDisconnected:
            return "User disconnected"
        case .stateRestored(let user):
            return "Session restored for \(user.displayName)"
        case .reauthenticationRequired(let reason):
            return "Re-authentication required: \(reason)"
        }
    }
}

extension TweetPostEvent {
    var isCritical: Bool {
        switch self {
        case .postFailed:
            return true
        default:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .postStarted(let text):
            return "Posting tweet: \(text.prefix(50))..."
        case .postCompleted(let success):
            return "Tweet posted successfully: \(success.tweetId)"
        case .postFailed(let error, let text):
            return "Tweet post failed: \(error.localizedDescription) - \(text.prefix(50))..."
        case .postQueued(let text):
            return "Tweet queued for retry: \(text.prefix(50))..."
        case .queueProcessingStarted:
            return "Processing queued tweets"
        case .queueProcessingCompleted(let successCount, let failureCount):
            return "Queue processed: \(successCount) succeeded, \(failureCount) failed"
        }
    }
}

extension RateLimitEvent {
    var isCritical: Bool {
        switch self {
        case .limitExceeded:
            return true
        default:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .usageUpdated(let info):
            return "Rate limit updated: \(info.remainingRequests) remaining"
        case .warningTriggered(let info):
            return "Rate limit warning: \(info.remainingRequests) requests remaining"
        case .limitExceeded(let info):
            return "Rate limit exceeded: \(info.statusDescription)"
        case .limitReset(let info):
            return "Rate limit reset: \(info.remainingRequests) requests available"
        }
    }
}

extension NetworkEvent {
    var isCritical: Bool {
        switch self {
        case .connectionLost:
            return true
        default:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .connectionEstablished:
            return "Network connection established"
        case .connectionLost:
            return "Network connection lost"
        case .connectionQualityChanged(let quality):
            return "Connection quality: \(quality.description)"
        case .operationRetried(let operation, let attempt):
            return "Retrying \(operation) (attempt \(attempt))"
        }
    }
}

// MARK: - Supporting Types

/// Event with timestamp for history tracking
public struct TimestampedEvent {
    public let event: Any
    public let timestamp: Date
    
    public init(event: Any, timestamp: Date) {
        self.event = event
        self.timestamp = timestamp
    }
}

// MARK: - State Change Notifications

/// Notification for state changes that components can observe
public struct AuthenticationStateChangeNotification {
    public let previousState: AuthenticationState
    public let newState: AuthenticationState
    public let timestamp: Date
    public let context: [String: Any]?
    
    public init(
        previousState: AuthenticationState,
        newState: AuthenticationState,
        timestamp: Date = Date(),
        context: [String: Any]? = nil
    ) {
        self.previousState = previousState
        self.newState = newState
        self.timestamp = timestamp
        self.context = context
    }
    
    /// Whether this notification represents a state transition to an error state
    public var isError: Bool {
        switch newState {
        case .error:
            return true
        default:
            return false
        }
    }
    
    /// Whether this notification represents successful authentication
    public var isAuthenticationSuccess: Bool {
        return newState == .authenticated && previousState != .authenticated
    }
    
    /// Whether this notification represents a disconnection
    public var isDisconnection: Bool {
        return newState == .disconnected && previousState == .authenticated
    }
    
    /// Whether this notification represents the start of authentication
    public var isAuthenticationStart: Bool {
        return newState == .authenticating && previousState == .disconnected
    }
    
    /// Whether this notification represents successful token refresh
    public var isTokenRefreshSuccess: Bool {
        return newState == .authenticated && previousState == .refreshing
    }
    
    /// User-friendly description of the state change
    public var description: String {
        switch (previousState, newState) {
        case (.disconnected, .authenticating):
            return "Starting authentication..."
        case (.authenticating, .authenticated):
            return "Authentication successful"
        case (.authenticating, .error(let error)):
            return "Authentication failed: \(error.localizedDescription)"
        case (.authenticated, .refreshing):
            return "Refreshing authentication..."
        case (.refreshing, .authenticated):
            return "Authentication refreshed successfully"
        case (.refreshing, .error(let error)):
            return "Authentication refresh failed: \(error.localizedDescription)"
        case (.authenticated, .disconnected):
            return "Disconnected from X"
        case (_, .error(let error)):
            return "Error: \(error.localizedDescription)"
        default:
            return "Authentication state changed from \(previousState.description) to \(newState.description)"
        }
    }
}

// MARK: - Event-Driven Coordination

/// Coordinates state changes across authentication components
@MainActor
public class AuthenticationCoordinator: ObservableObject {
    
    // MARK: - State Change Publisher
    
    private let stateChangeSubject = PassthroughSubject<AuthenticationStateChangeNotification, Never>()
    
    public var stateChanges: AnyPublisher<AuthenticationStateChangeNotification, Never> {
        stateChangeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Dependencies
    
    private let eventManager: AuthenticationEventManager
    private var cancellables = Set<AnyCancellable>()
    
    public init(eventManager: AuthenticationEventManager) {
        self.eventManager = eventManager
        setupEventCoordination()
    }
    
    // MARK: - State Change Notification
    
    public func notifyStateChange(
        from previousState: AuthenticationState,
        to newState: AuthenticationState,
        context: [String: Any]? = nil
    ) {
        let notification = AuthenticationStateChangeNotification(
            previousState: previousState,
            newState: newState,
            context: context
        )
        
        stateChangeSubject.send(notification)
        
        // Publish corresponding authentication event
        switch newState {
        case .authenticated:
            if let user = context?["user"] as? AuthenticatedUser {
                eventManager.publish(authenticationEvent: .authenticationCompleted(user))
            }
        case .disconnected:
            eventManager.publish(authenticationEvent: .userDisconnected)
        case .error(let error):
            eventManager.publish(authenticationEvent: .authenticationFailed(error))
        case .authenticating:
            eventManager.publish(authenticationEvent: .authenticationStarted)
        case .refreshing:
            eventManager.publish(authenticationEvent: .tokenRefreshStarted)
        }
    }
    
    // MARK: - Event Coordination
    
    private func setupEventCoordination() {
        // Coordinate authentication events with other systems
        eventManager.authenticationEvents
            .sink { [weak self] event in
                self?.handleAuthenticationEvent(event)
            }
            .store(in: &cancellables)
        
        // Coordinate network events with retry logic
        eventManager.networkEvents
            .sink { [weak self] event in
                self?.handleNetworkEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleAuthenticationEvent(_ event: AuthenticationEvent) {
        // Add coordination logic here
        // For example, triggering post queue processing after authentication
        switch event {
        case .authenticationCompleted:
            eventManager.publish(tweetPostEvent: .queueProcessingStarted)
        case .tokenRefreshCompleted:
            eventManager.publish(tweetPostEvent: .queueProcessingStarted)
        default:
            break
        }
    }
    
    private func handleNetworkEvent(_ event: NetworkEvent) {
        // Add network-based coordination logic here
        switch event {
        case .connectionEstablished:
            eventManager.publish(tweetPostEvent: .queueProcessingStarted)
        default:
            break
        }
    }
}
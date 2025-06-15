import Foundation
import Combine

/// Protocol defining the error event emission interface for core app error handling
/// This protocol abstracts error event emission and provides a clean interface
/// for the core Mercury app to handle all authentication-related errors
@MainActor
public protocol ErrorEventEmissionProtocol: ObservableObject {
    
    // MARK: - Error Event Publishers
    
    /// Publisher for all authentication-related errors
    var authenticationErrorPublisher: AnyPublisher<AuthenticationErrorEvent, Never> { get }
    
    /// Publisher for tweet posting errors
    var tweetPostErrorPublisher: AnyPublisher<TweetPostErrorEvent, Never> { get }
    
    /// Publisher for token management errors
    var tokenErrorPublisher: AnyPublisher<TokenErrorEvent, Never> { get }
    
    /// Publisher for rate limiting errors and warnings
    var rateLimitErrorPublisher: AnyPublisher<RateLimitErrorEvent, Never> { get }
    
    /// Publisher for network-related errors
    var networkErrorPublisher: AnyPublisher<NetworkErrorEvent, Never> { get }
    
    /// Publisher for queue management errors
    var queueErrorPublisher: AnyPublisher<QueueErrorEvent, Never> { get }
    
    /// Publisher for persistence and storage errors
    var persistenceErrorPublisher: AnyPublisher<PersistenceErrorEvent, Never> { get }
    
    /// Publisher for security-related errors
    var securityErrorPublisher: AnyPublisher<SecurityErrorEvent, Never> { get }
    
    /// Combined publisher for all error events
    var allErrorEventsPublisher: AnyPublisher<ErrorEvent, Never> { get }
    
    /// Publisher for critical errors requiring immediate user attention
    var criticalErrorPublisher: AnyPublisher<CriticalErrorEvent, Never> { get }
    
    /// Publisher for recoverable errors with suggested actions
    var recoverableErrorPublisher: AnyPublisher<RecoverableErrorEvent, Never> { get }
    
    // MARK: - Error Event Subscription Methods
    
    /// Subscribe to authentication errors with a completion handler
    /// - Parameter handler: Called whenever an authentication error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeAuthenticationErrors(_ handler: @escaping (AuthenticationErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to tweet posting errors with a completion handler
    /// - Parameter handler: Called whenever a tweet posting error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeTweetPostErrors(_ handler: @escaping (TweetPostErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to token management errors with a completion handler
    /// - Parameter handler: Called whenever a token error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeTokenErrors(_ handler: @escaping (TokenErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to rate limiting errors with a completion handler
    /// - Parameter handler: Called whenever a rate limit error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeRateLimitErrors(_ handler: @escaping (RateLimitErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to network errors with a completion handler
    /// - Parameter handler: Called whenever a network error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeNetworkErrors(_ handler: @escaping (NetworkErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to queue management errors with a completion handler
    /// - Parameter handler: Called whenever a queue error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeQueueErrors(_ handler: @escaping (QueueErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to persistence errors with a completion handler
    /// - Parameter handler: Called whenever a persistence error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observePersistenceErrors(_ handler: @escaping (PersistenceErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to security errors with a completion handler
    /// - Parameter handler: Called whenever a security error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeSecurityErrors(_ handler: @escaping (SecurityErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to all error events with a completion handler
    /// - Parameter handler: Called whenever any error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeAllErrors(_ handler: @escaping (ErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to critical errors requiring immediate attention
    /// - Parameter handler: Called whenever a critical error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeCriticalErrors(_ handler: @escaping (CriticalErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to recoverable errors with suggested actions
    /// - Parameter handler: Called whenever a recoverable error occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeRecoverableErrors(_ handler: @escaping (RecoverableErrorEvent) -> Void) -> AnyCancellable
    
    // MARK: - Error Filtering and Querying Methods
    
    /// Subscribe to errors of specific severity levels
    /// - Parameters:
    ///   - severities: Array of severity levels to watch for
    ///   - handler: Called when an error of specified severity occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeErrorsBySeverity(_ severities: [ErrorSeverity], handler: @escaping (ErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to errors in specific categories
    /// - Parameters:
    ///   - categories: Array of error categories to watch for
    ///   - handler: Called when an error in specified category occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeErrorsByCategory(_ categories: [ErrorCategory], handler: @escaping (ErrorEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to errors requiring specific recovery actions
    /// - Parameters:
    ///   - actions: Array of recovery actions to watch for
    ///   - handler: Called when an error requiring specified action occurs
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeErrorsByRecoveryAction(_ actions: [ErrorRecoveryAction], handler: @escaping (ErrorEvent) -> Void) -> AnyCancellable
    
    // MARK: - Error Context and Analysis Methods
    
    /// Gets the most recent error events
    /// - Parameter limit: Maximum number of recent errors to return
    /// - Returns: Array of recent error events ordered by timestamp
    func getRecentErrors(limit: Int) -> [ErrorEvent]
    
    /// Gets error events in a specific time range
    /// - Parameters:
    ///   - startDate: Start of the time range
    ///   - endDate: End of the time range
    /// - Returns: Array of error events within the time range
    func getErrorsInTimeRange(startDate: Date, endDate: Date) -> [ErrorEvent]
    
    /// Gets error statistics for monitoring and analysis
    /// - Returns: Statistics about error frequency and patterns
    func getErrorStatistics() -> ErrorStatistics
    
    /// Gets error patterns and trends analysis
    /// - Returns: Analysis of error patterns over time
    func getErrorAnalysis() -> ErrorAnalysis
    
    /// Checks if there are any unresolved critical errors
    /// - Returns: True if there are critical errors requiring attention
    func hasUnresolvedCriticalErrors() -> Bool
    
    /// Gets the current error state summary
    /// - Returns: Summary of current error conditions
    func getCurrentErrorState() -> ErrorStateSummary
    
    // MARK: - Error Resolution and Recovery Methods
    
    /// Marks an error as resolved
    /// - Parameter errorId: Unique identifier of the error event
    func markErrorAsResolved(_ errorId: UUID)
    
    /// Marks multiple errors as resolved
    /// - Parameter errorIds: Array of error identifiers to mark as resolved
    func markErrorsAsResolved(_ errorIds: [UUID])
    
    /// Attempts automatic recovery for recoverable errors
    /// - Returns: Number of errors that were automatically recovered
    @discardableResult
    func attemptAutomaticErrorRecovery() async -> Int
    
    /// Gets recovery suggestions for a specific error
    /// - Parameter errorId: Unique identifier of the error event
    /// - Returns: Array of suggested recovery actions
    func getRecoverySuggestions(for errorId: UUID) -> [ErrorRecoveryAction]
    
    /// Executes a recovery action for an error
    /// - Parameters:
    ///   - action: Recovery action to execute
    ///   - errorId: Error identifier to apply recovery to
    /// - Returns: True if recovery action was successful
    func executeRecoveryAction(_ action: ErrorRecoveryAction, for errorId: UUID) async -> Bool
    
    // MARK: - Error Notification and Alerting Methods
    
    /// Configure error notification preferences
    /// - Parameter preferences: Notification preferences for different error types
    func configureErrorNotifications(_ preferences: ErrorNotificationPreferences)
    
    /// Gets current error notification preferences
    /// - Returns: Current notification preferences
    func getErrorNotificationPreferences() -> ErrorNotificationPreferences
    
    /// Enables or disables error notifications
    /// - Parameter enabled: Whether error notifications should be enabled
    func setErrorNotificationsEnabled(_ enabled: Bool)
    
    /// Checks if error notifications are currently enabled
    /// - Returns: True if error notifications are enabled
    func areErrorNotificationsEnabled() -> Bool
    
    /// Sets the minimum severity level for error notifications
    /// - Parameter severity: Minimum severity level to trigger notifications
    func setMinimumNotificationSeverity(_ severity: ErrorSeverity)
    
    /// Gets the current minimum severity level for notifications
    /// - Returns: Current minimum severity level
    func getMinimumNotificationSeverity() -> ErrorSeverity
    
    // MARK: - Error Logging and Reporting Methods
    
    /// Enables or disables error logging to persistent storage
    /// - Parameter enabled: Whether error logging should be enabled
    func setErrorLoggingEnabled(_ enabled: Bool)
    
    /// Checks if error logging is currently enabled
    /// - Returns: True if error logging is enabled
    func isErrorLoggingEnabled() -> Bool
    
    /// Exports error logs for analysis or support
    /// - Parameter format: Export format for error logs
    /// - Returns: Exported error log data
    func exportErrorLogs(format: ErrorLogExportFormat) async -> Data?
    
    /// Clears error logs older than specified date
    /// - Parameter cutoffDate: Date before which errors should be cleared
    func clearErrorLogs(olderThan cutoffDate: Date) async
    
    /// Gets the size of stored error logs
    /// - Returns: Size of error logs in bytes
    func getErrorLogSize() -> Int64
    
    /// Submits error report for analysis (anonymized)
    /// - Parameter errorId: Error identifier to submit report for
    /// - Returns: True if report was successfully submitted
    func submitErrorReport(for errorId: UUID) async -> Bool
    
    // MARK: - Error Prevention and Monitoring Methods
    
    /// Gets error prevention recommendations based on error patterns
    /// - Returns: Array of recommendations to prevent common errors
    func getErrorPreventionRecommendations() -> [ErrorPreventionRecommendation]
    
    /// Checks system health to identify potential error conditions
    /// - Returns: Health status with potential issues
    func performErrorPreventionCheck() async -> ErrorPreventionStatus
    
    /// Monitors for error patterns that might indicate system issues
    /// - Parameter handler: Called when potential system issues are detected
    /// - Returns: AnyCancellable to store and manage the subscription
    func monitorForErrorPatterns(_ handler: @escaping (ErrorPatternAlert) -> Void) -> AnyCancellable
    
    /// Gets error threshold alerts when certain limits are exceeded
    /// - Parameter handler: Called when error thresholds are exceeded
    /// - Returns: AnyCancellable to store and manage the subscription
    func observeErrorThresholdAlerts(_ handler: @escaping (ErrorThresholdAlert) -> Void) -> AnyCancellable
}

// MARK: - Error Event Types

/// Base protocol for all error events
public protocol BaseErrorEvent {
    var id: UUID { get }
    var timestamp: Date { get }
    var severity: ErrorSeverity { get }
    var category: ErrorCategory { get }
    var title: String { get }
    var message: String { get }
    var technicalDetails: String? { get }
    var userContext: ErrorUserContext { get }
    var isResolved: Bool { get }
    var resolutionTime: Date? { get }
    var recoveryActions: [ErrorRecoveryAction] { get }
}

/// Authentication-related error event
public struct AuthenticationErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Authentication-specific properties
    public let authenticationError: AuthenticationError
    public let authenticationPhase: AuthenticationPhase
    public let canRetry: Bool
    public let requiresUserIntervention: Bool
    public let affectedOperations: [AuthenticationOperation]
    
    public init(authenticationError: AuthenticationError, authenticationPhase: AuthenticationPhase, canRetry: Bool, requiresUserIntervention: Bool, affectedOperations: [AuthenticationOperation], userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.authenticationError = authenticationError
        self.authenticationPhase = authenticationPhase
        self.canRetry = canRetry
        self.requiresUserIntervention = requiresUserIntervention
        self.affectedOperations = affectedOperations
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on error type
        switch authenticationError {
        case .authenticationInProgress:
            self.severity = .low
        case .invalidCredentials:
            self.severity = .high
        case .networkError:
            self.severity = .medium
        case .tokenRefreshFailed:
            self.severity = .medium
        case .keychainError:
            self.severity = .high
        }
        
        self.category = .authentication
        self.title = authenticationError.errorTitle
        self.message = authenticationError.localizedDescription
        self.technicalDetails = authenticationError.technicalDescription
    }
}

/// Tweet posting error event
public struct TweetPostErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Tweet posting-specific properties
    public let tweetPostError: TweetPostError
    public let tweetText: String
    public let wasQueued: Bool
    public let queuePosition: Int?
    public let estimatedRetryTime: Date?
    public let affectedRateLimit: Bool
    
    public init(tweetPostError: TweetPostError, tweetText: String, wasQueued: Bool, queuePosition: Int? = nil, estimatedRetryTime: Date? = nil, affectedRateLimit: Bool = false, userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.tweetPostError = tweetPostError
        self.tweetText = tweetText
        self.wasQueued = wasQueued
        self.queuePosition = queuePosition
        self.estimatedRetryTime = estimatedRetryTime
        self.affectedRateLimit = affectedRateLimit
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on error type
        switch tweetPostError {
        case .notAuthenticated:
            self.severity = .high
        case .invalidTweetText:
            self.severity = .medium
        case .rateLimitExceeded:
            self.severity = .medium
        case .networkError:
            self.severity = .low
        case .serverError:
            self.severity = .medium
        }
        
        self.category = .posting
        self.title = tweetPostError.errorTitle
        self.message = tweetPostError.localizedDescription
        self.technicalDetails = tweetPostError.technicalDescription
    }
}

/// Token management error event
public struct TokenErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Token-specific properties
    public let tokenError: TokenError
    public let tokenType: TokenType
    public let expirationDate: Date?
    public let refreshAttempted: Bool
    public let canRecoverAutomatically: Bool
    
    public init(tokenError: TokenError, tokenType: TokenType, expirationDate: Date? = nil, refreshAttempted: Bool = false, canRecoverAutomatically: Bool = false, userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.tokenError = tokenError
        self.tokenType = tokenType
        self.expirationDate = expirationDate
        self.refreshAttempted = refreshAttempted
        self.canRecoverAutomatically = canRecoverAutomatically
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on error type
        switch tokenError {
        case .expired:
            self.severity = .medium
        case .invalid:
            self.severity = .high
        case .refreshFailed:
            self.severity = .medium
        case .notFound:
            self.severity = .high
        case .corruptedData:
            self.severity = .high
        }
        
        self.category = .token
        self.title = tokenError.errorTitle
        self.message = tokenError.localizedDescription
        self.technicalDetails = tokenError.technicalDescription
    }
}

/// Rate limiting error event
public struct RateLimitErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Rate limiting-specific properties
    public let rateLimitInfo: RateLimitInfo
    public let limitType: RateLimitType
    public let resetDate: Date?
    public let remainingQuota: Int
    public let affectedOperations: [String]
    
    public init(rateLimitInfo: RateLimitInfo, limitType: RateLimitType, resetDate: Date? = nil, remainingQuota: Int = 0, affectedOperations: [String] = [], userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.rateLimitInfo = rateLimitInfo
        self.limitType = limitType
        self.resetDate = resetDate
        self.remainingQuota = remainingQuota
        self.affectedOperations = affectedOperations
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on limit type
        switch limitType {
        case .warning:
            self.severity = .low
        case .softLimit:
            self.severity = .medium
        case .hardLimit:
            self.severity = .high
        }
        
        self.category = .rateLimit
        self.title = "Rate Limit \(limitType.description)"
        self.message = "Rate limit \(limitType.description) with \(remainingQuota) requests remaining"
        self.technicalDetails = "Rate limit info: \(rateLimitInfo)"
    }
}

/// Network-related error event
public struct NetworkErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Network-specific properties
    public let networkError: NetworkError
    public let connectionType: NetworkConnectionType
    public let affectedOperations: [NetworkOperation]
    public let willRetry: Bool
    public let retryAttempt: Int
    public let nextRetryTime: Date?
    
    public init(networkError: NetworkError, connectionType: NetworkConnectionType, affectedOperations: [NetworkOperation], willRetry: Bool, retryAttempt: Int = 0, nextRetryTime: Date? = nil, userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.networkError = networkError
        self.connectionType = connectionType
        self.affectedOperations = affectedOperations
        self.willRetry = willRetry
        self.retryAttempt = retryAttempt
        self.nextRetryTime = nextRetryTime
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on error type
        switch networkError {
        case .noConnection:
            self.severity = .medium
        case .timeout:
            self.severity = .low
        case .serverError:
            self.severity = .medium
        case .invalidResponse:
            self.severity = .low
        case .securityError:
            self.severity = .high
        }
        
        self.category = .network
        self.title = networkError.errorTitle
        self.message = networkError.localizedDescription
        self.technicalDetails = networkError.technicalDescription
    }
}

/// Queue management error event
public struct QueueErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Queue-specific properties
    public let queueError: QueueError
    public let queueSize: Int
    public let affectedPostsCount: Int
    public let queueCapacity: Int
    public let canRecover: Bool
    
    public init(queueError: QueueError, queueSize: Int, affectedPostsCount: Int, queueCapacity: Int, canRecover: Bool, userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.queueError = queueError
        self.queueSize = queueSize
        self.affectedPostsCount = affectedPostsCount
        self.queueCapacity = queueCapacity
        self.canRecover = canRecover
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on error type
        switch queueError {
        case .queueFull:
            self.severity = .medium
        case .corruptedData:
            self.severity = .high
        case .processingFailed:
            self.severity = .low
        case .storageError:
            self.severity = .high
        }
        
        self.category = .queue
        self.title = queueError.errorTitle
        self.message = queueError.localizedDescription
        self.technicalDetails = queueError.technicalDescription
    }
}

/// Persistence and storage error event
public struct PersistenceErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Persistence-specific properties
    public let persistenceError: PersistenceError
    public let storageType: StorageType
    public let dataType: PersistenceDataType
    public let affectedData: String
    public let hasBackup: Bool
    public let canRestore: Bool
    
    public init(persistenceError: PersistenceError, storageType: StorageType, dataType: PersistenceDataType, affectedData: String, hasBackup: Bool, canRestore: Bool, userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.persistenceError = persistenceError
        self.storageType = storageType
        self.dataType = dataType
        self.affectedData = affectedData
        self.hasBackup = hasBackup
        self.canRestore = canRestore
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on error type
        switch persistenceError {
        case .readFailed:
            self.severity = .medium
        case .writeFailed:
            self.severity = .high
        case .corruptedData:
            self.severity = .high
        case .accessDenied:
            self.severity = .high
        case .insufficientStorage:
            self.severity = .medium
        }
        
        self.category = .persistence
        self.title = persistenceError.errorTitle
        self.message = persistenceError.localizedDescription
        self.technicalDetails = persistenceError.technicalDescription
    }
}

/// Security-related error event
public struct SecurityErrorEvent: BaseErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let severity: ErrorSeverity
    public let category: ErrorCategory
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let userContext: ErrorUserContext
    public let isResolved: Bool
    public let resolutionTime: Date?
    public let recoveryActions: [ErrorRecoveryAction]
    
    // Security-specific properties
    public let securityError: SecurityError
    public let securityDomain: SecurityDomain
    public let threatLevel: ThreatLevel
    public let affectedAssets: [String]
    public let requiresImmediateAction: Bool
    
    public init(securityError: SecurityError, securityDomain: SecurityDomain, threatLevel: ThreatLevel, affectedAssets: [String], requiresImmediateAction: Bool, userContext: ErrorUserContext = ErrorUserContext(), recoveryActions: [ErrorRecoveryAction] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.securityError = securityError
        self.securityDomain = securityDomain
        self.threatLevel = threatLevel
        self.affectedAssets = affectedAssets
        self.requiresImmediateAction = requiresImmediateAction
        self.userContext = userContext
        self.recoveryActions = recoveryActions
        self.isResolved = false
        self.resolutionTime = nil
        
        // Determine severity based on threat level
        switch threatLevel {
        case .low:
            self.severity = .low
        case .medium:
            self.severity = .medium
        case .high:
            self.severity = .high
        case .critical:
            self.severity = .critical
        }
        
        self.category = .security
        self.title = securityError.errorTitle
        self.message = securityError.localizedDescription
        self.technicalDetails = securityError.technicalDescription
    }
}

/// Union type for all error events
public enum ErrorEvent {
    case authentication(AuthenticationErrorEvent)
    case tweetPost(TweetPostErrorEvent)
    case token(TokenErrorEvent)
    case rateLimit(RateLimitErrorEvent)
    case network(NetworkErrorEvent)
    case queue(QueueErrorEvent)
    case persistence(PersistenceErrorEvent)
    case security(SecurityErrorEvent)
    
    /// Gets the base error event properties
    public var baseEvent: BaseErrorEvent {
        switch self {
        case .authentication(let event):
            return event
        case .tweetPost(let event):
            return event
        case .token(let event):
            return event
        case .rateLimit(let event):
            return event
        case .network(let event):
            return event
        case .queue(let event):
            return event
        case .persistence(let event):
            return event
        case .security(let event):
            return event
        }
    }
}

/// Critical error event requiring immediate attention
public struct CriticalErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let underlyingError: ErrorEvent
    public let criticalityReason: String
    public let immediateActions: [ErrorRecoveryAction]
    public let escalationLevel: EscalationLevel
    public let userNotificationRequired: Bool
    
    public init(underlyingError: ErrorEvent, criticalityReason: String, immediateActions: [ErrorRecoveryAction], escalationLevel: EscalationLevel, userNotificationRequired: Bool) {
        self.id = UUID()
        self.timestamp = Date()
        self.underlyingError = underlyingError
        self.criticalityReason = criticalityReason
        self.immediateActions = immediateActions
        self.escalationLevel = escalationLevel
        self.userNotificationRequired = userNotificationRequired
    }
}

/// Recoverable error event with suggested actions
public struct RecoverableErrorEvent {
    public let id: UUID
    public let timestamp: Date
    public let underlyingError: ErrorEvent
    public let recoveryStrategies: [ErrorRecoveryStrategy]
    public let automaticRecoveryPossible: Bool
    public let estimatedRecoveryTime: TimeInterval
    public let userInterventionRequired: Bool
    
    public init(underlyingError: ErrorEvent, recoveryStrategies: [ErrorRecoveryStrategy], automaticRecoveryPossible: Bool, estimatedRecoveryTime: TimeInterval, userInterventionRequired: Bool) {
        self.id = UUID()
        self.timestamp = Date()
        self.underlyingError = underlyingError
        self.recoveryStrategies = recoveryStrategies
        self.automaticRecoveryPossible = automaticRecoveryPossible
        self.estimatedRecoveryTime = estimatedRecoveryTime
        self.userInterventionRequired = userInterventionRequired
    }
}

// MARK: - Supporting Enumerations and Types

/// Error severity levels
public enum ErrorSeverity: Int, CaseIterable, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    public var description: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .critical:
            return "Critical"
        }
    }
    
    public static func < (lhs: ErrorSeverity, rhs: ErrorSeverity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Error categories for classification
public enum ErrorCategory: CaseIterable {
    case authentication
    case posting
    case token
    case rateLimit
    case network
    case queue
    case persistence
    case security
    case system
    case unknown
    
    public var description: String {
        switch self {
        case .authentication:
            return "Authentication"
        case .posting:
            return "Tweet Posting"
        case .token:
            return "Token Management"
        case .rateLimit:
            return "Rate Limiting"
        case .network:
            return "Network"
        case .queue:
            return "Queue Management"
        case .persistence:
            return "Data Persistence"
        case .security:
            return "Security"
        case .system:
            return "System"
        case .unknown:
            return "Unknown"
        }
    }
}

/// Recovery actions that can be taken for errors
public enum ErrorRecoveryAction: CaseIterable {
    case retry
    case reauthenticate
    case clearCache
    case refreshTokens
    case checkNetworkConnection
    case contactSupport
    case waitAndRetry
    case updateCredentials
    case clearQueue
    case restoreFromBackup
    case restartApplication
    case checkSystemSettings
    case reportBug
    case none
    
    public var description: String {
        switch self {
        case .retry:
            return "Retry operation"
        case .reauthenticate:
            return "Re-authenticate with X"
        case .clearCache:
            return "Clear application cache"
        case .refreshTokens:
            return "Refresh authentication tokens"
        case .checkNetworkConnection:
            return "Check network connection"
        case .contactSupport:
            return "Contact support"
        case .waitAndRetry:
            return "Wait and retry automatically"
        case .updateCredentials:
            return "Update login credentials"
        case .clearQueue:
            return "Clear post queue"
        case .restoreFromBackup:
            return "Restore from backup"
        case .restartApplication:
            return "Restart application"
        case .checkSystemSettings:
            return "Check system settings"
        case .reportBug:
            return "Report bug"
        case .none:
            return "No action required"
        }
    }
}

/// User context information for error events
public struct ErrorUserContext {
    public let userId: String?
    public let username: String?
    public let sessionId: String?
    public let appVersion: String
    public let systemVersion: String
    public let lastActionPerformed: String?
    public let userPreferences: [String: Any]
    
    public init(userId: String? = nil, username: String? = nil, sessionId: String? = nil, appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown", systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString, lastActionPerformed: String? = nil, userPreferences: [String: Any] = [:]) {
        self.userId = userId
        self.username = username
        self.sessionId = sessionId
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.lastActionPerformed = lastActionPerformed
        self.userPreferences = userPreferences
    }
}

// MARK: - Additional Supporting Types

/// Authentication phases for error context
public enum AuthenticationPhase {
    case initialization
    case authorization
    case tokenExchange
    case tokenRefresh
    case userValidation
    case disconnection
}

/// Authentication operations that can be affected by errors
public enum AuthenticationOperation {
    case login
    case logout
    case tokenRefresh
    case postTweet
    case validateUser
    case backgroundRefresh
}

/// Token types for error context
public enum TokenType {
    case accessToken
    case refreshToken
    case both
}

/// Token errors
public enum TokenError {
    case expired
    case invalid
    case refreshFailed
    case notFound
    case corruptedData
    
    public var errorTitle: String {
        switch self {
        case .expired:
            return "Token Expired"
        case .invalid:
            return "Invalid Token"
        case .refreshFailed:
            return "Token Refresh Failed"
        case .notFound:
            return "Token Not Found"
        case .corruptedData:
            return "Token Data Corrupted"
        }
    }
    
    public var localizedDescription: String {
        switch self {
        case .expired:
            return "Authentication token has expired"
        case .invalid:
            return "Authentication token is invalid"
        case .refreshFailed:
            return "Failed to refresh authentication token"
        case .notFound:
            return "Authentication token not found"
        case .corruptedData:
            return "Authentication token data is corrupted"
        }
    }
    
    public var technicalDescription: String {
        return "Token error: \(self)"
    }
}

/// Rate limit types
public enum RateLimitType {
    case warning
    case softLimit
    case hardLimit
    
    public var description: String {
        switch self {
        case .warning:
            return "Warning"
        case .softLimit:
            return "Soft Limit"
        case .hardLimit:
            return "Hard Limit"
        }
    }
}

/// Network connection types
public enum NetworkConnectionType {
    case wifi
    case cellular
    case ethernet
    case unknown
}

/// Network operations that can be affected
public enum NetworkOperation {
    case authentication
    case tokenRefresh
    case postTweet
    case userValidation
    case general
}

/// Network errors
public enum NetworkError {
    case noConnection
    case timeout
    case serverError(Int)
    case invalidResponse
    case securityError
    
    public var errorTitle: String {
        switch self {
        case .noConnection:
            return "No Network Connection"
        case .timeout:
            return "Network Timeout"
        case .serverError(let code):
            return "Server Error (\(code))"
        case .invalidResponse:
            return "Invalid Response"
        case .securityError:
            return "Network Security Error"
        }
    }
    
    public var localizedDescription: String {
        switch self {
        case .noConnection:
            return "No network connection available"
        case .timeout:
            return "Network request timed out"
        case .serverError(let code):
            return "Server returned error code \(code)"
        case .invalidResponse:
            return "Received invalid response from server"
        case .securityError:
            return "Network security error occurred"
        }
    }
    
    public var technicalDescription: String {
        return "Network error: \(self)"
    }
}

/// Queue errors
public enum QueueError {
    case queueFull
    case corruptedData
    case processingFailed
    case storageError
    
    public var errorTitle: String {
        switch self {
        case .queueFull:
            return "Queue Full"
        case .corruptedData:
            return "Queue Data Corrupted"
        case .processingFailed:
            return "Queue Processing Failed"
        case .storageError:
            return "Queue Storage Error"
        }
    }
    
    public var localizedDescription: String {
        switch self {
        case .queueFull:
            return "Post queue is full"
        case .corruptedData:
            return "Queue data is corrupted"
        case .processingFailed:
            return "Failed to process queue"
        case .storageError:
            return "Queue storage error"
        }
    }
    
    public var technicalDescription: String {
        return "Queue error: \(self)"
    }
}

/// Persistence errors
public enum PersistenceError {
    case readFailed
    case writeFailed
    case corruptedData
    case accessDenied
    case insufficientStorage
    
    public var errorTitle: String {
        switch self {
        case .readFailed:
            return "Read Failed"
        case .writeFailed:
            return "Write Failed"
        case .corruptedData:
            return "Data Corrupted"
        case .accessDenied:
            return "Access Denied"
        case .insufficientStorage:
            return "Insufficient Storage"
        }
    }
    
    public var localizedDescription: String {
        switch self {
        case .readFailed:
            return "Failed to read data from storage"
        case .writeFailed:
            return "Failed to write data to storage"
        case .corruptedData:
            return "Stored data is corrupted"
        case .accessDenied:
            return "Access to storage was denied"
        case .insufficientStorage:
            return "Insufficient storage space available"
        }
    }
    
    public var technicalDescription: String {
        return "Persistence error: \(self)"
    }
}

/// Storage types
public enum StorageType {
    case userDefaults
    case keychain
    case fileSystem
    case coreData
    case memory
}

/// Persistence data types
public enum PersistenceDataType {
    case tokens
    case userPreferences
    case queueData
    case authenticationState
    case logs
    case cache
}

/// Security errors
public enum SecurityError {
    case unauthorizedAccess
    case dataCompromised
    case certificateInvalid
    case encryptionFailed
    case keychainViolation
    
    public var errorTitle: String {
        switch self {
        case .unauthorizedAccess:
            return "Unauthorized Access"
        case .dataCompromised:
            return "Data Compromised"
        case .certificateInvalid:
            return "Invalid Certificate"
        case .encryptionFailed:
            return "Encryption Failed"
        case .keychainViolation:
            return "Keychain Violation"
        }
    }
    
    public var localizedDescription: String {
        switch self {
        case .unauthorizedAccess:
            return "Unauthorized access attempt detected"
        case .dataCompromised:
            return "Data may have been compromised"
        case .certificateInvalid:
            return "Security certificate is invalid"
        case .encryptionFailed:
            return "Data encryption failed"
        case .keychainViolation:
            return "Keychain security violation"
        }
    }
    
    public var technicalDescription: String {
        return "Security error: \(self)"
    }
}

/// Security domains
public enum SecurityDomain {
    case authentication
    case dataStorage
    case networkCommunication
    case userPrivacy
    case systemIntegrity
}

/// Threat levels for security errors
public enum ThreatLevel {
    case low
    case medium
    case high
    case critical
}

/// Escalation levels for critical errors
public enum EscalationLevel {
    case userNotification
    case administratorAlert
    case systemShutdown
    case emergencyProtocol
}

/// Error recovery strategies
public struct ErrorRecoveryStrategy {
    public let action: ErrorRecoveryAction
    public let description: String
    public let estimatedTime: TimeInterval
    public let successProbability: Double
    public let requiresUserInput: Bool
    
    public init(action: ErrorRecoveryAction, description: String, estimatedTime: TimeInterval, successProbability: Double, requiresUserInput: Bool) {
        self.action = action
        self.description = description
        self.estimatedTime = estimatedTime
        self.successProbability = successProbability
        self.requiresUserInput = requiresUserInput
    }
}

// MARK: - Error Statistics and Analysis Types

/// Error statistics for monitoring and analysis
public struct ErrorStatistics {
    public let totalErrors: Int
    public let errorsByCategory: [ErrorCategory: Int]
    public let errorsBySeverity: [ErrorSeverity: Int]
    public let averageErrorsPerDay: Double
    public let mostCommonErrors: [String: Int]
    public let errorTrends: [String: Double]
    public let lastAnalysisDate: Date
    
    public init(totalErrors: Int, errorsByCategory: [ErrorCategory: Int], errorsBySeverity: [ErrorSeverity: Int], averageErrorsPerDay: Double, mostCommonErrors: [String: Int], errorTrends: [String: Double], lastAnalysisDate: Date = Date()) {
        self.totalErrors = totalErrors
        self.errorsByCategory = errorsByCategory
        self.errorsBySeverity = errorsBySeverity
        self.averageErrorsPerDay = averageErrorsPerDay
        self.mostCommonErrors = mostCommonErrors
        self.errorTrends = errorTrends
        self.lastAnalysisDate = lastAnalysisDate
    }
}

/// Error analysis and patterns
public struct ErrorAnalysis {
    public let patternAnalysis: ErrorPatternAnalysis
    public let correlationAnalysis: ErrorCorrelationAnalysis
    public let predictionAnalysis: ErrorPredictionAnalysis
    public let recommendedActions: [ErrorPreventionRecommendation]
    public let analysisGeneratedDate: Date
    
    public init(patternAnalysis: ErrorPatternAnalysis, correlationAnalysis: ErrorCorrelationAnalysis, predictionAnalysis: ErrorPredictionAnalysis, recommendedActions: [ErrorPreventionRecommendation], analysisGeneratedDate: Date = Date()) {
        self.patternAnalysis = patternAnalysis
        self.correlationAnalysis = correlationAnalysis
        self.predictionAnalysis = predictionAnalysis
        self.recommendedActions = recommendedActions
        self.analysisGeneratedDate = analysisGeneratedDate
    }
}

/// Error pattern analysis
public struct ErrorPatternAnalysis {
    public let repeatingPatterns: [ErrorPattern]
    public let seasonalTrends: [SeasonalTrend]
    public let anomalousEvents: [AnomalousEvent]
    public let correlatedErrors: [ErrorCorrelation]
    
    public init(repeatingPatterns: [ErrorPattern], seasonalTrends: [SeasonalTrend], anomalousEvents: [AnomalousEvent], correlatedErrors: [ErrorCorrelation]) {
        self.repeatingPatterns = repeatingPatterns
        self.seasonalTrends = seasonalTrends
        self.anomalousEvents = anomalousEvents
        self.correlatedErrors = correlatedErrors
    }
}

/// Error correlation analysis
public struct ErrorCorrelationAnalysis {
    public let strongCorrelations: [ErrorCorrelation]
    public let weakCorrelations: [ErrorCorrelation]
    public let causalRelationships: [CausalRelationship]
    public let independentErrors: [ErrorCategory]
    
    public init(strongCorrelations: [ErrorCorrelation], weakCorrelations: [ErrorCorrelation], causalRelationships: [CausalRelationship], independentErrors: [ErrorCategory]) {
        self.strongCorrelations = strongCorrelations
        self.weakCorrelations = weakCorrelations
        self.causalRelationships = causalRelationships
        self.independentErrors = independentErrors
    }
}

/// Error prediction analysis
public struct ErrorPredictionAnalysis {
    public let predictedErrors: [PredictedError]
    public let riskFactors: [RiskFactor]
    public let confidenceLevel: Double
    public let predictionTimeframe: TimeInterval
    
    public init(predictedErrors: [PredictedError], riskFactors: [RiskFactor], confidenceLevel: Double, predictionTimeframe: TimeInterval) {
        self.predictedErrors = predictedErrors
        self.riskFactors = riskFactors
        self.confidenceLevel = confidenceLevel
        self.predictionTimeframe = predictionTimeframe
    }
}

/// Current error state summary
public struct ErrorStateSummary {
    public let hasActiveErrors: Bool
    public let criticalErrorCount: Int
    public let highSeverityErrorCount: Int
    public let unresolvedErrorCount: Int
    public let lastErrorTime: Date?
    public let systemHealthScore: Double
    public let recommendedActions: [ErrorRecoveryAction]
    
    public init(hasActiveErrors: Bool, criticalErrorCount: Int, highSeverityErrorCount: Int, unresolvedErrorCount: Int, lastErrorTime: Date?, systemHealthScore: Double, recommendedActions: [ErrorRecoveryAction]) {
        self.hasActiveErrors = hasActiveErrors
        self.criticalErrorCount = criticalErrorCount
        self.highSeverityErrorCount = highSeverityErrorCount
        self.unresolvedErrorCount = unresolvedErrorCount
        self.lastErrorTime = lastErrorTime
        self.systemHealthScore = systemHealthScore
        self.recommendedActions = recommendedActions
    }
}

// MARK: - Error Notification and Configuration Types

/// Error notification preferences
public struct ErrorNotificationPreferences {
    public let enabledCategories: Set<ErrorCategory>
    public let minimumSeverity: ErrorSeverity
    public let notificationMethods: Set<NotificationMethod>
    public let quietHours: TimeRange?
    public let maxNotificationsPerHour: Int
    public let groupSimilarErrors: Bool
    
    public init(enabledCategories: Set<ErrorCategory> = Set(ErrorCategory.allCases), minimumSeverity: ErrorSeverity = .medium, notificationMethods: Set<NotificationMethod> = [.inApp], quietHours: TimeRange? = nil, maxNotificationsPerHour: Int = 10, groupSimilarErrors: Bool = true) {
        self.enabledCategories = enabledCategories
        self.minimumSeverity = minimumSeverity
        self.notificationMethods = notificationMethods
        self.quietHours = quietHours
        self.maxNotificationsPerHour = maxNotificationsPerHour
        self.groupSimilarErrors = groupSimilarErrors
    }
}

/// Notification methods
public enum NotificationMethod {
    case inApp
    case systemNotification
    case email
    case log
}

/// Time range for quiet hours
public struct TimeRange {
    public let startHour: Int
    public let endHour: Int
    
    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }
}

/// Error log export formats
public enum ErrorLogExportFormat {
    case json
    case csv
    case xml
    case plain
    
    public var fileExtension: String {
        switch self {
        case .json:
            return "json"
        case .csv:
            return "csv"
        case .xml:
            return "xml"
        case .plain:
            return "txt"
        }
    }
}

/// Error prevention recommendation
public struct ErrorPreventionRecommendation {
    public let id: UUID
    public let title: String
    public let description: String
    public let category: ErrorCategory
    public let priority: RecommendationPriority
    public let estimatedImpact: Double
    public let implementationEffort: ImplementationEffort
    public let actions: [PreventionAction]
    
    public init(title: String, description: String, category: ErrorCategory, priority: RecommendationPriority, estimatedImpact: Double, implementationEffort: ImplementationEffort, actions: [PreventionAction]) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.category = category
        self.priority = priority
        self.estimatedImpact = estimatedImpact
        self.implementationEffort = implementationEffort
        self.actions = actions
    }
}

/// Recommendation priority levels
public enum RecommendationPriority {
    case low
    case medium
    case high
    case critical
}

/// Implementation effort levels
public enum ImplementationEffort {
    case minimal
    case low
    case medium
    case high
    case extensive
}

/// Prevention actions
public struct PreventionAction {
    public let description: String
    public let actionType: PreventionActionType
    public let automated: Bool
    public let estimatedTime: TimeInterval
    
    public init(description: String, actionType: PreventionActionType, automated: Bool, estimatedTime: TimeInterval) {
        self.description = description
        self.actionType = actionType
        self.automated = automated
        self.estimatedTime = estimatedTime
    }
}

/// Types of prevention actions
public enum PreventionActionType {
    case configuration
    case monitoring
    case validation
    case redundancy
    case optimization
    case userEducation
}

/// Error prevention status
public struct ErrorPreventionStatus {
    public let overallHealthScore: Double
    public let identifiedRisks: [RiskFactor]
    public let preventionMeasures: [PreventionMeasure]
    public let recommendations: [ErrorPreventionRecommendation]
    public let lastCheckDate: Date
    
    public init(overallHealthScore: Double, identifiedRisks: [RiskFactor], preventionMeasures: [PreventionMeasure], recommendations: [ErrorPreventionRecommendation], lastCheckDate: Date = Date()) {
        self.overallHealthScore = overallHealthScore
        self.identifiedRisks = identifiedRisks
        self.preventionMeasures = preventionMeasures
        self.recommendations = recommendations
        self.lastCheckDate = lastCheckDate
    }
}

/// Risk factors for error prediction
public struct RiskFactor {
    public let name: String
    public let description: String
    public let severity: RiskSeverity
    public let likelihood: Double
    public let impact: Double
    public let category: ErrorCategory
    
    public init(name: String, description: String, severity: RiskSeverity, likelihood: Double, impact: Double, category: ErrorCategory) {
        self.name = name
        self.description = description
        self.severity = severity
        self.likelihood = likelihood
        self.impact = impact
        self.category = category
    }
}

/// Risk severity levels
public enum RiskSeverity {
    case low
    case medium
    case high
    case critical
}

/// Prevention measures in place
public struct PreventionMeasure {
    public let name: String
    public let description: String
    public let effectiveness: Double
    public let isActive: Bool
    public let category: ErrorCategory
    
    public init(name: String, description: String, effectiveness: Double, isActive: Bool, category: ErrorCategory) {
        self.name = name
        self.description = description
        self.effectiveness = effectiveness
        self.isActive = isActive
        self.category = category
    }
}

/// Error pattern alerts
public struct ErrorPatternAlert {
    public let id: UUID
    public let pattern: ErrorPattern
    public let alertLevel: AlertLevel
    public let description: String
    public let recommendedActions: [ErrorRecoveryAction]
    public let timestamp: Date
    
    public init(pattern: ErrorPattern, alertLevel: AlertLevel, description: String, recommendedActions: [ErrorRecoveryAction]) {
        self.id = UUID()
        self.pattern = pattern
        self.alertLevel = alertLevel
        self.description = description
        self.recommendedActions = recommendedActions
        self.timestamp = Date()
    }
}

/// Error threshold alerts
public struct ErrorThresholdAlert {
    public let id: UUID
    public let threshold: ErrorThreshold
    public let currentValue: Double
    public let alertLevel: AlertLevel
    public let description: String
    public let timestamp: Date
    
    public init(threshold: ErrorThreshold, currentValue: Double, alertLevel: AlertLevel, description: String) {
        self.id = UUID()
        self.threshold = threshold
        self.currentValue = currentValue
        self.alertLevel = alertLevel
        self.description = description
        self.timestamp = Date()
    }
}

/// Alert levels
public enum AlertLevel {
    case info
    case warning
    case critical
    case emergency
}

/// Error thresholds for monitoring
public struct ErrorThreshold {
    public let name: String
    public let category: ErrorCategory
    public let metric: ThresholdMetric
    public let warningValue: Double
    public let criticalValue: Double
    public let timeWindow: TimeInterval
    
    public init(name: String, category: ErrorCategory, metric: ThresholdMetric, warningValue: Double, criticalValue: Double, timeWindow: TimeInterval) {
        self.name = name
        self.category = category
        self.metric = metric
        self.warningValue = warningValue
        self.criticalValue = criticalValue
        self.timeWindow = timeWindow
    }
}

/// Threshold metrics
public enum ThresholdMetric {
    case errorRate
    case errorCount
    case errorFrequency
    case severityScore
    case resolutionTime
}

// MARK: - Additional Supporting Types for Analysis

/// Error patterns identified in the system
public struct ErrorPattern {
    public let id: UUID
    public let name: String
    public let description: String
    public let frequency: Double
    public let categories: [ErrorCategory]
    public let timePattern: TimePattern
    public let triggerConditions: [String]
    
    public init(name: String, description: String, frequency: Double, categories: [ErrorCategory], timePattern: TimePattern, triggerConditions: [String]) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.frequency = frequency
        self.categories = categories
        self.timePattern = timePattern
        self.triggerConditions = triggerConditions
    }
}

/// Time patterns for error occurrence
public enum TimePattern {
    case random
    case periodic(TimeInterval)
    case seasonal(Season)
    case workingHours
    case specificTimes([Date])
}

/// Seasonal patterns
public enum Season {
    case daily
    case weekly
    case monthly
    case yearly
}

/// Seasonal trends in error occurrence
public struct SeasonalTrend {
    public let pattern: Season
    public let category: ErrorCategory
    public let peakTimes: [String]
    public let lowTimes: [String]
    public let magnitude: Double
    
    public init(pattern: Season, category: ErrorCategory, peakTimes: [String], lowTimes: [String], magnitude: Double) {
        self.pattern = pattern
        self.category = category
        self.peakTimes = peakTimes
        self.lowTimes = lowTimes
        self.magnitude = magnitude
    }
}

/// Anomalous error events
public struct AnomalousEvent {
    public let id: UUID
    public let event: ErrorEvent
    public let anomalyScore: Double
    public let explanation: String
    public let timestamp: Date
    
    public init(event: ErrorEvent, anomalyScore: Double, explanation: String) {
        self.id = UUID()
        self.event = event
        self.anomalyScore = anomalyScore
        self.explanation = explanation
        self.timestamp = Date()
    }
}

/// Error correlations
public struct ErrorCorrelation {
    public let primaryCategory: ErrorCategory
    public let secondaryCategory: ErrorCategory
    public let strength: Double
    public let confidence: Double
    public let description: String
    
    public init(primaryCategory: ErrorCategory, secondaryCategory: ErrorCategory, strength: Double, confidence: Double, description: String) {
        self.primaryCategory = primaryCategory
        self.secondaryCategory = secondaryCategory
        self.strength = strength
        self.confidence = confidence
        self.description = description
    }
}

/// Causal relationships between errors
public struct CausalRelationship {
    public let causeCategory: ErrorCategory
    public let effectCategory: ErrorCategory
    public let strength: Double
    public let delay: TimeInterval
    public let description: String
    
    public init(causeCategory: ErrorCategory, effectCategory: ErrorCategory, strength: Double, delay: TimeInterval, description: String) {
        self.causeCategory = causeCategory
        self.effectCategory = effectCategory
        self.strength = strength
        self.delay = delay
        self.description = description
    }
}

/// Predicted errors based on analysis
public struct PredictedError {
    public let category: ErrorCategory
    public let severity: ErrorSeverity
    public let probability: Double
    public let estimatedTime: Date
    public let confidence: Double
    public let preventionActions: [PreventionAction]
    
    public init(category: ErrorCategory, severity: ErrorSeverity, probability: Double, estimatedTime: Date, confidence: Double, preventionActions: [PreventionAction]) {
        self.category = category
        self.severity = severity
        self.probability = probability
        self.estimatedTime = estimatedTime
        self.confidence = confidence
        self.preventionActions = preventionActions
    }
}

// MARK: - Protocol Extensions with Error Handling Utilities

/// Extension providing convenience methods for error handling
public extension ErrorEventEmissionProtocol {
    
    /// Convenience method to check if there are any active errors
    /// - Returns: True if there are unresolved errors
    func hasActiveErrors() -> Bool {
        return hasUnresolvedCriticalErrors() || getCurrentErrorState().hasActiveErrors
    }
    
    /// Convenience method to get the most severe unresolved error
    /// - Returns: The most severe unresolved error, if any
    func getMostSevereError() -> ErrorEvent? {
        let recentErrors = getRecentErrors(limit: 100)
        return recentErrors
            .filter { !$0.baseEvent.isResolved }
            .max { $0.baseEvent.severity < $1.baseEvent.severity }
    }
    
    /// Convenience method to get error count by category
    /// - Parameter category: Error category to count
    /// - Returns: Number of errors in the specified category
    func getErrorCount(for category: ErrorCategory) -> Int {
        return getErrorStatistics().errorsByCategory[category] ?? 0
    }
    
    /// Convenience method to check if specific error types are occurring frequently
    /// - Parameter category: Error category to check
    /// - Parameter threshold: Frequency threshold
    /// - Returns: True if errors in category exceed threshold
    func isErrorFrequent(_ category: ErrorCategory, threshold: Double) -> Bool {
        let statistics = getErrorStatistics()
        let categoryCount = statistics.errorsByCategory[category] ?? 0
        let frequency = Double(categoryCount) / statistics.averageErrorsPerDay
        return frequency > threshold
    }
}
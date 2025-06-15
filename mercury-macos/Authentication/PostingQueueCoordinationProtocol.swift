import Foundation
import Combine

/// Protocol defining the posting queue coordination interface for core app integration
/// This protocol abstracts posting queue operations and provides a clean interface
/// for the core Mercury app to manage post queuing, retry logic, and status monitoring
@MainActor
public protocol PostingQueueCoordinationProtocol: ObservableObject {
    
    // MARK: - Published Properties for Reactive UI
    
    /// Number of posts currently queued for retry
    var queuedPostsCount: Int { get }
    
    /// Number of preserved posts waiting for restoration after re-authentication
    var preservedPostsCount: Int { get }
    
    // MARK: - Combine Publishers for State Observation
    
    /// Publisher for queued posts count changes
    var queuedPostsCountPublisher: AnyPublisher<Int, Never> { get }
    
    /// Publisher for preserved posts count changes
    var preservedPostsCountPublisher: AnyPublisher<Int, Never> { get }
    
    /// Publisher for queue status notifications (successes, failures, warnings)
    var queueNotificationsPublisher: AnyPublisher<[PostQueueNotification], Never> { get }
    
    /// Publisher for queue processing state changes
    var queueProcessingStatePublisher: AnyPublisher<PostQueueProcessingState, Never> { get }
    
    /// Combined publisher for comprehensive queue state monitoring
    var combinedQueueStatePublisher: AnyPublisher<PostQueueState, Never> { get }
    
    // MARK: - Core Post Queuing Methods
    
    /// Queues a post for retry if immediate posting fails
    /// - Parameter text: Tweet content to queue
    /// - Parameter metadata: Optional metadata for the post (source, timestamp, etc.)
    /// - Returns: True if post was successfully queued
    func queuePost(_ text: String, metadata: PostMetadata?) async -> Bool
    
    /// Queues a post with priority for urgent posts
    /// - Parameter text: Tweet content to queue
    /// - Parameter priority: Priority level for processing order
    /// - Parameter metadata: Optional metadata for the post
    /// - Returns: True if post was successfully queued
    func queuePostWithPriority(_ text: String, priority: PostPriority, metadata: PostMetadata?) async -> Bool
    
    /// Processes all queued posts with available authentication
    /// - Returns: Number of posts successfully processed and posted
    @discardableResult
    func processQueuedPosts() async -> Int
    
    /// Processes queued posts up to a specified limit
    /// - Parameter limit: Maximum number of posts to process
    /// - Returns: Number of posts successfully processed
    @discardableResult
    func processQueuedPosts(limit: Int) async -> Int
    
    /// Forces processing of all queued posts regardless of retry schedules
    /// - Returns: Number of posts successfully processed
    @discardableResult
    func forceProcessAllQueuedPosts() async -> Int
    
    // MARK: - Queue Status and Information Methods
    
    /// Gets the current number of queued posts
    /// - Returns: Number of posts waiting for retry
    func getQueuedPostsCount() -> Int
    
    /// Gets the current number of preserved posts
    /// - Returns: Number of posts preserved during re-authentication
    func getPreservedPostsCount() -> Int
    
    /// Gets the total number of pending posts (queued + preserved)
    /// - Returns: Total posts waiting to be processed
    func getTotalPendingPostsCount() -> Int
    
    /// Gets summary information about queued posts
    /// - Returns: Array of queued post summaries for UI display
    func getQueuedPostsSummary() async -> [QueuedPostSummary]
    
    /// Gets summary information about preserved posts
    /// - Returns: Array of preserved post summaries for UI display
    func getPreservedPostsSummary() async -> [PreservedPostSummary]
    
    /// Gets comprehensive queue status information
    /// - Returns: Current queue status including processing state and statistics
    func getQueueStatus() async -> PostQueueStatus
    
    /// Gets queue processing statistics for monitoring
    /// - Returns: Statistics about queue performance and retry success rates
    func getQueueStatistics() -> PostQueueStatistics
    
    // MARK: - Individual Post Management Methods
    
    /// Removes a specific post from the queue
    /// - Parameter postId: Unique identifier of the post to remove
    func removeQueuedPost(_ postId: UUID) async
    
    /// Removes multiple posts from the queue
    /// - Parameter postIds: Array of post identifiers to remove
    func removeQueuedPosts(_ postIds: [UUID]) async
    
    /// Manually retries a specific queued post immediately
    /// - Parameter postId: Unique identifier of the post to retry
    /// - Returns: True if retry was successful
    func retryQueuedPost(_ postId: UUID) async -> Bool
    
    /// Updates the priority of a queued post
    /// - Parameter postId: Unique identifier of the post
    /// - Parameter priority: New priority level
    func updatePostPriority(_ postId: UUID, priority: PostPriority) async
    
    /// Updates the metadata of a queued post
    /// - Parameter postId: Unique identifier of the post
    /// - Parameter metadata: New metadata to associate with the post
    func updatePostMetadata(_ postId: UUID, metadata: PostMetadata) async
    
    // MARK: - Queue Control Methods
    
    /// Pauses automatic processing of queued posts
    func pauseQueueProcessing()
    
    /// Resumes automatic processing of queued posts
    func resumeQueueProcessing()
    
    /// Clears all queued posts (with confirmation for safety)
    /// - Parameter confirm: Safety confirmation flag
    func clearQueuedPosts(confirm: Bool) async
    
    /// Clears all preserved posts (with confirmation for safety)
    /// - Parameter confirm: Safety confirmation flag
    func clearPreservedPosts(confirm: Bool) async
    
    /// Clears all posts (queued + preserved) with confirmation
    /// - Parameter confirm: Safety confirmation flag
    func clearAllPosts(confirm: Bool) async
    
    // MARK: - Deduplication and Validation Methods
    
    /// Checks if a post would be considered a duplicate
    /// - Parameter text: Tweet content to check
    /// - Returns: True if post would be considered duplicate
    func wouldPostBeDuplicate(_ text: String) async -> Bool
    
    /// Validates post content before queuing
    /// - Parameter text: Tweet content to validate
    /// - Returns: Validation result with details about any issues
    func validatePostContent(_ text: String) -> PostValidationResult
    
    /// Estimates processing time for current queue
    /// - Returns: Estimated time until all posts are processed
    func estimateQueueProcessingTime() async -> TimeInterval
    
    /// Checks if the queue has capacity for more posts
    /// - Returns: True if more posts can be queued
    func hasQueueCapacity() -> Bool
    
    /// Gets the current queue capacity information
    /// - Returns: Queue capacity details including limits and usage
    func getQueueCapacityInfo() -> QueueCapacityInfo
    
    // MARK: - Notification Management Methods
    
    /// Gets all queue-related notifications
    /// - Returns: Array of current queue notifications
    func getQueueNotifications() -> [PostQueueNotification]
    
    /// Gets unread queue notifications
    /// - Returns: Array of unread queue notifications
    func getUnreadQueueNotifications() -> [PostQueueNotification]
    
    /// Marks a notification as read
    /// - Parameter notificationId: Unique identifier of the notification
    func markNotificationAsRead(_ notificationId: UUID)
    
    /// Marks all notifications as read
    func markAllNotificationsAsRead()
    
    /// Dismisses a notification
    /// - Parameter notificationId: Unique identifier of the notification to dismiss
    func dismissNotification(_ notificationId: UUID)
    
    /// Dismisses all notifications
    func dismissAllNotifications()
    
    /// Gets notification statistics for monitoring
    /// - Returns: Statistics about notification frequency and types
    func getNotificationStatistics() -> QueueNotificationStatistics
    
    // MARK: - Network and Connectivity Integration Methods
    
    /// Processes queue when network connectivity is restored
    /// - Returns: Number of posts successfully processed
    @discardableResult
    func processQueueOnNetworkRestore() async -> Int
    
    /// Prepares queue for network disconnection
    func prepareForNetworkDisconnection() async
    
    /// Handles changes in network connectivity state
    /// - Parameter isConnected: Current network connectivity state
    func handleNetworkConnectivityChange(_ isConnected: Bool) async
    
    /// Gets queue behavior for current network conditions
    /// - Returns: How the queue will behave given current network state
    func getQueueBehaviorForNetworkConditions() -> QueueNetworkBehavior
    
    // MARK: - App Lifecycle Integration Methods
    
    /// Prepares queue for app backgrounding
    func prepareQueueForBackground() async
    
    /// Handles app returning to foreground
    func handleQueueOnForegroundRestore() async
    
    /// Prepares queue for app termination
    func prepareQueueForTermination() async
    
    /// Saves queue state for persistence
    /// - Parameter reason: Reason for the save operation
    /// - Returns: True if save was successful
    func saveQueueState(reason: String) async -> Bool
    
    /// Restores queue state from persistence
    /// - Parameter reason: Reason for the restore operation
    /// - Returns: True if restore was successful
    func restoreQueueState(reason: String) async -> Bool
    
    // MARK: - Preserved Posts Management Methods
    
    /// Preserves queued posts during re-authentication
    /// - Returns: Number of posts preserved
    func preserveQueuedPosts() async -> Int
    
    /// Restores preserved posts after successful authentication
    /// - Returns: Number of posts restored to queue
    func restorePreservedPosts() async -> Int
    
    /// Converts preserved posts back to queued posts
    /// - Parameter postIds: Specific posts to restore, or nil for all
    /// - Returns: Number of posts converted back to queued
    func convertPreservedToQueued(_ postIds: [UUID]?) async -> Int
    
    /// Permanently deletes preserved posts (after user confirmation)
    /// - Parameter postIds: Specific posts to delete, or nil for all
    /// - Parameter confirm: Safety confirmation flag
    func deletePreservedPosts(_ postIds: [UUID]?, confirm: Bool) async
    
    // MARK: - Advanced Queue Management Methods
    
    /// Reorders posts in the queue based on priority and age
    func optimizeQueueOrder() async
    
    /// Merges similar posts in the queue to reduce duplicates
    /// - Returns: Number of posts merged/removed
    func mergeSimilarPosts() async -> Int
    
    /// Archives old posts that have failed too many times
    /// - Returns: Number of posts archived
    func archiveFailedPosts() async -> Int
    
    /// Gets archived posts for review
    /// - Returns: Array of archived post summaries
    func getArchivedPosts() -> [ArchivedPostSummary]
    
    /// Restores archived posts to the active queue
    /// - Parameter postIds: Specific posts to restore
    /// - Returns: Number of posts restored
    func restoreArchivedPosts(_ postIds: [UUID]) async -> Int
    
    // MARK: - Monitoring and Analytics Methods
    
    /// Gets comprehensive analytics about queue performance
    /// - Returns: Analytics data for monitoring and optimization
    func getQueueAnalytics() -> PostQueueAnalytics
    
    /// Exports queue data for external analysis
    /// - Parameter format: Export format (JSON, CSV, etc.)
    /// - Returns: Exported data in requested format
    func exportQueueData(format: QueueDataExportFormat) async -> Data?
    
    /// Gets health status of the queue system
    /// - Returns: Health status with any issues or recommendations
    func getQueueHealthStatus() -> QueueHealthStatus
    
    /// Performs diagnostic check on queue integrity
    /// - Returns: Diagnostic results with any issues found
    func performQueueDiagnostics() async -> QueueDiagnosticsResult
}

// MARK: - Supporting Data Types

/// Represents the current state of the posting queue
public struct PostQueueState {
    public let queuedCount: Int
    public let preservedCount: Int
    public let processingState: PostQueueProcessingState
    public let lastProcessedTime: Date?
    public let nextScheduledProcessing: Date?
    public let notifications: [PostQueueNotification]
    public let statistics: PostQueueStatistics
    
    public init(queuedCount: Int, preservedCount: Int, processingState: PostQueueProcessingState, lastProcessedTime: Date?, nextScheduledProcessing: Date?, notifications: [PostQueueNotification], statistics: PostQueueStatistics) {
        self.queuedCount = queuedCount
        self.preservedCount = preservedCount
        self.processingState = processingState
        self.lastProcessedTime = lastProcessedTime
        self.nextScheduledProcessing = nextScheduledProcessing
        self.notifications = notifications
        self.statistics = statistics
    }
}

/// Processing state of the queue system
public enum PostQueueProcessingState: CaseIterable {
    case idle
    case processing
    case paused
    case error(String)
    case waitingForNetwork
    case waitingForAuthentication
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .processing:
            return "Processing posts..."
        case .paused:
            return "Paused"
        case .error(let message):
            return "Error: \(message)"
        case .waitingForNetwork:
            return "Waiting for network"
        case .waitingForAuthentication:
            return "Waiting for authentication"
        }
    }
    
    /// Whether processing can be initiated in this state
    public var canProcess: Bool {
        switch self {
        case .idle:
            return true
        case .processing, .paused, .error, .waitingForNetwork, .waitingForAuthentication:
            return false
        }
    }
}

/// Priority levels for post processing
public enum PostPriority: Int, CaseIterable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
    
    public var description: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        case .urgent:
            return "Urgent"
        }
    }
    
    public static func < (lhs: PostPriority, rhs: PostPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Metadata associated with a queued post
public struct PostMetadata {
    public let source: String
    public let timestamp: Date
    public let userContext: [String: Any]
    public let retryReason: String?
    public let originalAttemptTime: Date
    
    public init(source: String, timestamp: Date = Date(), userContext: [String: Any] = [:], retryReason: String? = nil, originalAttemptTime: Date = Date()) {
        self.source = source
        self.timestamp = timestamp
        self.userContext = userContext
        self.retryReason = retryReason
        self.originalAttemptTime = originalAttemptTime
    }
}

/// Summary information about a queued post for UI display
public struct QueuedPostSummary {
    public let id: UUID
    public let text: String
    public let priority: PostPriority
    public let queueTime: Date
    public let retryCount: Int
    public let nextRetryTime: Date?
    public let status: QueuedPostStatus
    public let metadata: PostMetadata
    
    public init(id: UUID, text: String, priority: PostPriority, queueTime: Date, retryCount: Int, nextRetryTime: Date?, status: QueuedPostStatus, metadata: PostMetadata) {
        self.id = id
        self.text = text
        self.priority = priority
        self.queueTime = queueTime
        self.retryCount = retryCount
        self.nextRetryTime = nextRetryTime
        self.status = status
        self.metadata = metadata
    }
}

/// Status of a queued post
public enum QueuedPostStatus {
    case waiting
    case scheduled
    case retrying
    case failed(String)
    
    public var description: String {
        switch self {
        case .waiting:
            return "Waiting"
        case .scheduled:
            return "Scheduled"
        case .retrying:
            return "Retrying"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}

/// Summary information about a preserved post
public struct PreservedPostSummary {
    public let id: UUID
    public let text: String
    public let preservedTime: Date
    public let originalQueueTime: Date
    public let retryCount: Int
    public let preservationReason: String
    public let metadata: PostMetadata
    
    public init(id: UUID, text: String, preservedTime: Date, originalQueueTime: Date, retryCount: Int, preservationReason: String, metadata: PostMetadata) {
        self.id = id
        self.text = text
        self.preservedTime = preservedTime
        self.originalQueueTime = originalQueueTime
        self.retryCount = retryCount
        self.preservationReason = preservationReason
        self.metadata = metadata
    }
}

/// Comprehensive status of the posting queue
public struct PostQueueStatus {
    public let queuedCount: Int
    public let preservedCount: Int
    public let processingState: PostQueueProcessingState
    public let averageProcessingTime: TimeInterval
    public let successRate: Double
    public let lastSuccessTime: Date?
    public let lastFailureTime: Date?
    public let nextScheduledProcessing: Date?
    public let isProcessingPaused: Bool
    public let capacityInfo: QueueCapacityInfo
    
    public init(queuedCount: Int, preservedCount: Int, processingState: PostQueueProcessingState, averageProcessingTime: TimeInterval, successRate: Double, lastSuccessTime: Date?, lastFailureTime: Date?, nextScheduledProcessing: Date?, isProcessingPaused: Bool, capacityInfo: QueueCapacityInfo) {
        self.queuedCount = queuedCount
        self.preservedCount = preservedCount
        self.processingState = processingState
        self.averageProcessingTime = averageProcessingTime
        self.successRate = successRate
        self.lastSuccessTime = lastSuccessTime
        self.lastFailureTime = lastFailureTime
        self.nextScheduledProcessing = nextScheduledProcessing
        self.isProcessingPaused = isProcessingPaused
        self.capacityInfo = capacityInfo
    }
}

/// Queue capacity information
public struct QueueCapacityInfo {
    public let maxQueueSize: Int
    public let currentQueueSize: Int
    public let maxPreservedSize: Int
    public let currentPreservedSize: Int
    public let availableCapacity: Int
    public let capacityWarningThreshold: Int
    public let isNearCapacity: Bool
    
    public init(maxQueueSize: Int, currentQueueSize: Int, maxPreservedSize: Int, currentPreservedSize: Int, availableCapacity: Int, capacityWarningThreshold: Int, isNearCapacity: Bool) {
        self.maxQueueSize = maxQueueSize
        self.currentQueueSize = currentQueueSize
        self.maxPreservedSize = maxPreservedSize
        self.currentPreservedSize = currentPreservedSize
        self.availableCapacity = availableCapacity
        self.capacityWarningThreshold = capacityWarningThreshold
        self.isNearCapacity = isNearCapacity
    }
}

/// Statistics about queue performance
public struct PostQueueStatistics {
    public let totalPostsProcessed: Int
    public let successfulPosts: Int
    public let failedPosts: Int
    public let averageRetryCount: Double
    public let averageProcessingTime: TimeInterval
    public let successRate: Double
    public let uptime: TimeInterval
    public let lastResetTime: Date
    
    public init(totalPostsProcessed: Int, successfulPosts: Int, failedPosts: Int, averageRetryCount: Double, averageProcessingTime: TimeInterval, successRate: Double, uptime: TimeInterval, lastResetTime: Date) {
        self.totalPostsProcessed = totalPostsProcessed
        self.successfulPosts = successfulPosts
        self.failedPosts = failedPosts
        self.averageRetryCount = averageRetryCount
        self.averageProcessingTime = averageProcessingTime
        self.successRate = successRate
        self.uptime = uptime
        self.lastResetTime = lastResetTime
    }
}

/// Queue notification for status updates
public struct PostQueueNotification {
    public let id: UUID
    public let type: NotificationType
    public let title: String
    public let message: String
    public let timestamp: Date
    public let priority: NotificationPriority
    public let isRead: Bool
    public let relatedPostId: UUID?
    public let actionRequired: Bool
    
    public init(id: UUID = UUID(), type: NotificationType, title: String, message: String, timestamp: Date = Date(), priority: NotificationPriority = .normal, isRead: Bool = false, relatedPostId: UUID? = nil, actionRequired: Bool = false) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.timestamp = timestamp
        self.priority = priority
        self.isRead = isRead
        self.relatedPostId = relatedPostId
        self.actionRequired = actionRequired
    }
    
    public enum NotificationType {
        case success
        case failure
        case warning
        case info
        case queueFull
        case processingPaused
        case networkIssue
        case authenticationRequired
    }
    
    public enum NotificationPriority {
        case low
        case normal
        case high
        case critical
    }
}

/// Statistics about queue notifications
public struct QueueNotificationStatistics {
    public let totalNotifications: Int
    public let unreadNotifications: Int
    public let notificationsByType: [PostQueueNotification.NotificationType: Int]
    public let lastNotificationTime: Date?
    public let averageNotificationsPerDay: Double
    
    public init(totalNotifications: Int, unreadNotifications: Int, notificationsByType: [PostQueueNotification.NotificationType: Int], lastNotificationTime: Date?, averageNotificationsPerDay: Double) {
        self.totalNotifications = totalNotifications
        self.unreadNotifications = unreadNotifications
        self.notificationsByType = notificationsByType
        self.lastNotificationTime = lastNotificationTime
        self.averageNotificationsPerDay = averageNotificationsPerDay
    }
}

/// Post content validation result
public struct PostValidationResult {
    public let isValid: Bool
    public let errors: [ValidationError]
    public let warnings: [ValidationWarning]
    public let characterCount: Int
    public let estimatedPostTime: TimeInterval
    
    public init(isValid: Bool, errors: [ValidationError], warnings: [ValidationWarning], characterCount: Int, estimatedPostTime: TimeInterval) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
        self.characterCount = characterCount
        self.estimatedPostTime = estimatedPostTime
    }
    
    public struct ValidationError {
        public let code: String
        public let message: String
        public let severity: Severity
        
        public init(code: String, message: String, severity: Severity) {
            self.code = code
            self.message = message
            self.severity = severity
        }
        
        public enum Severity {
            case error
            case critical
        }
    }
    
    public struct ValidationWarning {
        public let code: String
        public let message: String
        public let suggestion: String?
        
        public init(code: String, message: String, suggestion: String? = nil) {
            self.code = code
            self.message = message
            self.suggestion = suggestion
        }
    }
}

/// Queue behavior for different network conditions
public struct QueueNetworkBehavior {
    public let willProcessOnline: Bool
    public let willQueueOffline: Bool
    public let retryStrategy: NetworkRetryStrategy
    public let estimatedWaitTime: TimeInterval?
    public let recommendedAction: String
    
    public init(willProcessOnline: Bool, willQueueOffline: Bool, retryStrategy: NetworkRetryStrategy, estimatedWaitTime: TimeInterval?, recommendedAction: String) {
        self.willProcessOnline = willProcessOnline
        self.willQueueOffline = willQueueOffline
        self.retryStrategy = retryStrategy
        self.estimatedWaitTime = estimatedWaitTime
        self.recommendedAction = recommendedAction
    }
    
    public enum NetworkRetryStrategy {
        case immediate
        case exponentialBackoff
        case fixedInterval(TimeInterval)
        case waitForConnection
        case manual
    }
}

/// Archived post summary for review
public struct ArchivedPostSummary {
    public let id: UUID
    public let text: String
    public let archivedTime: Date
    public let originalQueueTime: Date
    public let finalRetryCount: Int
    public let archiveReason: String
    public let canRestore: Bool
    public let metadata: PostMetadata
    
    public init(id: UUID, text: String, archivedTime: Date, originalQueueTime: Date, finalRetryCount: Int, archiveReason: String, canRestore: Bool, metadata: PostMetadata) {
        self.id = id
        self.text = text
        self.archivedTime = archivedTime
        self.originalQueueTime = originalQueueTime
        self.finalRetryCount = finalRetryCount
        self.archiveReason = archiveReason
        self.canRestore = canRestore
        self.metadata = metadata
    }
}

/// Analytics data for queue performance monitoring
public struct PostQueueAnalytics {
    public let performanceMetrics: PerformanceMetrics
    public let usagePatterns: UsagePatterns
    public let errorAnalysis: ErrorAnalysis
    public let recommendations: [String]
    public let reportGeneratedTime: Date
    
    public init(performanceMetrics: PerformanceMetrics, usagePatterns: UsagePatterns, errorAnalysis: ErrorAnalysis, recommendations: [String], reportGeneratedTime: Date = Date()) {
        self.performanceMetrics = performanceMetrics
        self.usagePatterns = usagePatterns
        self.errorAnalysis = errorAnalysis
        self.recommendations = recommendations
        self.reportGeneratedTime = reportGeneratedTime
    }
    
    public struct PerformanceMetrics {
        public let averageProcessingTime: TimeInterval
        public let successRate: Double
        public let throughputPerHour: Double
        public let peakQueueSize: Int
        public let averageQueueSize: Double
        
        public init(averageProcessingTime: TimeInterval, successRate: Double, throughputPerHour: Double, peakQueueSize: Int, averageQueueSize: Double) {
            self.averageProcessingTime = averageProcessingTime
            self.successRate = successRate
            self.throughputPerHour = throughputPerHour
            self.peakQueueSize = peakQueueSize
            self.averageQueueSize = averageQueueSize
        }
    }
    
    public struct UsagePatterns {
        public let busyHours: [Int]
        public let averagePostsPerDay: Double
        public let peakUsageDays: [String]
        public let commonFailureReasons: [String: Int]
        
        public init(busyHours: [Int], averagePostsPerDay: Double, peakUsageDays: [String], commonFailureReasons: [String: Int]) {
            self.busyHours = busyHours
            self.averagePostsPerDay = averagePostsPerDay
            self.peakUsageDays = peakUsageDays
            self.commonFailureReasons = commonFailureReasons
        }
    }
    
    public struct ErrorAnalysis {
        public let commonErrors: [String: Int]
        public let errorTrends: [String: Double]
        public let recoveryRate: Double
        public let criticalErrors: [String]
        
        public init(commonErrors: [String: Int], errorTrends: [String: Double], recoveryRate: Double, criticalErrors: [String]) {
            self.commonErrors = commonErrors
            self.errorTrends = errorTrends
            self.recoveryRate = recoveryRate
            self.criticalErrors = criticalErrors
        }
    }
}

/// Export format for queue data
public enum QueueDataExportFormat {
    case json
    case csv
    case xml
    case plist
    
    public var fileExtension: String {
        switch self {
        case .json:
            return "json"
        case .csv:
            return "csv"
        case .xml:
            return "xml"
        case .plist:
            return "plist"
        }
    }
    
    public var mimeType: String {
        switch self {
        case .json:
            return "application/json"
        case .csv:
            return "text/csv"
        case .xml:
            return "application/xml"
        case .plist:
            return "application/x-plist"
        }
    }
}

/// Health status of the queue system
public struct QueueHealthStatus {
    public let overallHealth: HealthLevel
    public let issues: [HealthIssue]
    public let recommendations: [String]
    public let lastHealthCheck: Date
    public let nextRecommendedCheck: Date
    
    public init(overallHealth: HealthLevel, issues: [HealthIssue], recommendations: [String], lastHealthCheck: Date = Date(), nextRecommendedCheck: Date) {
        self.overallHealth = overallHealth
        self.issues = issues
        self.recommendations = recommendations
        self.lastHealthCheck = lastHealthCheck
        self.nextRecommendedCheck = nextRecommendedCheck
    }
    
    public enum HealthLevel {
        case excellent
        case good
        case fair
        case poor
        case critical
        
        public var description: String {
            switch self {
            case .excellent:
                return "Excellent"
            case .good:
                return "Good"
            case .fair:
                return "Fair"
            case .poor:
                return "Poor"
            case .critical:
                return "Critical"
            }
        }
        
        public var color: String {
            switch self {
            case .excellent:
                return "green"
            case .good:
                return "lightgreen"
            case .fair:
                return "yellow"
            case .poor:
                return "orange"
            case .critical:
                return "red"
            }
        }
    }
    
    public struct HealthIssue {
        public let severity: Severity
        public let category: Category
        public let description: String
        public let impact: String
        public let recommendedAction: String
        
        public init(severity: Severity, category: Category, description: String, impact: String, recommendedAction: String) {
            self.severity = severity
            self.category = category
            self.description = description
            self.impact = impact
            self.recommendedAction = recommendedAction
        }
        
        public enum Severity {
            case low
            case medium
            case high
            case critical
        }
        
        public enum Category {
            case performance
            case capacity
            case reliability
            case security
            case configuration
        }
    }
}

/// Diagnostics result for queue integrity
public struct QueueDiagnosticsResult {
    public let overallStatus: DiagnosticStatus
    public let checks: [DiagnosticCheck]
    public let summary: String
    public let runTime: Date
    public let duration: TimeInterval
    
    public init(overallStatus: DiagnosticStatus, checks: [DiagnosticCheck], summary: String, runTime: Date = Date(), duration: TimeInterval) {
        self.overallStatus = overallStatus
        self.checks = checks
        self.summary = summary
        self.runTime = runTime
        self.duration = duration
    }
    
    public enum DiagnosticStatus {
        case passed
        case passedWithWarnings
        case failed
        case criticalFailure
        
        public var description: String {
            switch self {
            case .passed:
                return "All checks passed"
            case .passedWithWarnings:
                return "Passed with warnings"
            case .failed:
                return "Some checks failed"
            case .criticalFailure:
                return "Critical failures detected"
            }
        }
    }
    
    public struct DiagnosticCheck {
        public let name: String
        public let status: CheckStatus
        public let description: String
        public let details: String?
        public let recommendation: String?
        
        public init(name: String, status: CheckStatus, description: String, details: String? = nil, recommendation: String? = nil) {
            self.name = name
            self.status = status
            self.description = description
            self.details = details
            self.recommendation = recommendation
        }
        
        public enum CheckStatus {
            case passed
            case warning
            case failed
            case critical
        }
    }
}

// MARK: - Protocol Extension with Default Implementations

/// Extension providing default implementations for optional protocol methods
public extension PostingQueueCoordinationProtocol {
    
    /// Default implementation for queuing posts without explicit metadata
    func queuePost(_ text: String) async -> Bool {
        return await queuePost(text, metadata: nil)
    }
    
    /// Default implementation for queuing posts with normal priority
    func queuePostWithPriority(_ text: String, priority: PostPriority) async -> Bool {
        return await queuePostWithPriority(text, priority: priority, metadata: nil)
    }
    
    /// Default implementation for clearing with safety check
    func clearQueuedPosts() async {
        await clearQueuedPosts(confirm: false)
    }
    
    /// Default implementation for clearing preserved posts with safety check
    func clearPreservedPosts() async {
        await clearPreservedPosts(confirm: false)
    }
    
    /// Default implementation for clearing all posts with safety check
    func clearAllPosts() async {
        await clearAllPosts(confirm: false)
    }
    
    /// Default implementation for converting all preserved posts
    func convertPreservedToQueued() async -> Int {
        return await convertPreservedToQueued(nil)
    }
    
    /// Default implementation for deleting all preserved posts
    func deletePreservedPosts(confirm: Bool) async {
        await deletePreservedPosts(nil, confirm: confirm)
    }
    
    /// Default implementation for export format
    func exportQueueData() async -> Data? {
        return await exportQueueData(format: .json)
    }
}

// MARK: - Convenience Extensions

/// Extension providing convenience methods for common queue operations
public extension PostingQueueCoordinationProtocol {
    
    /// Convenience method to check if there are any posts waiting
    /// - Returns: True if there are queued or preserved posts
    func hasPendingPosts() -> Bool {
        return queuedPostsCount > 0 || preservedPostsCount > 0
    }
    
    /// Convenience method to get total pending posts
    /// - Returns: Sum of queued and preserved posts
    func getTotalPendingPosts() -> Int {
        return queuedPostsCount + preservedPostsCount
    }
    
    /// Convenience method to check if queue is actively processing
    /// - Returns: True if queue is currently processing posts
    func isProcessing() -> Bool {
        // This would need to be implemented by conforming types
        // Default implementation assumes not processing
        return false
    }
    
    /// Convenience method to check if manual intervention is needed
    /// - Returns: True if user action is required
    func requiresManualIntervention() -> Bool {
        // This would be implemented by conforming types based on current state
        // Default implementation assumes no intervention needed
        return false
    }
}
import Foundation
import Combine

/// Protocol defining the rate limit status coordination interface for core app usage tracking
/// This protocol abstracts rate limit monitoring and provides a clean interface
/// for the core Mercury app to track and coordinate X API rate limit usage
@MainActor
public protocol RateLimitStatusCoordinationProtocol: ObservableObject {
    
    // MARK: - Rate Limit Status Properties
    
    /// Current rate limit information
    var currentRateLimitInfo: RateLimitInfo { get }
    
    /// Current monthly post usage
    var currentMonthlyUsage: MonthlyUsageInfo { get }
    
    /// Current daily post usage
    var currentDailyUsage: DailyUsageInfo { get }
    
    /// Current hourly post usage
    var currentHourlyUsage: HourlyUsageInfo { get }
    
    /// Whether currently rate limited
    var isCurrentlyRateLimited: Bool { get }
    
    /// Whether approaching rate limit (warning threshold)
    var isApproachingRateLimit: Bool { get }
    
    /// Estimated time until rate limit reset
    var timeUntilRateLimitReset: TimeInterval? { get }
    
    /// Current rate limit utilization percentage (0.0 to 1.0)
    var rateLimitUtilization: Double { get }
    
    /// Remaining requests in current window
    var remainingRequests: Int { get }
    
    /// Maximum requests in current window
    var maxRequests: Int { get }
    
    /// Current rate limit window type
    var currentWindowType: RateLimitWindowType { get }
    
    /// Rate limit compliance status
    var complianceStatus: RateLimitComplianceStatus { get }
    
    // MARK: - Rate Limit Status Publishers
    
    /// Publisher for rate limit information changes
    var rateLimitInfoPublisher: AnyPublisher<RateLimitInfo, Never> { get }
    
    /// Publisher for monthly usage changes
    var monthlyUsagePublisher: AnyPublisher<MonthlyUsageInfo, Never> { get }
    
    /// Publisher for daily usage changes
    var dailyUsagePublisher: AnyPublisher<DailyUsageInfo, Never> { get }
    
    /// Publisher for hourly usage changes
    var hourlyUsagePublisher: AnyPublisher<HourlyUsageInfo, Never> { get }
    
    /// Publisher for rate limit status changes (limited/not limited)
    var rateLimitStatusPublisher: AnyPublisher<Bool, Never> { get }
    
    /// Publisher for rate limit warning threshold changes
    var rateLimitWarningPublisher: AnyPublisher<RateLimitWarning, Never> { get }
    
    /// Publisher for rate limit utilization changes
    var utilizationPublisher: AnyPublisher<Double, Never> { get }
    
    /// Publisher for remaining requests changes
    var remainingRequestsPublisher: AnyPublisher<Int, Never> { get }
    
    /// Publisher for rate limit window resets
    var windowResetPublisher: AnyPublisher<RateLimitWindowReset, Never> { get }
    
    /// Publisher for compliance status changes
    var complianceStatusPublisher: AnyPublisher<RateLimitComplianceStatus, Never> { get }
    
    /// Combined publisher for comprehensive rate limit monitoring
    var combinedRateLimitStatusPublisher: AnyPublisher<RateLimitStatusSnapshot, Never> { get }
    
    /// Publisher for rate limit events requiring attention
    var rateLimitEventPublisher: AnyPublisher<RateLimitCoordinationEvent, Never> { get }
    
    // MARK: - Rate Limit Tracking Methods
    
    /// Records a successful post for rate limit tracking
    /// - Parameters:
    ///   - postType: Type of post that was made
    ///   - timestamp: When the post was made (defaults to now)
    ///   - metadata: Additional metadata about the post
    func recordSuccessfulPost(
        postType: PostType,
        timestamp: Date,
        metadata: PostMetadata?
    ) async
    
    /// Records a failed post attempt for rate limit tracking
    /// - Parameters:
    ///   - postType: Type of post that was attempted
    ///   - failureReason: Reason the post failed
    ///   - timestamp: When the attempt was made (defaults to now)
    ///   - metadata: Additional metadata about the attempt
    func recordFailedPostAttempt(
        postType: PostType,
        failureReason: PostFailureReason,
        timestamp: Date,
        metadata: PostMetadata?
    ) async
    
    /// Records rate limit response from X API
    /// - Parameter rateLimitResponse: Rate limit information from API response headers
    func recordRateLimitResponse(_ rateLimitResponse: APIRateLimitResponse) async
    
    /// Updates usage statistics based on current data
    func updateUsageStatistics() async
    
    /// Refreshes rate limit information from X API
    /// - Returns: Updated rate limit information
    func refreshRateLimitInfo() async -> RateLimitInfo
    
    /// Gets detailed usage breakdown for a specific time period
    /// - Parameter period: Time period to analyze
    /// - Returns: Detailed usage breakdown
    func getUsageBreakdown(for period: UsageTimePeriod) async -> UsageBreakdown
    
    /// Gets usage trends and predictions
    /// - Returns: Usage trend analysis
    func getUsageTrends() async -> UsageTrendAnalysis
    
    /// Gets rate limit compliance report
    /// - Returns: Compliance report with recommendations
    func getComplianceReport() async -> RateLimitComplianceReport
    
    // MARK: - Rate Limit Prediction and Planning
    
    /// Predicts if a post can be made without hitting rate limits
    /// - Parameters:
    ///   - postType: Type of post to check
    ///   - scheduledTime: When the post is planned (defaults to now)
    /// - Returns: Whether the post can be made safely
    func canMakePost(postType: PostType, scheduledTime: Date) async -> PostViabilityResult
    
    /// Gets optimal timing for making a post to avoid rate limits
    /// - Parameter postType: Type of post to schedule
    /// - Returns: Optimal timing recommendation
    func getOptimalPostTiming(for postType: PostType) async -> PostTimingRecommendation
    
    /// Estimates when rate limit will reset for specific operation
    /// - Parameter operationType: Type of operation to check
    /// - Returns: Estimated reset time
    func estimateRateLimitReset(for operationType: RateLimitOperationType) async -> Date?
    
    /// Predicts usage for remainder of current period
    /// - Parameter period: Period to predict for
    /// - Returns: Usage prediction
    func predictUsage(for period: UsageTimePeriod) async -> UsagePrediction
    
    /// Gets recommended posting strategy based on current limits
    /// - Returns: Posting strategy recommendations
    func getRecommendedPostingStrategy() async -> PostingStrategyRecommendation
    
    /// Analyzes posting patterns and suggests optimizations
    /// - Returns: Optimization recommendations
    func analyzePostingPatterns() async -> PostingPatternAnalysis
    
    // MARK: - Rate Limit Configuration and Preferences
    
    /// Gets current rate limit monitoring preferences
    /// - Returns: Current monitoring preferences
    func getRateLimitPreferences() -> RateLimitMonitoringPreferences
    
    /// Updates rate limit monitoring preferences
    /// - Parameter preferences: New preferences to apply
    func updateRateLimitPreferences(_ preferences: RateLimitMonitoringPreferences) async
    
    /// Gets rate limit warning thresholds
    /// - Returns: Current warning thresholds
    func getWarningThresholds() -> RateLimitWarningThresholds
    
    /// Updates rate limit warning thresholds
    /// - Parameter thresholds: New thresholds to apply
    func updateWarningThresholds(_ thresholds: RateLimitWarningThresholds) async
    
    /// Gets rate limit enforcement settings
    /// - Returns: Current enforcement settings
    func getEnforcementSettings() -> RateLimitEnforcementSettings
    
    /// Updates rate limit enforcement settings
    /// - Parameter settings: New enforcement settings
    func updateEnforcementSettings(_ settings: RateLimitEnforcementSettings) async
    
    // MARK: - Rate Limit Subscription Methods
    
    /// Subscribe to rate limit status changes
    /// - Parameter handler: Handler to call when status changes
    /// - Returns: Cancellable subscription
    func observeRateLimitStatus(_ handler: @escaping (Bool) -> Void) -> AnyCancellable
    
    /// Subscribe to rate limit warnings
    /// - Parameter handler: Handler to call when warnings are triggered
    /// - Returns: Cancellable subscription
    func observeRateLimitWarnings(_ handler: @escaping (RateLimitWarning) -> Void) -> AnyCancellable
    
    /// Subscribe to usage threshold crossings
    /// - Parameters:
    ///   - thresholds: Usage thresholds to monitor
    ///   - handler: Handler to call when thresholds are crossed
    /// - Returns: Cancellable subscription
    func observeUsageThresholds(_ thresholds: [UsageThreshold], handler: @escaping (UsageThresholdEvent) -> Void) -> AnyCancellable
    
    /// Subscribe to rate limit window resets
    /// - Parameter handler: Handler to call when windows reset
    /// - Returns: Cancellable subscription
    func observeWindowResets(_ handler: @escaping (RateLimitWindowReset) -> Void) -> AnyCancellable
    
    /// Subscribe to compliance status changes
    /// - Parameter handler: Handler to call when compliance status changes
    /// - Returns: Cancellable subscription
    func observeComplianceStatus(_ handler: @escaping (RateLimitComplianceStatus) -> Void) -> AnyCancellable
    
    /// Subscribe to rate limit utilization changes above threshold
    /// - Parameters:
    ///   - threshold: Utilization threshold to monitor (0.0 to 1.0)
    ///   - handler: Handler to call when threshold is exceeded
    /// - Returns: Cancellable subscription
    func observeUtilizationThreshold(_ threshold: Double, handler: @escaping (Double) -> Void) -> AnyCancellable
    
    // MARK: - Rate Limit Reporting and Analytics
    
    /// Generates rate limit usage report for a time period
    /// - Parameter period: Time period to report on
    /// - Returns: Comprehensive usage report
    func generateUsageReport(for period: ReportingTimePeriod) async -> RateLimitUsageReport
    
    /// Exports rate limit data for external analysis
    /// - Parameter format: Export format (JSON, CSV, etc.)
    /// - Returns: Exported data
    func exportRateLimitData(format: ExportFormat) async -> RateLimitExportData
    
    /// Gets rate limit efficiency metrics
    /// - Returns: Efficiency analysis
    func getRateLimitEfficiencyMetrics() async -> RateLimitEfficiencyMetrics
    
    /// Analyzes rate limit impact on user experience
    /// - Returns: User experience impact analysis
    func analyzeUserExperienceImpact() async -> UserExperienceImpactAnalysis
    
    /// Gets historical rate limit performance
    /// - Parameter period: Period to analyze
    /// - Returns: Historical performance metrics
    func getHistoricalPerformance(for period: ReportingTimePeriod) async -> RateLimitHistoricalPerformance
    
    /// Compares current usage to historical patterns
    /// - Returns: Usage comparison analysis
    func compareToHistoricalUsage() async -> UsageComparisonAnalysis
    
    // MARK: - Rate Limit State Persistence
    
    /// Saves rate limit tracking state
    /// - Returns: Whether save was successful
    func saveRateLimitState() async -> Bool
    
    /// Restores rate limit tracking state
    /// - Returns: Whether restore was successful
    func restoreRateLimitState() async -> Bool
    
    /// Clears all rate limit tracking data
    /// - Returns: Whether clear was successful
    func clearRateLimitData() async -> Bool
    
    /// Gets size of stored rate limit data
    /// - Returns: Data size in bytes
    func getRateLimitDataSize() async -> Int64
    
    /// Validates integrity of stored rate limit data
    /// - Returns: Whether data is valid
    func validateRateLimitDataIntegrity() async -> Bool
    
    /// Performs cleanup of old rate limit data
    /// - Parameter retentionPeriod: How long to retain data
    /// - Returns: Number of records cleaned up
    func cleanupOldData(retentionPeriod: TimeInterval) async -> Int
    
    // MARK: - Rate Limit Emergency and Recovery
    
    /// Handles rate limit emergency situations
    /// - Parameter emergency: Type of emergency
    /// - Returns: Emergency response actions taken
    func handleRateLimitEmergency(_ emergency: RateLimitEmergency) async -> EmergencyResponse
    
    /// Attempts to recover from rate limit violations
    /// - Returns: Recovery actions and success status
    func attemptRateLimitRecovery() async -> RateLimitRecoveryResult
    
    /// Gets emergency contact options for rate limit issues
    /// - Returns: Available emergency options
    func getEmergencyOptions() -> [RateLimitEmergencyOption]
    
    /// Enables emergency mode with relaxed rate limiting
    /// - Parameter duration: How long to enable emergency mode
    func enableEmergencyMode(duration: TimeInterval) async
    
    /// Disables emergency mode and returns to normal rate limiting
    func disableEmergencyMode() async
    
    /// Checks if currently in emergency mode
    /// - Returns: Whether emergency mode is active
    func isInEmergencyMode() -> Bool
}

// MARK: - Supporting Types

/// Monthly usage information
public struct MonthlyUsageInfo {
    public let month: Date
    public let postsCount: Int
    public let maxPosts: Int
    public let utilizationPercentage: Double
    public let daysRemaining: Int
    public let projectedEndOfMonthUsage: Int
    public let isOverLimit: Bool
    public let lastUpdated: Date
    
    public init(
        month: Date,
        postsCount: Int,
        maxPosts: Int,
        utilizationPercentage: Double,
        daysRemaining: Int,
        projectedEndOfMonthUsage: Int,
        isOverLimit: Bool,
        lastUpdated: Date = Date()
    ) {
        self.month = month
        self.postsCount = postsCount
        self.maxPosts = maxPosts
        self.utilizationPercentage = utilizationPercentage
        self.daysRemaining = daysRemaining
        self.projectedEndOfMonthUsage = projectedEndOfMonthUsage
        self.isOverLimit = isOverLimit
        self.lastUpdated = lastUpdated
    }
    
    public var remainingPosts: Int {
        return max(0, maxPosts - postsCount)
    }
    
    public var dailyBudgetRemaining: Double {
        return daysRemaining > 0 ? Double(remainingPosts) / Double(daysRemaining) : 0.0
    }
}

/// Daily usage information
public struct DailyUsageInfo {
    public let date: Date
    public let postsCount: Int
    public let maxPostsPerDay: Int
    public let hoursRemaining: Int
    public let hourlyUsagePattern: [Int]
    public let lastUpdated: Date
    
    public init(
        date: Date,
        postsCount: Int,
        maxPostsPerDay: Int,
        hoursRemaining: Int,
        hourlyUsagePattern: [Int],
        lastUpdated: Date = Date()
    ) {
        self.date = date
        self.postsCount = postsCount
        self.maxPostsPerDay = maxPostsPerDay
        self.hoursRemaining = hoursRemaining
        self.hourlyUsagePattern = hourlyUsagePattern
        self.lastUpdated = lastUpdated
    }
    
    public var remainingPosts: Int {
        return max(0, maxPostsPerDay - postsCount)
    }
    
    public var hourlyBudgetRemaining: Double {
        return hoursRemaining > 0 ? Double(remainingPosts) / Double(hoursRemaining) : 0.0
    }
}

/// Hourly usage information
public struct HourlyUsageInfo {
    public let hour: Date
    public let postsCount: Int
    public let maxPostsPerHour: Int
    public let minutesRemaining: Int
    public let minutelyUsagePattern: [Int]
    public let lastUpdated: Date
    
    public init(
        hour: Date,
        postsCount: Int,
        maxPostsPerHour: Int,
        minutesRemaining: Int,
        minutelyUsagePattern: [Int],
        lastUpdated: Date = Date()
    ) {
        self.hour = hour
        self.postsCount = postsCount
        self.maxPostsPerHour = maxPostsPerHour
        self.minutesRemaining = minutesRemaining
        self.minutelyUsagePattern = minutelyUsagePattern
        self.lastUpdated = lastUpdated
    }
    
    public var remainingPosts: Int {
        return max(0, maxPostsPerHour - postsCount)
    }
}

/// Rate limit window types
public enum RateLimitWindowType: String, CaseIterable {
    case monthly = "monthly"
    case daily = "daily"
    case hourly = "hourly"
    case fifteenMinute = "fifteenMinute"
    case perRequest = "perRequest"
    
    public var description: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .daily:
            return "Daily"
        case .hourly:
            return "Hourly"
        case .fifteenMinute:
            return "15 Minutes"
        case .perRequest:
            return "Per Request"
        }
    }
    
    public var duration: TimeInterval {
        switch self {
        case .monthly:
            return 30 * 24 * 60 * 60 // 30 days
        case .daily:
            return 24 * 60 * 60     // 24 hours
        case .hourly:
            return 60 * 60          // 1 hour
        case .fifteenMinute:
            return 15 * 60          // 15 minutes
        case .perRequest:
            return 0                // Immediate
        }
    }
}

/// Rate limit compliance status
public enum RateLimitComplianceStatus: String, CaseIterable {
    case compliant = "compliant"
    case warning = "warning"
    case approaching = "approaching"
    case exceeded = "exceeded"
    case violation = "violation"
    
    public var description: String {
        switch self {
        case .compliant:
            return "Compliant"
        case .warning:
            return "Warning"
        case .approaching:
            return "Approaching Limit"
        case .exceeded:
            return "Limit Exceeded"
        case .violation:
            return "Violation"
        }
    }
    
    public var severity: ComplianceSeverity {
        switch self {
        case .compliant:
            return .none
        case .warning:
            return .low
        case .approaching:
            return .medium
        case .exceeded:
            return .high
        case .violation:
            return .critical
        }
    }
}

/// Compliance severity levels
public enum ComplianceSeverity: String, CaseIterable {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

/// Rate limit warning information
public struct RateLimitWarning {
    public let warningType: RateLimitWarningType
    public let currentUsage: Int
    public let threshold: Int
    public let windowType: RateLimitWindowType
    public let timeUntilReset: TimeInterval?
    public let recommendedAction: String
    public let triggeredAt: Date
    
    public init(
        warningType: RateLimitWarningType,
        currentUsage: Int,
        threshold: Int,
        windowType: RateLimitWindowType,
        timeUntilReset: TimeInterval?,
        recommendedAction: String,
        triggeredAt: Date = Date()
    ) {
        self.warningType = warningType
        self.currentUsage = currentUsage
        self.threshold = threshold
        self.windowType = windowType
        self.timeUntilReset = timeUntilReset
        self.recommendedAction = recommendedAction
        self.triggeredAt = triggeredAt
    }
}

/// Types of rate limit warnings
public enum RateLimitWarningType: String, CaseIterable {
    case approachingLimit = "approachingLimit"
    case exceeded = "exceeded"
    case projectedOverage = "projectedOverage"
    case unusualUsage = "unusualUsage"
    case emergencyThreshold = "emergencyThreshold"
    
    public var description: String {
        switch self {
        case .approachingLimit:
            return "Approaching Rate Limit"
        case .exceeded:
            return "Rate Limit Exceeded"
        case .projectedOverage:
            return "Projected Overage"
        case .unusualUsage:
            return "Unusual Usage Pattern"
        case .emergencyThreshold:
            return "Emergency Threshold"
        }
    }
}

/// Rate limit window reset information
public struct RateLimitWindowReset {
    public let windowType: RateLimitWindowType
    public let resetTime: Date
    public let newLimit: Int
    public let previousUsage: Int
    public let resetReason: WindowResetReason
    
    public init(
        windowType: RateLimitWindowType,
        resetTime: Date,
        newLimit: Int,
        previousUsage: Int,
        resetReason: WindowResetReason
    ) {
        self.windowType = windowType
        self.resetTime = resetTime
        self.newLimit = newLimit
        self.previousUsage = previousUsage
        self.resetReason = resetReason
    }
}

/// Reasons for window resets
public enum WindowResetReason: String, CaseIterable {
    case scheduled = "scheduled"
    case manual = "manual"
    case emergency = "emergency"
    case apiChange = "apiChange"
    case recovery = "recovery"
}

/// Comprehensive rate limit status snapshot
public struct RateLimitStatusSnapshot {
    public let rateLimitInfo: RateLimitInfo
    public let monthlyUsage: MonthlyUsageInfo
    public let dailyUsage: DailyUsageInfo
    public let hourlyUsage: HourlyUsageInfo
    public let complianceStatus: RateLimitComplianceStatus
    public let utilization: Double
    public let isRateLimited: Bool
    public let timeUntilReset: TimeInterval?
    public let timestamp: Date
    
    public init(
        rateLimitInfo: RateLimitInfo,
        monthlyUsage: MonthlyUsageInfo,
        dailyUsage: DailyUsageInfo,
        hourlyUsage: HourlyUsageInfo,
        complianceStatus: RateLimitComplianceStatus,
        utilization: Double,
        isRateLimited: Bool,
        timeUntilReset: TimeInterval?,
        timestamp: Date = Date()
    ) {
        self.rateLimitInfo = rateLimitInfo
        self.monthlyUsage = monthlyUsage
        self.dailyUsage = dailyUsage
        self.hourlyUsage = hourlyUsage
        self.complianceStatus = complianceStatus
        self.utilization = utilization
        self.isRateLimited = isRateLimited
        self.timeUntilReset = timeUntilReset
        self.timestamp = timestamp
    }
}

/// Rate limit coordination events
public struct RateLimitCoordinationEvent {
    public let eventType: RateLimitEventType
    public let affectedLimits: [RateLimitWindowType]
    public let currentStatus: RateLimitComplianceStatus
    public let recommendations: [String]
    public let urgency: EventUrgency
    public let timestamp: Date
    
    public init(
        eventType: RateLimitEventType,
        affectedLimits: [RateLimitWindowType],
        currentStatus: RateLimitComplianceStatus,
        recommendations: [String],
        urgency: EventUrgency,
        timestamp: Date = Date()
    ) {
        self.eventType = eventType
        self.affectedLimits = affectedLimits
        self.currentStatus = currentStatus
        self.recommendations = recommendations
        self.urgency = urgency
        self.timestamp = timestamp
    }
}

/// Types of rate limit events
public enum RateLimitEventType: String, CaseIterable {
    case thresholdCrossed = "thresholdCrossed"
    case limitExceeded = "limitExceeded"
    case windowReset = "windowReset"
    case usageSpike = "usageSpike"
    case complianceViolation = "complianceViolation"
    case emergencyActivated = "emergencyActivated"
    case recoveryCompleted = "recoveryCompleted"
    
    public var description: String {
        switch self {
        case .thresholdCrossed:
            return "Threshold Crossed"
        case .limitExceeded:
            return "Limit Exceeded"
        case .windowReset:
            return "Window Reset"
        case .usageSpike:
            return "Usage Spike"
        case .complianceViolation:
            return "Compliance Violation"
        case .emergencyActivated:
            return "Emergency Activated"
        case .recoveryCompleted:
            return "Recovery Completed"
        }
    }
}

/// Event urgency levels
public enum EventUrgency: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
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
}

/// Post types for rate limit tracking
public enum PostType: String, CaseIterable {
    case regularTweet = "regularTweet"
    case replyTweet = "replyTweet"
    case quoteTweet = "quoteTweet"
    case threadTweet = "threadTweet"
    case scheduledTweet = "scheduledTweet"
    case retryTweet = "retryTweet"
    
    public var description: String {
        switch self {
        case .regularTweet:
            return "Regular Tweet"
        case .replyTweet:
            return "Reply Tweet"
        case .quoteTweet:
            return "Quote Tweet"
        case .threadTweet:
            return "Thread Tweet"
        case .scheduledTweet:
            return "Scheduled Tweet"
        case .retryTweet:
            return "Retry Tweet"
        }
    }
    
    public var rateLimitWeight: Double {
        switch self {
        case .regularTweet, .replyTweet, .quoteTweet:
            return 1.0
        case .threadTweet:
            return 1.2  // Slightly higher weight for threads
        case .scheduledTweet:
            return 1.0
        case .retryTweet:
            return 0.5  // Lower weight for retries
        }
    }
}

/// Post failure reasons
public enum PostFailureReason: String, CaseIterable {
    case rateLimited = "rateLimited"
    case networkError = "networkError"
    case authenticationError = "authenticationError"
    case invalidContent = "invalidContent"
    case serverError = "serverError"
    case unknown = "unknown"
    
    public var description: String {
        switch self {
        case .rateLimited:
            return "Rate Limited"
        case .networkError:
            return "Network Error"
        case .authenticationError:
            return "Authentication Error"
        case .invalidContent:
            return "Invalid Content"
        case .serverError:
            return "Server Error"
        case .unknown:
            return "Unknown Error"
        }
    }
    
    public var affectsRateLimit: Bool {
        switch self {
        case .rateLimited:
            return true
        case .networkError, .authenticationError, .serverError:
            return false
        case .invalidContent:
            return true  // Invalid content still counts against rate limit
        case .unknown:
            return false // Don't count unknown errors to be safe
        }
    }
}

/// API rate limit response information
public struct APIRateLimitResponse {
    public let requestsRemaining: Int
    public let requestsLimit: Int
    public let resetTime: Date
    public let windowType: RateLimitWindowType
    public let endpoint: String
    public let receivedAt: Date
    
    public init(
        requestsRemaining: Int,
        requestsLimit: Int,
        resetTime: Date,
        windowType: RateLimitWindowType,
        endpoint: String,
        receivedAt: Date = Date()
    ) {
        self.requestsRemaining = requestsRemaining
        self.requestsLimit = requestsLimit
        self.resetTime = resetTime
        self.windowType = windowType
        self.endpoint = endpoint
        self.receivedAt = receivedAt
    }
    
    public var utilization: Double {
        let used = requestsLimit - requestsRemaining
        return requestsLimit > 0 ? Double(used) / Double(requestsLimit) : 0.0
    }
}

/// Usage time periods for analysis
public enum UsageTimePeriod: String, CaseIterable {
    case currentHour = "currentHour"
    case currentDay = "currentDay"
    case currentWeek = "currentWeek"
    case currentMonth = "currentMonth"
    case last24Hours = "last24Hours"
    case last7Days = "last7Days"
    case last30Days = "last30Days"
    
    public var description: String {
        switch self {
        case .currentHour:
            return "Current Hour"
        case .currentDay:
            return "Current Day"
        case .currentWeek:
            return "Current Week"
        case .currentMonth:
            return "Current Month"
        case .last24Hours:
            return "Last 24 Hours"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        }
    }
}

/// Detailed usage breakdown
public struct UsageBreakdown {
    public let period: UsageTimePeriod
    public let totalPosts: Int
    public let postsByType: [PostType: Int]
    public let postsByHour: [Int: Int]
    public let averagePostsPerDay: Double
    public let peakUsageHour: Int
    public let lowUsageHours: [Int]
    public let trendsAnalysis: String
    public let generatedAt: Date
    
    public init(
        period: UsageTimePeriod,
        totalPosts: Int,
        postsByType: [PostType: Int],
        postsByHour: [Int: Int],
        averagePostsPerDay: Double,
        peakUsageHour: Int,
        lowUsageHours: [Int],
        trendsAnalysis: String,
        generatedAt: Date = Date()
    ) {
        self.period = period
        self.totalPosts = totalPosts
        self.postsByType = postsByType
        self.postsByHour = postsByHour
        self.averagePostsPerDay = averagePostsPerDay
        self.peakUsageHour = peakUsageHour
        self.lowUsageHours = lowUsageHours
        self.trendsAnalysis = trendsAnalysis
        self.generatedAt = generatedAt
    }
}

/// Usage trend analysis
public struct UsageTrendAnalysis {
    public let overallTrend: UsageTrend
    public let dailyTrends: [Date: UsageTrend]
    public let hourlyPatterns: [Int: Double]
    public let seasonalPatterns: [String: Double]
    public let projectedUsage: UsagePrediction
    public let anomalies: [UsageAnomaly]
    public let recommendations: [String]
    public let analysisDate: Date
    
    public init(
        overallTrend: UsageTrend,
        dailyTrends: [Date: UsageTrend],
        hourlyPatterns: [Int: Double],
        seasonalPatterns: [String: Double],
        projectedUsage: UsagePrediction,
        anomalies: [UsageAnomaly],
        recommendations: [String],
        analysisDate: Date = Date()
    ) {
        self.overallTrend = overallTrend
        self.dailyTrends = dailyTrends
        self.hourlyPatterns = hourlyPatterns
        self.seasonalPatterns = seasonalPatterns
        self.projectedUsage = projectedUsage
        self.anomalies = anomalies
        self.recommendations = recommendations
        self.analysisDate = analysisDate
    }
}

/// Usage trends
public enum UsageTrend: String, CaseIterable {
    case increasing = "increasing"
    case decreasing = "decreasing"
    case stable = "stable"
    case volatile = "volatile"
    case seasonal = "seasonal"
    
    public var description: String {
        switch self {
        case .increasing:
            return "Increasing"
        case .decreasing:
            return "Decreasing"
        case .stable:
            return "Stable"
        case .volatile:
            return "Volatile"
        case .seasonal:
            return "Seasonal"
        }
    }
}

/// Usage anomalies
public struct UsageAnomaly {
    public let type: AnomalyType
    public let detectedAt: Date
    public let severity: AnomalySeverity
    public let description: String
    public let expectedValue: Double
    public let actualValue: Double
    public let deviation: Double
    
    public init(
        type: AnomalyType,
        detectedAt: Date,
        severity: AnomalySeverity,
        description: String,
        expectedValue: Double,
        actualValue: Double,
        deviation: Double
    ) {
        self.type = type
        self.detectedAt = detectedAt
        self.severity = severity
        self.description = description
        self.expectedValue = expectedValue
        self.actualValue = actualValue
        self.deviation = deviation
    }
}

/// Types of usage anomalies
public enum AnomalyType: String, CaseIterable {
    case unusualSpike = "unusualSpike"
    case unexpectedDrop = "unexpectedDrop"
    case patternChange = "patternChange"
    case outlierHour = "outlierHour"
    case inconsistentTrend = "inconsistentTrend"
}

/// Anomaly severity levels
public enum AnomalySeverity: String, CaseIterable {
    case minor = "minor"
    case moderate = "moderate"
    case significant = "significant"
    case critical = "critical"
}

// MARK: - Additional Supporting Types (continued in next part due to length)

/// Post viability result
public struct PostViabilityResult {
    public let canPost: Bool
    public let reason: String
    public let alternativeTimings: [Date]
    public let estimatedWaitTime: TimeInterval?
    public let riskLevel: PostRiskLevel
    public let recommendations: [String]
    public let checkedAt: Date
    
    public init(
        canPost: Bool,
        reason: String,
        alternativeTimings: [Date] = [],
        estimatedWaitTime: TimeInterval? = nil,
        riskLevel: PostRiskLevel,
        recommendations: [String] = [],
        checkedAt: Date = Date()
    ) {
        self.canPost = canPost
        self.reason = reason
        self.alternativeTimings = alternativeTimings
        self.estimatedWaitTime = estimatedWaitTime
        self.riskLevel = riskLevel
        self.recommendations = recommendations
        self.checkedAt = checkedAt
    }
}

/// Post risk levels
public enum PostRiskLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
    public var description: String {
        switch self {
        case .low:
            return "Low Risk"
        case .medium:
            return "Medium Risk"
        case .high:
            return "High Risk"
        case .critical:
            return "Critical Risk"
        }
    }
}

/// Post timing recommendation
public struct PostTimingRecommendation {
    public let optimalTime: Date
    public let alternativeTimes: [Date]
    public let reasoning: String
    public let confidenceLevel: Double
    public let estimatedSuccessRate: Double
    public let riskAssessment: PostRiskLevel
    public let generatedAt: Date
    
    public init(
        optimalTime: Date,
        alternativeTimes: [Date],
        reasoning: String,
        confidenceLevel: Double,
        estimatedSuccessRate: Double,
        riskAssessment: PostRiskLevel,
        generatedAt: Date = Date()
    ) {
        self.optimalTime = optimalTime
        self.alternativeTimes = alternativeTimes
        self.reasoning = reasoning
        self.confidenceLevel = confidenceLevel
        self.estimatedSuccessRate = estimatedSuccessRate
        self.riskAssessment = riskAssessment
        self.generatedAt = generatedAt
    }
}

/// Rate limit operation types
public enum RateLimitOperationType: String, CaseIterable {
    case posting = "posting"
    case reading = "reading"
    case searching = "searching"
    case userInfo = "userInfo"
    case authentication = "authentication"
    
    public var description: String {
        switch self {
        case .posting:
            return "Posting"
        case .reading:
            return "Reading"
        case .searching:
            return "Searching"
        case .userInfo:
            return "User Info"
        case .authentication:
            return "Authentication"
        }
    }
}

/// Usage prediction
public struct UsagePrediction {
    public let predictedUsage: Int
    public let confidenceInterval: ClosedRange<Int>
    public let predictionAccuracy: Double
    public let factorsConsidered: [String]
    public let predictionMethod: PredictionMethod
    public let generatedAt: Date
    public let validUntil: Date
    
    public init(
        predictedUsage: Int,
        confidenceInterval: ClosedRange<Int>,
        predictionAccuracy: Double,
        factorsConsidered: [String],
        predictionMethod: PredictionMethod,
        generatedAt: Date = Date(),
        validUntil: Date
    ) {
        self.predictedUsage = predictedUsage
        self.confidenceInterval = confidenceInterval
        self.predictionAccuracy = predictionAccuracy
        self.factorsConsidered = factorsConsidered
        self.predictionMethod = predictionMethod
        self.generatedAt = generatedAt
        self.validUntil = validUntil
    }
}

/// Prediction methods
public enum PredictionMethod: String, CaseIterable {
    case linearRegression = "linearRegression"
    case movingAverage = "movingAverage"
    case seasonalDecomposition = "seasonalDecomposition"
    case machinelearning = "machineLearning"
    case hybrid = "hybrid"
}

/// Posting strategy recommendation
public struct PostingStrategyRecommendation {
    public let strategy: PostingStrategy
    public let optimalTimes: [Date]
    public let frequencyRecommendation: PostingFrequency
    public let contentTypeGuidance: [PostType: String]
    public let riskMitigation: [String]
    public let expectedOutcomes: [String]
    public let generatedAt: Date
    
    public init(
        strategy: PostingStrategy,
        optimalTimes: [Date],
        frequencyRecommendation: PostingFrequency,
        contentTypeGuidance: [PostType: String],
        riskMitigation: [String],
        expectedOutcomes: [String],
        generatedAt: Date = Date()
    ) {
        self.strategy = strategy
        self.optimalTimes = optimalTimes
        self.frequencyRecommendation = frequencyRecommendation
        self.contentTypeGuidance = contentTypeGuidance
        self.riskMitigation = riskMitigation
        self.expectedOutcomes = expectedOutcomes
        self.generatedAt = generatedAt
    }
}

/// Posting strategies
public enum PostingStrategy: String, CaseIterable {
    case conservative = "conservative"
    case balanced = "balanced"
    case aggressive = "aggressive"
    case bursty = "bursty"
    case scheduled = "scheduled"
    
    public var description: String {
        switch self {
        case .conservative:
            return "Conservative"
        case .balanced:
            return "Balanced"
        case .aggressive:
            return "Aggressive"
        case .bursty:
            return "Bursty"
        case .scheduled:
            return "Scheduled"
        }
    }
}

/// Posting frequency recommendations
public struct PostingFrequency {
    public let postsPerHour: Double
    public let postsPerDay: Int
    public let postsPerWeek: Int
    public let burstAllowance: Int
    public let cooldownPeriod: TimeInterval
    public let adaptiveAdjustment: Bool
    
    public init(
        postsPerHour: Double,
        postsPerDay: Int,
        postsPerWeek: Int,
        burstAllowance: Int,
        cooldownPeriod: TimeInterval,
        adaptiveAdjustment: Bool
    ) {
        self.postsPerHour = postsPerHour
        self.postsPerDay = postsPerDay
        self.postsPerWeek = postsPerWeek
        self.burstAllowance = burstAllowance
        self.cooldownPeriod = cooldownPeriod
        self.adaptiveAdjustment = adaptiveAdjustment
    }
}

/// Rate limit monitoring preferences
public struct RateLimitMonitoringPreferences {
    public let trackingEnabled: Bool
    public let warningsEnabled: Bool
    public let automaticThrottling: Bool
    public let aggressiveTracking: Bool
    public let predictiveAnalysis: Bool
    public let historicalRetention: TimeInterval
    public let updateFrequency: TimeInterval
    
    public init(
        trackingEnabled: Bool = true,
        warningsEnabled: Bool = true,
        automaticThrottling: Bool = false,
        aggressiveTracking: Bool = false,
        predictiveAnalysis: Bool = true,
        historicalRetention: TimeInterval = 30 * 24 * 60 * 60, // 30 days
        updateFrequency: TimeInterval = 60 // 1 minute
    ) {
        self.trackingEnabled = trackingEnabled
        self.warningsEnabled = warningsEnabled
        self.automaticThrottling = automaticThrottling
        self.aggressiveTracking = aggressiveTracking
        self.predictiveAnalysis = predictiveAnalysis
        self.historicalRetention = historicalRetention
        self.updateFrequency = updateFrequency
    }
    
    public static let `default` = RateLimitMonitoringPreferences()
}

// MARK: - Protocol Extension for Default Implementations

/// Extension providing default implementations for optional protocol methods
public extension RateLimitStatusCoordinationProtocol {
    
    /// Default implementation for recording successful posts
    func recordSuccessfulPost(
        postType: PostType,
        timestamp: Date = Date(),
        metadata: PostMetadata? = nil
    ) async {
        await recordSuccessfulPost(postType: postType, timestamp: timestamp, metadata: metadata)
    }
    
    /// Default implementation for recording failed post attempts
    func recordFailedPostAttempt(
        postType: PostType,
        failureReason: PostFailureReason,
        timestamp: Date = Date(),
        metadata: PostMetadata? = nil
    ) async {
        await recordFailedPostAttempt(postType: postType, failureReason: failureReason, timestamp: timestamp, metadata: metadata)
    }
    
    /// Default implementation for post viability check
    func canMakePost(postType: PostType, scheduledTime: Date = Date()) async -> PostViabilityResult {
        return await canMakePost(postType: postType, scheduledTime: scheduledTime)
    }
    
    /// Default implementation for rate limit state saving
    func saveRateLimitState() async -> Bool {
        return true
    }
    
    /// Default implementation for rate limit state restoration
    func restoreRateLimitState() async -> Bool {
        return true
    }
    
    /// Default implementation for emergency mode check
    func isInEmergencyMode() -> Bool {
        return false
    }
}
import Foundation
import Combine
import Network

/// Protocol defining the network state coordination interface for core app network monitoring
/// This protocol abstracts network state monitoring and provides a clean interface
/// for the core Mercury app to coordinate authentication operations with network state
@MainActor
public protocol NetworkStateCoordinationProtocol: ObservableObject {
    
    // MARK: - Network State Properties
    
    /// Current network connection state
    var networkState: NetworkConnectionState { get }
    
    /// Current network connection quality
    var connectionQuality: ConnectionQuality { get }
    
    /// Whether network is currently available for authentication operations
    var isNetworkAvailableForAuth: Bool { get }
    
    /// Whether network is currently available for posting operations
    var isNetworkAvailableForPosting: Bool { get }
    
    /// Current network interface type (WiFi, Cellular, etc.)
    var networkInterfaceType: NetworkInterfaceType { get }
    
    /// Estimated network latency in milliseconds
    var estimatedLatency: TimeInterval? { get }
    
    /// Network usage statistics for authentication operations
    var authNetworkUsage: NetworkUsageStats { get }
    
    // MARK: - Network State Publishers
    
    /// Publisher for network state changes
    var networkStatePublisher: AnyPublisher<NetworkConnectionState, Never> { get }
    
    /// Publisher for connection quality changes
    var connectionQualityPublisher: AnyPublisher<ConnectionQuality, Never> { get }
    
    /// Publisher for network availability changes for authentication
    var authNetworkAvailabilityPublisher: AnyPublisher<Bool, Never> { get }
    
    /// Publisher for network availability changes for posting
    var postNetworkAvailabilityPublisher: AnyPublisher<Bool, Never> { get }
    
    /// Publisher for network interface type changes
    var networkInterfacePublisher: AnyPublisher<NetworkInterfaceType, Never> { get }
    
    /// Publisher for latency changes
    var latencyPublisher: AnyPublisher<TimeInterval?, Never> { get }
    
    /// Publisher for network usage statistics updates
    var networkUsagePublisher: AnyPublisher<NetworkUsageStats, Never> { get }
    
    /// Combined publisher for comprehensive network state monitoring
    var combinedNetworkStatePublisher: AnyPublisher<NetworkStateSnapshot, Never> { get }
    
    /// Publisher for network events requiring attention
    var networkEventPublisher: AnyPublisher<NetworkCoordinationEvent, Never> { get }
    
    /// Publisher for network connectivity issues
    var connectivityIssuePublisher: AnyPublisher<NetworkConnectivityIssue, Never> { get }
    
    // MARK: - Network State Monitoring Methods
    
    /// Starts comprehensive network monitoring
    func startNetworkMonitoring() async
    
    /// Stops network monitoring
    func stopNetworkMonitoring() async
    
    /// Checks if network is available for a specific operation type
    /// - Parameter operationType: Type of operation to check
    /// - Returns: Whether network is available for the operation
    func isNetworkAvailable(for operationType: NetworkOperationType) async -> Bool
    
    /// Gets current network conditions for operation planning
    /// - Returns: Current network conditions
    func getCurrentNetworkConditions() async -> NetworkConditions
    
    /// Tests network connectivity with a lightweight probe
    /// - Returns: Network connectivity test result
    func testNetworkConnectivity() async -> NetworkConnectivityTestResult
    
    /// Gets network quality metrics for the current connection
    /// - Returns: Network quality metrics
    func getNetworkQualityMetrics() async -> NetworkQualityMetrics
    
    /// Estimates operation success probability based on network conditions
    /// - Parameter operationType: Type of operation to estimate
    /// - Returns: Success probability (0.0 to 1.0)
    func estimateOperationSuccessProbability(for operationType: NetworkOperationType) async -> Double
    
    // MARK: - Network State Coordination Methods
    
    /// Coordinates authentication operations with network state
    /// - Parameter operation: Authentication operation to coordinate
    /// - Returns: Coordination result with recommendations
    func coordinateAuthenticationOperation(_ operation: AuthenticationOperationType) async -> NetworkCoordinationResult
    
    /// Coordinates posting operations with network state
    /// - Parameter operation: Posting operation to coordinate
    /// - Returns: Coordination result with recommendations
    func coordinatePostingOperation(_ operation: PostingOperationType) async -> NetworkCoordinationResult
    
    /// Gets optimal timing for network-dependent operations
    /// - Parameter operationType: Type of operation to time
    /// - Returns: Optimal timing recommendation
    func getOptimalOperationTiming(for operationType: NetworkOperationType) async -> OperationTimingRecommendation
    
    /// Registers for network state change notifications
    /// - Parameters:
    ///   - states: Network states to monitor
    ///   - handler: Handler to call when state changes
    /// - Returns: Cancellable subscription
    func observeNetworkStates(_ states: [NetworkConnectionState], handler: @escaping (NetworkConnectionState) -> Void) -> AnyCancellable
    
    /// Registers for connection quality change notifications
    /// - Parameters:
    ///   - qualities: Quality levels to monitor
    ///   - handler: Handler to call when quality changes
    /// - Returns: Cancellable subscription
    func observeConnectionQualities(_ qualities: [ConnectionQuality], handler: @escaping (ConnectionQuality) -> Void) -> AnyCancellable
    
    /// Registers for network availability notifications
    /// - Parameters:
    ///   - operationType: Operation type to monitor availability for
    ///   - handler: Handler to call when availability changes
    /// - Returns: Cancellable subscription
    func observeNetworkAvailability(for operationType: NetworkOperationType, handler: @escaping (Bool) -> Void) -> AnyCancellable
    
    // MARK: - Network Recovery and Retry Coordination
    
    /// Gets retry strategy for failed operations based on network conditions
    /// - Parameters:
    ///   - operationType: Type of operation that failed
    ///   - failure: Details of the failure
    /// - Returns: Recommended retry strategy
    func getRetryStrategy(for operationType: NetworkOperationType, failure: NetworkOperationFailure) async -> NetworkRetryStrategy
    
    /// Schedules operation retry when network conditions improve
    /// - Parameters:
    ///   - operationType: Type of operation to retry
    ///   - conditions: Required network conditions for retry
    ///   - handler: Handler to call when conditions are met
    /// - Returns: Cancellable retry schedule
    func scheduleRetryOnNetworkImprovement(
        for operationType: NetworkOperationType,
        requiredConditions: NetworkConditions,
        handler: @escaping () -> Void
    ) -> AnyCancellable
    
    /// Cancels all pending network-based retry schedules
    func cancelAllRetrySchedules()
    
    /// Gets current retry schedules for monitoring
    /// - Returns: Array of active retry schedules
    func getCurrentRetrySchedules() -> [NetworkRetrySchedule]
    
    // MARK: - Network Usage Tracking
    
    /// Records network usage for an authentication operation
    /// - Parameters:
    ///   - operationType: Type of authentication operation
    ///   - bytesTransferred: Number of bytes transferred
    ///   - duration: Operation duration
    func recordAuthNetworkUsage(
        operationType: AuthenticationOperationType,
        bytesTransferred: Int64,
        duration: TimeInterval
    ) async
    
    /// Records network usage for a posting operation
    /// - Parameters:
    ///   - operationType: Type of posting operation
    ///   - bytesTransferred: Number of bytes transferred
    ///   - duration: Operation duration
    func recordPostNetworkUsage(
        operationType: PostingOperationType,
        bytesTransferred: Int64,
        duration: TimeInterval
    ) async
    
    /// Gets network usage statistics for a time period
    /// - Parameter period: Time period to get statistics for
    /// - Returns: Network usage statistics
    func getNetworkUsageStatistics(for period: NetworkUsageTimePeriod) async -> NetworkUsageStats
    
    /// Resets network usage statistics
    func resetNetworkUsageStatistics() async
    
    /// Exports network usage data for analysis
    /// - Returns: Exported usage data
    func exportNetworkUsageData() async -> NetworkUsageExportData
    
    // MARK: - Network State Persistence
    
    /// Saves current network state configuration
    /// - Returns: Whether save was successful
    func saveNetworkStateConfiguration() async -> Bool
    
    /// Restores network state configuration
    /// - Returns: Whether restore was successful
    func restoreNetworkStateConfiguration() async -> Bool
    
    /// Gets network monitoring preferences
    /// - Returns: Current network monitoring preferences
    func getNetworkMonitoringPreferences() -> NetworkMonitoringPreferences
    
    /// Updates network monitoring preferences
    /// - Parameter preferences: New preferences to apply
    func updateNetworkMonitoringPreferences(_ preferences: NetworkMonitoringPreferences) async
    
    // MARK: - Network Diagnostics
    
    /// Runs comprehensive network diagnostics
    /// - Returns: Network diagnostic results
    func runNetworkDiagnostics() async -> NetworkDiagnosticResults
    
    /// Gets network troubleshooting recommendations
    /// - Parameter issue: Network issue to troubleshoot
    /// - Returns: Troubleshooting recommendations
    func getNetworkTroubleshootingRecommendations(for issue: NetworkConnectivityIssue) async -> [NetworkTroubleshootingRecommendation]
    
    /// Tests specific network endpoints for connectivity
    /// - Parameter endpoints: Endpoints to test
    /// - Returns: Endpoint connectivity test results
    func testEndpointConnectivity(_ endpoints: [NetworkEndpoint]) async -> [EndpointConnectivityResult]
    
    /// Measures network performance metrics
    /// - Returns: Current network performance metrics
    func measureNetworkPerformance() async -> NetworkPerformanceMetrics
    
    /// Gets network health score (0.0 to 1.0)
    /// - Returns: Current network health score
    func getNetworkHealthScore() async -> Double
}

// MARK: - Supporting Types

/// Current network connection state
public enum NetworkConnectionState: String, CaseIterable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case limited = "limited"
    case unstable = "unstable"
    
    public var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .limited:
            return "Limited Connectivity"
        case .unstable:
            return "Unstable Connection"
        }
    }
    
    public var isAvailable: Bool {
        switch self {
        case .connected, .limited:
            return true
        case .disconnected, .connecting, .unstable:
            return false
        }
    }
}

/// Network connection quality levels
public enum ConnectionQuality: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case unknown = "unknown"
    
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
        case .unknown:
            return "Unknown"
        }
    }
    
    public var qualityScore: Double {
        switch self {
        case .excellent:
            return 1.0
        case .good:
            return 0.75
        case .fair:
            return 0.5
        case .poor:
            return 0.25
        case .unknown:
            return 0.0
        }
    }
}

/// Network interface types
public enum NetworkInterfaceType: String, CaseIterable {
    case wifi = "wifi"
    case cellular = "cellular"
    case ethernet = "ethernet"
    case vpn = "vpn"
    case other = "other"
    case unknown = "unknown"
    
    public var description: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .ethernet:
            return "Ethernet"
        case .vpn:
            return "VPN"
        case .other:
            return "Other"
        case .unknown:
            return "Unknown"
        }
    }
    
    public var isMetered: Bool {
        switch self {
        case .cellular:
            return true
        case .wifi, .ethernet, .vpn, .other, .unknown:
            return false
        }
    }
}

/// Types of network operations
public enum NetworkOperationType: String, CaseIterable {
    case authentication = "authentication"
    case tokenRefresh = "tokenRefresh"
    case posting = "posting"
    case queueProcessing = "queueProcessing"
    case diagnostics = "diagnostics"
    case monitoring = "monitoring"
    
    public var description: String {
        switch self {
        case .authentication:
            return "Authentication"
        case .tokenRefresh:
            return "Token Refresh"
        case .posting:
            return "Tweet Posting"
        case .queueProcessing:
            return "Queue Processing"
        case .diagnostics:
            return "Network Diagnostics"
        case .monitoring:
            return "Network Monitoring"
        }
    }
    
    public var requiredQuality: ConnectionQuality {
        switch self {
        case .authentication, .tokenRefresh:
            return .fair
        case .posting, .queueProcessing:
            return .good
        case .diagnostics, .monitoring:
            return .poor
        }
    }
}

/// Authentication operation types for network coordination
public enum AuthenticationOperationType: String, CaseIterable {
    case initialAuth = "initialAuth"
    case tokenRefresh = "tokenRefresh"
    case tokenValidation = "tokenValidation"
    case userInfoRetrieval = "userInfoRetrieval"
    case disconnection = "disconnection"
    
    public var description: String {
        switch self {
        case .initialAuth:
            return "Initial Authentication"
        case .tokenRefresh:
            return "Token Refresh"
        case .tokenValidation:
            return "Token Validation"
        case .userInfoRetrieval:
            return "User Info Retrieval"
        case .disconnection:
            return "Disconnection"
        }
    }
}

/// Posting operation types for network coordination
public enum PostingOperationType: String, CaseIterable {
    case singlePost = "singlePost"
    case queueProcessing = "queueProcessing"
    case retryPost = "retryPost"
    case bulkPosting = "bulkPosting"
    
    public var description: String {
        switch self {
        case .singlePost:
            return "Single Post"
        case .queueProcessing:
            return "Queue Processing"
        case .retryPost:
            return "Retry Post"
        case .bulkPosting:
            return "Bulk Posting"
        }
    }
}

/// Network usage statistics
public struct NetworkUsageStats {
    public let totalBytesTransferred: Int64
    public let totalOperations: Int
    public let averageOperationSize: Int64
    public let averageOperationDuration: TimeInterval
    public let successRate: Double
    public let period: NetworkUsageTimePeriod
    public let lastUpdated: Date
    
    public init(
        totalBytesTransferred: Int64,
        totalOperations: Int,
        averageOperationSize: Int64,
        averageOperationDuration: TimeInterval,
        successRate: Double,
        period: NetworkUsageTimePeriod,
        lastUpdated: Date = Date()
    ) {
        self.totalBytesTransferred = totalBytesTransferred
        self.totalOperations = totalOperations
        self.averageOperationSize = averageOperationSize
        self.averageOperationDuration = averageOperationDuration
        self.successRate = successRate
        self.period = period
        self.lastUpdated = lastUpdated
    }
}

/// Time periods for network usage tracking
public enum NetworkUsageTimePeriod: String, CaseIterable {
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case all = "all"
    
    public var description: String {
        switch self {
        case .hourly:
            return "Last Hour"
        case .daily:
            return "Last 24 Hours"
        case .weekly:
            return "Last Week"
        case .monthly:
            return "Last Month"
        case .all:
            return "All Time"
        }
    }
}

/// Comprehensive network state snapshot
public struct NetworkStateSnapshot {
    public let networkState: NetworkConnectionState
    public let connectionQuality: ConnectionQuality
    public let interfaceType: NetworkInterfaceType
    public let estimatedLatency: TimeInterval?
    public let isAvailableForAuth: Bool
    public let isAvailableForPosting: Bool
    public let timestamp: Date
    
    public init(
        networkState: NetworkConnectionState,
        connectionQuality: ConnectionQuality,
        interfaceType: NetworkInterfaceType,
        estimatedLatency: TimeInterval?,
        isAvailableForAuth: Bool,
        isAvailableForPosting: Bool,
        timestamp: Date = Date()
    ) {
        self.networkState = networkState
        self.connectionQuality = connectionQuality
        self.interfaceType = interfaceType
        self.estimatedLatency = estimatedLatency
        self.isAvailableForAuth = isAvailableForAuth
        self.isAvailableForPosting = isAvailableForPosting
        self.timestamp = timestamp
    }
}

/// Network coordination events
public struct NetworkCoordinationEvent {
    public let eventType: NetworkEventType
    public let networkState: NetworkConnectionState
    public let affectedOperations: [NetworkOperationType]
    public let recommendations: [String]
    public let timestamp: Date
    
    public init(
        eventType: NetworkEventType,
        networkState: NetworkConnectionState,
        affectedOperations: [NetworkOperationType],
        recommendations: [String],
        timestamp: Date = Date()
    ) {
        self.eventType = eventType
        self.networkState = networkState
        self.affectedOperations = affectedOperations
        self.recommendations = recommendations
        self.timestamp = timestamp
    }
}

/// Types of network coordination events
public enum NetworkEventType: String, CaseIterable {
    case connectionEstablished = "connectionEstablished"
    case connectionLost = "connectionLost"
    case qualityImproved = "qualityImproved"
    case qualityDegraded = "qualityDegraded"
    case interfaceChanged = "interfaceChanged"
    case latencyIncreased = "latencyIncreased"
    case retryRecommended = "retryRecommended"
    case operationScheduled = "operationScheduled"
    
    public var description: String {
        switch self {
        case .connectionEstablished:
            return "Connection Established"
        case .connectionLost:
            return "Connection Lost"
        case .qualityImproved:
            return "Quality Improved"
        case .qualityDegraded:
            return "Quality Degraded"
        case .interfaceChanged:
            return "Interface Changed"
        case .latencyIncreased:
            return "Latency Increased"
        case .retryRecommended:
            return "Retry Recommended"
        case .operationScheduled:
            return "Operation Scheduled"
        }
    }
}

/// Network connectivity issues
public struct NetworkConnectivityIssue {
    public let issueType: ConnectivityIssueType
    public let severity: ConnectivityIssueSeverity
    public let description: String
    public let affectedOperations: [NetworkOperationType]
    public let detectedAt: Date
    public let resolvedAt: Date?
    
    public init(
        issueType: ConnectivityIssueType,
        severity: ConnectivityIssueSeverity,
        description: String,
        affectedOperations: [NetworkOperationType],
        detectedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.issueType = issueType
        self.severity = severity
        self.description = description
        self.affectedOperations = affectedOperations
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
    }
    
    public var isResolved: Bool {
        return resolvedAt != nil
    }
}

/// Types of connectivity issues
public enum ConnectivityIssueType: String, CaseIterable {
    case noConnection = "noConnection"
    case slowConnection = "slowConnection"
    case unstableConnection = "unstableConnection"
    case limitedConnection = "limitedConnection"
    case highLatency = "highLatency"
    case frequentTimeouts = "frequentTimeouts"
    case dnsIssues = "dnsIssues"
    case certificateIssues = "certificateIssues"
}

/// Severity levels for connectivity issues
public enum ConnectivityIssueSeverity: String, CaseIterable {
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

/// Network conditions for operation planning
public struct NetworkConditions {
    public let connectionState: NetworkConnectionState
    public let quality: ConnectionQuality
    public let latency: TimeInterval?
    public let bandwidth: NetworkBandwidth?
    public let stability: NetworkStability
    public let timestamp: Date
    
    public init(
        connectionState: NetworkConnectionState,
        quality: ConnectionQuality,
        latency: TimeInterval?,
        bandwidth: NetworkBandwidth?,
        stability: NetworkStability,
        timestamp: Date = Date()
    ) {
        self.connectionState = connectionState
        self.quality = quality
        self.latency = latency
        self.bandwidth = bandwidth
        self.stability = stability
        self.timestamp = timestamp
    }
    
    public var meetsRequirements: Bool {
        return connectionState.isAvailable && quality.qualityScore >= 0.5
    }
}

/// Network bandwidth information
public struct NetworkBandwidth {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let measuredAt: Date
    
    public init(downloadMbps: Double, uploadMbps: Double, measuredAt: Date = Date()) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.measuredAt = measuredAt
    }
}

/// Network stability metrics
public enum NetworkStability: String, CaseIterable {
    case stable = "stable"
    case mostlyStable = "mostlyStable"
    case unstable = "unstable"
    case veryUnstable = "veryUnstable"
    
    public var stabilityScore: Double {
        switch self {
        case .stable:
            return 1.0
        case .mostlyStable:
            return 0.75
        case .unstable:
            return 0.5
        case .veryUnstable:
            return 0.25
        }
    }
}

// MARK: - Additional Supporting Types

/// Network connectivity test result
public struct NetworkConnectivityTestResult {
    public let isConnected: Bool
    public let latency: TimeInterval?
    public let testedEndpoints: [String]
    public let successfulEndpoints: [String]
    public let failedEndpoints: [String]
    public let testDuration: TimeInterval
    public let timestamp: Date
    
    public init(
        isConnected: Bool,
        latency: TimeInterval?,
        testedEndpoints: [String],
        successfulEndpoints: [String],
        failedEndpoints: [String],
        testDuration: TimeInterval,
        timestamp: Date = Date()
    ) {
        self.isConnected = isConnected
        self.latency = latency
        self.testedEndpoints = testedEndpoints
        self.successfulEndpoints = successfulEndpoints
        self.failedEndpoints = failedEndpoints
        self.testDuration = testDuration
        self.timestamp = timestamp
    }
}

/// Network quality metrics
public struct NetworkQualityMetrics {
    public let connectionQuality: ConnectionQuality
    public let latency: TimeInterval
    public let jitter: TimeInterval
    public let packetLoss: Double
    public let bandwidth: NetworkBandwidth?
    public let stability: NetworkStability
    public let measuredAt: Date
    
    public init(
        connectionQuality: ConnectionQuality,
        latency: TimeInterval,
        jitter: TimeInterval,
        packetLoss: Double,
        bandwidth: NetworkBandwidth?,
        stability: NetworkStability,
        measuredAt: Date = Date()
    ) {
        self.connectionQuality = connectionQuality
        self.latency = latency
        self.jitter = jitter
        self.packetLoss = packetLoss
        self.bandwidth = bandwidth
        self.stability = stability
        self.measuredAt = measuredAt
    }
}

/// Network coordination result
public struct NetworkCoordinationResult {
    public let canProceed: Bool
    public let recommendations: [NetworkRecommendation]
    public let estimatedDelay: TimeInterval?
    public let alternativeApproaches: [String]
    public let coordinatedAt: Date
    
    public init(
        canProceed: Bool,
        recommendations: [NetworkRecommendation],
        estimatedDelay: TimeInterval? = nil,
        alternativeApproaches: [String] = [],
        coordinatedAt: Date = Date()
    ) {
        self.canProceed = canProceed
        self.recommendations = recommendations
        self.estimatedDelay = estimatedDelay
        self.alternativeApproaches = alternativeApproaches
        self.coordinatedAt = coordinatedAt
    }
}

/// Network recommendation
public struct NetworkRecommendation {
    public let type: NetworkRecommendationType
    public let priority: NetworkRecommendationPriority
    public let description: String
    public let estimatedImpact: String
    
    public init(
        type: NetworkRecommendationType,
        priority: NetworkRecommendationPriority,
        description: String,
        estimatedImpact: String
    ) {
        self.type = type
        self.priority = priority
        self.description = description
        self.estimatedImpact = estimatedImpact
    }
}

/// Types of network recommendations
public enum NetworkRecommendationType: String, CaseIterable {
    case waitForBetterConnection = "waitForBetterConnection"
    case retryWithBackoff = "retryWithBackoff"
    case useQueueing = "useQueueing"
    case reduceOperationSize = "reduceOperationSize"
    case switchInterface = "switchInterface"
    case scheduleForLater = "scheduleForLater"
}

/// Priority levels for network recommendations
public enum NetworkRecommendationPriority: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

/// Operation timing recommendation
public struct OperationTimingRecommendation {
    public let recommendedDelay: TimeInterval?
    public let optimalTimeWindow: DateInterval?
    public let reasoning: String
    public let confidenceLevel: Double
    public let createdAt: Date
    
    public init(
        recommendedDelay: TimeInterval?,
        optimalTimeWindow: DateInterval?,
        reasoning: String,
        confidenceLevel: Double,
        createdAt: Date = Date()
    ) {
        self.recommendedDelay = recommendedDelay
        self.optimalTimeWindow = optimalTimeWindow
        self.reasoning = reasoning
        self.confidenceLevel = confidenceLevel
        self.createdAt = createdAt
    }
}

/// Network operation failure details
public struct NetworkOperationFailure {
    public let operationType: NetworkOperationType
    public let errorType: NetworkErrorType
    public let errorDescription: String
    public let networkStateAtFailure: NetworkConnectionState
    public let attemptCount: Int
    public let failedAt: Date
    
    public init(
        operationType: NetworkOperationType,
        errorType: NetworkErrorType,
        errorDescription: String,
        networkStateAtFailure: NetworkConnectionState,
        attemptCount: Int,
        failedAt: Date = Date()
    ) {
        self.operationType = operationType
        self.errorType = errorType
        self.errorDescription = errorDescription
        self.networkStateAtFailure = networkStateAtFailure
        self.attemptCount = attemptCount
        self.failedAt = failedAt
    }
}

/// Network error types
public enum NetworkErrorType: String, CaseIterable {
    case timeout = "timeout"
    case connectionLost = "connectionLost"
    case dnsFailure = "dnsFailure"
    case certificateError = "certificateError"
    case serverUnreachable = "serverUnreachable"
    case rateLimited = "rateLimited"
    case unknown = "unknown"
}

/// Network retry strategy
public struct NetworkRetryStrategy {
    public let shouldRetry: Bool
    public let retryDelay: TimeInterval
    public let maxRetries: Int
    public let backoffMultiplier: Double
    public let requiredConditions: NetworkConditions?
    public let strategy: RetryStrategyType
    
    public init(
        shouldRetry: Bool,
        retryDelay: TimeInterval,
        maxRetries: Int,
        backoffMultiplier: Double,
        requiredConditions: NetworkConditions?,
        strategy: RetryStrategyType
    ) {
        self.shouldRetry = shouldRetry
        self.retryDelay = retryDelay
        self.maxRetries = maxRetries
        self.backoffMultiplier = backoffMultiplier
        self.requiredConditions = requiredConditions
        self.strategy = strategy
    }
}

/// Retry strategy types
public enum RetryStrategyType: String, CaseIterable {
    case immediate = "immediate"
    case exponentialBackoff = "exponentialBackoff"
    case fixedInterval = "fixedInterval"
    case waitForConnection = "waitForConnection"
    case waitForQuality = "waitForQuality"
    case scheduleForLater = "scheduleForLater"
}

/// Network retry schedule
public struct NetworkRetrySchedule {
    public let id: UUID
    public let operationType: NetworkOperationType
    public let requiredConditions: NetworkConditions
    public let scheduledAt: Date
    public let expiresAt: Date?
    public let handler: () -> Void
    
    public init(
        operationType: NetworkOperationType,
        requiredConditions: NetworkConditions,
        scheduledAt: Date = Date(),
        expiresAt: Date? = nil,
        handler: @escaping () -> Void
    ) {
        self.id = UUID()
        self.operationType = operationType
        self.requiredConditions = requiredConditions
        self.scheduledAt = scheduledAt
        self.expiresAt = expiresAt
        self.handler = handler
    }
    
    public var isExpired: Bool {
        if let expiresAt = expiresAt {
            return Date() > expiresAt
        }
        return false
    }
}

/// Network usage export data
public struct NetworkUsageExportData {
    public let exportDate: Date
    public let period: NetworkUsageTimePeriod
    public let statistics: NetworkUsageStats
    public let detailedOperations: [NetworkOperationRecord]
    public let qualityMetrics: [NetworkQualityMetrics]
    public let issues: [NetworkConnectivityIssue]
    
    public init(
        exportDate: Date = Date(),
        period: NetworkUsageTimePeriod,
        statistics: NetworkUsageStats,
        detailedOperations: [NetworkOperationRecord],
        qualityMetrics: [NetworkQualityMetrics],
        issues: [NetworkConnectivityIssue]
    ) {
        self.exportDate = exportDate
        self.period = period
        self.statistics = statistics
        self.detailedOperations = detailedOperations
        self.qualityMetrics = qualityMetrics
        self.issues = issues
    }
}

/// Network operation record
public struct NetworkOperationRecord {
    public let operationType: NetworkOperationType
    public let startTime: Date
    public let endTime: Date
    public let bytesTransferred: Int64
    public let success: Bool
    public let errorType: NetworkErrorType?
    public let networkConditions: NetworkConditions
    
    public init(
        operationType: NetworkOperationType,
        startTime: Date,
        endTime: Date,
        bytesTransferred: Int64,
        success: Bool,
        errorType: NetworkErrorType?,
        networkConditions: NetworkConditions
    ) {
        self.operationType = operationType
        self.startTime = startTime
        self.endTime = endTime
        self.bytesTransferred = bytesTransferred
        self.success = success
        self.errorType = errorType
        self.networkConditions = networkConditions
    }
    
    public var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
}

/// Network monitoring preferences
public struct NetworkMonitoringPreferences {
    public let monitoringEnabled: Bool
    public let updateInterval: TimeInterval
    public let qualityTestingEnabled: Bool
    public let usageTrackingEnabled: Bool
    public let diagnosticsEnabled: Bool
    public let alertsEnabled: Bool
    public let preferredInterface: NetworkInterfaceType?
    
    public init(
        monitoringEnabled: Bool = true,
        updateInterval: TimeInterval = 30.0,
        qualityTestingEnabled: Bool = true,
        usageTrackingEnabled: Bool = true,
        diagnosticsEnabled: Bool = false,
        alertsEnabled: Bool = true,
        preferredInterface: NetworkInterfaceType? = nil
    ) {
        self.monitoringEnabled = monitoringEnabled
        self.updateInterval = updateInterval
        self.qualityTestingEnabled = qualityTestingEnabled
        self.usageTrackingEnabled = usageTrackingEnabled
        self.diagnosticsEnabled = diagnosticsEnabled
        self.alertsEnabled = alertsEnabled
        self.preferredInterface = preferredInterface
    }
    
    public static let `default` = NetworkMonitoringPreferences()
}

/// Network diagnostic results
public struct NetworkDiagnosticResults {
    public let overallHealth: NetworkHealthStatus
    public let connectivityTests: [ConnectivityTestResult]
    public let performanceMetrics: NetworkPerformanceMetrics
    public let identifiedIssues: [NetworkConnectivityIssue]
    public let recommendations: [NetworkTroubleshootingRecommendation]
    public let diagnosticDate: Date
    
    public init(
        overallHealth: NetworkHealthStatus,
        connectivityTests: [ConnectivityTestResult],
        performanceMetrics: NetworkPerformanceMetrics,
        identifiedIssues: [NetworkConnectivityIssue],
        recommendations: [NetworkTroubleshootingRecommendation],
        diagnosticDate: Date = Date()
    ) {
        self.overallHealth = overallHealth
        self.connectivityTests = connectivityTests
        self.performanceMetrics = performanceMetrics
        self.identifiedIssues = identifiedIssues
        self.recommendations = recommendations
        self.diagnosticDate = diagnosticDate
    }
}

/// Network health status
public enum NetworkHealthStatus: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case critical = "critical"
    
    public var healthScore: Double {
        switch self {
        case .excellent:
            return 1.0
        case .good:
            return 0.8
        case .fair:
            return 0.6
        case .poor:
            return 0.4
        case .critical:
            return 0.2
        }
    }
}

/// Connectivity test result
public struct ConnectivityTestResult {
    public let endpoint: NetworkEndpoint
    public let success: Bool
    public let responseTime: TimeInterval?
    public let errorDescription: String?
    public let testedAt: Date
    
    public init(
        endpoint: NetworkEndpoint,
        success: Bool,
        responseTime: TimeInterval?,
        errorDescription: String?,
        testedAt: Date = Date()
    ) {
        self.endpoint = endpoint
        self.success = success
        self.responseTime = responseTime
        self.errorDescription = errorDescription
        self.testedAt = testedAt
    }
}

/// Network endpoint information
public struct NetworkEndpoint {
    public let name: String
    public let url: URL
    public let expectedResponseTime: TimeInterval
    public let critical: Bool
    
    public init(name: String, url: URL, expectedResponseTime: TimeInterval, critical: Bool = false) {
        self.name = name
        self.url = url
        self.expectedResponseTime = expectedResponseTime
        self.critical = critical
    }
}

/// Endpoint connectivity result
public struct EndpointConnectivityResult {
    public let endpoint: NetworkEndpoint
    public let reachable: Bool
    public let responseTime: TimeInterval?
    public let statusCode: Int?
    public let error: Error?
    public let testedAt: Date
    
    public init(
        endpoint: NetworkEndpoint,
        reachable: Bool,
        responseTime: TimeInterval?,
        statusCode: Int?,
        error: Error?,
        testedAt: Date = Date()
    ) {
        self.endpoint = endpoint
        self.reachable = reachable
        self.responseTime = responseTime
        self.statusCode = statusCode
        self.error = error
        self.testedAt = testedAt
    }
}

/// Network performance metrics
public struct NetworkPerformanceMetrics {
    public let averageLatency: TimeInterval
    public let averageJitter: TimeInterval
    public let packetLossRate: Double
    public let throughput: NetworkBandwidth?
    public let connectionStability: NetworkStability
    public let measuredOverPeriod: TimeInterval
    public let measuredAt: Date
    
    public init(
        averageLatency: TimeInterval,
        averageJitter: TimeInterval,
        packetLossRate: Double,
        throughput: NetworkBandwidth?,
        connectionStability: NetworkStability,
        measuredOverPeriod: TimeInterval,
        measuredAt: Date = Date()
    ) {
        self.averageLatency = averageLatency
        self.averageJitter = averageJitter
        self.packetLossRate = packetLossRate
        self.throughput = throughput
        self.connectionStability = connectionStability
        self.measuredOverPeriod = measuredOverPeriod
        self.measuredAt = measuredAt
    }
}

/// Network troubleshooting recommendation
public struct NetworkTroubleshootingRecommendation {
    public let issue: NetworkConnectivityIssue
    public let recommendation: String
    public let priority: NetworkRecommendationPriority
    public let estimatedResolutionTime: TimeInterval?
    public let requiresUserAction: Bool
    public let automaticResolutionPossible: Bool
    
    public init(
        issue: NetworkConnectivityIssue,
        recommendation: String,
        priority: NetworkRecommendationPriority,
        estimatedResolutionTime: TimeInterval?,
        requiresUserAction: Bool,
        automaticResolutionPossible: Bool
    ) {
        self.issue = issue
        self.recommendation = recommendation
        self.priority = priority
        self.estimatedResolutionTime = estimatedResolutionTime
        self.requiresUserAction = requiresUserAction
        self.automaticResolutionPossible = automaticResolutionPossible
    }
}

// MARK: - Protocol Extension for Default Implementations

/// Extension providing default implementations for optional protocol methods
public extension NetworkStateCoordinationProtocol {
    
    /// Default implementation for network monitoring startup
    func startNetworkMonitoring() async {
        // Default: no-op - implementations can override
    }
    
    /// Default implementation for network monitoring shutdown
    func stopNetworkMonitoring() async {
        // Default: no-op - implementations can override
    }
    
    /// Default implementation for network availability check
    func isNetworkAvailable(for operationType: NetworkOperationType) async -> Bool {
        return networkState.isAvailable
    }
    
    /// Default implementation for operation success probability estimation
    func estimateOperationSuccessProbability(for operationType: NetworkOperationType) async -> Double {
        return connectionQuality.qualityScore
    }
    
    /// Default implementation for retry schedule cancellation
    func cancelAllRetrySchedules() {
        // Default: no-op - implementations can override
    }
    
    /// Default implementation for network configuration save
    func saveNetworkStateConfiguration() async -> Bool {
        return true
    }
    
    /// Default implementation for network configuration restore
    func restoreNetworkStateConfiguration() async -> Bool {
        return true
    }
    
    /// Default implementation for network usage statistics reset
    func resetNetworkUsageStatistics() async {
        // Default: no-op - implementations can override
    }
    
    /// Default implementation for network health score
    func getNetworkHealthScore() async -> Double {
        return connectionQuality.qualityScore * networkState.isAvailable.doubleValue
    }
}

// MARK: - Helper Extensions

extension Bool {
    fileprivate var doubleValue: Double {
        return self ? 1.0 : 0.0
    }
}
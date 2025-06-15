import Foundation
import Combine

/// Extension to AuthManager implementing RateLimitStatusCoordinationProtocol
/// This provides the core app with a clean interface for rate limit status coordination
extension AuthManager: RateLimitStatusCoordinationProtocol {
    
    // MARK: - Rate Limit Status Properties
    
    /// Current rate limit information
    public var currentRateLimitInfo: RateLimitInfo {
        return rateLimitManager.currentRateLimitInfo
    }
    
    /// Current monthly post usage
    public var currentMonthlyUsage: MonthlyUsageInfo {
        return rateLimitStatusTracker.getCurrentMonthlyUsage()
    }
    
    /// Current daily post usage
    public var currentDailyUsage: DailyUsageInfo {
        return rateLimitStatusTracker.getCurrentDailyUsage()
    }
    
    /// Current hourly post usage
    public var currentHourlyUsage: HourlyUsageInfo {
        return rateLimitStatusTracker.getCurrentHourlyUsage()
    }
    
    /// Whether currently rate limited
    public var isCurrentlyRateLimited: Bool {
        return rateLimitManager.isCurrentlyLimited
    }
    
    /// Whether approaching rate limit (warning threshold)
    public var isApproachingRateLimit: Bool {
        return rateLimitManager.isApproachingLimit
    }
    
    /// Estimated time until rate limit reset
    public var timeUntilRateLimitReset: TimeInterval? {
        return rateLimitManager.timeUntilReset
    }
    
    /// Current rate limit utilization percentage (0.0 to 1.0)
    public var rateLimitUtilization: Double {
        return rateLimitManager.currentUtilization
    }
    
    /// Remaining requests in current window
    public var remainingRequests: Int {
        return rateLimitManager.remainingRequests
    }
    
    /// Maximum requests in current window
    public var maxRequests: Int {
        return rateLimitManager.maxRequests
    }
    
    /// Current rate limit window type
    public var currentWindowType: RateLimitWindowType {
        return rateLimitStatusTracker.getCurrentWindowType()
    }
    
    /// Rate limit compliance status
    public var complianceStatus: RateLimitComplianceStatus {
        return rateLimitComplianceMonitor.getCurrentComplianceStatus()
    }
    
    // MARK: - Rate Limit Status Publishers
    
    /// Publisher for rate limit information changes
    public var rateLimitInfoPublisher: AnyPublisher<RateLimitInfo, Never> {
        return rateLimitManager.rateLimitInfoPublisher
    }
    
    /// Publisher for monthly usage changes
    public var monthlyUsagePublisher: AnyPublisher<MonthlyUsageInfo, Never> {
        return rateLimitStatusTracker.monthlyUsagePublisher
    }
    
    /// Publisher for daily usage changes
    public var dailyUsagePublisher: AnyPublisher<DailyUsageInfo, Never> {
        return rateLimitStatusTracker.dailyUsagePublisher
    }
    
    /// Publisher for hourly usage changes
    public var hourlyUsagePublisher: AnyPublisher<HourlyUsageInfo, Never> {
        return rateLimitStatusTracker.hourlyUsagePublisher
    }
    
    /// Publisher for rate limit status changes (limited/not limited)
    public var rateLimitStatusPublisher: AnyPublisher<Bool, Never> {
        return rateLimitManager.rateLimitStatusPublisher
    }
    
    /// Publisher for rate limit warning threshold changes
    public var rateLimitWarningPublisher: AnyPublisher<RateLimitWarning, Never> {
        return rateLimitWarningSystem.warningPublisher
    }
    
    /// Publisher for rate limit utilization changes
    public var utilizationPublisher: AnyPublisher<Double, Never> {
        return rateLimitManager.utilizationPublisher
    }
    
    /// Publisher for remaining requests changes
    public var remainingRequestsPublisher: AnyPublisher<Int, Never> {
        return rateLimitManager.remainingRequestsPublisher
    }
    
    /// Publisher for rate limit window resets
    public var windowResetPublisher: AnyPublisher<RateLimitWindowReset, Never> {
        return rateLimitWindowManager.windowResetPublisher
    }
    
    /// Publisher for compliance status changes
    public var complianceStatusPublisher: AnyPublisher<RateLimitComplianceStatus, Never> {
        return rateLimitComplianceMonitor.complianceStatusPublisher
    }
    
    /// Combined publisher for comprehensive rate limit monitoring
    public var combinedRateLimitStatusPublisher: AnyPublisher<RateLimitStatusSnapshot, Never> {
        return Publishers.CombineLatest4(
            rateLimitInfoPublisher,
            monthlyUsagePublisher,
            dailyUsagePublisher,
            hourlyUsagePublisher
        )
        .combineLatest(
            complianceStatusPublisher,
            utilizationPublisher
        )
        .map { [weak self] combined, complianceStatus, utilization in
            let (rateLimitInfo, monthlyUsage, dailyUsage, hourlyUsage) = combined
            return RateLimitStatusSnapshot(
                rateLimitInfo: rateLimitInfo,
                monthlyUsage: monthlyUsage,
                dailyUsage: dailyUsage,
                hourlyUsage: hourlyUsage,
                complianceStatus: complianceStatus,
                utilization: utilization,
                isRateLimited: self?.isCurrentlyRateLimited ?? false,
                timeUntilReset: self?.timeUntilRateLimitReset
            )
        }
        .eraseToAnyPublisher()
    }
    
    /// Publisher for rate limit events requiring attention
    public var rateLimitEventPublisher: AnyPublisher<RateLimitCoordinationEvent, Never> {
        return rateLimitEventCoordinator.eventPublisher
    }
    
    // MARK: - Rate Limit Tracking Methods
    
    /// Records a successful post for rate limit tracking
    public func recordSuccessfulPost(
        postType: PostType,
        timestamp: Date,
        metadata: PostMetadata?
    ) async {
        await rateLimitUsageRecorder.recordSuccessfulPost(
            postType: postType,
            timestamp: timestamp,
            metadata: metadata
        )
        
        // Update internal rate limit tracking
        await rateLimitManager.recordPostUsage()
        
        // Update usage statistics
        await rateLimitStatusTracker.updateUsageStatistics()
        
        // Check for threshold violations
        await rateLimitComplianceMonitor.checkComplianceAfterPost()
    }
    
    /// Records a failed post attempt for rate limit tracking
    public func recordFailedPostAttempt(
        postType: PostType,
        failureReason: PostFailureReason,
        timestamp: Date,
        metadata: PostMetadata?
    ) async {
        await rateLimitUsageRecorder.recordFailedPostAttempt(
            postType: postType,
            failureReason: failureReason,
            timestamp: timestamp,
            metadata: metadata
        )
        
        // Only update rate limit tracking if failure affects limits
        if failureReason.affectsRateLimit {
            await rateLimitManager.recordPostUsage()
        }
        
        // Update usage statistics and failure tracking
        await rateLimitStatusTracker.updateFailureStatistics(reason: failureReason)
    }
    
    /// Records rate limit response from X API
    public func recordRateLimitResponse(_ rateLimitResponse: APIRateLimitResponse) async {
        await rateLimitManager.updateFromAPIResponse(rateLimitResponse)
        await rateLimitStatusTracker.recordAPIResponse(rateLimitResponse)
        await rateLimitComplianceMonitor.validateComplianceFromAPIResponse(rateLimitResponse)
    }
    
    /// Updates usage statistics based on current data
    public func updateUsageStatistics() async {
        await rateLimitStatusTracker.refreshAllStatistics()
        await rateLimitComplianceMonitor.reevaluateCompliance()
        await rateLimitPredictionEngine.updatePredictionModels()
    }
    
    /// Refreshes rate limit information from X API
    public func refreshRateLimitInfo() async -> RateLimitInfo {
        let refreshedInfo = await rateLimitManager.refreshFromAPI()
        await rateLimitStatusTracker.syncWithRateLimitInfo(refreshedInfo)
        return refreshedInfo
    }
    
    /// Gets detailed usage breakdown for a specific time period
    public func getUsageBreakdown(for period: UsageTimePeriod) async -> UsageBreakdown {
        return await rateLimitAnalyzer.generateUsageBreakdown(for: period)
    }
    
    /// Gets usage trends and predictions
    public func getUsageTrends() async -> UsageTrendAnalysis {
        return await rateLimitTrendAnalyzer.generateTrendAnalysis()
    }
    
    /// Gets rate limit compliance report
    public func getComplianceReport() async -> RateLimitComplianceReport {
        return await rateLimitComplianceMonitor.generateComplianceReport()
    }
    
    // MARK: - Rate Limit Prediction and Planning
    
    /// Predicts if a post can be made without hitting rate limits
    public func canMakePost(postType: PostType, scheduledTime: Date) async -> PostViabilityResult {
        return await rateLimitPostViabilityChecker.checkPostViability(
            postType: postType,
            scheduledTime: scheduledTime
        )
    }
    
    /// Gets optimal timing for making a post to avoid rate limits
    public func getOptimalPostTiming(for postType: PostType) async -> PostTimingRecommendation {
        return await rateLimitTimingOptimizer.getOptimalTiming(for: postType)
    }
    
    /// Estimates when rate limit will reset for specific operation
    public func estimateRateLimitReset(for operationType: RateLimitOperationType) async -> Date? {
        return await rateLimitResetEstimator.estimateReset(for: operationType)
    }
    
    /// Predicts usage for remainder of current period
    public func predictUsage(for period: UsageTimePeriod) async -> UsagePrediction {
        return await rateLimitPredictionEngine.predictUsage(for: period)
    }
    
    /// Gets recommended posting strategy based on current limits
    public func getRecommendedPostingStrategy() async -> PostingStrategyRecommendation {
        return await rateLimitStrategyAdvisor.generatePostingStrategy()
    }
    
    /// Analyzes posting patterns and suggests optimizations
    public func analyzePostingPatterns() async -> PostingPatternAnalysis {
        return await rateLimitPatternAnalyzer.analyzePatterns()
    }
    
    // MARK: - Rate Limit Configuration and Preferences
    
    /// Gets current rate limit monitoring preferences
    public func getRateLimitPreferences() -> RateLimitMonitoringPreferences {
        return rateLimitPreferencesManager.getCurrentPreferences()
    }
    
    /// Updates rate limit monitoring preferences
    public func updateRateLimitPreferences(_ preferences: RateLimitMonitoringPreferences) async {
        await rateLimitPreferencesManager.updatePreferences(preferences)
        await rateLimitStatusTracker.applyPreferences(preferences)
    }
    
    /// Gets rate limit warning thresholds
    public func getWarningThresholds() -> RateLimitWarningThresholds {
        return rateLimitWarningSystem.getCurrentThresholds()
    }
    
    /// Updates rate limit warning thresholds
    public func updateWarningThresholds(_ thresholds: RateLimitWarningThresholds) async {
        await rateLimitWarningSystem.updateThresholds(thresholds)
    }
    
    /// Gets rate limit enforcement settings
    public func getEnforcementSettings() -> RateLimitEnforcementSettings {
        return rateLimitEnforcer.getCurrentSettings()
    }
    
    /// Updates rate limit enforcement settings
    public func updateEnforcementSettings(_ settings: RateLimitEnforcementSettings) async {
        await rateLimitEnforcer.updateSettings(settings)
    }
    
    // MARK: - Rate Limit Subscription Methods
    
    /// Subscribe to rate limit status changes
    public func observeRateLimitStatus(_ handler: @escaping (Bool) -> Void) -> AnyCancellable {
        return rateLimitStatusPublisher
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to rate limit warnings
    public func observeRateLimitWarnings(_ handler: @escaping (RateLimitWarning) -> Void) -> AnyCancellable {
        return rateLimitWarningPublisher
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to usage threshold crossings
    public func observeUsageThresholds(_ thresholds: [UsageThreshold], handler: @escaping (UsageThresholdEvent) -> Void) -> AnyCancellable {
        return rateLimitThresholdMonitor.observeThresholds(thresholds, handler: handler)
    }
    
    /// Subscribe to rate limit window resets
    public func observeWindowResets(_ handler: @escaping (RateLimitWindowReset) -> Void) -> AnyCancellable {
        return windowResetPublisher
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to compliance status changes
    public func observeComplianceStatus(_ handler: @escaping (RateLimitComplianceStatus) -> Void) -> AnyCancellable {
        return complianceStatusPublisher
            .sink(receiveValue: handler)
    }
    
    /// Subscribe to rate limit utilization changes above threshold
    public func observeUtilizationThreshold(_ threshold: Double, handler: @escaping (Double) -> Void) -> AnyCancellable {
        return utilizationPublisher
            .filter { $0 >= threshold }
            .sink(receiveValue: handler)
    }
    
    // MARK: - Rate Limit Reporting and Analytics
    
    /// Generates rate limit usage report for a time period
    public func generateUsageReport(for period: ReportingTimePeriod) async -> RateLimitUsageReport {
        return await rateLimitReportGenerator.generateUsageReport(for: period)
    }
    
    /// Exports rate limit data for external analysis
    public func exportRateLimitData(format: ExportFormat) async -> RateLimitExportData {
        return await rateLimitDataExporter.exportData(format: format)
    }
    
    /// Gets rate limit efficiency metrics
    public func getRateLimitEfficiencyMetrics() async -> RateLimitEfficiencyMetrics {
        return await rateLimitEfficiencyAnalyzer.calculateEfficiencyMetrics()
    }
    
    /// Analyzes rate limit impact on user experience
    public func analyzeUserExperienceImpact() async -> UserExperienceImpactAnalysis {
        return await rateLimitUXAnalyzer.analyzeUserExperienceImpact()
    }
    
    /// Gets historical rate limit performance
    public func getHistoricalPerformance(for period: ReportingTimePeriod) async -> RateLimitHistoricalPerformance {
        return await rateLimitHistoricalAnalyzer.getPerformance(for: period)
    }
    
    /// Compares current usage to historical patterns
    public func compareToHistoricalUsage() async -> UsageComparisonAnalysis {
        return await rateLimitComparisonAnalyzer.compareToHistorical()
    }
    
    // MARK: - Rate Limit State Persistence
    
    /// Saves rate limit tracking state
    public func saveRateLimitState() async -> Bool {
        return await rateLimitStatePersistenceManager.saveState()
    }
    
    /// Restores rate limit tracking state
    public func restoreRateLimitState() async -> Bool {
        return await rateLimitStatePersistenceManager.restoreState()
    }
    
    /// Clears all rate limit tracking data
    public func clearRateLimitData() async -> Bool {
        return await rateLimitDataManager.clearAllData()
    }
    
    /// Gets size of stored rate limit data
    public func getRateLimitDataSize() async -> Int64 {
        return await rateLimitDataManager.getDataSize()
    }
    
    /// Validates integrity of stored rate limit data
    public func validateRateLimitDataIntegrity() async -> Bool {
        return await rateLimitDataManager.validateIntegrity()
    }
    
    /// Performs cleanup of old rate limit data
    public func cleanupOldData(retentionPeriod: TimeInterval) async -> Int {
        return await rateLimitDataManager.cleanupOldData(retentionPeriod: retentionPeriod)
    }
    
    // MARK: - Rate Limit Emergency and Recovery
    
    /// Handles rate limit emergency situations
    public func handleRateLimitEmergency(_ emergency: RateLimitEmergency) async -> EmergencyResponse {
        return await rateLimitEmergencyHandler.handleEmergency(emergency)
    }
    
    /// Attempts to recover from rate limit violations
    public func attemptRateLimitRecovery() async -> RateLimitRecoveryResult {
        return await rateLimitRecoveryManager.attemptRecovery()
    }
    
    /// Gets emergency contact options for rate limit issues
    public func getEmergencyOptions() -> [RateLimitEmergencyOption] {
        return rateLimitEmergencyHandler.getAvailableOptions()
    }
    
    /// Enables emergency mode with relaxed rate limiting
    public func enableEmergencyMode(duration: TimeInterval) async {
        await rateLimitEmergencyManager.enableEmergencyMode(duration: duration)
    }
    
    /// Disables emergency mode and returns to normal rate limiting
    public func disableEmergencyMode() async {
        await rateLimitEmergencyManager.disableEmergencyMode()
    }
    
    /// Checks if currently in emergency mode
    public func isInEmergencyMode() -> Bool {
        return rateLimitEmergencyManager.isEmergencyModeActive
    }
}

// MARK: - Private Rate Limit Coordination Components

extension AuthManager {
    
    /// Rate limit status tracker component
    private var rateLimitStatusTracker: RateLimitStatusTrackerComponent {
        return dependencies.rateLimitStatusTracker
    }
    
    /// Rate limit usage recorder component
    private var rateLimitUsageRecorder: RateLimitUsageRecorderComponent {
        return dependencies.rateLimitUsageRecorder
    }
    
    /// Rate limit compliance monitor component
    private var rateLimitComplianceMonitor: RateLimitComplianceMonitorComponent {
        return dependencies.rateLimitComplianceMonitor
    }
    
    /// Rate limit warning system component
    private var rateLimitWarningSystem: RateLimitWarningSystemComponent {
        return dependencies.rateLimitWarningSystem
    }
    
    /// Rate limit window manager component
    private var rateLimitWindowManager: RateLimitWindowManagerComponent {
        return dependencies.rateLimitWindowManager
    }
    
    /// Rate limit event coordinator component
    private var rateLimitEventCoordinator: RateLimitEventCoordinatorComponent {
        return dependencies.rateLimitEventCoordinator
    }
    
    /// Rate limit analyzer component
    private var rateLimitAnalyzer: RateLimitAnalyzerComponent {
        return dependencies.rateLimitAnalyzer
    }
    
    /// Rate limit trend analyzer component
    private var rateLimitTrendAnalyzer: RateLimitTrendAnalyzerComponent {
        return dependencies.rateLimitTrendAnalyzer
    }
    
    /// Rate limit post viability checker component
    private var rateLimitPostViabilityChecker: RateLimitPostViabilityCheckerComponent {
        return dependencies.rateLimitPostViabilityChecker
    }
    
    /// Rate limit timing optimizer component
    private var rateLimitTimingOptimizer: RateLimitTimingOptimizerComponent {
        return dependencies.rateLimitTimingOptimizer
    }
    
    /// Rate limit reset estimator component
    private var rateLimitResetEstimator: RateLimitResetEstimatorComponent {
        return dependencies.rateLimitResetEstimator
    }
    
    /// Rate limit prediction engine component
    private var rateLimitPredictionEngine: RateLimitPredictionEngineComponent {
        return dependencies.rateLimitPredictionEngine
    }
    
    /// Rate limit strategy advisor component
    private var rateLimitStrategyAdvisor: RateLimitStrategyAdvisorComponent {
        return dependencies.rateLimitStrategyAdvisor
    }
    
    /// Rate limit pattern analyzer component
    private var rateLimitPatternAnalyzer: RateLimitPatternAnalyzerComponent {
        return dependencies.rateLimitPatternAnalyzer
    }
    
    /// Rate limit preferences manager component
    private var rateLimitPreferencesManager: RateLimitPreferencesManagerComponent {
        return dependencies.rateLimitPreferencesManager
    }
    
    /// Rate limit enforcer component
    private var rateLimitEnforcer: RateLimitEnforcerComponent {
        return dependencies.rateLimitEnforcer
    }
    
    /// Rate limit threshold monitor component
    private var rateLimitThresholdMonitor: RateLimitThresholdMonitorComponent {
        return dependencies.rateLimitThresholdMonitor
    }
    
    /// Rate limit report generator component
    private var rateLimitReportGenerator: RateLimitReportGeneratorComponent {
        return dependencies.rateLimitReportGenerator
    }
    
    /// Rate limit data exporter component
    private var rateLimitDataExporter: RateLimitDataExporterComponent {
        return dependencies.rateLimitDataExporter
    }
    
    /// Rate limit efficiency analyzer component
    private var rateLimitEfficiencyAnalyzer: RateLimitEfficiencyAnalyzerComponent {
        return dependencies.rateLimitEfficiencyAnalyzer
    }
    
    /// Rate limit UX analyzer component
    private var rateLimitUXAnalyzer: RateLimitUXAnalyzerComponent {
        return dependencies.rateLimitUXAnalyzer
    }
    
    /// Rate limit historical analyzer component
    private var rateLimitHistoricalAnalyzer: RateLimitHistoricalAnalyzerComponent {
        return dependencies.rateLimitHistoricalAnalyzer
    }
    
    /// Rate limit comparison analyzer component
    private var rateLimitComparisonAnalyzer: RateLimitComparisonAnalyzerComponent {
        return dependencies.rateLimitComparisonAnalyzer
    }
    
    /// Rate limit state persistence manager component
    private var rateLimitStatePersistenceManager: RateLimitStatePersistenceManagerComponent {
        return dependencies.rateLimitStatePersistenceManager
    }
    
    /// Rate limit data manager component
    private var rateLimitDataManager: RateLimitDataManagerComponent {
        return dependencies.rateLimitDataManager
    }
    
    /// Rate limit emergency handler component
    private var rateLimitEmergencyHandler: RateLimitEmergencyHandlerComponent {
        return dependencies.rateLimitEmergencyHandler
    }
    
    /// Rate limit recovery manager component
    private var rateLimitRecoveryManager: RateLimitRecoveryManagerComponent {
        return dependencies.rateLimitRecoveryManager
    }
    
    /// Rate limit emergency manager component
    private var rateLimitEmergencyManager: RateLimitEmergencyManagerComponent {
        return dependencies.rateLimitEmergencyManager
    }
}

// MARK: - Rate Limit Component Protocols

/// Protocol for rate limit status tracker component
public protocol RateLimitStatusTrackerComponent {
    var monthlyUsagePublisher: AnyPublisher<MonthlyUsageInfo, Never> { get }
    var dailyUsagePublisher: AnyPublisher<DailyUsageInfo, Never> { get }
    var hourlyUsagePublisher: AnyPublisher<HourlyUsageInfo, Never> { get }
    
    func getCurrentMonthlyUsage() -> MonthlyUsageInfo
    func getCurrentDailyUsage() -> DailyUsageInfo
    func getCurrentHourlyUsage() -> HourlyUsageInfo
    func getCurrentWindowType() -> RateLimitWindowType
    func updateUsageStatistics() async
    func updateFailureStatistics(reason: PostFailureReason) async
    func recordAPIResponse(_ response: APIRateLimitResponse) async
    func syncWithRateLimitInfo(_ info: RateLimitInfo) async
    func refreshAllStatistics() async
    func applyPreferences(_ preferences: RateLimitMonitoringPreferences) async
}

/// Protocol for rate limit usage recorder component
public protocol RateLimitUsageRecorderComponent {
    func recordSuccessfulPost(postType: PostType, timestamp: Date, metadata: PostMetadata?) async
    func recordFailedPostAttempt(postType: PostType, failureReason: PostFailureReason, timestamp: Date, metadata: PostMetadata?) async
}

/// Protocol for rate limit compliance monitor component
public protocol RateLimitComplianceMonitorComponent {
    var complianceStatusPublisher: AnyPublisher<RateLimitComplianceStatus, Never> { get }
    
    func getCurrentComplianceStatus() -> RateLimitComplianceStatus
    func checkComplianceAfterPost() async
    func validateComplianceFromAPIResponse(_ response: APIRateLimitResponse) async
    func reevaluateCompliance() async
    func generateComplianceReport() async -> RateLimitComplianceReport
}

/// Protocol for rate limit warning system component
public protocol RateLimitWarningSystemComponent {
    var warningPublisher: AnyPublisher<RateLimitWarning, Never> { get }
    
    func getCurrentThresholds() -> RateLimitWarningThresholds
    func updateThresholds(_ thresholds: RateLimitWarningThresholds) async
}

/// Protocol for rate limit window manager component
public protocol RateLimitWindowManagerComponent {
    var windowResetPublisher: AnyPublisher<RateLimitWindowReset, Never> { get }
}

/// Protocol for rate limit event coordinator component
public protocol RateLimitEventCoordinatorComponent {
    var eventPublisher: AnyPublisher<RateLimitCoordinationEvent, Never> { get }
}

// MARK: - Additional Component Protocols

/// Protocol for rate limit analyzer component
public protocol RateLimitAnalyzerComponent {
    func generateUsageBreakdown(for period: UsageTimePeriod) async -> UsageBreakdown
}

/// Protocol for rate limit trend analyzer component
public protocol RateLimitTrendAnalyzerComponent {
    func generateTrendAnalysis() async -> UsageTrendAnalysis
}

/// Protocol for rate limit post viability checker component
public protocol RateLimitPostViabilityCheckerComponent {
    func checkPostViability(postType: PostType, scheduledTime: Date) async -> PostViabilityResult
}

/// Protocol for rate limit timing optimizer component
public protocol RateLimitTimingOptimizerComponent {
    func getOptimalTiming(for postType: PostType) async -> PostTimingRecommendation
}

/// Protocol for rate limit reset estimator component
public protocol RateLimitResetEstimatorComponent {
    func estimateReset(for operationType: RateLimitOperationType) async -> Date?
}

/// Protocol for rate limit prediction engine component
public protocol RateLimitPredictionEngineComponent {
    func predictUsage(for period: UsageTimePeriod) async -> UsagePrediction
    func updatePredictionModels() async
}

/// Protocol for rate limit strategy advisor component
public protocol RateLimitStrategyAdvisorComponent {
    func generatePostingStrategy() async -> PostingStrategyRecommendation
}

/// Protocol for rate limit pattern analyzer component
public protocol RateLimitPatternAnalyzerComponent {
    func analyzePatterns() async -> PostingPatternAnalysis
}

/// Protocol for rate limit preferences manager component
public protocol RateLimitPreferencesManagerComponent {
    func getCurrentPreferences() -> RateLimitMonitoringPreferences
    func updatePreferences(_ preferences: RateLimitMonitoringPreferences) async
}

/// Protocol for rate limit enforcer component
public protocol RateLimitEnforcerComponent {
    func getCurrentSettings() -> RateLimitEnforcementSettings
    func updateSettings(_ settings: RateLimitEnforcementSettings) async
}

/// Protocol for rate limit threshold monitor component
public protocol RateLimitThresholdMonitorComponent {
    func observeThresholds(_ thresholds: [UsageThreshold], handler: @escaping (UsageThresholdEvent) -> Void) -> AnyCancellable
}

/// Protocol for rate limit report generator component
public protocol RateLimitReportGeneratorComponent {
    func generateUsageReport(for period: ReportingTimePeriod) async -> RateLimitUsageReport
}

/// Protocol for rate limit data exporter component
public protocol RateLimitDataExporterComponent {
    func exportData(format: ExportFormat) async -> RateLimitExportData
}

/// Protocol for rate limit efficiency analyzer component
public protocol RateLimitEfficiencyAnalyzerComponent {
    func calculateEfficiencyMetrics() async -> RateLimitEfficiencyMetrics
}

/// Protocol for rate limit UX analyzer component
public protocol RateLimitUXAnalyzerComponent {
    func analyzeUserExperienceImpact() async -> UserExperienceImpactAnalysis
}

/// Protocol for rate limit historical analyzer component
public protocol RateLimitHistoricalAnalyzerComponent {
    func getPerformance(for period: ReportingTimePeriod) async -> RateLimitHistoricalPerformance
}

/// Protocol for rate limit comparison analyzer component
public protocol RateLimitComparisonAnalyzerComponent {
    func compareToHistorical() async -> UsageComparisonAnalysis
}

/// Protocol for rate limit state persistence manager component
public protocol RateLimitStatePersistenceManagerComponent {
    func saveState() async -> Bool
    func restoreState() async -> Bool
}

/// Protocol for rate limit data manager component
public protocol RateLimitDataManagerComponent {
    func clearAllData() async -> Bool
    func getDataSize() async -> Int64
    func validateIntegrity() async -> Bool
    func cleanupOldData(retentionPeriod: TimeInterval) async -> Int
}

/// Protocol for rate limit emergency handler component
public protocol RateLimitEmergencyHandlerComponent {
    func handleEmergency(_ emergency: RateLimitEmergency) async -> EmergencyResponse
    func getAvailableOptions() -> [RateLimitEmergencyOption]
}

/// Protocol for rate limit recovery manager component
public protocol RateLimitRecoveryManagerComponent {
    func attemptRecovery() async -> RateLimitRecoveryResult
}

/// Protocol for rate limit emergency manager component
public protocol RateLimitEmergencyManagerComponent {
    var isEmergencyModeActive: Bool { get }
    
    func enableEmergencyMode(duration: TimeInterval) async
    func disableEmergencyMode() async
}

// MARK: - Rate Limit Coordination Integration

extension AuthManager {
    
    /// Integrates rate limit status coordination with existing authentication operations
    internal func integrateRateLimitStatusCoordination() {
        // Integrate rate limit status changes with authentication event system
        rateLimitStatusPublisher
            .sink { [weak self] isLimited in
                self?.handleRateLimitStatusChange(isLimited)
            }
            .store(in: &cancellables)
        
        // Integrate rate limit warnings with error handling
        rateLimitWarningPublisher
            .sink { [weak self] warning in
                self?.handleRateLimitWarning(warning)
            }
            .store(in: &cancellables)
        
        // Integrate compliance status changes with error reporting
        complianceStatusPublisher
            .sink { [weak self] status in
                self?.handleComplianceStatusChange(status)
            }
            .store(in: &cancellables)
        
        // Integrate rate limit events with coordination system
        rateLimitEventPublisher
            .sink { [weak self] event in
                self?.handleRateLimitCoordinationEvent(event)
            }
            .store(in: &cancellables)
    }
    
    /// Handles rate limit status changes
    private func handleRateLimitStatusChange(_ isLimited: Bool) {
        if isLimited {
            // Rate limit hit - pause posting operations
            Task {
                await postQueueManager.pauseProcessing()
                await rateLimitEmergencyHandler.handleEmergency(.limitExceeded)
            }
        } else {
            // Rate limit cleared - resume posting operations
            Task {
                await postQueueManager.resumeProcessing()
            }
        }
        
        // Emit rate limit event
        let rateLimitEvent = RateLimitEvent.usageUpdated(currentRateLimitInfo)
        eventManager.publish(rateLimitEvent: rateLimitEvent)
    }
    
    /// Handles rate limit warnings
    private func handleRateLimitWarning(_ warning: RateLimitWarning) {
        // Emit warning event to the broader authentication system
        let rateLimitEvent = RateLimitEvent.warningTriggered(currentRateLimitInfo)
        eventManager.publish(rateLimitEvent: rateLimitEvent)
        
        // Adjust posting strategy based on warning type
        Task {
            switch warning.warningType {
            case .approachingLimit:
                await postQueueManager.enableConservativeMode()
            case .projectedOverage:
                await postQueueManager.enableEmergencyThrottling()
            case .unusualUsage:
                await rateLimitAnalyzer.investigateUnusualUsage()
            default:
                break
            }
        }
    }
    
    /// Handles compliance status changes
    private func handleComplianceStatusChange(_ status: RateLimitComplianceStatus) {
        switch status {
        case .compliant:
            // All good - normal operations
            break
        case .warning, .approaching:
            // Approaching limits - enable conservative mode
            Task {
                await postQueueManager.enableConservativeMode()
            }
        case .exceeded, .violation:
            // Limit exceeded - emergency mode
            Task {
                await rateLimitEmergencyHandler.handleEmergency(.complianceViolation)
                await postQueueManager.pauseProcessing()
            }
        }
    }
    
    /// Handles rate limit coordination events
    private func handleRateLimitCoordinationEvent(_ event: RateLimitCoordinationEvent) {
        // Emit appropriate authentication system events based on rate limit events
        switch event.eventType {
        case .limitExceeded:
            let rateLimitEvent = RateLimitEvent.limitExceeded(currentRateLimitInfo)
            eventManager.publish(rateLimitEvent: rateLimitEvent)
        case .windowReset:
            let rateLimitEvent = RateLimitEvent.limitReset(currentRateLimitInfo)
            eventManager.publish(rateLimitEvent: rateLimitEvent)
        case .emergencyActivated:
            // Handle emergency situations
            Task {
                await enableEmergencyMode(duration: 3600) // 1 hour emergency mode
            }
        default:
            break
        }
    }
}
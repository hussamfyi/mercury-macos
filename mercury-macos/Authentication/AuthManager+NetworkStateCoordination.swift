import Foundation
import Combine
import Network

/// Extension to AuthManager implementing NetworkStateCoordinationProtocol
/// This provides the core app with a clean interface for network state coordination
extension AuthManager: NetworkStateCoordinationProtocol {
    
    // MARK: - Network State Properties
    
    /// Current network connection state
    public var networkState: NetworkConnectionState {
        return networkMonitor.currentConnectionState
    }
    
    /// Current network connection quality
    public var connectionQuality: ConnectionQuality {
        return networkMonitor.currentConnectionQuality
    }
    
    /// Whether network is currently available for authentication operations
    public var isNetworkAvailableForAuth: Bool {
        return networkState.isAvailable && connectionQuality.qualityScore >= 0.5
    }
    
    /// Whether network is currently available for posting operations
    public var isNetworkAvailableForPosting: Bool {
        return networkState.isAvailable && connectionQuality.qualityScore >= 0.6
    }
    
    /// Current network interface type (WiFi, Cellular, etc.)
    public var networkInterfaceType: NetworkInterfaceType {
        return networkMonitor.currentInterfaceType
    }
    
    /// Estimated network latency in milliseconds
    public var estimatedLatency: TimeInterval? {
        return networkMonitor.currentLatency
    }
    
    /// Network usage statistics for authentication operations
    public var authNetworkUsage: NetworkUsageStats {
        return networkUsageTracker.getAuthenticationUsageStats()
    }
    
    // MARK: - Network State Publishers
    
    /// Publisher for network state changes
    public var networkStatePublisher: AnyPublisher<NetworkConnectionState, Never> {
        return networkMonitor.connectionStatePublisher
    }
    
    /// Publisher for connection quality changes
    public var connectionQualityPublisher: AnyPublisher<ConnectionQuality, Never> {
        return networkMonitor.connectionQualityPublisher
    }
    
    /// Publisher for network availability changes for authentication
    public var authNetworkAvailabilityPublisher: AnyPublisher<Bool, Never> {
        return Publishers.CombineLatest(networkStatePublisher, connectionQualityPublisher)
            .map { state, quality in
                return state.isAvailable && quality.qualityScore >= 0.5
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher for network availability changes for posting
    public var postNetworkAvailabilityPublisher: AnyPublisher<Bool, Never> {
        return Publishers.CombineLatest(networkStatePublisher, connectionQualityPublisher)
            .map { state, quality in
                return state.isAvailable && quality.qualityScore >= 0.6
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher for network interface type changes
    public var networkInterfacePublisher: AnyPublisher<NetworkInterfaceType, Never> {
        return networkMonitor.interfaceTypePublisher
    }
    
    /// Publisher for latency changes
    public var latencyPublisher: AnyPublisher<TimeInterval?, Never> {
        return networkMonitor.latencyPublisher
    }
    
    /// Publisher for network usage statistics updates
    public var networkUsagePublisher: AnyPublisher<NetworkUsageStats, Never> {
        return networkUsageTracker.usageStatsPublisher
    }
    
    /// Combined publisher for comprehensive network state monitoring
    public var combinedNetworkStatePublisher: AnyPublisher<NetworkStateSnapshot, Never> {
        return Publishers.CombineLatest4(
            networkStatePublisher,
            connectionQualityPublisher,
            networkInterfacePublisher,
            latencyPublisher
        )
        .map { [weak self] state, quality, interface, latency in
            return NetworkStateSnapshot(
                networkState: state,
                connectionQuality: quality,
                interfaceType: interface,
                estimatedLatency: latency,
                isAvailableForAuth: self?.isNetworkAvailableForAuth ?? false,
                isAvailableForPosting: self?.isNetworkAvailableForPosting ?? false
            )
        }
        .eraseToAnyPublisher()
    }
    
    /// Publisher for network events requiring attention
    public var networkEventPublisher: AnyPublisher<NetworkCoordinationEvent, Never> {
        return networkEventCoordinator.networkEventsPublisher
    }
    
    /// Publisher for network connectivity issues
    public var connectivityIssuePublisher: AnyPublisher<NetworkConnectivityIssue, Never> {
        return networkIssueDetector.connectivityIssuesPublisher
    }
    
    // MARK: - Network State Monitoring Methods
    
    /// Starts comprehensive network monitoring
    public func startNetworkMonitoring() async {
        await networkMonitor.startMonitoring()
        await networkUsageTracker.startTracking()
        await networkEventCoordinator.startCoordination()
        await networkIssueDetector.startDetection()
    }
    
    /// Stops network monitoring
    public func stopNetworkMonitoring() async {
        await networkMonitor.stopMonitoring()
        await networkUsageTracker.stopTracking()
        await networkEventCoordinator.stopCoordination()
        await networkIssueDetector.stopDetection()
    }
    
    /// Checks if network is available for a specific operation type
    public func isNetworkAvailable(for operationType: NetworkOperationType) async -> Bool {
        let conditions = await getCurrentNetworkConditions()
        return await networkOperationCoordinator.isOperationSupported(operationType, conditions: conditions)
    }
    
    /// Gets current network conditions for operation planning
    public func getCurrentNetworkConditions() async -> NetworkConditions {
        return await networkConditionsAnalyzer.getCurrentConditions()
    }
    
    /// Tests network connectivity with a lightweight probe
    public func testNetworkConnectivity() async -> NetworkConnectivityTestResult {
        return await networkConnectivityTester.performConnectivityTest()
    }
    
    /// Gets network quality metrics for the current connection
    public func getNetworkQualityMetrics() async -> NetworkQualityMetrics {
        return await networkQualityAnalyzer.getCurrentQualityMetrics()
    }
    
    /// Estimates operation success probability based on network conditions
    public func estimateOperationSuccessProbability(for operationType: NetworkOperationType) async -> Double {
        let conditions = await getCurrentNetworkConditions()
        return await networkOperationCoordinator.estimateSuccessProbability(for: operationType, conditions: conditions)
    }
    
    // MARK: - Network State Coordination Methods
    
    /// Coordinates authentication operations with network state
    public func coordinateAuthenticationOperation(_ operation: AuthenticationOperationType) async -> NetworkCoordinationResult {
        let conditions = await getCurrentNetworkConditions()
        return await networkOperationCoordinator.coordinateAuthentication(operation, conditions: conditions)
    }
    
    /// Coordinates posting operations with network state
    public func coordinatePostingOperation(_ operation: PostingOperationType) async -> NetworkCoordinationResult {
        let conditions = await getCurrentNetworkConditions()
        return await networkOperationCoordinator.coordinatePosting(operation, conditions: conditions)
    }
    
    /// Gets optimal timing for network-dependent operations
    public func getOptimalOperationTiming(for operationType: NetworkOperationType) async -> OperationTimingRecommendation {
        return await networkTimingOptimizer.getOptimalTiming(for: operationType)
    }
    
    /// Registers for network state change notifications
    public func observeNetworkStates(_ states: [NetworkConnectionState], handler: @escaping (NetworkConnectionState) -> Void) -> AnyCancellable {
        return networkStatePublisher
            .filter { states.contains($0) }
            .sink(receiveValue: handler)
    }
    
    /// Registers for connection quality change notifications
    public func observeConnectionQualities(_ qualities: [ConnectionQuality], handler: @escaping (ConnectionQuality) -> Void) -> AnyCancellable {
        return connectionQualityPublisher
            .filter { qualities.contains($0) }
            .sink(receiveValue: handler)
    }
    
    /// Registers for network availability notifications
    public func observeNetworkAvailability(for operationType: NetworkOperationType, handler: @escaping (Bool) -> Void) -> AnyCancellable {
        switch operationType {
        case .authentication, .tokenRefresh:
            return authNetworkAvailabilityPublisher
                .sink(receiveValue: handler)
        case .posting, .queueProcessing:
            return postNetworkAvailabilityPublisher
                .sink(receiveValue: handler)
        default:
            return authNetworkAvailabilityPublisher
                .sink(receiveValue: handler)
        }
    }
    
    // MARK: - Network Recovery and Retry Coordination
    
    /// Gets retry strategy for failed operations based on network conditions
    public func getRetryStrategy(for operationType: NetworkOperationType, failure: NetworkOperationFailure) async -> NetworkRetryStrategy {
        return await networkRetryCoordinator.getRetryStrategy(for: operationType, failure: failure)
    }
    
    /// Schedules operation retry when network conditions improve
    public func scheduleRetryOnNetworkImprovement(
        for operationType: NetworkOperationType,
        requiredConditions: NetworkConditions,
        handler: @escaping () -> Void
    ) -> AnyCancellable {
        return networkRetryScheduler.scheduleRetry(
            for: operationType,
            requiredConditions: requiredConditions,
            handler: handler
        )
    }
    
    /// Cancels all pending network-based retry schedules
    public func cancelAllRetrySchedules() {
        networkRetryScheduler.cancelAllSchedules()
    }
    
    /// Gets current retry schedules for monitoring
    public func getCurrentRetrySchedules() -> [NetworkRetrySchedule] {
        return networkRetryScheduler.getCurrentSchedules()
    }
    
    // MARK: - Network Usage Tracking
    
    /// Records network usage for an authentication operation
    public func recordAuthNetworkUsage(
        operationType: AuthenticationOperationType,
        bytesTransferred: Int64,
        duration: TimeInterval
    ) async {
        await networkUsageTracker.recordAuthenticationUsage(
            operationType: operationType,
            bytesTransferred: bytesTransferred,
            duration: duration
        )
    }
    
    /// Records network usage for a posting operation
    public func recordPostNetworkUsage(
        operationType: PostingOperationType,
        bytesTransferred: Int64,
        duration: TimeInterval
    ) async {
        await networkUsageTracker.recordPostingUsage(
            operationType: operationType,
            bytesTransferred: bytesTransferred,
            duration: duration
        )
    }
    
    /// Gets network usage statistics for a time period
    public func getNetworkUsageStatistics(for period: NetworkUsageTimePeriod) async -> NetworkUsageStats {
        return await networkUsageTracker.getUsageStatistics(for: period)
    }
    
    /// Resets network usage statistics
    public func resetNetworkUsageStatistics() async {
        await networkUsageTracker.resetStatistics()
    }
    
    /// Exports network usage data for analysis
    public func exportNetworkUsageData() async -> NetworkUsageExportData {
        return await networkUsageTracker.exportUsageData()
    }
    
    // MARK: - Network State Persistence
    
    /// Saves current network state configuration
    public func saveNetworkStateConfiguration() async -> Bool {
        return await networkConfigurationManager.saveConfiguration()
    }
    
    /// Restores network state configuration
    public func restoreNetworkStateConfiguration() async -> Bool {
        return await networkConfigurationManager.restoreConfiguration()
    }
    
    /// Gets network monitoring preferences
    public func getNetworkMonitoringPreferences() -> NetworkMonitoringPreferences {
        return networkPreferencesManager.getCurrentPreferences()
    }
    
    /// Updates network monitoring preferences
    public func updateNetworkMonitoringPreferences(_ preferences: NetworkMonitoringPreferences) async {
        await networkPreferencesManager.updatePreferences(preferences)
    }
    
    // MARK: - Network Diagnostics
    
    /// Runs comprehensive network diagnostics
    public func runNetworkDiagnostics() async -> NetworkDiagnosticResults {
        return await networkDiagnosticsRunner.runComprehensiveDiagnostics()
    }
    
    /// Gets network troubleshooting recommendations
    public func getNetworkTroubleshootingRecommendations(for issue: NetworkConnectivityIssue) async -> [NetworkTroubleshootingRecommendation] {
        return await networkTroubleshooter.getRecommendations(for: issue)
    }
    
    /// Tests specific network endpoints for connectivity
    public func testEndpointConnectivity(_ endpoints: [NetworkEndpoint]) async -> [EndpointConnectivityResult] {
        return await networkEndpointTester.testEndpoints(endpoints)
    }
    
    /// Measures network performance metrics
    public func measureNetworkPerformance() async -> NetworkPerformanceMetrics {
        return await networkPerformanceMeasurer.measureCurrentPerformance()
    }
    
    /// Gets network health score (0.0 to 1.0)
    public func getNetworkHealthScore() async -> Double {
        return await networkHealthCalculator.calculateHealthScore()
    }
}

// MARK: - Private Network Coordination Components

extension AuthManager {
    
    /// Network monitor component for basic connectivity tracking
    private var networkMonitor: NetworkMonitorComponent {
        return dependencies.networkMonitor
    }
    
    /// Network usage tracker component
    private var networkUsageTracker: NetworkUsageTrackerComponent {
        return dependencies.networkUsageTracker
    }
    
    /// Network event coordinator component
    private var networkEventCoordinator: NetworkEventCoordinatorComponent {
        return dependencies.networkEventCoordinator
    }
    
    /// Network issue detector component
    private var networkIssueDetector: NetworkIssueDetectorComponent {
        return dependencies.networkIssueDetector
    }
    
    /// Network conditions analyzer component
    private var networkConditionsAnalyzer: NetworkConditionsAnalyzerComponent {
        return dependencies.networkConditionsAnalyzer
    }
    
    /// Network connectivity tester component
    private var networkConnectivityTester: NetworkConnectivityTesterComponent {
        return dependencies.networkConnectivityTester
    }
    
    /// Network quality analyzer component
    private var networkQualityAnalyzer: NetworkQualityAnalyzerComponent {
        return dependencies.networkQualityAnalyzer
    }
    
    /// Network operation coordinator component
    private var networkOperationCoordinator: NetworkOperationCoordinatorComponent {
        return dependencies.networkOperationCoordinator
    }
    
    /// Network timing optimizer component
    private var networkTimingOptimizer: NetworkTimingOptimizerComponent {
        return dependencies.networkTimingOptimizer
    }
    
    /// Network retry coordinator component
    private var networkRetryCoordinator: NetworkRetryCoordinatorComponent {
        return dependencies.networkRetryCoordinator
    }
    
    /// Network retry scheduler component
    private var networkRetryScheduler: NetworkRetrySchedulerComponent {
        return dependencies.networkRetryScheduler
    }
    
    /// Network configuration manager component
    private var networkConfigurationManager: NetworkConfigurationManagerComponent {
        return dependencies.networkConfigurationManager
    }
    
    /// Network preferences manager component
    private var networkPreferencesManager: NetworkPreferencesManagerComponent {
        return dependencies.networkPreferencesManager
    }
    
    /// Network diagnostics runner component
    private var networkDiagnosticsRunner: NetworkDiagnosticsRunnerComponent {
        return dependencies.networkDiagnosticsRunner
    }
    
    /// Network troubleshooter component
    private var networkTroubleshooter: NetworkTroubleshooterComponent {
        return dependencies.networkTroubleshooter
    }
    
    /// Network endpoint tester component
    private var networkEndpointTester: NetworkEndpointTesterComponent {
        return dependencies.networkEndpointTester
    }
    
    /// Network performance measurer component
    private var networkPerformanceMeasurer: NetworkPerformanceMeasurerComponent {
        return dependencies.networkPerformanceMeasurer
    }
    
    /// Network health calculator component
    private var networkHealthCalculator: NetworkHealthCalculatorComponent {
        return dependencies.networkHealthCalculator
    }
}

// MARK: - Network Coordination Component Protocols

/// Protocol for network monitor component
public protocol NetworkMonitorComponent {
    var currentConnectionState: NetworkConnectionState { get }
    var currentConnectionQuality: ConnectionQuality { get }
    var currentInterfaceType: NetworkInterfaceType { get }
    var currentLatency: TimeInterval? { get }
    
    var connectionStatePublisher: AnyPublisher<NetworkConnectionState, Never> { get }
    var connectionQualityPublisher: AnyPublisher<ConnectionQuality, Never> { get }
    var interfaceTypePublisher: AnyPublisher<NetworkInterfaceType, Never> { get }
    var latencyPublisher: AnyPublisher<TimeInterval?, Never> { get }
    
    func startMonitoring() async
    func stopMonitoring() async
}

/// Protocol for network usage tracker component
public protocol NetworkUsageTrackerComponent {
    var usageStatsPublisher: AnyPublisher<NetworkUsageStats, Never> { get }
    
    func getAuthenticationUsageStats() -> NetworkUsageStats
    func startTracking() async
    func stopTracking() async
    func recordAuthenticationUsage(operationType: AuthenticationOperationType, bytesTransferred: Int64, duration: TimeInterval) async
    func recordPostingUsage(operationType: PostingOperationType, bytesTransferred: Int64, duration: TimeInterval) async
    func getUsageStatistics(for period: NetworkUsageTimePeriod) async -> NetworkUsageStats
    func resetStatistics() async
    func exportUsageData() async -> NetworkUsageExportData
}

/// Protocol for network event coordinator component
public protocol NetworkEventCoordinatorComponent {
    var networkEventsPublisher: AnyPublisher<NetworkCoordinationEvent, Never> { get }
    
    func startCoordination() async
    func stopCoordination() async
}

/// Protocol for network issue detector component
public protocol NetworkIssueDetectorComponent {
    var connectivityIssuesPublisher: AnyPublisher<NetworkConnectivityIssue, Never> { get }
    
    func startDetection() async
    func stopDetection() async
}

/// Protocol for network conditions analyzer component
public protocol NetworkConditionsAnalyzerComponent {
    func getCurrentConditions() async -> NetworkConditions
}

/// Protocol for network connectivity tester component
public protocol NetworkConnectivityTesterComponent {
    func performConnectivityTest() async -> NetworkConnectivityTestResult
}

/// Protocol for network quality analyzer component
public protocol NetworkQualityAnalyzerComponent {
    func getCurrentQualityMetrics() async -> NetworkQualityMetrics
}

/// Protocol for network operation coordinator component
public protocol NetworkOperationCoordinatorComponent {
    func isOperationSupported(_ operationType: NetworkOperationType, conditions: NetworkConditions) async -> Bool
    func estimateSuccessProbability(for operationType: NetworkOperationType, conditions: NetworkConditions) async -> Double
    func coordinateAuthentication(_ operation: AuthenticationOperationType, conditions: NetworkConditions) async -> NetworkCoordinationResult
    func coordinatePosting(_ operation: PostingOperationType, conditions: NetworkConditions) async -> NetworkCoordinationResult
}

/// Protocol for network timing optimizer component
public protocol NetworkTimingOptimizerComponent {
    func getOptimalTiming(for operationType: NetworkOperationType) async -> OperationTimingRecommendation
}

/// Protocol for network retry coordinator component
public protocol NetworkRetryCoordinatorComponent {
    func getRetryStrategy(for operationType: NetworkOperationType, failure: NetworkOperationFailure) async -> NetworkRetryStrategy
}

/// Protocol for network retry scheduler component
public protocol NetworkRetrySchedulerComponent {
    func scheduleRetry(for operationType: NetworkOperationType, requiredConditions: NetworkConditions, handler: @escaping () -> Void) -> AnyCancellable
    func cancelAllSchedules()
    func getCurrentSchedules() -> [NetworkRetrySchedule]
}

/// Protocol for network configuration manager component
public protocol NetworkConfigurationManagerComponent {
    func saveConfiguration() async -> Bool
    func restoreConfiguration() async -> Bool
}

/// Protocol for network preferences manager component
public protocol NetworkPreferencesManagerComponent {
    func getCurrentPreferences() -> NetworkMonitoringPreferences
    func updatePreferences(_ preferences: NetworkMonitoringPreferences) async
}

/// Protocol for network diagnostics runner component
public protocol NetworkDiagnosticsRunnerComponent {
    func runComprehensiveDiagnostics() async -> NetworkDiagnosticResults
}

/// Protocol for network troubleshooter component
public protocol NetworkTroubleshooterComponent {
    func getRecommendations(for issue: NetworkConnectivityIssue) async -> [NetworkTroubleshootingRecommendation]
}

/// Protocol for network endpoint tester component
public protocol NetworkEndpointTesterComponent {
    func testEndpoints(_ endpoints: [NetworkEndpoint]) async -> [EndpointConnectivityResult]
}

/// Protocol for network performance measurer component
public protocol NetworkPerformanceMeasurerComponent {
    func measureCurrentPerformance() async -> NetworkPerformanceMetrics
}

/// Protocol for network health calculator component
public protocol NetworkHealthCalculatorComponent {
    func calculateHealthScore() async -> Double
}

// MARK: - Network Coordination Helper Extensions

extension AuthManager {
    
    /// Maps internal network monitor to NetworkConnectionState
    private func mapNetworkState(_ state: NetworkConnectionState) -> NetworkConnectionState {
        // Map from internal network state to protocol state
        return state
    }
    
    /// Maps internal connection quality to ConnectionQuality
    private func mapConnectionQuality(_ quality: ConnectionQuality) -> ConnectionQuality {
        // Map from internal quality to protocol quality
        return quality
    }
    
    /// Maps internal interface type to NetworkInterfaceType
    private func mapInterfaceType(_ type: NetworkInterfaceType) -> NetworkInterfaceType {
        // Map from internal interface type to protocol type
        return type
    }
    
    /// Creates a network coordination event for operation coordination
    private func createNetworkCoordinationEvent(
        type: NetworkEventType,
        operation: NetworkOperationType,
        recommendations: [String]
    ) -> NetworkCoordinationEvent {
        return NetworkCoordinationEvent(
            eventType: type,
            networkState: networkState,
            affectedOperations: [operation],
            recommendations: recommendations
        )
    }
    
    /// Creates a network connectivity issue for error reporting
    private func createNetworkConnectivityIssue(
        type: ConnectivityIssueType,
        severity: ConnectivityIssueSeverity,
        description: String,
        operations: [NetworkOperationType]
    ) -> NetworkConnectivityIssue {
        return NetworkConnectivityIssue(
            issueType: type,
            severity: severity,
            description: description,
            affectedOperations: operations
        )
    }
}

// MARK: - Network State Coordination Integration

extension AuthManager {
    
    /// Integrates network state coordination with existing authentication operations
    internal func integrateNetworkCoordination() {
        // Integrate network state changes with authentication state management
        networkStatePublisher
            .sink { [weak self] networkState in
                self?.handleNetworkStateChange(networkState)
            }
            .store(in: &cancellables)
        
        // Integrate connection quality changes with operation coordination
        connectionQualityPublisher
            .sink { [weak self] quality in
                self?.handleConnectionQualityChange(quality)
            }
            .store(in: &cancellables)
        
        // Integrate network events with authentication event system
        networkEventPublisher
            .sink { [weak self] event in
                self?.handleNetworkCoordinationEvent(event)
            }
            .store(in: &cancellables)
        
        // Integrate connectivity issues with error handling
        connectivityIssuePublisher
            .sink { [weak self] issue in
                self?.handleConnectivityIssue(issue)
            }
            .store(in: &cancellables)
    }
    
    /// Handles network state changes for authentication coordination
    private func handleNetworkStateChange(_ newState: NetworkConnectionState) {
        switch newState {
        case .connected:
            // Network connected - resume operations if needed
            Task {
                await resumeNetworkDependentOperations()
            }
        case .disconnected:
            // Network disconnected - pause operations and queue
            Task {
                await pauseNetworkDependentOperations()
            }
        case .unstable:
            // Unstable connection - adjust retry strategies
            Task {
                await adjustForUnstableConnection()
            }
        default:
            break
        }
    }
    
    /// Handles connection quality changes for operation optimization
    private func handleConnectionQualityChange(_ newQuality: ConnectionQuality) {
        switch newQuality {
        case .excellent, .good:
            // Good quality - increase operation frequency
            Task {
                await optimizeForGoodConnection()
            }
        case .poor:
            // Poor quality - reduce operation frequency
            Task {
                await optimizeForPoorConnection()
            }
        default:
            break
        }
    }
    
    /// Handles network coordination events
    private func handleNetworkCoordinationEvent(_ event: NetworkCoordinationEvent) {
        // Publish event to the broader authentication system
        eventManager.publish(networkEvent: NetworkEvent.operationRetried(operation: event.eventType.description, attempt: 1))
    }
    
    /// Handles connectivity issues
    private func handleConnectivityIssue(_ issue: NetworkConnectivityIssue) {
        // Create appropriate error events based on the connectivity issue
        switch issue.severity {
        case .critical:
            // Critical issues require immediate attention
            Task {
                await handleCriticalConnectivityIssue(issue)
            }
        case .high:
            // High severity issues may impact operations
            Task {
                await handleHighSeverityConnectivityIssue(issue)
            }
        default:
            // Lower severity issues are logged but don't interrupt operations
            break
        }
    }
    
    /// Resumes network-dependent operations when connectivity is restored
    private func resumeNetworkDependentOperations() async {
        // Resume token refresh if needed
        await tokenRefreshManager.resumeBackgroundRefresh()
        
        // Resume queue processing
        await postQueueManager.resumeProcessing()
        
        // Emit network restored event
        eventManager.publish(networkEvent: .connectionEstablished)
    }
    
    /// Pauses network-dependent operations when connectivity is lost
    private func pauseNetworkDependentOperations() async {
        // Pause token refresh to avoid errors
        await tokenRefreshManager.pauseBackgroundRefresh()
        
        // Pause queue processing
        await postQueueManager.pauseProcessing()
        
        // Emit network lost event
        eventManager.publish(networkEvent: .connectionLost)
    }
    
    /// Adjusts operations for unstable connection
    private func adjustForUnstableConnection() async {
        // Increase retry delays for unstable connections
        await postQueueManager.adjustRetryStrategy(for: .unstableConnection)
        
        // Reduce token refresh frequency
        await tokenRefreshManager.adjustRefreshFrequency(for: .unstableConnection)
    }
    
    /// Optimizes operations for good connection quality
    private func optimizeForGoodConnection() async {
        // Increase operation frequency for good connections
        await postQueueManager.optimizeForGoodConnection()
        
        // Resume normal token refresh frequency
        await tokenRefreshManager.optimizeForGoodConnection()
    }
    
    /// Optimizes operations for poor connection quality
    private func optimizeForPoorConnection() async {
        // Reduce operation frequency for poor connections
        await postQueueManager.optimizeForPoorConnection()
        
        // Increase token refresh buffer time
        await tokenRefreshManager.optimizeForPoorConnection()
    }
    
    /// Handles critical connectivity issues
    private func handleCriticalConnectivityIssue(_ issue: NetworkConnectivityIssue) async {
        // Stop all network operations for critical issues
        await pauseNetworkDependentOperations()
        
        // Create critical error event
        let errorEvent = AuthenticationError.networkError(issue.description)
        eventManager.publish(authenticationEvent: .authenticationFailed(errorEvent))
    }
    
    /// Handles high severity connectivity issues
    private func handleHighSeverityConnectivityIssue(_ issue: NetworkConnectivityIssue) async {
        // Adjust operation strategies for high severity issues
        await adjustForUnstableConnection()
        
        // Create warning event
        eventManager.publish(networkEvent: .connectionQualityChanged(.poor))
    }
}
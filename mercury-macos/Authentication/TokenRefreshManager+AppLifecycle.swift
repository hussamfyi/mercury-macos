import Foundation
import Combine

/// Extension to TokenRefreshManager adding app lifecycle coordination capabilities
public extension TokenRefreshManager {
    
    // MARK: - App Lifecycle Coordination Methods
    
    /// Checks if token refresh should be postponed due to app lifecycle constraints
    /// - Parameter operationType: Type of operation requesting refresh
    /// - Returns: True if refresh should be postponed
    func shouldPostponeRefresh(for operationType: AppLifecycleOperationType = .automatic) -> Bool {
        // During app termination, avoid starting new refresh operations
        if let appState = getAppLifecycleState(), appState == .terminating {
            print("🛑 Postponing refresh - app is terminating")
            return true
        }
        
        // For manual operations, allow during most states
        if operationType == .manual {
            return false
        }
        
        // For emergency operations, only postpone during termination
        if operationType == .emergency {
            return getAppLifecycleState() == .terminating
        }
        
        // For automatic operations, check various constraints
        return shouldPostponeAutomaticRefresh()
    }
    
    /// Checks if automatic refresh should be postponed
    /// - Returns: True if automatic refresh should be postponed
    private func shouldPostponeAutomaticRefresh() -> Bool {
        guard let appState = getAppLifecycleState() else { return false }
        
        switch appState {
        case .terminating:
            return true
        case .sleeping:
            // Allow refresh during sleep if network is available
            return !isNetworkAvailableForRefresh()
        case .background:
            // Allow background refresh with constraints
            return !canPerformBackgroundRefresh()
        case .active, .inactive:
            return false
        }
    }
    
    /// Checks if background refresh is allowed based on current constraints
    /// - Returns: True if background refresh can proceed
    private func canPerformBackgroundRefresh() -> Bool {
        // Check if we're within the background time limit
        guard let coordinator = getAppLifecycleCoordinator(),
              let timeInBackground = coordinator.getTimeInBackground() else {
            return true // If no coordinator, allow refresh
        }
        
        // Limit background operations to 10 minutes
        let maxBackgroundTime: TimeInterval = 10 * 60
        
        if timeInBackground > maxBackgroundTime {
            print("⏰ Background refresh not allowed - exceeded time limit (\(String(format: "%.1f", timeInBackground))s > \(String(format: "%.1f", maxBackgroundTime))s)")
            return false
        }
        
        return true
    }
    
    /// Checks if network is available for refresh operations
    /// - Returns: True if network allows refresh
    private func isNetworkAvailableForRefresh() -> Bool {
        // Use existing network monitor if available
        if let networkMonitor = getNetworkMonitor() {
            return networkMonitor.isConnected && networkMonitor.shouldAttemptOperation(.tokenRefresh)
        }
        
        return true // Assume available if no monitor
    }
    
    /// Schedules refresh to occur when app lifecycle state allows it
    /// - Parameter reason: Reason for the deferred refresh
    func scheduleRefreshWhenAppStateAllows(reason: String) {
        print("📅 Scheduling deferred refresh when app state allows: \(reason)")
        
        guard let coordinator = getAppLifecycleCoordinator() else {
            // No coordinator available, attempt immediate refresh
            Task {
                await self.checkAndRefreshToken()
            }
            return
        }
        
        // Add operation to be executed when app returns to foreground
        coordinator.addPendingForegroundOperation { [weak self] in
            print("🔄 Executing deferred refresh: \(reason)")
            await self?.checkAndRefreshToken()
        }
    }
    
    /// Adapts refresh strategy based on current app lifecycle state
    /// - Returns: Configuration for refresh operation
    func getRefreshStrategyForCurrentState() -> RefreshStrategy {
        guard let appState = getAppLifecycleState() else {
            return .normal
        }
        
        switch appState {
        case .active:
            return .normal
        case .inactive:
            return .conservative
        case .background:
            return .background
        case .sleeping:
            return .minimal
        case .terminating:
            return .disabled
        }
    }
    
    /// Updates refresh timing based on app lifecycle events
    /// - Parameter event: The lifecycle event that occurred
    func handleAppLifecycleEvent(_ event: AppLifecycleEvent) {
        Task {
            switch event {
            case .didBecomeActive:
                await handleAppBecameActive()
            case .didResignActive:
                await handleAppResignedActive()
            case .didEnterBackground:
                await handleAppEnteredBackground()
            case .willEnterForeground:
                await handleAppWillEnterForeground()
            case .willTerminate:
                await handleAppWillTerminate()
            case .systemDidSleep:
                await handleSystemSleep()
            case .systemDidWake:
                await handleSystemWake()
            }
        }
    }
    
    /// Configures refresh behavior for background operation
    func configureForBackgroundOperation() {
        print("🌅 Configuring TokenRefreshManager for background operation")
        
        // Pause the regular timer to save battery
        pauseRefreshTimer()
        
        // Store current state for restoration
        UserDefaults.standard.set(true, forKey: "mercury.auth.was_backgrounded")
        UserDefaults.standard.set(Date(), forKey: "mercury.auth.background_time")
    }
    
    /// Configures refresh behavior for foreground operation
    func configureForForegroundOperation() {
        print("🌄 Configuring TokenRefreshManager for foreground operation")
        
        // Resume normal timer
        resumeRefreshTimer()
        
        // Check if immediate refresh is needed
        if shouldCheckAfterBackground() {
            forceRefreshCheck()
        }
        
        // Clear background state
        UserDefaults.standard.removeObject(forKey: "mercury.auth.was_backgrounded")
        UserDefaults.standard.removeObject(forKey: "mercury.auth.background_time")
    }
    
    /// Checks if refresh check is needed after returning from background
    /// - Returns: True if refresh check should be performed
    private func shouldCheckAfterBackground() -> Bool {
        guard UserDefaults.standard.bool(forKey: "mercury.auth.was_backgrounded"),
              let backgroundTime = UserDefaults.standard.object(forKey: "mercury.auth.background_time") as? Date else {
            return false
        }
        
        let timeInBackground = Date().timeIntervalSince(backgroundTime)
        
        // Check after 1 minute in background
        return timeInBackground > 60
    }
    
    // MARK: - Private Lifecycle Event Handlers
    
    private func handleAppBecameActive() async {
        print("🌟 TokenRefreshManager: App became active")
        configureForForegroundOperation()
    }
    
    private func handleAppResignedActive() async {
        print("⏸️ TokenRefreshManager: App resigned active")
        // Don't change configuration for brief inactivity
    }
    
    private func handleAppEnteredBackground() async {
        print("🌅 TokenRefreshManager: App entered background")
        configureForBackgroundOperation()
    }
    
    private func handleAppWillEnterForeground() async {
        print("🌄 TokenRefreshManager: App will enter foreground")
        // Prepare for foreground restore
    }
    
    private func handleAppWillTerminate() async {
        print("🛑 TokenRefreshManager: App will terminate")
        stopRefresh()
    }
    
    private func handleSystemSleep() async {
        print("💤 TokenRefreshManager: System sleeping")
        pauseRefreshTimer()
    }
    
    private func handleSystemWake() async {
        print("⏰ TokenRefreshManager: System waking")
        resumeRefreshTimer()
        forceRefreshCheck()
    }
    
    // MARK: - Helper Methods
    
    /// Gets the current app lifecycle coordinator (requires injection)
    private func getAppLifecycleCoordinator() -> AppLifecycleCoordinator? {
        // This would need to be injected during initialization
        // For now, we'll use a static reference approach
        return AppLifecycleCoordinator.shared
    }
    
    /// Gets the current app lifecycle state
    private func getAppLifecycleState() -> AppLifecycleState? {
        return getAppLifecycleCoordinator()?.appState
    }
    
    /// Gets the network monitor for connectivity checks
    private func getNetworkMonitor() -> NetworkMonitor? {
        // This is already available as a property in TokenRefreshManager
        return networkMonitor
    }
}

// MARK: - Supporting Types

/// Types of refresh operations for lifecycle coordination
public enum AppLifecycleOperationType {
    case automatic   // Regular scheduled refresh
    case manual      // User-initiated refresh
    case emergency   // Critical refresh (token about to expire)
    case background  // Background refresh
}

/// Refresh strategies based on app lifecycle state
public enum RefreshStrategy {
    case normal      // Full refresh capabilities
    case conservative // Reduced refresh frequency
    case background  // Background-optimized refresh
    case minimal     // Only critical refreshes
    case disabled    // No refresh operations
    
    /// Maximum retry attempts for this strategy
    public var maxRetryAttempts: Int {
        switch self {
        case .normal:
            return 5
        case .conservative:
            return 3
        case .background:
            return 2
        case .minimal:
            return 1
        case .disabled:
            return 0
        }
    }
    
    /// Timeout interval for operations in this strategy
    public var timeoutInterval: TimeInterval {
        switch self {
        case .normal:
            return 30.0
        case .conservative:
            return 20.0
        case .background:
            return 15.0
        case .minimal:
            return 10.0
        case .disabled:
            return 5.0
        }
    }
    
    /// Whether this strategy allows network operations
    public var allowsNetworkOperations: Bool {
        switch self {
        case .disabled:
            return false
        default:
            return true
        }
    }
}

/// App lifecycle events that affect token refresh
public enum AppLifecycleEvent {
    case didBecomeActive
    case didResignActive
    case didEnterBackground
    case willEnterForeground
    case willTerminate
    case systemDidSleep
    case systemDidWake
}

// MARK: - Shared Instance Support

extension AppLifecycleCoordinator {
    /// Shared instance for use across the app (temporary approach)
    /// In production, this should be properly injected
    static var shared: AppLifecycleCoordinator = AppLifecycleCoordinator()
}
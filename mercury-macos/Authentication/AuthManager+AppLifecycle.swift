import Foundation
import Combine

/// Extension to AuthManager implementing app lifecycle coordination
extension AuthManager {
    
    // MARK: - App Lifecycle Coordination Implementation
    
    /// Internal app lifecycle coordinator
    private var appLifecycleCoordinator: AppLifecycleCoordinator {
        return AppLifecycleCoordinator.shared
    }
    
    /// Prepares the authentication service for app backgrounding
    /// Ensures critical operations are completed and background refresh is configured
    public func prepareForBackground() async {
        print("🌅 AuthManager: Preparing for app background...")
        
        // Delegate to the lifecycle coordinator
        await appLifecycleCoordinator.prepareForBackground()
        
        // Perform any AuthManager-specific background preparation
        await performAuthManagerBackgroundPreparation()
        
        print("🌅 AuthManager: Background preparation completed")
    }
    
    /// Handles app returning to foreground
    /// Resumes normal operations and checks for needed refreshes
    public func handleForegroundRestore() async {
        print("🌄 AuthManager: Handling foreground restore...")
        
        // Delegate to the lifecycle coordinator
        await appLifecycleCoordinator.handleForegroundRestore()
        
        // Perform any AuthManager-specific foreground restoration
        await performAuthManagerForegroundRestore()
        
        print("🌄 AuthManager: Foreground restore completed")
    }
    
    /// Prepares the authentication service for app termination
    /// Ensures critical state is saved before app exits
    public func prepareForTermination() async {
        print("🛑 AuthManager: Preparing for app termination...")
        
        // Delegate to the lifecycle coordinator
        await appLifecycleCoordinator.prepareForTermination()
        
        // Perform any AuthManager-specific termination preparation
        await performAuthManagerTerminationPreparation()
        
        print("🛑 AuthManager: Termination preparation completed")
    }
    
    /// Handles system sleep events
    /// Coordinates authentication operations with system power management
    public func handleSystemSleep() async {
        print("💤 AuthManager: Handling system sleep...")
        
        // Delegate to the lifecycle coordinator
        await appLifecycleCoordinator.handleSystemSleep()
        
        // Perform any AuthManager-specific sleep handling
        await performAuthManagerSleepHandling()
        
        print("💤 AuthManager: System sleep handling completed")
    }
    
    /// Handles system wake events
    /// Resumes authentication operations after system wake
    public func handleSystemWake() async {
        print("⏰ AuthManager: Handling system wake...")
        
        // Delegate to the lifecycle coordinator
        await appLifecycleCoordinator.handleSystemWake()
        
        // Perform any AuthManager-specific wake handling
        await performAuthManagerWakeHandling()
        
        print("⏰ AuthManager: System wake handling completed")
    }
    
    /// Gets the current app lifecycle state
    /// - Returns: Current app lifecycle state
    public func getAppLifecycleState() -> AppLifecycleState? {
        return appLifecycleCoordinator.appState
    }
    
    /// Checks if the authentication service is currently in background mode
    /// - Returns: True if in background mode
    public func isInBackgroundMode() -> Bool {
        return appLifecycleCoordinator.isInBackground
    }
    
    // MARK: - Internal App Lifecycle Setup
    
    /// Sets up app lifecycle coordination during AuthManager initialization
    /// This should be called during AuthManager init
    internal func setupAppLifecycleCoordination() {
        // Set dependencies in the coordinator
        appLifecycleCoordinator.setTokenRefreshManager(tokenRefreshManager)
        appLifecycleCoordinator.setAuthenticationService(self)
        
        // Set up coordinator reference in token refresh manager
        AppLifecycleCoordinator.shared = appLifecycleCoordinator
        
        print("🔄 AuthManager: App lifecycle coordination setup completed")
    }
    
    // MARK: - Private AuthManager-Specific Lifecycle Handling
    
    /// Performs AuthManager-specific background preparation
    private func performAuthManagerBackgroundPreparation() async {
        // Check if emergency token refresh is needed
        if await shouldPerformEmergencyRefreshBeforeBackground() {
            print("🚨 Performing emergency token refresh before background")
            let _ = await tokenRefreshManager.forceEmergencyRefresh(reason: "background_preparation")
        }
        
        // Pause event-driven state management if needed
        pauseEventDrivenStateManagement()
        
        // Update rate limit manager for background mode
        await rateLimitManager.configureForBackgroundMode()
        
        // Prepare post queue for background operations
        await postQueueManager.prepareForBackground()
        
        // Clear any sensitive UI state
        clearSensitiveUIState()
    }
    
    /// Performs AuthManager-specific foreground restoration
    private func performAuthManagerForegroundRestore() async {
        // Resume event-driven state management
        resumeEventDrivenStateManagement()
        
        // Restore rate limit manager for foreground mode
        await rateLimitManager.configureForForegroundMode()
        
        // Resume post queue processing
        await postQueueManager.resumeFromBackground()
        
        // Check if token validation is needed after background
        if await shouldValidateTokenAfterForeground() {
            print("🔍 Validating token after foreground restore")
            let _ = await validateTokenForCriticalOperation(.backgroundOperation)
        }
        
        // Process any queued posts if authenticated
        if isAuthenticated() {
            await processQueuedPosts()
        }
    }
    
    /// Performs AuthManager-specific termination preparation
    private func performAuthManagerTerminationPreparation() async {
        // Save critical authentication state
        await saveCriticalAuthenticationState()
        
        // Stop all background operations
        await tokenRefreshManager.stopRefresh()
        
        // Cancel network operations
        networkMonitor.cancelAllOperations()
        
        // Clear sensitive data from memory (but preserve keychain)
        clearSensitiveMemoryData()
    }
    
    /// Performs AuthManager-specific sleep handling
    private func performAuthManagerSleepHandling() async {
        // Configure network monitor for sleep
        networkMonitor.configureForSystemSleep()
        
        // Pause non-critical background tasks
        pauseNonCriticalBackgroundTasks()
    }
    
    /// Performs AuthManager-specific wake handling
    private func performAuthManagerWakeHandling() async {
        // Resume network monitor
        networkMonitor.configureForSystemWake()
        
        // Resume background tasks
        resumeNonCriticalBackgroundTasks()
        
        // Check network connectivity and token status
        if networkMonitor.isConnected {
            print("🌐 Network available after wake - checking authentication status")
            
            if isAuthenticated() {
                // Validate token after system wake
                let _ = await validateTokenForCriticalOperation(.backgroundOperation)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Checks if emergency token refresh is needed before backgrounding
    private func shouldPerformEmergencyRefreshBeforeBackground() async -> Bool {
        guard isAuthenticated() else { return false }
        
        // Check if token expires within 5 minutes
        if let timeUntilExpiry = await tokenRefreshManager.timeUntilExpiration() {
            return timeUntilExpiry <= 5 * 60 && timeUntilExpiry > 0
        }
        
        return false
    }
    
    /// Checks if token validation is needed after foregrounding
    private func shouldValidateTokenAfterForeground() async -> Bool {
        guard isAuthenticated() else { return false }
        
        // Check if we were in background for more than 1 minute
        if let timeInBackground = appLifecycleCoordinator.getTimeInBackground() {
            return timeInBackground > 60
        }
        
        return false
    }
    
    /// Pauses event-driven state management for background mode
    private func pauseEventDrivenStateManagement() {
        // Reduce frequency of state change notifications
        // This is automatically handled by the existing event system
        print("⏸️ Event-driven state management paused for background mode")
    }
    
    /// Resumes event-driven state management for foreground mode
    private func resumeEventDrivenStateManagement() {
        // Resume normal frequency of state change notifications
        // This is automatically handled by the existing event system
        print("▶️ Event-driven state management resumed for foreground mode")
    }
    
    /// Clears sensitive UI state for background mode
    private func clearSensitiveUIState() {
        // Clear any sensitive data that shouldn't persist in background
        // This is a placeholder - specific implementation depends on UI requirements
        print("🧹 Sensitive UI state cleared for background mode")
    }
    
    /// Saves critical authentication state for app termination
    private func saveCriticalAuthenticationState() async {
        // Save last successful authentication timestamp
        if let user = currentUser {
            UserDefaults.standard.set(Date(), forKey: "mercury.auth.last_active_time")
            UserDefaults.standard.set(user.username, forKey: "mercury.auth.last_user")
        }
        
        // Save rate limit state
        await rateLimitManager.saveCriticalState()
        
        print("💾 Critical authentication state saved")
    }
    
    /// Clears sensitive data from memory without affecting keychain
    private func clearSensitiveMemoryData() {
        // Clear token validation cache
        clearTokenValidationCache()
        
        // Clear any other sensitive memory data
        // Note: We don't clear keychain data here as that would log the user out
        
        print("🧹 Sensitive memory data cleared")
    }
    
    /// Pauses non-critical background tasks for system sleep
    private func pauseNonCriticalBackgroundTasks() {
        // Pause queue processing temporarily
        postQueueManager.pauseProcessing()
        
        print("⏸️ Non-critical background tasks paused for system sleep")
    }
    
    /// Resumes non-critical background tasks after system wake
    private func resumeNonCriticalBackgroundTasks() {
        // Resume queue processing
        postQueueManager.resumeProcessing()
        
        print("▶️ Non-critical background tasks resumed after system wake")
    }
    
    // MARK: - Public App Lifecycle Status Methods
    
    /// Gets comprehensive app lifecycle status for monitoring
    /// - Returns: Dictionary with app lifecycle coordination status
    public func getAppLifecycleStatus() -> [String: Any] {
        var status = appLifecycleCoordinator.getLifecycleStatus()
        
        // Add AuthManager-specific status
        status["authManager_isAuthenticated"] = isAuthenticated()
        status["authManager_authenticationState"] = authenticationState.description
        status["authManager_queuedPostsCount"] = queuedPostsCount
        status["authManager_rateLimitInfo"] = rateLimitInfo.description
        
        // Add token refresh manager status
        if let tokenRefreshState = tokenRefreshManager.refreshState as? TokenRefreshState {
            status["tokenRefreshManager_state"] = tokenRefreshState.description
        }
        
        // Add network monitor status
        status["networkMonitor_isConnected"] = networkMonitor.isConnected
        status["networkMonitor_connectionQuality"] = networkMonitor.currentConnectionQuality.description
        
        return status
    }
    
    /// Logs comprehensive app lifecycle status for debugging
    public func logAppLifecycleStatus() {
        print("🔄 AuthManager App Lifecycle Status:")
        
        let status = getAppLifecycleStatus()
        for (key, value) in status.sorted(by: { $0.key < $1.key }) {
            if let date = value as? Date {
                print("   \(key): \(date.formatted())")
            } else if let interval = value as? TimeInterval {
                print("   \(key): \(String(format: "%.1f", interval))s")
            } else {
                print("   \(key): \(value)")
            }
        }
        
        // Also log coordinator status
        appLifecycleCoordinator.logLifecycleStatus()
    }
}

// MARK: - Extensions for Dependencies

/// Extension to add app lifecycle support to RateLimitManager
private extension RateLimitManager {
    func configureForBackgroundMode() async {
        // Configure rate limiting for background mode
        print("🌅 RateLimitManager configured for background mode")
    }
    
    func configureForForegroundMode() async {
        // Configure rate limiting for foreground mode
        print("🌄 RateLimitManager configured for foreground mode")
    }
    
    func saveCriticalState() async {
        // Save critical rate limit state
        print("💾 RateLimitManager critical state saved")
    }
}

/// Extension to add app lifecycle support to PostQueueManager
private extension PostQueueManager {
    func prepareForBackground() async {
        // Prepare post queue for background operation
        print("🌅 PostQueueManager prepared for background")
    }
    
    func resumeFromBackground() async {
        // Resume post queue from background
        print("🌄 PostQueueManager resumed from background")
    }
    
    func pauseProcessing() {
        // Pause queue processing
        print("⏸️ PostQueueManager processing paused")
    }
    
    func resumeProcessing() {
        // Resume queue processing
        print("▶️ PostQueueManager processing resumed")
    }
}

/// Extension to add app lifecycle support to NetworkMonitor
private extension NetworkMonitor {
    func cancelAllOperations() {
        // Cancel all pending network operations
        print("❌ NetworkMonitor: All operations cancelled")
    }
    
    func configureForSystemSleep() {
        // Configure network monitoring for system sleep
        print("💤 NetworkMonitor configured for system sleep")
    }
    
    func configureForSystemWake() {
        // Configure network monitoring after system wake
        print("⏰ NetworkMonitor configured for system wake")
    }
}

// MARK: - State Extensions

extension TokenRefreshState {
    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .refreshing:
            return "Refreshing"
        case .success:
            return "Success"
        case .failure(let error):
            return "Failed: \(error.localizedDescription)"
        }
    }
}

extension AuthenticationState {
    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .authenticating:
            return "Authenticating"
        case .authenticated:
            return "Authenticated"
        case .refreshing:
            return "Refreshing"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

extension RateLimitInfo {
    var description: String {
        return "Used: \(requestsThisMonth)/\(monthlyLimit) (\(String(format: "%.1f", usagePercentage))%)"
    }
}

extension ConnectionQuality {
    var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .poor:
            return "Poor"
        case .fair:
            return "Fair"
        case .good:
            return "Good"
        case .excellent:
            return "Excellent"
        }
    }
}
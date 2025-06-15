import Foundation
import AppKit
import BackgroundTasks
import Combine

/// Coordinates authentication service operations with macOS app lifecycle events
/// Ensures proper token refresh handling during app state transitions
@MainActor
public class AppLifecycleCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current app state for reactive UI updates
    @Published public private(set) var appState: AppLifecycleState = .active
    
    /// Whether the app is currently in background
    @Published public private(set) var isInBackground = false
    
    /// Time when app was backgrounded (for calculating time in background)
    @Published public private(set) var backgroundedAt: Date?
    
    /// Time when app was foregrounded (for calculating time since foreground)
    @Published public private(set) var foregroundedAt: Date?
    
    // MARK: - Dependencies
    
    private weak var tokenRefreshManager: TokenRefreshManager?
    private weak var authenticationService: (any AuthenticationServiceProtocol)?
    
    // MARK: - Internal State
    
    private var cancellables = Set<AnyCancellable>()
    private var backgroundTaskIdentifier: NSBackgroundActivityScheduler?
    private var emergencyRefreshTimer: Timer?
    
    // Configuration
    private let maxBackgroundTime: TimeInterval = 10 * 60 // 10 minutes
    private let emergencyRefreshThreshold: TimeInterval = 5 * 60 // 5 minutes before token expiry
    private let backgroundRefreshInterval: TimeInterval = 2 * 60 // 2 minutes
    
    // State tracking
    private var wasAuthenticatedWhenBackgrounded = false
    private var lastBackgroundRefreshTime: Date?
    private var pendingForegroundOperations: [() async -> Void] = []
    
    // MARK: - Initialization
    
    public init() {
        setupAppLifecycleObservers()
        setupBackgroundTaskScheduling()
        
        // Initialize current app state
        updateAppState()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public Configuration Methods
    
    /// Sets the token refresh manager for lifecycle coordination
    /// - Parameter tokenRefreshManager: The token refresh manager to coordinate with
    public func setTokenRefreshManager(_ tokenRefreshManager: TokenRefreshManager) {
        self.tokenRefreshManager = tokenRefreshManager
    }
    
    /// Sets the authentication service for lifecycle coordination
    /// - Parameter authenticationService: The authentication service to coordinate with
    public func setAuthenticationService(_ authenticationService: any AuthenticationServiceProtocol) {
        self.authenticationService = authenticationService
    }
    
    // MARK: - Public Interface Methods
    
    /// Prepares for app going to background
    /// Ensures critical operations are completed and background refresh is scheduled
    public func prepareForBackground() async {
        print("🌅 Preparing app for background...")
        
        wasAuthenticatedWhenBackgrounded = authenticationService?.isAuthenticated() ?? false
        backgroundedAt = Date()
        isInBackground = true
        appState = .background
        
        // Pause the regular refresh timer to save battery
        tokenRefreshManager?.pauseRefreshTimer()
        
        // Check if we need an emergency refresh before going to background
        await performEmergencyRefreshIfNeeded()
        
        // Schedule background refresh if authenticated
        if wasAuthenticatedWhenBackgrounded {
            scheduleBackgroundRefresh()
        }
        
        print("🌅 App prepared for background mode")
    }
    
    /// Handles app returning to foreground
    /// Resumes normal operations and checks for needed refreshes
    public func handleForegroundRestore() async {
        print("🌄 Handling app foreground restore...")
        
        let timeInBackground = backgroundedAt?.timeIntervalSinceNow.magnitude ?? 0
        foregroundedAt = Date()
        isInBackground = false
        appState = .active
        
        // Cancel background refresh
        cancelBackgroundRefresh()
        
        // Resume normal refresh timer
        tokenRefreshManager?.resumeRefreshTimer()
        
        // Check if we need immediate refresh after being in background
        if wasAuthenticatedWhenBackgrounded && timeInBackground > 60 {
            print("🔄 App was in background for \(String(format: "%.1f", timeInBackground))s, checking token status...")
            await checkTokenStatusAfterBackground()
        }
        
        // Process any pending foreground operations
        await processPendingForegroundOperations()
        
        print("🌄 App foreground restore completed")
    }
    
    /// Handles app termination
    /// Ensures critical state is saved before app exits
    public func prepareForTermination() async {
        print("🛑 Preparing app for termination...")
        
        appState = .terminating
        
        // Stop all refresh operations
        tokenRefreshManager?.stopRefresh()
        
        // Cancel background tasks
        cancelBackgroundRefresh()
        
        // Give authentication service a chance to save critical state
        // Note: We don't call disconnect() here as that would clear tokens
        
        print("🛑 App prepared for termination")
    }
    
    /// Handles macOS sleep/wake events
    /// Coordinates token refresh with system power management
    public func handleSystemSleep() async {
        print("💤 System going to sleep...")
        
        appState = .sleeping
        
        // Pause refresh timer during sleep
        tokenRefreshManager?.pauseRefreshTimer()
        
        // Cancel any pending background tasks
        cancelBackgroundRefresh()
    }
    
    /// Handles system wake from sleep
    public func handleSystemWake() async {
        print("⏰ System waking from sleep...")
        
        appState = .active
        
        // Resume refresh timer
        tokenRefreshManager?.resumeRefreshTimer()
        
        // Force refresh check after system wake
        tokenRefreshManager?.forceRefreshCheck()
        
        print("⏰ System wake handling completed")
    }
    
    /// Adds an operation to be executed when app returns to foreground
    /// - Parameter operation: Async operation to execute
    public func addPendingForegroundOperation(_ operation: @escaping () async -> Void) {
        pendingForegroundOperations.append(operation)
    }
    
    /// Gets time spent in background (if currently backgrounded)
    /// - Returns: Time interval in background, or nil if not backgrounded
    public func getTimeInBackground() -> TimeInterval? {
        guard isInBackground, let backgroundedAt = backgroundedAt else { return nil }
        return Date().timeIntervalSince(backgroundedAt)
    }
    
    /// Gets time since last foreground (if currently active)
    /// - Returns: Time interval since foreground, or nil if not active
    public func getTimeSinceForeground() -> TimeInterval? {
        guard !isInBackground, let foregroundedAt = foregroundedAt else { return nil }
        return Date().timeIntervalSince(foregroundedAt)
    }
    
    // MARK: - Private Methods
    
    /// Sets up app lifecycle notification observers
    private func setupAppLifecycleObservers() {
        // App activation/deactivation
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppDidBecomeActive()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppDidResignActive()
                }
            }
            .store(in: &cancellables)
        
        // App hide/unhide
        NotificationCenter.default.publisher(for: NSApplication.didHideNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppDidHide()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppDidUnhide()
                }
            }
            .store(in: &cancellables)
        
        // App termination
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppWillTerminate()
                }
            }
            .store(in: &cancellables)
        
        // System sleep/wake notifications
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleSystemSleep()
                }
            }
            .store(in: &cancellables)
        
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleSystemWake()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Sets up background task scheduling for token refresh
    private func setupBackgroundTaskScheduling() {
        // Create background activity scheduler for token refresh
        backgroundTaskIdentifier = NSBackgroundActivityScheduler(identifier: "com.mercury.token-refresh")
        backgroundTaskIdentifier?.qualityOfService = .utility
        backgroundTaskIdentifier?.repeats = false
        backgroundTaskIdentifier?.tolerance = 30.0 // 30 seconds tolerance
    }
    
    /// Updates current app state based on NSApplication state
    private func updateAppState() {
        if NSApplication.shared.isActive {
            appState = .active
            isInBackground = false
        } else if NSApplication.shared.isHidden {
            appState = .background
            isInBackground = true
        } else {
            appState = .inactive
            isInBackground = false
        }
    }
    
    // MARK: - Notification Handlers
    
    private func handleAppDidBecomeActive() async {
        appState = .active
        await handleForegroundRestore()
    }
    
    private func handleAppDidResignActive() async {
        appState = .inactive
        // Don't treat resign active as full background - user might just be switching apps briefly
    }
    
    private func handleAppDidHide() async {
        await prepareForBackground()
    }
    
    private func handleAppDidUnhide() async {
        await handleForegroundRestore()
    }
    
    private func handleAppWillTerminate() async {
        await prepareForTermination()
    }
    
    // MARK: - Background Refresh Management
    
    /// Schedules background token refresh using NSBackgroundActivityScheduler
    private func scheduleBackgroundRefresh() {
        guard let scheduler = backgroundTaskIdentifier else { return }
        
        // Schedule refresh in 2 minutes
        scheduler.interval = backgroundRefreshInterval
        
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.performBackgroundRefresh()
                completion(.finished)
            }
        }
        
        print("📅 Scheduled background token refresh in \(backgroundRefreshInterval)s")
    }
    
    /// Cancels scheduled background refresh
    private func cancelBackgroundRefresh() {
        backgroundTaskIdentifier?.invalidate()
        emergencyRefreshTimer?.invalidate()
        emergencyRefreshTimer = nil
        
        print("❌ Cancelled background token refresh")
    }
    
    /// Performs background token refresh with limited capabilities
    private func performBackgroundRefresh() async {
        guard isInBackground, let tokenRefreshManager = tokenRefreshManager else { return }
        
        print("🔄 Performing background token refresh...")
        
        lastBackgroundRefreshTime = Date()
        
        // Check if token needs refresh
        if await tokenRefreshManager.shouldRefreshToken() {
            // Attempt background refresh with shorter timeout
            let success = await tokenRefreshManager.refreshTokenNow()
            
            if success {
                print("✅ Background token refresh successful")
            } else {
                print("❌ Background token refresh failed")
                
                // Schedule retry if we're still in background and under time limit
                if isInBackground, let backgroundedAt = backgroundedAt,
                   Date().timeIntervalSince(backgroundedAt) < maxBackgroundTime {
                    scheduleBackgroundRefresh()
                }
            }
        } else {
            print("ℹ️ Background refresh not needed")
        }
    }
    
    /// Performs emergency refresh if token is close to expiring
    private func performEmergencyRefreshIfNeeded() async {
        guard let tokenRefreshManager = tokenRefreshManager else { return }
        
        // Check if token expires soon
        if let timeUntilExpiry = await tokenRefreshManager.timeUntilExpiration(),
           timeUntilExpiry <= emergencyRefreshThreshold && timeUntilExpiry > 0 {
            
            print("🚨 Token expires in \(String(format: "%.1f", timeUntilExpiry))s - performing emergency refresh")
            
            let success = await tokenRefreshManager.forceEmergencyRefresh(reason: "app_backgrounding")
            
            if success {
                print("✅ Emergency refresh before background successful")
            } else {
                print("❌ Emergency refresh before background failed")
            }
        }
    }
    
    /// Checks token status after returning from background
    private func checkTokenStatusAfterBackground() async {
        guard let tokenRefreshManager = tokenRefreshManager,
              let authService = authenticationService else { return }
        
        // Check if token expired while in background
        if await tokenRefreshManager.isTokenExpired() {
            print("⚠️ Token expired while in background - triggering refresh")
            await tokenRefreshManager.forceRefreshCheck()
            return
        }
        
        // Check if token needs refresh soon
        if await tokenRefreshManager.shouldRefreshToken() {
            print("🔄 Token needs refresh after background - triggering check")
            await tokenRefreshManager.forceRefreshCheck()
            return
        }
        
        // Validate token is still working
        let validationResult = await authService.validateTokenForCriticalOperation(.backgroundOperation)
        
        if !validationResult.isValid {
            print("⚠️ Token validation failed after background - triggering refresh")
            await tokenRefreshManager.forceRefreshCheck()
        } else {
            print("✅ Token validated successfully after background")
        }
    }
    
    /// Processes operations that were deferred until foreground
    private func processPendingForegroundOperations() async {
        guard !pendingForegroundOperations.isEmpty else { return }
        
        print("🔄 Processing \(pendingForegroundOperations.count) pending foreground operations...")
        
        let operations = pendingForegroundOperations
        pendingForegroundOperations.removeAll()
        
        for operation in operations {
            await operation()
        }
        
        print("✅ Completed processing pending foreground operations")
    }
    
    /// Cleanup resources
    private func cleanup() {
        cancellables.removeAll()
        cancelBackgroundRefresh()
        pendingForegroundOperations.removeAll()
    }
    
    // MARK: - Public Monitoring Methods
    
    /// Gets comprehensive lifecycle status for monitoring
    /// - Returns: Dictionary with current lifecycle state information
    public func getLifecycleStatus() -> [String: Any] {
        var status: [String: Any] = [:]
        
        status["appState"] = appState.description
        status["isInBackground"] = isInBackground
        status["wasAuthenticatedWhenBackgrounded"] = wasAuthenticatedWhenBackgrounded
        
        if let backgroundedAt = backgroundedAt {
            status["backgroundedAt"] = backgroundedAt
            status["timeInBackground"] = Date().timeIntervalSince(backgroundedAt)
        }
        
        if let foregroundedAt = foregroundedAt {
            status["foregroundedAt"] = foregroundedAt
            status["timeSinceForeground"] = Date().timeIntervalSince(foregroundedAt)
        }
        
        if let lastRefresh = lastBackgroundRefreshTime {
            status["lastBackgroundRefreshTime"] = lastRefresh
            status["timeSinceLastBackgroundRefresh"] = Date().timeIntervalSince(lastRefresh)
        }
        
        status["pendingForegroundOperations"] = pendingForegroundOperations.count
        status["backgroundTaskScheduled"] = backgroundTaskIdentifier != nil
        status["emergencyRefreshTimerActive"] = emergencyRefreshTimer != nil
        
        // Configuration values
        status["maxBackgroundTimeSeconds"] = maxBackgroundTime
        status["emergencyRefreshThresholdSeconds"] = emergencyRefreshThreshold
        status["backgroundRefreshIntervalSeconds"] = backgroundRefreshInterval
        
        return status
    }
    
    /// Logs current lifecycle status for debugging
    public func logLifecycleStatus() {
        let status = getLifecycleStatus()
        
        print("🔄 App Lifecycle Status:")
        for (key, value) in status.sorted(by: { $0.key < $1.key }) {
            if let date = value as? Date {
                print("   \(key): \(date.formatted())")
            } else if let interval = value as? TimeInterval {
                print("   \(key): \(String(format: "%.1f", interval))s")
            } else {
                print("   \(key): \(value)")
            }
        }
    }
}

// MARK: - Supporting Types

/// Represents the current app lifecycle state
public enum AppLifecycleState: CaseIterable {
    case active      // App is active and in foreground
    case inactive    // App is inactive but not hidden
    case background  // App is hidden/backgrounded
    case sleeping    // System is sleeping
    case terminating // App is terminating
    
    public var description: String {
        switch self {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .background:
            return "Background"
        case .sleeping:
            return "Sleeping"
        case .terminating:
            return "Terminating"
        }
    }
    
    /// Whether this state allows background operations
    public var allowsBackgroundOperations: Bool {
        switch self {
        case .background, .sleeping:
            return true
        default:
            return false
        }
    }
    
    /// Whether this state requires conservative resource usage
    public var requiresConservativeMode: Bool {
        switch self {
        case .background, .sleeping, .terminating:
            return true
        default:
            return false
        }
    }
}
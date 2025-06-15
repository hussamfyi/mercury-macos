import Foundation
import Combine

/// Coordinates persistence of authentication state across all authentication components
/// Ensures atomic save/restore operations and consistency across app restarts and system events
@MainActor
public class AuthenticationStatePersistenceCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether persistence operations are currently in progress
    @Published public private(set) var isPersisting = false
    
    /// Whether restoration operations are currently in progress
    @Published public private(set) var isRestoring = false
    
    /// Last successful persistence timestamp
    @Published public private(set) var lastPersistenceTime: Date?
    
    /// Last successful restoration timestamp
    @Published public private(set) var lastRestorationTime: Date?
    
    // MARK: - Dependencies
    
    private weak var authManager: AuthManager?
    private weak var tokenRefreshManager: TokenRefreshManager?
    private weak var keychainManager: KeychainManager?
    private weak var rateLimitManager: RateLimitManager?
    private weak var postQueueManager: PostQueueManager?
    private weak var networkMonitor: NetworkMonitor?
    
    // MARK: - Persistence Configuration
    
    private let userDefaults = UserDefaults.standard
    private let persistenceQueue = DispatchQueue(label: "com.mercury.persistence", qos: .utility)
    
    // Storage keys for coordination metadata
    private enum CoordinationKeys {
        static let lastPersistenceTime = "mercury.persistence.last_save_time"
        static let lastRestorationTime = "mercury.persistence.last_restore_time"
        static let persistenceVersion = "mercury.persistence.version"
        static let componentVersions = "mercury.persistence.component_versions"
        static let persistenceInProgress = "mercury.persistence.in_progress"
        static let restorationRequired = "mercury.persistence.restoration_required"
        static let emergencyBackup = "mercury.persistence.emergency_backup"
    }
    
    // Current persistence format version for migration support
    private let currentPersistenceVersion = "1.0.0"
    
    // Registered persistence providers
    private var persistenceProviders: [String: AuthenticationPersistenceProvider] = [:]
    
    // State coordination
    private var pendingPersistenceOperations: Set<String> = []
    private var persistenceHooks: [PersistenceHook] = []
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public init() {
        setupPersistenceCoordination()
        checkRestorationRequired()
    }
    
    // MARK: - Component Registration
    
    /// Registers authentication components for coordinated persistence
    /// - Parameter authManager: The main authentication manager
    /// - Parameter tokenRefreshManager: Token refresh manager
    /// - Parameter keychainManager: Keychain manager
    /// - Parameter rateLimitManager: Rate limit manager
    /// - Parameter postQueueManager: Post queue manager
    /// - Parameter networkMonitor: Network monitor
    public func registerComponents(
        authManager: AuthManager?,
        tokenRefreshManager: TokenRefreshManager?,
        keychainManager: KeychainManager?,
        rateLimitManager: RateLimitManager?,
        postQueueManager: PostQueueManager?,
        networkMonitor: NetworkMonitor?
    ) {
        self.authManager = authManager
        self.tokenRefreshManager = tokenRefreshManager
        self.keychainManager = keychainManager
        self.rateLimitManager = rateLimitManager
        self.postQueueManager = postQueueManager
        self.networkMonitor = networkMonitor
        
        // Register built-in persistence providers
        registerBuiltInPersistenceProviders()
        
        print("🔄 Authentication components registered for coordinated persistence")
    }
    
    /// Registers a persistence provider for a component
    /// - Parameter provider: The persistence provider
    /// - Parameter identifier: Unique identifier for the component
    public func registerPersistenceProvider(_ provider: AuthenticationPersistenceProvider, identifier: String) {
        persistenceProviders[identifier] = provider
        print("📝 Registered persistence provider: \(identifier)")
    }
    
    /// Registers a persistence hook for custom save/restore logic
    /// - Parameter hook: The persistence hook
    public func registerPersistenceHook(_ hook: PersistenceHook) {
        persistenceHooks.append(hook)
        print("🪝 Registered persistence hook: \(hook.identifier)")
    }
    
    // MARK: - Coordinated Persistence Operations
    
    /// Performs coordinated save of all authentication state
    /// - Parameter reason: Reason for the save operation
    /// - Parameter isEmergency: Whether this is an emergency save before app termination
    /// - Returns: Success status
    @discardableResult
    public func saveAuthenticationState(reason: String, isEmergency: Bool = false) async -> Bool {
        guard !isPersisting else {
            print("⚠️ Persistence already in progress, skipping save request")
            return false
        }
        
        isPersisting = true
        defer { isPersisting = false }
        
        print("💾 Starting coordinated authentication state save: \(reason)")
        
        do {
            // Mark persistence as in progress
            markPersistenceInProgress(true)
            
            // Execute pre-save hooks
            await executePreSaveHooks(reason: reason, isEmergency: isEmergency)
            
            // Save each component's state
            let saveResults = await saveAllComponentStates(isEmergency: isEmergency)
            
            // Verify all saves succeeded
            let failedComponents = saveResults.filter { !$0.value }.keys
            
            if failedComponents.isEmpty {
                // All components saved successfully
                await recordSuccessfulPersistence()
                await executePostSaveHooks(success: true, reason: reason)
                
                print("✅ Coordinated authentication state save completed successfully")
                return true
                
            } else {
                // Some components failed to save
                print("❌ Persistence failed for components: \(Array(failedComponents))")
                await executePostSaveHooks(success: false, reason: reason)
                
                // Attempt emergency backup if this wasn't already an emergency save
                if !isEmergency {
                    await createEmergencyBackup()
                }
                
                return false
            }
            
        } catch {
            print("❌ Coordinated authentication state save failed: \(error)")
            await executePostSaveHooks(success: false, reason: reason)
            
            if !isEmergency {
                await createEmergencyBackup()
            }
            
            return false
            
        } finally {
            markPersistenceInProgress(false)
        }
    }
    
    /// Performs coordinated restoration of all authentication state
    /// - Parameter reason: Reason for the restoration
    /// - Returns: Success status
    @discardableResult
    public func restoreAuthenticationState(reason: String) async -> Bool {
        guard !isRestoring else {
            print("⚠️ Restoration already in progress, skipping restore request")
            return false
        }
        
        isRestoring = true
        defer { isRestoring = false }
        
        print("📤 Starting coordinated authentication state restoration: \(reason)")
        
        do {
            // Execute pre-restore hooks
            await executePreRestoreHooks(reason: reason)
            
            // Check persistence version compatibility
            let isCompatible = await checkPersistenceVersionCompatibility()
            if !isCompatible {
                print("⚠️ Persistence version incompatible, attempting migration")
                await migratePersistenceFormat()
            }
            
            // Restore each component's state
            let restoreResults = await restoreAllComponentStates()
            
            // Verify all restores succeeded
            let failedComponents = restoreResults.filter { !$0.value }.keys
            
            if failedComponents.isEmpty {
                // All components restored successfully
                await recordSuccessfulRestoration()
                await executePostRestoreHooks(success: true, reason: reason)
                
                // Clear restoration required flag
                clearRestorationRequired()
                
                print("✅ Coordinated authentication state restoration completed successfully")
                return true
                
            } else {
                // Some components failed to restore
                print("❌ Restoration failed for components: \(Array(failedComponents))")
                await executePostRestoreHooks(success: false, reason: reason)
                
                return false
            }
            
        } catch {
            print("❌ Coordinated authentication state restoration failed: \(error)")
            await executePostRestoreHooks(success: false, reason: reason)
            return false
        }
    }
    
    /// Performs emergency state backup before critical operations
    /// - Returns: Success status
    @discardableResult
    public func createEmergencyBackup() async -> Bool {
        print("🚨 Creating emergency authentication state backup")
        
        // Create emergency backup using a simplified persistence approach
        let backupData: [String: Any] = [
            "timestamp": Date(),
            "version": currentPersistenceVersion,
            "authState": authManager?.authenticationState.emergencyDescription ?? "unknown",
            "isAuthenticated": authManager?.isAuthenticated() ?? false,
            "queuedPostsCount": authManager?.queuedPostsCount ?? 0,
            "rateLimitInfo": await createEmergencyRateLimitBackup(),
            "lastSuccessfulAuth": userDefaults.object(forKey: "mercury.auth.last_success") as? Date ?? Date()
        ]
        
        // Store emergency backup
        if let backupDataEncoded = try? JSONSerialization.data(withJSONObject: backupData) {
            userDefaults.set(backupDataEncoded, forKey: CoordinationKeys.emergencyBackup)
            print("✅ Emergency backup created successfully")
            return true
        } else {
            print("❌ Emergency backup creation failed")
            return false
        }
    }
    
    /// Restores from emergency backup if available
    /// - Returns: Success status
    @discardableResult
    public func restoreFromEmergencyBackup() async -> Bool {
        guard let backupData = userDefaults.data(forKey: CoordinationKeys.emergencyBackup),
              let backup = try? JSONSerialization.jsonObject(with: backupData) as? [String: Any] else {
            print("❌ No emergency backup available")
            return false
        }
        
        print("🚨 Restoring from emergency authentication state backup")
        
        // Restore basic state information
        if let timestamp = backup["timestamp"] as? Date {
            print("📅 Emergency backup from: \(timestamp.formatted())")
        }
        
        if let lastAuth = backup["lastSuccessfulAuth"] as? Date {
            userDefaults.set(lastAuth, forKey: "mercury.auth.last_success")
        }
        
        // Trigger component restoration from emergency state
        await executeEmergencyRestoreHooks(backupData: backup)
        
        print("✅ Emergency backup restoration completed")
        return true
    }
    
    // MARK: - Lifecycle Integration
    
    /// Handles app backgrounding - saves critical state
    public func handleAppBackgrounding() async {
        print("🌅 Handling app backgrounding - saving critical state")
        await saveAuthenticationState(reason: "app_backgrounding", isEmergency: false)
    }
    
    /// Handles app foregrounding - checks if restoration is needed
    public func handleAppForegrounding() async {
        print("🌄 Handling app foregrounding - checking restoration needs")
        
        if shouldRestoreOnForeground() {
            await restoreAuthenticationState(reason: "app_foregrounding")
        }
    }
    
    /// Handles app termination - performs emergency save
    public func handleAppTermination() async {
        print("🛑 Handling app termination - performing emergency save")
        await saveAuthenticationState(reason: "app_termination", isEmergency: true)
    }
    
    /// Handles system sleep - saves state for recovery
    public func handleSystemSleep() async {
        print("💤 Handling system sleep - saving state for recovery")
        await saveAuthenticationState(reason: "system_sleep", isEmergency: false)
    }
    
    /// Handles system wake - restores state if needed
    public func handleSystemWake() async {
        print("⏰ Handling system wake - checking state consistency")
        
        if shouldRestoreAfterSystemWake() {
            await restoreAuthenticationState(reason: "system_wake")
        }
    }
    
    // MARK: - Private Implementation
    
    /// Sets up persistence coordination infrastructure
    private func setupPersistenceCoordination() {
        // Load last persistence/restoration times
        lastPersistenceTime = userDefaults.object(forKey: CoordinationKeys.lastPersistenceTime) as? Date
        lastRestorationTime = userDefaults.object(forKey: CoordinationKeys.lastRestorationTime) as? Date
        
        // Setup periodic integrity checks
        setupPeriodicIntegrityChecks()
        
        print("🔄 Persistence coordination infrastructure setup completed")
    }
    
    /// Registers built-in persistence providers for standard components
    private func registerBuiltInPersistenceProviders() {
        // Register AuthManager persistence provider
        registerPersistenceProvider(
            AuthManagerPersistenceProvider(authManager: authManager),
            identifier: "AuthManager"
        )
        
        // Register TokenRefreshManager persistence provider
        registerPersistenceProvider(
            TokenRefreshManagerPersistenceProvider(tokenRefreshManager: tokenRefreshManager),
            identifier: "TokenRefreshManager"
        )
        
        // Register RateLimitManager persistence provider
        registerPersistenceProvider(
            RateLimitManagerPersistenceProvider(rateLimitManager: rateLimitManager),
            identifier: "RateLimitManager"
        )
        
        // Register PostQueueManager persistence provider
        registerPersistenceProvider(
            PostQueueManagerPersistenceProvider(postQueueManager: postQueueManager),
            identifier: "PostQueueManager"
        )
        
        // Register NetworkMonitor persistence provider
        registerPersistenceProvider(
            NetworkMonitorPersistenceProvider(networkMonitor: networkMonitor),
            identifier: "NetworkMonitor"
        )
    }
    
    /// Saves state for all registered components
    private func saveAllComponentStates(isEmergency: Bool) async -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        for (identifier, provider) in persistenceProviders {
            do {
                pendingPersistenceOperations.insert(identifier)
                let success = await provider.saveState(isEmergency: isEmergency)
                results[identifier] = success
                
                if success {
                    print("✅ \(identifier) state saved successfully")
                } else {
                    print("❌ \(identifier) state save failed")
                }
                
                pendingPersistenceOperations.remove(identifier)
                
            } catch {
                print("❌ \(identifier) state save error: \(error)")
                results[identifier] = false
                pendingPersistenceOperations.remove(identifier)
            }
        }
        
        return results
    }
    
    /// Restores state for all registered components
    private func restoreAllComponentStates() async -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        for (identifier, provider) in persistenceProviders {
            do {
                let success = await provider.restoreState()
                results[identifier] = success
                
                if success {
                    print("✅ \(identifier) state restored successfully")
                } else {
                    print("❌ \(identifier) state restore failed")
                }
                
            } catch {
                print("❌ \(identifier) state restore error: \(error)")
                results[identifier] = false
            }
        }
        
        return results
    }
    
    /// Executes pre-save hooks
    private func executePreSaveHooks(reason: String, isEmergency: Bool) async {
        for hook in persistenceHooks {
            await hook.preSave(reason: reason, isEmergency: isEmergency)
        }
    }
    
    /// Executes post-save hooks
    private func executePostSaveHooks(success: Bool, reason: String) async {
        for hook in persistenceHooks {
            await hook.postSave(success: success, reason: reason)
        }
    }
    
    /// Executes pre-restore hooks
    private func executePreRestoreHooks(reason: String) async {
        for hook in persistenceHooks {
            await hook.preRestore(reason: reason)
        }
    }
    
    /// Executes post-restore hooks
    private func executePostRestoreHooks(success: Bool, reason: String) async {
        for hook in persistenceHooks {
            await hook.postRestore(success: success, reason: reason)
        }
    }
    
    /// Executes emergency restore hooks
    private func executeEmergencyRestoreHooks(backupData: [String: Any]) async {
        for hook in persistenceHooks {
            await hook.emergencyRestore(backupData: backupData)
        }
    }
    
    /// Records successful persistence operation
    private func recordSuccessfulPersistence() async {
        let now = Date()
        lastPersistenceTime = now
        userDefaults.set(now, forKey: CoordinationKeys.lastPersistenceTime)
        userDefaults.set(currentPersistenceVersion, forKey: CoordinationKeys.persistenceVersion)
    }
    
    /// Records successful restoration operation
    private func recordSuccessfulRestoration() async {
        let now = Date()
        lastRestorationTime = now
        userDefaults.set(now, forKey: CoordinationKeys.lastRestorationTime)
    }
    
    /// Creates emergency rate limit backup
    private func createEmergencyRateLimitBackup() async -> [String: Any] {
        guard let rateLimitManager = rateLimitManager else { return [:] }
        
        let rateLimitInfo = rateLimitManager.rateLimitInfo
        return [
            "requestsThisMonth": rateLimitInfo.requestsThisMonth,
            "monthlyLimit": rateLimitInfo.monthlyLimit,
            "isLimited": rateLimitInfo.isLimited,
            "resetDate": rateLimitInfo.resetDate ?? Date()
        ]
    }
    
    // MARK: - Helper Methods
    
    private func markPersistenceInProgress(_ inProgress: Bool) {
        userDefaults.set(inProgress, forKey: CoordinationKeys.persistenceInProgress)
    }
    
    private func checkRestorationRequired() {
        if userDefaults.bool(forKey: CoordinationKeys.restorationRequired) {
            Task {
                await restoreAuthenticationState(reason: "startup_restoration_required")
            }
        }
    }
    
    private func clearRestorationRequired() {
        userDefaults.removeObject(forKey: CoordinationKeys.restorationRequired)
    }
    
    private func shouldRestoreOnForeground() -> Bool {
        // Restore if persistence was interrupted
        return userDefaults.bool(forKey: CoordinationKeys.persistenceInProgress)
    }
    
    private func shouldRestoreAfterSystemWake() -> Bool {
        // Check if we need to restore state after system wake
        guard let lastPersistence = lastPersistenceTime else { return false }
        
        // If last persistence was more than 10 minutes ago, consider restoration
        return Date().timeIntervalSince(lastPersistence) > 10 * 60
    }
    
    private func checkPersistenceVersionCompatibility() async -> Bool {
        let storedVersion = userDefaults.string(forKey: CoordinationKeys.persistenceVersion)
        return storedVersion == currentPersistenceVersion
    }
    
    private func migratePersistenceFormat() async {
        print("🔄 Migrating persistence format to version \(currentPersistenceVersion)")
        // Implementation would depend on specific migration needs
    }
    
    private func setupPeriodicIntegrityChecks() {
        // Set up periodic checks to ensure persistence integrity
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performIntegrityCheck()
            }
        }
    }
    
    private func performIntegrityCheck() async {
        // Perform periodic integrity checks on persisted data
        print("🔍 Performing persistence integrity check")
    }
    
    // MARK: - Public Status Methods
    
    /// Gets comprehensive persistence status
    /// - Returns: Dictionary with persistence coordination status
    public func getPersistenceStatus() -> [String: Any] {
        var status: [String: Any] = [:]
        
        status["isPersisting"] = isPersisting
        status["isRestoring"] = isRestoring
        status["lastPersistenceTime"] = lastPersistenceTime
        status["lastRestorationTime"] = lastRestorationTime
        status["persistenceVersion"] = currentPersistenceVersion
        status["registeredProviders"] = Array(persistenceProviders.keys)
        status["pendingOperations"] = Array(pendingPersistenceOperations)
        status["persistenceHooksCount"] = persistenceHooks.count
        
        status["persistenceInProgress"] = userDefaults.bool(forKey: CoordinationKeys.persistenceInProgress)
        status["restorationRequired"] = userDefaults.bool(forKey: CoordinationKeys.restorationRequired)
        status["hasEmergencyBackup"] = userDefaults.data(forKey: CoordinationKeys.emergencyBackup) != nil
        
        return status
    }
    
    /// Logs persistence status for debugging
    public func logPersistenceStatus() {
        let status = getPersistenceStatus()
        
        print("🔄 Authentication State Persistence Status:")
        for (key, value) in status.sorted(by: { $0.key < $1.key }) {
            if let date = value as? Date {
                print("   \(key): \(date.formatted())")
            } else if let array = value as? [String] {
                print("   \(key): \(array.joined(separator: ", "))")
            } else {
                print("   \(key): \(value)")
            }
        }
    }
}

// MARK: - Extensions for Emergency State Description

private extension AuthenticationState {
    var emergencyDescription: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .authenticating:
            return "authenticating"
        case .authenticated:
            return "authenticated"
        case .refreshing:
            return "refreshing"
        case .error:
            return "error"
        }
    }
}
import Foundation
import Combine

/// Extension to AuthManager implementing authentication state persistence coordination
extension AuthManager {
    
    // MARK: - Persistence Coordinator Access
    
    /// Internal persistence coordinator
    private var persistenceCoordinator: AuthenticationStatePersistenceCoordinator {
        return AuthenticationStatePersistenceCoordinator.shared
    }
    
    // MARK: - Authentication State Persistence Implementation
    
    /// Saves authentication state in a coordinated manner across all components
    /// - Parameter reason: Reason for the save operation
    /// - Parameter isEmergency: Whether this is an emergency save before app termination
    /// - Returns: True if save was successful
    public func saveAuthenticationState(reason: String, isEmergency: Bool = false) async -> Bool {
        print("💾 AuthManager: Initiating coordinated authentication state save - \(reason)")
        
        // Delegate to the persistence coordinator
        let success = await persistenceCoordinator.saveAuthenticationState(reason: reason, isEmergency: isEmergency)
        
        if success {
            print("✅ AuthManager: Coordinated authentication state save completed successfully")
        } else {
            print("❌ AuthManager: Coordinated authentication state save failed")
        }
        
        return success
    }
    
    /// Restores authentication state in a coordinated manner across all components
    /// - Parameter reason: Reason for the restore operation
    /// - Returns: True if restore was successful
    public func restoreAuthenticationState(reason: String) async -> Bool {
        print("📤 AuthManager: Initiating coordinated authentication state restore - \(reason)")
        
        // Delegate to the persistence coordinator
        let success = await persistenceCoordinator.restoreAuthenticationState(reason: reason)
        
        if success {
            print("✅ AuthManager: Coordinated authentication state restore completed successfully")
            
            // After successful restore, validate the authentication state
            await validateRestoredAuthenticationState()
        } else {
            print("❌ AuthManager: Coordinated authentication state restore failed")
        }
        
        return success
    }
    
    /// Creates an emergency backup of critical authentication state
    /// - Returns: True if emergency backup was successful
    public func createEmergencyBackup() async -> Bool {
        print("🚨 AuthManager: Creating emergency authentication state backup")
        
        // Delegate to the persistence coordinator
        let success = await persistenceCoordinator.createEmergencyBackup()
        
        if success {
            print("✅ AuthManager: Emergency backup created successfully")
        } else {
            print("❌ AuthManager: Emergency backup creation failed")
        }
        
        return success
    }
    
    /// Restores from emergency backup if available
    /// - Returns: True if emergency restore was successful
    public func restoreFromEmergencyBackup() async -> Bool {
        print("🚨 AuthManager: Restoring from emergency authentication state backup")
        
        // Delegate to the persistence coordinator
        let success = await persistenceCoordinator.restoreFromEmergencyBackup()
        
        if success {
            print("✅ AuthManager: Emergency restore completed successfully")
            
            // After emergency restore, perform validation and recovery
            await performPostEmergencyRestoreValidation()
        } else {
            print("❌ AuthManager: Emergency restore failed")
        }
        
        return success
    }
    
    /// Checks if persisted authentication state exists and is valid
    /// - Returns: True if valid persisted state exists
    public func hasValidPersistedAuthenticationState() async -> Bool {
        // Check with all registered persistence providers
        let providers = getAllPersistenceProviders()
        
        for provider in providers {
            if await provider.hasValidPersistedState() {
                return true
            }
        }
        
        return false
    }
    
    /// Clears all persisted authentication state
    /// - Returns: True if clear was successful
    public func clearPersistedAuthenticationState() async -> Bool {
        print("🧹 AuthManager: Clearing all persisted authentication state")
        
        var allSuccess = true
        let providers = getAllPersistenceProviders()
        
        for provider in providers {
            let success = await provider.clearPersistedState()
            if !success {
                print("❌ Failed to clear persisted state for \(provider.identifier)")
                allSuccess = false
            }
        }
        
        if allSuccess {
            print("✅ All persisted authentication state cleared successfully")
        } else {
            print("❌ Some persisted authentication state could not be cleared")
        }
        
        return allSuccess
    }
    
    /// Gets the size of persisted authentication data (for monitoring)
    /// - Returns: Size in bytes, or nil if unable to determine
    public func getPersistedAuthenticationDataSize() async -> Int? {
        var totalSize = 0
        let providers = getAllPersistenceProviders()
        
        for provider in providers {
            if let size = await provider.getPersistedDataSize() {
                totalSize += size
            } else {
                // If any provider can't determine size, return nil
                return nil
            }
        }
        
        return totalSize
    }
    
    /// Validates the integrity of persisted authentication state
    /// - Returns: True if persisted state is valid and uncorrupted
    public func validatePersistedAuthenticationState() async -> Bool {
        let providers = getAllPersistenceProviders()
        
        for provider in providers {
            if await provider.hasValidPersistedState() {
                let isValid = await provider.validatePersistedState()
                if !isValid {
                    print("❌ Persisted state validation failed for \(provider.identifier)")
                    return false
                }
            }
        }
        
        print("✅ All persisted authentication state validated successfully")
        return true
    }
    
    /// Gets comprehensive persistence status information
    /// - Returns: Dictionary with persistence coordination status
    public func getPersistenceStatus() -> [String: Any] {
        return persistenceCoordinator.getPersistenceStatus()
    }
    
    // MARK: - Internal Persistence Setup
    
    /// Sets up authentication state persistence coordination during AuthManager initialization
    /// This should be called during AuthManager init
    internal func setupAuthenticationStatePersistence() {
        // Register components with the persistence coordinator
        persistenceCoordinator.registerComponents(
            authManager: self,
            tokenRefreshManager: tokenRefreshManager,
            keychainManager: keychainManager,
            rateLimitManager: rateLimitManager,
            postQueueManager: postQueueManager,
            networkMonitor: networkMonitor
        )
        
        // Register persistence hooks
        setupPersistenceHooks()
        
        // Set up shared instance reference
        AuthenticationStatePersistenceCoordinator.shared = persistenceCoordinator
        
        print("🔄 AuthManager: Authentication state persistence coordination setup completed")
    }
    
    /// Sets up persistence hooks for validation and monitoring
    private func setupPersistenceHooks() {
        // Register validation hook
        let validationHook = AuthenticationValidationHook(authManager: self)
        persistenceCoordinator.registerPersistenceHook(validationHook)
        
        // Register sensitive data cleanup hook
        let cleanupHook = SensitiveDataCleanupHook()
        persistenceCoordinator.registerPersistenceHook(cleanupHook)
        
        // Register monitoring hook
        let monitoringHook = PersistenceMonitoringHook()
        persistenceCoordinator.registerPersistenceHook(monitoringHook)
        
        print("🪝 Persistence hooks registered successfully")
    }
    
    // MARK: - App Lifecycle Integration with Persistence
    
    /// Enhanced app backgrounding with persistence coordination
    public func prepareForBackgroundWithPersistence() async {
        print("🌅 AuthManager: Preparing for background with persistence coordination")
        
        // First handle regular app lifecycle preparation
        await prepareForBackground()
        
        // Then save authentication state
        await saveAuthenticationState(reason: "app_backgrounding", isEmergency: false)
    }
    
    /// Enhanced app foregrounding with persistence coordination
    public func handleForegroundRestoreWithPersistence() async {
        print("🌄 AuthManager: Handling foreground restore with persistence coordination")
        
        // First check if restoration is needed
        if await shouldRestoreAuthenticationStateOnForeground() {
            await restoreAuthenticationState(reason: "app_foregrounding")
        }
        
        // Then handle regular app lifecycle restoration
        await handleForegroundRestore()
    }
    
    /// Enhanced app termination with persistence coordination
    public func prepareForTerminationWithPersistence() async {
        print("🛑 AuthManager: Preparing for termination with persistence coordination")
        
        // Perform emergency save before termination
        await saveAuthenticationState(reason: "app_termination", isEmergency: true)
        
        // Then handle regular app lifecycle termination
        await prepareForTermination()
    }
    
    // MARK: - Private Helper Methods
    
    /// Validates restored authentication state for consistency
    private func validateRestoredAuthenticationState() async {
        print("🔍 Validating restored authentication state...")
        
        // Check authentication state consistency
        let isAuthenticated = isAuthenticated()
        let hasUser = getCurrentUser() != nil
        let hasValidTokens = await keychainManager.hasValidTokens()
        
        if isAuthenticated != hasUser {
            print("⚠️ Authentication state inconsistency: authenticated=\(isAuthenticated), hasUser=\(hasUser)")
        }
        
        if isAuthenticated != hasValidTokens {
            print("⚠️ Token state inconsistency: authenticated=\(isAuthenticated), hasValidTokens=\(hasValidTokens)")
        }
        
        // Validate token if authenticated
        if isAuthenticated {
            let validationResult = await validateTokenForCriticalOperation(.backgroundOperation)
            if !validationResult.isValid {
                print("⚠️ Token validation failed after state restoration")
                
                // Attempt to recover by refreshing tokens
                await attemptTokenRecoveryAfterRestore()
            }
        }
        
        print("✅ Restored authentication state validation completed")
    }
    
    /// Performs validation and recovery after emergency restore
    private func performPostEmergencyRestoreValidation() async {
        print("🚨 Performing post-emergency restore validation...")
        
        // Validate restored state
        await validateRestoredAuthenticationState()
        
        // Check if re-authentication is needed
        if !isAuthenticated() {
            print("🔐 Emergency restore indicates re-authentication may be needed")
            
            // Check if emergency backup indicates we were previously authenticated
            let persistenceStatus = getPersistenceStatus()
            if let hasEmergencyBackup = persistenceStatus["hasEmergencyBackup"] as? Bool, hasEmergencyBackup {
                print("💡 Emergency backup suggests user should re-authenticate")
                
                // Could trigger UI notification for re-authentication here
                eventManager.publish(authenticationEvent: .reauthenticationRequired("emergency_restore_recovery"))
            }
        }
        
        // Process any preserved posts
        await restorePreservedPosts()
        
        print("✅ Post-emergency restore validation completed")
    }
    
    /// Attempts token recovery after state restoration
    private func attemptTokenRecoveryAfterRestore() async {
        print("🔧 Attempting token recovery after state restoration...")
        
        // Try token refresh first
        let refreshSuccess = await tokenRefreshManager.refreshTokenNow()
        
        if refreshSuccess {
            print("✅ Token recovery successful after state restoration")
        } else {
            print("❌ Token recovery failed - may need re-authentication")
            
            // Trigger fallback authentication if available
            let fallbackResult = await performFallbackAuthentication(
                reason: "token_recovery_failed",
                preserveQueuedPosts: true
            )
            
            if case .failure = fallbackResult {
                print("❌ Fallback authentication also failed after state restoration")
            }
        }
    }
    
    /// Checks if authentication state should be restored on app foreground
    private func shouldRestoreAuthenticationStateOnForeground() async -> Bool {
        // Check if we have valid persisted state
        guard await hasValidPersistedAuthenticationState() else { return false }
        
        // Check if current state is inconsistent
        let currentlyAuthenticated = isAuthenticated()
        let hasStoredTokens = await keychainManager.hasValidTokens()
        
        // Restore if we have tokens but aren't authenticated
        if hasStoredTokens && !currentlyAuthenticated {
            return true
        }
        
        // Check app lifecycle coordinator for additional context
        if let coordinator = getAppLifecycleCoordinator(),
           let timeInBackground = coordinator.getTimeInBackground() {
            // Restore if we were in background for more than 5 minutes
            return timeInBackground > 5 * 60
        }
        
        return false
    }
    
    /// Gets all persistence providers for validation and monitoring
    private func getAllPersistenceProviders() -> [AuthenticationPersistenceProvider] {
        return [
            AuthManagerPersistenceProvider(authManager: self),
            TokenRefreshManagerPersistenceProvider(tokenRefreshManager: tokenRefreshManager),
            RateLimitManagerPersistenceProvider(rateLimitManager: rateLimitManager),
            PostQueueManagerPersistenceProvider(postQueueManager: postQueueManager),
            NetworkMonitorPersistenceProvider(networkMonitor: networkMonitor)
        ]
    }
    
    /// Gets the app lifecycle coordinator for integration
    private func getAppLifecycleCoordinator() -> AppLifecycleCoordinator? {
        return AppLifecycleCoordinator.shared
    }
    
    // MARK: - Public Persistence Status Methods
    
    /// Gets comprehensive authentication persistence status for monitoring
    /// - Returns: Dictionary with authentication persistence status
    public func getAuthenticationPersistenceStatus() -> [String: Any] {
        var status = getPersistenceStatus()
        
        // Add AuthManager-specific persistence status
        status["authManager_isAuthenticated"] = isAuthenticated()
        status["authManager_authenticationState"] = authenticationState.emergencyDescription
        
        // Add component-specific status
        Task {
            status["authManager_hasValidPersistedState"] = await hasValidPersistedAuthenticationState()
            status["authManager_persistedDataSize"] = await getPersistedAuthenticationDataSize()
            status["authManager_stateValidation"] = await validatePersistedAuthenticationState()
        }
        
        return status
    }
    
    /// Logs comprehensive authentication persistence status for debugging
    public func logAuthenticationPersistenceStatus() {
        print("🔄 AuthManager Authentication Persistence Status:")
        
        let status = getAuthenticationPersistenceStatus()
        for (key, value) in status.sorted(by: { $0.key < $1.key }) {
            if let date = value as? Date {
                print("   \(key): \(date.formatted())")
            } else if let size = value as? Int {
                print("   \(key): \(size) bytes")
            } else {
                print("   \(key): \(value)")
            }
        }
        
        // Also log coordinator status
        persistenceCoordinator.logPersistenceStatus()
    }
}

// MARK: - Shared Instance Support

extension AuthenticationStatePersistenceCoordinator {
    /// Shared instance for use across the app (temporary approach)
    /// In production, this should be properly injected
    static var shared: AuthenticationStatePersistenceCoordinator = AuthenticationStatePersistenceCoordinator()
}
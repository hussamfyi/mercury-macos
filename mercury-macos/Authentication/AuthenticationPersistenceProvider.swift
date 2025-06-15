import Foundation

/// Protocol for components that can persist and restore their authentication-related state
public protocol AuthenticationPersistenceProvider {
    
    /// Unique identifier for this persistence provider
    var identifier: String { get }
    
    /// Current version of the persistence format for this provider
    var persistenceVersion: String { get }
    
    /// Saves the component's current state
    /// - Parameter isEmergency: Whether this is an emergency save before app termination
    /// - Returns: True if save was successful
    func saveState(isEmergency: Bool) async -> Bool
    
    /// Restores the component's state from persistent storage
    /// - Returns: True if restore was successful
    func restoreState() async -> Bool
    
    /// Checks if persisted state exists and is valid
    /// - Returns: True if valid persisted state exists
    func hasValidPersistedState() async -> Bool
    
    /// Clears all persisted state for this component
    /// - Returns: True if clear was successful
    func clearPersistedState() async -> Bool
    
    /// Gets the size of persisted data in bytes (for monitoring)
    /// - Returns: Size in bytes, or nil if unable to determine
    func getPersistedDataSize() async -> Int?
    
    /// Validates the integrity of persisted state
    /// - Returns: True if persisted state is valid and uncorrupted
    func validatePersistedState() async -> Bool
}

/// Protocol for persistence hooks that can execute custom logic during save/restore operations
public protocol PersistenceHook {
    
    /// Unique identifier for this persistence hook
    var identifier: String { get }
    
    /// Executed before save operations begin
    /// - Parameter reason: Reason for the save operation
    /// - Parameter isEmergency: Whether this is an emergency save
    func preSave(reason: String, isEmergency: Bool) async
    
    /// Executed after save operations complete
    /// - Parameter success: Whether the save operation was successful
    /// - Parameter reason: Reason for the save operation
    func postSave(success: Bool, reason: String) async
    
    /// Executed before restore operations begin
    /// - Parameter reason: Reason for the restore operation
    func preRestore(reason: String) async
    
    /// Executed after restore operations complete
    /// - Parameter success: Whether the restore operation was successful
    /// - Parameter reason: Reason for the restore operation
    func postRestore(success: Bool, reason: String) async
    
    /// Executed during emergency restore from backup data
    /// - Parameter backupData: Emergency backup data to restore from
    func emergencyRestore(backupData: [String: Any]) async
}

// MARK: - Concrete Persistence Providers

/// Persistence provider for AuthManager state
public class AuthManagerPersistenceProvider: AuthenticationPersistenceProvider {
    
    public let identifier = "AuthManager"
    public let persistenceVersion = "1.0.0"
    
    private weak var authManager: AuthManager?
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let authenticationState = "mercury.authmanager.authentication_state"
        static let lastActiveUser = "mercury.authmanager.last_active_user"
        static let lastActiveTime = "mercury.authmanager.last_active_time"
        static let queuedPostsCount = "mercury.authmanager.queued_posts_count"
        static let rateLimitInfo = "mercury.authmanager.rate_limit_info"
        static let persistenceVersion = "mercury.authmanager.persistence_version"
    }
    
    public init(authManager: AuthManager?) {
        self.authManager = authManager
    }
    
    public func saveState(isEmergency: Bool) async -> Bool {
        guard let authManager = authManager else { return false }
        
        do {
            // Save authentication state
            let stateData = authManager.authenticationState.emergencyDescription
            userDefaults.set(stateData, forKey: Keys.authenticationState)
            
            // Save current user info
            if let user = authManager.getCurrentUser() {
                let userData = [
                    "id": user.id,
                    "username": user.username,
                    "name": user.name,
                    "profileImageUrl": user.profileImageUrl ?? "",
                    "verified": user.verified ?? false
                ] as [String: Any]
                userDefaults.set(userData, forKey: Keys.lastActiveUser)
            }
            
            // Save last active time
            userDefaults.set(Date(), forKey: Keys.lastActiveTime)
            
            // Save queued posts count
            userDefaults.set(authManager.queuedPostsCount, forKey: Keys.queuedPostsCount)
            
            // Save rate limit info
            let rateLimitInfo = authManager.getRateLimitInfo()
            let rateLimitData = [
                "requestsThisMonth": rateLimitInfo.requestsThisMonth,
                "monthlyLimit": rateLimitInfo.monthlyLimit,
                "isLimited": rateLimitInfo.isLimited,
                "resetDate": rateLimitInfo.resetDate ?? Date()
            ] as [String: Any]
            userDefaults.set(rateLimitData, forKey: Keys.rateLimitInfo)
            
            // Save persistence version
            userDefaults.set(persistenceVersion, forKey: Keys.persistenceVersion)
            
            print("✅ AuthManager state persisted successfully")
            return true
            
        } catch {
            print("❌ AuthManager state persistence failed: \(error)")
            return false
        }
    }
    
    public func restoreState() async -> Bool {
        guard let authManager = authManager else { return false }
        
        do {
            // Check if persisted state exists
            guard hasValidPersistedState() else { return false }
            
            // Restore last active time
            if let lastActiveTime = userDefaults.object(forKey: Keys.lastActiveTime) as? Date {
                print("📅 AuthManager: Last active at \(lastActiveTime.formatted())")
                userDefaults.set(lastActiveTime, forKey: "mercury.auth.last_success")
            }
            
            // Note: We don't restore authentication state directly as that would
            // require re-establishing network connections and token validation
            // Instead, we let the normal initialization process handle state restoration
            
            print("✅ AuthManager state restored successfully")
            return true
            
        } catch {
            print("❌ AuthManager state restoration failed: \(error)")
            return false
        }
    }
    
    public func hasValidPersistedState() async -> Bool {
        let hasAuthState = userDefaults.object(forKey: Keys.authenticationState) != nil
        let hasValidVersion = userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
        return hasAuthState && hasValidVersion
    }
    
    public func clearPersistedState() async -> Bool {
        userDefaults.removeObject(forKey: Keys.authenticationState)
        userDefaults.removeObject(forKey: Keys.lastActiveUser)
        userDefaults.removeObject(forKey: Keys.lastActiveTime)
        userDefaults.removeObject(forKey: Keys.queuedPostsCount)
        userDefaults.removeObject(forKey: Keys.rateLimitInfo)
        userDefaults.removeObject(forKey: Keys.persistenceVersion)
        
        print("🧹 AuthManager persisted state cleared")
        return true
    }
    
    public func getPersistedDataSize() async -> Int? {
        // Approximate size calculation
        var size = 0
        
        if let stateData = userDefaults.string(forKey: Keys.authenticationState) {
            size += stateData.utf8.count
        }
        
        if let userData = userDefaults.object(forKey: Keys.lastActiveUser) {
            if let data = try? JSONSerialization.data(withJSONObject: userData) {
                size += data.count
            }
        }
        
        size += 8 // Date
        size += 4 // Int (queued posts count)
        
        return size
    }
    
    public func validatePersistedState() async -> Bool {
        // Check if all required keys exist and have valid values
        guard userDefaults.object(forKey: Keys.authenticationState) != nil else { return false }
        guard userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion else { return false }
        
        return true
    }
}

/// Persistence provider for TokenRefreshManager state
public class TokenRefreshManagerPersistenceProvider: AuthenticationPersistenceProvider {
    
    public let identifier = "TokenRefreshManager"
    public let persistenceVersion = "1.0.0"
    
    private weak var tokenRefreshManager: TokenRefreshManager?
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let refreshState = "mercury.tokenrefresh.refresh_state"
        static let retryCount = "mercury.tokenrefresh.retry_count"
        static let lastFailureTime = "mercury.tokenrefresh.last_failure_time"
        static let refreshMargin = "mercury.tokenrefresh.refresh_margin"
        static let isTimerActive = "mercury.tokenrefresh.is_timer_active"
        static let persistenceVersion = "mercury.tokenrefresh.persistence_version"
    }
    
    public init(tokenRefreshManager: TokenRefreshManager?) {
        self.tokenRefreshManager = tokenRefreshManager
    }
    
    public func saveState(isEmergency: Bool) async -> Bool {
        guard let tokenRefreshManager = tokenRefreshManager else { return false }
        
        do {
            let timingInfo = await tokenRefreshManager.getTimingInfo()
            
            // Save timing and state information
            userDefaults.set(timingInfo["isRefreshing"] as? Bool ?? false, forKey: Keys.refreshState)
            userDefaults.set(timingInfo["retryCount"] as? Int ?? 0, forKey: Keys.retryCount)
            userDefaults.set(timingInfo["lastFailureTime"] as? Date, forKey: Keys.lastFailureTime)
            userDefaults.set(timingInfo["refreshMarginSeconds"] as? TimeInterval ?? 900, forKey: Keys.refreshMargin)
            userDefaults.set(timingInfo["timerIsActive"] as? Bool ?? false, forKey: Keys.isTimerActive)
            userDefaults.set(persistenceVersion, forKey: Keys.persistenceVersion)
            
            print("✅ TokenRefreshManager state persisted successfully")
            return true
            
        } catch {
            print("❌ TokenRefreshManager state persistence failed: \(error)")
            return false
        }
    }
    
    public func restoreState() async -> Bool {
        guard let tokenRefreshManager = tokenRefreshManager else { return false }
        
        do {
            guard hasValidPersistedState() else { return false }
            
            // Restore timer state if it was active
            if userDefaults.bool(forKey: Keys.isTimerActive) {
                print("🔄 TokenRefreshManager: Resuming refresh timer after restoration")
                tokenRefreshManager.resumeRefreshTimer()
            }
            
            // Reset retry tracking if there was a failure before persistence
            if userDefaults.object(forKey: Keys.lastFailureTime) != nil {
                print("🔄 TokenRefreshManager: Resetting retry tracking after restoration")
                tokenRefreshManager.resetRetryTracking()
            }
            
            print("✅ TokenRefreshManager state restored successfully")
            return true
            
        } catch {
            print("❌ TokenRefreshManager state restoration failed: \(error)")
            return false
        }
    }
    
    public func hasValidPersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
    }
    
    public func clearPersistedState() async -> Bool {
        userDefaults.removeObject(forKey: Keys.refreshState)
        userDefaults.removeObject(forKey: Keys.retryCount)
        userDefaults.removeObject(forKey: Keys.lastFailureTime)
        userDefaults.removeObject(forKey: Keys.refreshMargin)
        userDefaults.removeObject(forKey: Keys.isTimerActive)
        userDefaults.removeObject(forKey: Keys.persistenceVersion)
        
        print("🧹 TokenRefreshManager persisted state cleared")
        return true
    }
    
    public func getPersistedDataSize() async -> Int? {
        return 32 // Approximate size for timing data
    }
    
    public func validatePersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
    }
}

/// Persistence provider for RateLimitManager state
public class RateLimitManagerPersistenceProvider: AuthenticationPersistenceProvider {
    
    public let identifier = "RateLimitManager"
    public let persistenceVersion = "1.0.0"
    
    private weak var rateLimitManager: RateLimitManager?
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let requestsThisMonth = "mercury.ratelimit.requests_this_month"
        static let monthlyLimit = "mercury.ratelimit.monthly_limit"
        static let resetDate = "mercury.ratelimit.reset_date"
        static let isLimited = "mercury.ratelimit.is_limited"
        static let persistenceVersion = "mercury.ratelimit.persistence_version"
    }
    
    public init(rateLimitManager: RateLimitManager?) {
        self.rateLimitManager = rateLimitManager
    }
    
    public func saveState(isEmergency: Bool) async -> Bool {
        guard let rateLimitManager = rateLimitManager else { return false }
        
        do {
            let rateLimitInfo = rateLimitManager.rateLimitInfo
            
            userDefaults.set(rateLimitInfo.requestsThisMonth, forKey: Keys.requestsThisMonth)
            userDefaults.set(rateLimitInfo.monthlyLimit, forKey: Keys.monthlyLimit)
            userDefaults.set(rateLimitInfo.resetDate, forKey: Keys.resetDate)
            userDefaults.set(rateLimitInfo.isLimited, forKey: Keys.isLimited)
            userDefaults.set(persistenceVersion, forKey: Keys.persistenceVersion)
            
            print("✅ RateLimitManager state persisted successfully")
            return true
            
        } catch {
            print("❌ RateLimitManager state persistence failed: \(error)")
            return false
        }
    }
    
    public func restoreState() async -> Bool {
        guard hasValidPersistedState() else { return false }
        
        // Rate limit state is automatically loaded by RateLimitManager during initialization
        // This method verifies the restoration was successful
        
        print("✅ RateLimitManager state restored successfully")
        return true
    }
    
    public func hasValidPersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion &&
               userDefaults.object(forKey: Keys.requestsThisMonth) != nil
    }
    
    public func clearPersistedState() async -> Bool {
        userDefaults.removeObject(forKey: Keys.requestsThisMonth)
        userDefaults.removeObject(forKey: Keys.monthlyLimit)
        userDefaults.removeObject(forKey: Keys.resetDate)
        userDefaults.removeObject(forKey: Keys.isLimited)
        userDefaults.removeObject(forKey: Keys.persistenceVersion)
        
        print("🧹 RateLimitManager persisted state cleared")
        return true
    }
    
    public func getPersistedDataSize() async -> Int? {
        return 24 // Approximate size for rate limit data
    }
    
    public func validatePersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
    }
}

/// Persistence provider for PostQueueManager state
public class PostQueueManagerPersistenceProvider: AuthenticationPersistenceProvider {
    
    public let identifier = "PostQueueManager"
    public let persistenceVersion = "1.0.0"
    
    private weak var postQueueManager: PostQueueManager?
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let queuedPostsCount = "mercury.postqueue.queued_posts_count"
        static let isProcessing = "mercury.postqueue.is_processing"
        static let lastProcessingTime = "mercury.postqueue.last_processing_time"
        static let persistenceVersion = "mercury.postqueue.persistence_version"
    }
    
    public init(postQueueManager: PostQueueManager?) {
        self.postQueueManager = postQueueManager
    }
    
    public func saveState(isEmergency: Bool) async -> Bool {
        guard let postQueueManager = postQueueManager else { return false }
        
        do {
            let queuedCount = await postQueueManager.getQueuedPostsCount()
            
            userDefaults.set(queuedCount, forKey: Keys.queuedPostsCount)
            userDefaults.set(Date(), forKey: Keys.lastProcessingTime)
            userDefaults.set(persistenceVersion, forKey: Keys.persistenceVersion)
            
            print("✅ PostQueueManager state persisted successfully")
            return true
            
        } catch {
            print("❌ PostQueueManager state persistence failed: \(error)")
            return false
        }
    }
    
    public func restoreState() async -> Bool {
        guard hasValidPersistedState() else { return false }
        
        // Post queue state is automatically loaded by PostQueueManager during initialization
        print("✅ PostQueueManager state restored successfully")
        return true
    }
    
    public func hasValidPersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
    }
    
    public func clearPersistedState() async -> Bool {
        userDefaults.removeObject(forKey: Keys.queuedPostsCount)
        userDefaults.removeObject(forKey: Keys.isProcessing)
        userDefaults.removeObject(forKey: Keys.lastProcessingTime)
        userDefaults.removeObject(forKey: Keys.persistenceVersion)
        
        print("🧹 PostQueueManager persisted state cleared")
        return true
    }
    
    public func getPersistedDataSize() async -> Int? {
        return 16 // Approximate size for queue state data
    }
    
    public func validatePersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
    }
}

/// Persistence provider for NetworkMonitor state
public class NetworkMonitorPersistenceProvider: AuthenticationPersistenceProvider {
    
    public let identifier = "NetworkMonitor"
    public let persistenceVersion = "1.0.0"
    
    private weak var networkMonitor: NetworkMonitor?
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let isConnected = "mercury.network.is_connected"
        static let connectionQuality = "mercury.network.connection_quality"
        static let lastConnectedTime = "mercury.network.last_connected_time"
        static let persistenceVersion = "mercury.network.persistence_version"
    }
    
    public init(networkMonitor: NetworkMonitor?) {
        self.networkMonitor = networkMonitor
    }
    
    public func saveState(isEmergency: Bool) async -> Bool {
        guard let networkMonitor = networkMonitor else { return false }
        
        do {
            userDefaults.set(networkMonitor.isConnected, forKey: Keys.isConnected)
            userDefaults.set(networkMonitor.currentConnectionQuality.rawValue, forKey: Keys.connectionQuality)
            
            if networkMonitor.isConnected {
                userDefaults.set(Date(), forKey: Keys.lastConnectedTime)
            }
            
            userDefaults.set(persistenceVersion, forKey: Keys.persistenceVersion)
            
            print("✅ NetworkMonitor state persisted successfully")
            return true
            
        } catch {
            print("❌ NetworkMonitor state persistence failed: \(error)")
            return false
        }
    }
    
    public func restoreState() async -> Bool {
        guard hasValidPersistedState() else { return false }
        
        // Network monitor state is automatically managed by the system
        // This method just validates that restoration context is available
        
        if let lastConnectedTime = userDefaults.object(forKey: Keys.lastConnectedTime) as? Date {
            let timeSinceLastConnection = Date().timeIntervalSince(lastConnectedTime)
            print("📶 NetworkMonitor: Last connected \(String(format: "%.1f", timeSinceLastConnection))s ago")
        }
        
        print("✅ NetworkMonitor state restored successfully")
        return true
    }
    
    public func hasValidPersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
    }
    
    public func clearPersistedState() async -> Bool {
        userDefaults.removeObject(forKey: Keys.isConnected)
        userDefaults.removeObject(forKey: Keys.connectionQuality)
        userDefaults.removeObject(forKey: Keys.lastConnectedTime)
        userDefaults.removeObject(forKey: Keys.persistenceVersion)
        
        print("🧹 NetworkMonitor persisted state cleared")
        return true
    }
    
    public func getPersistedDataSize() async -> Int? {
        return 16 // Approximate size for network state data
    }
    
    public func validatePersistedState() async -> Bool {
        return userDefaults.string(forKey: Keys.persistenceVersion) == persistenceVersion
    }
}
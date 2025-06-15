import Foundation
import Combine
import SwiftUI

/// Protocol for token refresh operations
public protocol TokenRefreshDelegate: AnyObject {
    func refreshTokens() async -> TokenRefreshResult
    func triggerReauthentication() async
}

/// Failure details for persistence
private struct FailureDetails: Codable {
    let count: Int
    let lastTime: Date
    
    init(count: Int, lastTime: Date) {
        self.count = count
        self.lastTime = lastTime
    }
}

/// Classification of refresh errors for appropriate handling
private enum RefreshErrorType: CaseIterable {
    case networkUnavailable        // No internet connection
    case networkTimeout           // Request timed out
    case networkSecurity          // SSL/TLS issues
    case networkGeneral          // Other network issues
    case serverUnavailable       // X API server unreachable
    case serverError            // X API server errors (5xx)
    case rateLimited           // Too many requests (429)
    case authenticationInvalid // Refresh token expired/invalid
    case apiError             // Client errors (4xx, non-auth)
    case unknown              // Unclassified errors
    
    /// Converts error type to string for storage
    func toString() -> String {
        switch self {
        case .networkUnavailable: return "networkUnavailable"
        case .networkTimeout: return "networkTimeout"
        case .networkSecurity: return "networkSecurity"
        case .networkGeneral: return "networkGeneral"
        case .serverUnavailable: return "serverUnavailable"
        case .serverError: return "serverError"
        case .rateLimited: return "rateLimited"
        case .authenticationInvalid: return "authenticationInvalid"
        case .apiError: return "apiError"
        case .unknown: return "unknown"
        }
    }
    
    /// Creates error type from string
    static func fromString(_ string: String) -> RefreshErrorType? {
        return RefreshErrorType.allCases.first { $0.toString() == string }
    }
}

/// Manages automatic token refresh with proper timing and error handling
@MainActor
public class TokenRefreshManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var refreshState: TokenRefreshState = .idle
    
    // MARK: - Public Publishers
    
    public var statePublisher: AnyPublisher<TokenRefreshState, Never> {
        $refreshState.eraseToAnyPublisher()
    }
    
    // MARK: - Dependencies
    
    private let keychainManager: KeychainManager
    private let rateLimitManager: RateLimitManager?
    private let networkMonitor: NetworkMonitor?
    private weak var delegate: TokenRefreshDelegate?
    
    // MARK: - Internal State
    
    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var cancellables = Set<AnyCancellable>()
    
    /// Synchronization for preventing simultaneous refresh attempts (Task 11.7)
    private let refreshSemaphore = DispatchSemaphore(value: 1)
    private var pendingRefreshRequests: Int = 0
    
    // Token expiration tracking
    private var cachedExpiryDate: Date?
    private var lastExpiryCheck: Date?
    
    // Exponential backoff tracking
    private var retryCount = 0
    private var lastFailureTime: Date?
    
    // Operation coordination tracking
    private var activePostingOperations = Set<UUID>()
    private var pendingRefreshAfterPost = false
    
    // MARK: - Configuration
    
    /// How early to refresh before expiration (15 minutes as per PRD)
    private let refreshMargin: TimeInterval = 15 * 60
    
    /// Minimum interval between refresh checks (5 minutes)
    private let checkInterval: TimeInterval = 5 * 60
    
    /// Maximum interval between refresh checks (30 minutes)
    private let maxCheckInterval: TimeInterval = 30 * 60
    
    /// Fallback check interval when expiry is unknown (10 minutes)
    private let fallbackCheckInterval: TimeInterval = 10 * 60
    
    // MARK: - Exponential Backoff Configuration
    
    /// Base delay for exponential backoff (1 second)
    private let baseRetryDelay: TimeInterval = 1.0
    
    /// Maximum retry delay (30 seconds as per PRD)
    private let maxRetryDelay: TimeInterval = 30.0
    
    /// Maximum number of consecutive failures before giving up
    private let maxRetryAttempts = 5
    
    // MARK: - Rate Limiting Configuration
    
    /// Minimum interval between refresh attempts to respect API rate limits (30 seconds)
    private let minRefreshInterval: TimeInterval = 30.0
    
    /// Time to wait after hitting rate limits (5 minutes per PRD)
    private let rateLimitBackoffTime: TimeInterval = 5 * 60
    
    /// Tracking for last refresh attempt time
    private var lastRefreshAttemptTime: Date?
    
    /// Rapid expiration detection (Task 11.7)
    private var shortLivedTokenCount: Int = 0
    private var lastShortLivedTokenTime: Date?
    private let shortLivedTokenThreshold: TimeInterval = 30 * 60 // 30 minutes - consider short-lived
    
    /// Success/failure tracking for monitoring (Task 11.6)
    private var refreshSuccessCount: Int = 0
    private var refreshFailureCount: Int = 0
    private var lastSuccessTime: Date?
    private var lastFailureDetailsByType: [RefreshErrorType: FailureDetails] = [:]
    
    /// UserDefaults storage for persistence of monitoring data
    private let userDefaults = UserDefaults.standard
    private enum MonitoringStorageKeys {
        static let successCount = "mercury.auth.refresh.success_count"
        static let failureCount = "mercury.auth.refresh.failure_count"
        static let lastSuccessTime = "mercury.auth.refresh.last_success_time"
        static let failureDetailsByType = "mercury.auth.refresh.failures_by_type"
        static let monitoringStartTime = "mercury.auth.refresh.monitoring_start_time"
    }
    
    // MARK: - Initialization
    
    public init(keychainManager: KeychainManager = KeychainManager(), 
                rateLimitManager: RateLimitManager? = nil,
                networkMonitor: NetworkMonitor? = nil,
                delegate: TokenRefreshDelegate? = nil) {
        self.keychainManager = keychainManager
        self.rateLimitManager = rateLimitManager
        self.networkMonitor = networkMonitor
        self.delegate = delegate
        
        // Load persisted monitoring data
        loadMonitoringData()
        
        // Start the timer after a brief delay to allow initialization to complete
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            startRefreshTimer()
        }
    }
    
    /// Sets the delegate for token refresh operations
    public func setDelegate(_ delegate: TokenRefreshDelegate) {
        self.delegate = delegate
    }
    
    /// Sets the rate limit manager for API rate limit awareness
    public func setRateLimitManager(_ rateLimitManager: RateLimitManager) {
        // Note: This would require making rateLimitManager var instead of let
        // For now, rate limit manager should be set during initialization
        print("⚠️ Rate limit manager should be set during TokenRefreshManager initialization")
    }
    
    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Public Methods
    
    /// Starts the automatic token refresh timer
    public func startRefreshTimer() {
        stopRefresh() // Stop any existing timer
        
        // Schedule timer with intelligent interval based on token expiry
        Task {
            await scheduleNextRefreshCheck()
        }
    }
    
    /// Schedules the next refresh check based on token expiration
    private func scheduleNextRefreshCheck() async {
        guard !isRefreshing else {
            // If currently refreshing, schedule a short check to reschedule after completion
            await scheduleShortCheck()
            return
        }
        
        let intervalToUse = await calculateOptimalCheckInterval()
        
        print("⏰ Scheduling next refresh check in \(String(format: "%.1f", intervalToUse))s (at \(Date().addingTimeInterval(intervalToUse).formatted()))")
        
        await MainActor.run {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: intervalToUse, repeats: false) { [weak self] _ in
                Task {
                    await self?.handleScheduledRefreshCheck()
                }
            }
        }
    }
    
    /// Calculates the optimal interval for the next refresh check
    private func calculateOptimalCheckInterval() async -> TimeInterval {
        // Consider both token expiry and rate limiting constraints
        let nextAllowedRefresh = nextAllowedRefreshTime()
        let nextTokenRefresh = await nextRefreshTime()
        
        // Determine the next actual refresh time considering all constraints
        let actualNextRefresh: Date
        if let tokenRefresh = nextTokenRefresh {
            actualNextRefresh = max(nextAllowedRefresh, tokenRefresh)
        } else {
            // No valid expiry date, but still need to respect rate limits
            let fallbackRefresh = Date().addingTimeInterval(fallbackCheckInterval)
            actualNextRefresh = max(nextAllowedRefresh, fallbackRefresh)
        }
        
        let timeUntilRefresh = actualNextRefresh.timeIntervalSinceNow
        
        if timeUntilRefresh <= 0 {
            // Can refresh now
            return 1.0
        } else if timeUntilRefresh <= checkInterval {
            // Close to refresh time, use exact timing
            return timeUntilRefresh
        } else if timeUntilRefresh <= maxCheckInterval {
            // Medium term, check half way to refresh time
            return timeUntilRefresh / 2
        } else {
            // Long term, use maximum check interval
            return maxCheckInterval
        }
    }
    
    /// Handles scheduled refresh checks with proper error handling
    private func handleScheduledRefreshCheck() async {
        print("🔄 Background refresh check triggered at \(Date().formatted())")
        
        do {
            await checkAndRefreshToken()
        } catch {
            // Log error but continue scheduling
            print("⚠️ Error during scheduled refresh check: \(error)")
        }
        
        // Always reschedule the next check
        await scheduleNextRefreshCheck()
    }
    
    /// Schedules a short check for when refresh is in progress
    private func scheduleShortCheck() async {
        await MainActor.run {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                Task {
                    await self?.scheduleNextRefreshCheck()
                }
            }
        }
    }
    
    /// Stops the automatic token refresh
    public func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRefreshing = false
        refreshState = .idle
        
        // Clear cached expiry data
        cachedExpiryDate = nil
        lastExpiryCheck = nil
        
        // Reset retry tracking
        retryCount = 0
        lastFailureTime = nil
    }
    
    /// Pauses the refresh timer (useful for app backgrounding)
    public func pauseRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    /// Resumes the refresh timer (useful for app foregrounding)
    public func resumeRefreshTimer() {
        guard refreshTimer == nil else { return } // Already running
        
        Task {
            // Check if we need immediate refresh after being paused
            if await shouldRefreshToken() {
                await checkAndRefreshToken()
            }
            
            // Resume normal scheduling
            await scheduleNextRefreshCheck()
        }
    }
    
    /// Forces an immediate check and reschedule (useful after network changes)
    public func forceRefreshCheck() {
        Task {
            await checkAndRefreshToken()
            await scheduleNextRefreshCheck()
        }
    }
    
    /// Forces immediate token refresh even if posting operations are active (emergency refresh)
    /// - Parameter reason: Reason for emergency refresh (for logging)
    public func forceEmergencyRefresh(reason: String) async -> Bool {
        print("🚨 Emergency token refresh requested: \\(reason)")
        
        if hasActivePostingOperations() {
            print("⚠️ Forcing refresh despite \\(getActivePostingCount()) active posting operation(s)")
        }
        
        // Temporarily bypass posting operation check
        return await performTokenRefresh()
    }
    
    /// Manually triggers token refresh (useful for testing or immediate needs)
    /// - Returns: True if refresh was successful
    @discardableResult
    public func refreshTokenNow() async -> Bool {
        // Implement proper synchronization to prevent simultaneous refresh attempts (Task 11.7)
        return await withCheckedContinuation { continuation in
            Task {
                // Increment pending requests counter
                await MainActor.run {
                    pendingRefreshRequests += 1
                }
                
                // Try to acquire semaphore (non-blocking check if refresh is already in progress)
                let acquired = refreshSemaphore.wait(timeout: .now())
                
                if acquired == .success {
                    // We got the semaphore, proceed with refresh
                    let result = await performTokenRefresh()
                    
                    // Release semaphore
                    refreshSemaphore.signal()
                    
                    await MainActor.run {
                        pendingRefreshRequests = max(0, pendingRefreshRequests - 1)
                    }
                    
                    continuation.resume(returning: result)
                } else {
                    // Another refresh is in progress, return false
                    await MainActor.run {
                        pendingRefreshRequests = max(0, pendingRefreshRequests - 1)
                    }
                    
                    print("🔄 Refresh attempt blocked - another refresh in progress")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Stores token expiration information when receiving OAuth response
    /// - Parameters:
    ///   - expiresIn: Expires in seconds from OAuth response
    ///   - issuedAt: When the token was issued (defaults to now)
    /// - Throws: KeychainError if storage fails
    public func storeTokenExpiration(expiresIn: Int, issuedAt: Date = Date()) async throws {
        let expiryDate = issuedAt.addingTimeInterval(TimeInterval(expiresIn))
        
        try await keychainManager.storeTokenExpiry(expiryDate)
        
        // Update cached values for quick access
        cachedExpiryDate = expiryDate
        lastExpiryCheck = Date()
        
        // Check for rapid expiration patterns (Task 11.7)
        checkForRapidExpiration(expiresIn: expiresIn)
    }
    
    /// Gets the current token expiration date with caching for performance
    /// - Returns: Token expiration date
    /// - Throws: KeychainError if expiry date cannot be retrieved
    public func getTokenExpiry() async throws -> Date {
        // Use cached value if it's fresh (within 1 minute)
        if let cached = cachedExpiryDate,
           let lastCheck = lastExpiryCheck,
           Date().timeIntervalSince(lastCheck) < 60 {
            return cached
        }
        
        // Fetch from keychain and update cache
        let expiryDate = try await keychainManager.getTokenExpiry()
        cachedExpiryDate = expiryDate
        lastExpiryCheck = Date()
        
        return expiryDate
    }
    
    /// Checks if token needs refresh based on expiration time
    /// - Returns: True if token should be refreshed
    public func shouldRefreshToken() async -> Bool {
        do {
            let expiryDate = try await getTokenExpiry()
            let timeUntilExpiry = expiryDate.timeIntervalSinceNow
            
            // Refresh if within the refresh margin (15 minutes before expiration)
            return timeUntilExpiry <= refreshMargin
        } catch {
            // If we can't get expiry date, assume we should refresh
            return true
        }
    }
    
    /// Gets time remaining until token expiration
    /// - Returns: Time interval until expiration (negative if already expired)
    public func timeUntilExpiration() async -> TimeInterval? {
        do {
            let expiryDate = try await getTokenExpiry()
            return expiryDate.timeIntervalSinceNow
        } catch {
            return nil
        }
    }
    
    /// Checks if token is currently expired
    /// - Returns: True if token is expired
    public func isTokenExpired() async -> Bool {
        guard let timeRemaining = await timeUntilExpiration() else {
            return true // Assume expired if we can't determine
        }
        return timeRemaining <= 0
    }
    
    /// Calculates when the next refresh should occur
    /// - Returns: Date when next refresh should happen, or nil if no valid expiry
    public func nextRefreshTime() async -> Date? {
        do {
            let expiryDate = try await getTokenExpiry()
            return expiryDate.addingTimeInterval(-refreshMargin)
        } catch {
            return nil
        }
    }
    
    /// Gets detailed timing information for diagnostics
    /// - Returns: Dictionary with timing information
    public func getTimingInfo() async -> [String: Any] {
        var info: [String: Any] = [:]
        
        info["isRefreshing"] = isRefreshing
        info["refreshMarginSeconds"] = refreshMargin
        info["checkIntervalSeconds"] = checkInterval
        info["maxCheckIntervalSeconds"] = maxCheckInterval
        info["fallbackCheckIntervalSeconds"] = fallbackCheckInterval
        info["timerIsActive"] = refreshTimer != nil
        
        if let expiry = try? await getTokenExpiry() {
            info["tokenExpiryDate"] = expiry
            info["timeUntilExpiry"] = expiry.timeIntervalSinceNow
            info["tokenIsExpired"] = expiry.timeIntervalSinceNow <= 0
        }
        
        if let nextRefresh = await nextRefreshTime() {
            info["nextRefreshTime"] = nextRefresh
            info["timeUntilNextRefresh"] = nextRefresh.timeIntervalSinceNow
            info["shouldRefreshNow"] = nextRefresh.timeIntervalSinceNow <= 0
        }
        
        if let lastCheck = lastExpiryCheck {
            info["lastExpiryCheck"] = lastCheck
            info["timeSinceLastCheck"] = Date().timeIntervalSince(lastCheck)
        }
        
        // Add retry tracking information
        info["retryCount"] = retryCount
        info["maxRetryAttempts"] = maxRetryAttempts
        
        if let lastFailure = lastFailureTime {
            info["lastFailureTime"] = lastFailure
            info["timeSinceLastFailure"] = Date().timeIntervalSince(lastFailure)
        }
        
        if retryCount > 0 {
            let nextRetryDelay = calculateExponentialBackoffDelay()
            info["nextRetryDelaySeconds"] = nextRetryDelay
        }
        
        // Add operation coordination information
        info["activePostingOperations"] = activePostingOperations.count
        info["pendingRefreshAfterPost"] = pendingRefreshAfterPost
        info["hasActiveOperations"] = hasActivePostingOperations()
        
        // Add rate limiting information
        info["minRefreshIntervalSeconds"] = minRefreshInterval
        info["rateLimitBackoffTimeSeconds"] = rateLimitBackoffTime
        
        if let lastAttempt = lastRefreshAttemptTime {
            info["lastRefreshAttemptTime"] = lastAttempt
            info["timeSinceLastRefreshAttempt"] = Date().timeIntervalSince(lastAttempt)
            info["canRefreshWithinRateLimits"] = canRefreshWithinRateLimits()
        }
        
        let nextAllowed = nextAllowedRefreshTime()
        info["nextAllowedRefreshTime"] = nextAllowed
        info["timeUntilNextAllowedRefresh"] = nextAllowed.timeIntervalSinceNow
        
        // Add rate limit manager info if available
        if let rateLimitManager = rateLimitManager {
            info["rateLimitManager_isRateLimited"] = rateLimitManager.isRateLimited
            info["rateLimitManager_shouldShowWarning"] = rateLimitManager.shouldShowWarning
            info["rateLimitManager_remainingRequests"] = rateLimitManager.rateLimitInfo.remainingRequests
            info["rateLimitManager_usagePercentage"] = rateLimitManager.rateLimitInfo.usagePercentage
            
            if let resetDate = rateLimitManager.rateLimitInfo.resetDate {
                info["rateLimitManager_resetDate"] = resetDate
                info["rateLimitManager_timeUntilReset"] = resetDate.timeIntervalSinceNow
            }
        }
        
        // Add monitoring statistics
        let monitoringStats = getRefreshMonitoringStats()
        info["monitoring_totalSuccesses"] = monitoringStats["totalSuccesses"]
        info["monitoring_totalFailures"] = monitoringStats["totalFailures"]
        info["monitoring_totalAttempts"] = monitoringStats["totalAttempts"]
        info["monitoring_successRatePercentage"] = monitoringStats["successRatePercentage"]
        
        if let lastSuccess = monitoringStats["lastSuccessTime"] as? Date {
            info["monitoring_lastSuccessTime"] = lastSuccess
            info["monitoring_timeSinceLastSuccess"] = monitoringStats["timeSinceLastSuccess"]
        }
        
        // Add rapid expiration statistics (Task 11.7)
        let rapidStats = getRapidExpirationStats()
        info["rapidExpiration_shortLivedTokenCount"] = rapidStats["shortLivedTokenCount"]
        info["rapidExpiration_pendingRequests"] = rapidStats["pendingRefreshRequests"]
        
        if let lastShortLived = rapidStats["lastShortLivedTokenTime"] as? Date {
            info["rapidExpiration_lastShortLivedTime"] = lastShortLived
            info["rapidExpiration_timeSinceLastShortLived"] = rapidStats["timeSinceLastShortLivedToken"]
        }
        
        return info
    }
    
    /// Logs current timing information for debugging
    public func logTimingInfo() async {
        let info = await getTimingInfo()
        print("🔄 TokenRefreshManager Timing Info:")
        for (key, value) in info.sorted(by: { $0.key < $1.key }) {
            if let date = value as? Date {
                print("   \(key): \(date.formatted())")
            } else if let interval = value as? TimeInterval {
                print("   \(key): \(String(format: "%.1f", interval))s")
            } else {
                print("   \(key): \(value)")
            }
        }
    }
    
    /// Resets retry tracking (useful when network conditions change or for testing)
    public func resetRetryTracking() {
        retryCount = 0
        lastFailureTime = nil
        lastRefreshAttemptTime = nil
        print("🔄 Retry tracking reset")
    }
    
    // MARK: - Rate Limiting Methods
    
    /// Checks if refresh can proceed without violating rate limits
    /// This method implements background refresh scheduling that respects API rate limits per PRD requirement 11.5
    /// - Returns: True if refresh is allowed, false if rate limited
    private func canRefreshWithinRateLimits() -> Bool {
        // Check general rate limiting against X API
        if let rateLimitManager = rateLimitManager {
            if rateLimitManager.isRateLimited {
                print("⏳ Skipping token refresh due to API rate limits")
                return false
            }
        }
        
        // Check minimum interval between refresh attempts
        if let lastAttempt = lastRefreshAttemptTime {
            let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
            if timeSinceLastAttempt < minRefreshInterval {
                let remainingTime = minRefreshInterval - timeSinceLastAttempt
                print("⏳ Skipping token refresh - minimum interval not met. Wait \(String(format: "%.1f", remainingTime))s more")
                return false
            }
        }
        
        return true
    }
    
    /// Gets the next time a refresh attempt is allowed
    /// - Returns: Date when next refresh can be attempted
    private func nextAllowedRefreshTime() -> Date {
        var nextTime = Date()
        
        // Check rate limit manager
        if let rateLimitManager = rateLimitManager, rateLimitManager.isRateLimited {
            if let resetDate = rateLimitManager.rateLimitInfo.resetDate {
                nextTime = max(nextTime, resetDate)
            } else {
                // If no reset date, use default backoff time
                nextTime = max(nextTime, Date().addingTimeInterval(rateLimitBackoffTime))
            }
        }
        
        // Check minimum refresh interval
        if let lastAttempt = lastRefreshAttemptTime {
            let minimumNextTime = lastAttempt.addingTimeInterval(minRefreshInterval)
            nextTime = max(nextTime, minimumNextTime)
        }
        
        return nextTime
    }
    
    /// Updates tracking when refresh attempt is made
    private func recordRefreshAttempt() {
        lastRefreshAttemptTime = Date()
    }
    
    /// Checks for rapid token expiration patterns (Task 11.7)
    /// - Parameter expiresIn: Token lifetime in seconds
    private func checkForRapidExpiration(expiresIn: Int) {
        let tokenLifetime = TimeInterval(expiresIn)
        
        if tokenLifetime <= shortLivedTokenThreshold {
            shortLivedTokenCount += 1
            lastShortLivedTokenTime = Date()
            
            print("⚠️ Short-lived token detected: \(expiresIn)s (\(shortLivedTokenCount) recent short-lived tokens)")
            
            // Log warning if we're getting many short-lived tokens
            if shortLivedTokenCount >= 3 {
                print("🚨 ALERT: Multiple short-lived tokens detected (\(shortLivedTokenCount)). This may indicate:")
                print("   - API configuration issues")
                print("   - Network connectivity problems")
                print("   - Server-side token policy changes")
                print("   - Client clock synchronization issues")
                
                // Reset counter to avoid spam
                if shortLivedTokenCount >= 5 {
                    shortLivedTokenCount = 0
                }
            }
        } else {
            // Reset counter on normal token lifetime
            if shortLivedTokenCount > 0 {
                print("✅ Normal token lifetime restored: \(expiresIn)s")
                shortLivedTokenCount = 0
            }
        }
    }
    
    /// Gets rapid expiration statistics for monitoring
    /// - Returns: Dictionary with rapid expiration tracking info
    public func getRapidExpirationStats() -> [String: Any] {
        var stats: [String: Any] = [:]
        
        stats["shortLivedTokenCount"] = shortLivedTokenCount
        stats["shortLivedTokenThresholdSeconds"] = shortLivedTokenThreshold
        
        if let lastShortLived = lastShortLivedTokenTime {
            stats["lastShortLivedTokenTime"] = lastShortLived
            stats["timeSinceLastShortLivedToken"] = Date().timeIntervalSince(lastShortLived)
        }
        
        stats["pendingRefreshRequests"] = pendingRefreshRequests
        
        return stats
    }
    
    /// Records a successful token refresh for monitoring (Task 11.6)
    private func recordRefreshSuccess() {
        refreshSuccessCount += 1
        lastSuccessTime = Date()
        saveMonitoringData()
        print("✅ Token refresh success recorded. Total successes: \(refreshSuccessCount)")
    }
    
    /// Records a failed token refresh for monitoring (Task 11.6)
    /// - Parameters:
    ///   - error: The error that caused the failure
    ///   - errorType: Classified error type
    private func recordRefreshFailure(_ error: Error, type errorType: RefreshErrorType) {
        refreshFailureCount += 1
        let now = Date()
        
        // Update detailed tracking by error type
        lastFailureDetailsByType[errorType] = FailureDetails(
            count: (lastFailureDetailsByType[errorType]?.count ?? 0) + 1,
            lastTime: now
        )
        
        saveMonitoringData()
        print("❌ Token refresh failure recorded. Type: \(errorType), Total failures: \(refreshFailureCount)")
    }
    
    /// Gets comprehensive refresh monitoring statistics (Task 11.6)
    /// - Returns: Dictionary with detailed success/failure statistics
    public func getRefreshMonitoringStats() -> [String: Any] {
        var stats: [String: Any] = [:]
        
        // Basic counts
        stats["totalSuccesses"] = refreshSuccessCount
        stats["totalFailures"] = refreshFailureCount
        stats["totalAttempts"] = refreshSuccessCount + refreshFailureCount
        
        // Success rate calculation
        let totalAttempts = refreshSuccessCount + refreshFailureCount
        if totalAttempts > 0 {
            stats["successRate"] = Double(refreshSuccessCount) / Double(totalAttempts)
            stats["failureRate"] = Double(refreshFailureCount) / Double(totalAttempts)
            stats["successRatePercentage"] = (Double(refreshSuccessCount) / Double(totalAttempts)) * 100.0
        } else {
            stats["successRate"] = 0.0
            stats["failureRate"] = 0.0
            stats["successRatePercentage"] = 0.0
        }
        
        // Last success/failure times
        if let lastSuccess = lastSuccessTime {
            stats["lastSuccessTime"] = lastSuccess
            stats["timeSinceLastSuccess"] = Date().timeIntervalSince(lastSuccess)
        }
        
        if let lastFailure = lastFailureTime {
            stats["lastFailureTime"] = lastFailure
            stats["timeSinceLastFailure"] = Date().timeIntervalSince(lastFailure)
        }
        
        // Detailed failure breakdown by type
        var failuresByType: [String: Any] = [:]
        for (errorType, details) in lastFailureDetailsByType {
            failuresByType["\(errorType)"] = [
                "count": details.count,
                "lastTime": details.lastTime,
                "timeSinceLast": Date().timeIntervalSince(details.lastTime)
            ]
        }
        stats["failuresByType"] = failuresByType
        
        // Rate limiting specific stats
        if let rateLimitFailures = lastFailureDetailsByType[.rateLimited] {
            stats["rateLimitFailureCount"] = rateLimitFailures.count
            stats["lastRateLimitFailure"] = rateLimitFailures.lastTime
        }
        
        // Network failure stats
        let networkErrorTypes: [RefreshErrorType] = [.networkUnavailable, .networkTimeout, .networkSecurity, .networkGeneral, .serverUnavailable]
        let networkFailureCount = networkErrorTypes.reduce(0) { total, type in
            total + (lastFailureDetailsByType[type]?.count ?? 0)
        }
        stats["networkFailureCount"] = networkFailureCount
        
        return stats
    }
    
    /// Logs detailed refresh monitoring statistics (Task 11.6)
    public func logRefreshMonitoringStats() {
        let stats = getRefreshMonitoringStats()
        
        print("🔄 Token Refresh Monitoring Statistics:")
        print("   Total Attempts: \(stats["totalAttempts"] ?? 0)")
        print("   Successes: \(stats["totalSuccesses"] ?? 0)")
        print("   Failures: \(stats["totalFailures"] ?? 0)")
        
        if let successRate = stats["successRatePercentage"] as? Double {
            print("   Success Rate: \(String(format: "%.2f", successRate))%")
        }
        
        if let lastSuccess = stats["lastSuccessTime"] as? Date {
            print("   Last Success: \(lastSuccess.formatted())")
        }
        
        if let lastFailure = stats["lastFailureTime"] as? Date {
            print("   Last Failure: \(lastFailure.formatted())")
        }
        
        // Log failure breakdown if there are failures
        if let failuresByType = stats["failuresByType"] as? [String: Any], !failuresByType.isEmpty {
            print("   Failures by Type:")
            for (type, details) in failuresByType {
                if let detailsDict = details as? [String: Any],
                   let count = detailsDict["count"] as? Int {
                    print("     \(type): \(count) failures")
                }
            }
        }
    }
    
    /// Resets monitoring statistics (useful for testing or fresh start)
    public func resetMonitoringStats() {
        refreshSuccessCount = 0
        refreshFailureCount = 0
        lastSuccessTime = nil
        lastFailureDetailsByType.removeAll()
        
        // Clear persisted data
        userDefaults.removeObject(forKey: MonitoringStorageKeys.successCount)
        userDefaults.removeObject(forKey: MonitoringStorageKeys.failureCount)
        userDefaults.removeObject(forKey: MonitoringStorageKeys.lastSuccessTime)
        userDefaults.removeObject(forKey: MonitoringStorageKeys.failureDetailsByType)
        userDefaults.set(Date(), forKey: MonitoringStorageKeys.monitoringStartTime)
        
        print("🔄 Refresh monitoring statistics reset")
    }
    
    /// Loads monitoring data from persistent storage
    private func loadMonitoringData() {
        refreshSuccessCount = userDefaults.integer(forKey: MonitoringStorageKeys.successCount)
        refreshFailureCount = userDefaults.integer(forKey: MonitoringStorageKeys.failureCount)
        lastSuccessTime = userDefaults.object(forKey: MonitoringStorageKeys.lastSuccessTime) as? Date
        
        // Load failure details by type
        if let data = userDefaults.data(forKey: MonitoringStorageKeys.failureDetailsByType),
           let decoded = try? JSONDecoder().decode([String: FailureDetails].self, from: data) {
            // Convert string keys back to RefreshErrorType
            for (key, value) in decoded {
                if let errorType = RefreshErrorType.fromString(key) {
                    lastFailureDetailsByType[errorType] = value
                }
            }
        }
        
        // Set monitoring start time if not already set
        if userDefaults.object(forKey: MonitoringStorageKeys.monitoringStartTime) == nil {
            userDefaults.set(Date(), forKey: MonitoringStorageKeys.monitoringStartTime)
        }
        
        print("📊 Loaded monitoring data: \(refreshSuccessCount) successes, \(refreshFailureCount) failures")
    }
    
    /// Saves monitoring data to persistent storage
    private func saveMonitoringData() {
        userDefaults.set(refreshSuccessCount, forKey: MonitoringStorageKeys.successCount)
        userDefaults.set(refreshFailureCount, forKey: MonitoringStorageKeys.failureCount)
        userDefaults.set(lastSuccessTime, forKey: MonitoringStorageKeys.lastSuccessTime)
        
        // Convert RefreshErrorType keys to strings for storage
        let stringKeyedFailures = Dictionary(uniqueKeysWithValues: 
            lastFailureDetailsByType.map { (key, value) in
                (key.toString(), value)
            }
        )
        if let encoded = try? JSONEncoder().encode(stringKeyedFailures) {
            userDefaults.set(encoded, forKey: MonitoringStorageKeys.failureDetailsByType)
        }
    }
    
    /// Gets monitoring period information
    /// - Returns: Start time and duration of current monitoring period
    public func getMonitoringPeriodInfo() -> (startTime: Date?, duration: TimeInterval?) {
        let startTime = userDefaults.object(forKey: MonitoringStorageKeys.monitoringStartTime) as? Date
        let duration = startTime?.timeIntervalSinceNow.magnitude
        return (startTime: startTime, duration: duration)
    }
    
    /// Logs comprehensive monitoring report with recommendations
    public func logComprehensiveMonitoringReport() {
        let stats = getRefreshMonitoringStats()
        let (startTime, duration) = getMonitoringPeriodInfo()
        
        print("📊 === TOKEN REFRESH MONITORING REPORT ===")
        
        if let start = startTime, let dur = duration {
            print("   Monitoring Period: \(start.formatted()) (\(String(format: "%.1f", dur / 3600)) hours)")
        }
        
        print("   Total Attempts: \(stats["totalAttempts"] ?? 0)")
        print("   Successes: \(stats["totalSuccesses"] ?? 0)")
        print("   Failures: \(stats["totalFailures"] ?? 0)")
        
        if let successRate = stats["successRatePercentage"] as? Double {
            print("   Success Rate: \(String(format: "%.2f", successRate))%")
            
            // Provide recommendations based on success rate
            if successRate < 90.0 {
                print("   ⚠️  RECOMMENDATION: Success rate below 90%. Investigate network/auth issues.")
            } else if successRate < 95.0 {
                print("   ⚠️  RECOMMENDATION: Success rate below 95%. Monitor for patterns.")
            } else {
                print("   ✅ RECOMMENDATION: Success rate healthy (95%+).")
            }
        }
        
        // Network failure analysis
        if let networkFailures = stats["networkFailureCount"] as? Int, networkFailures > 0 {
            let totalFailures = stats["totalFailures"] as? Int ?? 0
            if totalFailures > 0 {
                let networkPercentage = (Double(networkFailures) / Double(totalFailures)) * 100.0
                print("   Network Failures: \(networkFailures) (\(String(format: "%.1f", networkPercentage))% of failures)")
                
                if networkPercentage > 50.0 {
                    print("   ⚠️  RECOMMENDATION: High network failure rate. Check connectivity monitoring.")
                }
            }
        }
        
        // Rate limit analysis
        if let rateLimitFailures = stats["rateLimitFailureCount"] as? Int, rateLimitFailures > 0 {
            print("   Rate Limit Failures: \(rateLimitFailures)")
            print("   ⚠️  RECOMMENDATION: Rate limiting detected. Review refresh timing strategy.")
        }
        
        // Edge case analysis (Task 11.7)
        let rapidStats = getRapidExpirationStats()
        if let shortLivedCount = rapidStats["shortLivedTokenCount"] as? Int, shortLivedCount > 0 {
            print("   Short-lived Tokens: \(shortLivedCount)")
            print("   ⚠️  RECOMMENDATION: Investigate token lifetime issues.")
        }
        
        if let pendingRequests = rapidStats["pendingRefreshRequests"] as? Int, pendingRequests > 1 {
            print("   Concurrent Refresh Requests: \(pendingRequests)")
            print("   ⚠️  RECOMMENDATION: High concurrent refresh activity detected.")
        }
        
        print("   ========================================")
    }
    
    // MARK: - Operation Coordination
    
    /// Registers an active posting operation to prevent refresh interference
    /// - Returns: Operation ID to use when unregistering
    public func registerPostingOperation() -> UUID {
        let operationId = UUID()
        activePostingOperations.insert(operationId)
        print("📝 Registered posting operation \\(operationId.uuidString.prefix(8)). Active operations: \\(activePostingOperations.count)")
        return operationId
    }
    
    /// Unregisters a posting operation when complete
    /// - Parameter operationId: The operation ID returned from registerPostingOperation
    public func unregisterPostingOperation(_ operationId: UUID) {
        activePostingOperations.remove(operationId)
        print("✅ Unregistered posting operation \\(operationId.uuidString.prefix(8)). Active operations: \\(activePostingOperations.count)")
        
        // If there was a pending refresh and no more active operations, trigger it
        if pendingRefreshAfterPost && activePostingOperations.isEmpty {
            pendingRefreshAfterPost = false
            print("🔄 Triggering deferred refresh after posting operations completed")
            Task {
                await self.checkAndRefreshToken()
            }
        }
    }
    
    /// Checks if there are any active posting operations
    public func hasActivePostingOperations() -> Bool {
        return !activePostingOperations.isEmpty
    }
    
    /// Gets count of active posting operations
    public func getActivePostingCount() -> Int {
        return activePostingOperations.count
    }
    
    /// Classifies refresh errors for appropriate handling
    private func classifyRefreshError(_ error: Error) -> RefreshErrorType {
        // Check for network-specific errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .timedOut:
                return .networkTimeout
            case .cannotConnectToHost, .cannotFindHost:
                return .serverUnavailable
            case .secureConnectionFailed:
                return .networkSecurity
            default:
                return .networkGeneral
            }
        }
        
        // Check for OAuth/API errors
        if let oauthError = error as? OAuthError {
            switch oauthError {
            case .accessDenied, .invalidClientId:
                return .authenticationInvalid
            case .tokenExchangeFailed(let statusCode, _):
                if statusCode == 401 || statusCode == 403 {
                    return .authenticationInvalid
                } else if statusCode == 429 {
                    return .rateLimited
                } else if statusCode >= 500 {
                    return .serverError
                } else {
                    return .apiError
                }
            case .serverError:
                return .serverError
            case .networkError:
                return .networkGeneral
            default:
                return .unknown
            }
        }
        
        // Check for token refresh specific errors
        if let tokenRefreshError = error as? TokenRefreshError {
            switch tokenRefreshError {
            case .noRefreshToken, .refreshTokenExpired, .authenticationRequired:
                return .authenticationInvalid
            case .networkError:
                return .networkGeneral
            case .rateLimitExceeded:
                return .rateLimited
            case .serverError:
                return .serverError
            default:
                return .unknown
            }
        }
        
        return .unknown
    }
    
    /// Determines if an error indicates refresh token expiration requiring re-authentication
    private func shouldTriggerReauthentication(for error: Error) async -> Bool {
        // Check if it's a TokenRefreshError with requiresReauthentication flag
        if let tokenRefreshError = error as? TokenRefreshError {
            return tokenRefreshError.requiresReauthentication
        }
        
        // Check if it's an OAuthError from CLI component
        if let oauthError = error as? OAuthError {
            switch oauthError {
            case .accessDenied, .invalidClientId:
                return true
            case .tokenExchangeFailed(let statusCode, _):
                // 401 Unauthorized or 403 Forbidden typically indicate invalid refresh token
                return statusCode == 401 || statusCode == 403
            case .serverError(let message):
                // Check for specific refresh token error messages from X API
                let lowercaseMessage = message.lowercased()
                return lowercaseMessage.contains("invalid") && 
                       (lowercaseMessage.contains("refresh") || lowercaseMessage.contains("token"))
            default:
                return false
            }
        }
        
        // Check if we can't find a refresh token in keychain
        do {
            _ = try await keychainManager.getRefreshToken()
            return false // Refresh token exists, so it's likely a network/temporary issue
        } catch KeychainError.itemNotFound {
            return true // No refresh token found, need to re-authenticate
        } catch {
            return false // Other keychain errors are not necessarily auth issues
        }
    }
    
    // MARK: - Private Methods
    
    private func checkAndRefreshToken() async {
        guard !isRefreshing else { return }
        
        // Check if there are active posting operations that could be interrupted
        if hasActivePostingOperations() {
            print("📝 Deferring token refresh due to \\(getActivePostingCount()) active posting operation(s)")
            pendingRefreshAfterPost = true
            return
        }
        
        // Check rate limiting constraints before attempting refresh
        guard canRefreshWithinRateLimits() else {
            let nextAllowed = nextAllowedRefreshTime()
            let timeUntilAllowed = nextAllowed.timeIntervalSinceNow
            print("⏳ Token refresh blocked by rate limits. Next attempt allowed at \(nextAllowed.formatted()) (in \(String(format: "%.1f", timeUntilAllowed))s)")
            return
        }
        
        do {
            // Check if we have tokens to refresh
            guard await keychainManager.hasValidTokens() else {
                return
            }
            
            // Check if refresh is needed
            guard await shouldRefreshToken() else {
                return
            }
            
            // Record this refresh attempt for rate limiting tracking
            recordRefreshAttempt()
            
            // Perform refresh
            await performTokenRefresh()
            
        } catch {
            await handleRefreshError(error)
        }
    }
    
    @discardableResult
    private func performTokenRefresh() async -> Bool {
        guard !isRefreshing else { return false }
        
        isRefreshing = true
        await updateRefreshState(.refreshing)
        
        // Use delegate if available, otherwise fallback to mock behavior
        if let delegate = delegate {
            // Use intelligent retry if NetworkMonitor is available
            if let networkMonitor = networkMonitor {
                do {
                    let result = try await networkMonitor.performOperationWithIntelligentRetry(
                        operation: {
                            return try await self.delegateRefreshWithResult(delegate)
                        },
                        operationType: .tokenRefresh,
                        operationName: "token_refresh"
                    )
                    
                    // Handle successful refresh
                    if let expiresIn = result.expiresIn {
                        do {
                            try await storeTokenExpiration(expiresIn: expiresIn)
                        } catch {
                            print("⚠️ Failed to update token expiration: \(error)")
                        }
                    }
                    
                    await updateRefreshState(.success)
                    isRefreshing = false
                    
                    // Reset retry tracking on successful refresh
                    retryCount = 0
                    lastFailureTime = nil
                    
                    // Record success for monitoring
                    recordRefreshSuccess()
                    
                    return true
                    
                } catch {
                    // Handle refresh failure with intelligent retry
                    await handleRefreshFailure(error)
                    isRefreshing = false
                    return false
                }
                
            } else {
                // Fallback to original logic without intelligent retry
                let result = await delegate.refreshTokens()
                
                switch result {
                case .success(let tokenResponse):
                    // Update expiry tracking with new token information
                    if let expiresIn = tokenResponse.expiresIn {
                        do {
                            try await storeTokenExpiration(expiresIn: expiresIn)
                        } catch {
                            print("⚠️ Failed to update token expiration: \(error)")
                        }
                    }
                    
                    await updateRefreshState(.success)
                    isRefreshing = false
                    
                    // Reset retry tracking on successful refresh
                    retryCount = 0
                    lastFailureTime = nil
                    
                    // Record success for monitoring
                    recordRefreshSuccess()
                
                return true
                
            case .failure(let error):
                await handleRefreshError(error)
                isRefreshing = false
                return false
            }
        } else {
            // Fallback behavior for testing when no delegate is set
            do {
                // Simulate refresh process
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Simulate storing new expiry date (2 hours from now)
                try await storeTokenExpiration(expiresIn: 7200)
                
                await updateRefreshState(.success)
                isRefreshing = false
                
                // Reset retry tracking on successful refresh
                retryCount = 0
                lastFailureTime = nil
                
                // Record success for monitoring
                recordRefreshSuccess()
                
                return true
                
            } catch {
                await handleRefreshError(error)
                isRefreshing = false
                return false
            }
        }
    }
    
    private func handleRefreshError(_ error: Error) async {
        await updateRefreshState(.failure(error))
        
        // Classify the error for appropriate handling
        let errorType = classifyRefreshError(error)
        
        // Record failure for monitoring
        recordRefreshFailure(error, type: errorType)
        
        print("⚠️ Token refresh failed (\\(errorType)): \\(error)")
        
        // Handle authentication invalid errors immediately
        let shouldReauth = await shouldTriggerReauthentication(for: error)
        if errorType == .authenticationInvalid || shouldReauth {
            print("🔐 Refresh token expired or invalid. Triggering re-authentication flow.")
            
            // Clear invalid tokens from keychain
            do {
                try await keychainManager.clearAllTokens()
            } catch {
                print("⚠️ Failed to clear invalid tokens: \\(error)")
            }
            
            // Reset retry tracking since we're starting fresh
            retryCount = 0
            lastFailureTime = nil
            
            // Trigger re-authentication through delegate
            if let delegate = delegate {
                await delegate.triggerReauthentication()
            } else {
                print("⚠️ No delegate available to trigger re-authentication")
            }
            
            return
        }
        
        // Handle rate limiting with special delay
        if errorType == .rateLimited {
            print("⏳ Rate limited during token refresh. Using extended delay.")
            retryCount += 1
            lastFailureTime = Date()
            
            // Update rate limit manager if available
            if let rateLimitManager = rateLimitManager {
                Task {
                    await rateLimitManager.handleRateLimitExceeded()
                }
            }
            
            // Use longer delay for rate limiting (5 minutes)
            let rateLimitDelay: TimeInterval = rateLimitBackoffTime
            
            DispatchQueue.main.asyncAfter(deadline: .now() + rateLimitDelay) {
                Task {
                    await self.checkAndRefreshToken()
                }
            }
            return
        }
        
        // Handle network issues with adaptive retry logic
        if isNetworkError(errorType) {
            await handleNetworkError(errorType, originalError: error)
            return
        }
        
        // Handle server errors with appropriate retry logic
        if errorType == .serverError {
            await handleServerError(error)
            return
        }
        
        // For other errors, use standard exponential backoff
        await handleGeneralError(error)
    }
    
    /// Calculates exponential backoff delay based on retry count
    /// Implements the sequence: 1s, 2s, 4s, 8s, 16s, max 30s as per PRD requirements
    private func calculateExponentialBackoffDelay() -> TimeInterval {
        // Calculate exponential delay: baseDelay * 2^(retryCount-1)
        // For retryCount=1: 1s, retryCount=2: 2s, retryCount=3: 4s, etc.
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(retryCount - 1))
        
        // Cap at maximum delay
        let cappedDelay = min(exponentialDelay, maxRetryDelay)
        
        return cappedDelay
    }
    
    /// Legacy method for backward compatibility - now uses exponential backoff
    private func calculateRetryDelay() -> TimeInterval {
        return calculateExponentialBackoffDelay()
    }
    
    /// Helper method to convert delegate refresh result to throwing operation for intelligent retry
    /// - Parameter delegate: The token refresh delegate
    /// - Returns: Token response on success
    /// - Throws: Error on failure for intelligent retry handling
    private func delegateRefreshWithResult(_ delegate: TokenRefreshDelegate) async throws -> TokenResponse {
        let result = await delegate.refreshTokens()
        
        switch result {
        case .success(let tokenResponse):
            return tokenResponse
        case .failure(let error):
            throw error
        }
    }
    
    // MARK: - Specialized Error Handling
    
    /// Determines if error type is network-related
    private func isNetworkError(_ errorType: RefreshErrorType) -> Bool {
        switch errorType {
        case .networkUnavailable, .networkTimeout, .networkSecurity, .networkGeneral, .serverUnavailable:
            return true
        default:
            return false
        }
    }
    
    /// Handles network-related errors with adaptive retry logic
    private func handleNetworkError(_ errorType: RefreshErrorType, originalError: Error) async {
        retryCount += 1
        lastFailureTime = Date()
        
        // For network unavailable, use longer delays and fewer retries
        if errorType == .networkUnavailable {
            print("📡 No network connection detected. Using extended retry intervals.")
            
            if retryCount >= 3 {
                print("📡 Network still unavailable after 3 attempts. Will retry when network returns.")
                // Reset and wait for network monitor to trigger retry
                retryCount = 0
                return
            }
            
            // Use longer delays for network unavailable: 30s, 60s, 120s
            let networkDelay = TimeInterval(30 * retryCount)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + networkDelay) {
                Task {
                    await self.checkAndRefreshToken()
                }
            }
            return
        }
        
        // For timeouts, use moderate delays
        if errorType == .networkTimeout {
            print("⏱️ Network timeout detected. Using moderate retry delay.")
            
            if retryCount >= maxRetryAttempts {
                print("⏱️ Too many timeout failures. Stopping refresh attempts.")
                retryCount = 0
                return
            }
            
            // Use standard exponential backoff for timeouts
            let timeoutDelay = calculateExponentialBackoffDelay()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDelay) {
                Task {
                    await self.checkAndRefreshToken()
                }
            }
            return
        }
        
        // For other network errors, use standard retry logic
        await handleGeneralError(originalError)
    }
    
    /// Handles server errors with appropriate retry logic
    private func handleServerError(_ error: Error) async {
        retryCount += 1
        lastFailureTime = Date()
        
        print("🔧 Server error detected during token refresh.")
        
        if retryCount >= maxRetryAttempts {
            print("🔧 Too many server error failures. Stopping refresh attempts.")
            retryCount = 0
            return
        }
        
        // For server errors, use exponential backoff with longer base delay
        let serverErrorDelay = min(baseRetryDelay * 2 * pow(2.0, Double(retryCount - 1)), maxRetryDelay)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + serverErrorDelay) {
            Task {
                await self.checkAndRefreshToken()
            }
        }
    }
    
    /// Handles general errors with standard exponential backoff
    private func handleGeneralError(_ error: Error) async {
        retryCount += 1
        lastFailureTime = Date()
        
        if retryCount >= maxRetryAttempts {
            print("❌ Max retry attempts reached (\\(maxRetryAttempts)). Stopping refresh attempts.")
            retryCount = 0
            lastFailureTime = nil
            return
        }
        
        let retryDelay = calculateExponentialBackoffDelay()
        
        print("🔄 Scheduling retry in \\(String(format: \"%.1f\", retryDelay))s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            Task {
                await self.checkAndRefreshToken()
            }
        }
    }
    
    @MainActor
    private func updateRefreshState(_ newState: TokenRefreshState) {
        refreshState = newState
    }
}

// Using TokenRefreshError from AuthenticationModels.swift

// MARK: - Dictionary Extensions for Monitoring

private extension Dictionary {
    /// Maps dictionary keys using the provided transform
    func mapKeys<NewKey: Hashable>(_ transform: (Key) -> NewKey) -> [NewKey: Value] {
        return Dictionary<NewKey, Value>(uniqueKeysWithValues: self.map { (transform($0.key), $0.value) })
    }
}
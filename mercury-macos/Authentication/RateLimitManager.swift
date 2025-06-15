import Foundation
import Combine

/// Manages X API rate limit tracking and user feedback
@MainActor
public class RateLimitManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var rateLimitInfo: RateLimitInfo = .empty
    
    // MARK: - Public Publishers
    
    public var rateLimitInfoPublisher: AnyPublisher<RateLimitInfo, Never> {
        $rateLimitInfo.eraseToAnyPublisher()
    }
    
    // MARK: - Internal State
    
    private let userDefaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.mercury.ratelimit", qos: .utility)
    
    // MARK: - Configuration
    
    /// X API Free tier monthly limit
    private let monthlyLimit = 500
    
    /// Warning threshold (80% of limit)
    private let warningThreshold = 0.8
    
    // MARK: - Storage Keys
    
    private enum StorageKey {
        static let currentMonth = "mercury.ratelimit.current_month"
        static let requestCount = "mercury.ratelimit.request_count"
        static let lastResetDate = "mercury.ratelimit.last_reset"
        static let rateLimitHeaders = "mercury.ratelimit.headers"
    }
    
    // MARK: - Initialization
    
    public init() {
        loadRateLimitInfo()
        checkForMonthlyReset()
    }
    
    // MARK: - Public Properties
    
    /// Whether user is currently rate limited
    public var isRateLimited: Bool {
        return rateLimitInfo.isLimited || rateLimitInfo.remainingRequests <= 0
    }
    
    /// Whether user should be warned about approaching limit
    public var shouldShowWarning: Bool {
        return rateLimitInfo.shouldWarnUser
    }
    
    // MARK: - Public Methods
    
    /// Records a successful API request and updates rate limit info
    public func recordRequest() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.updateRequestCount()
                Task { @MainActor in
                    self.updateRateLimitInfo()
                }
                continuation.resume()
            }
        }
    }
    
    /// Updates rate limit info from HTTP response headers
    /// - Parameters:
    ///   - remaining: Remaining requests from X-Rate-Limit-Remaining header
    ///   - reset: Reset timestamp from X-Rate-Limit-Reset header
    public func updateFromHeaders(remaining: Int, reset: Date) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let newInfo = RateLimitInfo(
                    remainingRequests: remaining,
                    totalRequests: self.monthlyLimit,
                    resetDate: reset,
                    isLimited: remaining <= 0
                )
                
                Task { @MainActor in
                    self.rateLimitInfo = newInfo
                }
                self.saveRateLimitInfo()
                continuation.resume()
            }
        }
    }
    
    /// Handles HTTP 429 (Too Many Requests) response
    /// - Parameter retryAfter: Retry-After header value in seconds
    public func handleRateLimitExceeded(retryAfter: Int? = nil) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let resetDate: Date
                if let retryAfter = retryAfter {
                    resetDate = Date().addingTimeInterval(TimeInterval(retryAfter))
                } else {
                    // Default to next month if no Retry-After header
                    resetDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
                }
                
                let newInfo = RateLimitInfo(
                    remainingRequests: 0,
                    totalRequests: self.monthlyLimit,
                    resetDate: resetDate,
                    isLimited: true
                )
                
                Task { @MainActor in
                    self.rateLimitInfo = newInfo
                }
                self.saveRateLimitInfo()
                continuation.resume()
            }
        }
    }
    
    /// Gets current usage statistics
    /// - Returns: Usage information for display
    public func getUsageStats() -> (used: Int, remaining: Int, percentage: Double) {
        let used = monthlyLimit - rateLimitInfo.remainingRequests
        let remaining = rateLimitInfo.remainingRequests
        let percentage = rateLimitInfo.usagePercentage
        
        return (used: used, remaining: remaining, percentage: percentage)
    }
    
    /// Checks if a request can be made without exceeding limits
    /// - Returns: True if request is allowed
    public func canMakeRequest() -> Bool {
        return !isRateLimited
    }
    
    /// Gets user-friendly status message
    /// - Returns: Description of current rate limit status
    public func getStatusMessage() -> String {
        return rateLimitInfo.statusDescription
    }
    
    /// Resets rate limit info (useful for testing or manual reset)
    public func resetRateLimit() async {
        await withCheckedContinuation { continuation in
            queue.async {
                let newInfo = RateLimitInfo(
                    remainingRequests: self.monthlyLimit,
                    totalRequests: self.monthlyLimit,
                    resetDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                    isLimited: false
                )
                
                Task { @MainActor in
                    self.rateLimitInfo = newInfo
                }
                self.saveCurrentMonth()
                self.saveRateLimitInfo()
                continuation.resume()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadRateLimitInfo() {
        queue.async {
            let requestCount = self.userDefaults.integer(forKey: StorageKey.requestCount)
            let remainingRequests = max(0, self.monthlyLimit - requestCount)
            let resetDate = self.getNextMonthResetDate()
            
            Task { @MainActor in
                self.rateLimitInfo = RateLimitInfo(
                    remainingRequests: remainingRequests,
                    totalRequests: self.monthlyLimit,
                    resetDate: resetDate,
                    isLimited: remainingRequests <= 0
                )
            }
        }
    }
    
    private func updateRequestCount() {
        let currentCount = userDefaults.integer(forKey: StorageKey.requestCount)
        userDefaults.set(currentCount + 1, forKey: StorageKey.requestCount)
    }
    
    @MainActor
    private func updateRateLimitInfo() {
        let requestCount = userDefaults.integer(forKey: StorageKey.requestCount)
        let remainingRequests = max(0, monthlyLimit - requestCount)
        
        rateLimitInfo = RateLimitInfo(
            remainingRequests: remainingRequests,
            totalRequests: monthlyLimit,
            resetDate: getNextMonthResetDate(),
            isLimited: remainingRequests <= 0
        )
        
        saveRateLimitInfo()
    }
    
    private func checkForMonthlyReset() {
        queue.async {
            let currentMonth = self.getCurrentMonthIdentifier()
            let storedMonth = self.userDefaults.string(forKey: StorageKey.currentMonth)
            
            if storedMonth != currentMonth {
                // New month - reset counters
                self.userDefaults.set(0, forKey: StorageKey.requestCount)
                self.saveCurrentMonth()
                
                let newInfo = RateLimitInfo(
                    remainingRequests: self.monthlyLimit,
                    totalRequests: self.monthlyLimit,
                    resetDate: self.getNextMonthResetDate(),
                    isLimited: false
                )
                
                Task { @MainActor in
                    self.rateLimitInfo = newInfo
                }
                self.saveRateLimitInfo()
            }
        }
    }
    
    private func getCurrentMonthIdentifier() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }
    
    private func saveCurrentMonth() {
        userDefaults.set(getCurrentMonthIdentifier(), forKey: StorageKey.currentMonth)
    }
    
    private func getNextMonthResetDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        // Get first day of next month
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now),
              let firstOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) else {
            return calendar.date(byAdding: .day, value: 30, to: now) ?? now
        }
        
        return firstOfNextMonth
    }
    
    private func saveRateLimitInfo() {
        // Store rate limit info for persistence
        if let data = try? JSONEncoder().encode(rateLimitInfo) {
            userDefaults.set(data, forKey: StorageKey.rateLimitHeaders)
        }
    }
}

// MARK: - Rate Limit Extensions

extension RateLimitInfo {
    /// Warning message for approaching rate limit
    var warningMessage: String? {
        guard shouldWarnUser else { return nil }
        
        let used = totalRequests - remainingRequests
        return "You've used \(used) of \(totalRequests) posts this month. Consider upgrading for unlimited posting."
    }
    
    /// Critical message for rate limit exceeded
    var criticalMessage: String? {
        guard isLimited else { return nil }
        
        if let resetDate = resetDate {
            return "Monthly post limit reached. Limit resets \(resetDate.formatted(.relative(presentation: .named)))."
        } else {
            return "Monthly post limit reached. Please try again later."
        }
    }
}
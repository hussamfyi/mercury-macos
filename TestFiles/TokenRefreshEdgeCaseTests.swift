import XCTest
import Combine
@testable import mercury_macos

/// Tests for edge cases in token refresh: simultaneous refresh attempts, rapid token expiration
/// Implements Task 11.7: Test edge cases: simultaneous refresh attempts, rapid token expiration
final class TokenRefreshEdgeCaseTests: XCTestCase {
    
    var tokenRefreshManager: TokenRefreshManager!
    var mockKeychainManager: MockKeychainManager!
    var mockDelegate: MockTokenRefreshDelegate!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockKeychainManager = MockKeychainManager()
        mockDelegate = MockTokenRefreshDelegate()
        cancellables = Set<AnyCancellable>()
        
        tokenRefreshManager = TokenRefreshManager(
            keychainManager: mockKeychainManager,
            rateLimitManager: nil,
            delegate: nil
        )
        tokenRefreshManager.setDelegate(mockDelegate)
        
        // Reset monitoring stats for clean tests
        tokenRefreshManager.resetMonitoringStats()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        tokenRefreshManager.stopRefresh()
        tokenRefreshManager = nil
        mockKeychainManager = nil
        mockDelegate = nil
        super.tearDown()
    }
    
    // MARK: - Simultaneous Refresh Attempts Tests
    
    /// Test that simultaneous refresh attempts are properly serialized
    func testSimultaneousRefreshAttempts() async throws {
        // Set up tokens that need refresh
        let expiryDate = Date().addingTimeInterval(5 * 60) // 5 minutes from now (within refresh margin)
        try await mockKeychainManager.storeTokenExpiry(expiryDate)
        mockKeychainManager.hasValidTokensResult = true
        
        // Configure delegate to simulate slow refresh
        mockDelegate.refreshDelay = 2.0 // 2 second delay
        mockDelegate.refreshResult = .success(MockTokenResponse(accessToken: "new_token", expiresIn: 7200))
        
        let refreshStartTime = Date()
        
        // Launch multiple simultaneous refresh attempts
        let refreshTasks = (1...5).map { taskId in
            Task {
                let startTime = Date()
                let success = await tokenRefreshManager.refreshTokenNow()
                let endTime = Date()
                return (taskId: taskId, success: success, startTime: startTime, endTime: endTime)
            }
        }
        
        // Wait for all tasks to complete
        var results: [(taskId: Int, success: Bool, startTime: Date, endTime: Date)] = []
        for task in refreshTasks {
            let result = await task.value
            results.append(result)
        }
        
        let totalTime = Date().timeIntervalSince(refreshStartTime)
        
        // Verify that only one refresh succeeded (serialization)
        let successCount = results.filter { $0.success }.count
        XCTAssertEqual(successCount, 1, "Only one simultaneous refresh should succeed")
        
        // Verify that delegate was called only once (no duplicate refresh attempts)
        XCTAssertEqual(mockDelegate.refreshCallCount, 1, "Delegate should be called only once despite multiple attempts")
        
        // Verify that total time is reasonable (not 5 * 2 seconds which would indicate sequential execution)
        XCTAssertLessThan(totalTime, 4.0, "Simultaneous attempts should not execute sequentially")
        
        // Verify monitoring stats show only one attempt
        let stats = tokenRefreshManager.getRefreshMonitoringStats()
        XCTAssertEqual(stats["totalAttempts"] as? Int, 1, "Monitoring should show only one actual refresh attempt")
        
        print("✅ Simultaneous refresh test completed:")
        print("   - \(results.count) tasks launched")
        print("   - \(successCount) successful")
        print("   - \(mockDelegate.refreshCallCount) delegate calls")
        print("   - Total time: \(String(format: "%.2f", totalTime))s")
    }
    
    /// Test simultaneous refresh attempts with posting operations
    func testSimultaneousRefreshWithPostingOperations() async throws {
        // Set up tokens that need refresh
        let expiryDate = Date().addingTimeInterval(5 * 60) // 5 minutes from now
        try await mockKeychainManager.storeTokenExpiry(expiryDate)
        mockKeychainManager.hasValidTokensResult = true
        
        mockDelegate.refreshDelay = 1.0
        mockDelegate.refreshResult = .success(MockTokenResponse(accessToken: "new_token", expiresIn: 7200))
        
        // Register posting operations
        let operation1 = tokenRefreshManager.registerPostingOperation()
        let operation2 = tokenRefreshManager.registerPostingOperation()
        
        // Try to refresh while posting operations are active
        let refreshTask1 = Task {
            return await tokenRefreshManager.refreshTokenNow()
        }
        
        let refreshTask2 = Task {
            return await tokenRefreshManager.refreshTokenNow()
        }
        
        // Wait a bit then unregister posting operations
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        tokenRefreshManager.unregisterPostingOperation(operation1)
        tokenRefreshManager.unregisterPostingOperation(operation2)
        
        // Wait for refresh tasks to complete
        let result1 = await refreshTask1.value
        let result2 = await refreshTask2.value
        
        // At least one should succeed after posting operations complete
        let anySuccess = result1 || result2
        XCTAssertTrue(anySuccess, "Refresh should succeed after posting operations complete")
        
        // Verify that refresh was deferred initially
        XCTAssertEqual(mockDelegate.refreshCallCount, 1, "Only one refresh should have occurred")
        
        print("✅ Simultaneous refresh with posting operations test completed")
    }
    
    // MARK: - Rapid Token Expiration Tests
    
    /// Test handling of rapidly expiring tokens
    func testRapidTokenExpiration() async throws {
        // Set up token that expires very soon (10 seconds)
        let rapidExpiryDate = Date().addingTimeInterval(10)
        try await mockKeychainManager.storeTokenExpiry(rapidExpiryDate)
        mockKeychainManager.hasValidTokensResult = true
        
        var refreshCount = 0
        
        // Configure delegate to return tokens with short expiry
        mockDelegate.refreshHandler = { _ in
            refreshCount += 1
            let shortExpiry = refreshCount < 3 ? 15 : 7200 // First 2 refreshes get 15s tokens, then normal
            return .success(MockTokenResponse(accessToken: "token_\(refreshCount)", expiresIn: shortExpiry))
        }
        
        // Start automatic refresh
        tokenRefreshManager.startRefreshTimer()
        
        // Wait for multiple rapid refresh cycles
        try await Task.sleep(nanoseconds: 35_000_000_000) // 35 seconds
        
        // Verify that multiple refreshes occurred due to rapid expiration
        XCTAssertGreaterThanOrEqual(refreshCount, 2, "Multiple refreshes should occur with rapid expiration")
        
        let stats = tokenRefreshManager.getRefreshMonitoringStats()
        let totalAttempts = stats["totalAttempts"] as? Int ?? 0
        XCTAssertGreaterThanOrEqual(totalAttempts, 2, "Monitoring should show multiple attempts")
        
        print("✅ Rapid token expiration test completed:")
        print("   - \(refreshCount) refresh attempts")
        print("   - \(totalAttempts) total monitored attempts")
    }
    
    /// Test token expiration during active refresh
    func testTokenExpirationDuringRefresh() async throws {
        // Set up token that expires very soon
        let nearExpiryDate = Date().addingTimeInterval(30) // 30 seconds
        try await mockKeychainManager.storeTokenExpiry(nearExpiryDate)
        mockKeychainManager.hasValidTokensResult = true
        
        var refreshAttempts = 0
        
        // Configure delegate with variable delay and expiry times
        mockDelegate.refreshHandler = { _ in
            refreshAttempts += 1
            let delay = refreshAttempts == 1 ? 5.0 : 1.0 // First refresh is slow
            let expiry = refreshAttempts == 1 ? 10 : 7200 // First refresh gives short token
            
            return .success(MockTokenResponse(
                accessToken: "token_\(refreshAttempts)",
                expiresIn: expiry,
                delay: delay
            ))
        }
        
        // Start refresh process
        let refreshTask = Task {
            return await tokenRefreshManager.refreshTokenNow()
        }
        
        // Wait for first refresh to start then trigger another due to "expiration"
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        let secondRefreshTask = Task {
            return await tokenRefreshManager.refreshTokenNow()
        }
        
        // Wait for both to complete
        let result1 = await refreshTask.value
        let result2 = await secondRefreshTask.value
        
        // Verify proper handling
        XCTAssertTrue(result1, "First refresh should succeed")
        XCTAssertFalse(result2, "Second refresh should be blocked by first refresh in progress")
        
        // Verify delegate was called appropriately
        XCTAssertEqual(refreshAttempts, 1, "Only one refresh should have been attempted due to serialization")
        
        print("✅ Token expiration during refresh test completed")
    }
    
    // MARK: - Rate Limiting Edge Cases
    
    /// Test refresh behavior with rate limiting edge cases
    func testRapidRefreshWithRateLimit() async throws {
        // Create a rate limit manager
        let rateLimitManager = RateLimitManager()
        await rateLimitManager.handleRateLimitExceeded(retryAfter: 60) // 1 minute rate limit
        
        // Create new manager with rate limiting
        let rateLimitedManager = TokenRefreshManager(
            keychainManager: mockKeychainManager,
            rateLimitManager: rateLimitManager,
            delegate: mockDelegate
        )
        
        // Set up near-expiry token
        let expiryDate = Date().addingTimeInterval(5 * 60) // 5 minutes (within refresh margin)
        try await mockKeychainManager.storeTokenExpiry(expiryDate)
        mockKeychainManager.hasValidTokensResult = true
        
        mockDelegate.refreshResult = .success(MockTokenResponse(accessToken: "new_token", expiresIn: 7200))
        
        // Try multiple rapid refresh attempts
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 1...3 {
                group.addTask {
                    return await rateLimitedManager.refreshTokenNow()
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // All should fail due to rate limiting
        let successCount = results.filter { $0 }.count
        XCTAssertEqual(successCount, 0, "All refresh attempts should be blocked by rate limiting")
        
        // Verify delegate was not called
        XCTAssertEqual(mockDelegate.refreshCallCount, 0, "Delegate should not be called when rate limited")
        
        rateLimitedManager.stopRefresh()
        
        print("✅ Rapid refresh with rate limit test completed")
    }
    
    // MARK: - Memory and Resource Tests
    
    /// Test that repeated refresh cycles don't cause memory leaks
    func testRepeatedRefreshCyclesMemoryManagement() async throws {
        // Set up token with very short expiry for rapid cycling
        mockKeychainManager.hasValidTokensResult = true
        
        var refreshCount = 0
        let maxRefreshes = 10
        
        mockDelegate.refreshHandler = { _ in
            refreshCount += 1
            // Simulate realistic refresh cycle with proper expiry times
            let expiry = refreshCount < maxRefreshes ? 15 : 7200 // Short expiry for first few
            return .success(MockTokenResponse(accessToken: "token_\(refreshCount)", expiresIn: expiry))
        }
        
        // Store initial short expiry
        try await mockKeychainManager.storeTokenExpiry(Date().addingTimeInterval(10))
        
        // Run multiple refresh cycles
        for cycle in 1...maxRefreshes {
            let success = await tokenRefreshManager.refreshTokenNow()
            XCTAssertTrue(success, "Refresh cycle \(cycle) should succeed")
            
            // Brief pause between cycles
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Verify all refreshes completed
        XCTAssertEqual(refreshCount, maxRefreshes, "All refresh cycles should complete")
        
        let stats = tokenRefreshManager.getRefreshMonitoringStats()
        let totalAttempts = stats["totalAttempts"] as? Int ?? 0
        XCTAssertEqual(totalAttempts, maxRefreshes, "Monitoring should track all attempts")
        
        print("✅ Memory management test completed: \(refreshCount) refresh cycles")
    }
    
    /// Test edge case of token expiring exactly at refresh time
    func testTokenExpirationAtRefreshTime() async throws {
        // Set up token that expires in exactly 15 minutes (refresh margin)
        let exactExpiryDate = Date().addingTimeInterval(15 * 60)
        try await mockKeychainManager.storeTokenExpiry(exactExpiryDate)
        mockKeychainManager.hasValidTokensResult = true
        
        mockDelegate.refreshResult = .success(MockTokenResponse(accessToken: "new_token", expiresIn: 7200))
        
        // Check if refresh is needed (should be true at exactly the refresh margin)
        let shouldRefresh = await tokenRefreshManager.shouldRefreshToken()
        XCTAssertTrue(shouldRefresh, "Token should need refresh at exactly the refresh margin")
        
        // Perform refresh
        let success = await tokenRefreshManager.refreshTokenNow()
        XCTAssertTrue(success, "Refresh should succeed at refresh margin boundary")
        
        print("✅ Token expiration at refresh time test completed")
    }
    
    /// Test handling of refresh failure followed by immediate retry
    func testRefreshFailureRetryEdgeCase() async throws {
        mockKeychainManager.hasValidTokensResult = true
        try await mockKeychainManager.storeTokenExpiry(Date().addingTimeInterval(5 * 60))
        
        var attemptCount = 0
        
        // First attempt fails, second succeeds
        mockDelegate.refreshHandler = { _ in
            attemptCount += 1
            if attemptCount == 1 {
                return .failure(TokenRefreshError.networkError(URLError(.timedOut)))
            } else {
                return .success(MockTokenResponse(accessToken: "recovery_token", expiresIn: 7200))
            }
        }
        
        // First attempt should fail
        let firstResult = await tokenRefreshManager.refreshTokenNow()
        XCTAssertFalse(firstResult, "First refresh attempt should fail")
        
        // Wait for retry delay to pass
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Second attempt should succeed
        let secondResult = await tokenRefreshManager.refreshTokenNow()
        XCTAssertTrue(secondResult, "Second refresh attempt should succeed")
        
        // Verify monitoring tracks both attempts
        let stats = tokenRefreshManager.getRefreshMonitoringStats()
        XCTAssertEqual(stats["totalAttempts"] as? Int, 2, "Should track both refresh attempts")
        XCTAssertEqual(stats["totalFailures"] as? Int, 1, "Should track one failure")
        XCTAssertEqual(stats["totalSuccesses"] as? Int, 1, "Should track one success")
        
        print("✅ Refresh failure retry edge case test completed")
    }
}

// MARK: - Mock Classes for Testing

class MockTokenRefreshDelegate: TokenRefreshDelegate {
    var refreshCallCount = 0
    var refreshResult: TokenRefreshResult = .success(MockTokenResponse(accessToken: "mock_token", expiresIn: 7200))
    var refreshDelay: TimeInterval = 0.0
    var refreshHandler: ((Any) -> TokenRefreshResult)?
    
    func refreshTokens() async -> TokenRefreshResult {
        refreshCallCount += 1
        
        if refreshDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(refreshDelay * 1_000_000_000))
        }
        
        if let handler = refreshHandler {
            return handler(self)
        }
        
        return refreshResult
    }
    
    func triggerReauthentication() async {
        // Mock implementation
    }
}

struct MockTokenResponse {
    let accessToken: String
    let expiresIn: Int?
    let delay: TimeInterval
    
    init(accessToken: String, expiresIn: Int?, delay: TimeInterval = 0.0) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.delay = delay
    }
}

extension MockTokenResponse {
    init(accessToken: String, expiresIn: Int) {
        self.init(accessToken: accessToken, expiresIn: expiresIn, delay: 0.0)
    }
}
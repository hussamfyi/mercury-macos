import XCTest
import Network
import Combine
@testable import mercury_macos

/// Tests for intelligent retry strategies and connection quality detection
@MainActor
final class NetworkIntelligentRetryTests: XCTestCase {
    
    var networkMonitor: NetworkMonitor!
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        super.setUp()
        networkMonitor = NetworkMonitor()
        authManager = await AuthManager()
        keychainManager = KeychainManager()
        cancellables = Set<AnyCancellable>()
        
        // Clean up any existing test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
    }
    
    override func tearDown() {
        // Clean up test tokens
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
        
        cancellables = nil
        networkMonitor = nil
        authManager = nil
        keychainManager = nil
        super.tearDown()
    }
    
    // MARK: - Connection Quality Detection Tests
    
    func testConnectionQualityDetection() async throws {
        // Start network monitoring
        networkMonitor.startMonitoring()
        
        // Wait for initial connection state
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Test connection quality check
        let quality = await networkMonitor.checkConnectionQuality()
        
        // Should return a valid quality level
        XCTAssertTrue([ConnectionQuality.none, .poor, .fair, .good, .excellent].contains(quality),
                     "Should return a valid connection quality")
        
        networkMonitor.stopMonitoring()
    }
    
    func testConnectionQualityBasedRetryStrategy() async throws {
        // Test retry strategy for different connection qualities
        let excellentStrategy = ConnectionQuality.excellent.retryStrategy
        let poorStrategy = ConnectionQuality.poor.retryStrategy
        let noneStrategy = ConnectionQuality.none.retryStrategy
        
        // Excellent connection should be aggressive
        XCTAssertEqual(excellentStrategy, .aggressive, "Excellent connection should use aggressive retry")
        XCTAssertEqual(excellentStrategy.maxRetries, 5, "Aggressive should allow 5 retries")
        XCTAssertEqual(excellentStrategy.baseDelay, 1.0, "Aggressive should have 1s base delay")
        
        // Poor connection should be conservative
        XCTAssertEqual(poorStrategy, .conservative, "Poor connection should use conservative retry")
        XCTAssertEqual(poorStrategy.maxRetries, 2, "Conservative should allow 2 retries")
        XCTAssertEqual(poorStrategy.baseDelay, 5.0, "Conservative should have 5s base delay")
        
        // No connection should be conservative
        XCTAssertEqual(noneStrategy, .conservative, "No connection should use conservative retry")
    }
    
    func testExponentialBackoffCalculation() {
        let moderateStrategy = RetryStrategy.moderate
        
        // Test exponential backoff calculation
        let delay0 = moderateStrategy.delayForAttempt(0)
        let delay1 = moderateStrategy.delayForAttempt(1)
        let delay2 = moderateStrategy.delayForAttempt(2)
        let delay3 = moderateStrategy.delayForAttempt(3)
        
        XCTAssertEqual(delay0, 2.0, "First attempt should use base delay")
        XCTAssertEqual(delay1, 4.0, "Second attempt should double the delay")
        XCTAssertEqual(delay2, 8.0, "Third attempt should quadruple the delay")
        XCTAssertEqual(delay3, 16.0, "Fourth attempt should continue exponential growth")
        
        // Test maximum delay cap
        let delayMax = moderateStrategy.delayForAttempt(10)
        XCTAssertEqual(delayMax, 60.0, "Delay should be capped at 60 seconds")
    }
    
    // MARK: - Error-Based Retry Decision Tests
    
    func testNetworkErrorRetryDecisions() {
        let moderateStrategy = RetryStrategy.moderate
        
        // Test different URLError scenarios
        let timeoutError = URLError(.timedOut)
        let networkLostError = URLError(.networkConnectionLost)
        let notConnectedError = URLError(.notConnectedToInternet)
        let badServerError = URLError(.badServerResponse)
        let cannotConnectError = URLError(.cannotConnectToHost)
        
        // These should be retryable
        XCTAssertTrue(moderateStrategy.shouldRetryError(timeoutError, connectionQuality: .good),
                     "Timeout errors should be retryable with good connection")
        XCTAssertTrue(moderateStrategy.shouldRetryError(networkLostError, connectionQuality: .fair),
                     "Network lost errors should be retryable")
        XCTAssertTrue(moderateStrategy.shouldRetryError(notConnectedError, connectionQuality: .poor),
                     "Not connected errors should be retryable")
        
        // These should not be retryable
        XCTAssertFalse(moderateStrategy.shouldRetryError(badServerError, connectionQuality: .excellent),
                      "Bad server response should not be retryable")
        
        // Connection-dependent retries
        XCTAssertFalse(moderateStrategy.shouldRetryError(cannotConnectError, connectionQuality: .none),
                      "Cannot connect should not retry with no connection")
        XCTAssertTrue(moderateStrategy.shouldRetryError(cannotConnectError, connectionQuality: .good),
                     "Cannot connect should retry with good connection")
    }
    
    func testAuthenticationErrorRetryDecisions() {
        let aggressiveStrategy = RetryStrategy.aggressive
        
        // Create mock errors with authentication-related descriptions
        let networkAuthError = MockError(description: "Authentication network error")
        let rateLimitError = MockError(description: "Rate limited authentication")
        let invalidTokenError = MockError(description: "Invalid authentication token")
        let expiredTokenError = MockError(description: "Expired authentication credentials")
        let cancelledError = MockError(description: "Authentication cancelled by user")
        
        // Network auth errors should be retryable
        XCTAssertTrue(aggressiveStrategy.shouldRetryError(networkAuthError, connectionQuality: .good),
                     "Network authentication errors should be retryable")
        
        // Rate limit errors should not be retryable
        XCTAssertFalse(aggressiveStrategy.shouldRetryError(rateLimitError, connectionQuality: .excellent),
                      "Rate limit errors should not be retryable")
        
        // Invalid/expired token errors should not be retryable
        XCTAssertFalse(aggressiveStrategy.shouldRetryError(invalidTokenError, connectionQuality: .good),
                      "Invalid token errors should not be retryable")
        XCTAssertFalse(aggressiveStrategy.shouldRetryError(expiredTokenError, connectionQuality: .good),
                      "Expired token errors should not be retryable")
        
        // Cancelled errors should not be retryable
        XCTAssertFalse(aggressiveStrategy.shouldRetryError(cancelledError, connectionQuality: .excellent),
                      "Cancelled authentication should not be retryable")
    }
    
    // MARK: - Intelligent Retry Operation Tests
    
    func testIntelligentRetryWithSuccessfulOperation() async throws {
        networkMonitor.startMonitoring()
        
        var attemptCount = 0
        let successfulOperation: () async throws -> String = {
            attemptCount += 1
            return "Success on attempt \(attemptCount)"
        }
        
        let result = try await networkMonitor.performOperationWithIntelligentRetry(
            operation: successfulOperation,
            operationType: .posting,
            operationName: "test_success_operation"
        )
        
        XCTAssertEqual(result, "Success on attempt 1", "Should succeed on first attempt")
        XCTAssertEqual(attemptCount, 1, "Should only attempt once for successful operation")
        
        networkMonitor.stopMonitoring()
    }
    
    func testIntelligentRetryWithRetryableFailure() async throws {
        networkMonitor.startMonitoring()
        
        var attemptCount = 0
        let retryableOperation: () async throws -> String = {
            attemptCount += 1
            if attemptCount < 3 {
                throw URLError(.timedOut) // Retryable error
            }
            return "Success on attempt \(attemptCount)"
        }
        
        let result = try await networkMonitor.performOperationWithIntelligentRetry(
            operation: retryableOperation,
            operationType: .authentication,
            operationName: "test_retryable_operation"
        )
        
        XCTAssertEqual(result, "Success on attempt 3", "Should succeed after retries")
        XCTAssertEqual(attemptCount, 3, "Should attempt 3 times before success")
        
        networkMonitor.stopMonitoring()
    }
    
    func testIntelligentRetryWithNonRetryableFailure() async throws {
        networkMonitor.startMonitoring()
        
        var attemptCount = 0
        let nonRetryableOperation: () async throws -> String = {
            attemptCount += 1
            throw URLError(.badServerResponse) // Non-retryable error
        }
        
        do {
            _ = try await networkMonitor.performOperationWithIntelligentRetry(
                operation: nonRetryableOperation,
                operationType: .posting,
                operationName: "test_non_retryable_operation"
            )
            XCTFail("Should throw error for non-retryable failure")
        } catch {
            XCTAssertEqual(attemptCount, 1, "Should only attempt once for non-retryable error")
            XCTAssertTrue(error is URLError, "Should preserve original error type")
        }
        
        networkMonitor.stopMonitoring()
    }
    
    func testIntelligentRetryWithMaxRetriesExceeded() async throws {
        networkMonitor.startMonitoring()
        
        var attemptCount = 0
        let alwaysFailingOperation: () async throws -> String = {
            attemptCount += 1
            throw URLError(.timedOut) // Always fail with retryable error
        }
        
        do {
            _ = try await networkMonitor.performOperationWithIntelligentRetry(
                operation: alwaysFailingOperation,
                operationType: .tokenRefresh,
                operationName: "test_max_retries_operation"
            )
            XCTFail("Should throw error after max retries exceeded")
        } catch {
            // Should attempt initial + max retries based on connection quality
            let expectedMaxAttempts = await networkMonitor.checkConnectionQuality().retryStrategy.maxRetries + 1
            XCTAssertEqual(attemptCount, expectedMaxAttempts, "Should attempt initial + max retries")
        }
        
        networkMonitor.stopMonitoring()
    }
    
    // MARK: - Network Advice and Operation Suitability Tests
    
    func testOperationSuitabilityChecks() async throws {
        networkMonitor.startMonitoring()
        try await Task.sleep(nanoseconds: 200_000_000) // Wait for initial state
        
        // Test with connected state
        if networkMonitor.isConnected {
            XCTAssertTrue(networkMonitor.shouldAttemptOperation(.authentication),
                         "Should allow authentication when connected")
            XCTAssertTrue(networkMonitor.shouldAttemptOperation(.posting),
                         "Should allow posting when connected")
            XCTAssertTrue(networkMonitor.shouldAttemptOperation(.tokenRefresh),
                         "Should allow token refresh when connected")
        }
        
        // Simulate disconnected state for testing
        // Note: In a real test, you'd use dependency injection to control network state
        
        networkMonitor.stopMonitoring()
    }
    
    func testNetworkAdviceGeneration() async throws {
        // Test advice for different scenarios
        // Note: This test would need to mock network states to be fully effective
        
        let authAdvice = networkMonitor.getNetworkAdvice(for: .authentication)
        let postAdvice = networkMonitor.getNetworkAdvice(for: .posting)
        let refreshAdvice = networkMonitor.getNetworkAdvice(for: .tokenRefresh)
        
        // When connected, should return nil (no advice needed)
        if networkMonitor.isConnected {
            XCTAssertNil(authAdvice, "Should not provide advice when connected")
            XCTAssertNil(postAdvice, "Should not provide advice when connected")
            XCTAssertNil(refreshAdvice, "Should not provide advice when connected")
        }
    }
    
    // MARK: - Timeout Configuration Tests
    
    func testOperationTimeoutConfiguration() {
        // Test different operation types have appropriate timeouts
        let authTimeout = networkMonitor.getTimeoutForOperation(.authentication)
        let postTimeout = networkMonitor.getTimeoutForOperation(.posting)
        let refreshTimeout = networkMonitor.getTimeoutForOperation(.tokenRefresh)
        let generalTimeout = networkMonitor.getTimeoutForOperation(.general)
        
        // Verify PRD requirements are met
        XCTAssertGreaterThanOrEqual(authTimeout, 30.0, "Auth timeout should be at least 30s per PRD")
        XCTAssertGreaterThanOrEqual(postTimeout, 10.0, "Post timeout should be at least 10s per PRD")
        XCTAssertGreaterThan(refreshTimeout, 0, "Refresh timeout should be positive")
        XCTAssertGreaterThan(generalTimeout, 0, "General timeout should be positive")
        
        // Verify timeout relationships
        XCTAssertLessThan(refreshTimeout, authTimeout, "Refresh should be faster than full auth")
    }
    
    func testURLRequestTimeoutConfiguration() {
        let authURL = URL(string: "https://api.x.com/2/oauth2/token")!
        let postURL = URL(string: "https://api.x.com/2/tweets")!
        
        let authRequest = networkMonitor.createRequest(url: authURL, operationType: .authentication)
        let postRequest = networkMonitor.createRequest(url: postURL, operationType: .posting)
        
        XCTAssertGreaterThanOrEqual(authRequest.timeoutInterval, 30.0,
                                   "Auth request should have appropriate timeout")
        XCTAssertGreaterThanOrEqual(postRequest.timeoutInterval, 10.0,
                                   "Post request should have appropriate timeout")
    }
    
    func testSessionConfigurationTimeouts() {
        let authConfig = networkMonitor.createSessionConfiguration(operationType: .authentication)
        let postConfig = networkMonitor.createSessionConfiguration(operationType: .posting)
        
        XCTAssertGreaterThanOrEqual(authConfig.timeoutIntervalForRequest, 30.0,
                                   "Auth session should have appropriate request timeout")
        XCTAssertGreaterThanOrEqual(postConfig.timeoutIntervalForRequest, 10.0,
                                   "Post session should have appropriate request timeout")
        
        // Resource timeout should be 2x request timeout
        XCTAssertEqual(authConfig.timeoutIntervalForResource, 
                      authConfig.timeoutIntervalForRequest * 2,
                      "Resource timeout should be 2x request timeout")
    }
    
    // MARK: - Connection Quality Waiting Tests
    
    func testWaitForGoodConnection() async throws {
        networkMonitor.startMonitoring()
        
        // Test waiting for good connection with short timeout
        let startTime = Date()
        let connectionAvailable = await networkMonitor.waitForGoodConnection(timeout: 2.0)
        let elapsed = Date().timeIntervalSince(startTime)
        
        if connectionAvailable {
            XCTAssertLessThan(elapsed, 2.0, "Should return quickly if connection is already good")
        } else {
            XCTAssertGreaterThanOrEqual(elapsed, 2.0, "Should timeout after specified duration")
        }
        
        networkMonitor.stopMonitoring()
    }
    
    func testWaitForConnection() async throws {
        networkMonitor.startMonitoring()
        
        // Test basic connection waiting
        let startTime = Date()
        let connectionAvailable = await networkMonitor.waitForConnection(timeout: 1.0)
        let elapsed = Date().timeIntervalSince(startTime)
        
        if networkMonitor.isConnected {
            XCTAssertTrue(connectionAvailable, "Should return true if already connected")
            XCTAssertLessThan(elapsed, 1.0, "Should return immediately if connected")
        }
        
        networkMonitor.stopMonitoring()
    }
    
    // MARK: - Integration Tests with Authentication Manager
    
    func testAuthManagerNetworkIntegration() async throws {
        // Set up valid tokens for testing
        let mockAccessToken = "integration_test_token"
        let mockRefreshToken = "integration_test_refresh"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(mockRefreshToken)
        
        // Test authentication state with network considerations
        XCTAssertTrue(authManager.isAuthenticated, "Should be authenticated with stored tokens")
        
        // Test posting with network intelligence
        let postResult = await authManager.postTweet("Network integration test post")
        
        // Result depends on actual network state and mock implementation
        switch postResult {
        case .success(let response):
            print("✅ Post succeeded: \(response)")
        case .failure(let error):
            print("ℹ️ Post failed (expected in test environment): \(error)")
            // In test environment, failure is expected due to mock tokens
        }
    }
}

// MARK: - Mock Error for Testing

private struct MockError: LocalizedError {
    let description: String
    
    var errorDescription: String? {
        return description
    }
    
    var localizedDescription: String {
        return description
    }
}

// MARK: - Test Extensions

extension ConnectionQuality: Equatable {
    public static func == (lhs: ConnectionQuality, rhs: ConnectionQuality) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none), (.poor, .poor), (.fair, .fair), (.good, .good), (.excellent, .excellent):
            return true
        default:
            return false
        }
    }
}

extension RetryStrategy: Equatable {
    public static func == (lhs: RetryStrategy, rhs: RetryStrategy) -> Bool {
        switch (lhs, rhs) {
        case (.conservative, .conservative), (.moderate, .moderate), (.aggressive, .aggressive):
            return true
        default:
            return false
        }
    }
}
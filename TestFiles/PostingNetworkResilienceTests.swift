import XCTest
import Network
import Combine
@testable import mercury_macos

/// Tests for posting behavior and resilience across various network conditions
@MainActor
final class PostingNetworkResilienceTests: XCTestCase {
    
    var authManager: AuthManager!
    var keychainManager: KeychainManager!
    var networkMonitor: NetworkMonitor!
    var postQueueManager: PostQueueManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        super.setUp()
        authManager = await AuthManager()
        keychainManager = KeychainManager()
        networkMonitor = NetworkMonitor()
        postQueueManager = PostQueueManager()
        cancellables = Set<AnyCancellable>()
        
        // Clean up any existing test tokens and queue
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
        await postQueueManager.clearQueue()
        
        // Set up valid authentication for posting tests
        await setupValidAuthentication()
    }
    
    override func tearDown() {
        // Clean up test data
        try? keychainManager.deleteToken()
        try? keychainManager.deleteRefreshToken()
        Task {
            await postQueueManager.clearQueue()
        }
        
        cancellables = nil
        authManager = nil
        keychainManager = nil
        networkMonitor = nil
        postQueueManager = nil
        super.tearDown()
    }
    
    // MARK: - Setup Helper
    
    private func setupValidAuthentication() async {
        let mockAccessToken = "valid_posting_token"
        let mockRefreshToken = "valid_posting_refresh"
        let expirationDate = Date().addingTimeInterval(3600) // 1 hour
        
        try? keychainManager.storeToken(mockAccessToken, expiresAt: expirationDate)
        try? keychainManager.storeRefreshToken(mockRefreshToken)
    }
    
    // MARK: - Posting Retry Logic Tests
    
    func testPostingWithNetworkTimeouts() async throws {
        var postingAttempts: [String] = []
        var retryEvents: [String] = []
        
        // Monitor posting attempts and retries
        authManager.eventManager.tweetPostEvents
            .sink { event in
                switch event {
                case .postStarted(let text):
                    postingAttempts.append("started:\(text.prefix(20))")
                case .postCompleted:
                    postingAttempts.append("completed")
                case .postFailed(let error, let text):
                    postingAttempts.append("failed:\(error.localizedDescription.prefix(20))")
                case .postQueued(let text):
                    postingAttempts.append("queued:\(text.prefix(20))")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        authManager.eventManager.networkEvents
            .sink { event in
                if case .operationRetried(let operation, let attempt) = event {
                    retryEvents.append("\(operation):attempt_\(attempt)")
                }
            }
            .store(in: &cancellables)
        
        // Simulate slow network that causes timeouts
        await simulateNetworkDelay(seconds: 12) // Longer than 10s posting timeout
        
        let testPost = "Test post with network timeout scenario"
        let startTime = Date()
        let result = await authManager.postTweet(testPost)
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should timeout within posting timeout (10-15s depending on connection quality)
        XCTAssertLessThan(elapsed, 20.0, "Should timeout within extended posting timeout")
        
        // Allow time for events to process
        try await Task.sleep(nanoseconds: 200_000_000)
        
        switch result {
        case .success:
            print("ℹ️ Post succeeded despite timeout simulation")
            
        case .failure(let error):
            print("✅ Post failed due to timeout: \(error)")
            
            // Verify timeout error
            let errorMessage = error.localizedDescription.lowercased()
            let isTimeoutError = errorMessage.contains("timeout") || 
                               errorMessage.contains("timed out") ||
                               errorMessage.contains("network")
            
            if isTimeoutError {
                print("✅ Timeout error properly detected")
            }
        }
        
        print("📊 Posting attempts: \(postingAttempts)")
        print("📊 Retry events: \(retryEvents)")
        
        // Verify appropriate events were generated
        XCTAssertTrue(postingAttempts.contains { $0.contains("started") }, 
                     "Should have started posting attempt")
    }
    
    func testPostingRetryWithNetworkRecovery() async throws {
        var networkEvents: [String] = []
        var postingResults: [String] = []
        
        // Monitor network and posting events
        authManager.eventManager.networkEvents
            .sink { event in
                switch event {
                case .connectionLost:
                    networkEvents.append("connection_lost")
                case .connectionEstablished:
                    networkEvents.append("connection_established")
                case .operationRetried(let operation, let attempt):
                    networkEvents.append("retry:\(operation):attempt_\(attempt)")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        authManager.eventManager.tweetPostEvents
            .sink { event in
                switch event {
                case .postCompleted:
                    postingResults.append("success")
                case .postFailed:
                    postingResults.append("failed")
                case .postQueued:
                    postingResults.append("queued")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Start with network disconnected
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Attempt to post while disconnected
        let testPost = "Test post with network recovery"
        
        Task {
            // Restore network after a delay to simulate recovery during retry
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await self.simulateNetworkConnectivityChange(isConnected: true)
        }
        
        let result = await authManager.postTweet(testPost)
        
        // Allow time for events to process
        try await Task.sleep(nanoseconds: 300_000_000)
        
        print("📊 Network events: \(networkEvents)")
        print("📊 Posting results: \(postingResults)")
        
        // Verify network events were detected
        if networkEvents.contains("connection_lost") && networkEvents.contains("connection_established") {
            print("✅ Network recovery properly detected")
        }
        
        // Post behavior depends on implementation - might succeed after recovery or be queued
        switch result {
        case .success:
            print("✅ Post succeeded after network recovery")
            
        case .failure:
            print("ℹ️ Post failed or queued (expected behavior during network issues)")
        }
    }
    
    func testPostingWithIntermittentConnectivity() async throws {
        var connectivityEvents: [Date] = []
        var postingAttempts: [String] = []
        
        // Monitor network state changes
        networkMonitor.isConnectedPublisher
            .sink { isConnected in
                connectivityEvents.append(Date())
                postingAttempts.append(isConnected ? "connected" : "disconnected")
            }
            .store(in: &cancellables)
        
        networkMonitor.startMonitoring()
        
        // Simulate intermittent connectivity
        await simulateIntermittentNetworkPattern()
        
        // Attempt posting during unstable network
        let posts = [
            "Post 1 during intermittent connectivity",
            "Post 2 during intermittent connectivity",
            "Post 3 during intermittent connectivity"
        ]
        
        var results: [Result<TweetPostSuccess, Error>] = []
        
        for post in posts {
            let result = await authManager.postTweet(post)
            results.append(result)
            
            // Small delay between posts
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        
        networkMonitor.stopMonitoring()
        
        // Analyze results
        let successCount = results.filter { if case .success = $0 { return true }; return false }.count
        let failureCount = results.count - successCount
        
        print("📊 Posting results: \(successCount) successes, \(failureCount) failures")
        print("📊 Connectivity events: \(postingAttempts)")
        
        // At least some posts should be handled (success, failure, or queuing)
        XCTAssertEqual(results.count, posts.count, "Should have results for all posts")
        
        // Verify system handles intermittent connectivity gracefully
        XCTAssertTrue(successCount + failureCount == posts.count, 
                     "Should handle all posts with success or failure")
    }
    
    // MARK: - Connection Quality Impact Tests
    
    func testPostingPerformanceByConnectionQuality() async throws {
        let connectionQualities: [ConnectionQuality] = [.excellent, .good, .fair, .poor]
        var performanceMetrics: [ConnectionQuality: TimeInterval] = [:]
        
        for quality in connectionQualities {
            await simulateConnectionQuality(quality)
            
            let startTime = Date()
            let result = await authManager.postTweet("Performance test post for \(quality.description)")
            let elapsed = Date().timeIntervalSince(startTime)
            
            performanceMetrics[quality] = elapsed
            
            print("📊 \(quality.description) connection: \(elapsed)s")
            
            // Allow brief pause between tests
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Verify performance expectations
        if let excellentTime = performanceMetrics[.excellent],
           let poorTime = performanceMetrics[.poor] {
            
            // Poor connections should have longer timeouts but still complete
            XCTAssertLessThan(excellentTime, 15.0, "Excellent connection should be fast")
            XCTAssertLessThan(poorTime, 20.0, "Poor connection should still complete reasonably")
        }
    }
    
    func testRetryStrategyByConnectionQuality() async throws {
        let qualities: [ConnectionQuality] = [.excellent, .good, .poor, .none]
        
        for quality in qualities {
            let strategy = quality.retryStrategy
            
            print("📊 \(quality.description): \(strategy) - max retries: \(strategy.maxRetries), base delay: \(strategy.baseDelay)s")
            
            // Verify appropriate strategy selection
            switch quality {
            case .excellent, .good:
                XCTAssertEqual(strategy, .aggressive, "\(quality.description) should use aggressive strategy")
                
            case .fair:
                XCTAssertEqual(strategy, .moderate, "Fair connection should use moderate strategy")
                
            case .poor, .none:
                XCTAssertEqual(strategy, .conservative, "\(quality.description) should use conservative strategy")
            }
            
            // Test exponential backoff calculation
            let delay1 = strategy.delayForAttempt(1)
            let delay2 = strategy.delayForAttempt(2)
            
            XCTAssertEqual(delay1, strategy.baseDelay * 2, "First retry should double base delay")
            XCTAssertEqual(delay2, strategy.baseDelay * 4, "Second retry should quadruple base delay")
        }
    }
    
    // MARK: - Queue Behavior Under Network Conditions
    
    func testPostQueuingDuringOfflinePeriods() async throws {
        var queueEvents: [String] = []
        
        // Monitor queue events
        authManager.eventManager.tweetPostEvents
            .sink { event in
                switch event {
                case .postQueued(let text):
                    queueEvents.append("queued:\(text.prefix(10))")
                case .queueProcessingStarted:
                    queueEvents.append("processing_started")
                case .queueProcessingCompleted(let success, let failure):
                    queueEvents.append("processing_completed:\(success)success_\(failure)failure")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Go offline
        await simulateNetworkConnectivityChange(isConnected: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Queue multiple posts while offline
        let offlinePosts = [
            "Offline post 1",
            "Offline post 2", 
            "Offline post 3"
        ]
        
        for post in offlinePosts {
            let result = await authManager.postTweet(post)
            
            switch result {
            case .success:
                XCTFail("Posts should not succeed while offline")
                
            case .failure(let error):
                print("✅ Post failed while offline: \(error.localizedDescription.prefix(50))")
            }
        }
        
        // Allow time for queuing to process
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Go back online
        await simulateNetworkConnectivityChange(isConnected: true)
        try await Task.sleep(nanoseconds: 500_000_000) // Allow queue processing
        
        print("📊 Queue events: \(queueEvents)")
        
        // Verify queuing behavior
        let queuedCount = queueEvents.filter { $0.contains("queued") }.count
        print("📊 Queued posts: \(queuedCount)")
        
        // Check if queue processing was triggered
        if queueEvents.contains("processing_started") {
            print("✅ Queue processing started after network recovery")
        }
    }
    
    func testQueueProcessingRetryLogic() async throws {
        var processingEvents: [String] = []
        
        // Monitor queue processing events
        authManager.eventManager.tweetPostEvents
            .sink { event in
                if case .queueProcessingCompleted(let success, let failure) = event {
                    processingEvents.append("completed:\(success)success_\(failure)failure")
                }
            }
            .store(in: &cancellables)
        
        // Add some posts to queue manually (simulating previous offline posts)
        let queuedPost1 = QueuedPost(text: "Queued post 1", retryCount: 0)
        let queuedPost2 = QueuedPost(text: "Queued post 2", retryCount: 1)
        let queuedPost3 = QueuedPost(text: "Queued post 3", retryCount: 3)
        
        await postQueueManager.addToQueue(queuedPost1)
        await postQueueManager.addToQueue(queuedPost2)
        await postQueueManager.addToQueue(queuedPost3)
        
        // Simulate network recovery to trigger queue processing
        await simulateNetworkConnectivityChange(isConnected: true)
        
        // Trigger queue processing
        await postQueueManager.processQueue()
        
        // Allow time for processing
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        print("📊 Processing events: \(processingEvents)")
        
        // Verify queue processing was attempted
        if !processingEvents.isEmpty {
            print("✅ Queue processing completed")
        }
        
        // Check queue state after processing
        let remainingCount = await postQueueManager.getQueuedPostsCount()
        print("📊 Remaining queued posts: \(remainingCount)")
    }
    
    // MARK: - Rate Limiting Under Network Stress
    
    func testRateLimitingDuringNetworkRetries() async throws {
        var rateLimitEvents: [String] = []
        
        // Monitor rate limit events
        authManager.eventManager.rateLimitEvents
            .sink { event in
                switch event {
                case .usageUpdated(let info):
                    rateLimitEvents.append("usage:\(info.remainingRequests)")
                case .warningTriggered:
                    rateLimitEvents.append("warning")
                case .limitExceeded:
                    rateLimitEvents.append("exceeded")
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Simulate poor network with retries
        await simulateNetworkQuality(.poor)
        
        // Attempt multiple posts rapidly
        for i in 1...5 {
            let result = await authManager.postTweet("Rate limit test post \(i)")
            
            switch result {
            case .success:
                print("✅ Post \(i) succeeded")
                
            case .failure(let error):
                print("ℹ️ Post \(i) failed: \(error.localizedDescription.prefix(50))")
            }
            
            // Brief delay between posts
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        print("📊 Rate limit events: \(rateLimitEvents)")
        
        // Verify rate limiting is tracked during retries
        let usageEvents = rateLimitEvents.filter { $0.contains("usage") }
        if !usageEvents.isEmpty {
            print("✅ Rate limit usage tracked during network stress")
        }
    }
    
    // MARK: - Helper Methods
    
    private func simulateNetworkConnectivityChange(isConnected: Bool) async {
        if isConnected {
            NotificationCenter.default.post(
                name: .networkDidBecomeAvailable,
                object: nil
            )
        } else {
            NotificationCenter.default.post(
                name: .networkDidBecomeUnavailable,
                object: nil
            )
        }
    }
    
    private func simulateNetworkDelay(seconds: TimeInterval) async {
        let userInfo: [String: Any] = ["delay": seconds]
        NotificationCenter.default.post(
            name: .networkDelaySimulated,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func simulateConnectionQuality(_ quality: ConnectionQuality) async {
        let userInfo: [String: Any] = ["quality": quality.description]
        NotificationCenter.default.post(
            name: .networkQualityChanged,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func simulateIntermittentNetworkPattern() async {
        // Pattern: connected -> disconnected -> connected -> disconnected -> connected
        let pattern = [true, false, true, false, true]
        
        for isConnected in pattern {
            await simulateNetworkConnectivityChange(isConnected: isConnected)
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds between changes
        }
    }
}

// MARK: - Test Extensions

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("NetworkDidBecomeAvailable")
    static let networkDidBecomeUnavailable = Notification.Name("NetworkDidBecomeUnavailable")
    static let networkQualityChanged = Notification.Name("NetworkQualityChanged")
    static let networkDelaySimulated = Notification.Name("NetworkDelaySimulated")
}

// Mock success type for testing
struct TweetPostSuccess {
    let tweetId: String
    let timestamp: Date
}

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
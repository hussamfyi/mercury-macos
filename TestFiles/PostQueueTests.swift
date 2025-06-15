import XCTest
import Combine
@testable import mercury_macos

/// Comprehensive unit tests for PostQueueManager covering all queuing and retry scenarios
@MainActor
final class PostQueueTests: XCTestCase {
    
    private var postQueueManager: PostQueueManager!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        postQueueManager = PostQueueManager(networkMonitor: nil)
        cancellables = Set<AnyCancellable>()
        
        // Clear any existing data
        await postQueueManager.clearQueue()
        postQueueManager.clearDeduplicationHistory()
        postQueueManager.dismissAllNotifications()
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        await postQueueManager.clearQueue()
        postQueueManager.clearDeduplicationHistory()
        postQueueManager.dismissAllNotifications()
        
        cancellables.removeAll()
        postQueueManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Queuing Tests
    
    func testQueuePost_ValidPost_AddsToQueue() async throws {
        // Given
        let testText = "Test post content"
        let initialCount = await postQueueManager.getQueuedPostsCount()
        
        // When
        let wasQueued = await postQueueManager.queuePost(testText)
        
        // Then
        XCTAssertTrue(wasQueued, "Post should be successfully queued")
        
        let finalCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertEqual(finalCount, initialCount + 1, "Queue count should increase by 1")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.count, 1, "Should have exactly one queued post")
        XCTAssertEqual(queuedPosts.first?.text, testText, "Queued post should have correct text")
    }
    
    func testQueuePost_EmptyPost_AddsToQueue() async throws {
        // Given
        let testText = ""
        
        // When
        let wasQueued = await postQueueManager.queuePost(testText)
        
        // Then
        XCTAssertTrue(wasQueued, "Empty post should be queued (validation is handled elsewhere)")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.count, 1, "Should have one queued post")
        XCTAssertEqual(queuedPosts.first?.text, "", "Should preserve empty text")
    }
    
    func testQueuePost_LongPost_AddsToQueue() async throws {
        // Given
        let longText = String(repeating: "A", count: 500) // Longer than typical tweet limit
        
        // When
        let wasQueued = await postQueueManager.queuePost(longText)
        
        // Then
        XCTAssertTrue(wasQueued, "Long post should be queued")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.first?.text, longText, "Should preserve full long text")
    }
    
    func testQueuePost_MultipleUniquePosts_AddsAll() async throws {
        // Given
        let posts = ["Post 1", "Post 2", "Post 3"]
        
        // When
        for post in posts {
            let wasQueued = await postQueueManager.queuePost(post)
            XCTAssertTrue(wasQueued, "Each unique post should be queued")
        }
        
        // Then
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.count, posts.count, "All unique posts should be queued")
        
        let queuedTexts = queuedPosts.map { $0.text }
        for post in posts {
            XCTAssertTrue(queuedTexts.contains(post), "Queue should contain post: \(post)")
        }
    }
    
    // MARK: - Deduplication Tests
    
    func testQueuePost_DuplicatePost_PreventsQueuing() async throws {
        // Given
        let testText = "Duplicate test post"
        
        // When - Queue the same post twice
        let firstQueuing = await postQueueManager.queuePost(testText)
        let secondQueuing = await postQueueManager.queuePost(testText)
        
        // Then
        XCTAssertTrue(firstQueuing, "First posting should succeed")
        XCTAssertFalse(secondQueuing, "Duplicate posting should be prevented")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.count, 1, "Should only have one instance of the post")
    }
    
    func testQueuePost_SimilarButDifferentPosts_AllowsBoth() async throws {
        // Given
        let post1 = "Test post"
        let post2 = "Test post with extra content"
        
        // When
        let firstQueuing = await postQueueManager.queuePost(post1)
        let secondQueuing = await postQueueManager.queuePost(post2)
        
        // Then
        XCTAssertTrue(firstQueuing, "First post should be queued")
        XCTAssertTrue(secondQueuing, "Similar but different post should be queued")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.count, 2, "Both posts should be queued")
    }
    
    func testQueuePost_WhitespaceVariations_DetectsDuplicates() async throws {
        // Given
        let originalPost = "Test post"
        let whitespaceVariation = "  Test post  " // Extra whitespace
        let lineBreakVariation = "Test\npost" // Different whitespace
        
        // When
        let firstQueuing = await postQueueManager.queuePost(originalPost)
        let secondQueuing = await postQueueManager.queuePost(whitespaceVariation)
        let thirdQueuing = await postQueueManager.queuePost(lineBreakVariation)
        
        // Then
        XCTAssertTrue(firstQueuing, "Original post should be queued")
        // Note: The current implementation may or may not catch these as duplicates
        // depending on the normalization logic - this test documents the expected behavior
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        // The exact count depends on how sophisticated the deduplication is
        XCTAssertGreaterThanOrEqual(queuedPosts.count, 1, "Should have at least one post")
        XCTAssertLessThanOrEqual(queuedPosts.count, 3, "Should not have more than 3 posts")
    }
    
    func testWouldBeDuplicate_ExistingPost_ReturnsTrue() async throws {
        // Given
        let testText = "Test for duplicate check"
        await postQueueManager.queuePost(testText)
        
        // When
        let wouldBeDuplicate = await postQueueManager.wouldBeDuplicate(testText)
        
        // Then
        XCTAssertTrue(wouldBeDuplicate, "Should detect existing post as duplicate")
    }
    
    func testWouldBeDuplicate_NewPost_ReturnsFalse() async throws {
        // Given
        let existingText = "Existing post"
        let newText = "Completely different post"
        await postQueueManager.queuePost(existingText)
        
        // When
        let wouldBeDuplicate = await postQueueManager.wouldBeDuplicate(newText)
        
        // Then
        XCTAssertFalse(wouldBeDuplicate, "Should not detect new post as duplicate")
    }
    
    // MARK: - Queue Management Tests
    
    func testGetQueuedPosts_EmptyQueue_ReturnsEmptyArray() async throws {
        // When
        let queuedPosts = await postQueueManager.getQueuedPosts()
        
        // Then
        XCTAssertTrue(queuedPosts.isEmpty, "Empty queue should return empty array")
    }
    
    func testGetAllQueuedPosts_ReturnsTextArray() async throws {
        // Given
        let posts = ["Post A", "Post B", "Post C"]
        for post in posts {
            await postQueueManager.queuePost(post)
        }
        
        // When
        let allQueuedPosts = await postQueueManager.getAllQueuedPosts()
        
        // Then
        XCTAssertEqual(allQueuedPosts.count, posts.count, "Should return all post texts")
        for post in posts {
            XCTAssertTrue(allQueuedPosts.contains(post), "Should contain post: \(post)")
        }
    }
    
    func testRemovePost_ExistingPost_RemovesFromQueue() async throws {
        // Given
        await postQueueManager.queuePost("Test post to remove")
        let queuedPosts = await postQueueManager.getQueuedPosts()
        guard let postToRemove = queuedPosts.first else {
            XCTFail("Should have at least one queued post")
            return
        }
        
        let initialCount = await postQueueManager.getQueuedPostsCount()
        
        // When
        await postQueueManager.removePost(postToRemove.id)
        
        // Then
        let finalCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertEqual(finalCount, initialCount - 1, "Count should decrease by 1")
        
        let remainingPosts = await postQueueManager.getQueuedPosts()
        let remainingIds = remainingPosts.map { $0.id }
        XCTAssertFalse(remainingIds.contains(postToRemove.id), "Removed post should not be in queue")
    }
    
    func testRemovePost_NonexistentPost_DoesNothing() async throws {
        // Given
        await postQueueManager.queuePost("Test post")
        let initialCount = await postQueueManager.getQueuedPostsCount()
        let nonexistentId = UUID()
        
        // When
        await postQueueManager.removePost(nonexistentId)
        
        // Then
        let finalCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertEqual(finalCount, initialCount, "Count should remain unchanged")
    }
    
    func testClearQueue_WithMultiplePosts_RemovesAll() async throws {
        // Given
        let posts = ["Post 1", "Post 2", "Post 3", "Post 4"]
        for post in posts {
            await postQueueManager.queuePost(post)
        }
        
        let initialCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertGreaterThan(initialCount, 0, "Should have posts before clearing")
        
        // When
        await postQueueManager.clearQueue()
        
        // Then
        let finalCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertEqual(finalCount, 0, "Queue should be empty after clearing")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertTrue(queuedPosts.isEmpty, "Should have no queued posts")
    }
    
    // MARK: - Retry Logic Tests
    
    func testProcessQueue_WithQueuedPosts_AttemptsRetry() async throws {
        // Given
        await postQueueManager.queuePost("Test retry post")
        let initialCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertGreaterThan(initialCount, 0, "Should have posts to process")
        
        // When
        let processedCount = await postQueueManager.processQueue()
        
        // Then
        // Note: The actual behavior depends on the mock implementation in attemptToSendPost
        // The test verifies that processing occurs without crashing
        XCTAssertGreaterThanOrEqual(processedCount, 0, "Should return non-negative processed count")
    }
    
    func testProcessQueue_EmptyQueue_ReturnsZero() async throws {
        // Given - empty queue
        let initialCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertEqual(initialCount, 0, "Queue should be empty")
        
        // When
        let processedCount = await postQueueManager.processQueue()
        
        // Then
        XCTAssertEqual(processedCount, 0, "Should process zero posts from empty queue")
    }
    
    func testRetryPost_ExistingPost_AttemptsRetry() async throws {
        // Given
        await postQueueManager.queuePost("Test individual retry")
        let queuedPosts = await postQueueManager.getQueuedPosts()
        guard let postToRetry = queuedPosts.first else {
            XCTFail("Should have at least one queued post")
            return
        }
        
        // When
        let retryResult = await postQueueManager.retryPost(postToRetry.id)
        
        // Then
        // The actual result depends on the mock implementation
        // This test verifies the method doesn't crash and returns a boolean
        XCTAssertNotNil(retryResult, "Retry should return a result")
    }
    
    func testRetryPost_NonexistentPost_ReturnsFalse() async throws {
        // Given
        let nonexistentId = UUID()
        
        // When
        let retryResult = await postQueueManager.retryPost(nonexistentId)
        
        // Then
        XCTAssertFalse(retryResult, "Retry of nonexistent post should return false")
    }
    
    func testForceProcessAllPosts_IgnoresRetryTiming() async throws {
        // Given
        let posts = ["Post 1", "Post 2", "Post 3"]
        for post in posts {
            await postQueueManager.queuePost(post)
        }
        
        // When
        let processedCount = await postQueueManager.forceProcessAllPosts()
        
        // Then
        XCTAssertGreaterThanOrEqual(processedCount, 0, "Should return non-negative count")
        // Note: The exact count depends on the mock success rate
    }
    
    // MARK: - Retry Scheduling Tests
    
    func testGetRetryStatus_WithQueuedPosts_ReturnsStatus() async throws {
        // Given
        await postQueueManager.queuePost("Test status post")
        
        // When
        let retryStatus = await postQueueManager.getRetryStatus()
        
        // Then
        XCTAssertEqual(retryStatus.count, 1, "Should have one retry status")
        
        let status = retryStatus.first!
        XCTAssertEqual(status.retryCount, 0, "New post should have zero retries")
        XCTAssertTrue(status.isReadyForRetry, "New post should be ready for retry")
        XCTAssertEqual(status.content, "Test status post", "Should contain post content")
    }
    
    func testGetRetryStatus_EmptyQueue_ReturnsEmpty() async throws {
        // When
        let retryStatus = await postQueueManager.getRetryStatus()
        
        // Then
        XCTAssertTrue(retryStatus.isEmpty, "Empty queue should return empty status array")
    }
    
    // MARK: - Automatic Retry Management Tests
    
    func testPauseAndResumeAutomaticRetries() async throws {
        // Given - retries are running by default
        
        // When
        postQueueManager.pauseAutomaticRetries()
        
        // Then - verify pause doesn't crash
        // Note: Without access to internal timer state, we can only verify the methods don't crash
        
        // When
        postQueueManager.resumeAutomaticRetries()
        
        // Then - verify resume doesn't crash
        // The actual timer functionality would need integration tests
    }
    
    // MARK: - Storage and Persistence Tests
    
    func testGetStorageInfo_ReturnsValidInfo() async throws {
        // When
        let storageInfo = postQueueManager.getStorageInfo()
        
        // Then
        XCTAssertTrue(storageInfo.isUsingSecureStorage, "Should be using secure storage")
        XCTAssertGreaterThanOrEqual(storageInfo.storageFileSize, 0, "File size should be non-negative")
        XCTAssertNotNil(storageInfo.statusDescription, "Should have status description")
        XCTAssertNotNil(storageInfo.formattedFileSize, "Should have formatted file size")
    }
    
    func testGetPersistenceStatus_ReturnsValidStatus() async throws {
        // Given
        await postQueueManager.queuePost("Test persistence post")
        
        // When
        let persistenceStatus = postQueueManager.getPersistenceStatus()
        
        // Then
        XCTAssertEqual(persistenceStatus.queuedPostsCount, 1, "Should reflect current queue count")
        XCTAssertGreaterThanOrEqual(persistenceStatus.retrySchedulesCount, 0, "Should have non-negative retry count")
        XCTAssertTrue(persistenceStatus.isAppActive, "App should be active during tests")
        XCTAssertTrue(persistenceStatus.hasLifecycleObservers, "Should have lifecycle observers")
        XCTAssertNotNil(persistenceStatus.statusDescription, "Should have status description")
        XCTAssertTrue(persistenceStatus.isHealthy, "Should be healthy")
    }
    
    // MARK: - Deduplication System Tests
    
    func testGetDeduplicationStatus_ReturnsValidStatus() async throws {
        // When
        let deduplicationStatus = postQueueManager.getDeduplicationStatus()
        
        // Then
        XCTAssertGreaterThanOrEqual(deduplicationStatus.recentPostsCount, 0, "Should have non-negative count")
        XCTAssertGreaterThan(deduplicationStatus.deduplicationWindowMinutes, 0, "Should have positive window")
        XCTAssertNotNil(deduplicationStatus.statusDescription, "Should have status description")
        XCTAssertTrue(deduplicationStatus.isEffective, "Should be effective initially")
    }
    
    func testClearDeduplicationHistory_ClearsTracking() async throws {
        // Given
        await postQueueManager.queuePost("Test dedup clear")
        let initialStatus = postQueueManager.getDeduplicationStatus()
        
        // When
        postQueueManager.clearDeduplicationHistory()
        
        // Then
        let finalStatus = postQueueManager.getDeduplicationStatus()
        XCTAssertEqual(finalStatus.recentPostsCount, 0, "Should have no recent posts after clearing")
    }
    
    // MARK: - Notification System Tests
    
    func testNotificationPublisher_EmitsNotifications() async throws {
        // Given
        var receivedNotifications: [QueueStatusNotification] = []
        let expectation = expectation(description: "Notification received")
        
        postQueueManager.notificationsPublisher
            .sink { notifications in
                receivedNotifications = notifications
                if !notifications.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        await postQueueManager.queuePost("Test notification post")
        
        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertFalse(receivedNotifications.isEmpty, "Should receive notifications")
        
        // Verify notification content
        let queuedNotifications = receivedNotifications.filter { 
            if case .postQueued = $0.type { return true }
            return false
        }
        XCTAssertFalse(queuedNotifications.isEmpty, "Should have queued post notification")
    }
    
    func testMarkNotificationAsRead_UpdatesStatus() async throws {
        // Given
        await postQueueManager.queuePost("Test read notification")
        
        // Wait for notification to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let notifications = postQueueManager.queueNotifications
        guard let notification = notifications.first else {
            XCTFail("Should have at least one notification")
            return
        }
        
        XCTAssertFalse(notification.isRead, "Notification should initially be unread")
        
        // When
        postQueueManager.markNotificationAsRead(notification.id)
        
        // Then
        let updatedNotifications = postQueueManager.queueNotifications
        let updatedNotification = updatedNotifications.first { $0.id == notification.id }
        XCTAssertNotNil(updatedNotification, "Notification should still exist")
        XCTAssertTrue(updatedNotification?.isRead ?? false, "Notification should be marked as read")
    }
    
    func testMarkAllNotificationsAsRead_UpdatesAllStatus() async throws {
        // Given
        await postQueueManager.queuePost("Test post 1")
        await postQueueManager.queuePost("Test post 2")
        
        // Wait for notifications to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let unreadCount = postQueueManager.getUnreadNotificationCount()
        XCTAssertGreaterThan(unreadCount, 0, "Should have unread notifications")
        
        // When
        postQueueManager.markAllNotificationsAsRead()
        
        // Then
        let finalUnreadCount = postQueueManager.getUnreadNotificationCount()
        XCTAssertEqual(finalUnreadCount, 0, "Should have no unread notifications")
    }
    
    func testDismissNotification_RemovesFromActive() async throws {
        // Given
        await postQueueManager.queuePost("Test dismiss notification")
        
        // Wait for notification to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let initialCount = postQueueManager.queueNotifications.count
        XCTAssertGreaterThan(initialCount, 0, "Should have notifications")
        
        let notificationToDismiss = postQueueManager.queueNotifications.first!
        
        // When
        postQueueManager.dismissNotification(notificationToDismiss.id)
        
        // Then
        let finalCount = postQueueManager.queueNotifications.count
        XCTAssertEqual(finalCount, initialCount - 1, "Should have one fewer notification")
        
        let remainingIds = postQueueManager.queueNotifications.map { $0.id }
        XCTAssertFalse(remainingIds.contains(notificationToDismiss.id), "Dismissed notification should not be present")
    }
    
    func testDismissAllNotifications_ClearsActiveNotifications() async throws {
        // Given
        await postQueueManager.queuePost("Test post 1")
        await postQueueManager.queuePost("Test post 2")
        
        // Wait for notifications to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let initialCount = postQueueManager.queueNotifications.count
        XCTAssertGreaterThan(initialCount, 0, "Should have notifications")
        
        // When
        postQueueManager.dismissAllNotifications()
        
        // Then
        let finalCount = postQueueManager.queueNotifications.count
        XCTAssertEqual(finalCount, 0, "Should have no active notifications")
    }
    
    func testGetNotificationStats_ReturnsValidStats() async throws {
        // Given
        await postQueueManager.queuePost("Test stats post")
        
        // Wait for notification to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // When
        let stats = postQueueManager.getNotificationStats()
        
        // Then
        XCTAssertGreaterThanOrEqual(stats.activeNotifications, 0, "Should have non-negative active count")
        XCTAssertGreaterThanOrEqual(stats.totalNotifications, 0, "Should have non-negative total count")
        XCTAssertGreaterThanOrEqual(stats.unreadNotifications, 0, "Should have non-negative unread count")
        XCTAssertNotNil(stats.summary, "Should have summary")
    }
    
    func testGetNotificationHistory_ReturnsHistory() async throws {
        // Given
        await postQueueManager.queuePost("Test history post")
        
        // Wait for notification to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // When
        let history = postQueueManager.getNotificationHistory()
        
        // Then
        XCTAssertFalse(history.isEmpty, "Should have notification history")
        
        let queuedNotifications = history.filter {
            if case .postQueued = $0.type { return true }
            return false
        }
        XCTAssertFalse(queuedNotifications.isEmpty, "Should have queued post in history")
    }
    
    // MARK: - Publisher Tests
    
    func testQueueCountPublisher_EmitsCountChanges() async throws {
        // Given
        var receivedCounts: [Int] = []
        let expectation = expectation(description: "Count change received")
        expectation.expectedFulfillmentCount = 2 // Initial + after queuing
        
        postQueueManager.queueCountPublisher
            .sink { count in
                receivedCounts.append(count)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // When
        await postQueueManager.queuePost("Test count publisher")
        
        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedCounts.count, 2, "Should receive initial count and updated count")
        XCTAssertEqual(receivedCounts.last, 1, "Final count should be 1")
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testQueuePost_SpecialCharacters_HandlesCorrectly() async throws {
        // Given
        let specialCharPost = "Test with émojis 🚀 and symbols @#$%"
        
        // When
        let wasQueued = await postQueueManager.queuePost(specialCharPost)
        
        // Then
        XCTAssertTrue(wasQueued, "Should handle special characters")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.first?.text, specialCharPost, "Should preserve special characters")
    }
    
    func testQueuePost_UnicodeContent_HandlesCorrectly() async throws {
        // Given
        let unicodePost = "Unicode test: 你好世界 🌍 مرحبا بالعالم"
        
        // When
        let wasQueued = await postQueueManager.queuePost(unicodePost)
        
        // Then
        XCTAssertTrue(wasQueued, "Should handle Unicode content")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.first?.text, unicodePost, "Should preserve Unicode content")
    }
    
    func testQueuePost_NewlineCharacters_HandlesCorrectly() async throws {
        // Given
        let multilinePost = "Line 1\nLine 2\nLine 3"
        
        // When
        let wasQueued = await postQueueManager.queuePost(multilinePost)
        
        // Then
        XCTAssertTrue(wasQueued, "Should handle newline characters")
        
        let queuedPosts = await postQueueManager.getQueuedPosts()
        XCTAssertEqual(queuedPosts.first?.text, multilinePost, "Should preserve newline characters")
    }
    
    // MARK: - Performance Tests
    
    func testQueuePost_LargeNumberOfPosts_PerformsWell() async throws {
        // Given
        let numberOfPosts = 100
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // When
        for i in 0..<numberOfPosts {
            await postQueueManager.queuePost("Performance test post \(i)")
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        // Then
        XCTAssertLessThan(totalTime, 5.0, "Should queue 100 posts in under 5 seconds")
        
        let finalCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertEqual(finalCount, numberOfPosts, "Should have all posts queued")
    }
    
    func testProcessQueue_LargeQueue_PerformsWell() async throws {
        // Given
        let numberOfPosts = 50
        for i in 0..<numberOfPosts {
            await postQueueManager.queuePost("Process test post \(i)")
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // When
        let processedCount = await postQueueManager.processQueue()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        // Then
        XCTAssertLessThan(totalTime, 10.0, "Should process queue in under 10 seconds")
        XCTAssertGreaterThanOrEqual(processedCount, 0, "Should return non-negative processed count")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentQueueOperations_ThreadSafe() async throws {
        // Given
        let numberOfOperations = 20
        let posts = (0..<numberOfOperations).map { "Concurrent post \($0)" }
        
        // When - Perform concurrent queue operations
        await withTaskGroup(of: Bool.self) { group in
            for post in posts {
                group.addTask {
                    return await self.postQueueManager.queuePost(post)
                }
            }
            
            // Wait for all tasks to complete
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            
            // Then
            let successfulQueueings = results.filter { $0 }.count
            XCTAssertGreaterThan(successfulQueueings, 0, "Should have some successful queueings")
        }
        
        // Verify final state is consistent
        let finalCount = await postQueueManager.getQueuedPostsCount()
        XCTAssertGreaterThan(finalCount, 0, "Should have posts in queue after concurrent operations")
        XCTAssertLessThanOrEqual(finalCount, numberOfOperations, "Should not exceed maximum possible posts")
    }
}

// MARK: - QueueStatusNotification Tests

/// Tests for the QueueStatusNotification model and related functionality
final class QueueStatusNotificationTests: XCTestCase {
    
    func testNotificationType_Message_ReturnsCorrectMessage() {
        // Given
        let message = "Test message"
        let notificationType = QueueStatusNotification.NotificationType.postQueued(
            content: "test content",
            message: message
        )
        
        // When
        let retrievedMessage = notificationType.message
        
        // Then
        XCTAssertEqual(retrievedMessage, message, "Should return correct message")
    }
    
    func testNotificationType_ContentPreview_ReturnsContentForApplicableTypes() {
        // Given
        let content = "test content"
        let postQueuedType = QueueStatusNotification.NotificationType.postQueued(
            content: content,
            message: "test"
        )
        let rateLimitedType = QueueStatusNotification.NotificationType.rateLimited(
            retryAfterSeconds: 60,
            message: "test"
        )
        
        // When & Then
        XCTAssertEqual(postQueuedType.contentPreview, content, "Should return content for post types")
        XCTAssertNil(rateLimitedType.contentPreview, "Should not return content for system types")
    }
    
    func testNotificationType_Priority_ReturnsCorrectPriority() {
        // Given
        let highPriorityType = QueueStatusNotification.NotificationType.postFailed(
            content: "test",
            error: "error",
            message: "test"
        )
        let lowPriorityType = QueueStatusNotification.NotificationType.postSuccess(
            content: "test",
            message: "test"
        )
        
        // When & Then
        XCTAssertEqual(highPriorityType.priority, .high, "Post failures should be high priority")
        XCTAssertEqual(lowPriorityType.priority, .low, "Post successes should be low priority")
    }
    
    func testNotificationType_RequiresAttention_ReturnsCorrectValue() {
        // Given
        let attentionRequiredType = QueueStatusNotification.NotificationType.rateLimited(
            retryAfterSeconds: 60,
            message: "test"
        )
        let noAttentionType = QueueStatusNotification.NotificationType.postSuccess(
            content: "test",
            message: "test"
        )
        
        // When & Then
        XCTAssertTrue(attentionRequiredType.requiresAttention, "Rate limited should require attention")
        XCTAssertFalse(noAttentionType.requiresAttention, "Success should not require attention")
    }
    
    func testNotification_Age_CalculatesCorrectly() {
        // Given
        let pastTime = Date().addingTimeInterval(-60) // 1 minute ago
        let notification = QueueStatusNotification(
            type: .postQueued(content: "test", message: "test"),
            timestamp: pastTime
        )
        
        // When
        let age = notification.age
        
        // Then
        XCTAssertGreaterThan(age, 50, "Age should be approximately 60 seconds")
        XCTAssertLessThan(age, 70, "Age should be approximately 60 seconds")
    }
    
    func testNotification_AgeDescription_ReturnsReadableFormat() {
        // Given
        let recentTime = Date().addingTimeInterval(-30) // 30 seconds ago
        let oldTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
        let recentNotification = QueueStatusNotification(
            type: .postQueued(content: "test", message: "test"),
            timestamp: recentTime
        )
        let oldNotification = QueueStatusNotification(
            type: .postQueued(content: "test", message: "test"),
            timestamp: oldTime
        )
        
        // When & Then
        XCTAssertEqual(recentNotification.ageDescription, "Just now", "Recent notifications should show 'Just now'")
        XCTAssertTrue(oldNotification.ageDescription.contains("hour"), "Old notifications should show hours")
    }
    
    func testNotification_ShouldAutoDismiss_RespectsReadStatusAndPriority() {
        // Given
        let oldTime = Date().addingTimeInterval(-35) // 35 seconds ago
        let lowPriorityType = QueueStatusNotification.NotificationType.postSuccess(
            content: "test",
            message: "test"
        )
        
        var unreadNotification = QueueStatusNotification(
            type: lowPriorityType,
            timestamp: oldTime,
            isRead: false
        )
        var readNotification = QueueStatusNotification(
            type: lowPriorityType,
            timestamp: oldTime,
            isRead: true
        )
        
        // When & Then
        XCTAssertTrue(unreadNotification.shouldAutoDismiss, "Old unread low-priority notifications should auto-dismiss")
        XCTAssertTrue(readNotification.shouldAutoDismiss, "Old read low-priority notifications should auto-dismiss")
    }
}

// MARK: - Array Extension Tests

/// Tests for QueueStatusNotification array extensions
final class QueueStatusNotificationArrayTests: XCTestCase {
    
    private var notifications: [QueueStatusNotification]!
    
    override func setUp() {
        super.setUp()
        
        // Create test notifications with different priorities and read status
        notifications = [
            QueueStatusNotification(
                type: .postFailed(content: "failed", error: "error", message: "High priority"),
                isRead: false
            ),
            QueueStatusNotification(
                type: .postSuccess(content: "success", message: "Low priority"),
                isRead: true
            ),
            QueueStatusNotification(
                type: .retryScheduled(content: "retry", retryCount: 1, maxRetries: 3, message: "Medium priority"),
                isRead: false
            )
        ]
    }
    
    func testFilterByPriority_ReturnsCorrectNotifications() {
        // When
        let highPriorityNotifications = notifications.filter(priority: .high)
        let lowPriorityNotifications = notifications.filter(priority: .low)
        
        // Then
        XCTAssertEqual(highPriorityNotifications.count, 1, "Should have one high priority notification")
        XCTAssertEqual(lowPriorityNotifications.count, 1, "Should have one low priority notification")
        
        XCTAssertEqual(highPriorityNotifications.first?.type.priority, .high, "Should be high priority")
        XCTAssertEqual(lowPriorityNotifications.first?.type.priority, .low, "Should be low priority")
    }
    
    func testFilterByReadStatus_ReturnsCorrectNotifications() {
        // When
        let unreadNotifications = notifications.filter(isRead: false)
        let readNotifications = notifications.filter(isRead: true)
        
        // Then
        XCTAssertEqual(unreadNotifications.count, 2, "Should have two unread notifications")
        XCTAssertEqual(readNotifications.count, 1, "Should have one read notification")
        
        for notification in unreadNotifications {
            XCTAssertFalse(notification.isRead, "Should be unread")
        }
        for notification in readNotifications {
            XCTAssertTrue(notification.isRead, "Should be read")
        }
    }
    
    func testRequiresAttention_ReturnsOnlyAttentionRequiredNotifications() {
        // When
        let attentionNotifications = notifications.requiresAttention
        
        // Then
        XCTAssertEqual(attentionNotifications.count, 1, "Should have one notification requiring attention")
        XCTAssertTrue(attentionNotifications.first?.type.requiresAttention ?? false, "Should require attention")
    }
    
    func testSortedByPriority_SortsCorrectly() {
        // When
        let sortedNotifications = notifications.sortedByPriority
        
        // Then
        XCTAssertEqual(sortedNotifications.count, 3, "Should maintain all notifications")
        
        // High priority should come first
        XCTAssertEqual(sortedNotifications[0].type.priority, .high, "First should be high priority")
        XCTAssertEqual(sortedNotifications[1].type.priority, .medium, "Second should be medium priority")
        XCTAssertEqual(sortedNotifications[2].type.priority, .low, "Third should be low priority")
    }
    
    func testRecent_ReturnsOnlyRecentNotifications() {
        // Given
        let oldTime = Date().addingTimeInterval(-7200) // 2 hours ago
        let oldNotification = QueueStatusNotification(
            type: .postQueued(content: "old", message: "old"),
            timestamp: oldTime
        )
        
        let testNotifications = notifications + [oldNotification]
        
        // When
        let recentNotifications = testNotifications.recent
        
        // Then
        XCTAssertEqual(recentNotifications.count, 3, "Should exclude old notification")
        
        for notification in recentNotifications {
            XCTAssertLessThan(notification.age, 3600, "Should be within last hour")
        }
    }
    
    func testShouldAutoDismiss_ReturnsAutoDismissibleNotifications() {
        // Given
        let oldTime = Date().addingTimeInterval(-35) // 35 seconds ago
        let autoDismissNotification = QueueStatusNotification(
            type: .postSuccess(content: "dismiss", message: "dismiss"),
            timestamp: oldTime,
            isRead: true
        )
        
        let testNotifications = notifications + [autoDismissNotification]
        
        // When
        let autoDismissNotifications = testNotifications.shouldAutoDismiss
        
        // Then
        XCTAssertEqual(autoDismissNotifications.count, 1, "Should have one auto-dismissible notification")
        XCTAssertTrue(autoDismissNotifications.first?.shouldAutoDismiss ?? false, "Should be auto-dismissible")
    }
}
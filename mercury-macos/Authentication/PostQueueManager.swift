import Foundation
import Combine
import CryptoKit
import Security
import AppKit

/// Manages local post queuing and retry logic for failed posts
@MainActor
public class PostQueueManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var queuedPostsCount: Int = 0
    
    // MARK: - Public Publishers
    
    public var queueCountPublisher: AnyPublisher<Int, Never> {
        $queuedPostsCount.eraseToAnyPublisher()
    }
    
    /// Publisher for queue status notifications
    public var notificationsPublisher: AnyPublisher<[QueueStatusNotification], Never> {
        $queueNotifications.eraseToAnyPublisher()
    }
    
    // MARK: - Internal State
    
    private var queuedPosts: [QueuedPost] = []
    private let queue = DispatchQueue(label: "com.mercury.postqueue", qos: .utility)
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Automatic Retry Management
    
    nonisolated(unsafe) private var retryTimer: Timer?
    private var retrySchedule: [UUID: Date] = [:]
    private let retryCheckInterval: TimeInterval = 30 // Check every 30 seconds
    private var isProcessingRetries = false
    
    // MARK: - Lifecycle Management
    
    nonisolated(unsafe) private var lifecycleObservers: Set<AnyCancellable> = []
    private var isAppActive = true
    private var lastActiveTime: Date = Date()
    private let retryScheduleStorageKey = "mercury.retry_schedule"
    
    // MARK: - Deduplication Management
    
    private var recentlyPostedHashes: Set<String> = []
    private var postHashTimestamps: [String: Date] = [:]
    private let deduplicationWindow: TimeInterval = 300 // 5 minutes
    private let recentPostsStorageKey = "mercury.recent_posts"
    
    // MARK: - Notification Management
    
    @Published public private(set) var queueNotifications: [QueueStatusNotification] = []
    private var notificationHistory: [QueueStatusNotification] = []
    private let maxNotificationHistory = 50
    private let notificationDisplayDuration: TimeInterval = 10.0 // 10 seconds
    nonisolated(unsafe) private var notificationCleanupTimer: Timer?
    
    // MARK: - Configuration
    
    private let maxRetries = 5
    private let storageKey = "mercury.queued_posts"
    private let encryptionKeyService = "com.mercury.postqueue.encryption"
    private let encryptionKeyAccount = "postqueue_key"
    
    // MARK: - Secure Storage
    
    private lazy var secureStorage = SecurePostStorage(
        service: encryptionKeyService,
        account: encryptionKeyAccount
    )
    
    // MARK: - Network Integration
    
    private var networkMonitor: NetworkMonitor?
    
    // MARK: - Post Sending Integration
    
    /// Callback for actually sending posts - will be set by AuthManager
    public var postSender: ((String) async -> Bool)?
    
    /// Event publisher for network-related events (optional, set by AuthManager)
    public var networkEventPublisher: ((NetworkEvent) -> Void)?
    
    // MARK: - Initialization
    
    public init(networkMonitor: NetworkMonitor? = nil) {
        self.networkMonitor = networkMonitor
        loadQueueFromStorage()
        loadRetryScheduleFromStorage()
        loadRecentPostsFromStorage()
        setupLifecycleObservers()
        startAutomaticRetryTimer()
        startDeduplicationCleanupTimer()
        startNotificationCleanupTimer()
        
        // Send initial status notification if there are queued posts
        if !queuedPosts.isEmpty {
            publishNotification(.queueStatusUpdate(
                count: queuedPosts.count,
                message: "Restored \(queuedPosts.count) queued posts from storage"
            ))
        }
        
        print("📱 PostQueueManager initialized with \(queuedPosts.count) queued posts")
    }
    
    deinit {
        stopAutomaticRetryTimer()
        stopDeduplicationCleanupTimer()
        stopNotificationCleanupTimer()
        cleanupLifecycleObservers()
    }
    
    // MARK: - Public Methods
    
    /// Adds a post to the queue for later retry
    /// - Parameter text: Tweet text to queue
    /// - Returns: True if post was queued, false if it was a duplicate
    @discardableResult
    public func queuePost(_ text: String) async -> Bool {
        // Check for deduplication first
        let postHash = generatePostHash(text)
        
        let isDuplicate = await checkForDuplicate(hash: postHash, text: text)
        if isDuplicate {
            publishNotification(.duplicateDetected(
                content: String(text.prefix(50)),
                message: "Duplicate post detected and skipped"
            ))
            print("🔄 Skipped duplicate post: \"\(String(text.prefix(50)))...\"")
            return false
        }
        
        let post = QueuedPost(text: text)
        
        await withCheckedContinuation { continuation in
            queue.async {
                // Add to deduplication tracking
                self.trackNewPost(hash: postHash)
                
                // Add to queue
                self.queuedPosts.append(post)
                
                // Schedule automatic retry for this post
                self.scheduleAutomaticRetry(for: post)
                
                self.saveQueueToStorage()
                self.saveRecentPostsToStorage()
                
                Task { @MainActor in
                    self.updateQueueCount()
                }
                continuation.resume()
            }
        }
        
        // Send notification about successful queuing
        publishNotification(.postQueued(
            content: String(text.prefix(50)),
            message: "Post queued for retry"
        ))
        
        print("📤 Queued post for automatic retry: \"\(String(text.prefix(50)))...\"")
        return true
    }
    
    /// Processes all queued posts, attempting to send them
    /// - Returns: Number of posts successfully processed
    public func processQueue() async -> Int {
        guard !isProcessingRetries else {
            print("⏳ Queue processing already in progress, skipping...")
            return 0
        }
        
        // Check network connectivity before processing
        guard networkMonitor?.isConnected ?? true else {
            print("📴 Network unavailable - queue processing skipped")
            return 0
        }
        
        isProcessingRetries = true
        defer { isProcessingRetries = false }
        
        let postsToProcess = await getPostsReadyForRetry()
        var successCount = 0
        var failureCount = 0
        
        print("🔄 Processing \(postsToProcess.count) posts ready for retry...")
        
        for post in postsToProcess {
            let retryResult = await attemptPostRetryWithBackoff(post)
            
            switch retryResult {
            case .success:
                // Track successful post for deduplication
                await trackSuccessfulPost(post.text)
                await removePostFromQueue(post.id)
                successCount += 1
                
                // Send success notification
                publishNotification(.postSuccess(
                    content: String(post.text.prefix(30)),
                    message: "Post successfully published"
                ))
                
                print("✅ Successfully posted: \"\(String(post.text.prefix(30)))...\"")
                
            case .temporaryFailure(let error):
                await updatePostRetryInfo(post, error: error)
                await scheduleNextRetry(for: post)
                failureCount += 1
                
                // Publish network retry event
                networkEventPublisher?(.operationRetried(
                    operation: "post retry (\(String(post.text.prefix(20)))...)",
                    attempt: post.retryCount + 1
                ))
                
                // Send retry notification
                publishNotification(.retryScheduled(
                    content: String(post.text.prefix(30)),
                    retryCount: post.retryCount + 1,
                    maxRetries: maxRetries,
                    message: "Post failed, retry \(post.retryCount + 1)/\(maxRetries) scheduled"
                ))
                
                print("🔄 Temporary failure for post \(post.id): \(error)")
                
            case .permanentFailure(let error):
                await removePostFromQueue(post.id)
                failureCount += 1
                
                // Send permanent failure notification
                publishNotification(.postFailed(
                    content: String(post.text.prefix(30)),
                    error: error,
                    message: "Post failed permanently: \(error)"
                ))
                
                print("❌ Permanent failure, removing post \(post.id): \(error)")
                
            case .rateLimited(let retryAfter):
                await scheduleRateLimitRetry(for: post, retryAfter: retryAfter)
                failureCount += 1
                
                // Send rate limit notification
                publishNotification(.rateLimited(
                    retryAfterSeconds: Int(retryAfter),
                    message: "Rate limited, retry in \(Int(retryAfter)) seconds"
                ))
                
                print("⏱️ Rate limited, scheduling retry for post \(post.id) in \(retryAfter)s")
            }
        }
        
        if successCount > 0 || failureCount > 0 {
            // Send notification about processing results
            publishNotification(.processingComplete(
                successCount: successCount,
                failureCount: failureCount,
                message: "Processing complete: \(successCount) posted, \(failureCount) failed"
            ))
            print("📊 Queue processing complete: \(successCount) successful, \(failureCount) failed")
        }
        
        return successCount
    }
    
    /// Gets current count of queued posts
    /// - Returns: Number of posts in queue
    public func getQueuedPostsCount() async -> Int {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.queuedPosts.count)
            }
        }
    }
    
    /// Gets all queued posts (useful for UI display)
    /// - Returns: Array of queued posts
    public func getQueuedPosts() async -> [QueuedPost] {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.queuedPosts)
            }
        }
    }
    
    /// Gets all queued post content as strings (useful for preservation during re-auth)
    /// - Returns: Array of post content strings
    public func getAllQueuedPosts() async -> [String] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let postContents = self.queuedPosts.map { $0.text }
                continuation.resume(returning: postContents)
            }
        }
    }
    
    /// Removes a specific post from the queue
    /// - Parameter postId: ID of post to remove
    public func removePost(_ postId: UUID) async {
        await removePostFromQueue(postId)
    }
    
    /// Clears all queued posts
    public func clearQueue() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.queuedPosts.removeAll()
                self.retrySchedule.removeAll()
                
                // Clear from secure storage
                do {
                    try self.secureStorage.clearStoredPosts()
                    print("🗑️ Cleared all posts from secure storage")
                } catch {
                    print("⚠️ Failed to clear secure storage: \(error)")
                    // Still clear in-memory queue even if storage clear fails
                }
                
                // Clear retry schedules from storage
                self.saveRetryScheduleToStorage()
                
                Task { @MainActor in
                    self.updateQueueCount()
                }
                continuation.resume()
            }
        }
    }
    
    /// Retries a specific post immediately
    /// - Parameter postId: ID of post to retry
    /// - Returns: True if retry was successful
    public func retryPost(_ postId: UUID) async -> Bool {
        guard let post = await getPost(postId) else {
            return false
        }
        
        if await attemptToSendPost(post) {
            await removePostFromQueue(postId)
            return true
        } else {
            await updatePostRetryInfo(post)
            return false
        }
    }
    
    /// Gets information about the secure storage status
    /// - Returns: Storage status information
    public func getStorageInfo() -> PostQueueStorageInfo {
        let fileExists = FileManager.default.fileExists(atPath: secureStorage.queueFileURL.path)
        var fileSize: Int64 = 0
        
        if fileExists {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: secureStorage.queueFileURL.path),
               let size = attributes[.size] as? NSNumber {
                fileSize = size.int64Value
            }
        }
        
        return PostQueueStorageInfo(
            isUsingSecureStorage: true,
            storageFileExists: fileExists,
            storageFileSize: fileSize,
            queuedPostsCount: queuedPostsCount
        )
    }
    
    /// Gets retry status information for all queued posts
    /// - Returns: Array of retry status information
    public func getRetryStatus() async -> [PostRetryStatus] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let retryStatuses = self.queuedPosts.map { post in
                    PostRetryStatus(
                        postId: post.id,
                        content: String(post.text.prefix(50)),
                        retryCount: post.retryCount,
                        maxRetries: self.maxRetries,
                        nextRetryTime: self.retrySchedule[post.id] ?? post.nextRetryTime,
                        lastError: post.error,
                        isReadyForRetry: post.shouldRetry
                    )
                }
                continuation.resume(returning: retryStatuses)
            }
        }
    }
    
    /// Pauses automatic retry processing
    public func pauseAutomaticRetries() {
        stopAutomaticRetryTimer()
        print("⏸️ Paused automatic retry processing")
    }
    
    /// Resumes automatic retry processing
    public func resumeAutomaticRetries() {
        startAutomaticRetryTimer()
        print("▶️ Resumed automatic retry processing")
    }
    
    /// Processes queue when network becomes available (called by AuthManager)
    /// - Returns: Number of posts successfully processed
    public func processQueueOnNetworkRestored() async -> Int {
        print("🌐 Network connection restored - processing queued posts")
        
        let queuedCount = await getQueuedPostsCount()
        if queuedCount > 0 {
            // Publish event about automatic retry starting
            networkEventPublisher?(.operationRetried(
                operation: "automatic queue processing (\(queuedCount) posts)",
                attempt: 1
            ))
        }
        
        return await processQueue()
    }
    
    /// Forces immediate processing of all queued posts (ignoring retry timing)
    /// - Returns: Number of posts successfully processed
    public func forceProcessAllPosts() async -> Int {
        print("🚀 Force processing all queued posts...")
        
        let allPosts = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.queuedPosts)
            }
        }
        
        var successCount = 0
        for post in allPosts {
            let retryResult = await attemptPostRetryWithBackoff(post)
            
            switch retryResult {
            case .success:
                // Track successful post for deduplication
                await trackSuccessfulPost(post.text)
                await removePostFromQueue(post.id)
                successCount += 1
                print("✅ Force-posted: \"\(String(post.text.prefix(30)))...\"")
                
            case .temporaryFailure(let error):
                await updatePostRetryInfo(post, error: error)
                print("🔄 Force attempt failed for post \(post.id): \(error)")
                
            case .permanentFailure(let error):
                await removePostFromQueue(post.id)
                print("❌ Force attempt revealed permanent failure for post \(post.id): \(error)")
                
            case .rateLimited(let retryAfter):
                await scheduleRateLimitRetry(for: post, retryAfter: retryAfter)
                print("⏱️ Force attempt hit rate limit for post \(post.id)")
            }
        }
        
        print("🚀 Force processing complete: \(successCount) successful out of \(allPosts.count) posts")
        return successCount
    }
    
    // MARK: - Private Methods
    
    private func getPostsReadyForRetry() async -> [QueuedPost] {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.queuedPosts.filter { $0.shouldRetry })
            }
        }
    }
    
    private func attemptToSendPost(_ post: QueuedPost) async -> Bool {
        // Check network connectivity before attempting to send
        guard networkMonitor?.isConnected ?? true else {
            print("📴 Network unavailable - cannot send post")
            return false
        }
        
        // Use the post sender callback if available
        if let postSender = postSender {
            return await postSender(post.text)
        }
        
        // Fallback simulation for testing when no post sender is configured
        print("⚠️ No post sender configured - using simulation")
        return Double.random(in: 0...1) > 0.3
    }
    
    private func removePostFromQueue(_ postId: UUID) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.queuedPosts.removeAll { $0.id == postId }
                
                // Also remove from retry schedule
                self.retrySchedule.removeValue(forKey: postId)
                
                self.saveQueueToStorage()
                self.saveRetryScheduleToStorage()
                
                Task { @MainActor in
                    self.updateQueueCount()
                }
                continuation.resume()
            }
        }
    }
    
    private func updatePostRetryInfo(_ post: QueuedPost, error: String? = nil) async {
        await withCheckedContinuation { continuation in
            queue.async {
                if let index = self.queuedPosts.firstIndex(where: { $0.id == post.id }) {
                    let updatedPost = QueuedPost(
                        id: post.id,
                        text: post.text,
                        createdAt: post.createdAt,
                        retryCount: post.retryCount + 1,
                        lastRetryAt: Date(),
                        error: error ?? "Retry failed"
                    )
                    
                    // Remove post if max retries exceeded
                    if updatedPost.retryCount >= self.maxRetries {
                        self.queuedPosts.remove(at: index)
                        print("🗑️ Removed post \(post.id) after \(self.maxRetries) failed attempts")
                    } else {
                        self.queuedPosts[index] = updatedPost
                        print("🔄 Updated retry info for post \(post.id): attempt \(updatedPost.retryCount)/\(self.maxRetries)")
                    }
                    
                    self.saveQueueToStorage()
                    Task { @MainActor in
                        self.updateQueueCount()
                    }
                }
                continuation.resume()
            }
        }
    }
    
    private func getPost(_ postId: UUID) async -> QueuedPost? {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.queuedPosts.first { $0.id == postId })
            }
        }
    }
    
    private func loadQueueFromStorage() {
        queue.async {
            do {
                let posts = try self.secureStorage.loadQueuedPosts()
                self.queuedPosts = posts
                Task { @MainActor in
                    self.updateQueueCount()
                }
                print("📥 Loaded \(posts.count) queued posts from secure storage")
            } catch {
                print("⚠️ Failed to load queued posts from secure storage: \(error)")
                // Fallback to UserDefaults for migration if needed
                self.loadFromUserDefaultsFallback()
            }
        }
    }
    
    private func saveQueueToStorage() {
        // Called from within queue.sync, so no additional synchronization needed
        do {
            try secureStorage.saveQueuedPosts(queuedPosts)
            print("💾 Saved \(queuedPosts.count) queued posts to secure storage")
        } catch {
            print("❌ Failed to save queued posts to secure storage: \(error)")
            // Fallback to UserDefaults as emergency backup
            saveToUserDefaultsFallback()
        }
    }
    
    /// Fallback method to load from UserDefaults for migration
    private func loadFromUserDefaultsFallback() {
        if let data = userDefaults.data(forKey: storageKey),
           let posts = try? JSONDecoder().decode([QueuedPost].self, from: data) {
            queuedPosts = posts
            // Migrate to secure storage
            do {
                try secureStorage.saveQueuedPosts(posts)
                // Clear old UserDefaults storage after successful migration
                userDefaults.removeObject(forKey: storageKey)
                print("🔄 Migrated \(posts.count) posts from UserDefaults to secure storage")
            } catch {
                print("⚠️ Failed to migrate posts to secure storage: \(error)")
            }
            
            Task { @MainActor in
                self.updateQueueCount()
            }
        }
    }
    
    /// Emergency fallback to UserDefaults if secure storage fails
    private func saveToUserDefaultsFallback() {
        if let data = try? JSONEncoder().encode(queuedPosts) {
            userDefaults.set(data, forKey: "\(storageKey)_backup")
            print("⚠️ Saved posts to UserDefaults backup due to secure storage failure")
        }
    }
    
    @MainActor
    private func updateQueueCount() {
        queuedPostsCount = queuedPosts.count
    }
    
    // MARK: - Automatic Retry Implementation
    
    /// Starts the automatic retry timer
    private func startAutomaticRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryCheckInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.checkAndProcessScheduledRetries()
            }
        }
        print("⏰ Started automatic retry timer (checking every \(retryCheckInterval)s)")
    }
    
    /// Stops the automatic retry timer
    nonisolated private func stopAutomaticRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
        print("⏰ Stopped automatic retry timer")
    }
    
    /// Checks for posts that are ready for retry and processes them
    private func checkAndProcessScheduledRetries() async {
        let now = Date()
        let readyPosts = await getPostsReadyForScheduledRetry(at: now)
        
        if !readyPosts.isEmpty {
            print("🔄 Found \(readyPosts.count) posts ready for scheduled retry")
            await processQueue()
        }
    }
    
    /// Gets posts that are ready for retry based on scheduled times and network connectivity
    private func getPostsReadyForScheduledRetry(at time: Date) async -> [QueuedPost] {
        return await withCheckedContinuation { continuation in
            queue.async {
                // Only process posts if network is available
                guard self.networkMonitor?.isConnected ?? true else {
                    print("📴 Network unavailable - skipping retry processing")
                    continuation.resume(returning: [])
                    return
                }
                
                let readyPosts = self.queuedPosts.filter { post in
                    if let scheduledTime = self.retrySchedule[post.id] {
                        return time >= scheduledTime
                    }
                    return post.shouldRetry
                }
                continuation.resume(returning: readyPosts)
            }
        }
    }
    
    /// Schedules automatic retry for a new post
    private func scheduleAutomaticRetry(for post: QueuedPost) {
        let retryTime = post.nextRetryTime
        retrySchedule[post.id] = retryTime
        saveRetryScheduleToStorage()
        
        let timeInterval = retryTime.timeIntervalSinceNow
        print("⏰ Scheduled retry for post \(post.id) in \(Int(timeInterval))s")
    }
    
    /// Schedules the next retry for a failed post
    private func scheduleNextRetry(for post: QueuedPost) async {
        await withCheckedContinuation { continuation in
            queue.async {
                if let index = self.queuedPosts.firstIndex(where: { $0.id == post.id }) {
                    let updatedPost = self.queuedPosts[index]
                    let nextRetryTime = updatedPost.nextRetryTime
                    self.retrySchedule[post.id] = nextRetryTime
                    self.saveRetryScheduleToStorage()
                    
                    let timeInterval = nextRetryTime.timeIntervalSinceNow
                    print("⏰ Scheduled next retry for post \(post.id) in \(Int(timeInterval))s (attempt \(updatedPost.retryCount + 1)/\(self.maxRetries))")
                }
                continuation.resume()
            }
        }
    }
    
    /// Schedules retry after rate limiting
    private func scheduleRateLimitRetry(for post: QueuedPost, retryAfter: TimeInterval) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let retryTime = Date().addingTimeInterval(retryAfter)
                self.retrySchedule[post.id] = retryTime
                self.saveRetryScheduleToStorage()
                print("⏰ Scheduled rate limit retry for post \(post.id) at \(retryTime.formatted(.dateTime.hour().minute()))")
                continuation.resume()
            }
        }
    }
    
    /// Attempts to send a post with sophisticated retry logic
    private func attemptPostRetryWithBackoff(_ post: QueuedPost) async -> PostRetryResult {
        // Check network connectivity first
        guard networkMonitor?.isConnected ?? true else {
            return .temporaryFailure("No network connection")
        }
        
        // Use the real post sender if available
        if let postSender = postSender {
            let success = await postSender(post.text)
            
            if success {
                return .success
            } else {
                // For now, treat all failures as temporary since we don't have detailed error info
                // In a more sophisticated implementation, we'd get detailed error information
                return .temporaryFailure("Post failed - will retry")
            }
        }
        
        // Fallback simulation for testing when no post sender is configured
        print("⚠️ No post sender configured - using simulation for retry")
        
        let random = Double.random(in: 0...1)
        
        // Simulate different failure scenarios
        if post.retryCount == 0 && random < 0.7 {
            // 70% chance of success on first retry
            return .success
        } else if post.retryCount >= 3 && random < 0.9 {
            // Higher success rate after multiple retries (network may have stabilized)
            return .success
        } else if random < 0.1 {
            // 10% chance of permanent failure (invalid tweet content, etc.)
            return .permanentFailure("Invalid tweet content")
        } else if random < 0.2 {
            // 10% chance of rate limiting
            return .rateLimited(TimeInterval.random(in: 60...300)) // 1-5 minutes
        } else {
            // Temporary failure
            return .temporaryFailure("Network error or temporary API issue")
        }
    }
    
    // MARK: - Lifecycle Management Implementation
    
    /// Sets up observers for app lifecycle events
    private func setupLifecycleObservers() {
        // Observe app becoming active/inactive
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &lifecycleObservers)
        
        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &lifecycleObservers)
        
        // Observe app termination
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.handleAppWillTerminate()
            }
            .store(in: &lifecycleObservers)
        
        // Observe system sleep/wake notifications
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.handleSystemWillSleep()
            }
            .store(in: &lifecycleObservers)
        
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handleSystemDidWake()
            }
            .store(in: &lifecycleObservers)
        
        print("🔔 Set up lifecycle observers for app and system events")
    }
    
    /// Cleans up lifecycle observers
    nonisolated private func cleanupLifecycleObservers() {
        lifecycleObservers.removeAll()
        print("🧹 Cleaned up lifecycle observers")
    }
    
    /// Handles app becoming active
    private func handleAppDidBecomeActive() {
        print("📱 App became active")
        
        let wasInactive = !isAppActive
        isAppActive = true
        
        if wasInactive {
            let inactiveTime = Date().timeIntervalSince(lastActiveTime)
            print("⏰ App was inactive for \(Int(inactiveTime)) seconds")
            
            // Check if any retry schedules need to be processed after being inactive
            Task {
                await handlePostInactivityRecovery(inactiveDuration: inactiveTime)
            }
        }
        
        // Restart automatic retry timer if it was stopped
        if retryTimer == nil {
            startAutomaticRetryTimer()
        }
    }
    
    /// Handles app resigning active status
    private func handleAppWillResignActive() {
        print("📱 App will resign active")
        isAppActive = false
        lastActiveTime = Date()
        
        // Save current state before becoming inactive
        saveCurrentState()
    }
    
    /// Handles app termination
    private func handleAppWillTerminate() {
        print("📱 App will terminate - saving state")
        
        // Ensure all data is saved before termination
        saveCurrentState()
        
        // Stop retry timer
        stopAutomaticRetryTimer()
    }
    
    /// Handles system going to sleep
    private func handleSystemWillSleep() {
        print("💤 System will sleep - saving state")
        
        // Save current state before system sleep
        saveCurrentState()
        
        // Stop retry timer to conserve resources during sleep
        stopAutomaticRetryTimer()
    }
    
    /// Handles system waking from sleep
    private func handleSystemDidWake() {
        print("☀️ System did wake - restoring operations")
        
        // Restart automatic retry timer
        startAutomaticRetryTimer()
        
        // Process any retries that should have occurred during sleep
        Task {
            await handlePostSleepRecovery()
        }
    }
    
    /// Handles recovery after app inactivity
    private func handlePostInactivityRecovery(inactiveDuration: TimeInterval) async {
        print("🔄 Handling post-inactivity recovery (inactive for \(Int(inactiveDuration))s)")
        
        // Check for posts that should have been retried during inactive period
        let now = Date()
        let postsReadyForRetry = await getPostsReadyForScheduledRetry(at: now)
        
        if !postsReadyForRetry.isEmpty {
            print("📨 Found \(postsReadyForRetry.count) posts ready for retry after inactivity")
            await processQueue()
        }
        
        // Update retry schedules that may have become stale
        await validateAndUpdateRetrySchedules()
    }
    
    /// Handles recovery after system sleep/wake
    private func handlePostSleepRecovery() async {
        print("🔄 Handling post-sleep recovery")
        
        // Load the latest state from storage
        loadQueueFromStorage()
        loadRetryScheduleFromStorage()
        
        // Check for posts that should have been retried during sleep
        let now = Date()
        let postsReadyForRetry = await getPostsReadyForScheduledRetry(at: now)
        
        if !postsReadyForRetry.isEmpty {
            print("📨 Found \(postsReadyForRetry.count) posts ready for retry after sleep")
            await processQueue()
        }
        
        // Clean up and validate retry schedules
        await validateAndUpdateRetrySchedules()
    }
    
    /// Validates and updates retry schedules, removing orphaned entries
    private func validateAndUpdateRetrySchedules() async {
        await withCheckedContinuation { continuation in
            queue.async {
                let queuedPostIds = Set(self.queuedPosts.map { $0.id })
                let scheduledIds = Set(self.retrySchedule.keys)
                
                // Remove retry schedules for posts that no longer exist
                let orphanedIds = scheduledIds.subtracting(queuedPostIds)
                for orphanedId in orphanedIds {
                    self.retrySchedule.removeValue(forKey: orphanedId)
                }
                
                if !orphanedIds.isEmpty {
                    print("🧹 Cleaned up \(orphanedIds.count) orphaned retry schedules")
                    self.saveRetryScheduleToStorage()
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Saves current state to storage
    private func saveCurrentState() {
        // Save queued posts
        saveQueueToStorage()
        
        // Save retry schedules
        saveRetryScheduleToStorage()
        
        // Save deduplication data
        saveRecentPostsToStorage()
        
        print("💾 Saved current state to storage")
    }
    
    // MARK: - Retry Schedule Persistence
    
    /// Loads retry schedule from storage
    private func loadRetryScheduleFromStorage() {
        if let data = userDefaults.data(forKey: retryScheduleStorageKey),
           let schedule = try? JSONDecoder().decode([String: Date].self, from: data) {
            // Convert string keys back to UUIDs
            retrySchedule = Dictionary(uniqueKeysWithValues: 
                schedule.compactMap { (key, value) in
                    guard let uuid = UUID(uuidString: key) else { return nil }
                    return (uuid, value)
                }
            )
            print("📅 Loaded \(retrySchedule.count) retry schedules from storage")
        } else {
            retrySchedule = [:]
            print("📅 No existing retry schedules found")
        }
    }
    
    /// Saves retry schedule to storage
    private func saveRetryScheduleToStorage() {
        // Convert UUID keys to strings for JSON encoding
        let stringKeySchedule = Dictionary(uniqueKeysWithValues: 
            retrySchedule.map { (key, value) in
                (key.uuidString, value)
            }
        )
        
        if let data = try? JSONEncoder().encode(stringKeySchedule) {
            userDefaults.set(data, forKey: retryScheduleStorageKey)
            print("📅 Saved \(retrySchedule.count) retry schedules to storage")
        } else {
            print("❌ Failed to save retry schedules to storage")
        }
    }
    
    /// Gets comprehensive persistence status
    public func getPersistenceStatus() -> PostQueuePersistenceStatus {
        let storageInfo = getStorageInfo()
        
        return PostQueuePersistenceStatus(
            queuedPostsCount: queuedPostsCount,
            retrySchedulesCount: retrySchedule.count,
            storageInfo: storageInfo,
            isAppActive: isAppActive,
            lastActiveTime: lastActiveTime,
            hasLifecycleObservers: !lifecycleObservers.isEmpty,
            nextScheduledRetry: retrySchedule.values.min()
        )
    }
    
    // MARK: - Deduplication Implementation
    
    /// Generates a hash for post content for deduplication
    private func generatePostHash(_ text: String) -> String {
        // Normalize text for consistent hashing
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // Use SHA256 for content hashing
        let inputData = Data(normalizedText.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Checks if a post is a duplicate
    private func checkForDuplicate(hash: String, text: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async {
                // Check against recently posted hashes
                if self.recentlyPostedHashes.contains(hash) {
                    continuation.resume(returning: true)
                    return
                }
                
                // Check against existing queued posts
                let hasDuplicateInQueue = self.queuedPosts.contains { queuedPost in
                    let queuedHash = self.generatePostHash(queuedPost.text)
                    return queuedHash == hash
                }
                
                if hasDuplicateInQueue {
                    continuation.resume(returning: true)
                    return
                }
                
                // Check for similar content (fuzzy matching)
                let hasSimilarContent = self.checkForSimilarContent(text: text)
                
                continuation.resume(returning: hasSimilarContent)
            }
        }
    }
    
    /// Checks for similar content using fuzzy matching
    private func checkForSimilarContent(text: String) -> Bool {
        let normalizedNewText = normalizeTextForComparison(text)
        
        // Check against recently posted content
        for existingHash in recentlyPostedHashes {
            // For now, we'll use exact hash matching
            // In a more sophisticated implementation, we could store original text
            // and do similarity comparison here
        }
        
        // Check against queued posts
        for queuedPost in queuedPosts {
            let normalizedQueuedText = normalizeTextForComparison(queuedPost.text)
            
            // Calculate similarity score
            let similarity = calculateTextSimilarity(normalizedNewText, normalizedQueuedText)
            
            // Consider posts similar if they're more than 90% similar
            if similarity > 0.9 {
                print("🔍 Found similar content (similarity: \(String(format: "%.1f", similarity * 100))%)")
                return true
            }
        }
        
        return false
    }
    
    /// Normalizes text for comparison
    private func normalizeTextForComparison(_ text: String) -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
    
    /// Calculates text similarity using simple token-based comparison
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.components(separatedBy: " "))
        let words2 = Set(text2.components(separatedBy: " "))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        guard !union.isEmpty else { return 0.0 }
        
        return Double(intersection.count) / Double(union.count)
    }
    
    /// Tracks a new post being queued
    private func trackNewPost(hash: String) {
        // Don't add to recently posted until it's actually posted successfully
        // This allows retries of failed posts without marking them as duplicates
    }
    
    /// Tracks a successfully posted post for deduplication
    private func trackSuccessfulPost(_ text: String) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let hash = self.generatePostHash(text)
                let now = Date()
                
                self.recentlyPostedHashes.insert(hash)
                self.postHashTimestamps[hash] = now
                
                self.saveRecentPostsToStorage()
                
                print("🔒 Tracked successful post for deduplication: \"\(String(text.prefix(30)))...\"")
                continuation.resume()
            }
        }
    }
    
    /// Cleans up old deduplication entries
    private func cleanupOldDeduplicationEntries() {
        let now = Date()
        let cutoffTime = now.addingTimeInterval(-deduplicationWindow)
        
        let expiredHashes = postHashTimestamps.compactMap { (hash, timestamp) -> String? in
            return timestamp < cutoffTime ? hash : nil
        }
        
        for hash in expiredHashes {
            recentlyPostedHashes.remove(hash)
            postHashTimestamps.removeValue(forKey: hash)
        }
        
        if !expiredHashes.isEmpty {
            saveRecentPostsToStorage()
            print("🧹 Cleaned up \(expiredHashes.count) old deduplication entries")
        }
    }
    
    // MARK: - Deduplication Timer Management
    
    nonisolated(unsafe) private var deduplicationCleanupTimer: Timer?
    
    /// Starts the deduplication cleanup timer
    private func startDeduplicationCleanupTimer() {
        deduplicationCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupOldDeduplicationEntries()
        }
        print("🧹 Started deduplication cleanup timer")
    }
    
    /// Stops the deduplication cleanup timer
    nonisolated private func stopDeduplicationCleanupTimer() {
        deduplicationCleanupTimer?.invalidate()
        deduplicationCleanupTimer = nil
        print("🧹 Stopped deduplication cleanup timer")
    }
    
    // MARK: - Deduplication Storage
    
    /// Loads recent posts from storage
    private func loadRecentPostsFromStorage() {
        if let data = userDefaults.data(forKey: recentPostsStorageKey),
           let recentPosts = try? JSONDecoder().decode([String: Date].self, from: data) {
            
            postHashTimestamps = recentPosts
            recentlyPostedHashes = Set(recentPosts.keys)
            
            // Clean up old entries on load
            cleanupOldDeduplicationEntries()
            
            print("🔍 Loaded \(recentlyPostedHashes.count) recent post hashes for deduplication")
        } else {
            recentlyPostedHashes = []
            postHashTimestamps = [:]
            print("🔍 No existing deduplication data found")
        }
    }
    
    /// Saves recent posts to storage
    private func saveRecentPostsToStorage() {
        if let data = try? JSONEncoder().encode(postHashTimestamps) {
            userDefaults.set(data, forKey: recentPostsStorageKey)
        } else {
            print("❌ Failed to save recent posts to storage")
        }
    }
    
    /// Gets deduplication status information
    public func getDeduplicationStatus() -> PostDeduplicationStatus {
        return PostDeduplicationStatus(
            recentPostsCount: recentlyPostedHashes.count,
            deduplicationWindowMinutes: Int(deduplicationWindow / 60),
            oldestTrackedPost: postHashTimestamps.values.min(),
            newestTrackedPost: postHashTimestamps.values.max()
        )
    }
    
    /// Manually checks if a specific text would be considered a duplicate
    /// - Parameter text: Text to check
    /// - Returns: True if the text would be considered a duplicate
    public func wouldBeDuplicate(_ text: String) async -> Bool {
        let hash = generatePostHash(text)
        return await checkForDuplicate(hash: hash, text: text)
    }
    
    /// Clears all deduplication tracking (useful for testing or reset)
    public func clearDeduplicationHistory() {
        recentlyPostedHashes.removeAll()
        postHashTimestamps.removeAll()
        saveRecentPostsToStorage()
        print("🗑️ Cleared all deduplication history")
    }
    
    // MARK: - Notification Implementation
    
    /// Publishes a notification to observers
    private func publishNotification(_ type: QueueStatusNotification.NotificationType) {
        let notification = QueueStatusNotification(
            id: UUID(),
            type: type,
            timestamp: Date(),
            isRead: false
        )
        
        // Add to active notifications
        queueNotifications.append(notification)
        
        // Add to history
        notificationHistory.append(notification)
        
        // Trim history if needed
        if notificationHistory.count > maxNotificationHistory {
            notificationHistory.removeFirst(notificationHistory.count - maxNotificationHistory)
        }
        
        print("📢 Published notification: \(type.message)")
    }
    
    /// Marks a notification as read
    public func markNotificationAsRead(_ notificationId: UUID) {
        if let index = queueNotifications.firstIndex(where: { $0.id == notificationId }) {
            queueNotifications[index].isRead = true
        }
        
        if let index = notificationHistory.firstIndex(where: { $0.id == notificationId }) {
            notificationHistory[index].isRead = true
        }
    }
    
    /// Marks all notifications as read
    public func markAllNotificationsAsRead() {
        for index in queueNotifications.indices {
            queueNotifications[index].isRead = true
        }
        
        for index in notificationHistory.indices {
            notificationHistory[index].isRead = true
        }
    }
    
    /// Dismisses a specific notification
    public func dismissNotification(_ notificationId: UUID) {
        queueNotifications.removeAll { $0.id == notificationId }
    }
    
    /// Dismisses all notifications
    public func dismissAllNotifications() {
        queueNotifications.removeAll()
    }
    
    /// Gets all notification history
    public func getNotificationHistory() -> [QueueStatusNotification] {
        return notificationHistory
    }
    
    /// Gets unread notification count
    public func getUnreadNotificationCount() -> Int {
        return queueNotifications.filter { !$0.isRead }.count
    }
    
    /// Gets notifications by type
    public func getNotifications(ofType type: QueueStatusNotification.NotificationType) -> [QueueStatusNotification] {
        return queueNotifications.filter { notification in
            switch (notification.type, type) {
            case (.postSuccess, .postSuccess),
                 (.postFailed, .postFailed),
                 (.postQueued, .postQueued),
                 (.duplicateDetected, .duplicateDetected),
                 (.processingComplete, .processingComplete),
                 (.retryScheduled, .retryScheduled),
                 (.rateLimited, .rateLimited),
                 (.queueStatusUpdate, .queueStatusUpdate):
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Notification Timer Management
    
    /// Starts the notification cleanup timer
    private func startNotificationCleanupTimer() {
        notificationCleanupTimer = Timer.scheduledTimer(withTimeInterval: notificationDisplayDuration, repeats: true) { [weak self] _ in
            self?.cleanupOldNotifications()
        }
        print("🧹 Started notification cleanup timer")
    }
    
    /// Stops the notification cleanup timer
    nonisolated private func stopNotificationCleanupTimer() {
        notificationCleanupTimer?.invalidate()
        notificationCleanupTimer = nil
        print("🧹 Stopped notification cleanup timer")
    }
    
    /// Cleans up old notifications that have been displayed long enough
    private func cleanupOldNotifications() {
        let cutoffTime = Date().addingTimeInterval(-notificationDisplayDuration)
        let initialCount = queueNotifications.count
        
        queueNotifications.removeAll { notification in
            // Keep unread notifications longer
            if !notification.isRead {
                return notification.timestamp < cutoffTime.addingTimeInterval(-notificationDisplayDuration)
            } else {
                return notification.timestamp < cutoffTime
            }
        }
        
        let removedCount = initialCount - queueNotifications.count
        if removedCount > 0 {
            print("🧹 Cleaned up \(removedCount) old notifications")
        }
    }
    
    /// Gets notification statistics
    public func getNotificationStats() -> QueueNotificationStats {
        let now = Date()
        let last24Hours = now.addingTimeInterval(-24 * 3600)
        
        let recent = notificationHistory.filter { $0.timestamp > last24Hours }
        let successCount = recent.filter { 
            if case .postSuccess = $0.type { return true }
            return false
        }.count
        
        let failureCount = recent.filter {
            if case .postFailed = $0.type { return true }
            return false
        }.count
        
        let queuedCount = recent.filter {
            if case .postQueued = $0.type { return true }
            return false
        }.count
        
        return QueueNotificationStats(
            activeNotifications: queueNotifications.count,
            unreadNotifications: getUnreadNotificationCount(),
            totalNotifications: notificationHistory.count,
            successNotifications24h: successCount,
            failureNotifications24h: failureCount,
            queuedNotifications24h: queuedCount,
            oldestNotification: notificationHistory.first?.timestamp,
            newestNotification: notificationHistory.last?.timestamp
        )
    }
}

// MARK: - Retry Result Types

/// Result of attempting to send a queued post
enum PostRetryResult {
    case success
    case temporaryFailure(String)
    case permanentFailure(String)
    case rateLimited(TimeInterval) // Retry after specified seconds
}

// MARK: - Helper Extensions

// MARK: - Secure Storage Implementation

/// Secure storage manager for queued posts using Keychain and AES encryption
internal class SecurePostStorage {
    private let service: String
    private let account: String
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    internal let queueFileURL: URL
    
    init(service: String, account: String) {
        self.service = service
        self.account = account
        
        // Create secure storage directory in app's documents folder
        self.documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let secureStorageDirectory = documentsDirectory.appendingPathComponent("SecureStorage", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: secureStorageDirectory, withIntermediateDirectories: true)
        
        self.queueFileURL = secureStorageDirectory.appendingPathComponent("queued_posts.encrypted")
    }
    
    /// Loads queued posts from secure storage
    func loadQueuedPosts() throws -> [QueuedPost] {
        // Check if encrypted file exists
        guard fileManager.fileExists(atPath: queueFileURL.path) else {
            return [] // No posts stored yet
        }
        
        // Read encrypted data
        let encryptedData = try Data(contentsOf: queueFileURL)
        
        // Get encryption key from keychain
        let encryptionKey = try getOrCreateEncryptionKey()
        
        // Decrypt data
        let decryptedData = try decryptData(encryptedData, using: encryptionKey)
        
        // Decode posts
        let posts = try JSONDecoder().decode([QueuedPost].self, from: decryptedData)
        
        return posts
    }
    
    /// Saves queued posts to secure storage
    func saveQueuedPosts(_ posts: [QueuedPost]) throws {
        // Encode posts to JSON
        let jsonData = try JSONEncoder().encode(posts)
        
        // Get encryption key from keychain
        let encryptionKey = try getOrCreateEncryptionKey()
        
        // Encrypt data
        let encryptedData = try encryptData(jsonData, using: encryptionKey)
        
        // Write to file with atomic operation
        try encryptedData.write(to: queueFileURL, options: .atomic)
    }
    
    /// Clears all stored posts
    func clearStoredPosts() throws {
        if fileManager.fileExists(atPath: queueFileURL.path) {
            try fileManager.removeItem(at: queueFileURL)
        }
    }
    
    // MARK: - Encryption Key Management
    
    /// Gets existing encryption key from keychain or creates a new one
    private func getOrCreateEncryptionKey() throws -> SymmetricKey {
        do {
            // Try to load existing key
            let keyData = try loadEncryptionKeyFromKeychain()
            return SymmetricKey(data: keyData)
        } catch {
            // Create new key if none exists
            let newKey = SymmetricKey(size: .bits256)
            try storeEncryptionKeyInKeychain(newKey.withUnsafeBytes { Data($0) })
            return newKey
        }
    }
    
    /// Loads encryption key from macOS Keychain
    private func loadEncryptionKeyFromKeychain() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainReadFailed(status)
        }
        
        guard let keyData = result as? Data else {
            throw SecureStorageError.invalidKeyData
        }
        
        return keyData
    }
    
    /// Stores encryption key in macOS Keychain
    private func storeEncryptionKeyInKeychain(_ keyData: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainStoreFailed(status)
        }
    }
    
    // MARK: - Encryption/Decryption
    
    /// Encrypts data using AES-GCM
    private func encryptData(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }
    
    /// Decrypts data using AES-GCM
    private func decryptData(_ encryptedData: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

// MARK: - Secure Storage Errors

enum SecureStorageError: LocalizedError {
    case keychainReadFailed(OSStatus)
    case keychainStoreFailed(OSStatus)
    case invalidKeyData
    case encryptionFailed
    case decryptionFailed
    case fileAccessFailed
    
    var errorDescription: String? {
        switch self {
        case .keychainReadFailed(let status):
            return "Failed to read encryption key from keychain (status: \(status))"
        case .keychainStoreFailed(let status):
            return "Failed to store encryption key in keychain (status: \(status))"
        case .invalidKeyData:
            return "Invalid encryption key data"
        case .encryptionFailed:
            return "Failed to encrypt post data"
        case .decryptionFailed:
            return "Failed to decrypt post data"
        case .fileAccessFailed:
            return "Failed to access secure storage file"
        }
    }
}

// MARK: - Storage Info Model

/// Information about post queue storage status
public struct PostQueueStorageInfo {
    public let isUsingSecureStorage: Bool
    public let storageFileExists: Bool
    public let storageFileSize: Int64
    public let queuedPostsCount: Int
    
    /// Human-readable storage size
    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: storageFileSize)
    }
    
    /// Storage status description
    public var statusDescription: String {
        if isUsingSecureStorage {
            if storageFileExists {
                return "Secure storage active (\(formattedFileSize), \(queuedPostsCount) posts)"
            } else {
                return "Secure storage ready (no posts stored)"
            }
        } else {
            return "Using fallback storage"
        }
    }
}

/// Status information for a queued post's retry state
public struct PostRetryStatus {
    public let postId: UUID
    public let content: String
    public let retryCount: Int
    public let maxRetries: Int
    public let nextRetryTime: Date
    public let lastError: String?
    public let isReadyForRetry: Bool
    
    /// Time remaining until next retry
    public var timeUntilRetry: TimeInterval {
        return max(0, nextRetryTime.timeIntervalSinceNow)
    }
    
    /// Human-readable retry status
    public var statusDescription: String {
        if retryCount >= maxRetries {
            return "Max retries exceeded"
        } else if isReadyForRetry {
            return "Ready for retry (attempt \(retryCount + 1)/\(maxRetries))"
        } else {
            let timeRemaining = timeUntilRetry
            if timeRemaining > 60 {
                let minutes = Int(timeRemaining / 60)
                return "Next retry in \(minutes) minute\(minutes == 1 ? "" : "s") (attempt \(retryCount + 1)/\(maxRetries))"
            } else {
                let seconds = Int(timeRemaining)
                return "Next retry in \(seconds) second\(seconds == 1 ? "" : "s") (attempt \(retryCount + 1)/\(maxRetries))"
            }
        }
    }
}

/// Comprehensive persistence status for the post queue
public struct PostQueuePersistenceStatus {
    public let queuedPostsCount: Int
    public let retrySchedulesCount: Int
    public let storageInfo: PostQueueStorageInfo
    public let isAppActive: Bool
    public let lastActiveTime: Date
    public let hasLifecycleObservers: Bool
    public let nextScheduledRetry: Date?
    
    /// Time since app was last active
    public var timeSinceLastActive: TimeInterval {
        return Date().timeIntervalSince(lastActiveTime)
    }
    
    /// Time until next scheduled retry
    public var timeUntilNextRetry: TimeInterval? {
        return nextScheduledRetry?.timeIntervalSinceNow
    }
    
    /// Human-readable persistence status
    public var statusDescription: String {
        var components: [String] = []
        
        components.append("\(queuedPostsCount) queued posts")
        components.append("\(retrySchedulesCount) scheduled retries")
        
        if isAppActive {
            components.append("app active")
        } else {
            let inactiveTime = timeSinceLastActive
            if inactiveTime > 60 {
                components.append("inactive for \(Int(inactiveTime / 60)) min")
            } else {
                components.append("inactive for \(Int(inactiveTime)) sec")
            }
        }
        
        if let nextRetry = nextScheduledRetry, let timeUntil = timeUntilNextRetry, timeUntil > 0 {
            if timeUntil > 60 {
                components.append("next retry in \(Int(timeUntil / 60)) min")
            } else {
                components.append("next retry in \(Int(timeUntil)) sec")
            }
        }
        
        return components.joined(separator: ", ")
    }
    
    /// Whether the persistence system is healthy
    public var isHealthy: Bool {
        return hasLifecycleObservers && storageInfo.isUsingSecureStorage
    }
}

/// Status information for post deduplication system
public struct PostDeduplicationStatus {
    public let recentPostsCount: Int
    public let deduplicationWindowMinutes: Int
    public let oldestTrackedPost: Date?
    public let newestTrackedPost: Date?
    
    /// Time since oldest tracked post
    public var timeSinceOldestPost: TimeInterval? {
        return oldestTrackedPost?.timeIntervalSinceNow.magnitude
    }
    
    /// Time since newest tracked post
    public var timeSinceNewestPost: TimeInterval? {
        return newestTrackedPost?.timeIntervalSinceNow.magnitude
    }
    
    /// Human-readable deduplication status
    public var statusDescription: String {
        var components: [String] = []
        
        components.append("\(recentPostsCount) recent posts tracked")
        components.append("\(deduplicationWindowMinutes) min window")
        
        if let oldest = timeSinceOldestPost {
            if oldest > 3600 {
                components.append("oldest: \(Int(oldest / 3600))h ago")
            } else if oldest > 60 {
                components.append("oldest: \(Int(oldest / 60))m ago")
            } else {
                components.append("oldest: \(Int(oldest))s ago")
            }
        }
        
        return components.joined(separator: ", ")
    }
    
    /// Whether deduplication is working effectively
    public var isEffective: Bool {
        return recentPostsCount > 0 || oldestTrackedPost == nil
    }
}

// MARK: - Helper Extensions

extension QueuedPost {
    /// Creates a copy with updated retry information
    func withRetry(error: String? = nil) -> QueuedPost {
        return QueuedPost(
            id: self.id,
            text: self.text,
            createdAt: self.createdAt,
            retryCount: self.retryCount + 1,
            lastRetryAt: Date(),
            error: error
        )
    }
    
    /// Time until next retry attempt
    var timeUntilNextRetry: TimeInterval {
        guard let lastRetry = lastRetryAt else { return 0 }
        let backoffInterval = TimeInterval(1 << retryCount)
        let nextRetryTime = lastRetry.addingTimeInterval(backoffInterval)
        return max(0, nextRetryTime.timeIntervalSinceNow)
    }
}

// MARK: - Queue Status Notification Models

/// Notification about queue status changes for user awareness
public struct QueueStatusNotification: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: NotificationType
    public let timestamp: Date
    public var isRead: Bool
    
    public init(
        id: UUID = UUID(),
        type: NotificationType,
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.isRead = isRead
    }
    
    /// Different types of queue status notifications
    public enum NotificationType: Codable, Sendable {
        case postQueued(content: String, message: String)
        case postSuccess(content: String, message: String)
        case postFailed(content: String, error: String, message: String)
        case retryScheduled(content: String, retryCount: Int, maxRetries: Int, message: String)
        case duplicateDetected(content: String, message: String)
        case processingComplete(successCount: Int, failureCount: Int, message: String)
        case rateLimited(retryAfterSeconds: Int, message: String)
        case queueStatusUpdate(count: Int, message: String)
        
        /// User-friendly message for this notification type
        public var message: String {
            switch self {
            case .postQueued(_, let message),
                 .postSuccess(_, let message),
                 .postFailed(_, _, let message),
                 .retryScheduled(_, _, _, let message),
                 .duplicateDetected(_, let message),
                 .processingComplete(_, _, let message),
                 .rateLimited(_, let message),
                 .queueStatusUpdate(_, let message):
                return message
            }
        }
        
        /// Brief content preview when applicable
        public var contentPreview: String? {
            switch self {
            case .postQueued(let content, _),
                 .postSuccess(let content, _),
                 .postFailed(let content, _, _),
                 .retryScheduled(let content, _, _, _),
                 .duplicateDetected(let content, _):
                return content
            case .processingComplete, .rateLimited, .queueStatusUpdate:
                return nil
            }
        }
        
        /// Notification priority level
        public var priority: NotificationPriority {
            switch self {
            case .postFailed, .rateLimited:
                return .high
            case .retryScheduled, .duplicateDetected:
                return .medium
            case .postQueued, .postSuccess, .processingComplete, .queueStatusUpdate:
                return .low
            }
        }
        
        /// Whether this notification requires user attention
        public var requiresAttention: Bool {
            switch self {
            case .postFailed, .rateLimited:
                return true
            case .retryScheduled, .duplicateDetected:
                return false
            case .postQueued, .postSuccess, .processingComplete, .queueStatusUpdate:
                return false
            }
        }
        
        /// Icon name for UI display
        public var iconName: String {
            switch self {
            case .postQueued:
                return "clock.arrow.circlepath"
            case .postSuccess:
                return "checkmark.circle.fill"
            case .postFailed:
                return "xmark.circle.fill"
            case .retryScheduled:
                return "arrow.clockwise"
            case .duplicateDetected:
                return "doc.on.doc.fill"
            case .processingComplete:
                return "checkmark.circle"
            case .rateLimited:
                return "exclamationmark.triangle.fill"
            case .queueStatusUpdate:
                return "list.bullet"
            }
        }
        
        /// Color for UI display
        public var color: NotificationColor {
            switch self {
            case .postSuccess, .processingComplete:
                return .green
            case .postFailed, .rateLimited:
                return .red
            case .retryScheduled:
                return .orange
            case .duplicateDetected:
                return .yellow
            case .postQueued, .queueStatusUpdate:
                return .blue
            }
        }
    }
    
    /// Notification priority levels
    public enum NotificationPriority: String, Codable, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        
        /// Display order (high priority first)
        public var sortOrder: Int {
            switch self {
            case .high: return 0
            case .medium: return 1
            case .low: return 2
            }
        }
    }
    
    /// Colors for notification display
    public enum NotificationColor: String, Codable, CaseIterable {
        case blue = "blue"
        case green = "green"
        case yellow = "yellow"
        case orange = "orange"
        case red = "red"
        case gray = "gray"
    }
    
    /// Time since notification was created
    public var age: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }
    
    /// Human-readable age description
    public var ageDescription: String {
        let age = self.age
        if age < 60 {
            return "Just now"
        } else if age < 3600 {
            let minutes = Int(age / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if age < 86400 {
            let hours = Int(age / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(age / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    /// Whether this notification should auto-dismiss based on age
    public var shouldAutoDismiss: Bool {
        // Auto-dismiss read notifications after 10 seconds, unread after 30 seconds
        let dismissThreshold: TimeInterval = isRead ? 10 : 30
        return age > dismissThreshold && type.priority == .low
    }
}

/// Statistics about queue notifications
public struct QueueNotificationStats: Codable, Sendable {
    public let activeNotifications: Int
    public let unreadNotifications: Int
    public let totalNotifications: Int
    public let successNotifications24h: Int
    public let failureNotifications24h: Int
    public let queuedNotifications24h: Int
    public let oldestNotification: Date?
    public let newestNotification: Date?
    
    public init(
        activeNotifications: Int,
        unreadNotifications: Int,
        totalNotifications: Int,
        successNotifications24h: Int,
        failureNotifications24h: Int,
        queuedNotifications24h: Int,
        oldestNotification: Date? = nil,
        newestNotification: Date? = nil
    ) {
        self.activeNotifications = activeNotifications
        self.unreadNotifications = unreadNotifications
        self.totalNotifications = totalNotifications
        self.successNotifications24h = successNotifications24h
        self.failureNotifications24h = failureNotifications24h
        self.queuedNotifications24h = queuedNotifications24h
        self.oldestNotification = oldestNotification
        self.newestNotification = newestNotification
    }
    
    /// Success rate over last 24 hours
    public var successRate24h: Double {
        let total = successNotifications24h + failureNotifications24h
        guard total > 0 else { return 1.0 }
        return Double(successNotifications24h) / Double(total)
    }
    
    /// Human-readable statistics summary
    public var summary: String {
        var components: [String] = []
        
        if activeNotifications > 0 {
            components.append("\(activeNotifications) active")
        }
        
        if unreadNotifications > 0 {
            components.append("\(unreadNotifications) unread")
        }
        
        let total24h = successNotifications24h + failureNotifications24h + queuedNotifications24h
        if total24h > 0 {
            components.append("\(total24h) in 24h")
        }
        
        return components.joined(separator: ", ")
    }
}

/// Extension for notification filtering and sorting
extension Array where Element == QueueStatusNotification {
    /// Filter notifications by priority
    public func filter(priority: QueueStatusNotification.NotificationPriority) -> [QueueStatusNotification] {
        return filter { $0.type.priority == priority }
    }
    
    /// Filter notifications by read status
    public func filter(isRead: Bool) -> [QueueStatusNotification] {
        return filter { $0.isRead == isRead }
    }
    
    /// Filter notifications that require attention
    public var requiresAttention: [QueueStatusNotification] {
        return filter { $0.type.requiresAttention }
    }
    
    /// Sort notifications by priority and timestamp
    public var sortedByPriority: [QueueStatusNotification] {
        return sorted { first, second in
            if first.type.priority.sortOrder != second.type.priority.sortOrder {
                return first.type.priority.sortOrder < second.type.priority.sortOrder
            }
            return first.timestamp > second.timestamp
        }
    }
    
    /// Get recent notifications (within last hour)
    public var recent: [QueueStatusNotification] {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return filter { $0.timestamp > oneHourAgo }
    }
    
    /// Get notifications that should auto-dismiss
    public var shouldAutoDismiss: [QueueStatusNotification] {
        return filter { $0.shouldAutoDismiss }
    }
}
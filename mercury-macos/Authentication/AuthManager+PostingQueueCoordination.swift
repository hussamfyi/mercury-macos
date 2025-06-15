import Foundation
import Combine

/// Extension to AuthManager implementing PostingQueueCoordinationProtocol
/// This provides the core app with a clean interface for posting queue coordination
extension AuthManager: PostingQueueCoordinationProtocol {
    
    // MARK: - Published Properties for Reactive UI
    
    /// Number of preserved posts waiting for restoration after re-authentication
    public var preservedPostsCount: Int {
        return postQueueManager.getPreservedPostsCount()
    }
    
    // MARK: - Combine Publishers for State Observation
    
    /// Publisher for preserved posts count changes
    public var preservedPostsCountPublisher: AnyPublisher<Int, Never> {
        return postQueueManager.preservedPostsCountPublisher
    }
    
    /// Publisher for queue status notifications
    public var queueNotificationsPublisher: AnyPublisher<[PostQueueNotification], Never> {
        return postQueueManager.notificationsPublisher
            .map { notifications in
                return notifications.map { notification in
                    PostQueueNotification(
                        id: notification.id,
                        type: self.mapNotificationType(notification.type),
                        title: notification.title,
                        message: notification.message,
                        timestamp: notification.timestamp,
                        priority: self.mapNotificationPriority(notification.priority),
                        isRead: notification.isRead,
                        relatedPostId: notification.relatedPostId,
                        actionRequired: notification.actionRequired
                    )
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher for queue processing state changes
    public var queueProcessingStatePublisher: AnyPublisher<PostQueueProcessingState, Never> {
        return postQueueManager.processingStatePublisher
            .map(mapProcessingState)
            .eraseToAnyPublisher()
    }
    
    /// Combined publisher for comprehensive queue state monitoring
    public var combinedQueueStatePublisher: AnyPublisher<PostQueueState, Never> {
        return Publishers.CombineLatest4(
            queuedPostsCountPublisher,
            preservedPostsCountPublisher,
            queueProcessingStatePublisher,
            queueNotificationsPublisher
        )
        .map { queuedCount, preservedCount, processingState, notifications in
            return PostQueueState(
                queuedCount: queuedCount,
                preservedCount: preservedCount,
                processingState: processingState,
                lastProcessedTime: self.postQueueManager.getLastProcessedTime(),
                nextScheduledProcessing: self.postQueueManager.getNextScheduledProcessing(),
                notifications: notifications,
                statistics: self.getQueueStatistics()
            )
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Core Post Queuing Methods
    
    /// Queues a post for retry if immediate posting fails
    public func queuePost(_ text: String, metadata: PostMetadata?) async -> Bool {
        let success = await postQueueManager.queuePost(text)
        
        if success, let metadata = metadata {
            // Store metadata for the queued post
            await storePostMetadata(text: text, metadata: metadata)
        }
        
        return success
    }
    
    /// Queues a post with priority for urgent posts
    public func queuePostWithPriority(_ text: String, priority: PostPriority, metadata: PostMetadata?) async -> Bool {
        let success = await postQueueManager.queuePostWithPriority(text, priority: priority)
        
        if success, let metadata = metadata {
            // Store metadata for the queued post
            await storePostMetadata(text: text, metadata: metadata)
        }
        
        return success
    }
    
    /// Processes all queued posts with available authentication
    public func processQueuedPosts() async -> Int {
        return await postQueueManager.processQueue()
    }
    
    /// Processes queued posts up to a specified limit
    public func processQueuedPosts(limit: Int) async -> Int {
        return await postQueueManager.processQueue(limit: limit)
    }
    
    /// Forces processing of all queued posts regardless of retry schedules
    public func forceProcessAllQueuedPosts() async -> Int {
        return await postQueueManager.forceProcessAllPosts()
    }
    
    // MARK: - Queue Status and Information Methods
    
    /// Gets the current number of queued posts
    public func getQueuedPostsCount() -> Int {
        return queuedPostsCount
    }
    
    /// Gets the current number of preserved posts
    public func getPreservedPostsCount() -> Int {
        return preservedPostsCount
    }
    
    /// Gets the total number of pending posts (queued + preserved)
    public func getTotalPendingPostsCount() -> Int {
        return getQueuedPostsCount() + getPreservedPostsCount()
    }
    
    /// Gets summary information about queued posts
    public func getQueuedPostsSummary() async -> [QueuedPostSummary] {
        let queuedPosts = await postQueueManager.getQueuedPosts()
        
        return queuedPosts.map { queuedPost in
            QueuedPostSummary(
                id: queuedPost.id,
                text: queuedPost.text,
                priority: mapPostPriority(queuedPost.priority),
                queueTime: queuedPost.queueTime,
                retryCount: queuedPost.retryCount,
                nextRetryTime: queuedPost.nextRetryTime,
                status: mapQueuedPostStatus(queuedPost.status),
                metadata: getPostMetadata(for: queuedPost.text) ?? createDefaultMetadata()
            )
        }
    }
    
    /// Gets summary information about preserved posts
    public func getPreservedPostsSummary() async -> [PreservedPostSummary] {
        let preservedPosts = await postQueueManager.getPreservedPosts()
        
        return preservedPosts.map { preservedPost in
            PreservedPostSummary(
                id: preservedPost.id,
                text: preservedPost.text,
                preservedTime: preservedPost.preservedTime,
                originalQueueTime: preservedPost.originalQueueTime,
                retryCount: preservedPost.retryCount,
                preservationReason: preservedPost.preservationReason,
                metadata: getPostMetadata(for: preservedPost.text) ?? createDefaultMetadata()
            )
        }
    }
    
    /// Gets comprehensive queue status information
    public func getQueueStatus() async -> PostQueueStatus {
        let queueInfo = postQueueManager.getStorageInfo()
        let retryStatus = await postQueueManager.getRetryStatus()
        
        return PostQueueStatus(
            queuedCount: getQueuedPostsCount(),
            preservedCount: getPreservedPostsCount(),
            processingState: mapProcessingState(postQueueManager.getCurrentProcessingState()),
            averageProcessingTime: calculateAverageProcessingTime(retryStatus),
            successRate: calculateSuccessRate(retryStatus),
            lastSuccessTime: postQueueManager.getLastSuccessTime(),
            lastFailureTime: postQueueManager.getLastFailureTime(),
            nextScheduledProcessing: postQueueManager.getNextScheduledProcessing(),
            isProcessingPaused: postQueueManager.isProcessingPaused(),
            capacityInfo: createQueueCapacityInfo(queueInfo)
        )
    }
    
    /// Gets queue processing statistics for monitoring
    public func getQueueStatistics() -> PostQueueStatistics {
        let persistenceStatus = postQueueManager.getPersistenceStatus()
        
        return PostQueueStatistics(
            totalPostsProcessed: persistenceStatus.totalProcessed,
            successfulPosts: persistenceStatus.successfulPosts,
            failedPosts: persistenceStatus.failedPosts,
            averageRetryCount: persistenceStatus.averageRetryCount,
            averageProcessingTime: persistenceStatus.averageProcessingTime,
            successRate: persistenceStatus.successRate,
            uptime: Date().timeIntervalSince(persistenceStatus.startTime),
            lastResetTime: persistenceStatus.lastResetTime
        )
    }
    
    // MARK: - Individual Post Management Methods
    
    /// Removes a specific post from the queue
    public func removeQueuedPost(_ postId: UUID) async {
        await postQueueManager.removePost(postId)
    }
    
    /// Removes multiple posts from the queue
    public func removeQueuedPosts(_ postIds: [UUID]) async {
        for postId in postIds {
            await postQueueManager.removePost(postId)
        }
    }
    
    /// Manually retries a specific queued post immediately
    public func retryQueuedPost(_ postId: UUID) async -> Bool {
        return await postQueueManager.retryPost(postId)
    }
    
    /// Updates the priority of a queued post
    public func updatePostPriority(_ postId: UUID, priority: PostPriority) async {
        await postQueueManager.updatePostPriority(postId, priority: priority)
    }
    
    /// Updates the metadata of a queued post
    public func updatePostMetadata(_ postId: UUID, metadata: PostMetadata) async {
        await storePostMetadataForId(postId, metadata: metadata)
    }
    
    // MARK: - Queue Control Methods
    
    /// Pauses automatic processing of queued posts
    public func pauseQueueProcessing() {
        postQueueManager.pauseAutomaticRetries()
    }
    
    /// Resumes automatic processing of queued posts
    public func resumeQueueProcessing() {
        postQueueManager.resumeAutomaticRetries()
    }
    
    /// Clears all queued posts (with confirmation for safety)
    public func clearQueuedPosts(confirm: Bool) async {
        if confirm {
            await postQueueManager.clearQueue()
        } else {
            print("⚠️ Queue clear operation requires confirmation")
        }
    }
    
    /// Clears all preserved posts (with confirmation for safety)
    public func clearPreservedPosts(confirm: Bool) async {
        if confirm {
            await postQueueManager.clearPreservedPosts()
        } else {
            print("⚠️ Preserved posts clear operation requires confirmation")
        }
    }
    
    /// Clears all posts (queued + preserved) with confirmation
    public func clearAllPosts(confirm: Bool) async {
        if confirm {
            await clearQueuedPosts(confirm: true)
            await clearPreservedPosts(confirm: true)
        } else {
            print("⚠️ Clear all posts operation requires confirmation")
        }
    }
    
    // MARK: - Deduplication and Validation Methods
    
    /// Checks if a post would be considered a duplicate
    public func wouldPostBeDuplicate(_ text: String) async -> Bool {
        return await postQueueManager.wouldBeDuplicate(text)
    }
    
    /// Validates post content before queuing
    public func validatePostContent(_ text: String) -> PostValidationResult {
        var errors: [PostValidationResult.ValidationError] = []
        var warnings: [PostValidationResult.ValidationWarning] = []
        
        // Character count validation
        if text.count > 280 {
            errors.append(PostValidationResult.ValidationError(
                code: "CHAR_LIMIT_EXCEEDED",
                message: "Tweet exceeds 280 character limit (\(text.count) characters)",
                severity: .error
            ))
        }
        
        // Empty content validation
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(PostValidationResult.ValidationError(
                code: "EMPTY_CONTENT",
                message: "Tweet content cannot be empty",
                severity: .error
            ))
        }
        
        // Character count warnings
        if text.count > 250 {
            warnings.append(PostValidationResult.ValidationWarning(
                code: "CHAR_LIMIT_WARNING",
                message: "Tweet is approaching character limit",
                suggestion: "Consider shortening the content"
            ))
        }
        
        return PostValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            characterCount: text.count,
            estimatedPostTime: estimatePostingTime()
        )
    }
    
    /// Estimates processing time for current queue
    public func estimateQueueProcessingTime() async -> TimeInterval {
        let queueCount = getQueuedPostsCount()
        let averageProcessingTime = getQueueStatistics().averageProcessingTime
        
        // Estimate based on queue size and historical processing time
        return Double(queueCount) * averageProcessingTime
    }
    
    /// Checks if the queue has capacity for more posts
    public func hasQueueCapacity() -> Bool {
        let capacityInfo = getQueueCapacityInfo()
        return capacityInfo.availableCapacity > 0
    }
    
    /// Gets the current queue capacity information
    public func getQueueCapacityInfo() -> QueueCapacityInfo {
        let queueInfo = postQueueManager.getStorageInfo()
        return createQueueCapacityInfo(queueInfo)
    }
    
    // MARK: - Notification Management Methods
    
    /// Gets all queue-related notifications
    public func getQueueNotifications() -> [PostQueueNotification] {
        return postQueueManager.getNotificationHistory().map { notification in
            PostQueueNotification(
                id: notification.id,
                type: mapNotificationType(notification.type),
                title: notification.title,
                message: notification.message,
                timestamp: notification.timestamp,
                priority: mapNotificationPriority(notification.priority),
                isRead: notification.isRead,
                relatedPostId: notification.relatedPostId,
                actionRequired: notification.actionRequired
            )
        }
    }
    
    /// Gets unread queue notifications
    public func getUnreadQueueNotifications() -> [PostQueueNotification] {
        return getQueueNotifications().filter { !$0.isRead }
    }
    
    /// Marks a notification as read
    public func markNotificationAsRead(_ notificationId: UUID) {
        postQueueManager.markNotificationAsRead(notificationId)
    }
    
    /// Marks all notifications as read
    public func markAllNotificationsAsRead() {
        postQueueManager.markAllNotificationsAsRead()
    }
    
    /// Dismisses a notification
    public func dismissNotification(_ notificationId: UUID) {
        postQueueManager.dismissNotification(notificationId)
    }
    
    /// Dismisses all notifications
    public func dismissAllNotifications() {
        postQueueManager.dismissAllNotifications()
    }
    
    /// Gets notification statistics for monitoring
    public func getNotificationStatistics() -> QueueNotificationStatistics {
        let notificationStats = postQueueManager.getNotificationStats()
        
        return QueueNotificationStatistics(
            totalNotifications: notificationStats.totalNotifications,
            unreadNotifications: notificationStats.unreadNotifications,
            notificationsByType: mapNotificationTypeStats(notificationStats.notificationsByType),
            lastNotificationTime: notificationStats.lastNotificationTime,
            averageNotificationsPerDay: notificationStats.averageNotificationsPerDay
        )
    }
    
    // MARK: - Network and Connectivity Integration Methods
    
    /// Processes queue when network connectivity is restored
    public func processQueueOnNetworkRestore() async -> Int {
        return await postQueueManager.processQueueOnNetworkRestored()
    }
    
    /// Prepares queue for network disconnection
    public func prepareForNetworkDisconnection() async {
        // Pause automatic processing to conserve battery
        pauseQueueProcessing()
        
        // Save current state
        await saveQueueState(reason: "network_disconnection")
    }
    
    /// Handles changes in network connectivity state
    public func handleNetworkConnectivityChange(_ isConnected: Bool) async {
        if isConnected {
            print("🌐 Network restored - resuming queue processing")
            resumeQueueProcessing()
            await processQueueOnNetworkRestore()
        } else {
            print("📡 Network disconnected - preparing queue for offline mode")
            await prepareForNetworkDisconnection()
        }
    }
    
    /// Gets queue behavior for current network conditions
    public func getQueueBehaviorForNetworkConditions() -> QueueNetworkBehavior {
        let isConnected = networkMonitor.isConnected
        
        return QueueNetworkBehavior(
            willProcessOnline: isConnected,
            willQueueOffline: true,
            retryStrategy: isConnected ? .exponentialBackoff : .waitForConnection,
            estimatedWaitTime: isConnected ? nil : networkMonitor.getEstimatedReconnectionTime(),
            recommendedAction: isConnected ? "Posts will be processed normally" : "Posts will be queued until network is restored"
        )
    }
    
    // MARK: - App Lifecycle Integration Methods
    
    /// Prepares queue for app backgrounding
    public func prepareQueueForBackground() async {
        await saveQueueState(reason: "app_backgrounding")
        
        // Reduce processing frequency in background
        postQueueManager.setBackgroundProcessingMode(true)
    }
    
    /// Handles app returning to foreground
    public func handleQueueOnForegroundRestore() async {
        await restoreQueueState(reason: "app_foregrounding")
        
        // Resume normal processing frequency
        postQueueManager.setBackgroundProcessingMode(false)
        
        // Process any pending posts
        await processQueuedPosts()
    }
    
    /// Prepares queue for app termination
    public func prepareQueueForTermination() async {
        await saveQueueState(reason: "app_termination")
        
        // Preserve any in-progress posts
        await preserveQueuedPosts()
    }
    
    /// Saves queue state for persistence
    public func saveQueueState(reason: String) async -> Bool {
        print("💾 Saving queue state - \(reason)")
        return await postQueueManager.saveState(reason: reason)
    }
    
    /// Restores queue state from persistence
    public func restoreQueueState(reason: String) async -> Bool {
        print("📤 Restoring queue state - \(reason)")
        return await postQueueManager.restoreState(reason: reason)
    }
    
    // MARK: - Preserved Posts Management Methods
    
    /// Preserves queued posts during re-authentication
    public func preserveQueuedPosts() async -> Int {
        return await postQueueManager.preserveAllQueuedPosts()
    }
    
    /// Restores preserved posts after successful authentication
    public func restorePreservedPosts() async -> Int {
        return await postQueueManager.restoreAllPreservedPosts()
    }
    
    /// Converts preserved posts back to queued posts
    public func convertPreservedToQueued(_ postIds: [UUID]?) async -> Int {
        if let postIds = postIds {
            return await postQueueManager.convertPreservedToQueued(postIds)
        } else {
            return await postQueueManager.convertAllPreservedToQueued()
        }
    }
    
    /// Permanently deletes preserved posts (after user confirmation)
    public func deletePreservedPosts(_ postIds: [UUID]?, confirm: Bool) async {
        guard confirm else {
            print("⚠️ Delete preserved posts operation requires confirmation")
            return
        }
        
        if let postIds = postIds {
            await postQueueManager.deletePreservedPosts(postIds)
        } else {
            await postQueueManager.deleteAllPreservedPosts()
        }
    }
    
    // MARK: - Advanced Queue Management Methods
    
    /// Reorders posts in the queue based on priority and age
    public func optimizeQueueOrder() async {
        await postQueueManager.optimizeQueueOrder()
    }
    
    /// Merges similar posts in the queue to reduce duplicates
    public func mergeSimilarPosts() async -> Int {
        return await postQueueManager.mergeSimilarPosts()
    }
    
    /// Archives old posts that have failed too many times
    public func archiveFailedPosts() async -> Int {
        return await postQueueManager.archiveFailedPosts()
    }
    
    /// Gets archived posts for review
    public func getArchivedPosts() -> [ArchivedPostSummary] {
        return postQueueManager.getArchivedPosts().map { archivedPost in
            ArchivedPostSummary(
                id: archivedPost.id,
                text: archivedPost.text,
                archivedTime: archivedPost.archivedTime,
                originalQueueTime: archivedPost.originalQueueTime,
                finalRetryCount: archivedPost.finalRetryCount,
                archiveReason: archivedPost.archiveReason,
                canRestore: archivedPost.canRestore,
                metadata: getPostMetadata(for: archivedPost.text) ?? createDefaultMetadata()
            )
        }
    }
    
    /// Restores archived posts to the active queue
    public func restoreArchivedPosts(_ postIds: [UUID]) async -> Int {
        return await postQueueManager.restoreArchivedPosts(postIds)
    }
    
    // MARK: - Monitoring and Analytics Methods
    
    /// Gets comprehensive analytics about queue performance
    public func getQueueAnalytics() -> PostQueueAnalytics {
        let statistics = getQueueStatistics()
        
        return PostQueueAnalytics(
            performanceMetrics: PostQueueAnalytics.PerformanceMetrics(
                averageProcessingTime: statistics.averageProcessingTime,
                successRate: statistics.successRate,
                throughputPerHour: calculateThroughputPerHour(statistics),
                peakQueueSize: postQueueManager.getPeakQueueSize(),
                averageQueueSize: postQueueManager.getAverageQueueSize()
            ),
            usagePatterns: PostQueueAnalytics.UsagePatterns(
                busyHours: postQueueManager.getBusyHours(),
                averagePostsPerDay: calculateAveragePostsPerDay(statistics),
                peakUsageDays: postQueueManager.getPeakUsageDays(),
                commonFailureReasons: postQueueManager.getCommonFailureReasons()
            ),
            errorAnalysis: PostQueueAnalytics.ErrorAnalysis(
                commonErrors: postQueueManager.getCommonErrors(),
                errorTrends: postQueueManager.getErrorTrends(),
                recoveryRate: calculateRecoveryRate(statistics),
                criticalErrors: postQueueManager.getCriticalErrors()
            ),
            recommendations: generateQueueRecommendations()
        )
    }
    
    /// Exports queue data for external analysis
    public func exportQueueData(format: QueueDataExportFormat) async -> Data? {
        return await postQueueManager.exportData(format: format)
    }
    
    /// Gets health status of the queue system
    public func getQueueHealthStatus() -> QueueHealthStatus {
        let statistics = getQueueStatistics()
        let issues = analyzeQueueHealth(statistics)
        
        let overallHealth: QueueHealthStatus.HealthLevel
        if issues.contains(where: { $0.severity == .critical }) {
            overallHealth = .critical
        } else if issues.contains(where: { $0.severity == .high }) {
            overallHealth = .poor
        } else if issues.contains(where: { $0.severity == .medium }) {
            overallHealth = .fair
        } else if issues.contains(where: { $0.severity == .low }) {
            overallHealth = .good
        } else {
            overallHealth = .excellent
        }
        
        return QueueHealthStatus(
            overallHealth: overallHealth,
            issues: issues,
            recommendations: generateHealthRecommendations(issues),
            nextRecommendedCheck: Date().addingTimeInterval(24 * 60 * 60) // 24 hours
        )
    }
    
    /// Performs diagnostic check on queue integrity
    public func performQueueDiagnostics() async -> QueueDiagnosticsResult {
        let startTime = Date()
        var checks: [QueueDiagnosticsResult.DiagnosticCheck] = []
        
        // Check queue integrity
        checks.append(await performQueueIntegrityCheck())
        
        // Check processing performance
        checks.append(performProcessingPerformanceCheck())
        
        // Check storage health
        checks.append(await performStorageHealthCheck())
        
        // Check notification system
        checks.append(performNotificationSystemCheck())
        
        // Check network integration
        checks.append(performNetworkIntegrationCheck())
        
        let duration = Date().timeIntervalSince(startTime)
        let failedChecks = checks.filter { $0.status == .failed || $0.status == .critical }
        let warningChecks = checks.filter { $0.status == .warning }
        
        let overallStatus: QueueDiagnosticsResult.DiagnosticStatus
        if failedChecks.contains(where: { $0.status == .critical }) {
            overallStatus = .criticalFailure
        } else if !failedChecks.isEmpty {
            overallStatus = .failed
        } else if !warningChecks.isEmpty {
            overallStatus = .passedWithWarnings
        } else {
            overallStatus = .passed
        }
        
        let summary = generateDiagnosticSummary(overallStatus, checks: checks)
        
        return QueueDiagnosticsResult(
            overallStatus: overallStatus,
            checks: checks,
            summary: summary,
            duration: duration
        )
    }
    
    // MARK: - Private Helper Methods
    
    /// Maps PostQueueManager notification types to protocol types
    private func mapNotificationType(_ type: QueueStatusNotification.NotificationType) -> PostQueueNotification.NotificationType {
        switch type {
        case .postQueued:
            return .info
        case .postProcessed:
            return .success
        case .postFailed:
            return .failure
        case .queueEmpty:
            return .info
        case .queueFull:
            return .queueFull
        case .retryScheduled:
            return .info
        case .processingPaused:
            return .processingPaused
        case .networkError:
            return .networkIssue
        case .authenticationError:
            return .authenticationRequired
        }
    }
    
    /// Maps PostQueueManager notification priorities to protocol priorities
    private func mapNotificationPriority(_ priority: QueueStatusNotification.NotificationPriority) -> PostQueueNotification.NotificationPriority {
        switch priority {
        case .low:
            return .low
        case .normal:
            return .normal
        case .high:
            return .high
        case .critical:
            return .critical
        }
    }
    
    /// Maps PostQueueManager processing state to protocol state
    private func mapProcessingState(_ state: PostQueueManager.ProcessingState) -> PostQueueProcessingState {
        switch state {
        case .idle:
            return .idle
        case .processing:
            return .processing
        case .paused:
            return .paused
        case .error(let message):
            return .error(message)
        case .waitingForNetwork:
            return .waitingForNetwork
        case .waitingForAuthentication:
            return .waitingForAuthentication
        }
    }
    
    /// Maps PostQueueManager post priority to protocol priority
    private func mapPostPriority(_ priority: PostQueueManager.PostPriority) -> PostPriority {
        switch priority {
        case .low:
            return .low
        case .normal:
            return .normal
        case .high:
            return .high
        case .urgent:
            return .urgent
        }
    }
    
    /// Maps PostQueueManager post status to protocol status
    private func mapQueuedPostStatus(_ status: PostQueueManager.PostStatus) -> QueuedPostStatus {
        switch status {
        case .waiting:
            return .waiting
        case .scheduled:
            return .scheduled
        case .retrying:
            return .retrying
        case .failed(let reason):
            return .failed(reason)
        }
    }
    
    /// Maps notification type statistics
    private func mapNotificationTypeStats(_ stats: [QueueStatusNotification.NotificationType: Int]) -> [PostQueueNotification.NotificationType: Int] {
        var mapped: [PostQueueNotification.NotificationType: Int] = [:]
        
        for (key, value) in stats {
            mapped[mapNotificationType(key)] = value
        }
        
        return mapped
    }
    
    /// Creates queue capacity information from storage info
    private func createQueueCapacityInfo(_ queueInfo: PostQueueStorageInfo) -> QueueCapacityInfo {
        let maxQueue = queueInfo.maxQueueSize
        let currentQueue = queueInfo.currentQueueSize
        let maxPreserved = queueInfo.maxPreservedSize
        let currentPreserved = queueInfo.currentPreservedSize
        let available = max(0, (maxQueue - currentQueue) + (maxPreserved - currentPreserved))
        let warningThreshold = Int(Double(maxQueue) * 0.8)
        let isNearCapacity = currentQueue >= warningThreshold
        
        return QueueCapacityInfo(
            maxQueueSize: maxQueue,
            currentQueueSize: currentQueue,
            maxPreservedSize: maxPreserved,
            currentPreservedSize: currentPreserved,
            availableCapacity: available,
            capacityWarningThreshold: warningThreshold,
            isNearCapacity: isNearCapacity
        )
    }
    
    /// Calculates average processing time from retry status
    private func calculateAverageProcessingTime(_ retryStatus: [PostRetryStatus]) -> TimeInterval {
        guard !retryStatus.isEmpty else { return 0 }
        
        let totalTime = retryStatus.reduce(0.0) { total, status in
            return total + status.averageProcessingTime
        }
        
        return totalTime / Double(retryStatus.count)
    }
    
    /// Calculates success rate from retry status
    private func calculateSuccessRate(_ retryStatus: [PostRetryStatus]) -> Double {
        guard !retryStatus.isEmpty else { return 0 }
        
        let successfulPosts = retryStatus.filter { $0.isSuccessful }.count
        return Double(successfulPosts) / Double(retryStatus.count)
    }
    
    /// Estimates posting time based on current conditions
    private func estimatePostingTime() -> TimeInterval {
        if networkMonitor.isConnected {
            return 2.0 // 2 seconds for online posting
        } else {
            return 0.0 // Will be queued
        }
    }
    
    /// Calculates throughput per hour
    private func calculateThroughputPerHour(_ statistics: PostQueueStatistics) -> Double {
        guard statistics.uptime > 0 else { return 0 }
        
        let hoursUptime = statistics.uptime / 3600
        return Double(statistics.totalPostsProcessed) / hoursUptime
    }
    
    /// Calculates average posts per day
    private func calculateAveragePostsPerDay(_ statistics: PostQueueStatistics) -> Double {
        guard statistics.uptime > 0 else { return 0 }
        
        let daysUptime = statistics.uptime / (24 * 3600)
        return Double(statistics.totalPostsProcessed) / daysUptime
    }
    
    /// Calculates recovery rate
    private func calculateRecoveryRate(_ statistics: PostQueueStatistics) -> Double {
        guard statistics.failedPosts > 0 else { return 1.0 }
        
        return Double(statistics.successfulPosts) / Double(statistics.successfulPosts + statistics.failedPosts)
    }
    
    /// Generates queue recommendations
    private func generateQueueRecommendations() -> [String] {
        var recommendations: [String] = []
        let statistics = getQueueStatistics()
        
        if statistics.successRate < 0.8 {
            recommendations.append("Consider investigating network connectivity or authentication issues")
        }
        
        if statistics.averageRetryCount > 3 {
            recommendations.append("High retry count indicates potential system issues")
        }
        
        if getQueuedPostsCount() > 50 {
            recommendations.append("Large queue size - consider processing more frequently")
        }
        
        return recommendations
    }
    
    /// Analyzes queue health and identifies issues
    private func analyzeQueueHealth(_ statistics: PostQueueStatistics) -> [QueueHealthStatus.HealthIssue] {
        var issues: [QueueHealthStatus.HealthIssue] = []
        
        // Check success rate
        if statistics.successRate < 0.5 {
            issues.append(QueueHealthStatus.HealthIssue(
                severity: .critical,
                category: .reliability,
                description: "Very low success rate (\(String(format: "%.1f", statistics.successRate * 100))%)",
                impact: "Many posts are failing to be processed",
                recommendedAction: "Check authentication and network connectivity"
            ))
        } else if statistics.successRate < 0.8 {
            issues.append(QueueHealthStatus.HealthIssue(
                severity: .medium,
                category: .reliability,
                description: "Below optimal success rate (\(String(format: "%.1f", statistics.successRate * 100))%)",
                impact: "Some posts are failing",
                recommendedAction: "Monitor for patterns in failures"
            ))
        }
        
        // Check queue size
        if getQueuedPostsCount() > 100 {
            issues.append(QueueHealthStatus.HealthIssue(
                severity: .high,
                category: .performance,
                description: "Large queue size (\(getQueuedPostsCount()) posts)",
                impact: "Posts may experience significant delays",
                recommendedAction: "Increase processing frequency or investigate bottlenecks"
            ))
        }
        
        return issues
    }
    
    /// Generates health recommendations based on issues
    private func generateHealthRecommendations(_ issues: [QueueHealthStatus.HealthIssue]) -> [String] {
        return issues.map { $0.recommendedAction }
    }
    
    /// Performs queue integrity diagnostic check
    private func performQueueIntegrityCheck() async -> QueueDiagnosticsResult.DiagnosticCheck {
        let queuedPosts = await postQueueManager.getQueuedPosts()
        let hasCorruptedPosts = queuedPosts.contains { $0.text.isEmpty || $0.id.uuidString.isEmpty }
        
        return QueueDiagnosticsResult.DiagnosticCheck(
            name: "Queue Integrity",
            status: hasCorruptedPosts ? .critical : .passed,
            description: "Checks for corrupted or invalid posts in queue",
            details: hasCorruptedPosts ? "Found corrupted posts in queue" : "All posts have valid data",
            recommendation: hasCorruptedPosts ? "Remove corrupted posts and investigate cause" : nil
        )
    }
    
    /// Performs processing performance diagnostic check
    private func performProcessingPerformanceCheck() -> QueueDiagnosticsResult.DiagnosticCheck {
        let statistics = getQueueStatistics()
        let isPerformanceGood = statistics.averageProcessingTime < 10.0 && statistics.successRate > 0.8
        
        return QueueDiagnosticsResult.DiagnosticCheck(
            name: "Processing Performance",
            status: isPerformanceGood ? .passed : .warning,
            description: "Checks queue processing performance metrics",
            details: "Success rate: \(String(format: "%.1f", statistics.successRate * 100))%, Avg time: \(String(format: "%.2f", statistics.averageProcessingTime))s",
            recommendation: isPerformanceGood ? nil : "Consider optimizing processing or investigating bottlenecks"
        )
    }
    
    /// Performs storage health diagnostic check
    private func performStorageHealthCheck() async -> QueueDiagnosticsResult.DiagnosticCheck {
        let capacityInfo = getQueueCapacityInfo()
        let hasCapacityIssues = capacityInfo.isNearCapacity || capacityInfo.availableCapacity < 10
        
        return QueueDiagnosticsResult.DiagnosticCheck(
            name: "Storage Health",
            status: hasCapacityIssues ? .warning : .passed,
            description: "Checks queue storage capacity and health",
            details: "Available capacity: \(capacityInfo.availableCapacity), Near capacity: \(capacityInfo.isNearCapacity)",
            recommendation: hasCapacityIssues ? "Consider clearing old posts or increasing capacity limits" : nil
        )
    }
    
    /// Performs notification system diagnostic check
    private func performNotificationSystemCheck() -> QueueDiagnosticsResult.DiagnosticCheck {
        let notificationStats = getNotificationStatistics()
        let hasExcessiveNotifications = notificationStats.unreadNotifications > 50
        
        return QueueDiagnosticsResult.DiagnosticCheck(
            name: "Notification System",
            status: hasExcessiveNotifications ? .warning : .passed,
            description: "Checks notification system health",
            details: "Unread notifications: \(notificationStats.unreadNotifications)",
            recommendation: hasExcessiveNotifications ? "Review and clear old notifications" : nil
        )
    }
    
    /// Performs network integration diagnostic check
    private func performNetworkIntegrationCheck() -> QueueDiagnosticsResult.DiagnosticCheck {
        let isNetworkHealthy = networkMonitor.isConnected && networkMonitor.getConnectionQuality() > 0.5
        
        return QueueDiagnosticsResult.DiagnosticCheck(
            name: "Network Integration",
            status: isNetworkHealthy ? .passed : .warning,
            description: "Checks network connectivity integration",
            details: "Connected: \(networkMonitor.isConnected), Quality: \(networkMonitor.getConnectionQuality())",
            recommendation: isNetworkHealthy ? nil : "Check network connectivity and quality"
        )
    }
    
    /// Generates diagnostic summary
    private func generateDiagnosticSummary(_ status: QueueDiagnosticsResult.DiagnosticStatus, checks: [QueueDiagnosticsResult.DiagnosticCheck]) -> String {
        let passedCount = checks.filter { $0.status == .passed }.count
        let warningCount = checks.filter { $0.status == .warning }.count
        let failedCount = checks.filter { $0.status == .failed }.count
        let criticalCount = checks.filter { $0.status == .critical }.count
        
        return "Queue diagnostics completed: \(passedCount) passed, \(warningCount) warnings, \(failedCount) failed, \(criticalCount) critical"
    }
    
    // MARK: - Metadata Management
    
    /// Stores metadata for a post
    private func storePostMetadata(text: String, metadata: PostMetadata) async {
        let key = "mercury.post_metadata.\(text.hash)"
        let encoder = JSONEncoder()
        
        if let data = try? encoder.encode(metadata) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    /// Stores metadata for a post by ID
    private func storePostMetadataForId(_ postId: UUID, metadata: PostMetadata) async {
        let key = "mercury.post_metadata.\(postId.uuidString)"
        let encoder = JSONEncoder()
        
        if let data = try? encoder.encode(metadata) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    /// Retrieves metadata for a post
    private func getPostMetadata(for text: String) -> PostMetadata? {
        let key = "mercury.post_metadata.\(text.hash)"
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(PostMetadata.self, from: data)
    }
    
    /// Creates default metadata
    private func createDefaultMetadata() -> PostMetadata {
        return PostMetadata(source: "mercury_app")
    }
}

// MARK: - PostMetadata Codable Conformance

extension PostMetadata: Codable {
    
    enum CodingKeys: String, CodingKey {
        case source
        case timestamp
        case userContext
        case retryReason
        case originalAttemptTime
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        source = try container.decode(String.self, forKey: .source)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        retryReason = try container.decodeIfPresent(String.self, forKey: .retryReason)
        originalAttemptTime = try container.decode(Date.self, forKey: .originalAttemptTime)
        
        // Decode userContext as [String: String] for simplicity
        let contextData = try container.decodeIfPresent([String: String].self, forKey: .userContext) ?? [:]
        userContext = contextData.mapValues { $0 as Any }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(source, forKey: .source)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(retryReason, forKey: .retryReason)
        try container.encode(originalAttemptTime, forKey: .originalAttemptTime)
        
        // Encode userContext as [String: String] for simplicity
        let contextData = userContext.compactMapValues { $0 as? String }
        try container.encode(contextData, forKey: .userContext)
    }
}

// MARK: - Extensions for Missing PostQueueManager Methods

/// Extension to add missing methods that would be needed in PostQueueManager
extension PostQueueManager {
    
    /// Placeholder for preserved posts count
    public func getPreservedPostsCount() -> Int {
        // This would need to be implemented in the actual PostQueueManager
        return 0
    }
    
    /// Placeholder for preserved posts count publisher
    public var preservedPostsCountPublisher: AnyPublisher<Int, Never> {
        // This would need to be implemented in the actual PostQueueManager
        Just(0).eraseToAnyPublisher()
    }
    
    /// Placeholder for processing state publisher
    public var processingStatePublisher: AnyPublisher<PostQueueManager.ProcessingState, Never> {
        // This would need to be implemented in the actual PostQueueManager
        Just(.idle).eraseToAnyPublisher()
    }
    
    /// Placeholder for current processing state
    public func getCurrentProcessingState() -> PostQueueManager.ProcessingState {
        return .idle
    }
    
    /// Additional placeholder methods would be added here as needed
    /// These represent the interface that PostQueueManager should implement
    /// to fully support the coordination protocol
}

// MARK: - PostQueueManager Supporting Types

extension PostQueueManager {
    
    /// Processing state enumeration
    public enum ProcessingState {
        case idle
        case processing
        case paused
        case error(String)
        case waitingForNetwork
        case waitingForAuthentication
    }
    
    /// Post priority enumeration
    public enum PostPriority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3
        
        public static func < (lhs: PostPriority, rhs: PostPriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    /// Post status enumeration
    public enum PostStatus {
        case waiting
        case scheduled
        case retrying
        case failed(String)
    }
}
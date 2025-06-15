import Foundation
import Network
import Combine

/// Network operation types for timeout configuration
public enum NetworkOperationType {
    case authentication  // 30s timeout per PRD
    case posting        // 10s timeout per PRD  
    case tokenRefresh    // Token refresh operations
    case general        // Balanced timeout
}

/// Monitors network connectivity for authentication operations
public class NetworkMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var networkState: NetworkState = .disconnected
    @Published public private(set) var isConnected: Bool = false
    
    // MARK: - Public Publishers
    
    public var isConnectedPublisher: AnyPublisher<Bool, Never> {
        $isConnected.eraseToAnyPublisher()
    }
    
    public var networkStatePublisher: AnyPublisher<NetworkState, Never> {
        $networkState.eraseToAnyPublisher()
    }
    
    // MARK: - Internal State
    
    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.mercury.networkmonitor")
    
    // MARK: - Event Publishing
    
    /// Event publisher for network state changes (optional, set by AuthManager)
    public var eventPublisher: ((NetworkEvent) -> Void)?
    
    // MARK: - Initialization
    
    public init() {
        pathMonitor = NWPathMonitor()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Starts network monitoring
    public func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkState(from: path)
            }
        }
        
        pathMonitor.start(queue: monitorQueue)
    }
    
    /// Stops network monitoring
    public func stopMonitoring() {
        pathMonitor.cancel()
    }
    
    /// Checks if network is suitable for authentication operations
    /// - Returns: True if network can handle auth operations
    public func canPerformAuthOperations() -> Bool {
        return networkState == .connected
    }
    
    /// Checks if network is suitable for posting operations
    /// - Returns: True if network can handle posting
    public func canPerformPostOperations() -> Bool {
        return networkState == .connected
    }
    
    /// Gets detailed network information for debugging
    /// - Returns: Network status description
    public func getNetworkDetails() -> String {
        switch networkState {
        case .connected:
            return "Connected - all operations available"
        case .disconnected:
            return "No internet connection"
        case .limited:
            return "Limited connection - some operations may fail"
        }
    }
    
    /// Gets appropriate timeout for network operation based on current state and operation type
    /// - Parameter operationType: Type of operation (auth vs post vs refresh)
    /// - Returns: Recommended timeout in seconds per PRD requirements
    public func getTimeoutForOperation(_ operationType: NetworkOperationType) -> TimeInterval {
        switch operationType {
        case .authentication:
            return networkState.recommendedAuthTimeout
        case .posting:
            return networkState.recommendedPostTimeout
        case .tokenRefresh:
            return networkState.recommendedRefreshTimeout
        case .general:
            return (networkState.recommendedAuthTimeout + networkState.recommendedPostTimeout) / 2
        }
    }
    
    /// Creates a URLRequest with appropriate timeout for the operation type
    /// - Parameters:
    ///   - url: URL for the request
    ///   - operationType: Type of operation to configure timeout
    /// - Returns: URLRequest configured with PRD-specified timeout
    public func createRequest(url: URL, operationType: NetworkOperationType) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = getTimeoutForOperation(operationType)
        return request
    }
    
    /// Creates a URLSession configuration with appropriate timeout for the operation type
    /// - Parameter operationType: Type of operation to configure timeout
    /// - Returns: URLSessionConfiguration with PRD-specified timeouts
    public func createSessionConfiguration(operationType: NetworkOperationType) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        let timeout = getTimeoutForOperation(operationType)
        
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2  // 2x request timeout for resource
        
        return configuration
    }
    
    /// Waits for network to become available
    /// - Parameter timeout: Maximum time to wait in seconds
    /// - Returns: True if network becomes available within timeout
    public func waitForConnection(timeout: TimeInterval = 30.0) async -> Bool {
        guard !isConnected else { return true }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            
            // Set up timeout
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: false)
                }
            }
            
            // Listen for connection
            let cancellable = isConnectedPublisher
                .filter { $0 } // Only when connected
                .first()
                .sink { _ in
                    if !hasResumed {
                        hasResumed = true
                        timeoutTask.cancel()
                        continuation.resume(returning: true)
                    }
                }
            
            // Clean up cancellable when done
            Task {
                _ = await withCheckedContinuation { innerContinuation in
                    if hasResumed {
                        innerContinuation.resume(returning: ())
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + timeout + 1) {
                            innerContinuation.resume(returning: ())
                        }
                    }
                }
                cancellable.cancel()
            }
        }
    }
    
    /// Waits for good connection quality suitable for operations
    /// - Parameter timeout: Maximum time to wait in seconds
    /// - Returns: True if good connection becomes available within timeout
    public func waitForGoodConnection(timeout: TimeInterval = 30.0) async -> Bool {
        let currentQuality = await checkConnectionQuality()
        guard currentQuality == .poor || currentQuality == .none else {
            return true // Already have good connection
        }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: false)
                }
            }
            
            // Periodically check connection quality
            let checkTask = Task {
                while !hasResumed {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Check every 2 seconds
                    let quality = await checkConnectionQuality()
                    
                    if quality != .poor && quality != .none && !hasResumed {
                        hasResumed = true
                        timeoutTask.cancel()
                        continuation.resume(returning: true)
                        break
                    }
                }
            }
            
            // Clean up when done
            Task {
                _ = await withCheckedContinuation { innerContinuation in
                    if hasResumed {
                        innerContinuation.resume(returning: ())
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + timeout + 1) {
                            innerContinuation.resume(returning: ())
                        }
                    }
                }
                checkTask.cancel()
            }
        }
    }
    
    /// Performs intelligent retry of a network operation based on connection quality and error type
    /// - Parameters:
    ///   - operation: The operation to retry
    ///   - operationType: Type of operation for timeout configuration
    ///   - operationName: Name for logging/events
    /// - Returns: Result of the operation
    public func performOperationWithIntelligentRetry<T>(
        operation: @escaping () async throws -> T,
        operationType: NetworkOperationType,
        operationName: String
    ) async throws -> T {
        let connectionQuality = await checkConnectionQuality()
        let retryStrategy = connectionQuality.retryStrategy
        
        var lastError: Error?
        
        for attempt in 0...retryStrategy.maxRetries {
            do {
                // Attempt the operation
                return try await operation()
                
            } catch {
                lastError = error
                
                // Don't retry on final attempt
                if attempt == retryStrategy.maxRetries {
                    break
                }
                
                // Check if we should retry this error
                let currentQuality = await checkConnectionQuality()
                if !retryStrategy.shouldRetryError(error, connectionQuality: currentQuality) {
                    break
                }
                
                // Publish retry event
                eventPublisher?(.operationRetried(operation: operationName, attempt: attempt + 1))
                
                // Wait for better connection if needed
                if currentQuality == .none || currentQuality == .poor {
                    let waitTime = min(retryStrategy.delayForAttempt(attempt), 30.0)
                    let connectionImproved = await waitForGoodConnection(timeout: waitTime)
                    
                    // If connection didn't improve within timeout, use regular delay
                    if !connectionImproved {
                        let delay = retryStrategy.delayForAttempt(attempt)
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                } else {
                    // Regular exponential backoff for other errors
                    let delay = retryStrategy.delayForAttempt(attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // If we get here, all retries failed
        throw lastError ?? URLError(.unknown)
    }
    
    /// Determines if conditions are suitable for starting a new operation
    /// - Parameter operationType: Type of operation to assess
    /// - Returns: True if conditions are suitable for the operation
    public func shouldAttemptOperation(_ operationType: NetworkOperationType) -> Bool {
        guard isConnected else { return false }
        
        // Check if we're in a suitable network state
        switch operationType {
        case .authentication:
            // Auth can be attempted on any connection, but warn on limited
            return networkState.allowsAttemptedOperations
        case .posting, .tokenRefresh:
            // Posts and refreshes need reliable connection
            return networkState.allowsReliableOperations
        case .general:
            return networkState.allowsAttemptedOperations
        }
    }
    
    /// Gets human-readable advice for current network conditions
    /// - Parameter operationType: Type of operation user wants to perform
    /// - Returns: Advice string for the user
    public func getNetworkAdvice(for operationType: NetworkOperationType) -> String? {
        guard !isConnected else { return nil }
        
        switch networkState {
        case .disconnected:
            return "No internet connection. Please check your network settings."
        case .limited:
            switch operationType {
            case .authentication:
                return "Poor connection detected. Authentication may take longer than usual."
            case .posting:
                return "Poor connection. Your post will be queued and sent when connection improves."
            case .tokenRefresh:
                return "Poor connection detected. Retrying in the background."
            case .general:
                return "Poor connection detected. Some operations may be delayed."
            }
        case .connected:
            return nil // No advice needed for good connection
        }
    }
    
    // MARK: - Private Methods
    
    private func updateNetworkState(from path: NWPath) {
        let newState = determineNetworkState(from: path)
        let wasConnected = isConnected
        
        networkState = newState
        isConnected = newState.isConnected
        
        // Log significant state changes and publish events
        if wasConnected != isConnected {
            print("Network state changed: \(newState.description)")
            
            // Publish network state change events
            if isConnected {
                eventPublisher?(.connectionEstablished)
            } else {
                eventPublisher?(.connectionLost)
            }
        }
        
        // Check for connection quality changes
        if isConnected {
            Task {
                let quality = await checkConnectionQuality()
                eventPublisher?(.connectionQualityChanged(quality))
            }
        }
    }
    
    private func determineNetworkState(from path: NWPath) -> NetworkState {
        switch path.status {
        case .satisfied:
            // Check connection quality
            if path.isExpensive || path.isConstrained {
                return .limited
            } else {
                return .connected
            }
        case .unsatisfied:
            return .disconnected
        case .requiresConnection:
            return .disconnected
        @unknown default:
            return .disconnected
        }
    }
}

// MARK: - Network State Extensions

extension NetworkState {
    /// Whether operations requiring reliable network should proceed
    var allowsReliableOperations: Bool {
        return self == .connected
    }
    
    /// Whether operations can be attempted with potential fallback
    var allowsAttemptedOperations: Bool {
        return self != .disconnected
    }
    
    /// Recommended timeout for post operations in this state (PRD: 10s baseline)
    var recommendedPostTimeout: TimeInterval {
        switch self {
        case .connected:
            return 10.0 // PRD requirement: 10 seconds for posts
        case .limited:
            return 15.0 // Slightly longer for poor connections
        case .disconnected:
            return 5.0  // Quick timeout for immediate failure
        }
    }
    
    /// Recommended timeout for authentication operations in this state (PRD: 30s baseline)
    var recommendedAuthTimeout: TimeInterval {
        switch self {
        case .connected:
            return 30.0 // PRD requirement: 30 seconds for auth
        case .limited:
            return 45.0 // Longer timeout for poor connections
        case .disconnected:
            return 10.0 // Quick timeout for immediate failure
        }
    }
    
    /// Recommended timeout for token refresh operations in this state
    var recommendedRefreshTimeout: TimeInterval {
        switch self {
        case .connected:
            return 20.0 // Refresh should be faster than full auth
        case .limited:
            return 30.0 // Longer timeout for poor connections
        case .disconnected:
            return 8.0  // Quick timeout for immediate failure
        }
    }
}

// MARK: - Network Quality Detection

extension NetworkMonitor {
    /// Performs a quick network quality check
    /// - Returns: Estimated connection quality
    public func checkConnectionQuality() async -> ConnectionQuality {
        guard isConnected else { return .none }
        
        // Simple ping-like test to estimate quality
        let startTime = Date()
        
        do {
            // Test connection to a reliable endpoint
            let url = URL(string: "https://api.x.com/2/openapi.json")!
            let request = URLRequest(url: url, timeoutInterval: 5.0)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            let responseTime = Date().timeIntervalSince(startTime)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                return classifyConnectionQuality(responseTime: responseTime)
            } else {
                return .poor
            }
            
        } catch {
            return .poor
        }
    }
    
    private func classifyConnectionQuality(responseTime: TimeInterval) -> ConnectionQuality {
        switch responseTime {
        case 0..<1.0:
            return .excellent
        case 1.0..<3.0:
            return .good
        case 3.0..<5.0:
            return .fair
        default:
            return .poor
        }
    }
}

// MARK: - Connection Quality Types

public enum ConnectionQuality {
    case none
    case poor
    case fair
    case good
    case excellent
    
    public var description: String {
        switch self {
        case .none:
            return "No connection"
        case .poor:
            return "Poor connection"
        case .fair:
            return "Fair connection"
        case .good:
            return "Good connection"
        case .excellent:
            return "Excellent connection"
        }
    }
    
    /// Recommended retry strategy for this connection quality
    public var retryStrategy: RetryStrategy {
        switch self {
        case .none, .poor:
            return .conservative
        case .fair:
            return .moderate
        case .good, .excellent:
            return .aggressive
        }
    }
}

public enum RetryStrategy {
    case conservative // Longer delays, fewer attempts
    case moderate     // Standard delays and attempts
    case aggressive   // Shorter delays, more attempts
    
    public var maxRetries: Int {
        switch self {
        case .conservative: return 2
        case .moderate: return 3
        case .aggressive: return 5
        }
    }
    
    public var baseDelay: TimeInterval {
        switch self {
        case .conservative: return 5.0
        case .moderate: return 2.0
        case .aggressive: return 1.0
        }
    }
    
    /// Calculate delay for specific retry attempt using exponential backoff
    public func delayForAttempt(_ attempt: Int) -> TimeInterval {
        let exponentialFactor = min(pow(2.0, Double(attempt)), 60.0) // Max 60s
        return baseDelay * exponentialFactor
    }
    
    /// Whether to retry based on error type and connection quality
    public func shouldRetryError(_ error: Error, connectionQuality: ConnectionQuality) -> Bool {
        // Network errors are generally retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            case .cannotConnectToHost, .cannotFindHost:
                return connectionQuality != .none
            case .badServerResponse, .httpTooManyRedirects:
                return false // Don't retry server-side issues
            default:
                return connectionQuality != .none && connectionQuality != .poor
            }
        }
        
        // Custom authentication errors (assuming AuthenticationError is available in scope)
        if error.localizedDescription.contains("authentication") {
            // Handle authentication-related errors based on description
            let errorDesc = error.localizedDescription.lowercased()
            
            if errorDesc.contains("network") {
                return true
            } else if errorDesc.contains("rate limit") || errorDesc.contains("rate limited") {
                return false // Need to wait for rate limit reset
            } else if errorDesc.contains("invalid") || errorDesc.contains("expired") {
                return false // Need fresh auth, not retry
            } else if errorDesc.contains("cancelled") {
                return false // User cancelled, don't retry
            } else {
                return connectionQuality != .none
            }
        }
        
        return connectionQuality != .none && connectionQuality != .poor
    }
}
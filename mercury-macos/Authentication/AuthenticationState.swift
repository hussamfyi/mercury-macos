import Foundation
import Combine

// MARK: - Authentication State Models

/// Main authentication state for the Mercury app
public enum AuthenticationState: Equatable {
    case disconnected
    case authenticating
    case authenticated
    case refreshing
    case error(AuthenticationError)
    
    /// Human-readable description of the current state
    public var description: String {
        switch self {
        case .disconnected:
            return "Not connected to X"
        case .authenticating:
            return "Connecting to X..."
        case .authenticated:
            return "Connected to X"
        case .refreshing:
            return "Refreshing connection..."
        case .error(let error):
            return "Connection error: \(error.localizedDescription)"
        }
    }
    
    /// Whether the user can post tweets in this state
    public var canPost: Bool {
        return self == .authenticated
    }
    
    /// Whether authentication is in progress
    public var isInProgress: Bool {
        switch self {
        case .authenticating, .refreshing:
            return true
        default:
            return false
        }
    }
    
    public static func == (lhs: AuthenticationState, rhs: AuthenticationState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.authenticating, .authenticating),
             (.authenticated, .authenticated),
             (.refreshing, .refreshing):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Token refresh state for internal management
public enum TokenRefreshState {
    case idle
    case refreshing
    case success
    case failure(Error)
}

// MARK: - User Information Models

/// Authenticated user information
public struct AuthenticatedUser: Codable, Sendable {
    public let id: String
    public let username: String
    public let name: String
    public let profileImageUrl: String?
    public let followersCount: Int?
    public let followingCount: Int?
    public let tweetCount: Int?
    public let verified: Bool?
    public let authenticatedAt: Date
    
    public init(
        id: String,
        username: String,
        name: String,
        profileImageUrl: String? = nil,
        followersCount: Int? = nil,
        followingCount: Int? = nil,
        tweetCount: Int? = nil,
        verified: Bool? = nil,
        authenticatedAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.name = name
        self.profileImageUrl = profileImageUrl
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.tweetCount = tweetCount
        self.verified = verified
        self.authenticatedAt = authenticatedAt
    }
    
    /// Display name for UI (prefers name over username)
    public var displayName: String {
        return name.isEmpty ? "@\(username)" : name
    }
    
    /// Full display format for detailed views
    public var fullDisplayName: String {
        return name.isEmpty ? "@\(username)" : "\(name) (@\(username))"
    }
}

// MARK: - Rate Limiting Models

/// Rate limit information for X API Free tier
public struct RateLimitInfo: Codable, Sendable {
    public let remainingRequests: Int
    public let totalRequests: Int
    public let resetDate: Date?
    public let isLimited: Bool
    
    public init(
        remainingRequests: Int,
        totalRequests: Int,
        resetDate: Date? = nil,
        isLimited: Bool = false
    ) {
        self.remainingRequests = remainingRequests
        self.totalRequests = totalRequests
        self.resetDate = resetDate
        self.isLimited = isLimited
    }
    
    /// Empty state for initialization
    public static let empty = RateLimitInfo(
        remainingRequests: 500,
        totalRequests: 500,
        resetDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
        isLimited: false
    )
    
    /// Usage percentage (0.0 to 1.0)
    public var usagePercentage: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(totalRequests - remainingRequests) / Double(totalRequests)
    }
    
    /// Whether user should be warned about approaching limit
    public var shouldWarnUser: Bool {
        return usagePercentage >= 0.8 // Warn at 80% usage (400/500)
    }
    
    /// User-friendly description of rate limit status
    public var statusDescription: String {
        if isLimited {
            if let resetDate = resetDate {
                return "Rate limit exceeded. Resets \(resetDate.formatted(.relative(presentation: .named)))"
            } else {
                return "Rate limit exceeded. Please try again later."
            }
        } else {
            return "\(remainingRequests) of \(totalRequests) posts remaining this month"
        }
    }
}

// MARK: - Network State Models

/// Network connectivity state
public enum NetworkState {
    case connected
    case disconnected
    case limited // Poor connection
    
    public var isConnected: Bool {
        return self == .connected
    }
    
    public var description: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "No internet connection"
        case .limited:
            return "Limited connection"
        }
    }
}

// MARK: - Post Queue Models

/// Queued post information
public struct QueuedPost: Codable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public let retryCount: Int
    public let lastRetryAt: Date?
    public let error: String?
    
    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastRetryAt: Date? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
        self.error = error
    }
    
    /// Whether this post should be retried based on retry count and timing
    public var shouldRetry: Bool {
        guard retryCount < 5 else { return false } // Max 5 retries
        
        if let lastRetry = lastRetryAt {
            // Exponential backoff: 1s, 2s, 4s, 8s, 16s
            let backoffInterval = TimeInterval(1 << retryCount)
            return Date().timeIntervalSince(lastRetry) >= backoffInterval
        }
        
        return true // First retry
    }
    
    /// Next retry time based on exponential backoff
    public var nextRetryTime: Date {
        guard let lastRetry = lastRetryAt else { return Date() }
        let backoffInterval = TimeInterval(1 << retryCount)
        return lastRetry.addingTimeInterval(backoffInterval)
    }
}

// MARK: - Publishers for Reactive Programming

/// Protocol for components that need to publish state changes
public protocol StatePublisher {
    associatedtype StateType
    var statePublisher: AnyPublisher<StateType, Never> { get }
}

/// Extension to provide Combine publishers for authentication state management
extension AuthenticationState {
    /// Creates a publisher that emits when authentication state changes
    public static func publisher(from subject: PassthroughSubject<AuthenticationState, Never>) -> AnyPublisher<AuthenticationState, Never> {
        return subject.eraseToAnyPublisher()
    }
}
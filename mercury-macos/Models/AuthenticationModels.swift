import Foundation

// MARK: - Tweet Request Models

/// Request model for posting a tweet to X API (simplified from Phase 1)
public struct TweetRequest: Codable, Sendable {
    public let text: String
    public let replySettings: String?
    
    public init(text: String, replySettings: String? = nil) {
        self.text = text
        self.replySettings = replySettings
    }
    
    enum CodingKeys: String, CodingKey {
        case text
        case replySettings = "reply_settings"
    }
}

// MARK: - Tweet Response Models

/// Response model for tweet posting (simplified from Phase 1)
public struct TweetResponse: Codable, Sendable {
    public let data: TweetData
    
    public struct TweetData: Codable, Sendable {
        public let id: String
        public let text: String
        public let editHistoryTweetIds: [String]?
        
        public init(id: String, text: String, editHistoryTweetIds: [String]? = nil) {
            self.id = id
            self.text = text
            self.editHistoryTweetIds = editHistoryTweetIds
        }
        
        enum CodingKeys: String, CodingKey {
            case id
            case text
            case editHistoryTweetIds = "edit_history_tweet_ids"
        }
    }
    
    public init(data: TweetData) {
        self.data = data
    }
}

// MARK: - User Response Models

/// Response model for user information (simplified from Phase 1)
public struct UserResponse: Codable, Sendable {
    public let data: UserData
    
    public struct UserData: Codable, Sendable {
        public let id: String
        public let name: String
        public let username: String
        public let profileImageUrl: String?
        public let verified: Bool?
        public let publicMetrics: UserPublicMetrics?
        
        public init(
            id: String,
            name: String,
            username: String,
            profileImageUrl: String? = nil,
            verified: Bool? = nil,
            publicMetrics: UserPublicMetrics? = nil
        ) {
            self.id = id
            self.name = name
            self.username = username
            self.profileImageUrl = profileImageUrl
            self.verified = verified
            self.publicMetrics = publicMetrics
        }
        
        enum CodingKeys: String, CodingKey {
            case id, name, username, verified
            case profileImageUrl = "profile_image_url"
            case publicMetrics = "public_metrics"
        }
    }
    
    public init(data: UserData) {
        self.data = data
    }
}

/// User public metrics
public struct UserPublicMetrics: Codable, Sendable {
    public let followersCount: Int
    public let followingCount: Int
    public let tweetCount: Int
    public let listedCount: Int
    
    public init(followersCount: Int, followingCount: Int, tweetCount: Int, listedCount: Int) {
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.tweetCount = tweetCount
        self.listedCount = listedCount
    }
    
    enum CodingKeys: String, CodingKey {
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case tweetCount = "tweet_count"
        case listedCount = "listed_count"
    }
}

// MARK: - Authentication Session Models

/// Represents an active authentication session
public struct AuthenticationSession: Codable, Sendable {
    public let user: AuthenticatedUser
    public let tokenExpiryDate: Date
    public let scopes: [String]
    public let createdAt: Date
    public let lastActiveAt: Date
    
    public init(
        user: AuthenticatedUser,
        tokenExpiryDate: Date,
        scopes: [String],
        createdAt: Date = Date(),
        lastActiveAt: Date = Date()
    ) {
        self.user = user
        self.tokenExpiryDate = tokenExpiryDate
        self.scopes = scopes
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }
    
    /// Whether the session is currently valid
    public var isValid: Bool {
        return tokenExpiryDate > Date()
    }
    
    /// Time remaining until token expires
    public var timeUntilExpiry: TimeInterval {
        return tokenExpiryDate.timeIntervalSinceNow
    }
    
    /// Whether the token needs refresh (within 15 minutes of expiry)
    public var needsRefresh: Bool {
        return timeUntilExpiry <= 15 * 60 // 15 minutes
    }
}

// MARK: - Authentication Preferences

/// User preferences for authentication behavior
public struct AuthenticationPreferences: Codable, Sendable {
    public let autoRefreshTokens: Bool
    public let rememberCredentials: Bool
    public let showRateLimitWarnings: Bool
    public let queueFailedPosts: Bool
    
    public init(
        autoRefreshTokens: Bool = true,
        rememberCredentials: Bool = true,
        showRateLimitWarnings: Bool = true,
        queueFailedPosts: Bool = true
    ) {
        self.autoRefreshTokens = autoRefreshTokens
        self.rememberCredentials = rememberCredentials
        self.showRateLimitWarnings = showRateLimitWarnings
        self.queueFailedPosts = queueFailedPosts
    }
    
    /// Default preferences for new users
    public static let `default` = AuthenticationPreferences()
}

// MARK: - Token Refresh Models

/// Result of token refresh operations
public enum TokenRefreshResult {
    case success(OAuthTokenResponse)
    case failure(TokenRefreshError)
}

/// Errors that can occur during token refresh
public enum TokenRefreshError: Error, LocalizedError {
    case noRefreshToken
    case refreshTokenExpired
    case authenticationRequired
    case networkError(Error)
    case serverError(Int, String?)
    case invalidResponse
    case rateLimitExceeded
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available"
        case .refreshTokenExpired:
            return "Refresh token has expired - re-authentication required"
        case .authenticationRequired:
            return "Authentication required - invalid credentials"
        case .networkError(let error):
            return "Network error during token refresh: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error during token refresh (\(code)): \(message ?? "Unknown error")"
        case .invalidResponse:
            return "Invalid response from token refresh endpoint"
        case .rateLimitExceeded:
            return "Rate limit exceeded during token refresh"
        case .unknown(let error):
            return "Unknown token refresh error: \(error.localizedDescription)"
        }
    }
    
    /// Whether this error indicates the refresh token is invalid and re-authentication is needed
    public var requiresReauthentication: Bool {
        switch self {
        case .noRefreshToken, .refreshTokenExpired, .authenticationRequired:
            return true
        case .serverError(let code, _):
            return code == 401 || code == 403
        default:
            return false
        }
    }
}

// MARK: - Authentication Statistics

/// Statistics about authentication usage
public struct AuthenticationStatistics: Codable, Sendable {
    public let totalPostsThisMonth: Int
    public let successfulPosts: Int
    public let failedPosts: Int
    public let queuedPosts: Int
    public let lastPostDate: Date?
    public let averagePostsPerDay: Double
    
    public init(
        totalPostsThisMonth: Int,
        successfulPosts: Int,
        failedPosts: Int,
        queuedPosts: Int,
        lastPostDate: Date? = nil,
        averagePostsPerDay: Double = 0.0
    ) {
        self.totalPostsThisMonth = totalPostsThisMonth
        self.successfulPosts = successfulPosts
        self.failedPosts = failedPosts
        self.queuedPosts = queuedPosts
        self.lastPostDate = lastPostDate
        self.averagePostsPerDay = averagePostsPerDay
    }
    
    /// Success rate as a percentage
    public var successRate: Double {
        let totalAttempts = successfulPosts + failedPosts
        guard totalAttempts > 0 else { return 0.0 }
        return Double(successfulPosts) / Double(totalAttempts) * 100.0
    }
    
    /// Empty statistics for initialization
    public static let empty = AuthenticationStatistics(
        totalPostsThisMonth: 0,
        successfulPosts: 0,
        failedPosts: 0,
        queuedPosts: 0
    )
}

// MARK: - Configuration Models

/// Configuration for authentication components
public struct AuthenticationConfiguration: Codable, Sendable {
    public let clientId: String?
    public let baseURL: String
    public let tokenRefreshMargin: TimeInterval
    public let maxRetries: Int
    public let timeoutInterval: TimeInterval
    
    public init(
        clientId: String? = nil,
        baseURL: String = "https://api.twitter.com",
        tokenRefreshMargin: TimeInterval = 15 * 60, // 15 minutes
        maxRetries: Int = 3,
        timeoutInterval: TimeInterval = 30.0
    ) {
        self.clientId = clientId
        self.baseURL = baseURL
        self.tokenRefreshMargin = tokenRefreshMargin
        self.maxRetries = maxRetries
        self.timeoutInterval = timeoutInterval
    }
    
    /// Default configuration
    public static let `default` = AuthenticationConfiguration()
}
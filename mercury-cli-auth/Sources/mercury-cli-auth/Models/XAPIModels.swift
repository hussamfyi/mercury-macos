import Foundation

// MARK: - Tweet Models

/// Request model for posting a tweet to X API
public struct TweetRequest: Codable, Sendable {
    public let text: String
    public let replySettings: String?
    public let directMessageDeepLink: String?
    public let forSuperFollowersOnly: Bool?
    public let geo: TweetGeo?
    public let media: TweetMedia?
    public let poll: TweetPoll?
    public let quoteTweetId: String?
    public let reply: TweetReply?
    
    /// Initialize a basic tweet request
    /// - Parameters:
    ///   - text: Tweet content (max 280 characters)
    ///   - replySettings: Who can reply ("everyone", "mentionedUsers", "following")
    public init(text: String, replySettings: String? = nil) {
        self.text = text
        self.replySettings = replySettings
        self.directMessageDeepLink = nil
        self.forSuperFollowersOnly = nil
        self.geo = nil
        self.media = nil
        self.poll = nil
        self.quoteTweetId = nil
        self.reply = nil
    }
    
    /// Initialize a comprehensive tweet request
    /// - Parameters:
    ///   - text: Tweet content
    ///   - replySettings: Reply permissions
    ///   - directMessageDeepLink: DM deep link URL
    ///   - forSuperFollowersOnly: Super followers only flag
    ///   - geo: Geographic information
    ///   - media: Media attachments
    ///   - poll: Poll configuration
    ///   - quoteTweetId: Tweet ID to quote
    ///   - reply: Reply configuration
    public init(
        text: String,
        replySettings: String? = nil,
        directMessageDeepLink: String? = nil,
        forSuperFollowersOnly: Bool? = nil,
        geo: TweetGeo? = nil,
        media: TweetMedia? = nil,
        poll: TweetPoll? = nil,
        quoteTweetId: String? = nil,
        reply: TweetReply? = nil
    ) {
        self.text = text
        self.replySettings = replySettings
        self.directMessageDeepLink = directMessageDeepLink
        self.forSuperFollowersOnly = forSuperFollowersOnly
        self.geo = geo
        self.media = media
        self.poll = poll
        self.quoteTweetId = quoteTweetId
        self.reply = reply
    }
    
    enum CodingKeys: String, CodingKey {
        case text
        case replySettings = "reply_settings"
        case directMessageDeepLink = "direct_message_deep_link"
        case forSuperFollowersOnly = "for_super_followers_only"
        case geo
        case media
        case poll
        case quoteTweetId = "quote_tweet_id"
        case reply
    }
}

/// Tweet geographic information
public struct TweetGeo: Codable, Sendable {
    public let placeId: String?
    
    public init(placeId: String) {
        self.placeId = placeId
    }
    
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
    }
}

/// Tweet media configuration
public struct TweetMedia: Codable, Sendable {
    public let mediaIds: [String]
    public let taggedUserIds: [String]?
    
    public init(mediaIds: [String], taggedUserIds: [String]? = nil) {
        self.mediaIds = mediaIds
        self.taggedUserIds = taggedUserIds
    }
    
    enum CodingKeys: String, CodingKey {
        case mediaIds = "media_ids"
        case taggedUserIds = "tagged_user_ids"
    }
}

/// Tweet poll configuration
public struct TweetPoll: Codable, Sendable {
    public let options: [String]
    public let durationMinutes: Int
    
    public init(options: [String], durationMinutes: Int) {
        self.options = options
        self.durationMinutes = durationMinutes
    }
    
    enum CodingKeys: String, CodingKey {
        case options
        case durationMinutes = "duration_minutes"
    }
}

/// Tweet reply configuration
public struct TweetReply: Codable, Sendable {
    public let inReplyToTweetId: String
    public let excludeReplyUserIds: [String]?
    
    public init(inReplyToTweetId: String, excludeReplyUserIds: [String]? = nil) {
        self.inReplyToTweetId = inReplyToTweetId
        self.excludeReplyUserIds = excludeReplyUserIds
    }
    
    enum CodingKeys: String, CodingKey {
        case inReplyToTweetId = "in_reply_to_tweet_id"
        case excludeReplyUserIds = "exclude_reply_user_ids"
    }
}

/// Response model for tweet posting
public struct TweetResponse: Codable, Sendable {
    public let data: TweetData
    
    public struct TweetData: Codable, Sendable {
        public let id: String
        public let text: String
        public let editHistoryTweetIds: [String]?
        
        enum CodingKeys: String, CodingKey {
            case id
            case text
            case editHistoryTweetIds = "edit_history_tweet_ids"
        }
    }
}

// MARK: - User Models

/// Response model for user information
public struct UserResponse: Codable, Sendable {
    public let data: UserData
    
    public struct UserData: Codable, Sendable {
        public let id: String
        public let name: String
        public let username: String
        public let createdAt: String?
        public let description: String?
        public let entities: UserEntities?
        public let location: String?
        public let pinnedTweetId: String?
        public let profileImageUrl: String?
        public let protected: Bool?
        public let publicMetrics: UserPublicMetrics?
        public let url: String?
        public let verified: Bool?
        public let verifiedType: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name, username, description, location, url, verified, protected
            case createdAt = "created_at"
            case entities
            case pinnedTweetId = "pinned_tweet_id"
            case profileImageUrl = "profile_image_url"
            case publicMetrics = "public_metrics"
            case verifiedType = "verified_type"
        }
    }
}

/// User entities (URLs, mentions, etc.)
public struct UserEntities: Codable, Sendable {
    public let url: UserEntityUrls?
    public let description: UserEntityUrls?
    
    public struct UserEntityUrls: Codable, Sendable {
        public let urls: [UserEntityUrl]?
        
        public struct UserEntityUrl: Codable, Sendable {
            public let start: Int
            public let end: Int
            public let url: String
            public let expandedUrl: String?
            public let displayUrl: String?
            
            enum CodingKeys: String, CodingKey {
                case start, end, url
                case expandedUrl = "expanded_url"
                case displayUrl = "display_url"
            }
        }
    }
}

/// User public metrics
public struct UserPublicMetrics: Codable, Sendable {
    public let followersCount: Int
    public let followingCount: Int
    public let tweetCount: Int
    public let listedCount: Int
    
    enum CodingKeys: String, CodingKey {
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case tweetCount = "tweet_count"
        case listedCount = "listed_count"
    }
}

// MARK: - Error Models

/// X API error response structure
public struct XAPIErrorResponse: Codable, Sendable {
    public let title: String?
    public let detail: String?
    public let type: String?
    public let status: Int?
    public let errors: [XAPIDetailedError]?
    
    enum CodingKeys: String, CodingKey {
        case title, detail, type, status, errors
    }
}

/// Detailed X API error information
public struct XAPIDetailedError: Codable, Sendable {
    public let code: String
    public let message: String
    public let parameters: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case code, message, parameters
    }
}

/// X API specific errors with comprehensive HTTP status code coverage
public enum XAPIError: Error, LocalizedError {
    case invalidURL(String)
    case missingAccessToken
    case invalidAccessToken(String)
    case invalidResponse
    case unauthorized
    case forbidden(details: String?)
    case notFound
    case requestTimeout
    case rateLimitExceeded(retryAfter: String?, remainingRequests: String?)
    case internalServerError
    case badGateway
    case serviceUnavailable
    case gatewayTimeout
    case serverError(statusCode: Int)
    case httpError(statusCode: Int, data: Data)
    case networkError(underlying: Error)
    case apiError(statusCode: Int, title: String?, detail: String?, type: String?)
    case validationError([XAPIDetailedError])
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let endpoint):
            return "Invalid URL for endpoint: \(endpoint)"
        case .missingAccessToken:
            return "Access token is required for X API requests"
        case .invalidAccessToken(let reason):
            return "Invalid access token: \(reason)"
        case .invalidResponse:
            return "Invalid response received from X API"
        case .unauthorized:
            return "Unauthorized - check your access token"
        case .forbidden(let details):
            var message = "Forbidden - insufficient permissions"
            if let details = details {
                message += ": \(details)"
            }
            return message
        case .notFound:
            return "Resource not found"
        case .requestTimeout:
            return "Request timeout - the server took too long to respond"
        case .rateLimitExceeded(let retryAfter, let remainingRequests):
            var message = "Rate limit exceeded"
            if let remaining = remainingRequests {
                message += " (remaining: \(remaining))"
            }
            if let retryAfter = retryAfter {
                message += ". Retry after: \(retryAfter)"
            } else {
                message += ". Please try again later."
            }
            return message
        case .internalServerError:
            return "X API internal server error (500)"
        case .badGateway:
            return "Bad gateway error (502) - X API server is temporarily unavailable"
        case .serviceUnavailable:
            return "Service unavailable (503) - X API is temporarily down for maintenance"
        case .gatewayTimeout:
            return "Gateway timeout (504) - X API server took too long to respond"
        case .serverError(let statusCode):
            return "X API server error (status: \(statusCode))"
        case .httpError(let statusCode, _):
            return "HTTP error (status: \(statusCode))"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .apiError(let statusCode, let title, let detail, _):
            var message = "X API error (status: \(statusCode)"
            if let title = title {
                message += ", title: \(title)"
            }
            if let detail = detail {
                message += ", detail: \(detail)"
            }
            message += ")"
            return message
        case .validationError(let errors):
            let messages = errors.map { "\($0.code): \($0.message)" }
            return "Validation errors: \(messages.joined(separator: ", "))"
        }
    }
    
    /// Indicates whether this error is retryable
    public var isRetryable: Bool {
        switch self {
        case .requestTimeout, .rateLimitExceeded, .internalServerError, 
             .badGateway, .serviceUnavailable, .gatewayTimeout,
             .networkError:
            return true
        case .serverError(let statusCode):
            return statusCode >= 500
        default:
            return false
        }
    }
}
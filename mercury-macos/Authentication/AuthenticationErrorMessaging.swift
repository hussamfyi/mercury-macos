import Foundation
import CFNetwork

// MARK: - Authentication Error Messaging System

/// Provides user-friendly error messages for different authentication scenarios
/// Focuses on clear, actionable messaging for token expiration and related issues
public class AuthenticationErrorMessaging {
    
    // MARK: - Error Context
    
    /// Context information for generating appropriate error messages
    public struct ErrorContext {
        public let userDisplayName: String?
        public let lastSuccessfulAuth: Date?
        public let queuedPostsCount: Int
        public let networkStatus: NetworkStatus
        public let previousState: AuthenticationState?
        
        public init(
            userDisplayName: String? = nil,
            lastSuccessfulAuth: Date? = nil,
            queuedPostsCount: Int = 0,
            networkStatus: NetworkStatus = .unknown,
            previousState: AuthenticationState? = nil
        ) {
            self.userDisplayName = userDisplayName
            self.lastSuccessfulAuth = lastSuccessfulAuth
            self.queuedPostsCount = queuedPostsCount
            self.networkStatus = networkStatus
            self.previousState = previousState
        }
    }
    
    /// Network status for context-aware messaging
    public enum NetworkStatus {
        case connected
        case disconnected
        case poor
        case unknown
    }
    
    /// Detailed network failure types for specific error messaging
    /// Provides comprehensive categorization of network failures to enable user-friendly
    /// error messages with specific guidance for each type of network issue
    public enum NetworkFailureType {
        /// No internet connection (Wi-Fi disconnected, ethernet unplugged, airplane mode)
        case offline
        /// Connection timeout (slow network, server overload, packet loss)
        case timeout
        /// DNS resolution failure (DNS server issues, domain not found)
        case dnsFailure
        /// Connection refused by server (firewall blocking, service down, port closed)
        case connectionRefused
        /// SSL/TLS certificate errors (invalid certificate, man-in-the-middle, clock skew)
        case certificateError
        /// Slow network detected (poor bandwidth, high latency)
        case slowConnection
        /// Host unreachable (routing issues, network infrastructure problems)
        case hostUnreachable
        /// Unknown or uncategorized network error
        case unknown(Error)
        
        /// Creates network failure type from underlying error
        /// - Parameter error: The underlying network error
        /// - Returns: Appropriate network failure type
        public static func from(_ error: Error) -> NetworkFailureType {
            let nsError = error as NSError
            
            // Check for URLError types
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    return .offline
                case NSURLErrorTimedOut:
                    return .timeout
                case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                    return .dnsFailure
                case NSURLErrorCannotConnectToHost:
                    return .connectionRefused
                case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed, NSURLErrorClientCertificateRequired:
                    return .certificateError
                // Note: NSURLErrorSlowNetworkDetected may not be available on all platforms
                // case NSURLErrorSlowNetworkDetected:
                //     return .slowConnection
                case NSURLErrorResourceUnavailable, NSURLErrorInternationalRoamingOff:
                    return .hostUnreachable
                default:
                    return .unknown(error)
                }
            }
            
            // Check for CFNetwork errors - using string constants as CFNetwork constants may not be available
            if nsError.domain == "kCFErrorDomainCFNetwork" {
                switch nsError.code {
                case 2, 3: // Host not found errors
                    return .dnsFailure
                case -1001: // Timeout
                    return .timeout
                case -1009: // Not connected to internet
                    return .offline
                default:
                    return .unknown(error)
                }
            }
            
            // Check for POSIX errors
            if nsError.domain == NSPOSIXErrorDomain {
                switch nsError.code {
                case Int(ENOTCONN), Int(ENETDOWN), Int(ENETUNREACH):
                    return .offline
                case Int(ETIMEDOUT):
                    return .timeout
                case Int(ECONNREFUSED):
                    return .connectionRefused
                case Int(EHOSTUNREACH):
                    return .hostUnreachable
                default:
                    return .unknown(error)
                }
            }
            
            return .unknown(error)
        }
    }
    
    // MARK: - Message Types
    
    /// Different types of messages for different UI contexts
    public struct ErrorMessage {
        public let title: String
        public let description: String
        public let actionTitle: String?
        public let actionDescription: String?
        public let severity: Severity
        public let category: Category
        
        public enum Severity {
            case info
            case warning
            case error
            case critical
        }
        
        public enum Category {
            case tokenExpiration
            case networkIssue
            case authenticationFailure
            case systemError
            case rateLimiting
        }
        
        public init(
            title: String,
            description: String,
            actionTitle: String? = nil,
            actionDescription: String? = nil,
            severity: Severity,
            category: Category
        ) {
            self.title = title
            self.description = description
            self.actionTitle = actionTitle
            self.actionDescription = actionDescription
            self.severity = severity
            self.category = category
        }
    }
    
    // MARK: - Main Error Message Generation
    
    /// Generates appropriate error message for authentication errors
    /// - Parameters:
    ///   - error: The authentication error
    ///   - context: Additional context for generating relevant messages
    /// - Returns: User-friendly error message
    public static func messageForAuthenticationError(
        _ error: AuthenticationError,
        context: ErrorContext = ErrorContext()
    ) -> ErrorMessage {
        switch error {
        case .authenticationInProgress:
            return createAuthenticationInProgressMessage(context: context)
            
        case .invalidCredentials:
            return createInvalidCredentialsMessage(context: context)
            
        case .networkError(let underlyingError):
            return createNetworkErrorMessage(underlyingError, context: context)
            
        case .tokenRefreshFailed(let underlyingError):
            return createTokenRefreshFailedMessage(underlyingError, context: context)
            
        case .keychainError(let underlyingError):
            return createKeychainErrorMessage(underlyingError, context: context)
            
        case .serverError(let code, let message):
            return createServerErrorMessage(code: code, message: message, context: context)
            
        case .rateLimitExceeded:
            return createRateLimitExceededMessage(context: context)
            
        case .unknown(let underlyingError):
            return createUnknownErrorMessage(underlyingError, context: context)
        }
    }
    
    /// Generates appropriate error message for tweet posting errors
    /// - Parameters:
    ///   - error: The tweet posting error
    ///   - context: Additional context for generating relevant messages
    /// - Returns: User-friendly error message
    public static func messageForTweetPostError(
        _ error: TweetPostError,
        context: ErrorContext = ErrorContext()
    ) -> ErrorMessage {
        switch error {
        case .notAuthenticated:
            return createNotAuthenticatedMessage(context: context)
            
        case .invalidTweetText(let reason):
            return createInvalidTweetTextMessage(reason: reason, context: context)
            
        case .rateLimitExceeded(let rateLimitInfo):
            return createTweetRateLimitMessage(rateLimitInfo: rateLimitInfo, context: context)
            
        case .networkError(let underlyingError):
            return createTweetNetworkErrorMessage(underlyingError, context: context)
            
        case .serverError(let code, let message):
            return createTweetServerErrorMessage(code: code, message: message, context: context)
            
        case .unknown(let underlyingError):
            return createTweetUnknownErrorMessage(underlyingError, context: context)
        }
    }
    
    /// Generates appropriate error message for token refresh errors
    /// - Parameters:
    ///   - error: The token refresh error
    ///   - context: Additional context for generating relevant messages
    /// - Returns: User-friendly error message
    public static func messageForTokenRefreshError(
        _ error: TokenRefreshError,
        context: ErrorContext = ErrorContext()
    ) -> ErrorMessage {
        switch error {
        case .noRefreshToken:
            return createNoRefreshTokenMessage(context: context)
            
        case .refreshTokenExpired:
            return createRefreshTokenExpiredMessage(context: context)
            
        case .authenticationRequired:
            return createAuthenticationRequiredMessage(context: context)
            
        case .networkError(let underlyingError):
            return createTokenRefreshNetworkErrorMessage(underlyingError, context: context)
            
        case .serverError(let code, let message):
            return createTokenRefreshServerErrorMessage(code: code, message: message, context: context)
            
        case .invalidResponse:
            return createInvalidResponseMessage(context: context)
            
        case .rateLimitExceeded:
            return createTokenRefreshRateLimitMessage(context: context)
            
        case .unknown(let underlyingError):
            return createTokenRefreshUnknownErrorMessage(underlyingError, context: context)
        }
    }
    
    // MARK: - Authentication Error Messages
    
    private static func createAuthenticationInProgressMessage(context: ErrorContext) -> ErrorMessage {
        let description = context.networkStatus == .disconnected 
            ? "Authentication is in progress. Please ensure you have a stable internet connection and wait for the process to complete."
            : "Authentication is currently in progress. Please wait for the process to complete before trying again."
        
        return ErrorMessage(
            title: "Authentication in Progress",
            description: description,
            actionTitle: "Please Wait",
            actionDescription: "The authentication process should complete shortly.",
            severity: .info,
            category: .authenticationFailure
        )
    }
    
    private static func createInvalidCredentialsMessage(context: ErrorContext) -> ErrorMessage {
        let userInfo = context.userDisplayName.map { " for \($0)" } ?? ""
        let queuedInfo = context.queuedPostsCount > 0 
            ? " Your \(context.queuedPostsCount) queued posts will be preserved."
            : ""
        
        return ErrorMessage(
            title: "Authentication Required",
            description: "Your X account credentials\(userInfo) are no longer valid and need to be refreshed.\(queuedInfo)",
            actionTitle: "Reconnect to X",
            actionDescription: "Click to sign in with your X account again. This will restore your posting access.",
            severity: .warning,
            category: .authenticationFailure
        )
    }
    
    private static func createNetworkErrorMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        let failureType = NetworkFailureType.from(underlyingError)
        let queuedInfo = context.queuedPostsCount > 0 
            ? " Your \(context.queuedPostsCount) queued posts will be posted when connection is restored."
            : ""
        
        let title: String
        let description: String
        let actionTitle: String
        let actionDescription: String
        let severity: ErrorMessage.Severity
        
        switch failureType {
        case .offline:
            title = "No Internet Connection"
            description = "Your Mac isn't connected to the internet. Authentication requires an active internet connection.\(queuedInfo)"
            actionTitle = "Check Wi-Fi"
            actionDescription = "Check your Wi-Fi or ethernet connection and try again."
            severity = .warning
            
        case .timeout:
            title = "Connection Timeout"
            description = "The connection to X timed out. This may be due to a slow or unstable internet connection.\(queuedInfo)"
            actionTitle = "Try Again"
            actionDescription = "Check your internet speed and try again. Consider switching to a faster network."
            severity = .warning
            
        case .dnsFailure:
            title = "DNS Error"
            description = "Unable to resolve X's servers. This may be a DNS configuration issue or temporary X service problem.\(queuedInfo)"
            actionTitle = "Check DNS"
            actionDescription = "Try using a different DNS server (like 8.8.8.8) or check with your network administrator."
            severity = .error
            
        case .connectionRefused:
            title = "Connection Refused"
            description = "X's servers refused the connection. This may be due to network restrictions or temporary service issues.\(queuedInfo)"
            actionTitle = "Check Network"
            actionDescription = "Check if your network blocks social media, or try from a different network."
            severity = .error
            
        case .certificateError:
            title = "Security Certificate Error"
            description = "There's an issue with X's security certificate. This could indicate a security threat or network interference.\(queuedInfo)"
            actionTitle = "Check Security"
            actionDescription = "Try from a different network. If the issue persists, contact support."
            severity = .critical
            
        case .slowConnection:
            title = "Slow Network Detected"
            description = "Your internet connection is too slow for reliable authentication. Authentication may fail with poor connectivity.\(queuedInfo)"
            actionTitle = "Improve Connection"
            actionDescription = "Switch to a faster Wi-Fi network or try again when you have better connectivity."
            severity = .warning
            
        case .hostUnreachable:
            title = "X Servers Unreachable"
            description = "Cannot reach X's servers. This may be due to network routing issues or X service outage.\(queuedInfo)"
            actionTitle = "Wait and Retry"
            actionDescription = "Check X's status page for outages, or try again from a different network."
            severity = .error
            
        case .unknown(let error):
            // Fall back to general network error handling
            switch context.networkStatus {
            case .disconnected:
                title = "No Internet Connection"
                description = "No internet connection detected. Authentication requires a stable internet connection.\(queuedInfo)"
                actionTitle = "Check Connection"
                actionDescription = "Please check your internet connection and try again."
                severity = .warning
            case .poor:
                title = "Poor Connection"
                description = "Poor internet connection detected. Authentication may fail with an unstable connection.\(queuedInfo)"
                actionTitle = "Improve Connection"
                actionDescription = "Please check your internet connection and try again."
                severity = .warning
            default:
                title = "Network Error"
                description = "Network error occurred during authentication: \(error.localizedDescription)\(queuedInfo)"
                actionTitle = "Try Again"
                actionDescription = "Please check your internet connection and try again in a moment."
                severity = .error
            }
        }
        
        return ErrorMessage(
            title: title,
            description: description,
            actionTitle: actionTitle,
            actionDescription: actionDescription,
            severity: severity,
            category: .networkIssue
        )
    }
    
    private static func createTokenRefreshFailedMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        let userInfo = context.userDisplayName.map { " for \($0)" } ?? ""
        let queuedInfo = context.queuedPostsCount > 0 
            ? " Your \(context.queuedPostsCount) queued posts are preserved and will be posted after reconnection."
            : ""
        
        return ErrorMessage(
            title: "Session Expired",
            description: "Your X session\(userInfo) has expired and automatic renewal failed.\(queuedInfo)",
            actionTitle: "Reconnect to X",
            actionDescription: "Click to sign in with your X account again to restore posting access.",
            severity: .warning,
            category: .tokenExpiration
        )
    }
    
    private static func createKeychainErrorMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Security Error",
            description: "There was an issue accessing your secure authentication data. This may be due to keychain access restrictions.",
            actionTitle: "Try Again",
            actionDescription: "If the problem persists, you may need to reconnect your X account.",
            severity: .error,
            category: .systemError
        )
    }
    
    private static func createServerErrorMessage(code: Int, message: String?, context: ErrorContext) -> ErrorMessage {
        let title: String
        let description: String
        let actionDescription: String
        let severity: ErrorMessage.Severity
        
        switch code {
        case 401:
            title = "Authentication Failed"
            description = "Your X authentication is no longer valid. Please reconnect your account."
            actionDescription = "Click to sign in with your X account again."
            severity = .warning
        case 403:
            title = "Access Denied"
            description = "Your X account doesn't have permission to perform this action. This may be due to account restrictions."
            actionDescription = "Please check your X account status or try reconnecting."
            severity = .error
        case 429:
            title = "Rate Limited"
            description = "X is temporarily limiting requests. Please wait before trying again."
            actionDescription = "Wait a few minutes and try again."
            severity = .warning
        case 500...599:
            title = "X Service Issue"
            description = "X is experiencing technical difficulties. Your posts will be queued and sent when service is restored."
            actionDescription = "Please try again in a few minutes."
            severity = .error
        default:
            title = "Server Error"
            description = message ?? "An unexpected server error occurred (\(code))."
            actionDescription = "Please try again in a moment."
            severity = .error
        }
        
        return ErrorMessage(
            title: title,
            description: description,
            actionTitle: "Try Again",
            actionDescription: actionDescription,
            severity: severity,
            category: code >= 500 ? .systemError : .authenticationFailure
        )
    }
    
    private static func createRateLimitExceededMessage(context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Rate Limit Reached",
            description: "You've reached the X API rate limit. Your posts will be queued and sent automatically when the limit resets.",
            actionTitle: "View Usage",
            actionDescription: "Check your current X API usage and limit reset time.",
            severity: .warning,
            category: .rateLimiting
        )
    }
    
    private static func createUnknownErrorMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Unexpected Error",
            description: "An unexpected error occurred during authentication: \(underlyingError.localizedDescription)",
            actionTitle: "Try Again",
            actionDescription: "If the problem persists, try reconnecting your X account.",
            severity: .error,
            category: .systemError
        )
    }
    
    // MARK: - Tweet Post Error Messages
    
    private static func createNotAuthenticatedMessage(context: ErrorContext) -> ErrorMessage {
        let queuedInfo = context.queuedPostsCount > 0 
            ? " This post and your \(context.queuedPostsCount) other queued posts will be sent after reconnection."
            : " This post has been queued and will be sent after reconnection."
        
        return ErrorMessage(
            title: "Reconnection Needed",
            description: "You need to reconnect to X to post tweets.\(queuedInfo)",
            actionTitle: "Reconnect to X",
            actionDescription: "Sign in with your X account to restore posting access.",
            severity: .warning,
            category: .authenticationFailure
        )
    }
    
    private static func createInvalidTweetTextMessage(reason: String, context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Invalid Tweet",
            description: reason,
            actionTitle: "Edit Tweet",
            actionDescription: "Please modify your tweet and try posting again.",
            severity: .error,
            category: .systemError
        )
    }
    
    private static func createTweetRateLimitMessage(rateLimitInfo: RateLimitInfo, context: ErrorContext) -> ErrorMessage {
        let resetInfo = rateLimitInfo.resetDate?.formatted(.relative(presentation: .named)) ?? "later"
        
        return ErrorMessage(
            title: "Post Limit Reached",
            description: "You've reached your X posting limit (\(rateLimitInfo.remainingRequests) of \(rateLimitInfo.totalRequests) remaining). Your tweet has been queued and will post when the limit resets \(resetInfo).",
            actionTitle: "View Limits",
            actionDescription: "Check your current posting limits and queue status.",
            severity: .warning,
            category: .rateLimiting
        )
    }
    
    private static func createTweetNetworkErrorMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        let failureType = NetworkFailureType.from(underlyingError)
        
        let title: String
        let description: String
        let actionTitle: String
        let actionDescription: String
        let severity: ErrorMessage.Severity
        
        switch failureType {
        case .offline:
            title = "No Internet Connection"
            description = "Your Mac isn't connected to the internet. Your tweet has been queued and will post when connection is restored."
            actionTitle = "Check Wi-Fi"
            actionDescription = "Check your Wi-Fi or ethernet connection."
            severity = .info
            
        case .timeout:
            title = "Post Timeout"
            description = "The connection to X timed out while posting. Your tweet has been queued and will retry automatically."
            actionTitle = "Check Connection"
            actionDescription = "Check your internet speed. The post will retry automatically."
            severity = .info
            
        case .dnsFailure:
            title = "DNS Error"
            description = "Unable to reach X's servers due to DNS issues. Your tweet has been queued for retry."
            actionTitle = "Check DNS"
            actionDescription = "Try using a different DNS server or contact your network administrator."
            severity = .warning
            
        case .connectionRefused:
            title = "Connection Blocked"
            description = "Connection to X was refused. Your tweet has been queued and will retry when the connection is available."
            actionTitle = "Check Network"
            actionDescription = "Check if your network blocks social media access."
            severity = .warning
            
        case .certificateError:
            title = "Security Error"
            description = "Security certificate error prevented posting. Your tweet has been queued for retry."
            actionTitle = "Check Security"
            actionDescription = "Try from a different network. Contact support if this persists."
            severity = .error
            
        case .slowConnection:
            title = "Slow Connection"
            description = "Your connection is too slow for posting. Your tweet has been queued and will post when connection improves."
            actionTitle = "Improve Connection"
            actionDescription = "Switch to a faster network when possible."
            severity = .info
            
        case .hostUnreachable:
            title = "X Unavailable"
            description = "Cannot reach X's servers. Your tweet has been queued and will post when X is available."
            actionTitle = "Check X Status"
            actionDescription = "Check X's status page for service outages."
            severity = .info
            
        case .unknown(_):
            // Fall back to general network error handling
            switch context.networkStatus {
            case .disconnected:
                title = "No Internet Connection"
                description = "No internet connection. Your tweet has been queued and will post when connection is restored."
                actionTitle = "Check Connection"
                actionDescription = "Check your internet connection."
                severity = .info
            case .poor:
                title = "Poor Connection"
                description = "Poor internet connection. Your tweet has been queued and will post when connection improves."
                actionTitle = "Improve Connection"
                actionDescription = "Try from a better network when possible."
                severity = .info
            default:
                title = "Network Error"
                description = "Network error occurred while posting. Your tweet has been queued for retry."
                actionTitle = "Check Queue"
                actionDescription = "View your queued tweets and connection status."
                severity = .info
            }
        }
        
        return ErrorMessage(
            title: title,
            description: description,
            actionTitle: actionTitle,
            actionDescription: actionDescription,
            severity: severity,
            category: .networkIssue
        )
    }
    
    private static func createTweetServerErrorMessage(code: Int, message: String?, context: ErrorContext) -> ErrorMessage {
        let title: String
        let description: String
        
        switch code {
        case 401:
            title = "Authentication Expired"
            description = "Your X session expired while posting. Your tweet has been queued and will post after you reconnect."
        case 403:
            title = "Tweet Blocked"
            description = message ?? "X blocked this tweet. It may violate their terms of service."
        case 422:
            title = "Tweet Error"
            description = message ?? "There's an issue with your tweet content. Please check for duplicates or policy violations."
        case 429:
            title = "Rate Limited"
            description = "X is limiting your posts. Your tweet has been queued and will post when limits reset."
        case 500...599:
            title = "X Service Issue"
            description = "X is experiencing issues. Your tweet has been queued and will post when service is restored."
        default:
            title = "Post Failed"
            description = message ?? "Failed to post tweet due to server error (\(code))."
        }
        
        return ErrorMessage(
            title: title,
            description: description,
            actionTitle: code == 403 || code == 422 ? "Edit Tweet" : "View Queue",
            actionDescription: code == 403 || code == 422 ? "Modify your tweet to comply with X's guidelines." : "Check your queued tweets.",
            severity: code == 403 || code == 422 ? .error : .warning,
            category: code >= 500 ? .systemError : .authenticationFailure
        )
    }
    
    private static func createTweetUnknownErrorMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Post Failed",
            description: "An unexpected error occurred while posting your tweet. It has been queued for retry.",
            actionTitle: "View Queue",
            actionDescription: "Check your queued tweets and try again.",
            severity: .error,
            category: .systemError
        )
    }
    
    // MARK: - Token Refresh Error Messages
    
    private static func createNoRefreshTokenMessage(context: ErrorContext) -> ErrorMessage {
        let userInfo = context.userDisplayName.map { " for \($0)" } ?? ""
        
        return ErrorMessage(
            title: "Reconnection Required",
            description: "No saved authentication found\(userInfo). You'll need to sign in with X again.",
            actionTitle: "Connect to X",
            actionDescription: "Sign in with your X account to enable posting.",
            severity: .warning,
            category: .authenticationFailure
        )
    }
    
    private static func createRefreshTokenExpiredMessage(context: ErrorContext) -> ErrorMessage {
        let userInfo = context.userDisplayName.map { " for \($0)" } ?? ""
        let queuedInfo = context.queuedPostsCount > 0 
            ? " Your \(context.queuedPostsCount) queued posts will be sent after reconnection."
            : ""
        let lastAuthInfo: String
        if let lastAuth = context.lastSuccessfulAuth {
            lastAuthInfo = " (last connected \(lastAuth.formatted(.relative(presentation: .named))))"
        } else {
            lastAuthInfo = ""
        }
        
        return ErrorMessage(
            title: "Session Expired",
            description: "Your X authentication\(userInfo) has expired\(lastAuthInfo).\(queuedInfo)",
            actionTitle: "Reconnect to X",
            actionDescription: "Sign in with your X account again to restore posting access.",
            severity: .warning,
            category: .tokenExpiration
        )
    }
    
    private static func createAuthenticationRequiredMessage(context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Sign In Required",
            description: "You need to authenticate with X to continue posting tweets.",
            actionTitle: "Connect to X",
            actionDescription: "Sign in with your X account to enable posting.",
            severity: .warning,
            category: .authenticationFailure
        )
    }
    
    private static func createTokenRefreshNetworkErrorMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        let failureType = NetworkFailureType.from(underlyingError)
        
        let title: String
        let description: String
        let actionTitle: String
        let actionDescription: String
        let severity: ErrorMessage.Severity
        
        switch failureType {
        case .offline:
            title = "No Internet Connection"
            description = "Cannot refresh your X session without internet. Posts will be queued until connection is restored."
            actionTitle = "Check Wi-Fi"
            actionDescription = "Check your Wi-Fi or ethernet connection and try again."
            severity = .warning
            
        case .timeout:
            title = "Session Refresh Timeout"
            description = "Session refresh timed out due to slow connection. The system will retry automatically when connection improves."
            actionTitle = "Check Speed"
            actionDescription = "Check your internet speed or try from a faster network."
            severity = .warning
            
        case .dnsFailure:
            title = "DNS Error"
            description = "Cannot refresh session due to DNS issues. Posts will be queued and session refresh will retry automatically."
            actionTitle = "Check DNS"
            actionDescription = "Try using a different DNS server or contact your network administrator."
            severity = .error
            
        case .connectionRefused:
            title = "Connection Blocked"
            description = "Session refresh was blocked by network. Posts will be queued until connection is available."
            actionTitle = "Check Network"
            actionDescription = "Check if your network blocks social media, or try from a different network."
            severity = .error
            
        case .certificateError:
            title = "Security Certificate Error"
            description = "Session refresh failed due to security certificate issues. This may indicate network interference."
            actionTitle = "Check Security"
            actionDescription = "Try from a different network. Contact support if this persists."
            severity = .critical
            
        case .slowConnection:
            title = "Slow Connection"
            description = "Session refresh is failing due to slow connection. Posts will be queued and refresh will retry automatically."
            actionTitle = "Improve Connection"
            actionDescription = "Switch to a faster network when possible for reliable session management."
            severity = .warning
            
        case .hostUnreachable:
            title = "X Service Unreachable"
            description = "Cannot reach X's authentication servers. Session refresh will retry automatically when service is available."
            actionTitle = "Check X Status"
            actionDescription = "Check X's status page for authentication service outages."
            severity = .warning
            
        case .unknown(_):
            // Fall back to general network error handling
            switch context.networkStatus {
            case .disconnected:
                title = "No Internet Connection"
                description = "Cannot refresh your X session without internet. Posts will be queued until connection is restored."
                actionTitle = "Check Connection"
                actionDescription = "Ensure you have a stable internet connection."
                severity = .warning
            case .poor:
                title = "Poor Connection"
                description = "Poor connection is preventing session refresh. Posts will be queued until connection improves."
                actionTitle = "Improve Connection"
                actionDescription = "Try from a better network when possible."
                severity = .warning
            default:
                title = "Network Error"
                description = "Network error prevented session refresh. Posts will be queued and session will retry automatically."
                actionTitle = "Check Connection"
                actionDescription = "Ensure you have a stable internet connection."
                severity = .warning
            }
        }
        
        return ErrorMessage(
            title: title,
            description: description,
            actionTitle: actionTitle,
            actionDescription: actionDescription,
            severity: severity,
            category: .networkIssue
        )
    }
    
    private static func createTokenRefreshServerErrorMessage(code: Int, message: String?, context: ErrorContext) -> ErrorMessage {
        let title: String
        let description: String
        
        switch code {
        case 401, 403:
            title = "Authentication Invalid"
            description = "Your X authentication is no longer valid. Please reconnect your account."
        case 429:
            title = "Too Many Requests"
            description = "X is limiting authentication requests. Session refresh will retry automatically."
        case 500...599:
            title = "X Service Issue"
            description = "X authentication service is experiencing issues. Session refresh will retry automatically."
        default:
            title = "Authentication Error"
            description = message ?? "Session refresh failed due to server error (\(code))."
        }
        
        return ErrorMessage(
            title: title,
            description: description,
            actionTitle: code == 401 || code == 403 ? "Reconnect" : "Wait",
            actionDescription: code == 401 || code == 403 ? "Sign in with your X account again." : "The system will retry automatically.",
            severity: .warning,
            category: code >= 500 ? .systemError : .authenticationFailure
        )
    }
    
    private static func createInvalidResponseMessage(context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Authentication Error",
            description: "Received an invalid response from X during session refresh. This may be a temporary issue.",
            actionTitle: "Try Again",
            actionDescription: "If the problem persists, try reconnecting your X account.",
            severity: .warning,
            category: .systemError
        )
    }
    
    private static func createTokenRefreshRateLimitMessage(context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Rate Limited",
            description: "X is limiting authentication requests. Your session refresh will retry automatically when the limit resets.",
            actionTitle: "Please Wait",
            actionDescription: "The system will handle this automatically. No action needed.",
            severity: .info,
            category: .rateLimiting
        )
    }
    
    private static func createTokenRefreshUnknownErrorMessage(_ underlyingError: Error, context: ErrorContext) -> ErrorMessage {
        return ErrorMessage(
            title: "Session Refresh Failed",
            description: "An unexpected error occurred while refreshing your X session: \(underlyingError.localizedDescription)",
            actionTitle: "Reconnect",
            actionDescription: "If the problem persists, try signing in with your X account again.",
            severity: .warning,
            category: .systemError
        )
    }
}

// MARK: - Error Message Extensions

extension AuthenticationError {
    /// Gets user-friendly error message with context
    /// - Parameter context: Additional context for generating relevant messages
    /// - Returns: User-friendly error message
    public func userMessage(context: AuthenticationErrorMessaging.ErrorContext = AuthenticationErrorMessaging.ErrorContext()) -> AuthenticationErrorMessaging.ErrorMessage {
        return AuthenticationErrorMessaging.messageForAuthenticationError(self, context: context)
    }
}

extension TweetPostError {
    /// Gets user-friendly error message with context
    /// - Parameter context: Additional context for generating relevant messages
    /// - Returns: User-friendly error message
    public func userMessage(context: AuthenticationErrorMessaging.ErrorContext = AuthenticationErrorMessaging.ErrorContext()) -> AuthenticationErrorMessaging.ErrorMessage {
        return AuthenticationErrorMessaging.messageForTweetPostError(self, context: context)
    }
}

extension TokenRefreshError {
    /// Gets user-friendly error message with context
    /// - Parameter context: Additional context for generating relevant messages
    /// - Returns: User-friendly error message
    public func userMessage(context: AuthenticationErrorMessaging.ErrorContext = AuthenticationErrorMessaging.ErrorContext()) -> AuthenticationErrorMessaging.ErrorMessage {
        return AuthenticationErrorMessaging.messageForTokenRefreshError(self, context: context)
    }
}

// MARK: - Convenience Methods

extension AuthenticationErrorMessaging {
    
    /// Creates a quick error context from basic parameters
    /// - Parameters:
    ///   - username: Username if available
    ///   - queuedPosts: Number of queued posts
    ///   - isConnected: Network connection status
    /// - Returns: Error context
    public static func quickContext(username: String? = nil, queuedPosts: Int = 0, isConnected: Bool = true) -> ErrorContext {
        return ErrorContext(
            userDisplayName: username,
            queuedPostsCount: queuedPosts,
            networkStatus: isConnected ? .connected : .disconnected
        )
    }
    
    /// Gets a simple error message for token expiration scenarios
    /// - Parameters:
    ///   - username: Username if available
    ///   - queuedPosts: Number of queued posts
    /// - Returns: User-friendly error message
    public static func tokenExpiredMessage(username: String? = nil, queuedPosts: Int = 0) -> ErrorMessage {
        let context = quickContext(username: username, queuedPosts: queuedPosts)
        let error = TokenRefreshError.refreshTokenExpired
        return error.userMessage(context: context)
    }
    
    /// Gets a simple error message for network issues
    /// - Parameters:
    ///   - isConnected: Network connection status
    ///   - queuedPosts: Number of queued posts
    /// - Returns: User-friendly error message
    public static func networkIssueMessage(isConnected: Bool = false, queuedPosts: Int = 0) -> ErrorMessage {
        let context = quickContext(queuedPosts: queuedPosts, isConnected: isConnected)
        let error = AuthenticationError.networkError(NSError(domain: "NetworkError", code: 1))
        return error.userMessage(context: context)
    }
    
    /// Gets a simple error message for authentication required scenarios
    /// - Parameters:
    ///   - username: Username if available
    ///   - queuedPosts: Number of queued posts
    /// - Returns: User-friendly error message
    public static func authRequiredMessage(username: String? = nil, queuedPosts: Int = 0) -> ErrorMessage {
        let context = quickContext(username: username, queuedPosts: queuedPosts)
        let error = AuthenticationError.invalidCredentials
        return error.userMessage(context: context)
    }
    
    /// Gets a simple error message for rate limiting scenarios
    /// - Parameter rateLimitInfo: Rate limit information
    /// - Returns: User-friendly error message
    public static func rateLimitMessage(rateLimitInfo: RateLimitInfo) -> ErrorMessage {
        let context = quickContext()
        let error = TweetPostError.rateLimitExceeded(rateLimitInfo)
        return error.userMessage(context: context)
    }
    
    /// Gets specific network error message for offline scenarios
    /// - Parameters:
    ///   - queuedPosts: Number of queued posts
    ///   - operationType: Type of operation that failed (authentication, posting, refresh)
    /// - Returns: User-friendly error message for offline scenarios
    public static func offlineMessage(queuedPosts: Int = 0, operationType: String = "operation") -> ErrorMessage {
        let context = quickContext(queuedPosts: queuedPosts, isConnected: false)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let authError = AuthenticationError.networkError(error)
        return authError.userMessage(context: context)
    }
    
    /// Gets specific network error message for timeout scenarios
    /// - Parameters:
    ///   - queuedPosts: Number of queued posts
    ///   - operationType: Type of operation that timed out
    /// - Returns: User-friendly error message for timeout scenarios
    public static func timeoutMessage(queuedPosts: Int = 0, operationType: String = "operation") -> ErrorMessage {
        let context = quickContext(queuedPosts: queuedPosts, isConnected: true)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let authError = AuthenticationError.networkError(error)
        return authError.userMessage(context: context)
    }
    
    /// Gets specific network error message for DNS failure scenarios
    /// - Parameters:
    ///   - queuedPosts: Number of queued posts
    ///   - operationType: Type of operation that failed due to DNS
    /// - Returns: User-friendly error message for DNS failure scenarios
    public static func dnsFailureMessage(queuedPosts: Int = 0, operationType: String = "operation") -> ErrorMessage {
        let context = quickContext(queuedPosts: queuedPosts, isConnected: true)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let authError = AuthenticationError.networkError(error)
        return authError.userMessage(context: context)
    }
    
    /// Gets specific network error message for connection refused scenarios
    /// - Parameters:
    ///   - queuedPosts: Number of queued posts
    ///   - operationType: Type of operation that was refused
    /// - Returns: User-friendly error message for connection refused scenarios
    public static func connectionRefusedMessage(queuedPosts: Int = 0, operationType: String = "operation") -> ErrorMessage {
        let context = quickContext(queuedPosts: queuedPosts, isConnected: true)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        let authError = AuthenticationError.networkError(error)
        return authError.userMessage(context: context)
    }
    
    /// Gets specific network error message for certificate error scenarios
    /// - Parameters:
    ///   - queuedPosts: Number of queued posts
    ///   - operationType: Type of operation that failed due to certificate issues
    /// - Returns: User-friendly error message for certificate error scenarios
    public static func certificateErrorMessage(queuedPosts: Int = 0, operationType: String = "operation") -> ErrorMessage {
        let context = quickContext(queuedPosts: queuedPosts, isConnected: true)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        let authError = AuthenticationError.networkError(error)
        return authError.userMessage(context: context)
    }
}

// MARK: - Message Formatting Extensions

extension AuthenticationErrorMessaging.ErrorMessage {
    
    /// Gets a compact message suitable for status bars or notifications
    /// - Returns: Compact message string
    public var compactMessage: String {
        switch severity {
        case .info, .warning:
            return title
        case .error, .critical:
            return "\(title): \(description)"
        }
    }
    
    /// Gets a detailed message suitable for error dialogs
    /// - Returns: Detailed message string with action guidance
    public var detailedMessage: String {
        var message = "\(title)\n\n\(description)"
        
        if let actionTitle = actionTitle, let actionDescription = actionDescription {
            message += "\n\n\(actionTitle): \(actionDescription)"
        }
        
        return message
    }
    
    /// Gets an appropriate emoji prefix based on message severity
    /// - Returns: Emoji string
    public var emoji: String {
        switch severity {
        case .info:
            return "ℹ️"
        case .warning:
            return "⚠️"
        case .error:
            return "❌"
        case .critical:
            return "🚨"
        }
    }
    
    /// Gets the message with emoji prefix
    /// - Returns: Message with appropriate emoji
    public var messageWithEmoji: String {
        return "\(emoji) \(title)"
    }
}
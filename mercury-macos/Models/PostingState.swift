import Foundation
import SwiftUI
import Combine

/// Comprehensive data models for posting states with authentication awareness
/// Provides reactive state management for Mercury's posting interface

// MARK: - Primary Posting State

/// Represents the current posting state for UI updates with authentication context
public enum PostingState: Equatable {
    case idle
    case loading(PostingProgress)
    case success(TweetPostSuccess)
    case error(PostingErrorState)
    
    // MARK: - Convenience Properties
    
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
    
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
    
    /// Whether user input should be disabled
    public var shouldDisableInput: Bool {
        switch self {
        case .loading:
            return true
        default:
            return false
        }
    }
    
    /// Whether posting actions should be disabled
    public var shouldDisablePosting: Bool {
        switch self {
        case .loading:
            return true
        case .error(let errorState):
            return !errorState.canRetry
        default:
            return false
        }
    }
    
    /// Progress information for loading states
    public var progress: PostingProgress? {
        if case .loading(let progress) = self {
            return progress
        }
        return nil
    }
    
    /// Error information for error states
    public var errorState: PostingErrorState? {
        if case .error(let errorState) = self {
            return errorState
        }
        return nil
    }
    
    /// Success information for success states
    public var successInfo: TweetPostSuccess? {
        if case .success(let success) = self {
            return success
        }
        return nil
    }
    
    // MARK: - UI Display Properties
    
    /// User-friendly description of current state
    public var displayDescription: String {
        switch self {
        case .idle:
            return "Ready to post"
        case .loading(let progress):
            return progress.displayText
        case .success(let success):
            return "Posted successfully"
        case .error(let errorState):
            return errorState.displayDescription
        }
    }
    
    /// Color to use for state indicators
    public var indicatorColor: Color {
        switch self {
        case .idle:
            return .primary
        case .loading:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }
    
    /// SF Symbol icon for current state
    public var icon: String {
        switch self {
        case .idle:
            return "square.and.pencil"
        case .loading:
            return "arrow.clockwise"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Posting Progress

/// Detailed progress information for posting operations
public struct PostingProgress: Equatable {
    public let phase: PostingPhase
    public let authenticationRequired: Bool
    public let networkQuality: NetworkQuality?
    public let estimatedTimeRemaining: TimeInterval?
    
    public init(
        phase: PostingPhase,
        authenticationRequired: Bool = false,
        networkQuality: NetworkQuality? = nil,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.phase = phase
        self.authenticationRequired = authenticationRequired
        self.networkQuality = networkQuality
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
    
    /// User-friendly display text for current progress
    public var displayText: String {
        if authenticationRequired {
            return "Authenticating..."
        }
        
        switch phase {
        case .validating:
            return "Validating tweet..."
        case .authenticating:
            return "Checking authentication..."
        case .checkingRateLimit:
            return "Checking rate limit..."
        case .posting:
            return "Posting tweet..."
        case .processing:
            return "Processing..."
        case .queuing:
            return "Queuing for retry..."
        }
    }
    
    /// Progress percentage (0.0 to 1.0) for progress indicators
    public var progressPercentage: Double {
        switch phase {
        case .validating:
            return 0.1
        case .authenticating:
            return 0.3
        case .checkingRateLimit:
            return 0.5
        case .posting:
            return 0.8
        case .processing:
            return 0.9
        case .queuing:
            return 1.0
        }
    }
    
    /// Whether to show an indeterminate progress indicator
    public var isIndeterminate: Bool {
        switch phase {
        case .authenticating, .posting, .processing:
            return true
        default:
            return false
        }
    }
}

/// Phases of the posting process
public enum PostingPhase: String, CaseIterable {
    case validating = "validating"
    case authenticating = "authenticating" 
    case checkingRateLimit = "checking_rate_limit"
    case posting = "posting"
    case processing = "processing"
    case queuing = "queuing"
    
    public var displayName: String {
        switch self {
        case .validating:
            return "Validating"
        case .authenticating:
            return "Authenticating"
        case .checkingRateLimit:
            return "Checking Limits"
        case .posting:
            return "Posting"
        case .processing:
            return "Processing"
        case .queuing:
            return "Queuing"
        }
    }
    
    public var description: String {
        switch self {
        case .validating:
            return "Validating tweet content and length"
        case .authenticating:
            return "Verifying authentication status"
        case .checkingRateLimit:
            return "Checking rate limit status"
        case .posting:
            return "Sending tweet to X API"
        case .processing:
            return "Processing API response"
        case .queuing:
            return "Adding to retry queue"
        }
    }
}

// MARK: - Connection Status

/// Represents connection status for status indicators with authentication awareness
public enum ConnectionStatus: Equatable {
    case disconnected
    case connecting(progress: AuthenticationProgress?)
    case connected(user: ConnectedUserInfo)
    case refreshing(reason: RefreshReason)
    case disconnecting
    case error(ConnectionError)
    
    // MARK: - Convenience Properties
    
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    public var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
    
    public var isDisconnected: Bool {
        if case .disconnected = self { return true }
        return false
    }
    
    public var hasError: Bool {
        if case .error = self { return true }
        return false
    }
    
    public var canPost: Bool {
        switch self {
        case .connected:
            return true
        default:
            return false
        }
    }
    
    // MARK: - UI Display Properties
    
    public var displayText: String {
        switch self {
        case .disconnected:
            return "Not connected"
        case .connecting(let progress):
            return progress?.displayText ?? "Connecting..."
        case .connected(let user):
            return "Connected as @\(user.username)"
        case .refreshing(let reason):
            return reason.displayText
        case .disconnecting:
            return "Disconnecting..."
        case .error(let error):
            return error.displayText
        }
    }
    
    public var statusColor: Color {
        switch self {
        case .disconnected:
            return .secondary
        case .connecting, .refreshing, .disconnecting:
            return .orange
        case .connected:
            return .green
        case .error:
            return .red
        }
    }
    
    public var icon: String {
        switch self {
        case .disconnected:
            return "wifi.slash"
        case .connecting, .refreshing, .disconnecting:
            return "arrow.clockwise"
        case .connected:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    /// Whether to show an animated indicator
    public var isAnimated: Bool {
        switch self {
        case .connecting, .refreshing, .disconnecting:
            return true
        default:
            return false
        }
    }
}

// MARK: - Supporting Connection Types

/// Information about connected user
public struct ConnectedUserInfo: Equatable {
    public let username: String
    public let displayName: String?
    public let profileImageUrl: String?
    public let isVerified: Bool
    public let connectionTime: Date
    
    public init(
        username: String,
        displayName: String? = nil,
        profileImageUrl: String? = nil,
        isVerified: Bool = false,
        connectionTime: Date = Date()
    ) {
        self.username = username
        self.displayName = displayName
        self.profileImageUrl = profileImageUrl
        self.isVerified = isVerified
        self.connectionTime = connectionTime
    }
    
    /// Create from AuthenticatedUser
    public init(from user: AuthenticatedUser) {
        self.username = user.username
        self.displayName = user.name
        self.profileImageUrl = user.profileImageUrl
        self.isVerified = user.verified ?? false
        self.connectionTime = Date()
    }
    
    public var displayName_or_username: String {
        return displayName ?? username
    }
}

/// Progress information for authentication process
public struct AuthenticationProgress: Equatable {
    public let phase: AuthenticationPhase
    public let isUserInteractionRequired: Bool
    public let estimatedTimeRemaining: TimeInterval?
    
    public init(
        phase: AuthenticationPhase,
        isUserInteractionRequired: Bool = false,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.phase = phase
        self.isUserInteractionRequired = isUserInteractionRequired
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
    
    public var displayText: String {
        if isUserInteractionRequired {
            return "Waiting for authorization..."
        }
        return phase.displayText
    }
}

/// Phases of authentication process
public enum AuthenticationPhase: String, CaseIterable {
    case starting = "starting"
    case generatingChallenge = "generating_challenge"
    case openingBrowser = "opening_browser"
    case waitingForCallback = "waiting_for_callback"
    case exchangingCode = "exchanging_code"
    case retrievingUserInfo = "retrieving_user_info"
    case storing = "storing"
    case completing = "completing"
    
    public var displayText: String {
        switch self {
        case .starting:
            return "Starting authentication..."
        case .generatingChallenge:
            return "Generating security challenge..."
        case .openingBrowser:
            return "Opening browser..."
        case .waitingForCallback:
            return "Waiting for authorization..."
        case .exchangingCode:
            return "Exchanging authorization code..."
        case .retrievingUserInfo:
            return "Retrieving user information..."
        case .storing:
            return "Storing credentials..."
        case .completing:
            return "Completing authentication..."
        }
    }
}

/// Reasons for connection refresh
public enum RefreshReason: Equatable {
    case tokenExpiring
    case tokenExpired
    case networkReconnected
    case userRequested
    case automatic
    
    public var displayText: String {
        switch self {
        case .tokenExpiring:
            return "Refreshing connection..."
        case .tokenExpired:
            return "Reconnecting..."
        case .networkReconnected:
            return "Restoring connection..."
        case .userRequested:
            return "Refreshing..."
        case .automatic:
            return "Updating connection..."
        }
    }
}

/// Connection errors with context
public struct ConnectionError: Equatable {
    public let type: ConnectionErrorType
    public let underlyingError: String?
    public let isRecoverable: Bool
    public let requiresUserAction: Bool
    public let suggestedActions: [ErrorAction]
    
    public init(
        type: ConnectionErrorType,
        underlyingError: String? = nil,
        isRecoverable: Bool = true,
        requiresUserAction: Bool = false,
        suggestedActions: [ErrorAction] = []
    ) {
        self.type = type
        self.underlyingError = underlyingError
        self.isRecoverable = isRecoverable
        self.requiresUserAction = requiresUserAction
        self.suggestedActions = suggestedActions
    }
    
    public var displayText: String {
        return type.displayText
    }
    
    public static func == (lhs: ConnectionError, rhs: ConnectionError) -> Bool {
        return lhs.type == rhs.type &&
               lhs.underlyingError == rhs.underlyingError &&
               lhs.isRecoverable == rhs.isRecoverable &&
               lhs.requiresUserAction == rhs.requiresUserAction
    }
}

/// Types of connection errors
public enum ConnectionErrorType: Equatable {
    case networkError
    case authenticationFailed
    case tokenExpired
    case rateLimited
    case serverError
    case unknown
    
    public var displayText: String {
        switch self {
        case .networkError:
            return "Network error"
        case .authenticationFailed:
            return "Authentication failed"
        case .tokenExpired:
            return "Session expired"
        case .rateLimited:
            return "Rate limited"
        case .serverError:
            return "Server error"
        case .unknown:
            return "Connection error"
        }
    }
}

// MARK: - Posting Error State

/// Detailed error state for posting operations with authentication context
public struct PostingErrorState: Equatable {
    public let error: TweetPostError
    public let isRecoverable: Bool
    public let preservedText: String?
    public let canRetry: Bool
    public let authenticationState: AuthenticationState?
    public let suggestedActions: [ErrorAction]
    public let occurredAt: Date
    
    public init(
        error: TweetPostError,
        isRecoverable: Bool = true,
        preservedText: String? = nil,
        canRetry: Bool = false,
        authenticationState: AuthenticationState? = nil,
        suggestedActions: [ErrorAction] = [],
        occurredAt: Date = Date()
    ) {
        self.error = error
        self.isRecoverable = isRecoverable
        self.preservedText = preservedText
        self.canRetry = canRetry
        self.authenticationState = authenticationState
        self.suggestedActions = suggestedActions
        self.occurredAt = occurredAt
    }
    
    /// User-friendly display description
    public var displayDescription: String {
        switch error {
        case .notAuthenticated:
            return "Please connect your X account"
        case .invalidTweetText(let reason):
            return reason
        case .rateLimitExceeded:
            return "Rate limit reached"
        case .networkError:
            return "Network error"
        case .serverError:
            return "X is experiencing issues"
        case .unknown:
            return "Something went wrong"
        }
    }
    
    /// Detailed error description for debugging
    public var detailedDescription: String {
        var description = displayDescription
        
        if let authState = authenticationState {
            description += " (Auth: \(authState))"
        }
        
        if let underlyingMessage = error.errorDescription {
            description += "\nDetails: \(underlyingMessage)"
        }
        
        return description
    }
    
    /// Whether this error requires immediate user attention
    public var requiresImmediateAttention: Bool {
        switch error {
        case .notAuthenticated:
            return true
        case .invalidTweetText:
            return true
        default:
            return false
        }
    }
    
    /// Time since error occurred
    public var timeAgo: String {
        let interval = Date().timeIntervalSince(occurredAt)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
    
    public static func == (lhs: PostingErrorState, rhs: PostingErrorState) -> Bool {
        return lhs.error.localizedDescription == rhs.error.localizedDescription &&
               lhs.isRecoverable == rhs.isRecoverable &&
               lhs.preservedText == rhs.preservedText &&
               lhs.canRetry == rhs.canRetry
    }
}

// MARK: - Error Actions

/// Actions available for error recovery with context awareness
public enum ErrorAction: String, CaseIterable {
    case retry = "retry"
    case reconnect = "reconnect"
    case viewUsage = "view_usage"
    case editText = "edit_text"
    case copyError = "copy_error"
    case dismiss = "dismiss"
    
    public var title: String {
        switch self {
        case .retry:
            return "Retry"
        case .reconnect:
            return "Reconnect"
        case .viewUsage:
            return "View Usage"
        case .editText:
            return "Edit Text"
        case .copyError:
            return "Copy Error"
        case .dismiss:
            return "Dismiss"
        }
    }
    
    public var icon: String {
        switch self {
        case .retry:
            return "arrow.clockwise"
        case .reconnect:
            return "wifi"
        case .viewUsage:
            return "chart.bar"
        case .editText:
            return "pencil"
        case .copyError:
            return "doc.on.doc"
        case .dismiss:
            return "xmark"
        }
    }
    
    public var isPrimary: Bool {
        switch self {
        case .retry, .reconnect, .editText:
            return true
        default:
            return false
        }
    }
    
    /// Whether this action requires authentication
    public var requiresAuthentication: Bool {
        switch self {
        case .retry, .viewUsage:
            return true
        default:
            return false
        }
    }
}

// MARK: - Network Quality

/// Network quality indicators for posting optimization
public enum NetworkQuality: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case offline = "offline"
    
    public var displayText: String {
        switch self {
        case .excellent:
            return "Excellent"
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .poor:
            return "Poor"
        case .offline:
            return "Offline"
        }
    }
    
    public var color: Color {
        switch self {
        case .excellent, .good:
            return .green
        case .fair:
            return .orange
        case .poor, .offline:
            return .red
        }
    }
    
    public var icon: String {
        switch self {
        case .excellent:
            return "wifi"
        case .good:
            return "wifi"
        case .fair:
            return "wifi.exclamationmark"
        case .poor:
            return "wifi.slash"
        case .offline:
            return "wifi.slash"
        }
    }
    
    /// Whether posting should be attempted with this network quality
    public var shouldAttemptPosting: Bool {
        switch self {
        case .excellent, .good, .fair:
            return true
        case .poor, .offline:
            return false
        }
    }
}

// MARK: - State Factory Methods

extension PostingState {
    /// Creates a loading state for a specific phase
    public static func loading(
        phase: PostingPhase,
        authenticationRequired: Bool = false,
        networkQuality: NetworkQuality? = nil
    ) -> PostingState {
        let progress = PostingProgress(
            phase: phase,
            authenticationRequired: authenticationRequired,
            networkQuality: networkQuality
        )
        return .loading(progress)
    }
    
    /// Creates an error state with suggested actions
    public static func error(
        _ error: TweetPostError,
        preservedText: String? = nil,
        authenticationState: AuthenticationState? = nil,
        suggestedActions: [ErrorAction] = []
    ) -> PostingState {
        let errorState = PostingErrorState(
            error: error,
            isRecoverable: true,
            preservedText: preservedText,
            canRetry: true,
            authenticationState: authenticationState,
            suggestedActions: suggestedActions
        )
        return .error(errorState)
    }
}

extension ConnectionStatus {
    /// Creates connected status from authenticated user
    public static func connected(from user: AuthenticatedUser) -> ConnectionStatus {
        let userInfo = ConnectedUserInfo(from: user)
        return .connected(user: userInfo)
    }
    
    /// Creates connecting status with authentication phase
    public static func connecting(phase: AuthenticationPhase) -> ConnectionStatus {
        let progress = AuthenticationProgress(phase: phase)
        return .connecting(progress: progress)
    }
    
    /// Creates error status from authentication error
    public static func error(from authError: AuthenticationError, isRecoverable: Bool = true) -> ConnectionStatus {
        let errorType: ConnectionErrorType
        
        switch authError {
        case .networkError:
            errorType = .networkError
        case .invalidCredentials:
            errorType = .authenticationFailed
        case .tokenRefreshFailed:
            errorType = .tokenExpired
        case .rateLimitExceeded:
            errorType = .rateLimited
        case .serverError:
            errorType = .serverError
        default:
            errorType = .unknown
        }
        
        let connectionError = ConnectionError(
            type: errorType,
            underlyingError: authError.localizedDescription,
            isRecoverable: isRecoverable
        )
        
        return .error(connectionError)
    }
}
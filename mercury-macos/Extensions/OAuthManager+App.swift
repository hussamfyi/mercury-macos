import Foundation
import Combine

// Import the Phase 1 OAuth components
// Note: In a real implementation, these would be added as dependencies to Package.swift
// For now, we'll create protocol wrappers to define the interface

// MARK: - Operation Type Definition (from Phase 1 XAPIClient)

/// Operation type for configuring appropriate timeouts
public enum XAPIOperationType {
    case authentication  // 30s timeout per PRD
    case posting        // 10s timeout per PRD
    case general        // Default timeout
}

// MARK: - Protocol Wrappers for Phase 1 Components

/// Protocol wrapper for the Phase 1 OAuthManager
public protocol OAuthManagerProtocol {
    func startAuthorizationFlow(scopes: String) throws -> URL
    func exchangeCodeForToken(authorizationCode: String, receivedState: String) async throws -> OAuthTokenResponse
    func refreshAccessToken(refreshToken: String) async throws -> OAuthTokenResponse
    func openAuthorizationUrl(_ authUrl: URL) throws
}

/// Protocol wrapper for the Phase 1 XAPIClient
public protocol XAPIClientProtocol {
    func setAccessToken(_ token: String) throws
    func postTweet(_ tweetRequest: TweetRequest) async throws -> TweetResponse
    func getCurrentUser() async throws -> UserResponse
}

/// Protocol wrapper for the Phase 1 HTTPServer
public protocol HTTPServerProtocol {
    func start() async throws -> Int // Returns port number
    func waitForCallback() async throws -> CallbackResult
    func stop() async throws
}

// MARK: - AuthManager Integration Extension

extension AuthManager {
    
    /// Integrates Phase 1 OAuth flow into AuthManager.authenticate() method
    internal func performOAuthAuthentication() async -> AuthenticationResult {
        do {
            // Step 1: Get client ID from environment or user defaults
            guard let clientId = getClientId() else {
                throw AuthenticationError.invalidCredentials
            }
            
            // Step 2: Start HTTP server for callback
            let httpServer = createHTTPServer()
            let serverPort = try await httpServer.start()
            let redirectUri = "http://localhost:\(serverPort)/callback"
            
            // Step 3: Initialize OAuth manager
            let oauthManager = createOAuthManager(clientId: clientId, redirectUri: redirectUri)
            
            // Step 4: Generate authorization URL
            let authUrl = try oauthManager.startAuthorizationFlow(
                scopes: "tweet.read tweet.write users.read offline.access"
            )
            
            // Step 5: Open browser for authentication
            try oauthManager.openAuthorizationUrl(authUrl)
            
            // Step 6: Wait for callback
            let callbackResult = try await httpServer.waitForCallback()
            try await httpServer.stop()
            
            // Step 7: Validate callback
            guard let authCode = callbackResult.authorizationCode,
                  let state = callbackResult.state else {
                throw AuthenticationError.invalidCredentials
            }
            
            // Step 8: Exchange code for tokens
            let tokenResponse = try await oauthManager.exchangeCodeForToken(
                authorizationCode: authCode,
                receivedState: state
            )
            
            // Step 9: Store tokens securely
            try await keychainManager.storeAccessToken(tokenResponse.accessToken)
            if let refreshToken = tokenResponse.refreshToken {
                try await keychainManager.storeRefreshToken(refreshToken)
            }
            
            // Calculate and store expiry date
            let expiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 7200))
            try await keychainManager.storeTokenExpiry(expiryDate)
            
            // Step 10: Validate token and get user info
            let apiClient = createXAPIClient(operationType: .authentication)
            try apiClient.setAccessToken(tokenResponse.accessToken)
            let userResponse = try await apiClient.getCurrentUser()
            
            // Step 11: Store user info and create authenticated user
            let authenticatedUser = AuthenticatedUser(
                id: userResponse.data.id,
                username: userResponse.data.username,
                name: userResponse.data.name,
                profileImageUrl: userResponse.data.profileImageUrl,
                followersCount: userResponse.data.publicMetrics?.followersCount,
                followingCount: userResponse.data.publicMetrics?.followingCount,
                tweetCount: userResponse.data.publicMetrics?.tweetCount,
                verified: userResponse.data.verified
            )
            
            try await keychainManager.storeUserInfo(authenticatedUser)
            
            // Step 12: Update state and start token refresh
            await MainActor.run {
                self.currentUser = authenticatedUser
                self.authenticationState = .authenticated
            }
            
            await tokenRefreshManager.startRefreshTimer()
            
            return .success(authenticatedUser)
            
        } catch let error as AuthenticationError {
            await MainActor.run {
                self.authenticationState = .error(error)
            }
            return .failure(error)
            
        } catch {
            let authError = AuthenticationError.unknown(error)
            await MainActor.run {
                self.authenticationState = .error(authError)
            }
            return .failure(authError)
        }
    }
    
    /// Integrates Phase 1 XAPIClient into AuthManager.postTweet() method
    /// Includes graceful handling of expired access tokens during API calls
    internal func performTweetPost(_ text: String) async -> TweetPostResult {
        // Register this posting operation to prevent token refresh interference
        let operationId = tokenRefreshManager.registerPostingOperation()
        
        defer {
            // Always unregister the operation when done
            tokenRefreshManager.unregisterPostingOperation(operationId)
        }
        
        // Comprehensive token validation before critical operation
        let validationResult = await ensureTokenValidForOperation(.tweetPost)
        
        if !validationResult.isValid {
            print("❌ Token validation failed for tweet posting")
            
            // Convert validation failure to appropriate TweetPostError
            let context = getCurrentErrorContext()
            let postError: TweetPostError
            
            switch validationResult.status {
            case .expired, .refreshRequired, .invalid, .missing, .authenticationRequired:
                postError = .notAuthenticated
            case .networkError:
                postError = .networkError(NSError(domain: "TokenValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Token validation failed due to network error"]))
            case .valid:
                // This shouldn't happen since we checked !isValid above, but handle gracefully
                postError = .unknown(NSError(domain: "TokenValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected validation state"]))
            }
            
            // Log user-friendly error message
            let errorMessage = postError.userMessage(context: context)
            print("👤 Validation failed: \(errorMessage.description)")
            
            return .failure(postError)
        }
        
        print("✅ Token validation successful for tweet posting")
        
        // Attempt to post tweet with automatic token refresh on expiration
        return await performTweetPostWithTokenRefresh(text, retryCount: 0)
    }
    
    /// Attempts to post tweet with automatic token refresh on expiration
    /// - Parameters:
    ///   - text: Tweet content
    ///   - retryCount: Number of retry attempts (prevents infinite loops)
    /// - Returns: Tweet post result
    private func performTweetPostWithTokenRefresh(_ text: String, retryCount: Int) async -> TweetPostResult {
        // Prevent infinite retry loops
        guard retryCount < 2 else {
            return .failure(.notAuthenticated)
        }
        
        // Check network connectivity before attempting API call
        guard networkMonitor.isConnected else {
            print("❌ No network connection available for tweet posting")
            return .failure(.networkError(
                NSError(domain: "NetworkError", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "No internet connection available. Please check your network and try again."
                ])
            ))
        }
        
        do {
            // Get access token
            let accessToken = try await keychainManager.getAccessToken()
            
            // Create API client and set token
            let apiClient = createXAPIClient(operationType: .posting)
            try apiClient.setAccessToken(accessToken)
            
            // Create tweet request
            let tweetRequest = TweetRequest(text: text)
            
            // Post tweet
            let tweetResponse = try await apiClient.postTweet(tweetRequest)
            
            // Record request for rate limiting
            await rateLimitManager.recordRequest()
            
            // Create success result
            let success = TweetPostSuccess(
                tweetId: tweetResponse.data.id,
                text: tweetResponse.data.text
            )
            
            return .success(success)
            
        } catch let error as TweetPostError {
            return .failure(error)
            
        } catch {
            // Convert various error types to TweetPostError
            let postError: TweetPostError
            
            if let xapiError = error as? XAPIError {
                postError = convertXAPIErrorToTweetPostError(xapiError)
                
                // Handle expired access token gracefully
                if case .unauthorized = xapiError {
                    return await handleExpiredTokenDuringPost(text, retryCount: retryCount)
                }
                
            } else if let authError = error as? AuthenticationError {
                postError = .notAuthenticated
            } else {
                postError = .unknown(error)
            }
            
            return .failure(postError)
        }
    }
    
    /// Handles expired access token during API calls by refreshing and retrying
    /// - Parameters:
    ///   - text: Original tweet text to retry posting
    ///   - retryCount: Current retry attempt count
    /// - Returns: Tweet post result after token refresh attempt
    private func handleExpiredTokenDuringPost(_ text: String, retryCount: Int) async -> TweetPostResult {
        print("🔄 Access token expired during API call. Attempting token refresh...")
        
        // Attempt to refresh the token
        let refreshResult = await performTokenRefresh()
        
        switch refreshResult {
        case .success(let tokenResponse):
            print("✅ Token refresh successful. Retrying tweet post...")
            
            // Publish token refresh success event
            eventManager.publish(authenticationEvent: .tokenRefreshCompleted)
            
            // Retry the original post with new token
            return await performTweetPostWithTokenRefresh(text, retryCount: retryCount + 1)
            
        case .failure(let refreshError):
            print("❌ Token refresh failed: \(refreshError)")
            
            // Get error context for better messaging
            let context = getCurrentErrorContext()
            let errorMessage = refreshError.userMessage(context: context)
            print("📝 Error message: \(errorMessage.description)")
            
            // Check if we need full re-authentication
            if case .refreshTokenExpired = refreshError {
                print("🔐 Refresh token expired. Using fallback authentication flow.")
                
                // Use fallback authentication flow instead of simple trigger
                let fallbackResult = await performFallbackAuthentication(reason: "refresh_token_expired", preserveQueuedPosts: true)
                
                switch fallbackResult {
                case .success:
                    // Fallback succeeded, retry the original post
                    return await performTweetPostWithTokenRefresh(text, retryCount: retryCount + 1)
                case .failure:
                    // Fallback requires manual intervention, return user-friendly error
                    let tweetError = TweetPostError.notAuthenticated
                    let tweetErrorMessage = tweetError.userMessage(context: context)
                    print("👤 Manual intervention required: \(tweetErrorMessage.description)")
                    return .failure(.notAuthenticated)
                }
            }
            
            // For other refresh errors, try to convert to appropriate TweetPostError with better messaging
            let postError: TweetPostError
            switch refreshError {
            case .rateLimitExceeded:
                postError = .rateLimitExceeded(rateLimitManager.rateLimitInfo)
            case .networkError(let networkError):
                postError = .networkError(networkError)
            case .serverError(let statusCode, let message):
                postError = .serverError(statusCode, message)
            default:
                postError = .notAuthenticated
            }
            
            // Log user-friendly error message
            let postErrorMessage = postError.userMessage(context: context)
            print("📝 Post error message: \(postErrorMessage.description)")
            
            return .failure(postError)
        }
    }
    
    
    /// Refreshes access token using stored refresh token
    internal func performTokenRefresh() async -> TokenRefreshResult {
        do {
            // Step 1: Get stored refresh token
            let storedRefreshToken = try await keychainManager.getRefreshToken()
            
            // Step 2: Get client ID
            guard let clientId = getClientId() else {
                throw AuthenticationError.invalidCredentials
            }
            
            // Step 3: Create OAuth manager for refresh
            let oauthManager = createOAuthManager(clientId: clientId, redirectUri: "")
            
            // Step 4: Call refresh endpoint
            let tokenResponse = try await oauthManager.refreshAccessToken(refreshToken: storedRefreshToken)
            
            // Step 5: Store new access token
            try await keychainManager.storeAccessToken(tokenResponse.accessToken)
            
            // Step 6: Store new refresh token if provided
            if let newRefreshToken = tokenResponse.refreshToken {
                try await keychainManager.updateRefreshToken(newRefreshToken)
            }
            
            // Step 7: Calculate and store new expiry date
            let expiresIn = tokenResponse.expiresIn ?? 7200 // Default 2 hours
            let newExpiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            try await keychainManager.updateTokenExpiry(newExpiryDate)
            
            // Step 8: Validate new token by testing API call
            let apiClient = createXAPIClient(operationType: .authentication)
            try apiClient.setAccessToken(tokenResponse.accessToken)
            let _ = try await apiClient.getCurrentUser()
            
            return .success(tokenResponse)
            
        } catch let error as OAuthError {
            return .failure(convertOAuthErrorToTokenRefreshError(error))
            
        } catch let error as AuthenticationError {
            return .failure(.authenticationRequired)
            
        } catch {
            return .failure(.unknown(error))
        }
    }
    
    // MARK: - Factory Methods for Phase 1 Components
    
    /// Creates an OAuthManager instance (Phase 1 component)
    private func createOAuthManager(clientId: String, redirectUri: String) -> OAuthManagerProtocol {
        // In real implementation, this would be:
        // return OAuthManager(clientId: clientId, redirectUri: redirectUri)
        
        // For now, return a mock implementation
        return MockOAuthManager(clientId: clientId, redirectUri: redirectUri)
    }
    
    /// Creates an XAPIClient instance (Phase 1 component)
    /// - Parameter operationType: Type of operation to configure appropriate timeouts
    internal func createXAPIClient(operationType: XAPIOperationType = .general) -> XAPIClientProtocol {
        // In real implementation, this would be:
        // return XAPIClient(operationType: operationType)
        
        // For now, return a mock implementation with operation type awareness
        return MockXAPIClient(operationType: operationType)
    }
    
    /// Creates an HTTPServer instance (Phase 1 component)
    private func createHTTPServer() -> HTTPServerProtocol {
        // In real implementation, this would be:
        // return HTTPServer()
        
        // For now, return a mock implementation
        return MockHTTPServer()
    }
    
    // MARK: - Helper Methods
    
    /// Gets current error context for generating appropriate user messages
    /// - Returns: Error context with current authentication state
    private func getCurrentErrorContext() -> AuthenticationErrorMessaging.ErrorContext {
        return AuthenticationErrorMessaging.ErrorContext(
            userDisplayName: currentUser?.displayName,
            lastSuccessfulAuth: UserDefaults.standard.object(forKey: "mercury.auth.last_success") as? Date,
            queuedPostsCount: queuedPostsCount,
            networkStatus: networkMonitor.isConnected ? .connected : .disconnected,
            previousState: authenticationState
        )
    }
    
    /// Gets client ID from environment variables or stored preferences
    private func getClientId() -> String? {
        // Try environment variable first
        if let clientId = ProcessInfo.processInfo.environment["TWITTER_CLIENT_ID"],
           !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Try user defaults
        let userDefaults = UserDefaults.standard
        if let clientId = userDefaults.string(forKey: "mercury.twitter.client_id"),
           !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    /// Converts XAPIError to TweetPostError
    private func convertXAPIErrorToTweetPostError(_ xapiError: XAPIError) -> TweetPostError {
        switch xapiError {
        case .unauthorized:
            return .notAuthenticated
        case .rateLimitExceeded(let retryAfter, let remaining):
            let rateLimitInfo = RateLimitInfo(
                remainingRequests: Int(remaining ?? "0") ?? 0,
                totalRequests: 500,
                resetDate: retryAfter.flatMap { Date().addingTimeInterval(TimeInterval($0) ?? 0) },
                isLimited: true
            )
            return .rateLimitExceeded(rateLimitInfo)
        case .networkError(let underlying):
            return .networkError(underlying)
        case .apiError(let statusCode, let title, let detail, _):
            return .serverError(statusCode, detail ?? title)
        default:
            return .unknown(xapiError)
        }
    }
    
    /// Converts OAuthError to TokenRefreshError
    private func convertOAuthErrorToTokenRefreshError(_ oauthError: OAuthError) -> TokenRefreshError {
        switch oauthError {
        case .accessDenied:
            return .refreshTokenExpired
        case .serverError(let message):
            if message.contains("invalid") || message.contains("refresh") {
                return .refreshTokenExpired
            } else if message.contains("rate limit") {
                return .rateLimitExceeded
            } else {
                return .serverError(500, message)
            }
        case .invalidClientId:
            return .authenticationRequired
        case .tokenExchangeFailed(let statusCode, _):
            switch statusCode {
            case 400, 401, 403:
                return .refreshTokenExpired
            case 429:
                return .rateLimitExceeded
            case 500...599:
                return .serverError(statusCode, "X API server error")
            default:
                return .serverError(statusCode, "Token refresh failed")
            }
        default:
            return .unknown(oauthError)
        }
    }
}

// MARK: - Mock Implementations for Testing

/// Mock OAuth manager for development/testing
private class MockOAuthManager: OAuthManagerProtocol {
    private let clientId: String
    private let redirectUri: String
    
    init(clientId: String, redirectUri: String) {
        self.clientId = clientId
        self.redirectUri = redirectUri
    }
    
    func startAuthorizationFlow(scopes: String) throws -> URL {
        // Return a mock URL for testing
        return URL(string: "https://twitter.com/i/oauth2/authorize?client_id=\(clientId)")!
    }
    
    func exchangeCodeForToken(authorizationCode: String, receivedState: String) async throws -> OAuthTokenResponse {
        // Return a mock token response
        return OAuthTokenResponse(
            accessToken: "mock_access_token_\(UUID().uuidString)",
            tokenType: "bearer",
            expiresIn: 7200,
            refreshToken: "mock_refresh_token_\(UUID().uuidString)",
            scope: "tweet.read tweet.write users.read offline.access"
        )
    }
    
    func refreshAccessToken(refreshToken: String) async throws -> OAuthTokenResponse {
        // Simulate refresh delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Return a mock refreshed token response
        return OAuthTokenResponse(
            accessToken: "mock_refreshed_access_token_\(UUID().uuidString)",
            tokenType: "bearer",
            expiresIn: 7200,
            refreshToken: "mock_refreshed_refresh_token_\(UUID().uuidString)",
            scope: "tweet.read tweet.write users.read offline.access"
        )
    }
    
    func openAuthorizationUrl(_ authUrl: URL) throws {
        // Mock browser opening - in real implementation this would open the browser
        print("Mock: Would open URL in browser: \(authUrl)")
    }
}

/// Mock X API client for development/testing
private class MockXAPIClient: XAPIClientProtocol {
    private var accessToken: String?
    private let operationType: XAPIOperationType
    
    init(operationType: XAPIOperationType = .general) {
        self.operationType = operationType
    }
    
    func setAccessToken(_ token: String) throws {
        self.accessToken = token
    }
    
    func postTweet(_ tweetRequest: TweetRequest) async throws -> TweetResponse {
        guard accessToken != nil else {
            throw XAPIError.missingAccessToken
        }
        
        // Return a mock tweet response
        let tweetData = TweetResponse.TweetData(
            id: "mock_tweet_\(UUID().uuidString)",
            text: tweetRequest.text,
            editHistoryTweetIds: nil
        )
        
        return TweetResponse(data: tweetData)
    }
    
    func getCurrentUser() async throws -> UserResponse {
        guard accessToken != nil else {
            throw XAPIError.missingAccessToken
        }
        
        // Return a mock user response
        let userData = UserResponse.UserData(
            id: "mock_user_123",
            name: "Mock User",
            username: "mockuser"
        )
        
        return UserResponse(data: userData)
    }
}

/// Mock HTTP server for development/testing
private class MockHTTPServer: HTTPServerProtocol {
    func start() async throws -> Int {
        // Return a mock port number
        return 8080
    }
    
    func waitForCallback() async throws -> CallbackResult {
        // Simulate waiting for callback
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Return a mock successful callback
        return CallbackResult(
            authorizationCode: "mock_auth_code_\(UUID().uuidString)",
            state: "mock_state_\(UUID().uuidString)",
            error: nil,
            errorDescription: nil
        )
    }
    
    func stop() async throws {
        // Mock server stop
        print("Mock: HTTP server stopped")
    }
}

// MARK: - Supporting Types

/// OAuth token response from Phase 1
public struct OAuthTokenResponse: Codable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let scope: String?
    
    public init(accessToken: String, tokenType: String, expiresIn: Int?, refreshToken: String?, scope: String?) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
    }
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// HTTP callback result from Phase 1
public struct CallbackResult {
    public let authorizationCode: String?
    public let state: String?
    public let error: String?
    public let errorDescription: String?
    
    public init(authorizationCode: String?, state: String?, error: String?, errorDescription: String?) {
        self.authorizationCode = authorizationCode
        self.state = state
        self.error = error
        self.errorDescription = errorDescription
    }
}

/// OAuth Error from Phase 1 (simplified version)
public enum OAuthError: Error, LocalizedError {
    case accessDenied
    case invalidClientId
    case serverError(String)
    case tokenExchangeFailed(statusCode: Int, message: String?)
    case networkError(Error)
    case invalidResponse
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access denied by user or X API"
        case .invalidClientId:
            return "Invalid client ID"
        case .serverError(let message):
            return "Server error: \(message)"
        case .tokenExchangeFailed(let statusCode, let message):
            return "Token exchange failed (\(statusCode)): \(message ?? "Unknown error")"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from OAuth server"
        case .unknown(let error):
            return "Unknown OAuth error: \(error.localizedDescription)"
        }
    }
}

/// X API Error from Phase 1 (simplified version)
public enum XAPIError: Error, LocalizedError {
    case missingAccessToken
    case unauthorized
    case rateLimitExceeded(retryAfter: String?, remainingRequests: String?)
    case networkError(underlying: Error)
    case apiError(statusCode: Int, title: String?, detail: String?, type: String?)
    
    public var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Access token is required"
        case .unauthorized:
            return "Unauthorized - invalid token"
        case .rateLimitExceeded(let retryAfter, let remaining):
            return "Rate limit exceeded. Retry after: \(retryAfter ?? "unknown"), Remaining: \(remaining ?? "unknown")"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let statusCode, let title, let detail, _):
            return "API error (\(statusCode)): \(title ?? detail ?? "Unknown error")"
        }
    }
}


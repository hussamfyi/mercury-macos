import Foundation

// MARK: - OAuth Token Models

/// OAuth 2.0 token response from X API
/// Represents the successful token exchange response
public struct OAuthTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let scope: String?
    
    /// Initialize OAuth token response
    /// - Parameters:
    ///   - accessToken: The access token for API calls
    ///   - tokenType: Token type (typically "Bearer")
    ///   - expiresIn: Token expiration time in seconds
    ///   - refreshToken: Optional refresh token for token renewal
    ///   - scope: Granted OAuth scopes
    public init(accessToken: String, tokenType: String, expiresIn: Int? = nil, refreshToken: String? = nil, scope: String? = nil) {
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

/// OAuth 2.0 authorization request parameters
/// Used for building authorization URLs
public struct OAuthAuthorizationRequest: Sendable {
    public let clientId: String
    public let redirectUri: String
    public let scope: String
    public let state: String
    public let codeChallenge: String
    public let codeChallengeMethod: String
    
    /// Initialize OAuth authorization request
    /// - Parameters:
    ///   - clientId: X API client ID
    ///   - redirectUri: Callback URL for authorization
    ///   - scope: Requested OAuth scopes
    ///   - state: CSRF protection state parameter
    ///   - codeChallenge: PKCE code challenge
    ///   - codeChallengeMethod: PKCE challenge method (S256)
    public init(clientId: String, redirectUri: String, scope: String, state: String, codeChallenge: String, codeChallengeMethod: String = "S256") {
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.scope = scope
        self.state = state
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
    }
}

/// OAuth 2.0 token exchange request
/// Used for exchanging authorization code for access token
public struct OAuthTokenRequest: Codable, Sendable {
    public let grantType: String
    public let clientId: String
    public let code: String
    public let redirectUri: String
    public let codeVerifier: String
    
    /// Initialize OAuth token exchange request
    /// - Parameters:
    ///   - clientId: X API client ID
    ///   - authorizationCode: Authorization code from callback
    ///   - redirectUri: Callback URL (must match authorization request)
    ///   - codeVerifier: PKCE code verifier
    public init(clientId: String, authorizationCode: String, redirectUri: String, codeVerifier: String) {
        self.grantType = "authorization_code"
        self.clientId = clientId
        self.code = authorizationCode
        self.redirectUri = redirectUri
        self.codeVerifier = codeVerifier
    }
    
    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientId = "client_id"
        case code
        case redirectUri = "redirect_uri"
        case codeVerifier = "code_verifier"
    }
}

/// OAuth 2.0 refresh token request
/// Used for refreshing access tokens using refresh token
public struct OAuthRefreshTokenRequest: Codable, Sendable {
    public let grantType: String
    public let refreshToken: String
    public let clientId: String
    
    /// Initialize OAuth refresh token request
    /// - Parameters:
    ///   - refreshToken: The refresh token to exchange
    ///   - clientId: X API client ID
    public init(refreshToken: String, clientId: String) {
        self.grantType = "refresh_token"
        self.refreshToken = refreshToken
        self.clientId = clientId
    }
    
    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
        case clientId = "client_id"
    }
}

// MARK: - OAuth Error Models

/// OAuth 2.0 specific errors
/// Covers all OAuth flow error scenarios
public enum OAuthError: Error, LocalizedError {
    case pkceGenerationFailed
    case invalidAuthorizationUrl
    case stateMismatch
    case missingCodeVerifier
    case invalidResponse
    case tokenExchangeFailed(statusCode: Int, data: Data)
    case browserLaunchFailed
    case unsupportedPlatform
    case invalidClientId
    case invalidRedirectUri
    case accessDenied
    case serverError(String)
    
    public var errorDescription: String? {
        switch self {
        case .pkceGenerationFailed:
            return "Failed to generate PKCE code verifier"
        case .invalidAuthorizationUrl:
            return "Unable to construct valid authorization URL"
        case .stateMismatch:
            return "State parameter mismatch - possible CSRF attack"
        case .missingCodeVerifier:
            return "Code verifier not found - authorization flow not started"
        case .invalidResponse:
            return "Invalid response from OAuth server"
        case .tokenExchangeFailed(let statusCode, _):
            return "Token exchange failed with status code: \(statusCode)"
        case .browserLaunchFailed:
            return "Failed to open authorization URL in browser"
        case .unsupportedPlatform:
            return "Platform not supported for browser launch"
        case .invalidClientId:
            return "Invalid client ID - check your X API credentials"
        case .invalidRedirectUri:
            return "Invalid redirect URI - must match X Developer Portal configuration"
        case .accessDenied:
            return "User denied authorization request"
        case .serverError(let message):
            return "OAuth server error: \(message)"
        }
    }
}

// MARK: - OAuth Callback Models

/// OAuth callback response from redirect URL
/// Represents the parsed callback parameters
public struct OAuthCallbackResponse: Sendable {
    public let authorizationCode: String?
    public let state: String?
    public let error: String?
    public let errorDescription: String?
    
    /// Initialize OAuth callback response
    /// - Parameters:
    ///   - authorizationCode: Authorization code on success
    ///   - state: State parameter for validation
    ///   - error: Error code on failure
    ///   - errorDescription: Human-readable error description
    public init(authorizationCode: String? = nil, state: String? = nil, error: String? = nil, errorDescription: String? = nil) {
        self.authorizationCode = authorizationCode
        self.state = state
        self.error = error
        self.errorDescription = errorDescription
    }
    
    /// Check if callback represents a successful authorization
    public var isSuccess: Bool {
        return authorizationCode != nil && error == nil
    }
    
    /// Check if callback represents an error
    public var isError: Bool {
        return error != nil
    }
}
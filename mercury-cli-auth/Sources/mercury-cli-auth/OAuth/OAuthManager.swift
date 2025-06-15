import Foundation
#if os(macOS)
import AppKit
#endif

/// OAuth 2.0 manager for X API authentication using PKCE flow
/// Coordinates the complete OAuth flow including browser launch and token exchange
public class OAuthManager {
    
    // MARK: - Properties
    
    private let clientId: String
    private let redirectUri: String
    private let baseAuthUrl = "https://twitter.com/i/oauth2/authorize"
    private let tokenUrl = "https://api.twitter.com/2/oauth2/token"
    
    private var codeVerifier: String?
    private var state: String?
    
    // MARK: - Network Configuration
    
    /// URLSession configured for authentication operations (30s timeout per PRD)
    private lazy var authSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0  // PRD: 30s for auth operations
        configuration.timeoutIntervalForResource = 60.0 // 2x request timeout
        return URLSession(configuration: configuration)
    }()
    
    // MARK: - Initialization
    
    /// Initialize OAuth manager with X API credentials
    /// - Parameters:
    ///   - clientId: X API Client ID from Developer Portal
    ///   - redirectUri: Callback URL (should match server port)
    public init(clientId: String, redirectUri: String) {
        self.clientId = clientId
        self.redirectUri = redirectUri
    }
    
    // MARK: - OAuth Flow Management
    
    /// Start the OAuth 2.0 authorization flow
    /// - Parameter scopes: OAuth scopes to request (default: "tweet.read tweet.write users.read")
    /// - Returns: Authorization URL to open in browser
    /// - Throws: OAuthError if URL generation fails
    public func startAuthorizationFlow(scopes: String = "tweet.read tweet.write users.read") throws -> URL {
        // Generate PKCE parameters
        self.codeVerifier = PKCEGenerator.generateCodeVerifier()
        self.state = generateState()
        
        guard let codeVerifier = self.codeVerifier else {
            throw OAuthError.pkceGenerationFailed
        }
        
        let codeChallenge = PKCEGenerator.generateCodeChallenge(from: codeVerifier)
        
        // Build authorization URL
        var components = URLComponents(string: baseAuthUrl)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authUrl = components.url else {
            throw OAuthError.invalidAuthorizationUrl
        }
        
        return authUrl
    }
    
    /// Exchange authorization code for access token
    /// - Parameters:
    ///   - authorizationCode: Code received from callback
    ///   - receivedState: State parameter from callback for validation
    /// - Returns: OAuth token response
    /// - Throws: OAuthError for various failure scenarios
    public func exchangeCodeForToken(authorizationCode: String, receivedState: String) async throws -> OAuthTokenResponse {
        // Validate state parameter
        guard let expectedState = self.state, expectedState == receivedState else {
            throw OAuthError.stateMismatch
        }
        
        guard let codeVerifier = self.codeVerifier else {
            throw OAuthError.missingCodeVerifier
        }
        
        // Prepare token exchange request
        let requestBody = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": authorizationCode,
            "redirect_uri": redirectUri,
            "code_verifier": codeVerifier
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: URL(string: tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        // Execute token exchange with PRD-specified timeout (30s for auth)
        let (data, response) = try await authSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw OAuthError.tokenExchangeFailed(statusCode: httpResponse.statusCode, data: data)
        }
        
        // Parse token response
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        
        // Clear sensitive data after successful exchange
        self.codeVerifier = nil
        self.state = nil
        
        return tokenResponse
    }
    
    /// Refresh access token using refresh token
    /// - Parameter refreshToken: Valid refresh token from previous authentication
    /// - Returns: New OAuth token response with updated tokens
    /// - Throws: OAuthError for various failure scenarios
    public func refreshAccessToken(refreshToken: String) async throws -> OAuthTokenResponse {
        // Prepare refresh token request
        let requestBody = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refreshToken
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: URL(string: tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        // Execute refresh token exchange with PRD-specified timeout (30s for auth)
        let (data, response) = try await authSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }
        
        // Handle different HTTP status codes
        switch httpResponse.statusCode {
        case 200:
            // Success - parse token response
            let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            return tokenResponse
            
        case 400:
            // Bad request - likely invalid refresh token
            throw OAuthError.serverError("Invalid refresh token")
            
        case 401:
            // Unauthorized - refresh token expired
            throw OAuthError.accessDenied
            
        case 403:
            // Forbidden - client not authorized
            throw OAuthError.invalidClientId
            
        case 429:
            // Rate limited
            throw OAuthError.serverError("Rate limit exceeded")
            
        case 500...599:
            // Server error
            throw OAuthError.serverError("X API server error")
            
        default:
            throw OAuthError.tokenExchangeFailed(statusCode: httpResponse.statusCode, data: data)
        }
    }
    
    /// Open authorization URL in default browser
    /// - Parameter authUrl: URL to open
    /// - Throws: OAuthError if browser launch fails
    public func openAuthorizationUrl(_ authUrl: URL) throws {
        #if os(macOS)
        if !NSWorkspace.shared.open(authUrl) {
            throw OAuthError.browserLaunchFailed
        }
        #else
        throw OAuthError.unsupportedPlatform
        #endif
    }
    
    // MARK: - Private Methods
    
    /// Generate a cryptographically secure state parameter
    /// - Returns: Random state string for CSRF protection
    private func generateState() -> String {
        let randomBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let data = Data(randomBytes)
        return data.base64URLEncodedString()
    }
}

// Note: OAuth models (OAuthTokenResponse, OAuthError, etc.) 
// are defined in Models/OAuthModels.swift to avoid duplication
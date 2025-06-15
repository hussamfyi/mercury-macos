import Foundation

@main
struct MercuryAuthCLI {
    static func main() async {
        print("Mercury CLI Auth Tool")
        print("===================")
        print("OAuth 2.0 + PKCE Flow Validation for X API")
        print()
        
        // Get Client ID from environment variable or user input
        let clientId = getClientId()
        guard !clientId.isEmpty else {
            print("❌ Error: X API Client ID is required")
            print("Set the TWITTER_CLIENT_ID environment variable or provide it when prompted.")
            return
        }
        
        do {
            // Step 1: Test PKCE Generator
            print("🔐 Testing PKCE Generation...")
            let codeVerifier = PKCEGenerator.generateCodeVerifier()
            let codeChallenge = PKCEGenerator.generateCodeChallenge(from: codeVerifier)
            let isValid = PKCEGenerator.isValidCodeVerifier(codeVerifier)
            
            print("   ✅ Code Verifier: \(codeVerifier.prefix(20))... (\(codeVerifier.count) chars)")
            print("   ✅ Code Challenge: \(codeChallenge.prefix(20))...")
            print("   ✅ Validation: \(isValid ? "PASSED" : "FAILED")")
            print()
            
            // Step 2: Start HTTP Server
            print("🌐 Starting local HTTP server...")
            let httpServer = HTTPServer()
            let serverPort = try await httpServer.start()
            let redirectUri = "http://localhost:\(serverPort)/callback"
            print("   ✅ Server running on port \(serverPort)")
            print()
            
            // Step 3: Initialize OAuth Manager
            print("🔑 Initializing OAuth flow...")
            let oauthManager = OAuthManager(clientId: clientId, redirectUri: redirectUri)
            
            // Step 4: Generate Authorization URL and open browser
            let authUrl = try oauthManager.startAuthorizationFlow()
            print("   ✅ Authorization URL generated")
            print("   📱 Opening browser for authentication...")
            try oauthManager.openAuthorizationUrl(authUrl)
            print()
            
            // Step 5: Wait for callback
            print("⏳ Waiting for OAuth callback...")
            print("   Please complete the authorization in your browser.")
            
            let callbackResult = try await httpServer.waitForCallback()
            try await httpServer.stop()
            
            guard let authCode = callbackResult.authorizationCode,
                  let state = callbackResult.state else {
                print("❌ Authorization failed: \(callbackResult.error ?? "Unknown error")")
                if let errorDesc = callbackResult.errorDescription {
                    print("   Description: \(errorDesc)")
                }
                return
            }
            
            print("   ✅ Authorization code received")
            print()
            
            // Step 6: Exchange code for token
            print("🎫 Exchanging authorization code for access token...")
            let tokenResponse = try await oauthManager.exchangeCodeForToken(
                authorizationCode: authCode,
                receivedState: state
            )
            print("   ✅ Access token obtained")
            print("   Token Type: \(tokenResponse.tokenType)")
            if let expiresIn = tokenResponse.expiresIn {
                print("   Expires In: \(expiresIn) seconds")
            }
            print()
            
            // Step 7: Initialize X API Client
            print("🐦 Initializing X API client...")
            let apiClient = try XAPIClient(validatedAccessToken: tokenResponse.accessToken)
            print("   ✅ API client initialized")
            print()
            
            // Step 8: Validate token by getting current user
            print("👤 Validating token with /2/users/me...")
            let userResponse = try await apiClient.getCurrentUser()
            print("   ✅ Token validation successful")
            print("   User: @\(userResponse.data.username) (\(userResponse.data.name))")
            print("   ID: \(userResponse.data.id)")
            print()
            
            // Step 9: Post test tweet
            print("📝 Posting test tweet: \"claude code is cracked\"...")
            let tweetRequest = TweetRequest(text: "claude code is cracked")
            let tweetResponse = try await apiClient.postTweet(tweetRequest)
            print("   ✅ Tweet posted successfully!")
            print("   Tweet ID: \(tweetResponse.data.id)")
            print("   Content: \"\(tweetResponse.data.text)\"")
            print()
            
            // Success summary
            print("🎉 All tests completed successfully!")
            print("✅ PKCE generation and validation")
            print("✅ OAuth 2.0 authorization flow")
            print("✅ Token exchange")
            print("✅ Token validation")
            print("✅ Tweet posting")
            
        } catch let error as OAuthError {
            print("❌ OAuth Error: \(error.localizedDescription)")
        } catch let error as XAPIError {
            print("❌ X API Error: \(error.localizedDescription)")
        } catch let error as HTTPServerError {
            print("❌ HTTP Server Error: \(error.localizedDescription)")
        } catch {
            print("❌ Unexpected Error: \(error.localizedDescription)")
        }
    }
    
    /// Get Client ID from environment variable or user input
    private static func getClientId() -> String {
        // Try environment variable first
        if let clientId = ProcessInfo.processInfo.environment["TWITTER_CLIENT_ID"],
           !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Prompt user for input
        print("Enter your X API Client ID:")
        print("(You can also set the TWITTER_CLIENT_ID environment variable)")
        print("Client ID: ", terminator: "")
        
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !input.isEmpty {
            return input
        }
        
        return ""
    }
}

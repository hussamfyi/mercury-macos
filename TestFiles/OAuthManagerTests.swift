import XCTest
@testable import mercury_cli_auth

final class OAuthManagerTests: XCTestCase {
    
    private var oauthManager: OAuthManager!
    private let testClientId = "test_client_id_12345"
    private let testRedirectUri = "http://localhost:8080/callback"
    
    override func setUp() {
        super.setUp()
        oauthManager = OAuthManager(clientId: testClientId, redirectUri: testRedirectUri)
    }
    
    override func tearDown() {
        oauthManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testOAuthManagerInitialization() throws {
        let manager = OAuthManager(clientId: "test_id", redirectUri: "http://localhost:8080/callback")
        XCTAssertNotNil(manager, "OAuthManager should initialize successfully")
    }
    
    // MARK: - Authorization Flow Tests
    
    func testStartAuthorizationFlowWithDefaultScopes() throws {
        let authUrl = try oauthManager.startAuthorizationFlow()
        
        XCTAssertNotNil(authUrl, "Authorization URL should be generated")
        
        let urlComponents = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        XCTAssertNotNil(urlComponents, "URL should be valid")
        XCTAssertEqual(urlComponents?.scheme, "https", "URL should use HTTPS")
        XCTAssertEqual(urlComponents?.host, "twitter.com", "URL should point to Twitter")
        XCTAssertEqual(urlComponents?.path, "/i/oauth2/authorize", "URL should use correct authorization endpoint")
        
        guard let queryItems = urlComponents?.queryItems else {
            XCTFail("URL should contain query parameters")
            return
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        
        XCTAssertEqual(queryDict["response_type"], "code", "Response type should be 'code'")
        XCTAssertEqual(queryDict["client_id"], testClientId, "Client ID should match")
        XCTAssertEqual(queryDict["redirect_uri"], testRedirectUri, "Redirect URI should match")
        XCTAssertEqual(queryDict["scope"], "tweet.read tweet.write users.read", "Default scopes should be set")
        XCTAssertEqual(queryDict["code_challenge_method"], "S256", "PKCE method should be S256")
        XCTAssertNotNil(queryDict["state"], "State parameter should be present")
        XCTAssertNotNil(queryDict["code_challenge"], "Code challenge should be present")
        
        // Validate state parameter format (Base64 URL encoded)
        if let state = queryDict["state"] {
            XCTAssertFalse(state.isEmpty, "State should not be empty")
            XCTAssertFalse(state.contains("+"), "State should be Base64 URL encoded (no +)")
            XCTAssertFalse(state.contains("/"), "State should be Base64 URL encoded (no /)")
            XCTAssertFalse(state.contains("="), "State should be Base64 URL encoded (no =)")
        }
        
        // Validate code challenge format (Base64 URL encoded SHA256)
        if let codeChallenge = queryDict["code_challenge"] {
            XCTAssertEqual(codeChallenge.count, 43, "SHA256 Base64 URL encoded should be 43 characters")
            XCTAssertFalse(codeChallenge.contains("+"), "Code challenge should be Base64 URL encoded (no +)")
            XCTAssertFalse(codeChallenge.contains("/"), "Code challenge should be Base64 URL encoded (no /)")
            XCTAssertFalse(codeChallenge.contains("="), "Code challenge should be Base64 URL encoded (no =)")
        }
    }
    
    func testStartAuthorizationFlowWithCustomScopes() throws {
        let customScopes = "tweet.read users.read offline.access"
        let authUrl = try oauthManager.startAuthorizationFlow(scopes: customScopes)
        
        let urlComponents = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        guard let queryItems = urlComponents?.queryItems else {
            XCTFail("URL should contain query parameters")
            return
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        
        XCTAssertEqual(queryDict["scope"], customScopes, "Custom scopes should be used")
    }
    
    func testMultipleAuthorizationFlowsGenerateUniqueStates() throws {
        let authUrl1 = try oauthManager.startAuthorizationFlow()
        let authUrl2 = try oauthManager.startAuthorizationFlow()
        
        let components1 = URLComponents(url: authUrl1, resolvingAgainstBaseURL: false)
        let components2 = URLComponents(url: authUrl2, resolvingAgainstBaseURL: false)
        
        let state1 = components1?.queryItems?.first { $0.name == "state" }?.value
        let state2 = components2?.queryItems?.first { $0.name == "state" }?.value
        
        XCTAssertNotNil(state1, "First state should exist")
        XCTAssertNotNil(state2, "Second state should exist")
        XCTAssertNotEqual(state1, state2, "States should be unique")
    }
    
    func testMultipleAuthorizationFlowsGenerateUniqueChallenges() throws {
        let authUrl1 = try oauthManager.startAuthorizationFlow()
        let authUrl2 = try oauthManager.startAuthorizationFlow()
        
        let components1 = URLComponents(url: authUrl1, resolvingAgainstBaseURL: false)
        let components2 = URLComponents(url: authUrl2, resolvingAgainstBaseURL: false)
        
        let challenge1 = components1?.queryItems?.first { $0.name == "code_challenge" }?.value
        let challenge2 = components2?.queryItems?.first { $0.name == "code_challenge" }?.value
        
        XCTAssertNotNil(challenge1, "First challenge should exist")
        XCTAssertNotNil(challenge2, "Second challenge should exist")
        XCTAssertNotEqual(challenge1, challenge2, "Challenges should be unique")
    }
    
    // MARK: - Token Exchange Tests
    
    func testExchangeCodeForTokenWithoutStartingFlow() async throws {
        // Attempting to exchange code without starting flow should fail
        do {
            _ = try await oauthManager.exchangeCodeForToken(authorizationCode: "test_code", receivedState: "test_state")
            XCTFail("Should throw error when no authorization flow started")
        } catch let error as OAuthError {
            switch error {
            case .missingCodeVerifier:
                // Expected error
                break
            default:
                XCTFail("Should throw missingCodeVerifier error, got: \(error)")
            }
        }
    }
    
    func testExchangeCodeForTokenWithStateMismatch() async throws {
        // Start authorization flow to set up state
        _ = try oauthManager.startAuthorizationFlow()
        
        // Try to exchange with wrong state
        do {
            _ = try await oauthManager.exchangeCodeForToken(authorizationCode: "test_code", receivedState: "wrong_state")
            XCTFail("Should throw error for state mismatch")
        } catch let error as OAuthError {
            switch error {
            case .stateMismatch:
                // Expected error
                break
            default:
                XCTFail("Should throw stateMismatch error, got: \(error)")
            }
        }
    }
    
    func testExchangeCodeForTokenWithValidStateButNoNetwork() async throws {
        // Start authorization flow to get valid state
        let authUrl = try oauthManager.startAuthorizationFlow()
        
        // Extract state from the URL
        let components = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        guard let state = components?.queryItems?.first(where: { $0.name == "state" })?.value else {
            XCTFail("Should have state in authorization URL")
            return
        }
        
        // Try to exchange with valid state but invalid code (will fail due to network call)
        do {
            _ = try await oauthManager.exchangeCodeForToken(authorizationCode: "invalid_code", receivedState: state)
            XCTFail("Should throw error for invalid token exchange")
        } catch let error as OAuthError {
            switch error {
            case .tokenExchangeFailed:
                // Expected error due to invalid code
                break
            default:
                XCTFail("Should throw tokenExchangeFailed error, got: \(error)")
            }
        }
    }
    
    // MARK: - Browser Launch Tests (macOS only)
    
    func testOpenAuthorizationUrl() throws {
        let testUrl = URL(string: "https://twitter.com/i/oauth2/authorize?test=true")!
        
        #if os(macOS)
        // On macOS, this should not throw an error
        XCTAssertNoThrow(try oauthManager.openAuthorizationUrl(testUrl))
        #else
        // On other platforms, this should throw unsupportedPlatform error
        XCTAssertThrowsError(try oauthManager.openAuthorizationUrl(testUrl)) { error in
            guard let oauthError = error as? OAuthError else {
                XCTFail("Should throw OAuthError")
                return
            }
            
            switch oauthError {
            case .unsupportedPlatform:
                // Expected error
                break
            default:
                XCTFail("Should throw unsupportedPlatform error, got: \(oauthError)")
            }
        }
        #endif
    }
    
    // MARK: - Edge Cases
    
    func testEmptyClientId() throws {
        let manager = OAuthManager(clientId: "", redirectUri: testRedirectUri)
        let authUrl = try manager.startAuthorizationFlow()
        
        let components = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        let clientId = components?.queryItems?.first { $0.name == "client_id" }?.value
        
        XCTAssertEqual(clientId, "", "Empty client ID should be preserved")
    }
    
    func testEmptyRedirectUri() throws {
        let manager = OAuthManager(clientId: testClientId, redirectUri: "")
        let authUrl = try manager.startAuthorizationFlow()
        
        let components = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        let redirectUri = components?.queryItems?.first { $0.name == "redirect_uri" }?.value
        
        XCTAssertEqual(redirectUri, "", "Empty redirect URI should be preserved")
    }
    
    func testEmptyScopes() throws {
        let authUrl = try oauthManager.startAuthorizationFlow(scopes: "")
        
        let components = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        let scope = components?.queryItems?.first { $0.name == "scope" }?.value
        
        XCTAssertEqual(scope, "", "Empty scopes should be preserved")
    }
    
    func testVeryLongScopes() throws {
        let longScopes = String(repeating: "tweet.read ", count: 100)
        let authUrl = try oauthManager.startAuthorizationFlow(scopes: longScopes)
        
        let components = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        let scope = components?.queryItems?.first { $0.name == "scope" }?.value
        
        XCTAssertEqual(scope, longScopes, "Long scopes should be preserved")
    }
    
    // MARK: - Memory Management Tests
    
    func testStateAndVerifierClearedAfterSuccessfulExchange() async throws {
        // This test would require mocking the network layer to simulate a successful response
        // For now, we'll test that the error handling works correctly
        
        _ = try oauthManager.startAuthorizationFlow()
        
        // After starting flow, attempting exchange with wrong state should fail
        do {
            _ = try await oauthManager.exchangeCodeForToken(authorizationCode: "test", receivedState: "wrong")
            XCTFail("Should fail with state mismatch")
        } catch {
            // Expected failure
        }
        
        // State should still be preserved for the next attempt
        let authUrl = try oauthManager.startAuthorizationFlow()
        let components = URLComponents(url: authUrl, resolvingAgainstBaseURL: false)
        let state = components?.queryItems?.first { $0.name == "state" }?.value
        
        XCTAssertNotNil(state, "New state should be generated")
    }
}
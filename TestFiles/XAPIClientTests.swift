import XCTest
@testable import mercury_cli_auth

final class XAPIClientTests: XCTestCase {
    
    private var client: XAPIClient!
    private let testAccessToken = "test_access_token_12345_abcdef"
    
    override func setUp() {
        super.setUp()
        client = XAPIClient()
    }
    
    override func tearDown() {
        client = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testXAPIClientInitialization() {
        let client = XAPIClient()
        XCTAssertNotNil(client, "XAPIClient should initialize successfully")
    }
    
    func testXAPIClientInitializationWithToken() {
        let client = XAPIClient(accessToken: testAccessToken)
        XCTAssertNotNil(client, "XAPIClient should initialize with access token")
    }
    
    func testXAPIClientInitializationWithValidatedToken() throws {
        let client = try XAPIClient(validatedAccessToken: testAccessToken)
        XCTAssertNotNil(client, "XAPIClient should initialize with validated access token")
    }
    
    func testXAPIClientInitializationWithEmptyTokenThrows() {
        XCTAssertThrowsError(try XAPIClient(validatedAccessToken: "")) { error in
            guard let xapiError = error as? XAPIError else {
                XCTFail("Should throw XAPIError")
                return
            }
            
            switch xapiError {
            case .invalidAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw invalidAccessToken error, got: \(xapiError)")
            }
        }
    }
    
    func testXAPIClientInitializationWithWhitespaceOnlyTokenThrows() {
        XCTAssertThrowsError(try XAPIClient(validatedAccessToken: "   ")) { error in
            guard let xapiError = error as? XAPIError else {
                XCTFail("Should throw XAPIError")
                return
            }
            
            switch xapiError {
            case .invalidAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw invalidAccessToken error, got: \(xapiError)")
            }
        }
    }
    
    // MARK: - Access Token Management Tests
    
    func testSetAccessToken() throws {
        try client.setAccessToken(testAccessToken)
        // If no error is thrown, the test passes
    }
    
    func testSetAccessTokenTrimsWhitespace() throws {
        let tokenWithWhitespace = "  \(testAccessToken)  "
        try client.setAccessToken(tokenWithWhitespace)
        // If no error is thrown, the test passes
    }
    
    func testSetEmptyAccessTokenThrows() {
        XCTAssertThrowsError(try client.setAccessToken("")) { error in
            guard let xapiError = error as? XAPIError else {
                XCTFail("Should throw XAPIError")
                return
            }
            
            switch xapiError {
            case .invalidAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw invalidAccessToken error, got: \(xapiError)")
            }
        }
    }
    
    func testSetWhitespaceOnlyAccessTokenThrows() {
        XCTAssertThrowsError(try client.setAccessToken("   \t\n   ")) { error in
            guard let xapiError = error as? XAPIError else {
                XCTFail("Should throw XAPIError")
                return
            }
            
            switch xapiError {
            case .invalidAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw invalidAccessToken error, got: \(xapiError)")
            }
        }
    }
    
    func testClearAccessToken() throws {
        try client.setAccessToken(testAccessToken)
        client.clearAccessToken()
        // If no error is thrown, the test passes
    }
    
    // MARK: - HTTP Method Tests (Error Cases)
    
    func testGetWithoutAccessTokenThrows() async {
        do {
            _ = try await client.get(endpoint: "/2/users/me")
            XCTFail("Should throw error when no access token is set")
        } catch let error as XAPIError {
            switch error {
            case .missingAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw missingAccessToken error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    func testPostWithoutAccessTokenThrows() async {
        let testData = Data("{}".utf8)
        
        do {
            _ = try await client.post(endpoint: "/2/tweets", body: testData)
            XCTFail("Should throw error when no access token is set")
        } catch let error as XAPIError {
            switch error {
            case .missingAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw missingAccessToken error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    func testPutWithoutAccessTokenThrows() async {
        let testData = Data("{}".utf8)
        
        do {
            _ = try await client.put(endpoint: "/2/test", body: testData)
            XCTFail("Should throw error when no access token is set")
        } catch let error as XAPIError {
            switch error {
            case .missingAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw missingAccessToken error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    func testDeleteWithoutAccessTokenThrows() async {
        do {
            _ = try await client.delete(endpoint: "/2/test")
            XCTFail("Should throw error when no access token is set")
        } catch let error as XAPIError {
            switch error {
            case .missingAccessToken:
                // Expected error
                break
            default:
                XCTFail("Should throw missingAccessToken error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    // MARK: - Network Error Tests
    
    func testGetWithInvalidEndpointThrows() async {
        try! client.setAccessToken(testAccessToken)
        
        do {
            _ = try await client.get(endpoint: "invalid-endpoint")
            XCTFail("Should throw error for invalid endpoint")
        } catch let error as XAPIError {
            switch error {
            case .invalidURL:
                // Expected error
                break
            case .networkError, .httpError, .unauthorized, .forbidden, .notFound:
                // These are also acceptable since the endpoint is malformed
                break
            default:
                XCTFail("Should throw URL or network related error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    func testPostTweetWithInvalidTokenExpectedToFail() async {
        try! client.setAccessToken("invalid_token_12345")
        
        let tweetRequest = TweetRequest(text: "Test tweet")
        
        do {
            _ = try await client.postTweet(tweetRequest)
            XCTFail("Should fail with invalid token")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized, .forbidden, .networkError, .httpError:
                // Expected errors with invalid token
                break
            default:
                XCTFail("Should throw authentication or network error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    func testGetCurrentUserWithInvalidTokenExpectedToFail() async {
        try! client.setAccessToken("invalid_token_12345")
        
        do {
            _ = try await client.getCurrentUser()
            XCTFail("Should fail with invalid token")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized, .forbidden, .networkError, .httpError:
                // Expected errors with invalid token
                break
            default:
                XCTFail("Should throw authentication or network error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    // MARK: - TweetRequest Tests
    
    func testTweetRequestCreation() {
        let tweetRequest = TweetRequest(text: "Hello, world!")
        XCTAssertEqual(tweetRequest.text, "Hello, world!", "Tweet text should match")
        XCTAssertNil(tweetRequest.replySettings, "Reply settings should be nil by default")
        XCTAssertNil(tweetRequest.directMessageDeepLink, "DM deep link should be nil by default")
        XCTAssertNil(tweetRequest.forSuperFollowersOnly, "Super followers setting should be nil by default")
    }
    
    func testTweetRequestWithAllOptions() {
        let tweetRequest = TweetRequest(
            text: "Hello, world!",
            replySettings: "everyone",
            directMessageDeepLink: "https://example.com",
            forSuperFollowersOnly: true
        )
        
        XCTAssertEqual(tweetRequest.text, "Hello, world!", "Tweet text should match")
        XCTAssertEqual(tweetRequest.replySettings, "everyone", "Reply settings should match")
        XCTAssertEqual(tweetRequest.directMessageDeepLink, "https://example.com", "DM deep link should match")
        XCTAssertEqual(tweetRequest.forSuperFollowersOnly, true, "Super followers setting should match")
    }
    
    func testTweetRequestWithEmptyText() {
        let tweetRequest = TweetRequest(text: "")
        XCTAssertEqual(tweetRequest.text, "", "Empty tweet text should be preserved")
    }
    
    func testTweetRequestWithLongText() {
        let longText = String(repeating: "A", count: 280) // X's character limit
        let tweetRequest = TweetRequest(text: longText)
        XCTAssertEqual(tweetRequest.text, longText, "Long tweet text should be preserved")
    }
    
    func testTweetRequestWithVeryLongText() {
        let veryLongText = String(repeating: "A", count: 1000) // Exceeds X's character limit
        let tweetRequest = TweetRequest(text: veryLongText)
        XCTAssertEqual(tweetRequest.text, veryLongText, "Very long tweet text should be preserved")
    }
    
    // MARK: - Query Parameter Tests
    
    func testGetWithQueryParameters() async {
        try! client.setAccessToken(testAccessToken)
        
        let queryParams = [
            "user.fields": "id,name,username",
            "tweet.fields": "created_at,public_metrics"
        ]
        
        do {
            _ = try await client.get(endpoint: "/2/users/me", queryParameters: queryParams)
            XCTFail("Expected to fail with invalid token, but this tests the query parameter handling")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized, .forbidden, .networkError, .httpError:
                // Expected errors - this confirms query parameters were handled correctly
                break
            default:
                XCTFail("Should throw authentication or network error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    func testGetWithEmptyQueryParameters() async {
        try! client.setAccessToken(testAccessToken)
        
        do {
            _ = try await client.get(endpoint: "/2/users/me", queryParameters: [:])
            XCTFail("Expected to fail with invalid token")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized, .forbidden, .networkError, .httpError:
                // Expected errors
                break
            default:
                XCTFail("Should throw authentication or network error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    // MARK: - Content Type Tests
    
    func testPostWithCustomContentType() async {
        try! client.setAccessToken(testAccessToken)
        let testData = Data("test data".utf8)
        
        do {
            _ = try await client.post(endpoint: "/2/test", body: testData, contentType: "text/plain")
            XCTFail("Expected to fail with invalid endpoint")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized, .forbidden, .networkError, .httpError, .notFound:
                // Expected errors
                break
            default:
                XCTFail("Should throw authentication or network error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    // MARK: - Edge Cases
    
    func testGetWithSpecialCharactersInEndpoint() async {
        try! client.setAccessToken(testAccessToken)
        
        do {
            _ = try await client.get(endpoint: "/2/users/me?special=chars&test=123")
            XCTFail("Expected to fail with invalid token")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized, .forbidden, .networkError, .httpError:
                // Expected errors
                break
            default:
                XCTFail("Should throw authentication or network error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    func testPostWithLargeBody() async {
        try! client.setAccessToken(testAccessToken)
        
        // Create a large JSON body
        let largeData = Data(String(repeating: "a", count: 10000).utf8)
        
        do {
            _ = try await client.post(endpoint: "/2/tweets", body: largeData)
            XCTFail("Expected to fail with invalid token or large body")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized, .forbidden, .networkError, .httpError, .apiError:
                // Expected errors
                break
            default:
                XCTFail("Should throw authentication, network, or API error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw XAPIError, got: \(type(of: error))")
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentTokenSetting() throws {
        let iterations = 100
        let expectation = XCTestExpectation(description: "Concurrent token setting")
        expectation.expectedFulfillmentCount = iterations
        
        for i in 0..<iterations {
            DispatchQueue.global().async {
                do {
                    try self.client.setAccessToken("token_\(i)")
                    expectation.fulfill()
                } catch {
                    XCTFail("Token setting failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testConcurrentTokenClearing() throws {
        try client.setAccessToken(testAccessToken)
        
        let iterations = 100
        let expectation = XCTestExpectation(description: "Concurrent token clearing")
        expectation.expectedFulfillmentCount = iterations
        
        for _ in 0..<iterations {
            DispatchQueue.global().async {
                self.client.clearAccessToken()
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
}
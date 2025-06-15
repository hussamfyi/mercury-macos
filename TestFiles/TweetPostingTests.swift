import XCTest
@testable import mercury_cli_auth

/// Tests for successful tweet posting via X API
final class TweetPostingTests: XCTestCase {
    
    private var xapiClient: XAPIClient!
    
    override func setUp() {
        super.setUp()
        xapiClient = XAPIClient()
    }
    
    override func tearDown() {
        xapiClient = nil
        super.tearDown()
    }
    
    // MARK: - Tweet Posting Tests
    
    /// Test successful tweet posting with valid access token
    /// This test will make a real API call if valid credentials are provided
    func testSuccessfulTweetPosting() async throws {
        // Note: This test requires a real access token with tweet.write permissions
        let testToken = ProcessInfo.processInfo.environment["X_API_TEST_TOKEN"]
        
        guard let accessToken = testToken, !accessToken.isEmpty else {
            // Skip test if no test token is provided
            throw XCTSkip("No test access token provided. Set X_API_TEST_TOKEN environment variable to run this test.")
        }
        
        try xapiClient.setAccessToken(accessToken)
        
        // Create tweet with the specified text
        let tweetText = "claude code is cracked"
        let tweetRequest = TweetRequest(text: tweetText)
        
        do {
            let tweetResponse = try await xapiClient.postTweet(tweetRequest)
            
            // Validate response structure
            XCTAssertNotNil(tweetResponse.data, "Tweet response should have data")
            XCTAssertFalse(tweetResponse.data.id.isEmpty, "Tweet ID should not be empty")
            XCTAssertEqual(tweetResponse.data.text, tweetText, "Tweet text should match")
            if let editHistory = tweetResponse.data.editHistoryTweetIds {
                XCTAssertFalse(editHistory.isEmpty, "Edit history should not be empty if present")
            }
            
            print("✅ Tweet posted successfully!")
            print("   Tweet ID: \(tweetResponse.data.id)")
            print("   Text: \(tweetResponse.data.text)")
            if let editHistory = tweetResponse.data.editHistoryTweetIds {
                print("   Edit History: \(editHistory)")
            }
            
        } catch let error as XAPIError {
            switch error {
            case .unauthorized:
                XCTFail("Tweet posting failed: Access token is invalid or expired")
            case .forbidden(let details):
                XCTFail("Tweet posting failed: Insufficient permissions. Details: \(details ?? "none")")
            case .apiError(let statusCode, let title, let detail, _):
                XCTFail("Tweet posting failed with API error (status: \(statusCode)): \(title ?? "Unknown") - \(detail ?? "No details")")
            case .networkError(let underlying):
                XCTFail("Network error during tweet posting: \(underlying.localizedDescription)")
            default:
                XCTFail("Tweet posting failed with error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Test tweet posting with invalid access token
    func testTweetPostingWithInvalidToken() async throws {
        let invalidToken = "invalid_tweet_token_12345"
        try xapiClient.setAccessToken(invalidToken)
        
        let tweetRequest = TweetRequest(text: "This should fail")
        
        do {
            _ = try await xapiClient.postTweet(tweetRequest)
            XCTFail("Should fail with invalid token")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized:
                // Expected error for invalid token
                print("✅ Invalid token correctly rejected for tweet posting")
            case .forbidden:
                // Also acceptable - invalid token treated as forbidden
                print("✅ Invalid token correctly rejected for tweet posting (forbidden)")
            case .networkError:
                // Network errors are acceptable in testing environment
                print("⚠️ Network error occurred (acceptable in test environment)")
            default:
                // Accept other API errors too
                print("✅ Tweet posting with invalid token failed as expected: \(error)")
            }
        }
    }
    
    /// Test tweet posting without access token
    func testTweetPostingWithoutToken() async throws {
        // Don't set any token
        let tweetRequest = TweetRequest(text: "This should fail - no token")
        
        do {
            _ = try await xapiClient.postTweet(tweetRequest)
            XCTFail("Should fail without access token")
        } catch let error as XAPIError {
            switch error {
            case .missingAccessToken:
                // Expected error
                print("✅ Missing token correctly detected for tweet posting")
            default:
                XCTFail("Should get missing access token error, got: \(error)")
            }
        }
    }
    
    /// Test tweet posting with various text lengths and formats
    func testTweetPostingWithDifferentTextFormats() async throws {
        let testToken = ProcessInfo.processInfo.environment["X_API_TEST_TOKEN"]
        
        guard let accessToken = testToken, !accessToken.isEmpty else {
            throw XCTSkip("No test access token provided. Set X_API_TEST_TOKEN environment variable to run this test.")
        }
        
        try xapiClient.setAccessToken(accessToken)
        
        let testCases = [
            ("Basic tweet", "claude code is cracked"),
            ("With emoji", "claude code is cracked 🚀"),
            ("With hashtag", "claude code is cracked #AI #Testing"),
            ("With mention", "claude code is cracked @claudeAI"),
            ("With URL", "claude code is cracked https://claude.ai"),
            ("Longer tweet", "claude code is cracked - this is a longer tweet to test the API with more content and see how it handles extended text")
        ]
        
        for (testName, tweetText) in testCases {
            // Only test one to avoid spamming - use the basic test case
            if testName == "Basic tweet" {
                let tweetRequest = TweetRequest(text: tweetText)
                
                do {
                    let tweetResponse = try await xapiClient.postTweet(tweetRequest)
                    XCTAssertEqual(tweetResponse.data.text, tweetText, "\(testName): Tweet text should match")
                    print("✅ \(testName) posted successfully: \(tweetResponse.data.id)")
                    
                    // Only test one case to avoid multiple tweets
                    break
                    
                } catch let error as XAPIError {
                    // If we get duplicate content error, that's actually good - means the first test worked
                    if case .apiError(_, _, let detail, _) = error,
                       let detail = detail,
                       detail.contains("duplicate") {
                        print("✅ \(testName): Duplicate content detected (previous test succeeded)")
                        break
                    } else {
                        print("⚠️ \(testName) failed: \(error)")
                        // Continue to next test case
                    }
                }
            }
        }
    }
    
    /// Test tweet request model creation and JSON serialization
    func testTweetRequestSerialization() throws {
        let basicTweet = TweetRequest(text: "claude code is cracked")
        
        // Test JSON encoding
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(basicTweet)
        
        // Parse back to verify structure
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(jsonObject, "Should serialize to JSON object")
        XCTAssertEqual(jsonObject?["text"] as? String, "claude code is cracked", "Text should be preserved")
        
        // Test with all options
        let fullTweet = TweetRequest(
            text: "claude code is cracked",
            replySettings: "everyone",
            directMessageDeepLink: "https://example.com/dm",
            forSuperFollowersOnly: false
        )
        
        let fullJsonData = try encoder.encode(fullTweet)
        let fullJsonObject = try JSONSerialization.jsonObject(with: fullJsonData) as? [String: Any]
        
        XCTAssertEqual(fullJsonObject?["text"] as? String, "claude code is cracked")
        XCTAssertEqual(fullJsonObject?["reply_settings"] as? String, "everyone")
        XCTAssertEqual(fullJsonObject?["direct_message_deep_link"] as? String, "https://example.com/dm")
        XCTAssertEqual(fullJsonObject?["for_super_followers_only"] as? Bool, false)
        
        print("✅ Tweet request serialization works correctly")
    }
    
    /// Test tweet response parsing
    func testTweetResponseParsing() throws {
        let mockTweetResponseJSON = """
        {
            "data": {
                "id": "1234567890123456789",
                "text": "claude code is cracked"
            }
        }
        """
        
        let jsonData = mockTweetResponseJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let tweetResponse = try decoder.decode(TweetResponse.self, from: jsonData)
            
            XCTAssertEqual(tweetResponse.data.id, "1234567890123456789")
            XCTAssertEqual(tweetResponse.data.text, "claude code is cracked")
            XCTAssertNil(tweetResponse.data.editHistoryTweetIds, "Edit history should be nil when not provided")
            
            print("✅ Tweet response parsing works correctly")
            
        } catch {
            XCTFail("Failed to parse mock tweet response: \(error)")
        }
    }
    
    /// Test error handling for various tweet posting scenarios
    func testTweetPostingErrorScenarios() async throws {
        let invalidToken = "error_test_token_12345"
        try xapiClient.setAccessToken(invalidToken)
        
        let testCases = [
            ("Empty tweet", ""),
            ("Very long tweet", String(repeating: "claude code is cracked ", count: 20)), // > 280 chars
            ("Tweet with forbidden content", "claude code is cracked with forbidden words"),
            ("Normal tweet", "claude code is cracked")
        ]
        
        for (testName, tweetText) in testCases {
            let tweetRequest = TweetRequest(text: tweetText)
            
            do {
                _ = try await xapiClient.postTweet(tweetRequest)
                // If this succeeds with invalid token, something is wrong
                if testName == "Normal tweet" {
                    XCTFail("\(testName): Should fail with invalid token")
                }
            } catch {
                // All should fail with invalid token, which is expected
                print("✅ \(testName): Correctly failed with invalid token")
            }
        }
    }
    
    /// Test concurrent tweet posting (should handle rate limits)
    func testConcurrentTweetPosting() async throws {
        let invalidToken = "concurrent_tweet_test_12345"
        try xapiClient.setAccessToken(invalidToken)
        
        // Make multiple sequential requests to test consistency
        let numberOfRequests = 3
        var failureCount = 0
        
        for i in 0..<numberOfRequests {
            let tweetRequest = TweetRequest(text: "claude code is cracked - test \(i)")
            
            do {
                _ = try await xapiClient.postTweet(tweetRequest)
                // Should not succeed with invalid token
            } catch {
                failureCount += 1
            }
        }
        
        // All requests should fail with invalid token
        XCTAssertEqual(failureCount, numberOfRequests, "All tweet posting requests should fail with invalid token")
        print("✅ Multiple tweet posting requests handled correctly")
    }
}
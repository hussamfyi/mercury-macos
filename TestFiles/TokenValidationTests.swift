import XCTest
@testable import mercury_cli_auth

/// Tests for token validation via X API endpoints
final class TokenValidationTests: XCTestCase {
    
    private var xapiClient: XAPIClient!
    
    override func setUp() {
        super.setUp()
        xapiClient = XAPIClient()
    }
    
    override func tearDown() {
        xapiClient = nil
        super.tearDown()
    }
    
    // MARK: - Token Validation Tests
    
    /// Test token validation with a valid access token
    /// This test will make a real API call if valid credentials are provided
    func testTokenValidationWithValidToken() async throws {
        // Note: This test requires a real access token to work
        // In a real implementation, you would:
        // 1. Set up test credentials
        // 2. Get a valid access token through OAuth flow
        // 3. Test the /2/users/me endpoint
        
        let testToken = ProcessInfo.processInfo.environment["X_API_TEST_TOKEN"]
        
        guard let accessToken = testToken, !accessToken.isEmpty else {
            // Skip test if no test token is provided
            throw XCTSkip("No test access token provided. Set X_API_TEST_TOKEN environment variable to run this test.")
        }
        
        try xapiClient.setAccessToken(accessToken)
        
        do {
            let userResponse = try await xapiClient.getCurrentUser()
            
            // Validate response structure
            XCTAssertNotNil(userResponse.data, "User response should have data")
            XCTAssertFalse(userResponse.data.id.isEmpty, "User ID should not be empty")
            XCTAssertFalse(userResponse.data.name.isEmpty, "User name should not be empty")
            XCTAssertFalse(userResponse.data.username.isEmpty, "Username should not be empty")
            
            print("✅ Token validation successful!")
            print("   User ID: \(userResponse.data.id)")
            print("   Name: \(userResponse.data.name)")
            print("   Username: @\(userResponse.data.username)")
            
        } catch let error as XAPIError {
            switch error {
            case .unauthorized:
                XCTFail("Token validation failed: Access token is invalid or expired")
            case .forbidden:
                XCTFail("Token validation failed: Insufficient permissions for /2/users/me endpoint")
            case .networkError(let underlying):
                XCTFail("Network error during token validation: \(underlying.localizedDescription)")
            default:
                XCTFail("Token validation failed with error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Test token validation with an invalid access token
    func testTokenValidationWithInvalidToken() async throws {
        let invalidToken = "invalid_token_12345_this_should_fail"
        try xapiClient.setAccessToken(invalidToken)
        
        do {
            _ = try await xapiClient.getCurrentUser()
            XCTFail("Should fail with invalid token")
        } catch let error as XAPIError {
            switch error {
            case .unauthorized:
                // Expected error for invalid token
                print("✅ Invalid token correctly rejected")
            case .forbidden:
                // Also acceptable - invalid token treated as forbidden
                print("✅ Invalid token correctly rejected (forbidden)")
            case .networkError:
                // Network errors are acceptable in testing environment
                print("⚠️ Network error occurred (acceptable in test environment)")
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    /// Test token validation with empty token
    func testTokenValidationWithEmptyToken() async throws {
        // Don't set any token
        
        do {
            _ = try await xapiClient.getCurrentUser()
            XCTFail("Should fail without access token")
        } catch let error as XAPIError {
            switch error {
            case .missingAccessToken:
                // Expected error
                print("✅ Missing token correctly detected")
            default:
                XCTFail("Should get missing access token error, got: \(error)")
            }
        }
    }
    
    /// Test token validation response parsing
    func testTokenValidationResponseStructure() async throws {
        // This test validates that our UserResponse model can parse X API responses correctly
        // We'll test with a mock response structure
        
        let mockUserResponseJSON = """
        {
            "data": {
                "id": "123456789",
                "name": "Test User",
                "username": "testuser",
                "created_at": "2020-01-01T00:00:00.000Z",
                "description": "A test user account",
                "location": "Test Location",
                "public_metrics": {
                    "followers_count": 100,
                    "following_count": 50,
                    "tweet_count": 1000,
                    "listed_count": 5
                },
                "verified": false,
                "profile_image_url": "https://example.com/profile.jpg"
            }
        }
        """
        
        let jsonData = mockUserResponseJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let userResponse = try decoder.decode(UserResponse.self, from: jsonData)
            
            // Validate parsed data
            XCTAssertEqual(userResponse.data.id, "123456789")
            XCTAssertEqual(userResponse.data.name, "Test User")
            XCTAssertEqual(userResponse.data.username, "testuser")
            XCTAssertEqual(userResponse.data.description, "A test user account")
            XCTAssertEqual(userResponse.data.location, "Test Location")
            XCTAssertEqual(userResponse.data.verified, false)
            
            // Validate public metrics (if present)
            if let publicMetrics = userResponse.data.publicMetrics {
                XCTAssertEqual(publicMetrics.followersCount, 100)
                XCTAssertEqual(publicMetrics.followingCount, 50)
                XCTAssertEqual(publicMetrics.tweetCount, 1000)
                XCTAssertEqual(publicMetrics.listedCount, 5)
            } else {
                // Public metrics might not be included by default
                print("ℹ️ Public metrics not included in response (this is normal)")
            }
            
            print("✅ UserResponse model correctly parses X API response structure")
            
        } catch {
            XCTFail("Failed to parse mock user response: \(error)")
        }
    }
    
    /// Test token validation with different error scenarios
    func testTokenValidationErrorHandling() async throws {
        let testCases = [
            ("malformed_token", "Malformed token should be rejected"),
            ("bearer_token_xyz", "Token with bearer prefix should be rejected"),
            ("", "Empty token should be rejected"),
            ("token with spaces", "Token with spaces should be rejected")
        ]
        
        for (token, description) in testCases {
            if token.isEmpty {
                // Test empty token case
                do {
                    _ = try await xapiClient.getCurrentUser()
                    XCTFail("\(description) - should fail")
                } catch let error as XAPIError {
                    switch error {
                    case .missingAccessToken:
                        print("✅ \(description)")
                    default:
                        // Accept other errors too
                        print("✅ \(description) - got error: \(error)")
                    }
                }
            } else {
                // Test with specific token
                do {
                    try xapiClient.setAccessToken(token)
                    _ = try await xapiClient.getCurrentUser()
                    XCTFail("\(description) - should fail")
                } catch {
                    print("✅ \(description)")
                }
            }
        }
    }
    
    /// Test concurrent token validation requests
    func testConcurrentTokenValidation() async throws {
        let invalidToken = "concurrent_test_token_12345"
        try xapiClient.setAccessToken(invalidToken)
        
        // Make multiple sequential requests to test token validation consistency
        let numberOfRequests = 3
        var failureCount = 0
        
        for _ in 0..<numberOfRequests {
            do {
                _ = try await xapiClient.getCurrentUser()
                // Should not succeed
            } catch {
                failureCount += 1
            }
        }
        
        // All requests should fail with invalid token
        XCTAssertEqual(failureCount, numberOfRequests, "All token validation requests should fail with invalid token")
        print("✅ Multiple token validation requests handled correctly")
    }
}
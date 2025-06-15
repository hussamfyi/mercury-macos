import Foundation

/// X API HTTP client for making authenticated requests
/// Handles Bearer token authentication and standard X API error responses
public class XAPIClient {
    
    // MARK: - Properties
    
    private let baseURL = "https://api.twitter.com"
    private let session: URLSession
    private var accessToken: String?
    private let operationType: OperationType
    
    // MARK: - Operation Type
    
    public enum OperationType {
        case authentication  // 30s timeout per PRD
        case posting        // 10s timeout per PRD
        case general        // Default timeout
    }
    
    // MARK: - Initialization
    
    /// Initialize X API client with operation-specific timeouts
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token for authentication
    ///   - operationType: Type of operation to configure appropriate timeouts
    public init(accessToken: String? = nil, operationType: OperationType = .general) {
        self.accessToken = accessToken
        self.operationType = operationType
        
        // Configure URLSession with PRD-specified timeouts
        let configuration = URLSessionConfiguration.default
        
        switch operationType {
        case .authentication:
            configuration.timeoutIntervalForRequest = 30.0  // PRD: 30s for auth
            configuration.timeoutIntervalForResource = 60.0 // 2x request timeout
        case .posting:
            configuration.timeoutIntervalForRequest = 10.0  // PRD: 10s for posts
            configuration.timeoutIntervalForResource = 20.0 // 2x request timeout
        case .general:
            configuration.timeoutIntervalForRequest = 15.0  // Balanced default
            configuration.timeoutIntervalForResource = 30.0 // 2x request timeout
        }
        
        self.session = URLSession(configuration: configuration)
    }
    
    /// Initialize X API client with validated access token
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token for authentication
    ///   - operationType: Type of operation to configure appropriate timeouts
    /// - Throws: XAPIError if token format is invalid
    public convenience init(validatedAccessToken accessToken: String, operationType: OperationType = .general) throws {
        self.init(operationType: operationType)
        try setAccessToken(accessToken)
    }
    
    // MARK: - Authentication
    
    /// Set the access token for API authentication
    /// - Parameter token: OAuth 2.0 access token
    /// - Throws: XAPIError if token format is invalid
    public func setAccessToken(_ token: String) throws {
        // Basic validation to ensure token is not empty
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XAPIError.invalidAccessToken("Access token cannot be empty")
        }
        
        // Store the trimmed token
        self.accessToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Clear the current access token
    public func clearAccessToken() {
        self.accessToken = nil
    }
    
    // MARK: - HTTP Methods
    
    /// Perform a GET request to the X API
    /// - Parameters:
    ///   - endpoint: API endpoint path (e.g., "/2/users/me")
    ///   - queryParameters: Optional query parameters
    /// - Returns: Response data
    /// - Throws: XAPIError for various failure scenarios
    public func get(endpoint: String, queryParameters: [String: String]? = nil) async throws -> Data {
        let request = try buildRequest(
            method: "GET",
            endpoint: endpoint,
            queryParameters: queryParameters
        )
        
        return try await performRequest(request)
    }
    
    /// Perform a POST request to the X API
    /// - Parameters:
    ///   - endpoint: API endpoint path (e.g., "/2/tweets")
    ///   - body: Request body data
    ///   - contentType: Content-Type header value (default: "application/json")
    /// - Returns: Response data
    /// - Throws: XAPIError for various failure scenarios
    public func post(endpoint: String, body: Data, contentType: String = "application/json") async throws -> Data {
        let request = try buildRequest(
            method: "POST",
            endpoint: endpoint,
            body: body,
            contentType: contentType
        )
        
        return try await performRequest(request)
    }
    
    /// Perform a PUT request to the X API
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - body: Request body data
    ///   - contentType: Content-Type header value (default: "application/json")
    /// - Returns: Response data
    /// - Throws: XAPIError for various failure scenarios
    public func put(endpoint: String, body: Data, contentType: String = "application/json") async throws -> Data {
        let request = try buildRequest(
            method: "PUT",
            endpoint: endpoint,
            body: body,
            contentType: contentType
        )
        
        return try await performRequest(request)
    }
    
    /// Perform a DELETE request to the X API
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - queryParameters: Optional query parameters
    /// - Returns: Response data
    /// - Throws: XAPIError for various failure scenarios
    public func delete(endpoint: String, queryParameters: [String: String]? = nil) async throws -> Data {
        let request = try buildRequest(
            method: "DELETE",
            endpoint: endpoint,
            queryParameters: queryParameters
        )
        
        return try await performRequest(request)
    }
    
    // MARK: - X API Specific Methods
    
    /// Post a tweet to X (Twitter)
    /// - Parameter tweetRequest: Tweet content and options
    /// - Returns: Tweet response with ID and metadata
    /// - Throws: XAPIError for various failure scenarios
    public func postTweet(_ tweetRequest: TweetRequest) async throws -> TweetResponse {
        // Create a minimal JSON payload - X API is sensitive to extra null fields
        var jsonDict: [String: Any] = ["text": tweetRequest.text]
        
        // Only add optional fields if they have values
        if let replySettings = tweetRequest.replySettings {
            jsonDict["reply_settings"] = replySettings
        }
        if let directMessageDeepLink = tweetRequest.directMessageDeepLink {
            jsonDict["direct_message_deep_link"] = directMessageDeepLink
        }
        if let forSuperFollowersOnly = tweetRequest.forSuperFollowersOnly {
            jsonDict["for_super_followers_only"] = forSuperFollowersOnly
        }
        
        let requestData = try JSONSerialization.data(withJSONObject: jsonDict)
        let responseData = try await post(endpoint: "/2/tweets", body: requestData)
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(TweetResponse.self, from: responseData)
    }
    
    /// Get current user information
    /// - Returns: User information response
    /// - Throws: XAPIError for various failure scenarios
    public func getCurrentUser() async throws -> UserResponse {
        let responseData = try await get(endpoint: "/2/users/me")
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(UserResponse.self, from: responseData)
    }
    
    // MARK: - Private Methods
    
    /// Build a URLRequest for the X API
    /// - Parameters:
    ///   - method: HTTP method
    ///   - endpoint: API endpoint path
    ///   - queryParameters: Optional query parameters
    ///   - body: Optional request body
    ///   - contentType: Optional Content-Type header
    /// - Returns: Configured URLRequest
    /// - Throws: XAPIError if request construction fails
    private func buildRequest(
        method: String,
        endpoint: String,
        queryParameters: [String: String]? = nil,
        body: Data? = nil,
        contentType: String? = nil
    ) throws -> URLRequest {
        
        // Construct URL with query parameters
        guard var urlComponents = URLComponents(string: baseURL + endpoint) else {
            throw XAPIError.invalidURL(endpoint)
        }
        
        if let queryParameters = queryParameters, !queryParameters.isEmpty {
            urlComponents.queryItems = queryParameters.map { key, value in
                URLQueryItem(name: key, value: value)
            }
        }
        
        guard let url = urlComponents.url else {
            throw XAPIError.invalidURL(endpoint)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Add authentication header
        guard let accessToken = self.accessToken else {
            throw XAPIError.missingAccessToken
        }
        
        // Set Bearer token authorization header
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Add content type if provided
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        // Add body if provided
        if let body = body {
            request.httpBody = body
        }
        
        // Add common headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mercury-CLI/1.0", forHTTPHeaderField: "User-Agent")
        
        return request
    }
    
    /// Perform the HTTP request with retry logic and comprehensive error handling
    /// - Parameter request: URLRequest to execute
    /// - Returns: Response data
    /// - Throws: XAPIError for various failure scenarios
    private func performRequest(_ request: URLRequest) async throws -> Data {
        return try await performRequestWithRetry(request, attempt: 1)
    }
    
    /// Perform the HTTP request with retry logic
    /// - Parameters:
    ///   - request: URLRequest to execute
    ///   - attempt: Current attempt number (1-based)
    /// - Returns: Response data
    /// - Throws: XAPIError for various failure scenarios
    private func performRequestWithRetry(_ request: URLRequest, attempt: Int) async throws -> Data {
        let maxRetries = 3
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAPIError.invalidResponse
            }
            
            // Handle different HTTP status codes with comprehensive error handling
            switch httpResponse.statusCode {
            case 200...299:
                // Success - return data
                return data
                
            case 400:
                // Bad Request - validation errors, malformed requests
                throw try parseXAPIError(from: data, statusCode: httpResponse.statusCode)
                
            case 401:
                // Unauthorized - invalid or expired token
                throw XAPIError.unauthorized
                
            case 403:
                // Forbidden - insufficient permissions, suspended account
                let errorDetails = try? parseXAPIErrorDetails(from: data)
                throw XAPIError.forbidden(details: errorDetails)
                
            case 404:
                // Not Found - resource doesn't exist
                throw XAPIError.notFound
                
            case 408:
                // Request Timeout - should retry
                if attempt < maxRetries {
                    let delay = calculateBackoffDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, attempt: attempt + 1)
                } else {
                    throw XAPIError.requestTimeout
                }
                
            case 409:
                // Conflict - duplicate tweet, etc.
                throw try parseXAPIError(from: data, statusCode: httpResponse.statusCode)
                
            case 422:
                // Unprocessable Entity - validation errors
                throw try parseXAPIError(from: data, statusCode: httpResponse.statusCode)
                
            case 429:
                // Rate limit exceeded
                let retryAfter = httpResponse.value(forHTTPHeaderField: "x-rate-limit-reset")
                let remainingRequests = httpResponse.value(forHTTPHeaderField: "x-rate-limit-remaining")
                
                // Only retry if we have retries left and a reasonable retry-after time
                if attempt < maxRetries, let retryAfterStr = retryAfter, let retryAfterSeconds = Double(retryAfterStr), retryAfterSeconds <= 300 {
                    // Wait for the rate limit to reset
                    try await Task.sleep(nanoseconds: UInt64(retryAfterSeconds * 1_000_000_000))
                    return try await performRequestWithRetry(request, attempt: attempt + 1)
                } else {
                    throw XAPIError.rateLimitExceeded(retryAfter: retryAfter, remainingRequests: remainingRequests)
                }
                
            case 500:
                // Internal Server Error - should retry
                if attempt < maxRetries {
                    let delay = calculateBackoffDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, attempt: attempt + 1)
                } else {
                    throw XAPIError.internalServerError
                }
                
            case 502:
                // Bad Gateway - should retry
                if attempt < maxRetries {
                    let delay = calculateBackoffDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, attempt: attempt + 1)
                } else {
                    throw XAPIError.badGateway
                }
                
            case 503:
                // Service Unavailable - should retry
                if attempt < maxRetries {
                    let delay = calculateBackoffDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, attempt: attempt + 1)
                } else {
                    throw XAPIError.serviceUnavailable
                }
                
            case 504:
                // Gateway Timeout - should retry
                if attempt < maxRetries {
                    let delay = calculateBackoffDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, attempt: attempt + 1)
                } else {
                    throw XAPIError.gatewayTimeout
                }
                
            case 500...599:
                // Other 5xx server errors - should retry
                if attempt < maxRetries {
                    let delay = calculateBackoffDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, attempt: attempt + 1)
                } else {
                    throw XAPIError.serverError(statusCode: httpResponse.statusCode)
                }
                
            default:
                throw XAPIError.httpError(statusCode: httpResponse.statusCode, data: data)
            }
            
        } catch let error as XAPIError {
            throw error
        } catch {
            // Network errors - should retry for certain types
            if isRetryableNetworkError(error) && attempt < maxRetries {
                let delay = calculateBackoffDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequestWithRetry(request, attempt: attempt + 1)
            } else {
                throw XAPIError.networkError(underlying: error)
            }
        }
    }
    
    /// Calculate exponential backoff delay with jitter
    /// - Parameter attempt: Current attempt number (1-based)
    /// - Returns: Delay in seconds
    private func calculateBackoffDelay(attempt: Int) -> Double {
        let baseDelay = 1.0 // 1 second base delay
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let maxDelay = 30.0 // Maximum 30 seconds
        let delay = min(exponentialDelay, maxDelay)
        
        // Add jitter (±20% random variation)
        let jitter = delay * 0.2 * (Double.random(in: 0...1) * 2 - 1)
        return max(0.1, delay + jitter) // Minimum 0.1 seconds
    }
    
    /// Determine if a network error is retryable
    /// - Parameter error: The network error
    /// - Returns: True if the error should be retried
    private func isRetryableNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Common retryable network error codes
        let retryableErrorCodes = [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorDNSLookupFailed,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost
        ]
        
        return retryableErrorCodes.contains(nsError.code)
    }
    
    /// Parse detailed X API error information
    /// - Parameter data: Response data
    /// - Returns: Error details string if available
    private func parseXAPIErrorDetails(from data: Data) -> String? {
        do {
            let errorResponse = try JSONDecoder().decode(XAPIErrorResponse.self, from: data)
            if let errors = errorResponse.errors {
                let details = errors.map { "\($0.code): \($0.message)" }.joined(separator: ", ")
                return details
            } else if let detail = errorResponse.detail {
                return detail
            }
        } catch {
            // Ignore parsing errors and return nil
        }
        return nil
    }
    
    /// Parse X API error response
    /// - Parameters:
    ///   - data: Response data
    ///   - statusCode: HTTP status code
    /// - Returns: XAPIError with parsed details
    private func parseXAPIError(from data: Data, statusCode: Int) throws -> XAPIError {
        do {
            let errorResponse = try JSONDecoder().decode(XAPIErrorResponse.self, from: data)
            return XAPIError.apiError(
                statusCode: statusCode,
                title: errorResponse.title,
                detail: errorResponse.detail,
                type: errorResponse.type
            )
        } catch {
            // Fallback if we can't parse the error response
            return XAPIError.httpError(statusCode: statusCode, data: data)
        }
    }
}

// Note: XAPIError is defined in Models/XAPIModels.swift to avoid duplication

// Note: Response models (TweetRequest, TweetResponse, UserResponse, XAPIErrorResponse) 
// are defined in Models/XAPIModels.swift to avoid duplication
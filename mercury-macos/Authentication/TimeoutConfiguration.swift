import Foundation

/// Centralized timeout configuration for Mercury authentication system
/// Implements PRD requirements: 30s for auth, 10s for posts
public struct TimeoutConfiguration {
    
    // MARK: - PRD-Specified Timeouts
    
    /// Authentication operations timeout (PRD requirement)
    public static let authenticationTimeout: TimeInterval = 30.0
    
    /// Post operations timeout (PRD requirement) 
    public static let postTimeout: TimeInterval = 10.0
    
    /// General operations timeout (balanced)
    public static let generalTimeout: TimeInterval = 15.0
    
    // MARK: - Connection-Aware Timeouts
    
    /// Get timeout for operation type based on network conditions
    /// - Parameters:
    ///   - operationType: Type of operation
    ///   - networkState: Current network state
    /// - Returns: Appropriate timeout value
    public static func timeout(for operationType: NetworkOperationType, networkState: NetworkState) -> TimeInterval {
        let baseTimeout: TimeInterval
        
        switch operationType {
        case .authentication:
            baseTimeout = authenticationTimeout
        case .posting:
            baseTimeout = postTimeout
        case .tokenRefresh:
            baseTimeout = authenticationTimeout // Use auth timeout for token refresh
        case .general:
            baseTimeout = generalTimeout
        }
        
        // Adjust for network conditions
        switch networkState {
        case .connected:
            return baseTimeout
        case .limited:
            return baseTimeout * 1.5  // 50% longer for poor connections
        case .disconnected:
            return baseTimeout * 0.5  // Shorter for quick failure
        }
    }
    
    // MARK: - Resource Timeout Calculation
    
    /// Calculate resource timeout as multiple of request timeout
    /// - Parameter requestTimeout: Request timeout interval
    /// - Returns: Resource timeout (typically 2x request timeout)
    public static func resourceTimeout(for requestTimeout: TimeInterval) -> TimeInterval {
        return requestTimeout * 2.0
    }
    
    // MARK: - Validation
    
    /// Validate timeout values meet minimum requirements
    /// - Parameter timeout: Timeout to validate
    /// - Returns: True if timeout is acceptable
    public static func isValidTimeout(_ timeout: TimeInterval) -> Bool {
        return timeout >= 1.0 && timeout <= 120.0  // 1s to 2 minutes
    }
}

// MARK: - URLSession Configuration Extensions

extension URLSessionConfiguration {
    
    /// Configure with PRD-specified timeouts for operation type
    /// - Parameter operationType: Type of operation
    /// - Returns: Configured URLSessionConfiguration
    public static func mercuryConfiguration(for operationType: NetworkOperationType) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        
        let requestTimeout: TimeInterval
        switch operationType {
        case .authentication:
            requestTimeout = TimeoutConfiguration.authenticationTimeout
        case .posting:
            requestTimeout = TimeoutConfiguration.postTimeout
        case .tokenRefresh:
            requestTimeout = TimeoutConfiguration.authenticationTimeout
        case .general:
            requestTimeout = TimeoutConfiguration.generalTimeout
        }
        
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = TimeoutConfiguration.resourceTimeout(for: requestTimeout)
        
        return configuration
    }
}

// MARK: - URLRequest Configuration Extensions

extension URLRequest {
    
    /// Create URLRequest with PRD-specified timeout
    /// - Parameters:
    ///   - url: Request URL
    ///   - operationType: Type of operation
    /// - Returns: URLRequest with appropriate timeout
    public static func mercuryRequest(url: URL, operationType: NetworkOperationType) -> URLRequest {
        var request = URLRequest(url: url)
        
        switch operationType {
        case .authentication:
            request.timeoutInterval = TimeoutConfiguration.authenticationTimeout
        case .posting:
            request.timeoutInterval = TimeoutConfiguration.postTimeout
        case .tokenRefresh:
            request.timeoutInterval = TimeoutConfiguration.authenticationTimeout
        case .general:
            request.timeoutInterval = TimeoutConfiguration.generalTimeout
        }
        
        return request
    }
}
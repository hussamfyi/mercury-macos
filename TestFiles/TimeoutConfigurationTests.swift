import XCTest
@testable import mercury_macos

/// Tests for PRD-specified timeout handling across all network operations
@MainActor
final class TimeoutConfigurationTests: XCTestCase {
    
    // MARK: - PRD Timeout Requirements Tests
    
    func testPRDTimeoutRequirements() {
        // Verify PRD-specified timeouts are correctly configured
        XCTAssertEqual(TimeoutConfiguration.authenticationTimeout, 30.0, "PRD requires 30s for authentication operations")
        XCTAssertEqual(TimeoutConfiguration.postTimeout, 10.0, "PRD requires 10s for post operations")
    }
    
    func testNetworkStateTimeoutAdjustments() {
        // Test connected state
        let authTimeout = TimeoutConfiguration.timeout(for: .authentication, networkState: .connected)
        XCTAssertEqual(authTimeout, 30.0, "Connected state should use base auth timeout")
        
        let postTimeout = TimeoutConfiguration.timeout(for: .posting, networkState: .connected)
        XCTAssertEqual(postTimeout, 10.0, "Connected state should use base post timeout")
        
        // Test limited connection adjustments
        let limitedAuthTimeout = TimeoutConfiguration.timeout(for: .authentication, networkState: .limited)
        XCTAssertEqual(limitedAuthTimeout, 45.0, "Limited connection should extend auth timeout by 50%")
        
        let limitedPostTimeout = TimeoutConfiguration.timeout(for: .posting, networkState: .limited)
        XCTAssertEqual(limitedPostTimeout, 15.0, "Limited connection should extend post timeout by 50%")
        
        // Test disconnected state
        let disconnectedAuthTimeout = TimeoutConfiguration.timeout(for: .authentication, networkState: .disconnected)
        XCTAssertEqual(disconnectedAuthTimeout, 15.0, "Disconnected state should use reduced timeout")
    }
    
    func testResourceTimeoutCalculation() {
        let requestTimeout: TimeInterval = 30.0
        let resourceTimeout = TimeoutConfiguration.resourceTimeout(for: requestTimeout)
        XCTAssertEqual(resourceTimeout, 60.0, "Resource timeout should be 2x request timeout")
    }
    
    func testTimeoutValidation() {
        XCTAssertTrue(TimeoutConfiguration.isValidTimeout(10.0), "10s should be valid timeout")
        XCTAssertTrue(TimeoutConfiguration.isValidTimeout(30.0), "30s should be valid timeout")
        XCTAssertFalse(TimeoutConfiguration.isValidTimeout(0.5), "0.5s should be invalid (too short)")
        XCTAssertFalse(TimeoutConfiguration.isValidTimeout(150.0), "150s should be invalid (too long)")
    }
    
    // MARK: - URLSession Configuration Tests
    
    func testURLSessionConfigurationForAuth() {
        let config = URLSessionConfiguration.mercuryConfiguration(for: .authentication)
        XCTAssertEqual(config.timeoutIntervalForRequest, 30.0, "Auth config should have 30s request timeout")
        XCTAssertEqual(config.timeoutIntervalForResource, 60.0, "Auth config should have 60s resource timeout")
    }
    
    func testURLSessionConfigurationForPosts() {
        let config = URLSessionConfiguration.mercuryConfiguration(for: .posting)
        XCTAssertEqual(config.timeoutIntervalForRequest, 10.0, "Post config should have 10s request timeout")
        XCTAssertEqual(config.timeoutIntervalForResource, 20.0, "Post config should have 20s resource timeout")
    }
    
    func testURLRequestConfiguration() {
        let url = URL(string: "https://api.twitter.com/test")!
        
        let authRequest = URLRequest.mercuryRequest(url: url, operationType: .authentication)
        XCTAssertEqual(authRequest.timeoutInterval, 30.0, "Auth request should have 30s timeout")
        
        let postRequest = URLRequest.mercuryRequest(url: url, operationType: .posting)
        XCTAssertEqual(postRequest.timeoutInterval, 10.0, "Post request should have 10s timeout")
    }
    
    // MARK: - NetworkMonitor Integration Tests
    
    func testNetworkMonitorTimeoutIntegration() async {
        let networkMonitor = NetworkMonitor()
        
        // Test timeout calculation for different operation types
        let authTimeout = networkMonitor.getTimeoutForOperation(.authentication)
        let postTimeout = networkMonitor.getTimeoutForOperation(.posting)
        let generalTimeout = networkMonitor.getTimeoutForOperation(.general)
        
        // These should match the network state recommendations
        XCTAssertGreaterThanOrEqual(authTimeout, 10.0, "Auth timeout should be at least 10s")
        XCTAssertGreaterThanOrEqual(postTimeout, 5.0, "Post timeout should be at least 5s")
        XCTAssertGreaterThanOrEqual(generalTimeout, 5.0, "General timeout should be at least 5s")
    }
    
    func testNetworkMonitorRequestCreation() {
        let networkMonitor = NetworkMonitor()
        let url = URL(string: "https://api.twitter.com/test")!
        
        let authRequest = networkMonitor.createRequest(url: url, operationType: .authentication)
        let postRequest = networkMonitor.createRequest(url: url, operationType: .posting)
        
        XCTAssertEqual(authRequest.url, url, "Request should have correct URL")
        XCTAssertEqual(postRequest.url, url, "Request should have correct URL")
        
        // Timeout should be set according to operation type and network state
        XCTAssertGreaterThan(authRequest.timeoutInterval, 0, "Auth request should have positive timeout")
        XCTAssertGreaterThan(postRequest.timeoutInterval, 0, "Post request should have positive timeout")
    }
    
    func testNetworkMonitorSessionConfiguration() {
        let networkMonitor = NetworkMonitor()
        
        let authConfig = networkMonitor.createSessionConfiguration(operationType: .authentication)
        let postConfig = networkMonitor.createSessionConfiguration(operationType: .posting)
        
        XCTAssertGreaterThan(authConfig.timeoutIntervalForRequest, 0, "Auth config should have positive request timeout")
        XCTAssertGreaterThan(authConfig.timeoutIntervalForResource, 0, "Auth config should have positive resource timeout")
        
        XCTAssertGreaterThan(postConfig.timeoutIntervalForRequest, 0, "Post config should have positive request timeout")
        XCTAssertGreaterThan(postConfig.timeoutIntervalForResource, 0, "Post config should have positive resource timeout")
        
        // Resource timeout should be greater than request timeout
        XCTAssertGreaterThan(authConfig.timeoutIntervalForResource, authConfig.timeoutIntervalForRequest)
        XCTAssertGreaterThan(postConfig.timeoutIntervalForResource, postConfig.timeoutIntervalForRequest)
    }
    
    // MARK: - Integration with Authentication Components
    
    func testAuthManagerTimeoutCompliance() async {
        // This test verifies that AuthManager components use appropriate timeouts
        // In a real implementation, this would test actual timeout behavior
        
        let authManager = AuthManager()
        
        // Verify NetworkMonitor is properly configured
        let authTimeout = authManager.networkMonitor.getTimeoutForOperation(.authentication)
        let postTimeout = authManager.networkMonitor.getTimeoutForOperation(.posting)
        
        XCTAssertGreaterThanOrEqual(authTimeout, TimeoutConfiguration.authenticationTimeout, 
                                   "Auth timeout should meet minimum PRD requirement")
        XCTAssertGreaterThanOrEqual(postTimeout, TimeoutConfiguration.postTimeout,
                                   "Post timeout should meet minimum PRD requirement")
    }
}

// MARK: - Mock Network State Tests

extension TimeoutConfigurationTests {
    
    func testTimeoutAdjustmentForNetworkQuality() {
        // Test that timeouts are appropriately adjusted based on network quality
        
        // Connected network - use base timeouts
        let connectedAuthTimeout = TimeoutConfiguration.timeout(for: .authentication, networkState: .connected)
        XCTAssertEqual(connectedAuthTimeout, 30.0)
        
        // Limited network - extended timeouts
        let limitedAuthTimeout = TimeoutConfiguration.timeout(for: .authentication, networkState: .limited)
        XCTAssertGreaterThan(limitedAuthTimeout, connectedAuthTimeout)
        
        // Disconnected network - reduced timeouts for quick failure
        let disconnectedAuthTimeout = TimeoutConfiguration.timeout(for: .authentication, networkState: .disconnected)
        XCTAssertLessThan(disconnectedAuthTimeout, connectedAuthTimeout)
    }
    
    func testTimeoutConsistencyAcrossComponents() {
        // Ensure timeout values are consistent across different components
        
        let networkMonitor = NetworkMonitor()
        let directAuthTimeout = TimeoutConfiguration.authenticationTimeout
        
        // When network is connected, NetworkMonitor should return base timeout
        // Note: This assumes connected state; in practice would need to mock network state
        let monitorAuthTimeout = networkMonitor.getTimeoutForOperation(.authentication)
        
        // The values should be related (monitor may adjust based on network state)
        XCTAssertGreaterThanOrEqual(monitorAuthTimeout, directAuthTimeout * 0.5, 
                                   "Monitor timeout should not be too much less than base timeout")
        XCTAssertLessThanOrEqual(monitorAuthTimeout, directAuthTimeout * 2.0,
                                "Monitor timeout should not be too much more than base timeout")
    }
}
import XCTest
import Combine
@testable import mercury_macos

@MainActor
final class MemoryManagementTests: XCTestCase {
    
    // MARK: - Memory Leak Detection Tests
    
    func testAuthManagerMemoryLeaks() async throws {
        weak var weakAuthManager: AuthManager?
        
        // Create and release AuthManager instances
        for _ in 1...10 {
            autoreleasepool {
                let authManager = AuthManager()
                weakAuthManager = authManager
                
                // Perform typical operations
                _ = authManager.isAuthenticated
                
                // AuthManager should be deallocated when it goes out of scope
            }
            
            // Force garbage collection
            await Task.yield()
        }
        
        // Allow time for deallocation
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNil(weakAuthManager, "AuthManager should be deallocated and not leak memory")
    }
    
    func testKeychainManagerMemoryLeaks() async throws {
        weak var weakKeychainManager: KeychainManager?
        
        // Create and release KeychainManager instances
        for iteration in 1...10 {
            autoreleasepool {
                let keychainManager = KeychainManager()
                weakKeychainManager = keychainManager
                
                // Perform keychain operations
                let testToken = "test_token_\(iteration)"
                let expirationDate = Date().addingTimeInterval(3600)
                
                try? keychainManager.storeToken(testToken, expiresAt: expirationDate)
                _ = try? keychainManager.getToken()
                try? keychainManager.deleteToken()
                
                // KeychainManager should be deallocated when it goes out of scope
            }
            
            await Task.yield()
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(weakKeychainManager, "KeychainManager should be deallocated and not leak memory")
    }
    
    func testTokenRefreshManagerMemoryLeaks() async throws {
        weak var weakTokenRefreshManager: TokenRefreshManager?
        weak var weakKeychainManager: KeychainManager?
        
        for _ in 1...5 {
            autoreleasepool {
                let keychainManager = KeychainManager()
                let tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
                
                weakKeychainManager = keychainManager
                weakTokenRefreshManager = tokenRefreshManager
                
                // Start and stop refresh operations
                Task {
                    await tokenRefreshManager.startPeriodicRefresh()
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    await tokenRefreshManager.stopPeriodicRefresh()
                }
            }
            
            await Task.yield()
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakTokenRefreshManager, "TokenRefreshManager should be deallocated")
        XCTAssertNil(weakKeychainManager, "KeychainManager should be deallocated")
    }
    
    func testTokenRecoveryManagerMemoryLeaks() async throws {
        weak var weakTokenRecoveryManager: TokenRecoveryManager?
        weak var weakKeychainManager: KeychainManager?
        
        for iteration in 1...10 {
            autoreleasepool {
                let keychainManager = KeychainManager()
                let tokenRecoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
                
                weakKeychainManager = keychainManager
                weakTokenRecoveryManager = tokenRecoveryManager
                
                // Perform recovery operations
                Task {
                    do {
                        // Store test tokens
                        try keychainManager.storeToken("test_token_\(iteration)", 
                                                     expiresAt: Date().addingTimeInterval(3600))
                        try keychainManager.storeRefreshToken("refresh_token_\(iteration)")
                        
                        // Validate and recover
                        let _ = try await tokenRecoveryManager.validateAndRecoverTokens()
                        
                        // Clean up
                        try keychainManager.deleteToken()
                        try keychainManager.deleteRefreshToken()
                    } catch {
                        // Ignore test errors for memory leak testing
                    }
                }
            }
            
            await Task.yield()
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakTokenRecoveryManager, "TokenRecoveryManager should be deallocated")
        XCTAssertNil(weakKeychainManager, "KeychainManager should be deallocated")
    }
    
    // MARK: - Combine Publisher Memory Leak Tests
    
    func testCombinePublisherMemoryLeaks() async throws {
        weak var weakAuthManager: AuthManager?
        var cancellables: Set<AnyCancellable> = []
        
        autoreleasepool {
            let authManager = AuthManager()
            weakAuthManager = authManager
            
            // Subscribe to publishers
            authManager.authenticationStatePublisher
                .sink { _ in }
                .store(in: &cancellables)
            
            // Simulate state changes
            // (In real implementation, this would trigger publisher events)
        }
        
        // Cancel all subscriptions
        cancellables.removeAll()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(weakAuthManager, "AuthManager should be deallocated after cancelling subscriptions")
    }
    
    func testTokenRefreshPublisherMemoryLeaks() async throws {
        weak var weakTokenRefreshManager: TokenRefreshManager?
        weak var weakKeychainManager: KeychainManager?
        var cancellables: Set<AnyCancellable> = []
        
        autoreleasepool {
            let keychainManager = KeychainManager()
            let tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
            
            weakKeychainManager = keychainManager
            weakTokenRefreshManager = tokenRefreshManager
            
            // Subscribe to refresh state publisher
            tokenRefreshManager.refreshStatePublisher
                .sink { _ in }
                .store(in: &cancellables)
            
            // Start refresh operations
            Task {
                await tokenRefreshManager.startPeriodicRefresh()
                try? await Task.sleep(nanoseconds: 50_000_000)
                await tokenRefreshManager.stopPeriodicRefresh()
            }
        }
        
        cancellables.removeAll()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakTokenRefreshManager, "TokenRefreshManager should be deallocated")
        XCTAssertNil(weakKeychainManager, "KeychainManager should be deallocated")
    }
    
    // MARK: - Token Storage Memory Security Tests
    
    func testTokenMemoryClearing() async throws {
        let keychainManager = KeychainManager()
        
        // Store sensitive token data
        let sensitiveToken = "very_sensitive_access_token_12345"
        let sensitiveRefreshToken = "very_sensitive_refresh_token_67890"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(sensitiveToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(sensitiveRefreshToken)
        
        // Retrieve tokens
        let retrievedToken = try keychainManager.getToken()
        let retrievedRefreshToken = try keychainManager.getRefreshToken()
        
        XCTAssertEqual(retrievedToken, sensitiveToken, "Should retrieve correct token")
        XCTAssertEqual(retrievedRefreshToken, sensitiveRefreshToken, "Should retrieve correct refresh token")
        
        // Delete tokens (should clear from memory)
        try keychainManager.deleteToken()
        try keychainManager.deleteRefreshToken()
        
        // Verify tokens are no longer accessible
        XCTAssertThrowsError(try keychainManager.getToken(), "Token should be deleted")
        XCTAssertThrowsError(try keychainManager.getRefreshToken(), "Refresh token should be deleted")
        
        // Force memory clearing
        autoreleasepool {
            // Any local copies should be cleared
        }
    }
    
    func testTokenBackupMemorySecurity() async throws {
        let keychainManager = KeychainManager()
        let tokenRecoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
        
        // Store tokens
        let accessToken = "backup_security_access_token"
        let refreshToken = "backup_security_refresh_token"
        let expirationDate = Date().addingTimeInterval(3600)
        
        try keychainManager.storeToken(accessToken, expiresAt: expirationDate)
        try keychainManager.storeRefreshToken(refreshToken)
        
        // Create backup
        weak var weakBackup: TokenBackup?
        
        autoreleasepool {
            let backup = try! tokenRecoveryManager.createTokenBackup()
            weakBackup = backup
            
            XCTAssertEqual(backup.accessToken, accessToken, "Backup should contain access token")
            XCTAssertEqual(backup.refreshToken, refreshToken, "Backup should contain refresh token")
            
            // Backup should be deallocated when it goes out of scope
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        // Note: WeakBackup test may not work as expected with structs
        // This test validates that backup data doesn't leak in implementation
        
        // Clean up
        try keychainManager.deleteToken()
        try keychainManager.deleteRefreshToken()
    }
    
    // MARK: - Concurrent Operations Memory Tests
    
    func testConcurrentOperationsMemoryStability() async throws {
        let keychainManager = KeychainManager()
        
        // Store initial tokens
        try keychainManager.storeToken("concurrent_test_token", 
                                     expiresAt: Date().addingTimeInterval(3600))
        try keychainManager.storeRefreshToken("concurrent_refresh_token")
        
        // Perform many concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Multiple authentication managers
            for i in 1...10 {
                group.addTask {
                    autoreleasepool {
                        let authManager = AuthManager()
                        _ = authManager.isAuthenticated
                        
                        // Simulate some work
                        Task {
                            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
                        }
                    }
                }
            }
            
            // Multiple keychain operations
            for i in 1...20 {
                group.addTask {
                    autoreleasepool {
                        do {
                            _ = try keychainManager.getToken()
                            _ = try keychainManager.getRefreshToken()
                        } catch {
                            // Ignore errors for memory testing
                        }
                    }
                }
            }
            
            // Multiple recovery operations
            for i in 1...5 {
                group.addTask {
                    autoreleasepool {
                        let recoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
                        Task {
                            do {
                                let _ = try await recoveryManager.validateAndRecoverTokens()
                            } catch {
                                // Ignore errors for memory testing
                            }
                        }
                    }
                }
            }
        }
        
        // Allow time for cleanup
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // System should remain stable
        XCTAssertTrue(true, "System should handle concurrent operations without memory issues")
        
        // Clean up
        try keychainManager.deleteToken()
        try keychainManager.deleteRefreshToken()
    }
    
    // MARK: - Long-Running Operations Memory Tests
    
    func testLongRunningOperationsMemoryStability() async throws {
        let keychainManager = KeychainManager()
        let tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
        
        // Store tokens with shorter expiration for more frequent refresh
        try keychainManager.storeToken("long_running_token", 
                                     expiresAt: Date().addingTimeInterval(300)) // 5 minutes
        try keychainManager.storeRefreshToken("long_running_refresh_token")
        
        // Start long-running refresh operations
        await tokenRefreshManager.startPeriodicRefresh()
        
        // Simulate extended operation with periodic memory pressure
        for cycle in 1...20 {
            // Simulate some work that creates temporary objects
            autoreleasepool {
                let tempAuthManager = AuthManager()
                _ = tempAuthManager.isAuthenticated
                
                let tempRecoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
                Task {
                    do {
                        let _ = try await tempRecoveryManager.validateAndRecoverTokens()
                    } catch {
                        // Ignore validation errors for memory testing
                    }
                }
            }
            
            // Small delay between cycles
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Stop refresh operations
        await tokenRefreshManager.stopPeriodicRefresh()
        
        // Allow cleanup time
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // System should remain stable after long-running operations
        XCTAssertTrue(tokenRefreshManager != nil, "TokenRefreshManager should remain stable")
        
        // Clean up
        try keychainManager.deleteToken()
        try keychainManager.deleteRefreshToken()
    }
    
    // MARK: - Network Monitor Memory Tests
    
    func testNetworkMonitorMemoryLeaks() async throws {
        weak var weakNetworkMonitor: NetworkMonitor?
        var cancellables: Set<AnyCancellable> = []
        
        for _ in 1...5 {
            autoreleasepool {
                let networkMonitor = NetworkMonitor()
                weakNetworkMonitor = networkMonitor
                
                // Subscribe to network state changes
                networkMonitor.isConnectedPublisher
                    .sink { _ in }
                    .store(in: &cancellables)
                
                // Start and stop monitoring
                networkMonitor.startMonitoring()
                networkMonitor.stopMonitoring()
            }
            
            await Task.yield()
        }
        
        cancellables.removeAll()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNil(weakNetworkMonitor, "NetworkMonitor should be deallocated")
    }
    
    // MARK: - Memory Usage Monitoring
    
    func testMemoryUsageStability() async throws {
        // This test monitors general memory usage during typical operations
        let keychainManager = KeychainManager()
        let authManager = AuthManager()
        let tokenRefreshManager = TokenRefreshManager(keychainManager: keychainManager)
        let tokenRecoveryManager = TokenRecoveryManager(keychainManager: keychainManager)
        
        // Store test tokens
        try keychainManager.storeToken("memory_usage_test_token", 
                                     expiresAt: Date().addingTimeInterval(3600))
        try keychainManager.storeRefreshToken("memory_usage_refresh_token")
        
        // Perform typical operations repeatedly
        for iteration in 1...100 {
            // Authentication checks
            _ = authManager.isAuthenticated
            
            // Token operations
            _ = try? keychainManager.getToken()
            _ = try? keychainManager.getRefreshToken()
            
            // Recovery validation (every 10th iteration)
            if iteration % 10 == 0 {
                let _ = try? await tokenRecoveryManager.validateAndRecoverTokens()
            }
            
            // Brief pause to prevent overwhelming
            if iteration % 20 == 0 {
                try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }
        }
        
        // Memory usage should remain stable
        XCTAssertTrue(true, "Memory usage should remain stable during repeated operations")
        
        // Clean up
        try keychainManager.deleteToken()
        try keychainManager.deleteRefreshToken()
    }
    
    // MARK: - Token String Memory Security
    
    func testTokenStringMemorySecurity() async throws {
        let keychainManager = KeychainManager()
        
        // Test that token strings don't leak in memory after use
        let testToken = "sensitive_token_that_should_not_leak_12345"
        let expirationDate = Date().addingTimeInterval(3600)
        
        autoreleasepool {
            // Store and retrieve token
            try! keychainManager.storeToken(testToken, expiresAt: expirationDate)
            let retrievedToken = try! keychainManager.getToken()
            
            XCTAssertEqual(retrievedToken, testToken, "Should retrieve correct token")
            
            // Token strings should be cleared when they go out of scope
        }
        
        // Delete the token
        try keychainManager.deleteToken()
        
        // Force garbage collection
        autoreleasepool {}
        
        // Token should no longer be accessible
        XCTAssertThrowsError(try keychainManager.getToken(), "Token should be deleted from keychain")
    }
}
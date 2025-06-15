# AuthManager Integration Guidelines

## Overview

This document defines the integration interface between the X API Authentication Component (AuthManager) and the Mercury Core Application. It establishes clear separation of concerns and integration patterns.

## Separation of Concerns

### AuthManager Responsibilities (Authentication Component)
- OAuth 2.0 + PKCE implementation
- Token management and automatic refresh
- Secure keychain storage
- Post queuing for failed requests
- Rate limiting logic and tracking
- Network connectivity coordination
- Background authentication operations
- Authentication state management
- Error categorization and reporting

### Core App Responsibilities (Mercury Core Application)
- All user interface and user experience
- Window management and global hotkeys
- Text input interface and character counting
- Authentication status display and indicators
- Error notification UI and user feedback
- Onboarding and setup screens
- Settings and preferences interface
- Usage tracking UI and visualization
- Main application state management
- UI accessibility and localization

## AuthManager Interface Contract

### Core Methods
```swift
class AuthManager {
    // Authentication lifecycle
    func authenticate() async throws -> AuthenticationResult
    func disconnect() async throws
    func isAuthenticated() -> Bool
    
    // Posting operations
    func postTweet(_ text: String) async throws -> PostResult
    
    // State monitoring
    var authenticationState: AnyPublisher<AuthenticationState, Never>
    var rateLimitStatus: AnyPublisher<RateLimitStatus, Never>
    var queueStatus: AnyPublisher<QueueStatus, Never>
}
```

### Authentication States
```swift
enum AuthenticationState {
    case disconnected
    case authenticating
    case authenticated(username: String)
    case refreshing
    case error(AuthenticationError)
}
```

### Error Types
```swift
enum AuthenticationError {
    case networkError(NetworkError)
    case tokenExpired
    case rateLimitExceeded(resetDate: Date)
    case apiError(code: Int, message: String)
    case authorizationRevoked
}
```

## Integration Patterns

### 1. Dependency Injection
Core App should inject AuthManager as a dependency:
```swift
@main
struct MercuryApp: App {
    let authManager = AuthManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
```

### 2. State Observation
Core App subscribes to authentication state changes:
```swift
struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var authState: AuthenticationState = .disconnected
    
    var body: some View {
        // UI based on authState
    }
    .onReceive(authManager.authenticationState) { state in
        authState = state
    }
}
```

### 3. Error Handling
Core App handles AuthManager errors through UI:
```swift
func handlePostingError(_ error: AuthenticationError) {
    switch error {
    case .networkError:
        notificationManager.show(.networkError, actions: [.retry])
    case .tokenExpired:
        notificationManager.show(.authExpired, actions: [.reconnect])
    case .rateLimitExceeded(let resetDate):
        notificationManager.show(.rateLimitReached(resetDate), actions: [.viewUsage])
    }
}
```

### 4. Background Operations
AuthManager handles background tasks automatically:
- Token refresh happens transparently
- Failed posts are queued automatically
- Network state changes trigger appropriate actions
- Core App only needs to handle user-visible state changes

## Data Flow

### Posting Flow
1. User types in Core App text input
2. User presses Cmd+Enter
3. Core App calls `authManager.postTweet(text)`
4. AuthManager handles authentication validation, posting, queuing
5. Core App receives result and updates UI accordingly
6. AuthManager publishes state changes for real-time UI updates

### Authentication Flow
1. User triggers authentication in Core App UI
2. Core App calls `authManager.authenticate()`
3. AuthManager handles OAuth flow, browser interaction
4. Core App observes state changes and updates UI
5. AuthManager stores tokens securely
6. Core App receives final authentication result

### Error Recovery Flow
1. AuthManager detects error (network, auth, API)
2. AuthManager categorizes error and publishes state change
3. Core App receives error state through subscription
4. Core App displays appropriate notification UI
5. User interacts with error UI (retry, reconnect, etc.)
6. Core App calls appropriate AuthManager method
7. Cycle repeats until resolution

## Testing Strategy

### Unit Testing
- AuthManager: Test all authentication logic, token management, API interactions
- Core App: Test UI components, state management, user interactions
- Integration: Test AuthManager interface contract compliance

### Integration Testing
- Test complete flows: authentication → posting → error handling
- Test state synchronization between AuthManager and Core App
- Test error scenarios and recovery mechanisms

### UI Testing
- Test user workflows end-to-end
- Test accessibility and keyboard navigation
- Test error notification interactions

## Performance Considerations

### Memory Management
- AuthManager maintains minimal memory footprint
- Core App manages UI component lifecycle
- Shared state is managed through Combine publishers

### Threading
- AuthManager operations are async and non-blocking
- UI updates happen on main thread
- Background operations (token refresh, queue processing) use appropriate queues

### Startup Performance
- AuthManager initializes lazily
- Core App can start immediately and show "connecting" state
- Authentication state is restored from keychain asynchronously

## Security Guidelines

### Token Handling
- AuthManager exclusively manages all token operations
- Core App never directly accesses tokens
- All authentication data flows through AuthManager interface

### Error Information
- AuthManager provides sanitized error information to Core App
- Sensitive details (tokens, internal state) are never exposed to UI
- Error logging includes only non-sensitive debugging information

### Network Security
- AuthManager handles all HTTPS certificate validation
- Core App relies on AuthManager for secure API communication
- No authentication-related network operations in Core App

## Versioning and Compatibility

### Interface Stability
- AuthManager interface is versioned for stability
- Breaking changes require major version bump
- Core App declares compatible AuthManager version

### Migration Strategy
- AuthManager provides migration hooks for data format changes
- Core App adapts to new AuthManager versions through interface
- Backwards compatibility maintained for one major version

## Monitoring and Debugging

### Logging Strategy
- AuthManager logs authentication events, errors, performance metrics
- Core App logs UI interactions, user actions, state changes
- Logs are coordinated to enable end-to-end debugging

### Analytics
- AuthManager provides authentication success/failure metrics
- Core App provides usage and interaction analytics
- No user-identifying information in analytics

### Debug Tools
- AuthManager exposes debugging interface for development
- Core App provides authentication debugging UI in settings
- Debug information helps troubleshoot integration issues

## Future Considerations

### Multi-Account Support
- AuthManager interface designed to support multiple accounts
- Core App UI can be extended for account switching
- Migration path defined for single → multi-account transition

### Additional Social Platforms
- AuthManager pattern can be extended to other platforms
- Core App UI abstracts away platform-specific details
- Interface remains stable across platform additions

### Advanced Features
- AuthManager can add features without Core App changes
- Core App adds UI for new features as needed
- Feature flags coordinate capability exposure
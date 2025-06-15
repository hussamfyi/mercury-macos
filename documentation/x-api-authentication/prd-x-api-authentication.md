# PRD: Mercury X API Authentication Component

## Introduction/Overview

Mercury is a macOS application designed for instant, frictionless idea capture and publishing to X (formerly Twitter). The X API Authentication Component is a critical foundation that enables users to authenticate once with their X account and then seamlessly post thoughts without any authentication friction.

The core problem this component solves is eliminating authentication barriers that break the "instant capture" user experience. Any authentication delays, prompts, or failures during posting would undermine Mercury's primary value proposition of capturing authentic thoughts before self-doubt sets in.

**Goal**: Create a robust, invisible authentication system that handles all X API OAuth complexities while maintaining Mercury's core promise of frictionless posting.

## Goals

1. **One-time Setup**: Enable users to authenticate with X in under 2 minutes during initial setup
2. **Invisible Operation**: Achieve 99%+ success rate for posts without users seeing auth-related errors
3. **Automatic Recovery**: Handle token expiration and refresh automatically in the background
4. **Graceful Degradation**: Preserve user input and provide clear guidance when authentication issues occur
5. **Reliability**: Maintain authentication state across Mac sleep/wake cycles and network changes
6. **Security**: Store credentials securely using macOS Keychain with proper encryption

## User Stories

- **As a new Mercury user**, I want to connect my X account once during setup so that I can immediately start posting my thoughts without repeated authentication prompts.

- **As a daily Mercury user**, I want my posts to go through instantly via the hotkey without any authentication delays, so that I can capture fleeting thoughts before they disappear.

- **As a Mercury user experiencing auth issues**, I want to see a subtle notification about reconnection needs without losing my current text input, so that my thought process isn't interrupted.

- **As a Mercury user with expired tokens**, I want the app to automatically refresh my authentication in the background so that I never notice token expiration.

- **As a Mercury user when X API is down**, I want my posts to be queued locally and automatically retried when service is restored, so that I don't lose my content.

## Functional Requirements

### Core Authentication Flow
1. The system must implement OAuth 2.0 Authorization Code + PKCE flow (not OAuth 1.0a)
2. The system must request these specific scopes: "tweet.read users.read tweet.write offline.access"
3. The system must handle local redirect using a temporary localhost HTTP server on a random available port
4. The system must securely store access tokens, refresh tokens, and user credentials in macOS Keychain
5. The system must validate successful authentication by making a test API call to verify token functionality

### Token Management
6. The system must automatically refresh access tokens before the 2-hour expiration using stored refresh tokens
7. The system must handle refresh token expiration by triggering a re-authentication flow
8. The system must implement exponential backoff for failed token refresh attempts
9. The system must persist token refresh state across app restarts and Mac sleep/wake cycles
10. The system must proactively refresh tokens 15 minutes before expiration to avoid race conditions

### Integration Interface
11. The system must provide an AuthManager class with these methods: `authenticate()`, `postTweet(text)`, `isAuthenticated()`, `disconnect()`
12. The system must emit events for authentication state changes (authenticated, disconnected, error)
13. The system must never expose OAuth implementation details to the main Mercury application
14. The system must provide synchronous status checks and asynchronous authentication operations

### Error Handling
15. The system must display subtle, non-modal notifications for authentication issues
16. The system must preserve user text input during any authentication error scenarios
17. The system must queue failed posts locally and automatically retry after successful reconnection
18. The system must provide specific error messages for different failure scenarios (API down, rate limited, network issues, auth expired)
19. The system must include a "Reconnect" button that initiates the full authentication flow when needed

### Rate Limiting & API Management
20. The system must track and respect X API Free tier limits (500 posts/month)
21. The system must provide clear feedback when rate limits are approached or exceeded
22. The system must handle HTTP 429 (Too Many Requests) responses gracefully
23. The system must implement appropriate request retry logic with exponential backoff

## Non-Goals (Out of Scope)

- **Multiple Account Support**: This version will only support one X account per Mercury installation
- **Advanced Tweet Features**: No support for threads, polls, media attachments, or scheduling in this initial version
- **Analytics/Metrics**: No built-in analytics for posting success rates or user engagement
- **Custom API Endpoints**: Will only support standard X API v2 endpoints, no custom or experimental endpoints
- **OAuth 1.0a Support**: Will not maintain backward compatibility with OAuth 1.0a
- **Cross-platform Support**: macOS-specific implementation only, no Windows or Linux considerations

## Design Considerations

### User Interface
- Authentication setup should integrate with Mercury's existing onboarding flow
- Error notifications should match Mercury's design language (subtle, non-intrusive)
- "Reconnect" button should be easily accessible but not prominent during normal usage
- Status indicators should be minimal and contextual

### User Experience Flow
1. **Initial Setup**: Single "Connect to X" button → browser opens → user authorizes → automatic redirect → setup complete
2. **Normal Usage**: Completely invisible - user types and posts without seeing any auth interface
3. **Error Recovery**: Subtle notification appears → user clicks "Reconnect" when convenient → same auth flow as initial setup

## Technical Considerations

### Dependencies
- Must integrate with existing Mercury SwiftUI architecture
- Should leverage Foundation's URL loading system for HTTP requests
- Must use Security framework for Keychain operations
- Consider using Combine framework for event-driven authentication state management

### Security Requirements
- All tokens must be stored in macOS Keychain with appropriate access controls
- HTTP redirect server must bind to localhost only and use random ports
- Client secret (if required) must be securely embedded or omitted per OAuth PKCE best practices
- All API communications must use HTTPS with certificate validation

### Performance Considerations
- Token refresh operations must not block the main UI thread
- Background token refresh should occur during app idle time when possible
- Network timeouts should be configured appropriately (30 seconds for auth, 10 seconds for posts)

### Testing Strategy
- Create standalone CLI tool to validate complete OAuth flow before integration
- Test token refresh scenarios with artificially expired tokens
- Test posting functionality end-to-end with real X API
- Load test approach to 500 posts/month limit
- Test authentication persistence across app restarts

## Success Metrics

### User Experience Metrics
- **Setup Time**: Average authentication setup completes in under 2 minutes
- **Post Success Rate**: 99%+ of posts succeed without user-visible authentication errors
- **Error Recovery Time**: Users can recover from auth errors in under 30 seconds

### Technical Metrics
- **Token Refresh Success Rate**: 99%+ of automatic token refreshes succeed
- **Background Operation Success**: Authentication operations don't block UI for more than 100ms
- **Persistence Reliability**: Authentication state survives 100% of app restarts and Mac sleep/wake cycles

### Quality Metrics
- **Zero Data Loss**: No user text input is ever lost due to authentication failures
- **Graceful Degradation**: All error scenarios provide clear, actionable user guidance
- **Rate Limit Compliance**: Stay within X API Free tier limits with appropriate user feedback

## Development Phases

### Phase 1: OAuth Flow Validation (Week 1)
- Create standalone CLI tool for testing OAuth 2.0 + PKCE flow
- Validate authorization endpoint, token exchange, and basic API calls
- Test with X API Free tier account
- Document any X Developer Portal setup requirements

### Phase 2: Token Management & Persistence (Week 2)  
- Implement secure token storage in macOS Keychain
- Build automatic token refresh logic with proper timing
- Test persistence across various system states
- Handle all token expiration and refresh scenarios

### Phase 3: Main App Integration (Week 3)
- Create AuthManager class with clean interface
- Integrate with Mercury's existing architecture
- Implement event-driven state management
- Build basic error notification system

### Phase 4: Advanced Error Handling (Week 4)
- Implement post queuing and retry logic
- Add comprehensive error messaging
- Build rate limiting awareness and feedback
- Performance testing and optimization

### Phase 5: User Interface & Experience Implementation (Week 5)
- Design and implement authentication setup screens
- Build onboarding flow integration with existing Mercury UI
- Create subtle error notification system with Mercury design language
- Implement reconnection flow and status indicators
- Build authentication settings and management screens
- Create user feedback for rate limiting and usage tracking
- Integrate authentication state with main Mercury posting interface

### Phase 6: End-to-End Testing & Polish (Week 6)
- Comprehensive user acceptance testing across all authentication flows
- Performance optimization and memory leak detection
- Edge case testing (network failures, token corruption, API downtime)
- Load testing for rate limit scenarios and high-frequency usage
- Beta testing with real users for authentication edge cases
- Final security audit and penetration testing
- Documentation completion and deployment preparation

## Open Questions

1. **X Developer Portal Setup**: What specific app configuration is required in the X Developer Portal for Mercury? Should this be documented as part of the setup process?

2. **Rate Limit Strategy**: Should Mercury proactively warn users as they approach the 500 posts/month limit, or only notify when exceeded?

3. **Network Connectivity**: How should the component handle scenarios where the Mac has no internet connection during posting attempts?

4. **Token Security**: Are there additional security considerations for storing X API tokens beyond standard macOS Keychain practices?

5. **Error Analytics**: Should the component collect any anonymized error metrics to help improve reliability, or maintain complete user privacy?

6. **Beta Testing**: What specific authentication edge cases should be prioritized for beta testing with real users?
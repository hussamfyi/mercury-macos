# Mercury Authentication Module

## Phase 2: Token Management & Persistence

This module contains all authentication-related components for the Mercury macOS app, building on the validated OAuth 2.0 + PKCE implementation from Phase 1 (mercury-cli-auth).

## Architecture

### Core Components

- **AuthManager.swift** - Main authentication interface for the app
  - Clean async API: `authenticate()`, `postTweet()`, `isAuthenticated()`, `disconnect()`
  - Event-driven state management using Combine
  - Integrates all other authentication components

- **KeychainManager.swift** - Secure token storage
  - Uses macOS Security framework
  - Encrypted storage for refresh tokens
  - Proper access controls for sensitive data

- **TokenRefreshManager.swift** - Background token refresh
  - Proactive refresh 15 minutes before expiration
  - Exponential backoff for failures
  - Network-aware retry logic

- **AuthenticationState.swift** - State management models
  - Authentication state enum (authenticated, disconnected, refreshing, error)
  - Combine publishers for reactive UI updates
  - Error models for different failure scenarios

### Advanced Features

- **PostQueueManager.swift** - Local post queuing and retry
  - Stores failed posts locally with Core Data or UserDefaults
  - Automatic retry with exponential backoff
  - Survives app restarts and system sleep/wake

- **RateLimitManager.swift** - X API rate limit management
  - Tracks usage against 500 posts/month Free tier limit
  - Proactive user notifications at 400/500 threshold
  - Handles HTTP 429 responses gracefully

### Integration

- **Extensions/OAuthManager+App.swift** - OAuth integration
  - Extends Phase 1 OAuth components for app use
  - Bridges CLI validation components to app architecture

- **Services/NetworkMonitor.swift** - Network connectivity
  - Monitors connection state using Network framework
  - Triggers automatic queue processing when online
  - Handles timeout scenarios (30s auth, 10s posts)

## Testing

All components include comprehensive unit tests following XCTest patterns established in Phase 1.

## Dependencies

- Phase 1 OAuth components (mercury-cli-auth)
- macOS Security framework (Keychain)
- Network framework (connectivity monitoring)
- Combine framework (reactive state management)
- Core Data or UserDefaults (local storage) 
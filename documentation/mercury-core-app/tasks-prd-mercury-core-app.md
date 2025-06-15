# Tasks for Mercury Core Application V1

## Relevant Files

### Core Application Files
- `mercury-macos/Services/HotkeyService.swift` - Global hotkey registration and management service using NSEvent monitoring with conflict detection and user notifications (✓ Enhanced)
- `mercury-macos/Models/PreferencesManager.swift` - UserDefaults-based preferences management with hotkey configuration (✓ Created)
- `mercury-macos/Views/PreferencesView.swift` - SwiftUI preferences interface with hotkey recording and preset options (✓ Created)
- `mercury-macos/Views/MercuryWindow.swift` - Main floating window component with borderless, floating styling (✓ Created)
- `mercury-macos/Utils/WindowManager.swift` - Window lifecycle management with toggle behavior, multi-display positioning, session persistence, drag handling, focus management, text preservation, and macOS system integration (✓ Enhanced)
- `mercury-macos/Services/HotkeyService.test.swift` - Unit tests for HotkeyService
- `mercury-macos/Views/MercuryWindow.test.swift` - Unit tests for MercuryWindow
- `mercury-macos/Views/TextInputView.swift` - Text input field with placeholder, auto-resize, scrolling, keyboard shortcuts, and focus management (✓ Enhanced)
- `mercury-macos/Views/TextInputView.test.swift` - Unit tests for TextInputView
- `mercury-macos/Utils/WindowManager.test.swift` - Unit tests for WindowManager

### Posting and Authentication Integration Files
- `mercury-macos/MercuryApp.swift` - Main app entry point with AuthManager integration via AuthManagerWrapper (✓ Enhanced)
- `mercury-macos/Models/AppState.swift` - App state management with authentication state tracking and AuthManager integration (✓ Enhanced)
- `mercury-macos/Views/ContentView.swift` - Root view with AuthManager configuration and authentication status display (✓ Enhanced)
- `mercury-macos/Utils/WindowManager.swift` - Window management with AuthManager integration for posting functionality (✓ Enhanced)
- `mercury-macos/Services/TwitterPostingService.swift` - X API posting integration using AuthManager with comprehensive state management and error handling (✓ Created)
- `mercury-macos/Services/TwitterPostingService.test.swift` - Unit tests for TwitterPostingService
- `mercury-macos/Models/PostingState.swift` - Comprehensive data models for posting states with authentication awareness, connection status, error handling, and UI integration (✓ Created)
- `mercury-macos/Models/PostingState.test.swift` - Unit tests for PostingState
- `mercury-macos/Views/StatusIndicatorView.swift` - Authentication status display component with enhanced animated indicators and accessibility support (✓ Enhanced)
- `mercury-macos/Views/StatusIndicatorView.test.swift` - Unit tests for StatusIndicatorView
- `mercury-macos/Views/AnimatedStatusIndicators.swift` - Smooth animated status indicators for all authentication states with transition effects and compact variants (✓ Created)
- `mercury-macos/Views/DiscreteStatusIndicators.swift` - Discrete connection status indicators with hover details, tooltips, and accessibility support (✓ Enhanced)
- `mercury-macos/Views/ContextualReconnectButton.swift` - Contextual reconnect button with intelligent placement and accessibility support (✓ Enhanced)
- `mercury-macos/Services/AuthenticationPersistenceService.swift` - Authentication status persistence and recovery service across app sessions with connection history tracking (✓ Created)

### Error Handling and Notification Files
- `mercury-macos/Services/ErrorHandlingService.swift` - Centralized error handling for posting and authentication
- `mercury-macos/Services/ErrorHandlingService.test.swift` - Unit tests for ErrorHandlingService
- `mercury-macos/Services/NotificationManager.swift` - Notification system for error and status feedback
- `mercury-macos/Services/NotificationManager.test.swift` - Unit tests for NotificationManager
- `mercury-macos/Views/Components/NotificationBanner.swift` - Notification UI components
- `mercury-macos/Views/Components/NotificationBanner.test.swift` - Unit tests for NotificationBanner

### Authentication UI and Onboarding Files
- `mercury-macos/Views/Onboarding/OnboardingView.swift` - Main onboarding flow container with authentication setup
- `mercury-macos/Views/Onboarding/OnboardingView.test.swift` - Unit tests for OnboardingView
- `mercury-macos/Views/Onboarding/AuthSetupView.swift` - Authentication setup screens and progress tracking
- `mercury-macos/Views/Onboarding/AuthSetupView.test.swift` - Unit tests for AuthSetupView
- `mercury-macos/Views/Settings/AuthenticationSettingsView.swift` - Authentication management settings interface
- `mercury-macos/Views/Settings/AuthenticationSettingsView.test.swift` - Unit tests for AuthenticationSettingsView
- `mercury-macos/Views/Components/ConnectionStatusView.swift` - Connection status indicators and reconnection UI
- `mercury-macos/Views/Components/ConnectionStatusView.test.swift` - Unit tests for ConnectionStatusView

### Usage Tracking and Rate Limiting Files
- `mercury-macos/Views/Settings/UsageTrackingView.swift` - Rate limit and usage display interface
- `mercury-macos/Views/Settings/UsageTrackingView.test.swift` - Unit tests for UsageTrackingView
- `mercury-macos/Views/Components/UsageProgressView.swift` - Usage tracking UI components
- `mercury-macos/Views/Components/UsageProgressView.test.swift` - Unit tests for UsageProgressView

### Notes

- Unit tests should be placed alongside the code files they are testing in the same directory
- Use `xcodebuild test -scheme mercury-macos` to run all tests for the project
- Tests can be run individually in Xcode using Cmd+U or by right-clicking on specific test methods

## Tasks

- [x] 1.0 Implement Global Hotkey System and Window Management
  - [x] 1.1 Create HotkeyService.swift to register global hotkey (default Cmd+Space) using modern NSEvent APIs
  - [x] 1.2 Implement hotkey conflict detection and user notification system
  - [x] 1.3 Add hotkey configuration support in app preferences
  - [x] 1.4 Create MercuryWindow.swift with borderless, floating window styling
  - [x] 1.5 Implement window positioning logic for primary display and session persistence
  - [x] 1.6 Add window dragging functionality for user repositioning
  - [x] 1.7 Implement toggle behavior (show/hide) for the same hotkey
  - [x] 1.8 Add proper focus management and integration with macOS window system

- [x] 2.0 Build Core Text Input Interface with Character Counter
  - [x] 2.1 Create TextInputView.swift with placeholder text "What's on your mind?"
  - [x] 2.2 Implement live character counter showing used/280 limit
  - [x] 2.3 Add auto-resize functionality for window height based on text content
  - [x] 2.4 Implement maximum height limit with scrolling for long text
  - [x] 2.5 Add text preservation when window is hidden/restored during session
  - [x] 2.6 Implement character limit enforcement (allow typing but disable posting)
  - [x] 2.7 Add keyboard shortcuts (Escape to hide, Cmd+Enter to post)
  - [x] 2.8 Ensure immediate focus on text field when window appears

- [x] 3.0 Implement X API Posting Integration and State Management
  - [x] 3.1 Integrate AuthManager service from X API Authentication Component into core app
  - [x] 3.2 Create TwitterPostingService.swift that uses AuthManager for all X API operations
  - [x] 3.3 Implement PostingState.swift model (idle, loading, success, error states) with authentication awareness
  - [x] 3.4 Add posting flow with Cmd+Enter trigger and loading state display
  - [x] 3.5 Implement circular progress indicator during posting with authentication status integration
  - [x] 3.6 Add text field disabling during posting attempts and authentication operations
  - [x] 3.7 Create success state with confirmation and tweet link display
  - [x] 3.8 Implement auto-clear and auto-hide after successful posting (2-3 seconds)
  - [x] 3.9 Add network timeout handling (10 seconds max) coordinated with AuthManager timeouts
  - [x] 3.10 Implement posting queue integration for offline/failed authentication scenarios
  - [x] 3.11 Add authentication state change handling in posting flow
  - [x] 3.12 Create posting button state management based on authentication status

- [ ] 4.0 Create Authentication Status Display and Connection Management
  - [x] 4.1 Create StatusIndicatorView.swift for connection status display in main Mercury interface
  - [x] 4.2 Implement "Connected to @username" with green dot for authenticated state
  - [x] 4.3 Add red status indicator and posting prevention when not authenticated
  - [x] 4.4 Create streamlined reconnection UI flow that mirrors initial setup
  - [x] 4.5 Design ultra-subtle authentication status indicators that integrate with Mercury's minimalist design
  - [x] 4.6 Implement contextual "Reconnect" button placement with intelligent visibility rules
  - [x] 4.7 Add discrete connection status indicator with hover details and tooltips
  - [x] 4.8 Create smooth animated status indicators for all authentication states (connecting, connected, error)
  - [x] 4.9 Implement status indicator accessibility support (VoiceOver, keyboard navigation)
  - [x] 4.10 Add authentication status persistence and recovery across app sessions
  - [ ] 4.11 Create authentication debugging tools and connection testing interface
  - [x] 4.12 Implement connected account display (username, avatar, connection status, last activity)

- [ ] 5.0 Implement Error Handling and User Feedback System
  - [ ] 5.1 Create ErrorHandlingService.swift for centralized error management (posting and authentication)
  - [ ] 5.2 Implement clear, actionable error messages for posting and authentication failures
  - [ ] 5.3 Add text preservation during all error scenarios (posting, authentication, network)
  - [ ] 5.4 Create NotificationManager class with queue management and priority handling
  - [ ] 5.5 Design notification banner UI components matching Mercury's minimalist design language
  - [ ] 5.6 Implement non-blocking notification display using SwiftUI overlays and animations
  - [ ] 5.7 Add intelligent notification dismissal (auto-hide 8s, manual dismiss, swipe gestures)
  - [ ] 5.8 Create notification priority system (critical, warning, info) with visual distinctions
  - [ ] 5.9 Integrate notifications with AuthManager state changes and posting error conditions
  - [ ] 5.10 Add notification action buttons (Retry, Settings, Dismiss) with proper handling
  - [ ] 5.11 Implement notification persistence for critical errors across app sessions
  - [ ] 5.12 Create notification accessibility support (VoiceOver announcements, reduced motion)
  - [ ] 5.13 Implement retry functionality for failed posts with exponential backoff
  - [ ] 5.14 Add offline scenario detection and appropriate error messaging
  - [ ] 5.15 Create comprehensive error state UI with retry options and recovery guidance
  - [ ] 5.16 Add network connectivity monitoring and automatic recovery
  - [ ] 5.17 Implement graceful degradation for various API and authentication error responses
  - [ ] 5.18 Create contextual error messages based on authentication state and user action

- [ ] 6.0 Implement Authentication Setup and Onboarding UI
  - [ ] 6.1 Create OnboardingView.swift with step-by-step authentication setup flow and progress tracking
  - [ ] 6.2 Design prominent "Connect to X" button with Mercury's design language and loading states
  - [ ] 6.3 Implement animated setup progress indicators with clear status messages and time estimates
  - [ ] 6.4 Create seamless browser redirect handling with user feedback and timeout recovery
  - [ ] 6.5 Add setup completion confirmation with success animation and clear next steps
  - [ ] 6.6 Implement comprehensive setup error handling with retry options and help links
  - [ ] 6.7 Test setup flow across different Mac screen sizes and user interaction patterns
  - [ ] 6.8 Add setup cancellation and resume functionality with state preservation
  - [ ] 6.9 Create setup accessibility support (VoiceOver, keyboard navigation, high contrast)
  - [ ] 6.10 Integrate authentication setup into Mercury's existing onboarding flow
  - [ ] 6.11 Create onboarding step management with clear progress indicators and navigation controls
  - [ ] 6.12 Implement intelligent skip/later options with reminders and re-engagement prompts

- [ ] 7.0 Build Authentication Settings and Management Interface
  - [ ] 7.1 Create AuthenticationSettingsView.swift with clear account management interface
  - [ ] 7.2 Add connected account display (username, avatar, connection status, last activity)
  - [ ] 7.3 Implement safe disconnect/reconnect functionality with confirmation dialogs and data preservation
  - [ ] 7.4 Create authentication debugging and diagnostic tools for troubleshooting
  - [ ] 7.5 Add detailed token expiration and refresh status display with countdown timers
  - [ ] 7.6 Implement secure settings export/import functionality for debugging and migration
  - [ ] 7.7 Create comprehensive help documentation and troubleshooting guides
  - [ ] 7.8 Add authentication verification tools and connection testing
  - [ ] 7.9 Implement settings accessibility support (VoiceOver, keyboard navigation)

- [ ] 8.0 Create Usage Tracking and Rate Limit Management UI
  - [ ] 8.1 Design beautiful usage tracking UI components (animated progress bars, counters, charts)
  - [ ] 8.2 Create clear monthly usage display with reset date countdown and visual indicators
  - [ ] 8.3 Implement smart usage projection and early warning systems based on usage patterns
  - [ ] 8.4 Add detailed usage history tracking with trends and insights visualization
  - [ ] 8.5 Create customizable usage limit notification preferences (thresholds, timing, methods)
  - [ ] 8.6 Implement usage data export functionality for user analysis and record keeping
  - [ ] 8.7 Test usage tracking UI with various posting patterns and edge cases
  - [ ] 8.8 Add usage optimization suggestions and posting behavior insights
  - [ ] 8.9 Create usage comparison features (month-over-month, goal tracking)
  - [ ] 8.10 Integrate usage tracking with posting interface to show real-time status
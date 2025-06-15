Based on the tasks and files you've created in Phase 5, can you help me understand how you've visualized what the difference UI components are and what the screens are that I need to design? I can get a headstart on these by mocking things up in Figma.

⏺ Based on the Phase 5 tasks and files, here are the key UI components and screens you'll need to design in Figma:

  1. Onboarding/Setup Screens

  Files: OnboardingView.swift, AuthSetupView.swift,
  SetupProgressView.swift

  - Initial Setup Screen: Single "Connect to X" button, Mercury branding, progress indicator
  - Browser Redirect Screen: "Opening browser..." with spinner, cancel option
  - Setup Progress Screen: Step indicators (1. Authorize
   2. Connecting 3. Complete)
  - Success Screen: Checkmark, "Connected to X successfully", continue button
  - Error Screen: Retry button, "Try Again" or "Skip for
   Now" options

  2. Main App Integration Elements

  Files: ContentView+Auth.swift,
  AuthStatusIndicator.swift

  - Text Input Area: Subtle auth status indicator (green
   dot = connected, red = disconnected)
  - Post Button States: Normal, disabled (not
  authenticated), posting, error
  - Inline Status Messages: "Not connected to X" warning
   below text input
  - Queue Status: Small indicator showing "3 posts
  queued" when offline

  3. Notification System

  Files: NotificationBanner.swift,
  AuthNotificationView.swift

  - Subtle Banner Notifications: Slide-in from top,
  non-blocking
  - Error Notification: Red accent, "Connection lost"
  with "Reconnect" button
  - Warning Notification: Yellow accent, "Approaching
  rate limit (450/500)"
  - Success Notification: Green accent, "Reconnected
  successfully"
  - Action Buttons: Dismiss (X), Retry, Settings

  4. Status Indicators & Reconnection

  Files: ConnectionStatusView.swift

  - Menu Bar Status: Small X logo with connection
  indicator (green/red/yellow)
  - Reconnect Flow: Modal similar to initial setup but
  labeled "Reconnect to X"
  - Connection States: Connected (green), Disconnected
  (red), Refreshing (yellow pulse)

  5. Settings/Management Screens

  Files: AuthenticationSettingsView.swift,
  UsageTrackingView.swift

  - Account Display: User avatar, @username, "Connected"
   status badge
  - Usage Tracking: Progress bar showing "127/500 posts
  this month"
  - Rate Limit Display: Circular progress, "373 posts
  remaining", "Resets Jan 1"
  - Management Actions: "Disconnect Account",
  "Reconnect", "View Diagnostics"
  - Debug Panel: Token status, last refresh time, error
  logs

  6. Usage Tracking Components

  Files: UsageProgressView.swift

  - Monthly Usage Widget: Donut chart with posts
  used/remaining
  - Usage History: Simple line graph of daily posting
  activity
  - Warning Thresholds: Visual indicators at 80% and 95%
   usage

  Design Considerations:

  - Mercury's Design Language: Minimal, subtle,
  non-intrusive
  - Color Scheme: Likely matches Mercury's existing
  palette
  - Typography: Clean, readable system fonts
  - Animations: Smooth slide-ins, subtle state
  transitions
  - Dark Mode: Support for macOS appearance preferences

  The key principle is invisible when working, helpful 
  when not - most users should rarely see these screens
  after initial setup, but when they do, the experience
  should be clear and actionable.
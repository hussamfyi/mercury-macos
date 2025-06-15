# PRD: Mercury Core Application V1

## Introduction/Overview

Mercury is a macOS application designed for instant, frictionless idea capture and authentic sharing to X (formerly Twitter). The core problem Mercury solves is eliminating the friction, distractions, and context-switching that prevent users from sharing raw, authentic thoughts online.

Currently, posting to X requires opening a browser, navigating to x.com, and getting pulled into the algorithmic feed - breaking focus and preventing authentic expression. Mercury provides a globally accessible, lightning-fast posting interface that appears instantly via hotkey, allowing users to capture and share thoughts without leaving their current context.

**Goal**: Create the fastest possible path from thought to published tweet, enabling users to treat X as a frictionless public journal and build consistent sharing habits.

## Goals

1. **Instant Access**: Global hotkey summons Mercury in <100ms, ready to type immediately
2. **Zero Context Switching**: Post thoughts without leaving current application or workflow
3. **Authentic Expression**: Remove barriers that lead to overthinking or self-censorship
4. **Habit Formation**: Enable consistent daily posting through minimal friction
5. **Reliable Performance**: 99%+ posting success rate with clear error recovery
6. **Speed Optimization**: Complete posting flow (hotkey → type → post) achievable in under 5 seconds

## User Stories

- **As someone working on my Mac**, I want to instantly share my ideas without switching away from my work, so I can capture authentic thoughts in real-time.

- **As an active X user**, I want to post raw, unfiltered thoughts immediately when they occur, so I can build a habit of consistent authentic sharing rather than consuming content.

- **As someone avoiding X's algorithmic distractions**, I want to post without opening x.com, so I can share ideas without getting pulled into the feed and losing focus.

- **As someone building online presence**, I want frictionless posting to encourage more frequent sharing, so I can develop my voice and distribution advantage through consistent content creation.

- **As someone with fleeting thoughts**, I want to capture ideas before they disappear, so I can preserve and share insights that would otherwise be lost to distraction or self-doubt.

## Functional Requirements

### Core Posting Interface
1. The system must provide a global hotkey (configurable, default: Cmd+Space) that instantly summons Mercury's floating window
2. The system must display a focused text input field immediately upon window appearance, ready for typing
3. The system must support the same hotkey to hide/show Mercury (toggle behavior)
4. The system must allow users to drag the window to reposition it anywhere on screen
5. The system must remember window position between uses within the same session

### Text Input & Character Management
6. The system must provide a text input field with placeholder text ("What's on your mind?")
7. The system must display a live character counter showing characters used vs. 280 limit
8. The system must allow typing beyond 280 characters but disable posting when limit exceeded
9. The system must auto-resize window height as text content grows, up to a maximum height with scrolling
10. The system must preserve entered text when Mercury is hidden and restored during the same session

### Posting Flow & States
11. The system must post content via Cmd+Enter keyboard shortcut
12. The system must show a loading state with circular progress indicator during posting
13. The system must disable text editing during posting attempts
14. The system must display success state with brief confirmation and link to posted tweet
15. The system must automatically clear text field and hide Mercury 2-3 seconds after successful posting
16. The system must revert to editable state with error message if posting fails, preserving user text

### Authentication & Connection Status
17. The system must display connection status indicator showing "Connected to @username" with green dot when authenticated
18. The system must show red status indicator and prevent posting when not authenticated
19. The system must integrate with existing X API authentication system for seamless token management
20. The system must handle authentication errors gracefully with clear reconnection options

### Window Behavior & Navigation
21. The system must hide Mercury window when Escape key is pressed
22. The system must appear on the primary display in multi-monitor setups
23. The system must maintain focus on text input field when window is active
24. The system must handle loss of focus gracefully without interfering with other applications

### Error Handling & Recovery
25. The system must provide clear, actionable error messages for posting failures (network, API, authentication)
26. The system must preserve user text during all error scenarios
27. The system must offer retry functionality for failed posts
28. The system must handle offline scenarios with appropriate error messaging

## Non-Goals (Out of Scope)

- **Rich Text Formatting**: No bold, italics, or text styling in V1
- **Media Attachments**: No image, video, or file upload support
- **Thread Support**: No multi-tweet thread creation or management
- **Post History/Journaling**: No local storage, history, or browsing of past posts
- **Multiple Account Support**: Single X account per Mercury installation only
- **Advanced Analytics**: No detailed posting statistics or engagement metrics
- **Multi-Platform Support**: macOS only, no Windows or Linux versions
- **Link Previews**: No URL preview generation or rich link cards
- **Draft Management**: No persistent draft storage beyond current session
- **Scheduling**: No delayed or scheduled posting functionality
- **Content Creator Features**: No advanced formatting, analytics, or multi-platform posting

## Design Considerations

### User Interface Design
- **Minimalist Aesthetic**: Clean, distraction-free interface focused solely on text input
- **Floating Window**: Borderless, modern floating window similar to ChatGPT or Raycast
- **Visual Hierarchy**: Character counter, status indicator, and posting state clearly visible but unobtrusive
- **Responsive Layout**: Window adapts to content length while maintaining consistent width

### User Experience Flow
1. **Summon**: Hotkey → Mercury appears instantly, text field focused
2. **Compose**: Type thought, see character count, status confirmation
3. **Post**: Cmd+Enter → loading state → success confirmation → auto-hide
4. **Error Recovery**: Failed post → show error → retry option → preserve text

### Interaction Patterns
- **Keyboard-First**: All primary actions accessible via keyboard shortcuts
- **Instant Feedback**: Visual response to all user actions within 100ms
- **Graceful States**: Smooth transitions between normal, loading, success, and error states
- **Context Preservation**: Never lose user text except on successful posting

## Technical Considerations

### Architecture Requirements
- **SwiftUI Framework**: Native macOS application using SwiftUI for modern, responsive UI
- **Global Hotkey Support**: Integration with macOS accessibility APIs for system-wide hotkey registration
- **Window Management**: Custom window styling (borderless, always-on-top when active, proper focus handling)
- **Memory Efficiency**: Minimal memory footprint when running in background

### Performance Requirements
- **Instant Summoning**: Window appears in <100ms after hotkey press
- **Real-time Responsiveness**: Character counting and UI updates with zero lag
- **Background Efficiency**: Minimal CPU/memory usage when hidden
- **Network Optimization**: Fast posting with proper timeout handling (10 seconds max)

### Integration Dependencies
- **X API Authentication**: Leverage existing Mercury authentication system for OAuth and token management
- **macOS Permissions**: Request accessibility permissions for global hotkey functionality
- **System Integration**: Proper integration with macOS window management and focus behavior

### Data Management
- **Session Persistence**: Text content persists only during app session (lost on restart)
- **Stateless Design**: No local database or persistent storage requirements
- **Secure Token Handling**: Use existing keychain-based authentication token storage

## Success Metrics

### User Experience Metrics
- **Speed**: Hotkey to ready-to-type state in <100ms
- **Posting Success Rate**: 99%+ of posting attempts succeed without user-visible errors
- **Error Recovery Time**: Users can retry failed posts within 5 seconds
- **Workflow Integration**: Zero disruption to user's current application focus

### Performance Metrics
- **Memory Usage**: <25MB RAM usage when running in background
- **CPU Impact**: <1% CPU usage when idle, <5% during active use
- **Network Efficiency**: Post requests complete within 3 seconds under normal conditions
- **Battery Impact**: Negligible battery drain when running continuously

### Adoption & Habit Metrics
- **Daily Usage**: Users posting multiple times per day after first week
- **Session Efficiency**: Average time from hotkey to posted tweet <10 seconds
- **Error-Free Sessions**: 95%+ of posting sessions complete without requiring error handling
- **Retention**: Users continue using Mercury daily after first month

## Open Questions

1. **Hotkey Conflicts**: How should Mercury handle conflicts with existing system or application hotkeys? Should it detect conflicts during setup?

2. **Window Positioning**: Should Mercury remember window position across app restarts, or always start in a default position (e.g., center screen)?

3. **Network Resilience**: For temporary network issues, should Mercury automatically retry posting after connection is restored, or require manual retry?

4. **Authentication Persistence**: How long should Mercury maintain authenticated sessions before requiring re-authentication? Should this align with X's token expiration?

5. **Onboarding Complexity**: What's the minimum viable onboarding flow that ensures users understand permissions, hotkey setup, and X authentication without overwhelming them?

6. **Error Logging**: Should Mercury collect any anonymized error data to improve reliability, or maintain complete user privacy with no telemetry?

7. **macOS Integration**: Should Mercury integrate with macOS notification system for posting confirmations, or keep all feedback within the app interface?

8. **Accessibility Standards**: Beyond basic keyboard navigation, what additional accessibility features are essential for users with disabilities?
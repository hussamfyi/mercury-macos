//
//  ContextualReconnectButton.swift
//  Mercury
//
//  Created by Claude on 2025-06-15.
//

import SwiftUI
import Combine

// MARK: - Contextual Reconnect Button with Intelligent Visibility

struct ContextualReconnectButton: View {
    @ObservedObject var windowManager: WindowManager
    let placement: ButtonPlacement
    @State private var showingReconnection = false
    @State private var lastDisconnectionTime: Date?
    @State private var userDismissedRecently = false
    @State private var queuedPostsCount = 0
    @State private var networkQuality: NetworkQuality = .good
    @State private var cancellables = Set<AnyCancellable>()
    @FocusState private var isFocused: Bool
    
    init(windowManager: WindowManager, placement: ButtonPlacement = .automatic) {
        self.windowManager = windowManager
        self.placement = placement
    }
    
    var body: some View {
        Group {
            if shouldShowReconnectButton {
                reconnectButton
                    .focusable()
                    .focused($isFocused)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(accessibilityHint)
                    .accessibilityValue(accessibilityValue)
                    .accessibilityAddTraits(accessibilityTraits)
                    .accessibilityAction(named: accessibilityActionName) {
                        performAccessibilityAction()
                    }
                    .onKeyPress(.return) {
                        showReconnectionFlow()
                        return .handled
                    }
                    .onKeyPress(.space) {
                        showReconnectionFlow()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismissButton()
                        return .handled
                    }
                    .transition(buttonTransition)
                    .animation(.easeInOut(duration: 0.3), value: shouldShowReconnectButton)
            }
        }
        .onAppear {
            setupStateObservation()
        }
        .onDisappear {
            cancellables.removeAll()
        }
        .sheet(isPresented: $showingReconnection) {
            ReconnectionView(windowManager: windowManager)
                .frame(width: 380, height: 350)
        }
    }
    
    // MARK: - Reconnect Button Variants
    
    @ViewBuilder
    private var reconnectButton: some View {
        switch reconnectButtonStyle {
        case .prominent:
            prominentReconnectButton
        case .discrete:
            discreteReconnectButton
        case .urgent:
            urgentReconnectButton
        case .gentle:
            gentleReconnectButton
        case .minimal:
            minimalReconnectButton
        }
    }
    
    private var prominentReconnectButton: some View {
        Button(action: showReconnectionFlow) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 12, weight: .medium))
                
                Text("Reconnect to X")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
        }
        .buttonStyle(ProminentReconnectButtonStyle())
        .help("Restore connection to continue posting")
    }
    
    private var discreteReconnectButton: some View {
        Button(action: showReconnectionFlow) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                
                Text("Reconnect")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(DiscreteReconnectButtonStyle())
        .help("Reconnect to X")
    }
    
    private var urgentReconnectButton: some View {
        Button(action: showReconnectionFlow) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Lost")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(queuedPostsCount) posts queued")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                Text("Reconnect")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .buttonStyle(UrgentReconnectButtonStyle())
        .help("Urgent: \(queuedPostsCount) posts waiting to be sent")
    }
    
    private var gentleReconnectButton: some View {
        Button(action: showReconnectionFlow) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                
                Text("Reconnect")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .help("Restore connection when convenient")
    }
    
    private var minimalReconnectButton: some View {
        Button(action: showReconnectionFlow) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Reconnect")
    }
    
    // MARK: - Intelligent Visibility Logic
    
    private var shouldShowReconnectButton: Bool {
        // Don't show if user dismissed recently (except for urgent situations)
        if userDismissedRecently && reconnectContext != .urgent {
            return false
        }
        
        // Don't show during connection attempts
        guard !windowManager.connectionStatus.isConnecting else { return false }
        
        // Only show for disconnected or error states
        guard windowManager.connectionStatus.isDisconnected || windowManager.connectionStatus.isError else { return false }
        
        // Apply placement-specific visibility rules
        return shouldShowForPlacement && shouldShowForContext
    }
    
    private var shouldShowForPlacement: Bool {
        switch placement {
        case .automatic:
            return shouldShowForAutomaticPlacement
        case .header:
            // Always show in header when disconnected (it's the primary location)
            return true
        case .statusArea:
            // Show in status area only if not too cluttered and after some delay
            return timeSinceDisconnection > 3.0 && !isStatusAreaCluttered
        case .sidebar:
            // Show in sidebar for subtle indication after longer delay
            return timeSinceDisconnection > 10.0
        case .overlay:
            // Show as overlay only for urgent situations
            return reconnectContext == .urgent
        case .minimal:
            // Show minimal version after extended delay
            return timeSinceDisconnection > 30.0
        }
    }
    
    private var shouldShowForContext: Bool {
        switch reconnectContext {
        case .immediate:
            return true
        case .delayed:
            return timeSinceDisconnection > 5.0 // Wait 5 seconds
        case .gentle:
            return timeSinceDisconnection > 30.0 // Wait 30 seconds
        case .urgent:
            return queuedPostsCount > 0 // Show immediately if posts are queued
        case .minimal:
            return timeSinceDisconnection > 60.0 // Wait 1 minute
        case .hidden:
            return false
        }
    }
    
    private var shouldShowForAutomaticPlacement: Bool {
        // Intelligent placement selection based on context and UI state
        switch reconnectContext {
        case .urgent:
            return placement == .overlay || placement == .header
        case .immediate:
            return placement == .header
        case .gentle:
            return placement == .statusArea || placement == .sidebar
        case .delayed:
            return placement == .statusArea
        case .minimal:
            return placement == .minimal || placement == .sidebar
        case .hidden:
            return false
        }
    }
    
    private var isStatusAreaCluttered: Bool {
        // Check if the status area has too many elements
        let hasPostingDisabled = !windowManager.connectionStatus.isConnected
        let hasCharacterCounter = !windowManager.currentText.isEmpty
        let hasConnectionIndicator = true // Always present
        
        // Consider cluttered if multiple indicators are present
        return hasPostingDisabled && hasCharacterCounter
    }
    
    private var reconnectContext: ReconnectContext {
        // Determine context based on various factors
        
        // Urgent: Has queued posts
        if queuedPostsCount > 0 {
            return .urgent
        }
        
        // Immediate: Network quality is good and recent disconnect
        if networkQuality == .good && timeSinceDisconnection < 30.0 {
            return .immediate
        }
        
        // Delayed: Network quality is poor
        if networkQuality == .poor {
            return .delayed
        }
        
        // Gentle: User was actively typing when disconnected
        if windowManager.isTextFieldFocused {
            return .gentle
        }
        
        // Minimal: Background disconnect, no user activity
        if !windowManager.isWindowFocused && timeSinceDisconnection > 120.0 {
            return .minimal
        }
        
        // Default to immediate for unknown scenarios
        return .immediate
    }
    
    private var reconnectButtonStyle: ReconnectButtonStyle {
        // Consider both context and placement for style selection
        switch (reconnectContext, placement) {
        case (.urgent, _):
            return .urgent
        case (.immediate, .header):
            return .prominent
        case (.immediate, .statusArea):
            return .discrete
        case (.immediate, .sidebar):
            return .minimal
        case (.delayed, .header):
            return .discrete
        case (.delayed, .statusArea):
            return .gentle
        case (.gentle, _):
            return .gentle
        case (.minimal, _):
            return .minimal
        case (.hidden, _):
            return .minimal // Fallback, but shouldn't be visible
        default:
            // Default behavior based on context
            switch reconnectContext {
            case .immediate:
                return .prominent
            case .delayed:
                return .discrete
            case .gentle:
                return .gentle
            case .urgent:
                return .urgent
            case .minimal:
                return .minimal
            case .hidden:
                return .minimal
            }
        }
    }
    
    private var buttonTransition: AnyTransition {
        switch reconnectButtonStyle {
        case .prominent, .urgent:
            return .asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            )
        case .discrete, .gentle:
            return .opacity.combined(with: .move(edge: .trailing))
        case .minimal:
            return .opacity
        }
    }
    
    private var timeSinceDisconnection: TimeInterval {
        guard let lastDisconnectionTime = lastDisconnectionTime else { return 0 }
        return Date().timeIntervalSince(lastDisconnectionTime)
    }
    
    // MARK: - Actions
    
    private func showReconnectionFlow() {
        showingReconnection = true
    }
    
    private func dismissButton() {
        userDismissedRecently = true
        
        // Re-enable after some time
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { // 5 minutes
            userDismissedRecently = false
        }
    }
    
    // MARK: - State Observation
    
    private func setupStateObservation() {
        // Monitor connection status changes
        windowManager.$connectionStatus
            .sink { status in
                handleConnectionStatusChange(status)
            }
            .store(in: &cancellables)
        
        // Monitor queued posts count
        windowManager.postQueueManager?.queueCountPublisher
            .sink { count in
                queuedPostsCount = count
            }
            .store(in: &cancellables)
        
        // Monitor network quality (if available)
        // This would connect to NetworkMonitor if available
        setupNetworkQualityObservation()
    }
    
    private func handleConnectionStatusChange(_ status: ConnectionStatus) {
        switch status {
        case .disconnected, .error:
            // Mark disconnect time if not already set
            if lastDisconnectionTime == nil {
                lastDisconnectionTime = Date()
            }
        case .connected:
            // Reset state when reconnected
            lastDisconnectionTime = nil
            userDismissedRecently = false
        default:
            break
        }
    }
    
    private func setupNetworkQualityObservation() {
        // This would connect to NetworkMonitor if available
        // For now, we'll simulate network quality detection
        Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // Simulate network quality detection
                // In real implementation, this would use NetworkMonitor
                updateNetworkQuality()
            }
            .store(in: &cancellables)
    }
    
    private func updateNetworkQuality() {
        // Simulate network quality assessment
        // In real implementation, this would use actual network monitoring
        networkQuality = .good // Default assumption
    }
    
    // MARK: - Accessibility Support
    
    private var accessibilityLabel: String {
        switch reconnectButtonStyle {
        case .prominent:
            return "Reconnect to X button"
        case .discrete:
            return "Reconnect button"
        case .urgent:
            return "Urgent reconnect button"
        case .gentle:
            return "Gentle reconnect suggestion"
        case .minimal:
            return "Minimal reconnect button"
        }
    }
    
    private var accessibilityHint: String {
        switch reconnectContext {
        case .urgent:
            let postText = queuedPostsCount == 1 ? "post" : "posts"
            return "Connection lost with \(queuedPostsCount) \(postText) waiting. Double tap to reconnect immediately."
        case .immediate:
            return "Recent disconnection detected. Double tap to restore connection now."
        case .delayed:
            return "Connection issues detected. Double tap to reconnect when ready."
        case .gentle:
            return "Consider reconnecting when convenient. Double tap to restore connection."
        case .minimal:
            return "Background disconnection. Double tap to reconnect."
        case .hidden:
            return "Reconnection available if needed."
        }
    }
    
    private var accessibilityValue: String {
        var value = "Status: Disconnected"
        
        if queuedPostsCount > 0 {
            let postText = queuedPostsCount == 1 ? "post" : "posts"
            value += ", \(queuedPostsCount) \(postText) queued"
        }
        
        value += ", Network quality: \(networkQuality.description)"
        value += ", Placement: \(placement.description)"
        
        return value
    }
    
    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = [.button]
        
        switch reconnectContext {
        case .urgent:
            traits.insert(.startsMediaSession)
        case .immediate:
            traits.insert(.startsMediaSession)
        default:
            break
        }
        
        return traits
    }
    
    private var accessibilityActionName: String {
        switch reconnectContext {
        case .urgent:
            return "Reconnect urgently"
        case .immediate:
            return "Reconnect now"
        case .delayed:
            return "Reconnect when ready"
        case .gentle:
            return "Reconnect gently"
        case .minimal:
            return "Reconnect"
        case .hidden:
            return "Reconnect"
        }
    }
    
    private func performAccessibilityAction() {
        showReconnectionFlow()
        
        // Announce action
        let announcement = "Reconnection flow started"
        
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
}

// MARK: - Supporting Types

enum ButtonPlacement {
    case automatic      // Intelligent placement based on context
    case header         // In the authentication status header
    case statusArea     // In the bottom status area
    case sidebar        // As a side indicator
    case overlay        // As an overlay element
    case minimal        // Ultra-minimal placement
    
    var description: String {
        switch self {
        case .automatic: return "Automatic"
        case .header: return "Header"
        case .statusArea: return "Status Area"
        case .sidebar: return "Sidebar"
        case .overlay: return "Overlay"
        case .minimal: return "Minimal"
        }
    }
}

enum ReconnectContext {
    case immediate  // Show immediately - good network, recent disconnect
    case delayed    // Show after delay - poor network or transient issue
    case gentle     // Show gently - user was active, don't interrupt
    case urgent     // Show urgently - queued posts or critical state
    case minimal    // Show minimally - background/passive disconnect
    case hidden     // Don't show - user dismissed or inappropriate timing
}

enum ReconnectButtonStyle {
    case prominent  // Full button with icon and text
    case discrete   // Small button with minimal text
    case urgent     // Warning style with queue info
    case gentle     // Soft suggestion style
    case minimal    // Icon only
}

enum NetworkQuality {
    case good
    case fair
    case poor
    
    var description: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}

// MARK: - Custom Button Styles

struct ProminentReconnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(8)
            .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DiscreteReconnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
            )
            .foregroundColor(.blue)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct UrgentReconnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.red, Color.red.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(8)
            .shadow(color: .red.opacity(0.4), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Smart Reconnect Manager

@MainActor
class SmartReconnectManager: ObservableObject {
    @Published var shouldShowReconnect = false
    @Published var buttonStyle: ReconnectButtonStyle = .discrete
    @Published var reconnectContext: ReconnectContext = .immediate
    
    private var windowManager: WindowManager
    private var lastUserActivity: Date = Date()
    private var disconnectionEvents: [Date] = []
    private var userPreferences = ReconnectPreferences()
    private var cancellables = Set<AnyCancellable>()
    
    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        setupIntelligentMonitoring()
    }
    
    private func setupIntelligentMonitoring() {
        // Monitor connection status with pattern recognition
        windowManager.$connectionStatus
            .sink { [weak self] status in
                self?.analyzeConnectionPattern(status)
            }
            .store(in: &cancellables)
        
        // Monitor user activity for context
        windowManager.$isTextFieldFocused
            .sink { [weak self] focused in
                if focused {
                    self?.lastUserActivity = Date()
                }
            }
            .store(in: &cancellables)
        
        // Monitor window focus for context
        windowManager.$isWindowFocused
            .sink { [weak self] focused in
                if focused {
                    self?.lastUserActivity = Date()
                }
            }
            .store(in: &cancellables)
    }
    
    private func analyzeConnectionPattern(_ status: ConnectionStatus) {
        switch status {
        case .disconnected, .error:
            disconnectionEvents.append(Date())
            analyzeReconnectStrategy()
        case .connected:
            // Reset patterns when successfully connected
            disconnectionEvents.removeAll()
        default:
            break
        }
    }
    
    private func analyzeReconnectStrategy() {
        // Analyze recent disconnection patterns
        let recentDisconnections = disconnectionEvents.filter { 
            Date().timeIntervalSince($0) < 300 // Last 5 minutes
        }
        
        // Determine appropriate strategy
        if recentDisconnections.count >= 3 {
            // Frequent disconnections - be more conservative
            reconnectContext = .gentle
            buttonStyle = .minimal
        } else if hasQueuedPosts {
            // Has queued posts - show urgently
            reconnectContext = .urgent
            buttonStyle = .urgent
        } else if isUserActive {
            // User is active - show prominently but not urgently
            reconnectContext = .immediate
            buttonStyle = .prominent
        } else {
            // Background disconnect - be subtle
            reconnectContext = .gentle
            buttonStyle = .discrete
        }
        
        updateVisibility()
    }
    
    private var hasQueuedPosts: Bool {
        // This would check the actual queue count
        // For now, simulate based on windowManager state
        return false // windowManager.postQueueManager?.queuedPostsCount ?? 0 > 0
    }
    
    private var isUserActive: Bool {
        return Date().timeIntervalSince(lastUserActivity) < 60.0 // Active in last minute
    }
    
    private func updateVisibility() {
        let shouldShow = determineVisibility()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            shouldShowReconnect = shouldShow
        }
    }
    
    private func determineVisibility() -> Bool {
        // Apply user preferences
        if userPreferences.hasDisabledReconnectPrompts {
            return false
        }
        
        // Don't show if actively connecting
        if windowManager.connectionStatus.isConnecting {
            return false
        }
        
        // Only show for disconnected states
        guard windowManager.connectionStatus.isDisconnected || windowManager.connectionStatus.isError else {
            return false
        }
        
        // Apply context-specific logic
        switch reconnectContext {
        case .urgent:
            return true // Always show for urgent cases
        case .immediate:
            return true // Show immediately in most cases
        case .gentle:
            return timeSinceLastActivity > 30.0 // Wait for user to be less active
        case .delayed:
            return timeSinceDisconnection > 10.0 // Wait a bit
        case .minimal:
            return timeSinceDisconnection > 120.0 // Wait much longer
        case .hidden:
            return false
        }
    }
    
    private var timeSinceLastActivity: TimeInterval {
        return Date().timeIntervalSince(lastUserActivity)
    }
    
    private var timeSinceDisconnection: TimeInterval {
        guard let lastDisconnection = disconnectionEvents.last else { return 0 }
        return Date().timeIntervalSince(lastDisconnection)
    }
}

// MARK: - User Preferences

struct ReconnectPreferences {
    var hasDisabledReconnectPrompts = false
    var preferredButtonStyle: ReconnectButtonStyle = .discrete
    var reconnectStrategy: ReconnectStrategy = .smart
}

enum ReconnectStrategy {
    case aggressive  // Show reconnect immediately
    case smart      // Analyze context and patterns
    case passive    // Wait for user to initiate
}

// MARK: - Previews

#Preview("Header Placement") {
    ContextualReconnectButton(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }(), placement: .header)
    .padding()
}

#Preview("All Placements") {
    VStack(spacing: 20) {
        // Different placement styles
        Group {
            Text("Header Placement")
                .font(.caption)
            ContextualReconnectButton(windowManager: createMockWindowManager(.disconnected), placement: .header)
            
            Text("Status Area Placement")
                .font(.caption)
            ContextualReconnectButton(windowManager: createMockWindowManager(.disconnected), placement: .statusArea)
            
            Text("Minimal Placement")
                .font(.caption)
            ContextualReconnectButton(windowManager: createMockWindowManager(.disconnected), placement: .minimal)
            
            Text("Sidebar Placement")
                .font(.caption)
            ContextualReconnectButton(windowManager: createMockWindowManager(.error), placement: .sidebar)
        }
    }
    .padding()
}

private func createMockWindowManager(_ status: ConnectionStatus) -> WindowManager {
    let wm = WindowManager.shared
    wm.connectionStatus = status
    return wm
}
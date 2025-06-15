//
//  DiscreteStatusIndicators.swift
//  Mercury
//
//  Created by Claude on 2025-06-15.
//

import SwiftUI
import Combine
import AppKit

// MARK: - Enhanced Discrete Connection Status Indicator

struct EnhancedDiscreteStatusIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var isHovered = false
    @State private var showDetailedTooltip = false
    @State private var hoverOpacity: Double = 0.3
    @State private var lastConnectionTime: Date?
    @State private var cancellables = Set<AnyCancellable>()
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Base discrete indicator
            baseIndicator
            
            // Hover expansion with detailed info
            if isHovered || isFocused {
                hoverExpansion
            }
        }
        .help(tooltipText)
        .focusable()
        .focused($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatusLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(accessibilityTraits)
        .accessibilityAction(named: accessibilityActionName) {
            performAccessibilityAction()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
            
            // Show detailed tooltip after extended hover
            if hovering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if isHovered {
                        showDetailedTooltip = true
                    }
                }
            } else {
                showDetailedTooltip = false
            }
        }
        .onTapGesture {
            handleUserInteraction()
        }
        .onKeyPress(.return) {
            handleUserInteraction()
            return .handled
        }
        .onKeyPress(.space) {
            handleUserInteraction()
            return .handled
        }
        .onAppear {
            setupStatusObservation()
            startDiscreteAnimation()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    // MARK: - Base Indicator
    
    private var baseIndicator: some View {
        Rectangle()
            .fill(statusGradient)
            .frame(width: indicatorWidth, height: 12)
            .opacity(isHovered ? 0.9 : hoverOpacity)
            .cornerRadius(1)
            .overlay(
                // Subtle connection quality indicator
                connectionQualityOverlay
            )
    }
    
    private var indicatorWidth: CGFloat {
        switch windowManager.connectionStatus {
        case .connected:
            return 3
        case .connecting, .refreshing:
            return 2
        case .disconnected, .error:
            return 4 // Slightly wider for attention
        }
    }
    
    private var connectionQualityOverlay: some View {
        Group {
            if windowManager.connectionStatus.isConnected {
                // Show connection strength indicator
                HStack(spacing: 0.5) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle()
                            .fill(Color.green.opacity(connectionStrengthOpacity(for: index)))
                            .frame(width: 0.5, height: CGFloat(2 + index))
                    }
                }
                .opacity(0.6)
            }
        }
    }
    
    private func connectionStrengthOpacity(for index: Int) -> Double {
        // Simulate connection strength (would be from NetworkMonitor in real implementation)
        let strength = 0.8 // Good connection
        return index < Int(strength * 3) ? 1.0 : 0.3
    }
    
    // MARK: - Hover Expansion
    
    private var hoverExpansion: some View {
        HStack(spacing: 8) {
            // Status icon
            statusIcon
            
            // Status details
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryStatusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(secondaryStatusText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Additional details on extended hover
            if showDetailedTooltip {
                VStack(alignment: .leading, spacing: 1) {
                    detailedStatusInfo
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    private var statusIcon: some View {
        Group {
            switch windowManager.connectionStatus {
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .connecting:
                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            case .refreshing:
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(isHovered ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isHovered)
            case .disconnected:
                Image(systemName: "wifi.slash")
                    .foregroundColor(.red)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 12))
    }
    
    // MARK: - Status Text
    
    private var primaryStatusText: String {
        switch windowManager.connectionStatus {
        case .connected:
            if let user = windowManager.authManager?.currentUser {
                return "Connected as @\(user.username)"
            } else {
                return "Connected to X"
            }
        case .connecting:
            return "Connecting to X..."
        case .refreshing:
            return "Refreshing connection"
        case .disconnected:
            return "Disconnected from X"
        case .error:
            return "Connection error"
        }
    }
    
    private var secondaryStatusText: String {
        switch windowManager.connectionStatus {
        case .connected:
            return timeSinceConnection
        case .connecting:
            return "Please wait..."
        case .refreshing:
            return "Updating credentials"
        case .disconnected:
            return "Posting unavailable"
        case .error:
            return "Check connection"
        }
    }
    
    private var timeSinceConnection: String {
        guard let lastConnectionTime = lastConnectionTime else {
            return "Recently connected"
        }
        
        let interval = Date().timeIntervalSince(lastConnectionTime)
        
        if interval < 60 {
            return "Connected \(Int(interval))s ago"
        } else if interval < 3600 {
            return "Connected \(Int(interval/60))m ago"
        } else {
            return "Connected \(Int(interval/3600))h ago"
        }
    }
    
    // MARK: - Detailed Status Info
    
    @ViewBuilder
    private var detailedStatusInfo: some View {
        switch windowManager.connectionStatus {
        case .connected:
            connectedDetails
        case .connecting:
            connectingDetails
        case .refreshing:
            refreshingDetails
        case .disconnected:
            disconnectedDetails
        case .error:
            errorDetails
        }
    }
    
    private var connectedDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("• Posting enabled")
                .font(.system(size: 8))
                .foregroundColor(.green)
            
            Text("• Rate limit: \(rateLimitInfo)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            
            if let queueCount = queuedPostsCount, queueCount > 0 {
                Text("• Queue: \(queueCount) posts")
                    .font(.system(size: 8))
                    .foregroundColor(.blue)
            }
        }
    }
    
    private var connectingDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("• Establishing secure connection")
                .font(.system(size: 8))
                .foregroundColor(.blue)
            
            Text("• Network quality: \(networkQualityText)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
    }
    
    private var refreshingDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("• Updating authentication")
                .font(.system(size: 8))
                .foregroundColor(.orange)
            
            Text("• Posting temporarily paused")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
    }
    
    private var disconnectedDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("• Posting disabled")
                .font(.system(size: 8))
                .foregroundColor(.red)
            
            Text("• Tap to reconnect")
                .font(.system(size: 8))
                .foregroundColor(.blue)
            
            if let queueCount = queuedPostsCount, queueCount > 0 {
                Text("• \(queueCount) posts queued")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var errorDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("• Authentication failed")
                .font(.system(size: 8))
                .foregroundColor(.red)
            
            Text("• Check network connection")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            
            Text("• Tap to retry")
                .font(.system(size: 8))
                .foregroundColor(.blue)
        }
    }
    
    // MARK: - Helper Properties
    
    private var rateLimitInfo: String {
        // Would get from AuthManager in real implementation
        "98/100"
    }
    
    private var queuedPostsCount: Int? {
        // Would get from PostQueueManager in real implementation
        let count = 0 // windowManager.postQueueManager?.queuedPostsCount ?? 0
        return count > 0 ? count : nil
    }
    
    private var networkQualityText: String {
        // Would get from NetworkMonitor in real implementation
        "Good"
    }
    
    private var tooltipText: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Connected to X - Click for details"
        case .connecting:
            return "Connecting to X..."
        case .refreshing:
            return "Refreshing connection - Please wait"
        case .disconnected:
            return "Disconnected from X - Click to reconnect"
        case .error:
            return "Connection error - Click to retry"
        }
    }
    
    // MARK: - Status Gradient
    
    private var statusGradient: LinearGradient {
        switch windowManager.connectionStatus {
        case .connected:
            return LinearGradient(
                colors: [.green.opacity(0.9), .green.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .connecting, .refreshing:
            return LinearGradient(
                colors: [.blue.opacity(0.9), .blue.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .disconnected, .error:
            return LinearGradient(
                colors: [.red.opacity(0.9), .red.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // MARK: - Animations
    
    private func startDiscreteAnimation() {
        let animation: Animation? = switch windowManager.connectionStatus {
        case .connected:
            Animation.easeInOut(duration: 8.0).repeatForever(autoreverses: true)
        case .disconnected, .error:
            Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
        case .connecting, .refreshing:
            Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        }
        
        if let animation = animation {
            withAnimation(animation) {
                hoverOpacity = switch windowManager.connectionStatus {
                case .connected: 0.7
                case .disconnected, .error: 0.8
                case .connecting, .refreshing: 0.6
                }
            }
        }
    }
    
    // MARK: - State Observation
    
    private func setupStatusObservation() {
        windowManager.$connectionStatus
            .sink { status in
                if status.isConnected && !windowManager.connectionStatus.isConnected {
                    // Just connected
                    lastConnectionTime = Date()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Accessibility Support
    
    private var accessibilityStatusLabel: String {
        switch windowManager.connectionStatus {
        case .connected:
            if let user = windowManager.authManager?.currentUser {
                return "Connected to X as \(user.username)"
            } else {
                return "Connected to X"
            }
        case .connecting:
            return "Connecting to X"
        case .refreshing:
            return "Refreshing X connection"
        case .disconnected:
            return "Disconnected from X"
        case .error:
            return "X connection error"
        }
    }
    
    private var accessibilityHint: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Posting is enabled. Double tap for connection details."
        case .connecting:
            return "Connection in progress. Please wait."
        case .refreshing:
            return "Updating credentials. Posting temporarily disabled."
        case .disconnected:
            return "Posting disabled. Double tap to reconnect."
        case .error:
            return "Connection failed. Double tap to retry connection."
        }
    }
    
    private var accessibilityValue: String {
        switch windowManager.connectionStatus {
        case .connected:
            var value = "Status: Active"
            if let queueCount = queuedPostsCount, queueCount > 0 {
                value += ", \(queueCount) posts in queue"
            }
            value += ", Rate limit: \(rateLimitInfo)"
            return value
        case .connecting:
            return "Status: Establishing connection"
        case .refreshing:
            return "Status: Updating authentication"
        case .disconnected:
            var value = "Status: Offline"
            if let queueCount = queuedPostsCount, queueCount > 0 {
                value += ", \(queueCount) posts queued"
            }
            return value
        case .error:
            return "Status: Error, connection failed"
        }
    }
    
    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = [.button]
        
        switch windowManager.connectionStatus {
        case .connected:
            traits.insert(.updatesFrequently)
        case .connecting, .refreshing:
            traits.insert(.updatesFrequently)
        case .disconnected, .error:
            traits.insert(.startsMediaSession) // Indicates action available
        }
        
        return traits
    }
    
    private var accessibilityActionName: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Show connection details"
        case .connecting:
            return "View connection status"
        case .refreshing:
            return "View refresh status"
        case .disconnected:
            return "Reconnect to X"
        case .error:
            return "Retry connection"
        }
    }
    
    private func performAccessibilityAction() {
        switch windowManager.connectionStatus {
        case .disconnected, .error:
            // Trigger reconnection flow
            windowManager.authManager?.refreshAuthenticationIfNeeded()
        case .connected, .connecting, .refreshing:
            // Show detailed status (could trigger a modal or announcement)
            announceDetailedStatus()
        }
    }
    
    private func handleUserInteraction() {
        // Handle tap/keyboard interaction
        performAccessibilityAction()
        
        // Provide haptic feedback if available
        #if canImport(UIKit)
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        #endif
    }
    
    private func announceDetailedStatus() {
        // Create detailed status announcement for VoiceOver
        var announcement = accessibilityStatusLabel + ". " + accessibilityValue
        
        if showDetailedTooltip {
            announcement += ". Additional details: " + detailedStatusAnnouncement
        }
        
        // Use iOS announcement if available, otherwise rely on value updates
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
        
        // Update focus to show expanded details
        isFocused = true
        showDetailedTooltip = true
    }
    
    private var detailedStatusAnnouncement: String {
        switch windowManager.connectionStatus {
        case .connected:
            var details = "Posting enabled"
            if let queueCount = queuedPostsCount, queueCount > 0 {
                details += ", \(queueCount) posts in queue"
            }
            details += ", Rate limit shows \(rateLimitInfo) requests available"
            return details
            
        case .connecting:
            return "Establishing secure connection, network quality is \(networkQualityText)"
            
        case .refreshing:
            return "Updating authentication tokens, posting temporarily paused"
            
        case .disconnected:
            var details = "Posting disabled"
            if let queueCount = queuedPostsCount, queueCount > 0 {
                details += ", \(queueCount) posts will sync when reconnected"
            }
            return details
            
        case .error:
            return "Authentication failed, check internet connection and account access"
        }
    }
}

// MARK: - Minimalist Status Dot with Rich Tooltip

struct MinimalistStatusDot: View {
    @ObservedObject var windowManager: WindowManager
    @State private var showTooltip = false
    @State private var pulseScale: CGFloat = 1.0
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .scaleEffect(pulseScale)
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
            .onHover { hovering in
                showTooltip = hovering
            }
            .onTapGesture {
                handleUserInteraction()
            }
            .onKeyPress(.return) {
                handleUserInteraction()
                return .handled
            }
            .onKeyPress(.space) {
                handleUserInteraction()
                return .handled
            }
            .help(detailedTooltipText)
            .onAppear {
                startPulseAnimation()
            }
            .animation(pulseAnimation, value: pulseScale)
    }
    
    private var statusColor: Color {
        switch windowManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .refreshing:
            return .blue
        case .disconnected, .error:
            return .red
        }
    }
    
    private var pulseAnimation: Animation? {
        switch windowManager.connectionStatus {
        case .connected:
            return Animation.easeInOut(duration: 4.0).repeatForever(autoreverses: true)
        case .disconnected, .error:
            return Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        case .connecting, .refreshing:
            return Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        }
    }
    
    private var detailedTooltipText: String {
        switch windowManager.connectionStatus {
        case .connected:
            var tooltip = "✅ Connected to X"
            if let user = windowManager.authManager?.currentUser {
                tooltip += " as @\(user.username)"
            }
            tooltip += "\n📤 Posting enabled"
            tooltip += "\n⚡ Rate limit: 98/100"
            return tooltip
            
        case .connecting:
            return "🔄 Connecting to X...\n🌐 Establishing secure connection\n⏳ Please wait"
            
        case .refreshing:
            return "🔄 Refreshing connection\n🔑 Updating credentials\n⏸️ Posting temporarily paused"
            
        case .disconnected:
            var tooltip = "❌ Disconnected from X\n🚫 Posting disabled"
            let queueCount = 0 // Would get from queue manager
            if queueCount > 0 {
                tooltip += "\n📋 \(queueCount) posts queued"
            }
            tooltip += "\n🔧 Click to reconnect"
            return tooltip
            
        case .error:
            return "⚠️ Connection error\n🔗 Check network connection\n🔄 Click to retry"
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(pulseAnimation) {
            pulseScale = switch windowManager.connectionStatus {
            case .connected: 1.1
            case .disconnected, .error: 1.2
            case .connecting, .refreshing: 1.15
            }
        }
    }
    
    // MARK: - Accessibility Support
    
    private var accessibilityLabel: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Connected status indicator"
        case .connecting:
            return "Connecting status indicator"
        case .refreshing:
            return "Refreshing status indicator"
        case .disconnected:
            return "Disconnected status indicator"
        case .error:
            return "Error status indicator"
        }
    }
    
    private var accessibilityHint: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Shows X connection is active. Double tap for details."
        case .connecting:
            return "Connection to X in progress"
        case .refreshing:
            return "Connection being refreshed"
        case .disconnected:
            return "Not connected to X. Double tap to reconnect."
        case .error:
            return "Connection error. Double tap to retry."
        }
    }
    
    private var accessibilityValue: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Green dot, posting enabled"
        case .connecting:
            return "Blue dot, establishing connection"
        case .refreshing:
            return "Blue dot, updating credentials"
        case .disconnected:
            return "Red dot, posting disabled"
        case .error:
            return "Red dot, connection failed"
        }
    }
    
    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = [.button]
        
        switch windowManager.connectionStatus {
        case .connected:
            traits.insert(.updatesFrequently)
        case .connecting, .refreshing:
            traits.insert(.updatesFrequently)
        case .disconnected, .error:
            traits.insert(.startsMediaSession)
        }
        
        return traits
    }
    
    private var accessibilityActionName: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "View connection status"
        case .connecting, .refreshing:
            return "Check connection progress"
        case .disconnected:
            return "Reconnect to X"
        case .error:
            return "Retry connection"
        }
    }
    
    private func performAccessibilityAction() {
        switch windowManager.connectionStatus {
        case .disconnected, .error:
            windowManager.authManager?.refreshAuthenticationIfNeeded()
        case .connected, .connecting, .refreshing:
            announceDetailedStatus()
        }
    }
    
    private func handleUserInteraction() {
        performAccessibilityAction()
        isFocused = true
    }
    
    private func announceDetailedStatus() {
        let announcement = accessibilityLabel + ". " + accessibilityValue + ". " + stripEmojis(from: detailedTooltipText)
        
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
    
    private func stripEmojis(from text: String) -> String {
        return text.replacingOccurrences(of: "✅", with: "")
                  .replacingOccurrences(of: "🔄", with: "")
                  .replacingOccurrences(of: "❌", with: "")
                  .replacingOccurrences(of: "⚠️", with: "")
                  .replacingOccurrences(of: "📤", with: "")
                  .replacingOccurrences(of: "⚡", with: "")
                  .replacingOccurrences(of: "🌐", with: "")
                  .replacingOccurrences(of: "⏳", with: "")
                  .replacingOccurrences(of: "🔑", with: "")
                  .replacingOccurrences(of: "⏸️", with: "")
                  .replacingOccurrences(of: "🚫", with: "")
                  .replacingOccurrences(of: "📋", with: "")
                  .replacingOccurrences(of: "🔧", with: "")
                  .replacingOccurrences(of: "🔗", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Connection Quality Indicator

struct ConnectionQualityIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var signalStrength: Double = 0.8
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(barColor(for: index))
                    .frame(width: 2, height: CGFloat(4 + index * 2))
                    .opacity(barOpacity(for: index))
                    .animation(.easeInOut(duration: 0.3), value: signalStrength)
            }
        }
        .focusable()
        .focused($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection quality indicator")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows network signal strength")
        .accessibilityAddTraits([.updatesFrequently])
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            isFocused = true
            announceQualityStatus()
        }
        .onKeyPress(.return) {
            announceQualityStatus()
            return .handled
        }
        .onKeyPress(.space) {
            announceQualityStatus()
            return .handled
        }
        .help(qualityTooltipText)
        .onAppear {
            updateSignalStrength()
        }
    }
    
    private func barColor(for index: Int) -> Color {
        let activeLevel = Int(signalStrength * 4)
        
        if index < activeLevel {
            switch signalStrength {
            case 0.75...:
                return .green
            case 0.5..<0.75:
                return .yellow
            default:
                return .red
            }
        } else {
            return .gray
        }
    }
    
    private func barOpacity(for index: Int) -> Double {
        let activeLevel = Int(signalStrength * 4)
        return index < activeLevel ? 1.0 : 0.3
    }
    
    private var qualityTooltipText: String {
        let qualityText = switch signalStrength {
        case 0.75...: "Excellent"
        case 0.5..<0.75: "Good"
        case 0.25..<0.5: "Fair"
        default: "Poor"
        }
        
        return "📶 Connection Quality: \(qualityText)\n⚡ Signal Strength: \(Int(signalStrength * 100))%"
    }
    
    private func updateSignalStrength() {
        // Would get from NetworkMonitor in real implementation
        // For now, simulate based on connection status
        signalStrength = switch windowManager.connectionStatus {
        case .connected: 0.8
        case .connecting, .refreshing: 0.6
        case .disconnected, .error: 0.0
        }
    }
    
    // MARK: - Accessibility Support
    
    private var accessibilityValue: String {
        let qualityText = switch signalStrength {
        case 0.75...: "Excellent"
        case 0.5..<0.75: "Good"
        case 0.25..<0.5: "Fair"
        default: "Poor"
        }
        
        let activeLevel = Int(signalStrength * 4)
        return "\(qualityText) signal strength, \(activeLevel) of 4 bars active"
    }
    
    private func announceQualityStatus() {
        let announcement = "Connection quality: " + accessibilityValue
        
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
}

// MARK: - Integrated Discrete Status Bar

struct DiscreteStatusBar: View {
    @ObservedObject var windowManager: WindowManager
    let showQualityIndicator: Bool
    
    init(windowManager: WindowManager, showQualityIndicator: Bool = true) {
        self.windowManager = windowManager
        self.showQualityIndicator = showQualityIndicator
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Main animated status indicator
            CompactAnimatedStatusIndicator(windowManager: windowManager)
            
            // Enhanced discrete status indicator
            EnhancedDiscreteStatusIndicator(windowManager: windowManager)
            
            // Connection quality bars (when connected)
            if showQualityIndicator && windowManager.connectionStatus.isConnected {
                ConnectionQualityIndicator(windowManager: windowManager)
            }
            
            // Minimalist status dot for quick reference
            MinimalistStatusDot(windowManager: windowManager)
        }
    }
}

// MARK: - Enhanced Tooltip System

struct TooltipView: View {
    let title: String
    let subtitle: String?
    let details: [String]
    let statusColor: Color
    
    init(title: String, subtitle: String? = nil, details: [String] = [], statusColor: Color = .primary) {
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.statusColor = statusColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title with status color
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            // Subtitle
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Detailed information
            if !details.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(details, id: \.self) { detail in
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Tooltip Enhancement Modifier

extension View {
    func enhancedTooltip(
        title: String,
        subtitle: String? = nil,
        details: [String] = [],
        statusColor: Color = .primary,
        delay: Double = 0.5
    ) -> some View {
        self.help(title) // Fallback to system tooltip
    }
}

// MARK: - Status Tooltip Factory

struct StatusTooltipFactory {
    static func createTooltip(for status: ConnectionStatus, windowManager: WindowManager) -> String {
        switch status {
        case .connected:
            var tooltip = "✅ Connected to X"
            if let user = windowManager.authManager?.currentUser {
                tooltip += " as @\(user.username)"
            }
            tooltip += "\n📤 Posting enabled"
            tooltip += "\n⚡ Rate limit: Available"
            
            // Add queue info if available
            let queueCount = 0 // windowManager.postQueueManager?.queuedPostsCount ?? 0
            if queueCount > 0 {
                tooltip += "\n📋 \(queueCount) posts in queue"
            }
            
            return tooltip
            
        case .connecting:
            return "🔄 Connecting to X...\n🌐 Establishing secure connection\n⏳ Please wait"
            
        case .refreshing:
            return "🔄 Refreshing connection\n🔑 Updating credentials\n⏸️ Posting temporarily paused"
            
        case .disconnected:
            var tooltip = "❌ Disconnected from X\n🚫 Posting disabled"
            
            let queueCount = 0 // windowManager.postQueueManager?.queuedPostsCount ?? 0
            if queueCount > 0 {
                tooltip += "\n📋 \(queueCount) posts queued"
            }
            
            tooltip += "\n🔧 Click to reconnect"
            return tooltip
            
        case .error:
            return "⚠️ Connection error\n🔗 Check network connection\n🔄 Click to retry"
        }
    }
    
    static func createDetailedTooltip(for status: ConnectionStatus, windowManager: WindowManager) -> [String] {
        switch status {
        case .connected:
            var details = [
                "• Posting enabled",
                "• Rate limit: 98/100 requests",
                "• Connection: Secure",
                "• Last sync: Just now"
            ]
            
            let queueCount = 0 // windowManager.postQueueManager?.queuedPostsCount ?? 0
            if queueCount > 0 {
                details.append("• Queue: \(queueCount) posts pending")
            }
            
            return details
            
        case .connecting:
            return [
                "• Establishing secure connection",
                "• Network quality: Good",
                "• Please wait...",
                "• Auto-retry: Enabled"
            ]
            
        case .refreshing:
            return [
                "• Updating authentication tokens",
                "• Posting temporarily disabled",
                "• Connection will resume automatically",
                "• Please do not close the app"
            ]
            
        case .disconnected:
            var details = [
                "• Posting disabled",
                "• Network connection lost",
                "• Click anywhere to reconnect"
            ]
            
            let queueCount = 0 // windowManager.postQueueManager?.queuedPostsCount ?? 0
            if queueCount > 0 {
                details.append("• \(queueCount) posts will sync when reconnected")
            }
            
            return details
            
        case .error:
            return [
                "• Authentication failed",
                "• Check internet connection",
                "• Verify X account access",
                "• Click to retry connection"
            ]
        }
    }
}

// MARK: - Smart Status Indicator with Adaptive Tooltips

struct SmartStatusIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var isHovered = false
    @State private var hoverDuration: TimeInterval = 0
    @State private var showAdvancedTooltip = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .opacity(isHovered || isFocused ? 1.0 : 0.7)
            .overlay(
                // Subtle pulse animation
                Circle()
                    .stroke(statusColor.opacity(0.3), lineWidth: 1)
                    .scaleEffect(isHovered || isFocused ? 1.5 : 1.0)
                    .opacity(isHovered || isFocused ? 0.5 : 0.0)
            )
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
            .onHover { hovering in
                isHovered = hovering
                
                if hovering {
                    // Track hover duration for advanced tooltip
                    let startTime = Date()
                    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        if isHovered {
                            hoverDuration = Date().timeIntervalSince(startTime)
                            if hoverDuration > 1.5 && !showAdvancedTooltip {
                                showAdvancedTooltip = true
                            }
                        } else {
                            timer.invalidate()
                            hoverDuration = 0
                            showAdvancedTooltip = false
                        }
                    }
                } else {
                    showAdvancedTooltip = false
                }
            }
            .onTapGesture {
                handleUserInteraction()
            }
            .onKeyPress(.return) {
                handleUserInteraction()
                return .handled
            }
            .onKeyPress(.space) {
                handleUserInteraction()
                return .handled
            }
            .help(tooltipText)
            .animation(.easeInOut(duration: 0.2), value: isHovered || isFocused)
    }
    
    private var statusColor: Color {
        switch windowManager.connectionStatus {
        case .connected: return .green
        case .connecting, .refreshing: return .blue
        case .disconnected, .error: return .red
        }
    }
    
    private var tooltipText: String {
        if showAdvancedTooltip {
            let basicTooltip = StatusTooltipFactory.createTooltip(for: windowManager.connectionStatus, windowManager: windowManager)
            let details = StatusTooltipFactory.createDetailedTooltip(for: windowManager.connectionStatus, windowManager: windowManager)
            return basicTooltip + "\n\n" + details.joined(separator: "\n")
        } else {
            return StatusTooltipFactory.createTooltip(for: windowManager.connectionStatus, windowManager: windowManager)
        }
    }
    
    // MARK: - Accessibility Support
    
    private var accessibilityLabel: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Smart status indicator - Connected"
        case .connecting:
            return "Smart status indicator - Connecting"
        case .refreshing:
            return "Smart status indicator - Refreshing"
        case .disconnected:
            return "Smart status indicator - Disconnected"
        case .error:
            return "Smart status indicator - Error"
        }
    }
    
    private var accessibilityHint: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Shows active X connection. Double tap for detailed status."
        case .connecting:
            return "Connection to X in progress. Double tap for progress details."
        case .refreshing:
            return "Refreshing X connection. Double tap for refresh status."
        case .disconnected:
            return "Not connected to X. Double tap to reconnect."
        case .error:
            return "Connection error occurred. Double tap to retry."
        }
    }
    
    private var accessibilityValue: String {
        let colorDescription = switch windowManager.connectionStatus {
        case .connected: "Green indicator"
        case .connecting, .refreshing: "Blue indicator"
        case .disconnected, .error: "Red indicator"
        }
        
        return colorDescription + " with adaptive tooltip"
    }
    
    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = [.button]
        
        switch windowManager.connectionStatus {
        case .connected:
            traits.insert(.updatesFrequently)
        case .connecting, .refreshing:
            traits.insert(.updatesFrequently)
        case .disconnected, .error:
            traits.insert(.startsMediaSession)
        }
        
        return traits
    }
    
    private var accessibilityActionName: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "View detailed status"
        case .connecting, .refreshing:
            return "Check connection progress"
        case .disconnected:
            return "Reconnect to X"
        case .error:
            return "Retry connection"
        }
    }
    
    private func performAccessibilityAction() {
        switch windowManager.connectionStatus {
        case .disconnected, .error:
            windowManager.authManager?.refreshAuthenticationIfNeeded()
        case .connected, .connecting, .refreshing:
            announceDetailedStatus()
        }
    }
    
    private func handleUserInteraction() {
        performAccessibilityAction()
        isFocused = true
        showAdvancedTooltip = true
    }
    
    private func announceDetailedStatus() {
        let basicTooltip = StatusTooltipFactory.createTooltip(for: windowManager.connectionStatus, windowManager: windowManager)
        let cleanTooltip = stripEmojis(from: basicTooltip)
        
        var announcement = accessibilityLabel + ". " + cleanTooltip
        
        if showAdvancedTooltip {
            let details = StatusTooltipFactory.createDetailedTooltip(for: windowManager.connectionStatus, windowManager: windowManager)
            announcement += ". Additional details: " + details.joined(separator: ", ")
        }
        
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
    
    private func stripEmojis(from text: String) -> String {
        return text.replacingOccurrences(of: "✅", with: "")
                  .replacingOccurrences(of: "🔄", with: "")
                  .replacingOccurrences(of: "❌", with: "")
                  .replacingOccurrences(of: "⚠️", with: "")
                  .replacingOccurrences(of: "📤", with: "")
                  .replacingOccurrences(of: "⚡", with: "")
                  .replacingOccurrences(of: "🌐", with: "")
                  .replacingOccurrences(of: "⏳", with: "")
                  .replacingOccurrences(of: "🔑", with: "")
                  .replacingOccurrences(of: "⏸️", with: "")
                  .replacingOccurrences(of: "🚫", with: "")
                  .replacingOccurrences(of: "📋", with: "")
                  .replacingOccurrences(of: "🔧", with: "")
                  .replacingOccurrences(of: "🔗", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Previews

#Preview("Enhanced Discrete Status - Connected") {
    EnhancedDiscreteStatusIndicator(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Enhanced Discrete Status - Disconnected") {
    EnhancedDiscreteStatusIndicator(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }())
    .padding()
}

#Preview("Minimalist Status Dot") {
    HStack(spacing: 20) {
        MinimalistStatusDot(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connected
            return wm
        }())
        
        MinimalistStatusDot(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connecting
            return wm
        }())
        
        MinimalistStatusDot(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .disconnected
            return wm
        }())
    }
    .padding()
}

#Preview("Connection Quality Indicator") {
    ConnectionQualityIndicator(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Discrete Status Bar") {
    DiscreteStatusBar(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Smart Status Indicator") {
    HStack(spacing: 20) {
        SmartStatusIndicator(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connected
            return wm
        }())
        
        SmartStatusIndicator(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connecting
            return wm
        }())
        
        SmartStatusIndicator(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .disconnected
            return wm
        }())
    }
    .padding()
}

#Preview("Tooltip View") {
    VStack(spacing: 20) {
        TooltipView(
            title: "Connected to X",
            subtitle: "as @username",
            details: [
                "• Posting enabled",
                "• Rate limit: 98/100",
                "• Connection: Secure"
            ],
            statusColor: .green
        )
        
        TooltipView(
            title: "Connection Error",
            subtitle: "Authentication failed",
            details: [
                "• Check internet connection",
                "• Verify account access",
                "• Click to retry"
            ],
            statusColor: .red
        )
    }
    .padding()
}
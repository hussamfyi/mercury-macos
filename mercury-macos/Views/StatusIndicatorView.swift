//
//  StatusIndicatorView.swift
//  Mercury
//
//  Created by Claude on 2025-06-15.
//

import SwiftUI
import Combine

struct StatusIndicatorView: View {
    @ObservedObject var windowManager: WindowManager
    @State private var animationOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var cancellables = Set<AnyCancellable>()
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Enhanced animated status icon
            StatusTransitionAnimation(windowManager: windowManager)
            statusText
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusBackgroundColor)
        .cornerRadius(12)
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
            setupAnimations()
        }
    }
    
    // MARK: - Status Icon
    
    @ViewBuilder
    private var statusIcon: some View {
        Group {
            switch windowManager.connectionStatus {
            case .connected:
                connectedIcon
            case .connecting:
                connectingIcon
            case .disconnected:
                disconnectedIcon
            case .error:
                errorIcon
            case .refreshing:
                refreshingIcon
            }
        }
        .frame(width: 12, height: 12)
    }
    
    private var connectedIcon: some View {
        ZStack {
            // Outer glow effect
            Circle()
                .fill(Color.green.opacity(0.3))
                .scaleEffect(pulseScale * 1.5)
                .animation(
                    Animation.easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // Main green dot
            Circle()
                .fill(Color.green)
                .shadow(color: .green.opacity(0.6), radius: 2, x: 0, y: 0)
        }
    }
    
    private var connectingIcon: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
            
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    Color.blue,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(animationOffset))
        }
    }
    
    private var refreshingIcon: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
            
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    Color.orange,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(animationOffset))
        }
    }
    
    private var disconnectedIcon: some View {
        ZStack {
            // Outer warning glow for disconnected state
            Circle()
                .fill(Color.red.opacity(0.3))
                .scaleEffect(pulseScale * 1.5)
                .animation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // Main red warning dot
            Circle()
                .fill(Color.red)
                .shadow(color: .red.opacity(0.6), radius: 2, x: 0, y: 0)
        }
    }
    
    private var errorIcon: some View {
        Circle()
            .fill(Color.red)
            .scaleEffect(pulseScale)
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                value: pulseScale
            )
    }
    
    // MARK: - Status Text
    
    @ViewBuilder
    private var statusText: some View {
        Text(statusMessage)
            .font(.caption2)
            .foregroundColor(statusTextColor)
            .lineLimit(1)
    }
    
    private var statusMessage: String {
        switch windowManager.connectionStatus {
        case .connected:
            if let authManager = windowManager.authManager,
               let user = authManager.currentUser {
                return "Connected to @\(user.username)"
            } else {
                return "Connected to X"
            }
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Not connected"
        case .error:
            return "Connection error"
        case .refreshing:
            return "Refreshing..."
        }
    }
    
    // MARK: - Styling
    
    private var statusBackgroundColor: Color {
        switch windowManager.connectionStatus {
        case .connected:
            return Color.green.opacity(0.1)
        case .connecting, .refreshing:
            return Color.blue.opacity(0.1)
        case .disconnected:
            return Color.gray.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        }
    }
    
    private var statusTextColor: Color {
        switch windowManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .refreshing:
            return .blue
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
    
    // MARK: - Animations
    
    private func setupAnimations() {
        // Spinning animation for connecting/refreshing states
        Timer.publish(every: 0.02, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.linear(duration: 0.02)) {
                    animationOffset += 6
                    if animationOffset >= 360 {
                        animationOffset = 0
                    }
                }
            }
            .store(in: &cancellables)
        
        // Pulse animation for connected/error states
        withAnimation(
            Animation.easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.2
        }
    }
    
    // MARK: - Accessibility Support
    
    private var accessibilityLabel: String {
        switch windowManager.connectionStatus {
        case .connected:
            if let user = windowManager.authManager?.currentUser {
                return "Status indicator - Connected to X as \(user.username)"
            } else {
                return "Status indicator - Connected to X"
            }
        case .connecting:
            return "Status indicator - Connecting to X"
        case .refreshing:
            return "Status indicator - Refreshing X connection"
        case .disconnected:
            return "Status indicator - Disconnected from X"
        case .error:
            return "Status indicator - X connection error"
        }
    }
    
    private var accessibilityHint: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "X connection is active, posting is enabled. Double tap for details."
        case .connecting:
            return "Connection to X in progress. Please wait."
        case .refreshing:
            return "Refreshing X credentials. Posting temporarily disabled."
        case .disconnected:
            return "Not connected to X. Posting disabled. Double tap to reconnect."
        case .error:
            return "Connection error occurred. Double tap to retry connection."
        }
    }
    
    private var accessibilityValue: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Green status indicator with animated pulse"
        case .connecting:
            return "Blue spinning indicator"
        case .refreshing:
            return "Orange spinning indicator"
        case .disconnected:
            return "Gray status indicator"
        case .error:
            return "Red pulsing error indicator"
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
            return "View connection details"
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
        var announcement = accessibilityLabel + ". " + accessibilityValue
        
        // Add contextual information
        switch windowManager.connectionStatus {
        case .connected:
            announcement += ". Posting is enabled and working properly."
        case .connecting:
            announcement += ". Establishing secure connection to X servers."
        case .refreshing:
            announcement += ". Updating authentication tokens with X."
        case .disconnected:
            announcement += ". Connection to X has been lost. Posting is disabled."
        case .error:
            announcement += ". Connection to X failed. Check your internet connection."
        }
        
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
}

// MARK: - Compact Status Indicator

struct CompactStatusIndicatorView: View {
    @ObservedObject var windowManager: WindowManager
    @State private var animationOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        statusIcon
            .frame(width: 8, height: 8)
            .onAppear {
                setupAnimations()
            }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch windowManager.connectionStatus {
        case .connected:
            ZStack {
                // Outer glow effect for compact view
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .scaleEffect(pulseScale * 1.8)
                    .animation(
                        Animation.easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                
                // Main green dot
                Circle()
                    .fill(Color.green)
                    .shadow(color: .green.opacity(0.6), radius: 1, x: 0, y: 0)
            }
        case .connecting:
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .rotationEffect(.degrees(animationOffset))
            }
        case .refreshing:
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        Color.orange,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .rotationEffect(.degrees(animationOffset))
            }
        case .disconnected:
            ZStack {
                // Outer warning glow for disconnected state
                Circle()
                    .fill(Color.red.opacity(0.4))
                    .frame(width: 12, height: 12)
                    .blur(radius: 1)
                
                // Main red warning dot
                Circle()
                    .fill(Color.red)
                    .scaleEffect(pulseScale)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: pulseScale
                    )
            }
        case .error:
            Circle()
                .fill(Color.red)
                .scaleEffect(pulseScale)
                .animation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                    value: pulseScale
                )
        }
    }
    
    private func setupAnimations() {
        // Spinning animation for connecting/refreshing states
        Timer.publish(every: 0.02, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.linear(duration: 0.02)) {
                    animationOffset += 6
                    if animationOffset >= 360 {
                        animationOffset = 0
                    }
                }
            }
            .store(in: &cancellables)
        
        // Pulse animation for connected/error states
        withAnimation(
            Animation.easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.2
        }
    }
}

// MARK: - Connection Status Badge

struct ConnectionStatusBadge: View {
    @ObservedObject var windowManager: WindowManager
    @State private var showTooltip = false
    
    var body: some View {
        Button(action: {
            // Handle status indicator tap - could show connection details
        }) {
            HStack(spacing: 4) {
                CompactStatusIndicatorView(windowManager: windowManager)
                
                if windowManager.connectionStatus == .connected {
                    Text("●")
                        .font(.system(size: 6))
                        .foregroundColor(.green)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltipText)
        .onHover { hovering in
            showTooltip = hovering
        }
    }
    
    private var tooltipText: String {
        switch windowManager.connectionStatus {
        case .connected:
            if let authManager = windowManager.authManager,
               let user = authManager.currentUser {
                return "Connected to X as @\(user.username)"
            } else {
                return "Connected to X"
            }
        case .connecting:
            return "Connecting to X..."
        case .disconnected:
            return "Not connected to X"
        case .error:
            return "Connection error - tap to retry"
        case .refreshing:
            return "Refreshing X connection..."
        }
    }
}

// MARK: - Detailed Status View

struct DetailedStatusView: View {
    @ObservedObject var windowManager: WindowManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusIndicatorView(windowManager: windowManager)
                Spacer()
            }
            
            if windowManager.connectionStatus == .connected,
               let authManager = windowManager.authManager,
               let user = authManager.currentUser {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account: @\(user.username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let displayName = user.displayName {
                        Text("Name: \(displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Last connected: \(formattedLastConnectedTime)")
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                }
            }
            
            if windowManager.connectionStatus == .error {
                Button("Retry Connection") {
                    // Handle retry connection
                    Task {
                        await windowManager.authManager?.refreshAuthentication()
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var formattedLastConnectedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }
}

// MARK: - Connected Account Display (Task 4.12)

struct ConnectedAccountDisplay: View {
    @ObservedObject var windowManager: WindowManager
    @State private var showFullDisplay = false
    @State private var avatarLoadError = false
    
    var body: some View {
        if let authManager = windowManager.authManager,
           let user = authManager.currentUser,
           windowManager.connectionStatus.isConnected {
            
            HStack(spacing: 12) {
                // Avatar with fallback
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    if avatarLoadError {
                        // Fallback avatar
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                            
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue.opacity(0.6))
                                .font(.system(size: 16))
                        }
                    } else {
                        // Loading indicator
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                            
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(connectionStatusColor, lineWidth: 2)
                )
                .onAppear {
                    avatarLoadError = false
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // User information
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if user.verified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 12))
                        }
                    }
                    
                    Text("@\(user.username)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Connection status and last activity
                    HStack(spacing: 8) {
                        ConnectionStatusIndicator(status: windowManager.connectionStatus)
                        
                        if showFullDisplay {
                            Text("•")
                                .foregroundColor(.tertiary)
                                .font(.system(size: 10))
                            
                            Text("Active \(lastActivityText)")
                                .font(.system(size: 10))
                                .foregroundColor(.tertiary)
                        }
                    }
                }
                
                Spacer()
                
                // Expand/collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullDisplay.toggle()
                    }
                }) {
                    Image(systemName: showFullDisplay ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(connectionStatusColor.opacity(0.3), lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.3), value: showFullDisplay)
        }
    }
    
    private var avatarURL: URL? {
        guard let authManager = windowManager.authManager,
              let user = authManager.currentUser,
              let urlString = user.profileImageUrl else {
            return nil
        }
        return URL(string: urlString)
    }
    
    private var connectionStatusColor: Color {
        switch windowManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .refreshing:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        case .disconnecting:
            return .orange
        }
    }
    
    private var lastActivityText: String {
        guard let authManager = windowManager.authManager,
              let user = authManager.currentUser else {
            return "unknown"
        }
        
        let now = Date()
        let interval = now.timeIntervalSince(user.authenticatedAt)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Connection Status Indicator Component

struct ConnectionStatusIndicator: View {
    let status: ConnectionStatus
    @State private var pulseOpacity: Double = 1.0
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .opacity(pulseOpacity)
                .animation(pulseAnimation, value: pulseOpacity)
            
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor)
        }
        .onAppear {
            startPulseAnimation()
        }
        .onChange(of: status) { _, _ in
            startPulseAnimation()
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting, .refreshing, .disconnecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .refreshing:
            return "Refreshing"
        case .disconnecting:
            return "Disconnecting"
        case .disconnected:
            return "Offline"
        case .error:
            return "Error"
        }
    }
    
    private var pulseAnimation: Animation? {
        switch status {
        case .connected:
            return Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
        case .connecting, .refreshing, .disconnecting:
            return Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        case .error:
            return Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        default:
            return nil
        }
    }
    
    private func startPulseAnimation() {
        if let animation = pulseAnimation {
            withAnimation(animation) {
                pulseOpacity = status == .connected ? 0.7 : 0.5
            }
        } else {
            pulseOpacity = 1.0
        }
    }
}

// MARK: - Compact Connected Account Display

struct CompactConnectedAccountDisplay: View {
    @ObservedObject var windowManager: WindowManager
    @State private var avatarLoadError = false
    
    var body: some View {
        if let authManager = windowManager.authManager,
           let user = authManager.currentUser,
           windowManager.connectionStatus.isConnected {
            
            HStack(spacing: 8) {
                // Compact avatar
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    if avatarLoadError {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                            
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue.opacity(0.6))
                                .font(.system(size: 10))
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                            
                            ProgressView()
                                .scaleEffect(0.4)
                        }
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(connectionStatusColor, lineWidth: 1.5)
                )
                
                // Username and status
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(user.username)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    ConnectionStatusIndicator(status: windowManager.connectionStatus)
                }
                
                Spacer()
            }
        }
    }
    
    private var avatarURL: URL? {
        guard let authManager = windowManager.authManager,
              let user = authManager.currentUser,
              let urlString = user.profileImageUrl else {
            return nil
        }
        return URL(string: urlString)
    }
    
    private var connectionStatusColor: Color {
        switch windowManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .refreshing:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        case .disconnecting:
            return .orange
        }
    }
}

// MARK: - Not Authenticated Warning Display

struct NotAuthenticatedWarning: View {
    @ObservedObject var windowManager: WindowManager
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4
    @State private var showingReconnection = false
    
    var body: some View {
        if windowManager.connectionStatus.isDisconnected || windowManager.connectionStatus.isError {
            HStack(spacing: 10) {
                // Prominent red warning indicator
                ZStack {
                    // Outer pulsing glow
                    Circle()
                        .fill(Color.red.opacity(glowOpacity))
                        .frame(width: 20, height: 20)
                        .scaleEffect(pulseScale * 1.6)
                        .blur(radius: 3)
                    
                    // Inner bright glow
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 14, height: 14)
                        .scaleEffect(pulseScale * 1.2)
                        .blur(radius: 1)
                    
                    // Core warning dot
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.red.opacity(0.9),
                                    Color.red
                                ]),
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 6
                            )
                        )
                        .frame(width: 10, height: 10)
                        .shadow(color: .red.opacity(0.8), radius: 4, x: 0, y: 0)
                    
                    // Warning icon overlay
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Warning message
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not authenticated")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                    
                    Text("Posting is disabled until you connect")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Intelligent contextual reconnect button (task 4.6)
                ContextualReconnectButton(windowManager: windowManager, placement: .header)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
                    )
            )
            .onAppear {
                startWarningAnimation()
            }
            .sheet(isPresented: $showingReconnection) {
                ReconnectionView(windowManager: windowManager)
                    .frame(width: 380, height: 350)
            }
        }
    }
    
    private func startWarningAnimation() {
        // Warning pulse animation
        withAnimation(
            Animation.easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
        ) {
            glowOpacity = 0.7
        }
        
        // Urgent pulsing for the dot
        withAnimation(
            Animation.easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.3
        }
    }
}

// MARK: - Connected Status Display

struct ConnectedStatusDisplay: View {
    @ObservedObject var windowManager: WindowManager
    @State private var glowOpacity: Double = 0.3
    @State private var dotScale: CGFloat = 1.0
    
    var body: some View {
        if windowManager.connectionStatus == .connected {
            HStack(spacing: 8) {
                // Enhanced green dot with glow
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(Color.green.opacity(glowOpacity))
                        .frame(width: 16, height: 16)
                        .scaleEffect(dotScale * 1.4)
                        .blur(radius: 2)
                    
                    // Inner bright glow
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 12, height: 12)
                        .scaleEffect(dotScale * 1.1)
                        .blur(radius: 1)
                    
                    // Core dot
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.green.opacity(0.9),
                                    Color.green
                                ]),
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 6
                            )
                        )
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.7), radius: 3, x: 0, y: 0)
                }
                
                // Connected status text
                Text(connectedStatusText)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
            .onAppear {
                startConnectedAnimation()
            }
        }
    }
    
    private var connectedStatusText: String {
        if let authManager = windowManager.authManager,
           let user = authManager.currentUser {
            return "Connected to @\(user.username)"
        } else {
            return "Connected to X"
        }
    }
    
    private func startConnectedAnimation() {
        // Gentle pulsing glow
        withAnimation(
            Animation.easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true)
        ) {
            glowOpacity = 0.6
        }
        
        // Subtle dot scaling
        withAnimation(
            Animation.easeInOut(duration: 2.5)
                .repeatForever(autoreverses: true)
        ) {
            dotScale = 1.15
        }
    }
}

// MARK: - Authentication Status Header

struct AuthenticationStatusHeader: View {
    @ObservedObject var windowManager: WindowManager
    let useMinimalistDesign: Bool
    
    var body: some View {
        if useMinimalistDesign {
            MinimalistAuthHeader(windowManager: windowManager)
        } else {
            VStack(spacing: 8) {
                // Primary status display
                Group {
                    switch windowManager.connectionStatus {
                    case .connected:
                        ConnectedStatusDisplay(windowManager: windowManager)
                    case .connecting:
                        connectingStatusDisplay
                    case .disconnected, .error:
                        // Prominent warning for not authenticated states
                        NotAuthenticatedWarning(windowManager: windowManager)
                    case .refreshing:
                        refreshingStatusDisplay
                    }
                }
                
                // Secondary compact status (only for connected state)
                if windowManager.connectionStatus == .connected {
                    HStack {
                        Spacer()
                        ConnectionStatusBadge(windowManager: windowManager)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: windowManager.connectionStatus)
        }
    }
    
    private var connectingStatusDisplay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text("Connecting to X...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var disconnectedStatusDisplay: some View {
        HStack(spacing: 8) {
            // Red indicator for not authenticated state
            ZStack {
                // Outer warning glow
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .blur(radius: 1)
                
                // Main red dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.5), radius: 2, x: 0, y: 0)
            }
            
            Text("Not connected - posting disabled")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var errorStatusDisplay: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 10))
            
            Text("Connection error")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var refreshingStatusDisplay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
            
            Text("Refreshing connection...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Posting Disabled Indicator

struct PostingDisabledIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var pulseOpacity: Double = 0.6
    
    var body: some View {
        if shouldShowPostingDisabled {
            HStack(spacing: 6) {
                // Warning icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .opacity(pulseOpacity)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: pulseOpacity
                    )
                
                Text("Posting disabled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )
            .onAppear {
                startPulseAnimation()
            }
        }
    }
    
    private var shouldShowPostingDisabled: Bool {
        switch windowManager.connectionStatus {
        case .disconnected, .error:
            return true
        case .connecting, .refreshing:
            return false
        case .connected:
            return false
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(
            Animation.easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
        ) {
            pulseOpacity = 1.0
        }
    }
}

// MARK: - Ultra-Subtle Status Indicators (Task 4.5)

struct MinimalStatusIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var subtleOpacity: Double = 0.6
    
    var body: some View {
        HStack(spacing: 4) {
            // Ultra-minimal status dot
            Circle()
                .fill(statusColor)
                .frame(width: 4, height: 4)
                .opacity(subtleOpacity)
                .animation(
                    statusPulseAnimation,
                    value: subtleOpacity
                )
            
            // Extremely subtle text (only when relevant)
            if shouldShowStatusText {
                Text(statusText)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(statusColor)
                    .opacity(0.7)
            }
        }
        .onAppear {
            startSubtleAnimation()
        }
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
    
    private var statusText: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "●"
        case .connecting:
            return "○"
        case .refreshing:
            return "◐"
        case .disconnected, .error:
            return "○"
        }
    }
    
    private var shouldShowStatusText: Bool {
        // Only show for non-connected states to minimize visual noise
        switch windowManager.connectionStatus {
        case .connected:
            return false
        default:
            return true
        }
    }
    
    private var statusPulseAnimation: Animation? {
        switch windowManager.connectionStatus {
        case .connected:
            return Animation.easeInOut(duration: 4.0).repeatForever(autoreverses: true)
        case .disconnected, .error:
            return Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
        default:
            return nil
        }
    }
    
    private func startSubtleAnimation() {
        if windowManager.connectionStatus.isConnected {
            withAnimation(statusPulseAnimation) {
                subtleOpacity = 0.9
            }
        } else if windowManager.connectionStatus.isDisconnected || windowManager.connectionStatus.isError {
            withAnimation(statusPulseAnimation) {
                subtleOpacity = 0.8
            }
        }
    }
}

struct DiscreteConnectionIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var hoverOpacity: Double = 0.3
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            // Base indicator - nearly invisible when not hovered
            Rectangle()
                .fill(statusGradient)
                .frame(width: 2, height: 12)
                .opacity(isHovered ? 0.8 : hoverOpacity)
                .cornerRadius(1)
            
            // Hover expansion
            if isHovered {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(statusGradient)
                        .frame(width: 2, height: 12)
                        .cornerRadius(1)
                    
                    Text(connectionStatusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary.opacity(0.7))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onAppear {
            startDiscreteAnimation()
        }
    }
    
    private var statusGradient: LinearGradient {
        switch windowManager.connectionStatus {
        case .connected:
            return LinearGradient(
                colors: [.green.opacity(0.8), .green.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .connecting, .refreshing:
            return LinearGradient(
                colors: [.blue.opacity(0.8), .blue.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .disconnected, .error:
            return LinearGradient(
                colors: [.red.opacity(0.8), .red.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var connectionStatusText: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .refreshing:
            return "Refreshing"
        case .disconnected:
            return "Offline"
        case .error:
            return "Error"
        }
    }
    
    private func startDiscreteAnimation() {
        // Very subtle pulse for different states
        let animation: Animation? = switch windowManager.connectionStatus {
        case .connected:
            Animation.easeInOut(duration: 6.0).repeatForever(autoreverses: true)
        case .disconnected, .error:
            Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)
        default:
            nil
        }
        
        if let animation = animation {
            withAnimation(animation) {
                hoverOpacity = windowManager.connectionStatus.isConnected ? 0.6 : 0.5
            }
        }
    }
}

struct PeripheralStatusGlow: View {
    @ObservedObject var windowManager: WindowManager
    @State private var glowIntensity: Double = 0.0
    
    var body: some View {
        // Extremely subtle glow around the window edge
        RoundedRectangle(cornerRadius: 12)
            .stroke(glowColor, lineWidth: 1)
            .opacity(glowIntensity)
            .blur(radius: 1)
            .allowsHitTesting(false)
            .onAppear {
                startPeripheralGlow()
            }
            .onChange(of: windowManager.connectionStatus) { _, _ in
                updateGlowForStatus()
            }
    }
    
    private var glowColor: Color {
        switch windowManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .refreshing:
            return .blue
        case .disconnected, .error:
            return .red
        }
    }
    
    private func startPeripheralGlow() {
        updateGlowForStatus()
    }
    
    private func updateGlowForStatus() {
        let targetIntensity: Double = switch windowManager.connectionStatus {
        case .connected:
            0.1
        case .connecting, .refreshing:
            0.15
        case .disconnected, .error:
            0.2
        }
        
        let duration: Double = switch windowManager.connectionStatus {
        case .connected:
            4.0
        case .connecting, .refreshing:
            2.0
        case .disconnected, .error:
            1.5
        }
        
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            glowIntensity = targetIntensity
        }
    }
}

struct MinimalistAuthHeader: View {
    @ObservedObject var windowManager: WindowManager
    
    var body: some View {
        HStack {
            // Ultra-minimal status when connected
            if windowManager.connectionStatus.isConnected {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 3, height: 3)
                        .opacity(0.6)
                    
                    if let user = windowManager.authManager?.currentUser {
                        Text("@\(user.username)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.primary.opacity(0.5))
                    }
                }
            } else {
                // Intelligent reconnect placement for minimalist design
                HStack(spacing: 8) {
                    // Subtle disconnect indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 3, height: 3)
                            .opacity(0.6)
                        
                        Text("Offline")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.primary.opacity(0.5))
                    }
                    
                    // Contextual reconnect with minimal style
                    ContextualReconnectButton(windowManager: windowManager, placement: .minimal)
                }
            }
            
            Spacer()
            
            // Enhanced discrete side indicator (task 4.7)
            EnhancedDiscreteStatusIndicator(windowManager: windowManager)
        }
        .animation(.easeInOut(duration: 0.3), value: windowManager.connectionStatus)
    }
}

// MARK: - Previews

#Preview("Status Indicator - Connected") {
    StatusIndicatorView(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Status Indicator - Connecting") {
    StatusIndicatorView(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connecting
        return wm
    }())
    .padding()
}

#Preview("Status Indicator - Disconnected") {
    StatusIndicatorView(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }())
    .padding()
}

#Preview("Status Indicator - Error") {
    StatusIndicatorView(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .error
        return wm
    }())
    .padding()
}

#Preview("Compact Status Indicator") {
    HStack(spacing: 16) {
        CompactStatusIndicatorView(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connected
            return wm
        }())
        
        CompactStatusIndicatorView(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connecting
            return wm
        }())
        
        CompactStatusIndicatorView(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .disconnected
            return wm
        }())
        
        CompactStatusIndicatorView(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .error
            return wm
        }())
    }
    .padding()
}

#Preview("Connection Status Badge") {
    ConnectionStatusBadge(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Detailed Status View") {
    DetailedStatusView(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Connected Status Display") {
    ConnectedStatusDisplay(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Authentication Status Header - Connected") {
    AuthenticationStatusHeader(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }(), useMinimalistDesign: false)
    .padding()
}

#Preview("Authentication Status Header - Connecting") {
    AuthenticationStatusHeader(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connecting
        return wm
    }(), useMinimalistDesign: false)
    .padding()
}

#Preview("Authentication Status Header - Disconnected") {
    AuthenticationStatusHeader(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }(), useMinimalistDesign: false)
    .padding()
}

#Preview("Authentication Status Header - Error") {
    AuthenticationStatusHeader(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .error
        return wm
    }(), useMinimalistDesign: false)
    .padding()
}

#Preview("Minimalist Auth Header - Connected") {
    AuthenticationStatusHeader(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }(), useMinimalistDesign: true)
    .padding()
}

#Preview("Minimalist Auth Header - Disconnected") {
    AuthenticationStatusHeader(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }(), useMinimalistDesign: true)
    .padding()
}

#Preview("Minimal Status Indicator") {
    HStack(spacing: 20) {
        MinimalStatusIndicator(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connected
            return wm
        }())
        
        MinimalStatusIndicator(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .connecting
            return wm
        }())
        
        MinimalStatusIndicator(windowManager: {
            let wm = WindowManager.shared
            wm.connectionStatus = .disconnected
            return wm
        }())
    }
    .padding()
}

#Preview("Discrete Connection Indicator") {
    DiscreteConnectionIndicator(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected
        return wm
    }())
    .padding()
}

#Preview("Not Authenticated Warning") {
    NotAuthenticatedWarning(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }())
    .padding()
}

#Preview("Posting Disabled Indicator") {
    PostingDisabledIndicator(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }())
    .padding()
}

#Preview("Connected Account Display") {
    ConnectedAccountDisplay(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected(user: ConnectedUserInfo(
            username: "testuser",
            displayName: "Test User",
            profileImageUrl: "https://example.com/avatar.jpg",
            isVerified: true
        ))
        return wm
    }())
    .padding()
}

#Preview("Compact Connected Account Display") {
    CompactConnectedAccountDisplay(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .connected(user: ConnectedUserInfo(
            username: "testuser",
            displayName: "Test User",
            profileImageUrl: "https://example.com/avatar.jpg",
            isVerified: false
        ))
        return wm
    }())
    .padding()
}
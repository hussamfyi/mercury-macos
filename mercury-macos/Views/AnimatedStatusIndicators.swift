//
//  AnimatedStatusIndicators.swift
//  Mercury
//
//  Created by Claude on 2025-06-15.
//

import SwiftUI
import Combine

// MARK: - Smooth Animated Status Indicators

struct AnimatedStatusIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var animationPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Angle = .zero
    @State private var waveOffset: CGFloat = 0
    @State private var breathingScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.3
    @State private var cancellables = Set<AnyCancellable>()
    @FocusState private var isFocused: Bool
    
    private let animationTimer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect() // 60fps
    
    var body: some View {
        ZStack {
            // Background glow layer
            backgroundGlow
            
            // Main status indicator
            mainIndicator
            
            // Overlay effects
            overlayEffects
        }
        .frame(width: indicatorSize.width, height: indicatorSize.height)
        .focusable()
        .focused($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(accessibilityTraits)
        .onReceive(animationTimer) { _ in
            updateAnimations()
        }
        .onAppear {
            startStateAnimation()
        }
        .onChange(of: windowManager.connectionStatus) { _, newStatus in
            withAnimation(.easeInOut(duration: 0.5)) {
                transitionToNewState(newStatus)
            }
        }
    }
    
    // MARK: - Size Configuration
    
    private var indicatorSize: CGSize {
        switch windowManager.connectionStatus {
        case .connected:
            return CGSize(width: 16, height: 16)
        case .connecting, .refreshing:
            return CGSize(width: 18, height: 18)
        case .disconnected:
            return CGSize(width: 14, height: 14)
        case .error:
            return CGSize(width: 20, height: 20)
        }
    }
    
    // MARK: - Background Glow
    
    @ViewBuilder
    private var backgroundGlow: some View {
        switch windowManager.connectionStatus {
        case .connected:
            connectedGlow
        case .connecting:
            connectingGlow
        case .refreshing:
            refreshingGlow
        case .disconnected:
            disconnectedGlow
        case .error:
            errorGlow
        }
    }
    
    private var connectedGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .green.opacity(glowIntensity * 0.8),
                        .green.opacity(glowIntensity * 0.4),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 20
                )
            )
            .scaleEffect(breathingScale * 2.0)
            .animation(
                .easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                value: breathingScale
            )
    }
    
    private var connectingGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .blue.opacity(glowIntensity * 0.6),
                        .blue.opacity(glowIntensity * 0.3),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 24
                )
            )
            .scaleEffect(pulseScale * 2.2)
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: pulseScale
            )
    }
    
    private var refreshingGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .orange.opacity(glowIntensity * 0.7),
                        .orange.opacity(glowIntensity * 0.35),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 22
                )
            )
            .scaleEffect(1.8)
            .rotationEffect(rotationAngle)
    }
    
    private var disconnectedGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .gray.opacity(glowIntensity * 0.3),
                        .gray.opacity(glowIntensity * 0.1),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 16
                )
            )
            .scaleEffect(1.5)
    }
    
    private var errorGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .red.opacity(glowIntensity * 0.9),
                        .red.opacity(glowIntensity * 0.5),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 25
                )
            )
            .scaleEffect(pulseScale * 2.3)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: pulseScale
            )
    }
    
    // MARK: - Main Indicator
    
    @ViewBuilder
    private var mainIndicator: some View {
        switch windowManager.connectionStatus {
        case .connected:
            connectedIndicator
        case .connecting:
            connectingIndicator
        case .refreshing:
            refreshingIndicator
        case .disconnected:
            disconnectedIndicator
        case .error:
            errorIndicator
        }
    }
    
    private var connectedIndicator: some View {
        ZStack {
            // Stable center dot
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 10, height: 10)
                .shadow(color: .green.opacity(0.6), radius: 3, x: 0, y: 1)
            
            // Subtle breathing animation
            Circle()
                .stroke(.green.opacity(0.4), lineWidth: 1)
                .frame(width: 14, height: 14)
                .scaleEffect(breathingScale)
        }
    }
    
    private var connectingIndicator: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(.blue.opacity(0.2), lineWidth: 2)
                .frame(width: 14, height: 14)
            
            // Animated arc segments
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 14, height: 14)
                    .rotationEffect(rotationAngle + .degrees(Double(index) * 120))
                    .opacity(0.8 - Double(index) * 0.2)
            }
        }
    }
    
    private var refreshingIndicator: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(.orange.opacity(0.2), lineWidth: 2)
                .frame(width: 14, height: 14)
            
            // Bidirectional rotation effect
            Circle()
                .trim(from: 0, to: 0.6)
                .stroke(
                    AngularGradient(
                        colors: [.orange, .orange.opacity(0.8), .orange.opacity(0.4), .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 14, height: 14)
                .rotationEffect(rotationAngle)
            
            // Counter-rotating inner element
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(.orange.opacity(0.6), lineWidth: 1)
                .frame(width: 8, height: 8)
                .rotationEffect(-rotationAngle * 1.5)
        }
    }
    
    private var disconnectedIndicator: some View {
        ZStack {
            // Faded circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.gray.opacity(0.6), .gray.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 10, height: 10)
            
            // Subtle disconnection indicator
            Rectangle()
                .fill(.gray.opacity(0.8))
                .frame(width: 8, height: 1)
                .rotationEffect(.degrees(45))
            
            Rectangle()
                .fill(.gray.opacity(0.8))
                .frame(width: 8, height: 1)
                .rotationEffect(.degrees(-45))
        }
    }
    
    private var errorIndicator: some View {
        ZStack {
            // Pulsing error background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.red, .red.opacity(0.7)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 16, height: 16)
                .scaleEffect(pulseScale)
            
            // Warning symbol
            Image(systemName: "exclamationmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
    }
    
    // MARK: - Overlay Effects
    
    @ViewBuilder
    private var overlayEffects: some View {
        switch windowManager.connectionStatus {
        case .connected:
            connectedOverlay
        case .connecting:
            connectingOverlay
        case .refreshing:
            refreshingOverlay
        case .disconnected:
            EmptyView()
        case .error:
            errorOverlay
        }
    }
    
    private var connectedOverlay: some View {
        // Periodic success flash
        Circle()
            .stroke(.green.opacity(0.8), lineWidth: 1)
            .frame(width: 20, height: 20)
            .scaleEffect(animationPhase > 0.95 ? 1.5 : 1.0)
            .opacity(animationPhase > 0.95 ? 0.0 : 0.6)
            .animation(.easeOut(duration: 0.3), value: animationPhase)
    }
    
    private var connectingOverlay: some View {
        // Expanding connection waves
        ForEach(0..<2, id: \.self) { index in
            Circle()
                .stroke(.blue.opacity(0.3), lineWidth: 1)
                .frame(width: 18, height: 18)
                .scaleEffect(1.0 + waveOffset + CGFloat(index) * 0.3)
                .opacity(1.0 - (waveOffset + CGFloat(index) * 0.3))
        }
    }
    
    private var refreshingOverlay: some View {
        // Spiral refresh effect
        ForEach(0..<4, id: \.self) { index in
            Circle()
                .trim(from: 0, to: 0.1)
                .stroke(.orange.opacity(0.4), lineWidth: 1)
                .frame(width: CGFloat(16 + index * 2), height: CGFloat(16 + index * 2))
                .rotationEffect(rotationAngle * Double(1 + index) * 0.3)
                .opacity(0.8 - CGFloat(index) * 0.15)
        }
    }
    
    private var errorOverlay: some View {
        // Alert rings
        ForEach(0..<3, id: \.self) { index in
            Circle()
                .stroke(.red.opacity(0.5), lineWidth: 1)
                .frame(width: CGFloat(22 + index * 4), height: CGFloat(22 + index * 4))
                .scaleEffect(pulseScale * (1.0 + CGFloat(index) * 0.1))
                .opacity(1.0 - CGFloat(index) * 0.25)
        }
    }
    
    // MARK: - Animation Logic
    
    private func updateAnimations() {
        switch windowManager.connectionStatus {
        case .connected:
            updateConnectedAnimation()
        case .connecting:
            updateConnectingAnimation()
        case .refreshing:
            updateRefreshingAnimation()
        case .disconnected:
            updateDisconnectedAnimation()
        case .error:
            updateErrorAnimation()
        }
    }
    
    private func updateConnectedAnimation() {
        // Gentle breathing and periodic flash
        animationPhase += 0.008 // Slow cycle
        if animationPhase >= 1.0 {
            animationPhase = 0
        }
        
        breathingScale = 1.0 + sin(animationPhase * 2 * .pi) * 0.05 // Subtle breathing
        glowIntensity = 0.3 + sin(animationPhase * 2 * .pi) * 0.1
    }
    
    private func updateConnectingAnimation() {
        // Rotating segments with wave propagation
        rotationAngle += .degrees(3) // Smooth rotation
        
        waveOffset += 0.02
        if waveOffset >= 1.0 {
            waveOffset = 0
        }
        
        pulseScale = 1.0 + sin(waveOffset * 2 * .pi) * 0.15
        glowIntensity = 0.4 + sin(waveOffset * 4 * .pi) * 0.2
    }
    
    private func updateRefreshingAnimation() {
        // Bidirectional rotation with variable speed
        let speedMultiplier = 1.0 + sin(animationPhase * .pi) * 0.5
        rotationAngle += .degrees(2.5 * speedMultiplier)
        
        animationPhase += 0.01
        if animationPhase >= 2.0 {
            animationPhase = 0
        }
        
        glowIntensity = 0.5 + sin(animationPhase * 3 * .pi) * 0.2
    }
    
    private func updateDisconnectedAnimation() {
        // Minimal subtle fade
        animationPhase += 0.005
        glowIntensity = 0.1 + sin(animationPhase * .pi) * 0.05
    }
    
    private func updateErrorAnimation() {
        // Urgent pulsing
        animationPhase += 0.025 // Faster cycle for urgency
        pulseScale = 1.0 + sin(animationPhase * 4 * .pi) * 0.2
        glowIntensity = 0.6 + sin(animationPhase * 6 * .pi) * 0.3
    }
    
    private func startStateAnimation() {
        // Initialize animation state
        animationPhase = 0
        pulseScale = 1.0
        rotationAngle = .zero
        waveOffset = 0
        breathingScale = 1.0
        glowIntensity = 0.3
    }
    
    private func transitionToNewState(_ newStatus: ConnectionStatus) {
        // Smooth transition between states
        switch newStatus {
        case .connected:
            breathingScale = 1.1
            glowIntensity = 0.6
        case .connecting:
            pulseScale = 1.2
            glowIntensity = 0.5
        case .refreshing:
            glowIntensity = 0.7
        case .disconnected:
            glowIntensity = 0.1
        case .error:
            pulseScale = 1.3
            glowIntensity = 0.8
        }
        
        // Reset to normal after transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 1.0)) {
                startStateAnimation()
            }
        }
    }
    
    // MARK: - Accessibility Support
    
    private var accessibilityLabel: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Animated status indicator - Connected with breathing effect"
        case .connecting:
            return "Animated status indicator - Connecting with rotating segments"
        case .refreshing:
            return "Animated status indicator - Refreshing with spiral effect"
        case .disconnected:
            return "Animated status indicator - Disconnected with subtle fade"
        case .error:
            return "Animated status indicator - Error with urgent pulsing"
        }
    }
    
    private var accessibilityHint: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Smooth green breathing animation indicates stable X connection"
        case .connecting:
            return "Blue rotating segments show connection in progress"
        case .refreshing:
            return "Orange spiral animation indicates credential refresh"
        case .disconnected:
            return "Gray faded indicator shows no connection"
        case .error:
            return "Red pulsing animation indicates connection error"
        }
    }
    
    private var accessibilityValue: String {
        switch windowManager.connectionStatus {
        case .connected:
            return "Green indicator with gentle breathing and glow"
        case .connecting:
            return "Blue indicator with rotating connection animation"
        case .refreshing:
            return "Orange indicator with bidirectional refresh animation"
        case .disconnected:
            return "Gray indicator with disconnection symbol"
        case .error:
            return "Red indicator with warning symbol and urgent pulsing"
        }
    }
    
    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = [.image]
        
        switch windowManager.connectionStatus {
        case .connected:
            traits.insert(.updatesFrequently)
        case .connecting, .refreshing:
            traits.insert(.updatesFrequently)
        case .error:
            traits.insert(.causesPageTurn)
        default:
            break
        }
        
        return traits
    }
}

// MARK: - Compact Animated Status

struct CompactAnimatedStatusIndicator: View {
    @ObservedObject var windowManager: WindowManager
    @State private var animationPhase: CGFloat = 0
    @State private var rotationAngle: Angle = .zero
    @State private var pulseScale: CGFloat = 1.0
    
    private let animationTimer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect() // 30fps for compact
    
    var body: some View {
        ZStack {
            statusIndicator
        }
        .frame(width: 8, height: 8)
        .onReceive(animationTimer) { _ in
            updateCompactAnimation()
        }
        .onAppear {
            startCompactAnimation()
        }
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch windowManager.connectionStatus {
        case .connected:
            Circle()
                .fill(.green)
                .scaleEffect(pulseScale)
                .shadow(color: .green.opacity(0.4), radius: 2, x: 0, y: 1)
                
        case .connecting:
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(.blue, lineWidth: 1.5)
                .rotationEffect(rotationAngle)
                
        case .refreshing:
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.orange, lineWidth: 1.5)
                .rotationEffect(rotationAngle)
                
        case .disconnected:
            Circle()
                .fill(.gray.opacity(0.6))
                .overlay(
                    Rectangle()
                        .fill(.gray)
                        .frame(width: 6, height: 0.8)
                        .rotationEffect(.degrees(45))
                )
                
        case .error:
            Circle()
                .fill(.red)
                .scaleEffect(pulseScale)
                .overlay(
                    Text("!")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundColor(.white)
                )
        }
    }
    
    private func updateCompactAnimation() {
        switch windowManager.connectionStatus {
        case .connected:
            animationPhase += 0.015
            pulseScale = 1.0 + sin(animationPhase * 2 * .pi) * 0.1
            
        case .connecting:
            rotationAngle += .degrees(4)
            
        case .refreshing:
            rotationAngle += .degrees(3)
            
        case .disconnected:
            // Static
            break
            
        case .error:
            animationPhase += 0.04
            pulseScale = 1.0 + sin(animationPhase * 4 * .pi) * 0.15
        }
    }
    
    private func startCompactAnimation() {
        animationPhase = 0
        rotationAngle = .zero
        pulseScale = 1.0
    }
}

// MARK: - Status Transition Animation

struct StatusTransitionAnimation: View {
    @ObservedObject var windowManager: WindowManager
    @State private var previousStatus: ConnectionStatus?
    @State private var showTransition = false
    @State private var transitionProgress: CGFloat = 0
    @State private var transitionScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Main animated indicator
            AnimatedStatusIndicator(windowManager: windowManager)
            
            // Transition overlay
            if showTransition {
                transitionOverlay
            }
        }
        .onChange(of: windowManager.connectionStatus) { oldStatus, newStatus in
            if let old = oldStatus, old != newStatus {
                triggerTransition(from: old, to: newStatus)
            }
        }
    }
    
    @ViewBuilder
    private var transitionOverlay: some View {
        Circle()
            .stroke(transitionColor.opacity(0.8), lineWidth: 2)
            .frame(width: 24, height: 24)
            .scaleEffect(transitionScale)
            .opacity(1.0 - transitionProgress)
            .animation(.easeOut(duration: 0.6), value: transitionScale)
            .animation(.easeOut(duration: 0.6), value: transitionProgress)
    }
    
    private var transitionColor: Color {
        switch windowManager.connectionStatus {
        case .connected: return .green
        case .connecting: return .blue
        case .refreshing: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    private func triggerTransition(from oldStatus: ConnectionStatus, to newStatus: ConnectionStatus) {
        showTransition = true
        transitionProgress = 0
        transitionScale = 1.0
        
        withAnimation(.easeOut(duration: 0.6)) {
            transitionProgress = 1.0
            transitionScale = 2.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showTransition = false
        }
    }
}

// MARK: - Previews

#Preview("Animated Status - All States") {
    VStack(spacing: 30) {
        Group {
            Text("Connected")
                .font(.caption)
            AnimatedStatusIndicator(windowManager: createMockWindowManager(.connected))
            
            Text("Connecting")
                .font(.caption)
            AnimatedStatusIndicator(windowManager: createMockWindowManager(.connecting))
            
            Text("Refreshing")
                .font(.caption)
            AnimatedStatusIndicator(windowManager: createMockWindowManager(.refreshing))
            
            Text("Disconnected")
                .font(.caption)
            AnimatedStatusIndicator(windowManager: createMockWindowManager(.disconnected))
            
            Text("Error")
                .font(.caption)
            AnimatedStatusIndicator(windowManager: createMockWindowManager(.error))
        }
    }
    .padding()
}

#Preview("Compact Animated Status") {
    HStack(spacing: 20) {
        CompactAnimatedStatusIndicator(windowManager: createMockWindowManager(.connected))
        CompactAnimatedStatusIndicator(windowManager: createMockWindowManager(.connecting))
        CompactAnimatedStatusIndicator(windowManager: createMockWindowManager(.refreshing))
        CompactAnimatedStatusIndicator(windowManager: createMockWindowManager(.disconnected))
        CompactAnimatedStatusIndicator(windowManager: createMockWindowManager(.error))
    }
    .padding()
}

#Preview("Status Transition Animation") {
    StatusTransitionAnimation(windowManager: createMockWindowManager(.connected))
        .padding()
}

private func createMockWindowManager(_ status: ConnectionStatus) -> WindowManager {
    let wm = WindowManager.shared
    wm.connectionStatus = status
    return wm
}
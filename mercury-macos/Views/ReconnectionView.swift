//
//  ReconnectionView.swift
//  Mercury
//
//  Created by Claude on 2025-06-15.
//

import SwiftUI
import Combine

// MARK: - Streamlined Reconnection Flow

struct ReconnectionView: View {
    @ObservedObject var windowManager: WindowManager
    @State private var isReconnecting = false
    @State private var reconnectionProgress: Double = 0.0
    @State private var currentStep: ReconnectionStep = .initial
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            reconnectionHeader
            
            // Progress indicator
            if isReconnecting {
                reconnectionProgressView
            }
            
            // Main content based on current step
            Group {
                switch currentStep {
                case .initial:
                    initialView
                case .connecting:
                    connectingView
                case .verifying:
                    verifyingView
                case .success:
                    successView
                case .error:
                    errorView
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            // Action buttons
            actionButtons
        }
        .padding(24)
        .frame(width: 380)
        .background(backgroundMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .onAppear {
            setupStateObservation()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    // MARK: - Header
    
    private var reconnectionHeader: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            // Title
            Text("Reconnect to X")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            
            // Subtitle
            Text("Your connection was lost. Let's get you back online.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Progress View
    
    private var reconnectionProgressView: some View {
        VStack(spacing: 12) {
            // Progress bar
            ProgressView(value: reconnectionProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(y: 2)
            
            // Step description
            Text(currentStep.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.blue)
                .animation(.easeInOut(duration: 0.2), value: currentStep)
        }
    }
    
    // MARK: - Step Views
    
    private var initialView: some View {
        VStack(spacing: 16) {
            // Connection status
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                
                Text("Disconnected from X")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Benefits of reconnecting
            VStack(alignment: .leading, spacing: 8) {
                reconnectionBenefit(icon: "paperplane.fill", text: "Resume posting tweets")
                reconnectionBenefit(icon: "arrow.clockwise", text: "Sync queued posts")
                reconnectionBenefit(icon: "person.fill", text: "Access your account")
            }
        }
    }
    
    private var connectingView: some View {
        VStack(spacing: 16) {
            // Animated connection indicator
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                
                Text("Connecting to X...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            // Helpful message
            Text("This may take a few seconds")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    private var verifyingView: some View {
        VStack(spacing: 16) {
            // Verification indicator
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
                
                Text("Verifying credentials...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.green)
            }
            
            // Security message
            Text("Ensuring secure connection")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    private var successView: some View {
        VStack(spacing: 16) {
            // Success indicator
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                
                Text("Successfully reconnected!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.green)
            }
            
            // Account info if available
            if let user = windowManager.authManager?.currentUser {
                Text("Connected as @\(user.username)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            // Error indicator
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.red)
                
                Text("Connection failed")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
            }
            
            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.05))
                    )
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Cancel/Close button
            if currentStep != .success {
                Button("Cancel") {
                    dismissReconnection()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            
            // Primary action button
            Button(primaryButtonText) {
                handlePrimaryAction()
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !isReconnecting))
            .disabled(isReconnecting && currentStep != .error)
        }
    }
    
    // MARK: - Helper Views
    
    private func reconnectionBenefit(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.blue)
                .frame(width: 16)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
    }
    
    private var backgroundMaterial: some ShapeStyle {
        #if os(macOS)
        return Material.hudWindow
        #else
        return Material.regular
        #endif
    }
    
    // MARK: - Computed Properties
    
    private var primaryButtonText: String {
        switch currentStep {
        case .initial:
            return "Reconnect"
        case .connecting, .verifying:
            return "Connecting..."
        case .success:
            return "Done"
        case .error:
            return "Try Again"
        }
    }
    
    // MARK: - Actions
    
    private func handlePrimaryAction() {
        switch currentStep {
        case .initial, .error:
            startReconnection()
        case .success:
            dismissReconnection()
        default:
            break
        }
    }
    
    private func startReconnection() {
        guard let authManager = windowManager.authManager else { return }
        
        isReconnecting = true
        currentStep = .connecting
        reconnectionProgress = 0.1
        errorMessage = nil
        
        Task {
            let result = await authManager.authenticate()
            
            await MainActor.run {
                switch result {
                case .success:
                    currentStep = .success
                    reconnectionProgress = 1.0
                    
                    // Auto-dismiss after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismissReconnection()
                    }
                    
                case .failure(let error):
                    currentStep = .error
                    errorMessage = error.localizedDescription
                    isReconnecting = false
                    reconnectionProgress = 0.0
                }
            }
        }
    }
    
    private func dismissReconnection() {
        // This would be handled by the parent view
        // For now, we'll reset to initial state
        currentStep = .initial
        isReconnecting = false
        reconnectionProgress = 0.0
        errorMessage = nil
    }
    
    // MARK: - State Observation
    
    private func setupStateObservation() {
        windowManager.authManager?.authenticationStatePublisher
            .sink { [weak windowManager] state in
                updateProgressForState(state)
            }
            .store(in: &cancellables)
    }
    
    private func updateProgressForState(_ state: AuthenticationState) {
        guard isReconnecting else { return }
        
        switch state {
        case .authenticating:
            currentStep = .connecting
            reconnectionProgress = 0.3
        case .authenticated:
            currentStep = .verifying
            reconnectionProgress = 0.8
        case .error:
            currentStep = .error
            isReconnecting = false
            reconnectionProgress = 0.0
        default:
            break
        }
    }
}

// MARK: - Reconnection Steps

enum ReconnectionStep: CaseIterable {
    case initial
    case connecting
    case verifying
    case success
    case error
    
    var description: String {
        switch self {
        case .initial:
            return "Ready to reconnect"
        case .connecting:
            return "Connecting to X..."
        case .verifying:
            return "Verifying credentials..."
        case .success:
            return "Connection successful!"
        case .error:
            return "Connection failed"
        }
    }
}

// MARK: - Custom Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    let isEnabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? Color.blue : Color.blue.opacity(0.6))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Compact Reconnection Button

struct CompactReconnectButton: View {
    @ObservedObject var windowManager: WindowManager
    @State private var showingReconnection = false
    
    var body: some View {
        if shouldShowReconnectButton {
            Button("Reconnect") {
                showingReconnection = true
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.blue)
            .cornerRadius(6)
            .popover(isPresented: $showingReconnection) {
                ReconnectionView(windowManager: windowManager)
                    .frame(width: 380, height: 300)
            }
        }
    }
    
    private var shouldShowReconnectButton: Bool {
        switch windowManager.connectionStatus {
        case .disconnected, .error:
            return true
        default:
            return false
        }
    }
}

// MARK: - Inline Reconnection Prompt

struct InlineReconnectionPrompt: View {
    @ObservedObject var windowManager: WindowManager
    @State private var showingReconnection = false
    
    var body: some View {
        if shouldShowPrompt {
            HStack(spacing: 12) {
                // Warning icon
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                
                // Message
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection lost")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                    
                    Text("Tap to reconnect and resume posting")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.8))
                }
                
                Spacer()
                
                // Reconnect button
                Button("Reconnect") {
                    showingReconnection = true
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .cornerRadius(6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .sheet(isPresented: $showingReconnection) {
                ReconnectionView(windowManager: windowManager)
                    .frame(width: 380, height: 350)
            }
        }
    }
    
    private var shouldShowPrompt: Bool {
        switch windowManager.connectionStatus {
        case .disconnected, .error:
            return true
        default:
            return false
        }
    }
}

// MARK: - Previews

#Preview("Reconnection View - Initial") {
    ReconnectionView(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }())
    .frame(width: 400, height: 350)
}

#Preview("Compact Reconnect Button") {
    CompactReconnectButton(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }())
    .padding()
}

#Preview("Inline Reconnection Prompt") {
    InlineReconnectionPrompt(windowManager: {
        let wm = WindowManager.shared
        wm.connectionStatus = .disconnected
        return wm
    }())
    .padding()
}
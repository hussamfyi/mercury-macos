import SwiftUI
import AppKit

struct PreferencesView: View {
    @StateObject private var preferences = PreferencesManager.shared
    @StateObject private var hotkeyService = HotkeyService.shared
    @State private var isRecordingHotkey = false
    @State private var tempKeyCode: UInt16?
    @State private var tempModifiers: NSEvent.ModifierFlags?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.title)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("Mercury Preferences")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Configure global hotkey and app settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Hotkey Configuration Section
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Global Hotkey")
                        .font(.headline)
                    
                    Spacer()
                    
                    if hotkeyService.isHotKeyRegistered {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Label("Inactive", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                Text("Press the hotkey combination to activate Mercury from anywhere on your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Current Hotkey Display
                HStack {
                    Text("Current Hotkey:")
                        .font(.subheadline)
                    
                    Button(action: {
                        startRecordingHotkey()
                    }) {
                        HStack {
                            Text(isRecordingHotkey ? "Press keys..." : preferences.hotkeyDescription)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isRecordingHotkey ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isRecordingHotkey ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            
                            if !isRecordingHotkey {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                
                // Preset Hotkeys
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(PreferencesManager.presetHotkeys, id: \.description) { preset in
                            Button(preset.description) {
                                setHotkey(keyCode: preset.keyCode, modifiers: preset.modifiers)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(preferences.hotkeyKeyCode == preset.keyCode && 
                                     preferences.hotkeyModifiers == preset.modifiers)
                        }
                    }
                }
                
                // Error Display
                if let error = hotkeyService.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            if let suggestion = error.recoverySuggestion {
                                Text(suggestion)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Fix") {
                            handleError(error)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Reset to Default") {
                    preferences.resetToDefaults()
                    _ = hotkeyService.registerHotKey(keyCode: preferences.hotkeyKeyCode, modifiers: preferences.hotkeyModifiers)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Test Hotkey") {
                    testHotkey()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .onAppear {
            setupHotkeyRecording()
        }
        .onChange(of: preferences.hotkeyKeyCode) { _ in
            updateHotkey()
        }
        .onChange(of: preferences.hotkeyModifiers) { _ in
            updateHotkey()
        }
    }
    
    // MARK: - Hotkey Recording
    private func startRecordingHotkey() {
        isRecordingHotkey = true
        tempKeyCode = nil
        tempModifiers = nil
    }
    
    private func setupHotkeyRecording() {
        // Set up global key monitoring for recording new hotkeys
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if isRecordingHotkey {
                handleKeyEvent(event)
                return nil // Consume the event
            }
            return event
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            tempKeyCode = event.keyCode
            tempModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Complete recording if we have both key and modifiers
            if let keyCode = tempKeyCode, let modifiers = tempModifiers, !modifiers.isEmpty {
                completeHotkeyRecording(keyCode: keyCode, modifiers: modifiers)
            }
        } else if event.type == .flagsChanged {
            tempModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        }
    }
    
    private func completeHotkeyRecording(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        isRecordingHotkey = false
        setHotkey(keyCode: keyCode, modifiers: modifiers)
    }
    
    private func setHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        preferences.setHotkey(keyCode: keyCode, modifiers: modifiers)
    }
    
    private func updateHotkey() {
        _ = hotkeyService.registerHotKey(keyCode: preferences.hotkeyKeyCode, modifiers: preferences.hotkeyModifiers)
    }
    
    private func testHotkey() {
        let alert = NSAlert()
        alert.messageText = "Hotkey Test"
        alert.informativeText = "Press \(preferences.hotkeyDescription) to test if the hotkey is working properly."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func handleError(_ error: HotkeyError) {
        switch error {
        case .accessibilityPermissionDenied:
            hotkeyService.requestAccessibilityPermissions()
        case .hotkeyConflict:
            // Show conflict resolution options
            showConflictResolution()
        case .registrationFailed:
            _ = hotkeyService.registerHotKey()
        }
    }
    
    private func showConflictResolution() {
        let alert = NSAlert()
        alert.messageText = "Hotkey Conflict"
        alert.informativeText = "The selected hotkey conflicts with another application. Would you like to choose a different hotkey?"
        alert.addButton(withTitle: "Choose Different")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Reset to a safe default
            preferences.setHotkey(keyCode: 49, modifiers: [.command, .shift])
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
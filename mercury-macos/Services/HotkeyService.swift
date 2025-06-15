import Foundation
import AppKit
import Combine

enum HotkeyError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case hotkeyConflict(conflictingApp: String?)
    case registrationFailed
    
    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Mercury needs accessibility permissions to register global hotkeys."
        case .hotkeyConflict(let app):
            if let app = app {
                return "The hotkey Cmd+Space conflicts with \(app). Please choose a different hotkey or disable the conflicting shortcut."
            } else {
                return "The hotkey Cmd+Space conflicts with another application. Please choose a different hotkey."
            }
        case .registrationFailed:
            return "Failed to register the global hotkey. Please try again."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Go to System Preferences > Security & Privacy > Privacy > Accessibility and enable Mercury."
        case .hotkeyConflict:
            return "Try using a different key combination like Cmd+Shift+Space or Cmd+Option+Space."
        case .registrationFailed:
            return "Restart Mercury and try again. If the problem persists, check System Preferences > Keyboard > Shortcuts for conflicts."
        }
    }
}

class HotkeyService: ObservableObject {
    static let shared = HotkeyService()
    
    @Published var isHotKeyRegistered = false
    @Published var hotKeyConflict = false
    @Published var lastError: HotkeyError?
    
    private let hotkeyTriggeredSubject = PassthroughSubject<Void, Never>()
    var hotkeyTriggered: AnyPublisher<Void, Never> {
        hotkeyTriggeredSubject.eraseToAnyPublisher()
    }
    
    private var globalMonitor: Any?
    private let defaultModifiers: NSEvent.ModifierFlags = [.command]
    private let defaultKeyCode: UInt16 = 49 // Space key
    
    private init() {
        // Subscribe to preference changes
        PreferencesManager.shared.hotkeyChangedPublisher
            .sink { [weak self] in
                let prefs = PreferencesManager.shared
                _ = self?.registerHotKey(keyCode: prefs.hotkeyKeyCode, modifiers: prefs.hotkeyModifiers)
            }
            .store(in: &cancellables)
        
        // Register initial hotkey from preferences
        let prefs = PreferencesManager.shared
        registerHotKey(keyCode: prefs.hotkeyKeyCode, modifiers: prefs.hotkeyModifiers)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    func registerHotKey(keyCode: UInt16 = 49, modifiers: NSEvent.ModifierFlags = [.command]) -> Bool {
        // Unregister existing hotkey if any
        unregisterHotKey()
        
        // Clear previous errors
        lastError = nil
        
        // Check if accessibility permissions are granted
        guard checkAccessibilityPermissions() else {
            let error = HotkeyError.accessibilityPermissionDenied
            lastError = error
            hotKeyConflict = true
            showNotification(for: error)
            return false
        }
        
        // Check for conflicts with system shortcuts
        let conflictingApp = detectConflictingApplication(keyCode: keyCode, modifiers: modifiers)
        if let conflictingApp = conflictingApp {
            let error = HotkeyError.hotkeyConflict(conflictingApp: conflictingApp)
            lastError = error
            hotKeyConflict = true
            showNotification(for: error)
            return false
        }
        
        // Register global key down monitor
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            
            // Check if the pressed key matches our hotkey
            if event.keyCode == keyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers {
                DispatchQueue.main.async {
                    self.hotkeyTriggeredSubject.send()
                }
            }
        }
        
        if globalMonitor != nil {
            isHotKeyRegistered = true
            hotKeyConflict = false
            lastError = nil
            return true
        } else {
            let error = HotkeyError.registrationFailed
            lastError = error
            hotKeyConflict = true
            showNotification(for: error)
            return false
        }
    }
    
    func unregisterHotKey() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        isHotKeyRegistered = false
        hotKeyConflict = false
    }
    
    func checkForConflicts() -> Bool {
        // Test registration to detect conflicts
        let currentStatus = isHotKeyRegistered
        let testResult = registerHotKey()
        
        // Restore original state if we were just testing
        if !currentStatus && testResult {
            unregisterHotKey()
        }
        
        return !testResult
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        return accessibilityEnabled
    }
    
    func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    private func detectConflictingApplication(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        // Check common system shortcuts that might conflict
        if keyCode == 49 && modifiers == [.command] { // Cmd+Space
            // Check if Spotlight is enabled (most common conflict)
            let spotlightEnabled = isSpotlightEnabled()
            if spotlightEnabled {
                return "Spotlight"
            }
            
            // Check for other common launcher apps
            let runningApps = NSWorkspace.shared.runningApplications
            let commonLaunchers = ["Raycast", "Alfred", "LaunchBar", "Quicksilver"]
            
            for app in runningApps {
                if let appName = app.localizedName,
                   commonLaunchers.contains(where: { $0.lowercased() == appName.lowercased() }) {
                    return appName
                }
            }
        }
        
        return nil
    }
    
    private func isSpotlightEnabled() -> Bool {
        // Check if Spotlight search shortcut is enabled
        // This is a simplified check - in a real implementation, you might want to
        // read from system preferences or use more sophisticated detection
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Look for Spotlight shortcut (key 64 is typically Cmd+Space for Spotlight)
            return output.contains("64") && output.contains("enabled = 1")
        } catch {
            // If we can't determine, assume it's enabled to be safe
            return true
        }
    }
    
    private func showNotification(for error: HotkeyError) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Hotkey Registration Failed"
            alert.informativeText = error.localizedDescription
            
            if let suggestion = error.recoverySuggestion {
                alert.informativeText += "\n\n" + suggestion
            }
            
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            
            // Add action buttons based on error type
            switch error {
            case .accessibilityPermissionDenied:
                alert.addButton(withTitle: "Open System Preferences")
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    self.openAccessibilityPreferences()
                }
                
            case .hotkeyConflict:
                alert.addButton(withTitle: "Try Different Hotkey")
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    // This could trigger a hotkey selection UI
                    self.suggestAlternativeHotkeys()
                }
                
            case .registrationFailed:
                alert.addButton(withTitle: "Retry")
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    _ = self.registerHotKey()
                }
            }
        }
    }
    
    private func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    private func suggestAlternativeHotkeys() {
        // Suggest alternative hotkey combinations
        let alternatives: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (49, [.command, .shift], "Cmd+Shift+Space"),
            (49, [.command, .option], "Cmd+Option+Space"),
            (36, [.command, .shift], "Cmd+Shift+Return"),
            (122, [.command], "Cmd+F1")
        ]
        
        for (keyCode, modifiers, description) in alternatives {
            if detectConflictingApplication(keyCode: keyCode, modifiers: modifiers) == nil {
                let alert = NSAlert()
                alert.messageText = "Alternative Hotkey Suggestion"
                alert.informativeText = "Would you like to use \(description) instead?"
                alert.addButton(withTitle: "Use This Hotkey")
                alert.addButton(withTitle: "Choose Different")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    _ = registerHotKey(keyCode: keyCode, modifiers: modifiers)
                    break
                }
            }
        }
    }
    
    deinit {
        unregisterHotKey()
    }
}

// MARK: - Key Code Constants
extension HotkeyService {
    static let virtualKeyCodes: [String: UInt16] = [
        "Space": 49,
        "Return": 36,
        "Tab": 48,
        "Escape": 53,
        "Delete": 51,
        "F1": 122,
        "F2": 120,
        "F3": 99,
        "F4": 118,
        "F5": 96,
        "F6": 97,
        "F7": 98,
        "F8": 100,
        "F9": 101,
        "F10": 109,
        "F11": 103,
        "F12": 111
    ]
}
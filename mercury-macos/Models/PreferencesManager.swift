import Foundation
import AppKit
import Combine

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    @Published var hotkeyKeyCode: UInt16 {
        didSet {
            UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode")
            hotkeyChanged.send()
        }
    }
    
    @Published var hotkeyModifiers: NSEvent.ModifierFlags {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers.rawValue, forKey: "hotkeyModifiers")
            hotkeyChanged.send()
        }
    }
    
    @Published var isFirstLaunch: Bool {
        didSet {
            UserDefaults.standard.set(isFirstLaunch, forKey: "isFirstLaunch")
        }
    }
    
    private let hotkeyChanged = PassthroughSubject<Void, Never>()
    var hotkeyChangedPublisher: AnyPublisher<Void, Never> {
        hotkeyChanged.eraseToAnyPublisher()
    }
    
    private init() {
        // Load saved preferences or use defaults - initialize directly without triggering didSet
        let savedKeyCode = UInt16(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        self.hotkeyKeyCode = savedKeyCode == 0 ? 49 : savedKeyCode // Default to Space key
        
        let modifiersRaw = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        if modifiersRaw == 0 {
            self.hotkeyModifiers = [.command] // Default to Command
        } else {
            self.hotkeyModifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw))
        }
        
        self.isFirstLaunch = UserDefaults.standard.object(forKey: "isFirstLaunch") == nil ? true : UserDefaults.standard.bool(forKey: "isFirstLaunch")
    }
    
    // MARK: - Hotkey Description
    var hotkeyDescription: String {
        var components: [String] = []
        
        if hotkeyModifiers.contains(.command) {
            components.append("⌘")
        }
        if hotkeyModifiers.contains(.option) {
            components.append("⌥")
        }
        if hotkeyModifiers.contains(.control) {
            components.append("⌃")
        }
        if hotkeyModifiers.contains(.shift) {
            components.append("⇧")
        }
        
        // Get key name from key code
        let keyName = keyNameForCode(hotkeyKeyCode)
        components.append(keyName)
        
        return components.joined(separator: "")
    }
    
    private func keyNameForCode(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Delete"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 0...25: return String(Character(UnicodeScalar(65 + Int(keyCode))!))
        default: return "Key \(keyCode)"
        }
    }
    
    // MARK: - Preset Hotkeys
    static let presetHotkeys: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, description: String)] = [
        (49, [.command], "⌘Space"),
        (49, [.command, .shift], "⌘⇧Space"),
        (49, [.command, .option], "⌘⌥Space"),
        (36, [.command, .shift], "⌘⇧Return"),
        (122, [.command], "⌘F1"),
        (120, [.command], "⌘F2"),
        (99, [.command], "⌘F3")
    ]
    
    func setHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.hotkeyKeyCode = keyCode
        self.hotkeyModifiers = modifiers
    }
    
    func resetToDefaults() {
        setHotkey(keyCode: 49, modifiers: [.command])
    }
}


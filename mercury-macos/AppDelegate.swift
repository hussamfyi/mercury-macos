// AppDelegate handles macOS-specific window configuration that SwiftUI can't handle directly
// This class is connected to our app through @NSApplicationDelegateAdaptor in mercuryApp.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // Access to the app lifecycle coordinator for integration
    private var appLifecycleCoordinator: AppLifecycleCoordinator {
        return AppLifecycleCoordinator.shared
    }
    // This function runs automatically when the app finishes launching
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenus()
        setupWindows()
        setupHotkeyService()
    }
    
    private func setupWindows() {
        // NSApplication.shared represents our running app instance (like a global app object)
        // .windows gives us an array of all windows currently open in our app
        // .first gets the first window in that array (our main window)
        // if let safely unwraps the optional window, since there might not be any windows yet
        //
        // Example: When you launch the app, macOS creates a window that you see on screen
        // This code gets a reference to that window so we can modify it
        // If you close the window and reopen it, this code will grab the new window
        // Think of it like getting a handle to the physical window you see on your screen
        if let window = NSApplication.shared.windows.first {
            // Check if window was previously in fullscreen mode
            if window.styleMask.contains(.fullScreen) {
                // Force exit fullscreen mode by toggling it
                window.toggleFullScreen(nil)
            }
            
            // Position the window in the center of the screen
            // This uses AppKit's built-in centering calculation
            window.center()
        }
    }
    
    private func setupMenus() {
        // Create the main menu bar
        let mainMenu = NSMenu(title: "Main Menu")
        
        // App menu (Mercury)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu(title: "Mercury")
        appMenuItem.submenu = appMenu
        
        // About Mercury
        appMenu.addItem(NSMenuItem(title: "About Mercury", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        
        // Preferences
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Services
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApplication.shared.servicesMenu = servicesMenu
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Hide/Quit
        appMenu.addItem(NSMenuItem(title: "Hide Mercury", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Mercury", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        
        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        NSApplication.shared.windowsMenu = windowMenu
        
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        
        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @objc private func showPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func setupHotkeyService() {
        // Initialize the hotkey service to start listening for global hotkeys
        _ = HotkeyService.shared
    }
    
    // MARK: - App Lifecycle Delegation to Coordinator
    
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await appLifecycleCoordinator.handleForegroundRestore()
        }
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        // Handle app becoming inactive (but not necessarily backgrounded)
    }
    
    func applicationDidHide(_ notification: Notification) {
        Task { @MainActor in
            await appLifecycleCoordinator.prepareForBackground()
        }
    }
    
    func applicationDidUnhide(_ notification: Notification) {
        Task { @MainActor in
            await appLifecycleCoordinator.handleForegroundRestore()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            await appLifecycleCoordinator.prepareForTermination()
        }
    }
}

// AppDelegate is used only for macOS-specific window handling that SwiftUI doesn't support natively
// Window settings like size and toolbar are configured in mercuryApp.swift, declarative style
// through modifiers in the WindowGroup scene, which is the preferred approach because:
// 1. It's more SwiftUI-native and declarative
// 2. Settings automatically persist when windows are recreated
// 3. Handles both initial window creation and subsequent changes consistently
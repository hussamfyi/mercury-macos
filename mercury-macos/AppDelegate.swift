// AppDelegate handles macOS-specific window configuration that SwiftUI can't handle directly
// This class is connected to our app through @NSApplicationDelegateAdaptor in mercuryApp.swift
class AppDelegate: NSObject, NSApplicationDelegate {
    // This function runs automatically when the app finishes launching
    func applicationDidFinishLaunching(_ notification: Notification) {
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
}

// AppDelegate is used only for macOS-specific window handling that SwiftUI doesn't support natively
// Window settings like size and toolbar are configured in mercuryApp.swift, declarative style
// through modifiers in the WindowGroup scene, which is the preferred approach because:
// 1. It's more SwiftUI-native and declarative
// 2. Settings automatically persist when windows are recreated
// 3. Handles both initial window creation and subsequent changes consistently
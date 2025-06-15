import Foundation
import AppKit
import SwiftUI
import Combine

// MARK: - Custom Window for Drag Detection
class MercuryNSWindow: NSWindow {
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onEscapePressed: (() -> Void)?
    var onPostRequested: (() -> Void)?
    
    private var isDragging = false
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        // Start drag detection
        if !isDragging {
            isDragging = true
            onDragStart?()
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        
        // End drag detection
        if isDragging {
            isDragging = false
            onDragEnd?()
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        
        // Ensure drag state is active
        if !isDragging {
            isDragging = true
            onDragStart?()
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // Handle keyboard shortcuts
        if event.keyCode == 53 { // Escape key
            onEscapePressed?()
        } else if event.keyCode == 36 && event.modifierFlags.contains(.command) { // Cmd+Enter
            // Key code 36 is Return/Enter
            onPostRequested?()
        } else {
            super.keyDown(with: event)
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - Window Manager
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    @Published var isWindowVisible = false
    @Published var windowPosition: CGPoint = .zero
    @Published var windowSize: CGSize = CGSize(width: 400, height: 160)
    @Published var preferredScreen: NSScreen?
    @Published var isDragging = false
    @Published var isWindowFocused = false
    @Published var currentText: String = ""
    @Published var contentHeight: CGFloat = 160
    @Published var isTextFieldFocused = false
    @Published var postingState: PostingState = .idle
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isAuthenticationInProgress: Bool = false
    
    // AuthManager integration for X API posting
    weak var authManager: AuthManager?
    
    // PostQueueManager integration for offline/failed authentication scenarios
    weak var postQueueManager: PostQueueManager?
    
    // Authentication persistence service for status recovery
    @Published var persistenceService: AuthenticationPersistenceService?
    
    private var mercuryWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var screenConfigurationObserver: Any?
    private var applicationObserver: Any?
    private var lastToggleTime: Date = Date.distantPast
    private var previousActiveApp: NSRunningApplication?
    
    // Session persistence keys
    private let positionXKey = "mercuryWindowX"
    private let positionYKey = "mercuryWindowY"
    private let screenIdentifierKey = "mercuryPreferredScreenID"
    private let windowSizeWidthKey = "mercuryWindowWidth"
    private let windowSizeHeightKey = "mercuryWindowHeight"
    private let isFirstLaunchKey = "mercuryIsFirstLaunch"
    private let sessionTextKey = "mercurySessionText"
    
    private init() {
        setupHotkeyListener()
        setupScreenObserver()
        setupApplicationObserver()
        loadPersistedState()
        setupWindowLevelManagement()
        setupTextPersistence()
    }
    
    /// Configure the WindowManager with AuthManager for posting functionality
    /// - Parameter authManager: The initialized AuthManager instance
    func configure(with authManager: AuthManager, postQueueManager: PostQueueManager? = nil) {
        self.authManager = authManager
        self.postQueueManager = postQueueManager
        
        // Initialize persistence service (task 4.10)
        setupPersistenceService(authManager: authManager)
        
        updateConnectionStatus()
        
        // Observe authentication state changes
        authManager.authenticationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.handleAuthenticationStateChange(newState)
            }
            .store(in: &cancellables)
        
        // Configure queue manager if provided (task 3.10)
        if let queueManager = postQueueManager {
            configureQueueManager(queueManager)
        }
    }
    
    /// Configures the PostQueueManager integration for offline/failed authentication scenarios
    /// Implements task 3.10 requirement for queue integration
    private func configureQueueManager(_ queueManager: PostQueueManager) {
        #if DEBUG
        print("📨 Configuring PostQueueManager integration for offline/failed auth scenarios")
        #endif
        
        // Set up post sender callback for the queue manager
        queueManager.postSender = { [weak self] text in
            guard let self = self, let authManager = self.authManager else {
                return false
            }
            
            // Use the same posting logic but without queue fallback to avoid infinite loops
            let result = await authManager.postTweet(text)
            
            switch result {
            case .success:
                return true
            case .failure:
                return false
            }
        }
        
        // Observe queue count for potential UI updates
        queueManager.queueCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                #if DEBUG
                if count > 0 {
                    print("📬 Queue now has \(count) posts pending")
                }
                #endif
            }
            .store(in: &cancellables)
    }
    
    private func updateConnectionStatus() {
        guard let authManager = authManager else {
            connectionStatus = .disconnected
            isAuthenticationInProgress = false
            return
        }
        
        switch authManager.authenticationState {
        case .disconnected:
            connectionStatus = .disconnected
            isAuthenticationInProgress = false
        case .authenticating:
            connectionStatus = .connecting(progress: AuthenticationProgress(phase: .starting))
            isAuthenticationInProgress = true
        case .authenticated:
            if let user = authManager.getCurrentUser() {
                connectionStatus = .connected(user: ConnectedUserInfo(from: user))
            } else {
                connectionStatus = .connected(user: ConnectedUserInfo(username: "Unknown"))
            }
            isAuthenticationInProgress = false
        case .refreshing:
            connectionStatus = .refreshing(reason: .automatic)
            isAuthenticationInProgress = true
        case .error(let error):
            connectionStatus = .error(ConnectionError(
                type: .authenticationFailed,
                underlyingError: error.localizedDescription,
                isRecoverable: true
            ))
            isAuthenticationInProgress = false
        }
    }
    
    /// Handles authentication state changes with posting flow integration
    /// Implements task 3.11 requirement for authentication state change handling in posting flow
    private func handleAuthenticationStateChange(_ newState: AuthenticationState) {
        // Update connection status first
        updateConnectionStatus()
        
        // Handle posting flow interactions with authentication state changes
        handlePostingFlowAuthenticationChanges(newState)
    }
    
    /// Handles authentication state changes that affect the posting flow
    /// Implements task 3.11 requirement for posting flow authentication integration
    private func handlePostingFlowAuthenticationChanges(_ newState: AuthenticationState) {
        switch newState {
        case .disconnected:
            handleAuthenticationDisconnected()
            
        case .authenticating:
            handleAuthenticationInProgress()
            
        case .authenticated:
            handleAuthenticationSuccess()
            
        case .refreshing:
            handleAuthenticationRefreshing()
            
        case .error(let error):
            handleAuthenticationError(error)
        }
    }
    
    /// Handles disconnection during posting flow
    private func handleAuthenticationDisconnected() {
        // If we're currently posting, this is a critical failure
        if postingState.isLoading {
            #if DEBUG
            print("⚠️ Authentication disconnected during posting - canceling post")
            #endif
            
            // Cancel posting with authentication error
            let authError = PostingErrorState(
                error: .notAuthenticated,
                isRecoverable: true,
                preservedText: currentText,
                canRetry: true,
                authenticationState: .disconnected,
                suggestedActions: [.reconnect, .dismiss]
            )
            setPostingState(.error(authError))
        }
    }
    
    /// Handles authentication in progress during posting flow
    private func handleAuthenticationInProgress() {
        // If user tries to post while authenticating, provide feedback
        if postingState.isLoading {
            #if DEBUG
            print("🔄 Authentication in progress during posting - updating progress phase")
            #endif
            
            // Update posting progress to show authentication phase
            setPostingState(.loading(PostingProgress(
                phase: .authenticating,
                authenticationRequired: true
            )))
        }
    }
    
    /// Handles successful authentication during posting flow
    private func handleAuthenticationSuccess() {
        let wasAuthenticating = isAuthenticationInProgress
        
        // If authentication just completed and we have queued posts, trigger processing
        if wasAuthenticating, let queueManager = postQueueManager {
            #if DEBUG
            print("✅ Authentication completed - triggering queue processing")
            #endif
            
            Task {
                let processedCount = await queueManager.processQueueOnNetworkRestored()
                if processedCount > 0 {
                    #if DEBUG
                    print("📤 Processed \(processedCount) queued posts after authentication")
                    #endif
                }
            }
        }
        
        // Handle posting flow state after authentication success
        handlePostingFlowAfterAuthSuccess()
    }
    
    /// Handles posting flow state management after successful authentication
    /// Implements task 3.11 requirement for resuming interrupted posting flows
    private func handlePostingFlowAfterAuthSuccess() {
        // If we were in an error state due to authentication, clear it
        if case .error(let errorState) = postingState,
           case .notAuthenticated = errorState.error {
            #if DEBUG
            print("🔄 Authentication restored - clearing authentication error state")
            #endif
            setPostingState(.idle)
        }
        
        // If we were in loading state due to authentication (user tried to post during auth), 
        // and we have text, attempt to resume posting
        if case .loading(let progress) = postingState,
           progress.authenticationRequired,
           !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let authManager = authManager {
            
            #if DEBUG
            print("🔄 Resuming interrupted posting after authentication success")
            #endif
            
            // Resume posting with the current text
            Task {
                await resumeInterruptedPosting(authManager: authManager)
            }
        }
    }
    
    /// Resumes posting that was interrupted by authentication
    private func resumeInterruptedPosting(authManager: AuthManager) async {
        let textToPost = currentText
        
        #if DEBUG
        print("📝 Resuming posting after authentication: \(textToPost)")
        #endif
        
        // Update to posting phase
        await MainActor.run {
            setPostingState(.loading(PostingProgress(phase: .posting)))
        }
        
        // Execute posting with timeout handling
        let postingTimeout = getPostingTimeout()
        let result = await performPostingWithTimeout(authManager: authManager, text: textToPost, timeout: postingTimeout)
        
        await MainActor.run {
            switch result {
            case .success(let success):
                #if DEBUG
                print("✅ Resumed posting successful: \(success.tweetId)")
                #endif
                
                // Show success state
                setPostingState(.success(success))
                
                // Clear text after successful post
                clearText()
                
                // Auto-hide after success
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.autoHideAfterSuccess()
                }
                
            case .failure(let error):
                #if DEBUG
                print("❌ Resumed posting failed: \(error.localizedDescription)")
                #endif
                
                // Handle failure with queue integration
                await handlePostingFailureWithQueue(error: error, textToPost: textToPost, authManager: authManager)
            }
        }
    }
    
    /// Handles authentication refresh during posting flow
    private func handleAuthenticationRefreshing() {
        // Authentication refresh should not interrupt normal posting
        // but we track it for state awareness
        
        if postingState.isLoading {
            #if DEBUG
            print("🔄 Token refresh during posting - continuing with refresh awareness")
            #endif
        }
    }
    
    /// Handles authentication errors during posting flow
    private func handleAuthenticationError(_ error: AuthenticationError) {
        // If we're currently posting, this affects the posting flow
        if postingState.isLoading {
            #if DEBUG
            print("❌ Authentication error during posting: \(error.localizedDescription)")
            #endif
            
            // Cancel posting with authentication error
            let authError = PostingErrorState(
                error: .notAuthenticated,
                isRecoverable: true,
                preservedText: currentText,
                canRetry: true,
                authenticationState: .error(error),
                suggestedActions: [.reconnect, .dismiss]
            )
            setPostingState(.error(authError))
        }
    }
    
    /// Sets up the authentication persistence service for status recovery across app sessions
    /// Implements task 4.10 requirement for authentication status persistence and recovery
    private func setupPersistenceService(authManager: AuthManager) {
        let service = AuthenticationPersistenceService.shared
        service.configure(windowManager: self, authManager: authManager)
        self.persistenceService = service
        
        #if DEBUG
        print("📱 Authentication persistence service configured for status recovery")
        #endif
    }
    
    /// Checks if posting can proceed with current authentication state
    /// Implements task 3.11 requirement for authentication state awareness in posting
    private func canPostWithCurrentAuthState(_ authManager: AuthManager) -> Bool {
        let authState = authManager.authenticationState
        
        switch authState {
        case .authenticated:
            // Can post when fully authenticated
            return true
            
        case .refreshing:
            // Can attempt to post during token refresh
            return true
            
        case .disconnected, .error:
            // Cannot post when disconnected or in error state
            return false
            
        case .authenticating:
            // Cannot post while authentication is in progress
            return false
        }
    }
    
    /// Handles post requests that are blocked by authentication state
    /// Implements task 3.11 requirement for authentication-aware posting flow
    private func handlePostRequestBlockedByAuth(_ authManager: AuthManager) {
        let authState = authManager.authenticationState
        
        #if DEBUG
        print("🚫 Post request blocked due to authentication state: \(authState)")
        #endif
        
        switch authState {
        case .disconnected:
            // Show error state for disconnected
            let authError = PostingErrorState(
                error: .notAuthenticated,
                isRecoverable: true,
                preservedText: currentText,
                canRetry: false, // Don't allow retry until connected
                authenticationState: .disconnected,
                suggestedActions: [.reconnect, .dismiss]
            )
            setPostingState(.error(authError))
            NSSound.beep()
            
        case .authenticating:
            // Provide feedback that authentication is in progress
            setPostingState(.loading(PostingProgress(
                phase: .authenticating,
                authenticationRequired: true
            )))
            
            #if DEBUG
            print("⏳ Post will proceed when authentication completes")
            #endif
            
        case .error(let error):
            // Show error state for authentication errors
            let authError = PostingErrorState(
                error: .notAuthenticated,
                isRecoverable: true,
                preservedText: currentText,
                canRetry: false,
                authenticationState: .error(error),
                suggestedActions: [.reconnect, .dismiss]
            )
            setPostingState(.error(authError))
            NSSound.beep()
            
        case .authenticated, .refreshing:
            // This shouldn't happen if canPostWithCurrentAuthState works correctly
            #if DEBUG
            print("⚠️ Unexpected auth state block: \(authState)")
            #endif
        }
    }
    
    private func setupHotkeyListener() {
        HotkeyService.shared.hotkeyTriggered
            .sink { [weak self] in
                self?.handleHotkeyToggle()
            }
            .store(in: &cancellables)
    }
    
    private func handleHotkeyToggle() {
        let now = Date()
        let timeSinceLastToggle = now.timeIntervalSince(lastToggleTime)
        
        // Debounce rapid hotkey presses (prevent accidental double-triggering)
        guard timeSinceLastToggle > 0.2 else {
            #if DEBUG
            print("Hotkey debounced - too rapid")
            #endif
            return
        }
        
        lastToggleTime = now
        
        // Special handling for when app is not active
        if !NSApp.isActive && !isWindowVisible {
            // If app is in background and window is hidden, always show
            showWindow()
        } else {
            // Normal toggle behavior
            toggleWindow()
        }
        
        #if DEBUG
        print("Hotkey triggered - toggling to: \(!isWindowVisible)")
        #endif
    }
    
    private func setupScreenObserver() {
        // Observe screen configuration changes (resolution, display changes)
        screenConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenConfigurationChange()
        }
    }
    
    private func setupApplicationObserver() {
        // Observe application activation/deactivation
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationBecameActive()
        }
        
        // Observe when app will resign active
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationWillResignActive()
        }
    }
    
    private func setupWindowLevelManagement() {
        // Set up proper window level management for different contexts
        // This will be called after window creation
    }
    
    private func setupTextPersistence() {
        // Automatically persist text changes during session
        $currentText
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                UserDefaults.standard.set(text, forKey: self?.sessionTextKey ?? "mercurySessionText")
            }
            .store(in: &cancellables)
    }
    
    private func handleApplicationBecameActive() {
        // Ensure window maintains proper level when app becomes active
        if let window = mercuryWindow, isWindowVisible {
            window.level = .floating
            window.orderFrontRegardless()
        }
    }
    
    private func handleApplicationWillResignActive() {
        // Store the currently active app before we lose focus
        previousActiveApp = NSWorkspace.shared.frontmostApplication
        
        // Lower window level to avoid interfering with other apps
        if let window = mercuryWindow {
            window.level = .normal
        }
    }
    
    private func loadPersistedState() {
        // Load window position
        let x = UserDefaults.standard.double(forKey: positionXKey)
        let y = UserDefaults.standard.double(forKey: positionYKey)
        
        if x != 0 || y != 0 {
            windowPosition = CGPoint(x: x, y: y)
        }
        
        // Load window size
        let width = UserDefaults.standard.double(forKey: windowSizeWidthKey)
        let height = UserDefaults.standard.double(forKey: windowSizeHeightKey)
        
        if width > 0 && height > 0 {
            windowSize = CGSize(width: width, height: height)
            contentHeight = height
        }
        
        // Load preferred screen
        if let screenID = UserDefaults.standard.string(forKey: screenIdentifierKey) {
            preferredScreen = findScreen(withIdentifier: screenID)
        }
        
        // Set preferred screen to main if none found or first launch
        if preferredScreen == nil {
            preferredScreen = NSScreen.main
        }
        
        // Load persisted session text
        let savedText = UserDefaults.standard.string(forKey: sessionTextKey) ?? ""
        currentText = savedText
    }
    
    private func persistState() {
        // Persist window position
        UserDefaults.standard.set(windowPosition.x, forKey: positionXKey)
        UserDefaults.standard.set(windowPosition.y, forKey: positionYKey)
        
        // Persist window size
        UserDefaults.standard.set(windowSize.width, forKey: windowSizeWidthKey)
        UserDefaults.standard.set(contentHeight, forKey: windowSizeHeightKey)
        
        // Persist preferred screen
        if let screen = preferredScreen {
            UserDefaults.standard.set(screenIdentifier(for: screen), forKey: screenIdentifierKey)
        }
        
        // Persist session text
        UserDefaults.standard.set(currentText, forKey: sessionTextKey)
    }
    
    private func handleScreenConfigurationChange() {
        // Ensure window remains visible after screen configuration changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.isWindowVisible, let window = self.mercuryWindow {
                self.ensureWindowOnScreen(window)
            }
        }
    }
    
    // MARK: - Screen Utilities
    
    private func findScreen(withIdentifier identifier: String) -> NSScreen? {
        return NSScreen.screens.first { screen in
            screenIdentifier(for: screen) == identifier
        }
    }
    
    private func screenIdentifier(for screen: NSScreen) -> String {
        // Create a unique identifier for the screen based on its properties
        let frame = screen.frame
        return "\(Int(frame.width))x\(Int(frame.height))@\(Int(frame.origin.x)),\(Int(frame.origin.y))"
    }
    
    private func findBestScreen() -> NSScreen {
        // Try to use preferred screen first
        if let preferred = preferredScreen, NSScreen.screens.contains(preferred) {
            return preferred
        }
        
        // Fall back to screen with cursor
        if let cursorScreen = NSScreen.screens.first(where: { screen in
            let mouseLocation = NSEvent.mouseLocation
            return screen.frame.contains(mouseLocation)
        }) {
            return cursorScreen
        }
        
        // Fall back to main screen
        return NSScreen.main ?? NSScreen.screens.first!
    }
    
    func toggleWindow() {
        // Handle edge case where window might be in an inconsistent state
        if let window = mercuryWindow, window.isVisible != isWindowVisible {
            isWindowVisible = window.isVisible
        }
        
        if isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    func forceShow() {
        // Ensure window is shown regardless of current state
        showWindow()
    }
    
    func forceHide() {
        // Ensure window is hidden regardless of current state
        hideWindow()
    }
    
    func showWindow() {
        // Prevent multiple show calls
        guard !isWindowVisible || mercuryWindow?.isVisible != true else { return }
        
        if mercuryWindow == nil {
            createWindow()
        }
        
        guard let window = mercuryWindow else { return }
        
        // Position window appropriately
        if windowPosition == .zero || isFirstLaunch() {
            positionWindowOnBestScreen(window)
            markAsLaunched()
        } else {
            // Use persisted position but ensure it's still on screen
            ensureWindowOnScreen(window)
        }
        
        // Show and focus window with animation
        window.alphaValue = 0.0
        
        // Proper window ordering and activation
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        
        // Activate app and bring to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Update state immediately to prevent double-triggering
        isWindowVisible = true
        isWindowFocused = true
        
        // Animate window appearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
        
        // Ensure text state is loaded and current
        if currentText.isEmpty {
            let savedText = UserDefaults.standard.string(forKey: sessionTextKey) ?? ""
            currentText = savedText
        }
        
        // Focus management with accessibility support
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.establishProperFocus(window)
        }
        
        // Additional focus attempt after window animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.ensureTextFieldFocus()
        }
        
        // Log for debugging
        #if DEBUG
        print("Mercury window shown")
        #endif
    }
    
    func hideWindow() {
        // Prevent multiple hide calls
        guard isWindowVisible, let window = mercuryWindow, window.isVisible else { return }
        
        // Update state immediately to prevent double-triggering
        isWindowVisible = false
        isWindowFocused = false
        
        // Save current text state before hiding
        saveTextState()
        
        // Restore previous app focus if we remember one
        restorePreviousAppFocus()
        
        // Animate window disappearance
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }) {
            window.orderOut(nil)
        }
        
        persistState()
        
        // Log for debugging
        #if DEBUG
        print("Mercury window hidden")
        #endif
    }
    
    private func createWindow() {
        // Create the window content
        let contentView = MercuryWindowContent()
        
        let initialSize = CGSize(width: windowSize.width, height: contentHeight)
        mercuryWindow = MercuryNSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Set up callbacks for our custom window
        if let mercuryNSWindow = mercuryWindow as? MercuryNSWindow {
            mercuryNSWindow.onDragStart = { [weak self] in
                self?.startDrag()
            }
            mercuryNSWindow.onDragEnd = { [weak self] in
                self?.endDrag()
            }
            mercuryNSWindow.onEscapePressed = { [weak self] in
                self?.hideWindow()
            }
            mercuryNSWindow.onPostRequested = { [weak self] in
                self?.handlePostRequest()
            }
        }
        
        guard let window = mercuryWindow else { return }
        
        // Window configuration for floating, borderless appearance
        window.contentView = NSHostingView(rootView: contentView)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false // We'll handle shadows in SwiftUI
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Enable window dragging by background
        window.isMovableByWindowBackground = true
        
        // Set up window delegate for position and focus tracking
        window.delegate = self
        
        // Configure window to not activate other apps when clicking outside
        window.hidesOnDeactivate = false
        
        // Configure focus and accessibility
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
    }
    
    // MARK: - Focus Management
    
    private func establishProperFocus(_ window: NSWindow) {
        // Ensure window can receive key events
        window.makeKey()
        
        // Set first responder to content view to enable text field focus
        window.makeFirstResponder(window.contentView)
        
        // Force focus on the text field with multiple attempts for reliability
        DispatchQueue.main.async {
            // First attempt - immediate
            self.forceFocusOnTextField()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Second attempt - delayed for SwiftUI synchronization
            self.forceFocusOnTextField()
        }
        
        // Announce to accessibility system
        if let contentView = window.contentView {
            NSAccessibility.post(element: contentView, notification: .focusedUIElementChanged)
        }
        
        #if DEBUG
        print("Focus established on Mercury window")
        #endif
    }
    
    private func forceFocusOnTextField() {
        // This method helps ensure the text field gets focus
        // The actual focus is managed by @FocusState in TextInputView
        guard let window = mercuryWindow else { return }
        
        // Ensure window has key focus
        if !window.isKeyWindow {
            window.makeKey()
        }
        
        // Make sure the window is the main window
        if !window.isMainWindow {
            window.makeMain()
        }
    }
    
    private func ensureTextFieldFocus() {
        // Ensure the text field has focus after window appears
        guard isWindowVisible else { return }
        
        if !isTextFieldFocused {
            // If text field doesn't have focus, try to establish it
            forceFocusOnTextField()
            
            #if DEBUG
            print("Ensuring text field focus - current state: \(isTextFieldFocused)")
            #endif
        }
    }
    
    private func restorePreviousAppFocus() {
        // Try to restore focus to the previously active app
        if let previousApp = previousActiveApp,
           previousApp.isTerminated == false {
            previousApp.activate(options: [])
            #if DEBUG
            print("Restored focus to: \(previousApp.localizedName ?? "Unknown")")
            #endif
        }
        
        // Clear the reference
        previousActiveApp = nil
    }
    
    private func positionWindowOnBestScreen(_ window: NSWindow) {
        let screen = findBestScreen()
        preferredScreen = screen
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        // Center horizontally, position in upper third vertically for easy access
        let x = screenFrame.midX - windowFrame.width / 2
        let y = screenFrame.maxY - screenFrame.height / 3 - windowFrame.height / 2
        
        let newOrigin = CGPoint(x: x, y: y)
        window.setFrameOrigin(newOrigin)
        windowPosition = newOrigin
    }
    
    private func ensureWindowOnScreen(_ window: NSWindow) {
        let currentFrame = CGRect(origin: windowPosition, size: windowSize)
        let screens = NSScreen.screens
        
        // Check if window is visible on any screen
        let isOnScreen = screens.contains { screen in
            screen.visibleFrame.intersects(currentFrame)
        }
        
        if !isOnScreen {
            // Reposition to best available screen if not visible
            positionWindowOnBestScreen(window)
        } else {
            // Ensure window is within screen bounds
            let bestScreen = findBestScreen()
            let screenFrame = bestScreen.visibleFrame
            let windowFrame = CGRect(origin: windowPosition, size: windowSize)
            
            var adjustedPosition = windowPosition
            
            // Adjust X position if needed
            if windowFrame.maxX > screenFrame.maxX {
                adjustedPosition.x = screenFrame.maxX - windowFrame.width
            } else if windowFrame.minX < screenFrame.minX {
                adjustedPosition.x = screenFrame.minX
            }
            
            // Adjust Y position if needed
            if windowFrame.maxY > screenFrame.maxY {
                adjustedPosition.y = screenFrame.maxY - windowFrame.height
            } else if windowFrame.minY < screenFrame.minY {
                adjustedPosition.y = screenFrame.minY
            }
            
            window.setFrameOrigin(adjustedPosition)
            windowPosition = adjustedPosition
        }
    }
    
    private func isFirstLaunch() -> Bool {
        return UserDefaults.standard.object(forKey: isFirstLaunchKey) == nil
    }
    
    private func markAsLaunched() {
        UserDefaults.standard.set(false, forKey: isFirstLaunchKey)
    }
    
    func centerWindow() {
        guard let window = mercuryWindow else { return }
        let screen = findBestScreen()
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        let x = screenFrame.midX - windowFrame.width / 2
        let y = screenFrame.midY - windowFrame.height / 2
        
        let newOrigin = CGPoint(x: x, y: y)
        window.setFrameOrigin(newOrigin)
        windowPosition = newOrigin
        preferredScreen = screen
    }
    
    // MARK: - Dragging Support
    
    func startDrag() {
        isDragging = true
    }
    
    func endDrag() {
        isDragging = false
        
        // Snap to screen edges if close
        guard let window = mercuryWindow else { return }
        snapToEdgesIfNeeded(window)
        persistState()
    }
    
    private func snapToEdgesIfNeeded(_ window: NSWindow) {
        let screen = findBestScreen()
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let snapThreshold: CGFloat = 20
        
        var newOrigin = windowFrame.origin
        var didSnap = false
        
        // Snap to left edge
        if abs(windowFrame.minX - screenFrame.minX) < snapThreshold {
            newOrigin.x = screenFrame.minX + 10 // Small margin
            didSnap = true
        }
        
        // Snap to right edge
        if abs(windowFrame.maxX - screenFrame.maxX) < snapThreshold {
            newOrigin.x = screenFrame.maxX - windowFrame.width - 10
            didSnap = true
        }
        
        // Snap to top edge
        if abs(windowFrame.maxY - screenFrame.maxY) < snapThreshold {
            newOrigin.y = screenFrame.maxY - windowFrame.height - 10
            didSnap = true
        }
        
        if didSnap {
            // Animate the snap
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrameOrigin(newOrigin)
            }
            windowPosition = newOrigin
        }
    }
    
    // MARK: - Public Utilities
    
    func moveToScreen(_ screen: NSScreen) {
        guard let window = mercuryWindow else { return }
        
        preferredScreen = screen
        positionWindowOnBestScreen(window)
        persistState()
    }
    
    func resetPosition() {
        guard let window = mercuryWindow else { return }
        
        // Reset to default position on best screen
        positionWindowOnBestScreen(window)
        persistState()
    }
    
    func constrainToScreen() {
        guard let window = mercuryWindow else { return }
        ensureWindowOnScreen(window)
        persistState()
    }
    
    func getScreenInfo() -> [(name: String, screen: NSScreen)] {
        return NSScreen.screens.enumerated().map { index, screen in
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            return (name: name, screen: screen)
        }
    }
    
    var currentScreenName: String {
        guard let screen = preferredScreen else { return "Unknown" }
        return screen.localizedName.isEmpty ? "Main Display" : screen.localizedName
    }
    
    // MARK: - Window System Integration
    
    func bringToFront() {
        guard let window = mercuryWindow else { return }
        
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKey()
        
        NSApp.activate(ignoringOtherApps: true)
        isWindowFocused = true
    }
    
    func sendToBack() {
        guard let window = mercuryWindow else { return }
        
        window.level = .normal
        window.orderBack(nil)
        isWindowFocused = false
    }
    
    func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func getCurrentlyFocusedApp() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }
    
    func getWindowInfo() -> [String: Any] {
        guard let window = mercuryWindow else {
            return ["status": "not_created"]
        }
        
        return [
            "isVisible": isWindowVisible,
            "isFocused": isWindowFocused,
            "isDragging": isDragging,
            "position": NSStringFromPoint(window.frame.origin),
            "size": NSStringFromSize(window.frame.size),
            "level": window.level.rawValue,
            "screen": currentScreenName,
            "canBecomeKey": window.canBecomeKey,
            "isKeyWindow": window.isKeyWindow,
            "isMainWindow": window.isMainWindow
        ]
    }
    
    func updateWindowSize(_ newSize: CGSize) {
        guard let window = mercuryWindow else { return }
        
        let currentFrame = window.frame
        let newFrame = CGRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y - (newSize.height - currentFrame.height), // Grow upward
            width: newSize.width,
            height: newSize.height
        )
        
        window.setFrame(newFrame, display: true, animate: true)
        windowSize = newSize
        persistState()
    }
    
    func updateContentHeight(_ newHeight: CGFloat) {
        contentHeight = newHeight
        
        // Only resize if window is visible to avoid unnecessary operations
        guard isWindowVisible else { return }
        
        let newSize = CGSize(width: windowSize.width, height: newHeight)
        updateWindowSize(newSize)
    }
    
    // MARK: - Text Management
    
    func clearText() {
        currentText = ""
        UserDefaults.standard.set("", forKey: sessionTextKey)
    }
    
    func saveTextState() {
        UserDefaults.standard.set(currentText, forKey: sessionTextKey)
    }
    
    func hasUnsavedText() -> Bool {
        return !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func canPost() -> Bool {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty && currentText.count <= 280
    }
    
    func getCharacterCount() -> Int {
        return currentText.count
    }
    
    func getCharactersRemaining() -> Int {
        return 280 - currentText.count
    }
    
    /// Determines if text input should be disabled due to posting or authentication operations
    var shouldDisableTextInput: Bool {
        // Disable during posting operations
        if postingState.shouldDisableInput {
            return true
        }
        
        // Disable during authentication operations
        if isAuthenticationInProgress {
            return true
        }
        
        // Disable during connection state changes that require user to wait
        switch connectionStatus {
        case .connecting, .refreshing, .disconnecting:
            return true
        default:
            return false
        }
    }
    
    /// Gets the appropriate timeout for posting operations coordinated with AuthManager
    /// Implements task 3.9 requirement for 10-second max timeout
    private func getPostingTimeout() -> TimeInterval {
        // Use TimeoutConfiguration for standardized timeout (10 seconds per PRD)
        return TimeoutConfiguration.postTimeout
    }
    
    /// Performs posting with network timeout handling coordinated with AuthManager
    /// Implements task 3.9 requirement for 10-second max timeout with network state awareness
    private func performPostingWithTimeout(
        authManager: AuthManager,
        text: String,
        timeout: TimeInterval
    ) async -> Result<TweetPostSuccess, TweetPostError> {
        
        let startTime = Date()
        
        #if DEBUG
        print("🌐 Starting posting with \(timeout)s timeout (AuthManager internal timeout coordination)")
        #endif
        
        return await withTaskGroup(of: Result<TweetPostSuccess, TweetPostError>.self) { group in
            // Add the actual posting task
            group.addTask {
                return await authManager.postTweet(text)
            }
            
            // Add the timeout task with coordinated timing
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                let elapsed = Date().timeIntervalSince(startTime)
                
                #if DEBUG
                print("⏰ Posting operation timed out after \(String(format: "%.1f", elapsed))s (max: \(timeout)s)")
                #endif
                
                // Return network timeout error to distinguish from AuthManager errors
                return .failure(.networkError)
            }
            
            // Return the first result (either success/error from posting, or timeout)
            guard let result = await group.next() else {
                #if DEBUG
                print("❌ Unexpected posting task group failure")
                #endif
                return .failure(.networkError)
            }
            
            // Cancel remaining tasks to clean up
            group.cancelAll()
            
            // Log successful completion timing for debugging
            if case .success = result {
                let elapsed = Date().timeIntervalSince(startTime)
                #if DEBUG
                print("✅ Posting completed in \(String(format: "%.1f", elapsed))s (within \(timeout)s timeout)")
                #endif
            }
            
            return result
        }
    }
    
    /// Determines the appropriate visual feedback for disabled text input
    var textInputDisabledReason: String {
        if postingState.shouldDisableInput {
            if let progress = postingState.progress {
                return progress.displayText
            }
            return "Posting in progress..."
        }
        
        if isAuthenticationInProgress {
            switch connectionStatus {
            case .connecting(let progress):
                return progress?.displayText ?? "Authenticating..."
            case .refreshing(let reason):
                return reason.displayText
            default:
                return "Authentication in progress..."
            }
        }
        
        switch connectionStatus {
        case .connecting:
            return "Connecting to X..."
        case .refreshing:
            return "Refreshing connection..."
        case .disconnecting:
            return "Disconnecting..."
        default:
            return "Please wait..."
        }
    }
    
    // MARK: - Authentication Operations
    
    /// Starts an authentication operation, disabling text input during the process
    func startAuthenticationOperation() async -> AuthenticationResult {
        guard let authManager = authManager else {
            return .failure(.networkError("AuthManager not configured"))
        }
        
        // Update UI to show authentication is starting
        await MainActor.run {
            isAuthenticationInProgress = true
            connectionStatus = .connecting(progress: AuthenticationProgress(phase: .starting))
        }
        
        let result = await authManager.authenticate()
        
        // Update UI based on result
        await MainActor.run {
            updateConnectionStatus() // This will set isAuthenticationInProgress to false
        }
        
        return result
    }
    
    /// Manually triggers token refresh, disabling text input during the process
    func refreshAuthentication() async -> AuthenticationResult {
        guard let authManager = authManager else {
            return .failure(.networkError("AuthManager not configured"))
        }
        
        // Update UI to show refresh is starting
        await MainActor.run {
            isAuthenticationInProgress = true
            connectionStatus = .refreshing(reason: .userRequested)
        }
        
        let result = await authManager.startReauthentication()
        
        // Update UI based on result
        await MainActor.run {
            updateConnectionStatus() // This will set isAuthenticationInProgress to false
        }
        
        return result
    }
    
    // MARK: - Keyboard Shortcuts
    
    func handlePostRequest() {
        // Only attempt to post if content is valid
        guard canPost() else {
            // Could add haptic feedback or sound for invalid post attempt
            NSSound.beep()
            return
        }
        
        // Check if AuthManager is available
        guard let authManager = authManager else {
            #if DEBUG
            print("⚠️ AuthManager not configured, cannot post tweet")
            #endif
            NSSound.beep()
            return
        }
        
        // Enhanced authentication state check (task 3.11)
        guard canPostWithCurrentAuthState(authManager) else {
            handlePostRequestBlockedByAuth(authManager)
            return
        }
        
        // Post via AuthManager using async task with proper state management
        let textToPost = currentText
        
        #if DEBUG
        print("📝 Posting tweet via AuthManager: \(textToPost)")
        #endif
        
        Task {
            // Start posting flow with validation state
            await MainActor.run {
                setPostingState(.loading(PostingProgress(phase: .validating)))
            }
            
            // Small delay to show validation phase
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Check authentication status before posting
            await MainActor.run {
                let authRequired = !authManager.isAuthenticated()
                setPostingState(.loading(PostingProgress(
                    phase: authRequired ? .authenticating : .checkingRateLimit,
                    authenticationRequired: authRequired
                )))
            }
            
            // Brief delay to show authentication check
            if !authManager.isAuthenticated() {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for auth check
            } else {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds for rate limit check
            }
            
            await MainActor.run {
                setPostingState(.loading(PostingProgress(phase: .posting)))
            }
            
            // Execute posting with network timeout handling (task 3.9)
            let postingTimeout = getPostingTimeout()
            let result = await performPostingWithTimeout(authManager: authManager, text: textToPost, timeout: postingTimeout)
            
            await MainActor.run {
                switch result {
                case .success(let success):
                    #if DEBUG
                    print("✅ Tweet posted successfully: \(success.tweetId)")
                    #endif
                    
                    // Show success state with tweet details
                    setPostingState(.success(success))
                    
                    // Clear text after successful post
                    clearText()
                    
                    // Auto-clear success state and auto-hide window after 2.5 seconds
                    // This provides enough time for users to see the success confirmation
                    // and optionally interact with tweet link before auto-hide
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.autoHideAfterSuccess()
                    }
                    
                case .failure(let error):
                    #if DEBUG
                    print("❌ Tweet posting failed: \(error.localizedDescription)")
                    #endif
                    
                    // Handle queue integration for offline/failed authentication scenarios (task 3.10)
                    await handlePostingFailureWithQueue(error: error, textToPost: textToPost, authManager: authManager)
                }
            }
        }
    }
    
    private func setPostingState(_ newState: PostingState) {
        postingState = newState
    }
    
    private func getSuggestedActions(for error: TweetPostError) -> [ErrorAction] {
        // Consider if queue manager is available for enhanced suggestions
        let hasQueueManager = postQueueManager != nil
        
        switch error {
        case .notAuthenticated:
            return [.reconnect, .dismiss]
        case .invalidTweetText:
            return [.editText, .dismiss]
        case .rateLimitExceeded:
            // If queue manager available, suggest viewing usage instead of retry (will be auto-queued)
            return hasQueueManager ? [.viewUsage, .dismiss] : [.retry, .viewUsage, .dismiss]
        case .networkError:
            // If queue manager available, post will be auto-queued, so don't suggest manual retry
            return hasQueueManager ? [.dismiss] : [.retry, .dismiss]
        case .serverError:
            // If queue manager available, post will be auto-queued
            return hasQueueManager ? [.copyError, .dismiss] : [.retry, .copyError, .dismiss]
        case .unknown:
            // If queue manager available, post will be auto-queued
            return hasQueueManager ? [.copyError, .dismiss] : [.retry, .copyError, .dismiss]
        }
    }
    
    /// Auto-clear success state and auto-hide window after successful posting
    /// This implements the requirement from task 3.8 for 2-3 second auto-hide behavior
    private func autoHideAfterSuccess() {
        // Only proceed if we're still in a success state
        // (user might have manually hidden window or started new post)
        guard postingState.isSuccess else { return }
        
        #if DEBUG
        print("🔄 Auto-clearing success state and hiding window")
        #endif
        
        // Clear the success state back to idle
        setPostingState(.idle)
        
        // Hide the window to complete the auto-hide behavior
        hideWindow()
        
        // Add subtle audio feedback to confirm the action
        NSSound(named: .defaultSystemSound)?.play()
    }
    
    /// Handles posting failures with queue integration for offline/failed authentication scenarios
    /// Implements task 3.10 requirement for queuing posts when appropriate
    private func handlePostingFailureWithQueue(
        error: TweetPostError,
        textToPost: String,
        authManager: AuthManager
    ) async {
        
        // Determine if this failure should result in queuing the post
        let shouldQueue = shouldQueuePostForError(error, authManager: authManager)
        
        if shouldQueue, let queueManager = postQueueManager {
            #if DEBUG
            print("📨 Queuing post due to \(error): \"\(String(textToPost.prefix(30)))...\"")
            #endif
            
            // Queue the post for retry
            let wasQueued = await queueManager.queuePost(textToPost)
            
            if wasQueued {
                // Show success state for queuing (different from posting success)
                let queueSuccess = TweetPostSuccess(
                    tweetId: "queued_\(UUID().uuidString)",
                    text: "Post queued for retry", // Indicate this is queued, not posted
                    createdAt: Date()
                )
                
                setPostingState(.success(queueSuccess))
                
                // Clear text since it's now queued
                clearText()
                
                // Provide user feedback about queuing
                #if DEBUG
                print("✅ Post queued successfully for retry when connection is restored")
                #endif
                
                // Auto-hide after showing queue confirmation
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.autoHideAfterSuccess()
                }
                
            } else {
                // Queuing failed (likely duplicate), show regular error
                await showPostingError(error: error, textToPost: textToPost, authManager: authManager, wasQueued: false)
            }
            
        } else {
            // Don't queue, show regular error
            await showPostingError(error: error, textToPost: textToPost, authManager: authManager, wasQueued: false)
        }
    }
    
    /// Determines if a posting error should result in queuing the post
    private func shouldQueuePostForError(_ error: TweetPostError, authManager: AuthManager) -> Bool {
        switch error {
        case .notAuthenticated:
            // Queue if authentication is completely failed
            return authManager.authenticationState != .authenticated
            
        case .networkError:
            // Queue for network errors (includes timeouts from our timeout handling)
            return true
            
        case .serverError:
            // Queue for server errors (X API might be down)
            return true
            
        case .rateLimitExceeded:
            // Queue for rate limiting - will be retried later
            return true
            
        case .invalidTweetText:
            // Don't queue invalid text - user needs to fix it
            return false
            
        case .unknown:
            // Queue unknown errors to be safe
            return true
        }
    }
    
    /// Shows posting error with appropriate state and user feedback
    private func showPostingError(
        error: TweetPostError,
        textToPost: String,
        authManager: AuthManager,
        wasQueued: Bool
    ) async {
        await MainActor.run {
            // Create error state with preserved text
            let errorState = PostingErrorState(
                error: error,
                isRecoverable: true,
                preservedText: textToPost,
                canRetry: !wasQueued, // Don't show retry if it was queued
                authenticationState: authManager.authenticationState,
                suggestedActions: getSuggestedActions(for: error)
            )
            
            setPostingState(.error(errorState))
            
            // Provide audio feedback for failed post
            NSSound.beep()
            
            #if DEBUG
            print("❌ Showing error state for \(error): preserved text for user")
            #endif
        }
    }
    
    deinit {
        // Clean up observers
        if let observer = screenConfigurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        if let observer = applicationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Remove any remaining notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Final state persistence
        persistState()
        
        // Restore focus to previous app if needed
        restorePreviousAppFocus()
    }
}

// MARK: - Window Delegate
extension WindowManager: NSWindowDelegate {
    func windowWillStartLiveResize(_ notification: Notification) {
        isDragging = true
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        isDragging = false
        endDrag()
    }
    
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windowPosition = window.frame.origin
        
        // Update preferred screen based on current position
        let currentScreen = NSScreen.screens.first { screen in
            screen.frame.contains(window.frame.origin)
        }
        
        if let screen = currentScreen {
            preferredScreen = screen
        }
        
        // Debounced persistence to avoid excessive UserDefaults writes
        NSObject.cancelPreviousPerformRequests(target: self, selector: #selector(debouncedPersistState), object: nil)
        perform(#selector(debouncedPersistState), with: nil, afterDelay: 0.5)
    }
    
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windowSize = window.frame.size
        
        // Debounced persistence
        NSObject.cancelPreviousPerformRequests(target: self, selector: #selector(debouncedPersistState), object: nil)
        perform(#selector(debouncedPersistState), with: nil, afterDelay: 0.5)
    }
    
    @objc private func debouncedPersistState() {
        persistState()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        isWindowFocused = true
        
        // Ensure proper window level when becoming key
        if let window = notification.object as? NSWindow {
            window.level = .floating
        }
        
        #if DEBUG
        print("Mercury window became key")
        #endif
    }
    
    func windowDidResignKey(_ notification: Notification) {
        isWindowFocused = false
        
        // Hide window when it loses key focus (user clicks elsewhere)
        // But only if we're not in the middle of a drag operation
        guard !isDragging else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.isWindowVisible && !self.isDragging {
                self.hideWindow()
            }
        }
        
        #if DEBUG
        print("Mercury window resigned key")
        #endif
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false // Don't actually close, just hide
    }
    
    // Handle escape key to hide window
    func windowWillReturnFieldEditor(_ sender: NSWindow, to object: Any?) -> Any? {
        // This will be used later to capture Escape key presses
        return nil
    }
}

// MARK: - Mercury Window Content
struct MercuryWindowContent: View {
    @StateObject private var windowManager = WindowManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var dragOffset = CGSize.zero
    @State private var isDragHovering = false
    
    private var shouldShowSidebar: Bool {
        // Show sidebar for extended disconnection periods or when status area is cluttered
        let isDisconnected = windowManager.connectionStatus.isDisconnected || windowManager.connectionStatus.isError
        let hasTextContent = !windowManager.currentText.isEmpty
        return isDisconnected && hasTextContent
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Drag handle area
                DragHandleView(isDragging: $windowManager.isDragging, isHovering: $isDragHovering)
                
                // Main content area with text input
                MainContentView(text: $windowManager.currentText)
            }
            
            // Sidebar for contextual reconnect (task 4.6)
            if shouldShowSidebar {
                VStack {
                    Spacer()
                    ContextualReconnectButton(windowManager: windowManager, placement: .sidebar)
                    Spacer()
                }
                .frame(width: 24)
                .background(Color.clear)
            }
        }
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(windowManager.isDragging ? 0.4 : 0.25), radius: windowManager.isDragging ? 30 : 20, x: 0, y: windowManager.isDragging ? 15 : 10)
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
        .overlay(
            // Subtle border with drag state
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: windowManager.isDragging ? 1.0 : 0.5)
        )
        .overlay(
            // Ultra-subtle authentication status glow (task 4.5)
            PeripheralStatusGlow(windowManager: windowManager)
        )
        .scaleEffect(windowManager.isDragging ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: windowManager.isDragging)
    }
    
    private var windowBackground: some ShapeStyle {
        if colorScheme == .dark {
            return Material.hudWindow
        } else {
            return Material.regular
        }
    }
    
    private var borderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.15)
        } else {
            return Color.black.opacity(0.08)
        }
    }
}

// MARK: - Main Content View
struct MainContentView: View {
    @Binding var text: String
    @StateObject private var windowManager = WindowManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Authentication status header (task 4.2 & 4.5)
            AuthenticationStatusHeader(windowManager: windowManager, useMinimalistDesign: false)
            
            // Text input field using our new TextInputView
            TextInputView(
                text: $text,
                isInputDisabled: windowManager.shouldDisableTextInput,
                onHeightChange: { newHeight in
                    handleTextHeightChange(newHeight)
                },
                onPostRequested: {
                    // Prevent posting if text input is disabled or posting is not allowed
                    if !windowManager.shouldDisableTextInput && !windowManager.postingState.shouldDisablePosting {
                        WindowManager.shared.handlePostRequest()
                    } else {
                        // Provide audio feedback when action is blocked
                        NSSound.beep()
                    }
                },
                onEscapePressed: {
                    WindowManager.shared.hideWindow()
                },
                onFocusChange: { focused in
                    WindowManager.shared.isTextFieldFocused = focused
                }
            )
            .disabled(windowManager.shouldDisableTextInput)
            .opacity(windowManager.shouldDisableTextInput ? 0.6 : 1.0)
            .overlay(
                // Disabled state overlay with reason
                Group {
                    if windowManager.shouldDisableTextInput {
                        DisabledTextInputOverlay(reason: windowManager.textInputDisabledReason)
                    }
                }
            )
            
            // Status and actions row
            HStack {
                // Left side - character counter or status
                if windowManager.postingState.isLoading {
                    PostingStatusView(postingState: windowManager.postingState)
                } else if windowManager.postingState.isError {
                    PostingErrorView(postingState: windowManager.postingState)
                        .transition(.opacity)
                } else if windowManager.postingState.isSuccess {
                    EnhancedPostingSuccessView(postingState: windowManager.postingState)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 12) {
                        CharacterCounterView(characterCount: text.count)
                        
                        // Posting disabled indicator (task 4.3)
                        PostingDisabledIndicator(windowManager: windowManager)
                        
                        // Contextual reconnect in status area (task 4.6)
                        ContextualReconnectButton(windowManager: windowManager, placement: .statusArea)
                        
                        // Enhanced discrete status indicators (task 4.7)
                        DiscreteStatusBar(windowManager: windowManager, showQualityIndicator: false)
                    }
                }
                
                Spacer()
                
                // Right side - post button, progress indicator, or success actions
                if windowManager.postingState.isLoading {
                    PostingProgressIndicator()
                } else if windowManager.postingState.isSuccess {
                    SuccessActionsView(postingState: windowManager.postingState)
                } else {
                    // Enhanced posting button with authentication-aware state management (task 3.12)
                    PostingButton(
                        text: text,
                        postingState: windowManager.postingState,
                        connectionStatus: windowManager.connectionStatus,
                        onPost: {
                            WindowManager.shared.handlePostRequest()
                        }
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 360) // Slightly smaller than window for padding
        .animation(.easeInOut(duration: 0.2), value: windowManager.postingState.isLoading)
        .animation(.easeInOut(duration: 0.2), value: windowManager.postingState.isError)
        .animation(.easeInOut(duration: 0.2), value: windowManager.postingState.isSuccess)
    }
    
    
    private func handleTextHeightChange(_ newTextHeight: CGFloat) {
        // Calculate total content height: padding + auth header + text input + spacing + bottom row + padding
        let totalPadding: CGFloat = 40 // 20 top + 20 bottom
        let authHeaderHeight: CGFloat = 32 // Authentication status header height
        let bottomRowHeight: CGFloat = 28 // Character counter and button row
        let spacing: CGFloat = 16 // Spacing between components (2 instances: after auth header, after text input)
        let dragHandleHeight: CGFloat = 24
        
        let newContentHeight = dragHandleHeight + totalPadding + authHeaderHeight + newTextHeight + (spacing * 2) + bottomRowHeight
        
        // Only update if height actually changed significantly
        if abs(WindowManager.shared.contentHeight - newContentHeight) > 2 {
            DispatchQueue.main.async {
                WindowManager.shared.updateContentHeight(newContentHeight)
            }
        }
    }
}

// MARK: - Enhanced Posting Button Component

/// Enhanced posting button with authentication-aware state management
/// Implements task 3.12 requirement for posting button state management based on authentication status
struct PostingButton: View {
    let text: String
    let postingState: PostingState
    let connectionStatus: ConnectionStatus
    let onPost: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onPost) {
            HStack(spacing: 6) {
                // Authentication status icon
                authenticationIcon
                
                // Button text
                Text(buttonText)
                    .fontWeight(.medium)
                    .font(.system(size: 13))
            }
            .foregroundColor(buttonTextColor)
        }
        .buttonStyle(PostingButtonStyle(
            isEnabled: !shouldDisablePosting,
            buttonState: currentButtonState,
            colorScheme: colorScheme
        ))
        .controlSize(.small)
        .disabled(shouldDisablePosting)
        .help(helpText)
        .animation(.easeInOut(duration: 0.15), value: currentButtonState)
    }
    
    // MARK: - Button State Logic
    
    private var currentButtonState: PostingButtonState {
        // Determine button state based on authentication and posting status
        if postingState.shouldDisablePosting {
            return .posting
        }
        
        switch connectionStatus {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            if canPostWithText {
                return .ready
            } else {
                return .textInvalid
            }
        case .refreshing:
            return .refreshing
        case .error:
            return .authError
        case .disconnecting:
            return .disconnecting
        }
    }
    
    private var shouldDisablePosting: Bool {
        // Enhanced posting validation with authentication awareness
        switch currentButtonState {
        case .ready:
            return false
        case .posting, .connecting, .refreshing, .disconnected, .authError, .textInvalid, .disconnecting:
            return true
        }
    }
    
    private var canPostWithText: Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty && text.count <= 280
    }
    
    // MARK: - UI Properties
    
    private var buttonText: String {
        switch currentButtonState {
        case .ready:
            return "Post"
        case .posting:
            return "Posting..."
        case .connecting:
            return "Connecting..."
        case .refreshing:
            return "Refreshing..."
        case .disconnected:
            return "Connect"
        case .authError:
            return "Reconnect"
        case .textInvalid:
            return "Post"
        case .disconnecting:
            return "Disconnecting..."
        }
    }
    
    private var authenticationIcon: some View {
        Group {
            switch currentButtonState {
            case .ready:
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
            case .posting:
                Image(systemName: "paperplane")
                    .foregroundColor(.white.opacity(0.7))
            case .connecting, .refreshing:
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.orange)
            case .disconnected, .authError:
                Image(systemName: "wifi.slash")
                    .foregroundColor(.red)
            case .textInvalid:
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.gray)
            case .disconnecting:
                Image(systemName: "wifi")
                    .foregroundColor(.gray)
            }
        }
        .font(.system(size: 12, weight: .semibold))
    }
    
    private var buttonTextColor: Color {
        switch currentButtonState {
        case .ready:
            return .white
        case .posting:
            return .white.opacity(0.8)
        case .connecting, .refreshing:
            return .primary
        case .disconnected, .authError:
            return .primary
        case .textInvalid:
            return .secondary
        case .disconnecting:
            return .secondary
        }
    }
    
    private var helpText: String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch currentButtonState {
        case .ready:
            if case .connected(let user) = connectionStatus {
                return "Post to X as @\(user.username) (⌘⏎)"
            } else {
                return "Post to X (⌘⏎)"
            }
            
        case .posting:
            return "Currently posting your message..."
            
        case .connecting:
            return "Connecting to X..."
            
        case .refreshing:
            return "Refreshing connection to X..."
            
        case .disconnected:
            return "Connect to X to post your message"
            
        case .authError:
            return "Authentication error - click to reconnect"
            
        case .textInvalid:
            if trimmedText.isEmpty {
                return "Enter some text to post"
            } else if text.count > 280 {
                let overCount = text.count - 280
                return "Post disabled: \(overCount) character\(overCount == 1 ? "" : "s") over limit"
            } else {
                return "Text validation error"
            }
            
        case .disconnecting:
            return "Disconnecting from X..."
        }
    }
}

// MARK: - Posting Button State

/// States for the posting button based on authentication and text validation
enum PostingButtonState {
    case ready           // Authenticated and text is valid
    case posting         // Currently posting
    case connecting      // Authenticating
    case refreshing      // Token refresh in progress
    case disconnected    // Not authenticated
    case authError       // Authentication error
    case textInvalid     // Text is empty or over limit
    case disconnecting   // Disconnecting
}

// MARK: - Posting Button Style

/// Custom button style for the posting button with state-aware appearance
struct PostingButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let buttonState: PostingButtonState
    let colorScheme: ColorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(backgroundFor(state: buttonState, isPressed: configuration.isPressed))
            .foregroundColor(foregroundColorFor(state: buttonState))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColorFor(state: buttonState), lineWidth: borderWidthFor(state: buttonState))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
    
    private func backgroundFor(state: PostingButtonState, isPressed: Bool) -> Color {
        let pressedOpacity: Double = isPressed ? 0.8 : 1.0
        
        switch state {
        case .ready:
            return Color.accentColor.opacity(pressedOpacity)
        case .posting:
            return Color.accentColor.opacity(0.7 * pressedOpacity)
        case .connecting, .refreshing:
            return Color.orange.opacity(0.2 * pressedOpacity)
        case .disconnected, .authError:
            return Color.red.opacity(0.1 * pressedOpacity)
        case .textInvalid, .disconnecting:
            return (colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)).opacity(pressedOpacity)
        }
    }
    
    private func foregroundColorFor(state: PostingButtonState) -> Color {
        switch state {
        case .ready, .posting:
            return .white
        case .connecting, .refreshing:
            return .orange
        case .disconnected, .authError:
            return .red
        case .textInvalid, .disconnecting:
            return .secondary
        }
    }
    
    private func borderColorFor(state: PostingButtonState) -> Color {
        switch state {
        case .ready, .posting:
            return .clear
        case .connecting, .refreshing:
            return .orange.opacity(0.3)
        case .disconnected, .authError:
            return .red.opacity(0.3)
        case .textInvalid, .disconnecting:
            return .secondary.opacity(0.3)
        }
    }
    
    private func borderWidthFor(state: PostingButtonState) -> CGFloat {
        switch state {
        case .ready, .posting:
            return 0
        case .connecting, .refreshing, .disconnected, .authError, .textInvalid, .disconnecting:
            return 1
        }
    }
}

// MARK: - Drag Handle View
struct DragHandleView: View {
    @Binding var isDragging: Bool
    @Binding var isHovering: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            // Left side - drag dots indicator
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { _ in
                    Circle()
                        .fill(dotColor)
                        .frame(width: 3, height: 3)
                }
            }
            .opacity(isHovering || isDragging ? 0.6 : 0.3)
            
            Spacer()
            
            // Right side - discrete connection status with tooltip (task 4.7)
            MinimalistStatusDot(windowManager: WindowManager.shared)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle()) // Make entire area draggable
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    
                    // The actual window movement is handled by NSWindow.isMovableByWindowBackground
                    // This gesture just provides visual feedback
                }
                .onEnded { value in
                    isDragging = false
                    
                    // Trigger persistence after drag ends
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        WindowManager.shared.persistState()
                    }
                }
        )
        .cursor(isHovering ? .openHand : .arrow)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
    
    private var dotColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.6)
        } else {
            return Color.black.opacity(0.4)
        }
    }
}

// MARK: - Character Counter View
struct CharacterCounterView: View {
    let characterCount: Int
    private let maxCharacters = 280
    
    var body: some View {
        HStack(spacing: 8) {
            // Character count text with enhanced styling when over limit
            Group {
                if characterCount > maxCharacters {
                    Text("\(characterCount)/\(maxCharacters)")
                        .font(.caption)
                        .foregroundColor(textColor)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red.opacity(0.1))
                                .padding(.horizontal, -3)
                                .padding(.vertical, -1)
                        )
                } else {
                    Text("\(characterCount)/\(maxCharacters)")
                        .font(.caption)
                        .foregroundColor(textColor)
                        .monospacedDigit()
                }
            }
            
            // Visual progress indicator
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 16, height: 16)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: min(1.0, progressPercentage))
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progressPercentage)
                
                // Warning indicator when over limit
                if characterCount > maxCharacters {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white))
                        .scaleEffect(0.8)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: characterCount > maxCharacters)
    }
    
    private var progressPercentage: CGFloat {
        CGFloat(characterCount) / CGFloat(maxCharacters)
    }
    
    private var textColor: Color {
        if characterCount > maxCharacters {
            return .red
        } else if characterCount > maxCharacters - 20 {
            return .orange
        } else {
            return .secondary
        }
    }
    
    private var progressColor: Color {
        if characterCount > maxCharacters {
            return .red
        } else if characterCount > maxCharacters - 20 {
            return .orange
        } else {
            return .accentColor
        }
    }
}

// MARK: - Cursor Extension
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Posting State UI Components

struct PostingStatusView: View {
    let postingState: PostingState
    
    var body: some View {
        HStack(spacing: 8) {
            if let progress = postingState.progress {
                Text(progress.displayText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct PostingProgressIndicator: View {
    @StateObject private var windowManager = WindowManager.shared
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Enhanced circular progress indicator with authentication status
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 20, height: 20)
                
                // Progress circle - shows different progress based on phase
                Circle()
                    .trim(from: 0, to: progressAmount)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progressAmount)
                
                // Animated spinner overlay for indeterminate progress
                if shouldShowSpinner {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(progressColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                }
                
                // Authentication status indicator
                if showAuthenticationIcon {
                    Image(systemName: "key.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(authenticationIconColor)
                        .background(
                            Circle()
                                .fill(Color(.windowBackgroundColor))
                                .frame(width: 12, height: 12)
                        )
                        .scaleEffect(0.8)
                }
            }
            .onAppear {
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
            }
            
            // Status text with authentication context
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryStatusText)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let secondaryText = secondaryStatusText {
                    Text(secondaryText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentProgress: PostingProgress? {
        windowManager.postingState.progress
    }
    
    private var progressAmount: CGFloat {
        guard let progress = currentProgress else { return 0.0 }
        return CGFloat(progress.progressPercentage)
    }
    
    private var progressColor: Color {
        guard let progress = currentProgress else { return .accentColor }
        
        if progress.authenticationRequired {
            return .orange
        }
        
        switch progress.phase {
        case .validating:
            return .blue
        case .authenticating:
            return .orange
        case .checkingRateLimit:
            return .yellow
        case .posting:
            return .accentColor
        case .processing:
            return .green
        case .queuing:
            return .purple
        }
    }
    
    private var shouldShowSpinner: Bool {
        guard let progress = currentProgress else { return true }
        return progress.isIndeterminate
    }
    
    private var showAuthenticationIcon: Bool {
        guard let progress = currentProgress else { return false }
        return progress.authenticationRequired || progress.phase == .authenticating
    }
    
    private var authenticationIconColor: Color {
        guard let progress = currentProgress else { return .secondary }
        
        if progress.authenticationRequired {
            return .orange
        } else {
            return .green
        }
    }
    
    private var primaryStatusText: String {
        guard let progress = currentProgress else { return "Posting..." }
        return progress.displayText
    }
    
    private var secondaryStatusText: String? {
        guard let progress = currentProgress else { return nil }
        
        if progress.authenticationRequired {
            return "Auth required"
        }
        
        // Show authentication status for relevant phases
        switch progress.phase {
        case .authenticating:
            return "Checking credentials"
        case .checkingRateLimit:
            return "Verifying limits"
        case .posting:
            if let authManager = windowManager.authManager,
               let user = authManager.getCurrentUser() {
                return "As @\(user.username)"
            }
            return "Sending to X"
        default:
            return nil
        }
    }
}

struct PostingErrorView: View {
    let postingState: PostingState
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
            
            if let errorState = postingState.errorState {
                Text(errorState.displayDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
}

struct PostingSuccessView: View {
    let postingState: PostingState
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Animated success icon
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatCount(1, autoreverses: true), value: isAnimating)
                .onAppear {
                    withAnimation {
                        isAnimating = true
                    }
                }
            
            VStack(alignment: .leading, spacing: 2) {
                // Success message
                Text("Posted successfully!")
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.medium)
                
                // Tweet link if available
                if let successInfo = postingState.successInfo {
                    HStack(spacing: 6) {
                        // Tweet link button
                        Button(action: {
                            openTweetInBrowser(tweetId: successInfo.tweetId)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.caption2)
                                Text("View tweet")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Open tweet in browser")
                        
                        // Copy link button
                        Button(action: {
                            copyTweetLink(tweetId: successInfo.tweetId)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Copy tweet link")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func openTweetInBrowser(tweetId: String) {
        let tweetURL = "https://twitter.com/i/web/status/\(tweetId)"
        if let url = URL(string: tweetURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func copyTweetLink(tweetId: String) {
        let tweetURL = "https://twitter.com/i/web/status/\(tweetId)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tweetURL, forType: .string)
        
        // Provide brief visual feedback
        NSSound(named: "Tink")?.play()
    }
}

// MARK: - Enhanced Success View

struct EnhancedPostingSuccessView: View {
    let postingState: PostingState
    @State private var isAnimating = false
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main success indicator
            HStack(spacing: 10) {
                // Animated checkmark with pulse effect
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 24, height: 24)
                        .scaleEffect(isAnimating ? 1.3 : 1.0)
                        .opacity(isAnimating ? 0.0 : 1.0)
                        .animation(
                            .easeOut(duration: 1.5).repeatCount(1, autoreverses: false),
                            value: isAnimating
                        )
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.3).delay(0.1),
                            value: isAnimating
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tweet posted successfully!")
                        .font(.callout)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                    
                    if let successInfo = postingState.successInfo {
                        // Tweet info and actions
                        HStack(spacing: 12) {
                            // Tweet timestamp
                            Text("Posted \(timeAgoString(from: successInfo.createdAt))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            // Actions
                            HStack(spacing: 8) {
                                // View tweet button
                                Button(action: {
                                    openTweetInBrowser(tweetId: successInfo.tweetId)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption2)
                                        Text("View")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Open tweet in browser")
                                
                                // Copy link button
                                Button(action: {
                                    copyTweetLink(tweetId: successInfo.tweetId)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "link")
                                            .font(.caption2)
                                        Text("Copy")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.1))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Copy tweet link to clipboard")
                            }
                        }
                        
                        // Tweet preview (expandable)
                        if showDetails {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tweet content:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text(successInfo.text)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        }
                        
                        // Toggle details button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showDetails.toggle()
                            }
                        }) {
                            HStack(spacing: 2) {
                                Text(showDetails ? "Hide details" : "Show details")
                                    .font(.caption2)
                                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(showDetails ? "Hide tweet details" : "Show tweet details")
                    }
                }
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
            
            // Auto-show details briefly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showDetails = true
                }
            }
            
            // Auto-hide details after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showDetails = false
                }
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
    
    private func openTweetInBrowser(tweetId: String) {
        let tweetURL = "https://twitter.com/i/web/status/\(tweetId)"
        if let url = URL(string: tweetURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func copyTweetLink(tweetId: String) {
        let tweetURL = "https://twitter.com/i/web/status/\(tweetId)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tweetURL, forType: .string)
        
        // Provide brief visual and audio feedback
        NSSound(named: "Tink")?.play()
    }
}

// MARK: - Success Actions View

struct SuccessActionsView: View {
    let postingState: PostingState
    @State private var justCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            if let successInfo = postingState.successInfo {
                // Quick action buttons
                Button(action: {
                    openTweetInBrowser(tweetId: successInfo.tweetId)
                }) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Open tweet in browser")
                
                Button(action: {
                    copyTweetLink(tweetId: successInfo.tweetId)
                }) {
                    Image(systemName: justCopied ? "checkmark" : "link")
                        .font(.callout)
                        .foregroundColor(justCopied ? .green : .primary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy tweet link")
                .animation(.easeInOut(duration: 0.2), value: justCopied)
            }
        }
    }
    
    private func openTweetInBrowser(tweetId: String) {
        let tweetURL = "https://twitter.com/i/web/status/\(tweetId)"
        if let url = URL(string: tweetURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func copyTweetLink(tweetId: String) {
        let tweetURL = "https://twitter.com/i/web/status/\(tweetId)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tweetURL, forType: .string)
        
        // Show temporary checkmark
        withAnimation {
            justCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                justCopied = false
            }
        }
        
        // Provide audio feedback
        NSSound(named: "Tink")?.play()
    }
}

// MARK: - Connection Status Indicator

struct ConnectionStatusIndicator: View {
    let connectionStatus: ConnectionStatus
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Status icon with animation for connecting states
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 12, height: 12)
                
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(connectionStatus.isAnimated && isAnimating ? 1.2 : 1.0)
                    .opacity(connectionStatus.isAnimated && isAnimating ? 0.7 : 1.0)
                    .animation(
                        connectionStatus.isAnimated
                        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                        : .none,
                        value: isAnimating
                    )
            }
            .onAppear {
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
            }
            
            // Status text - compact for space efficiency
            Text(compactStatusText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .help(fullStatusText) // Tooltip for full details
    }
    
    private var statusColor: Color {
        connectionStatus.statusColor
    }
    
    private var compactStatusText: String {
        switch connectionStatus {
        case .disconnected:
            return "Not connected"
        case .connecting:
            return "Connecting..."
        case .connected(let user):
            return "@\(user.username)"
        case .refreshing:
            return "Refreshing..."
        case .disconnecting:
            return "Disconnecting..."
        case .error:
            return "Error"
        }
    }
    
    private var fullStatusText: String {
        switch connectionStatus {
        case .disconnected:
            return "Not connected to X. Click to connect."
        case .connecting(let progress):
            return progress?.displayText ?? "Connecting to X..."
        case .connected(let user):
            return "Connected to X as @\(user.username)"
        case .refreshing(let reason):
            return "Refreshing connection: \(reason.displayText)"
        case .disconnecting:
            return "Disconnecting from X..."
        case .error(let error):
            return "Connection error: \(error.displayText)"
        }
    }
}

// MARK: - Disabled Text Input Overlay

struct DisabledTextInputOverlay: View {
    let reason: String
    @State private var isVisible = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.1))
                    .allowsHitTesting(false)
                
                // Centered reason text
                VStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .lineLimit(2)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
                .scaleEffect(isVisible ? 1.0 : 0.9)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isVisible)
            }
        }
        .allowsHitTesting(false) // Allow interactions to pass through
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2).delay(0.1)) {
                isVisible = true
            }
        }
        .onDisappear {
            isVisible = false
        }
    }
}
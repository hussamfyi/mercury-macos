/*
This file contains the state of the app.
Think of @State as telling SwiftUI: "Watch this value. If it changes, update the UI that uses it."
SwiftUI's state is a property wrapper. It creates a persistent storage location in the app's memory, instead of React where the state is managed in the component.
Also, @State is for simple value types like Int, String, Bool, etc. For more complex data types, we use @StateObject or @ObservedObject.
*/

import SwiftUI
import Foundation
import Combine

class AppState: ObservableObject {
    @Published var entries: [HumanEntry] = []
    @Published var text: String = ""
    /*
    In Swift, you can either explicitly declare it as Bool or let type inference determine it's a Boolean based on the false value. Both approaches are equivalent.
    */
    @Published var isFullscreen = false
    
    // Authentication state integration
    @Published var isAuthenticated = false
    @Published var currentUser: AuthenticatedUser?
    @Published var authenticationError: String?
    
    private var cancellables = Set<AnyCancellable>()
    weak var authManager: AuthManager?
    
    private let aiChatPrompt = """
You are a helpful assistant.
"""
    
    /// Configure AppState with AuthManager for authentication state tracking
    /// - Parameter authManager: The initialized AuthManager instance
    @MainActor
    func configure(with authManager: AuthManager) {
        self.authManager = authManager
        
        // Observe authentication state changes
        authManager.authenticationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateAuthenticationState(state)
            }
            .store(in: &cancellables)
        
        // Observe current user changes
        authManager.currentUserPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.currentUser = user
            }
            .store(in: &cancellables)
    }
    
    private func updateAuthenticationState(_ state: AuthenticationState) {
        switch state {
        case .authenticated:
            isAuthenticated = true
            authenticationError = nil
        case .disconnected:
            isAuthenticated = false
            authenticationError = nil
        case .authenticating:
            authenticationError = nil
        case .refreshing:
            // Keep current authenticated state during refresh
            break
        case .error(let error):
            isAuthenticated = false
            authenticationError = error.localizedDescription
        }
    }
}

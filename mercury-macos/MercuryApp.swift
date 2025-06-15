//
//  MercuryApp.swift
//  Mercury
//
//  Created by Hussam Zaghal on 2025-04-12.
//

import SwiftUI
import Combine

/// Main Mercury application entry point
/// Handles app lifecycle and integrates authentication management
@main
struct MercuryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // AuthManager integrated for X API authentication
    @StateObject private var authManager = AuthManagerWrapper()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .toolbar(.hidden)
                .environmentObject(authManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .defaultSize(width: 1100, height: 600)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        
        // Preferences Window
        Settings {
            PreferencesView()
                .environmentObject(PreferencesManager.shared)
                .environmentObject(authManager)
        }
    }
}

/// Wrapper class to handle AuthManager's async initialization in SwiftUI
@MainActor
class AuthManagerWrapper: ObservableObject {
    @Published var authManager: AuthManager?
    @Published var isInitialized = false
    
    init() {
        Task {
            await initialize()
        }
    }
    
    private func initialize() async {
        authManager = await AuthManager(configuration: .production)
        isInitialized = true
    }
}
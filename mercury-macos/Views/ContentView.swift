//
//  ContentView.swift
//  Mercury
//
//  Created by Hussam Zaghal on 2025-04-12.
//

import SwiftUI
// AppKit is Apple's native UI framework for macOS development
// It provides desktop-specific components like menu bars, window controls, 
// status bar items and system dialogs that aren't available in SwiftUI alone
import AppKit

struct ContentView: View {
    @EnvironmentObject var authManagerWrapper: AuthManagerWrapper
    @StateObject private var appState = AppState()
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Mercury Core Application")
                .font(.title2)
            
            if authManagerWrapper.isInitialized {
                if let authManager = authManagerWrapper.authManager {
                    VStack(spacing: 8) {
                        Text("Authentication service initialized")
                            .foregroundColor(.green)
                        
                        if appState.isAuthenticated {
                            if let user = appState.currentUser {
                                Text("Connected as @\(user.username)")
                                    .foregroundColor(.blue)
                            } else {
                                Text("Connected to X")
                                    .foregroundColor(.blue)
                            }
                        } else {
                            Text("Not authenticated")
                                .foregroundColor(.orange)
                        }
                        
                        if let error = appState.authenticationError {
                            Text("Error: \(error)")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        // Authentication recovery status (task 4.10)
                        if let persistenceService = WindowManager.shared.persistenceService {
                            Divider()
                                .padding(.vertical, 8)
                            
                            RecoveryStatusView(persistenceService: persistenceService)
                        }
                    }
                    .onAppear {
                        // Configure WindowManager and AppState with AuthManager
                        WindowManager.shared.configure(with: authManager)
                        appState.configure(with: authManager)
                    }
                } else {
                    Text("Authentication service failed to initialize")
                        .foregroundColor(.red)
                }
            } else {
                Text("Initializing authentication service...")
                    .foregroundColor(.orange)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

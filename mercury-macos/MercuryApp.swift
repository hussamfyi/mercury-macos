//
//  MercuryApp.swift
//  Mercury
//
//  Created by Hussam Zaghal on 2025-04-12.
//

import SwiftUI

@main
struct mercuryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .toolbar(.hidden)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .defaultSize(width: 1100, height: 600)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
    }
}
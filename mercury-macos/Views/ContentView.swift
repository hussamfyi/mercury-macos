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

struct HumanEntry: Identifiable {
    
}

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, bitches!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

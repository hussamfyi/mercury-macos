import SwiftUI

// MARK: - Mercury Window Entry Point
struct MercuryWindow: View {
    @StateObject private var windowManager = WindowManager.shared
    
    var body: some View {
        // This view is just a placeholder since the actual window is managed by WindowManager
        // The real window content is in MercuryWindowContent within WindowManager.swift
        Text("Mercury Window")
            .opacity(0) // Hidden - window is managed externally
            .onAppear {
                // Window management is handled by WindowManager
            }
    }
}

struct MercuryWindow_Previews: PreviewProvider {
    static var previews: some View {
        // Preview the actual window content
        MercuryWindowContent()
            .frame(width: 400, height: 160)
            .background(Color.gray.opacity(0.1))
    }
}
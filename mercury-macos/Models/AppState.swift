/*
This file contains the state of the app.
Think of @State as telling SwiftUI: "Watch this value. If it changes, update the UI that uses it."
SwiftUI's state is a property wrapper. It creates a persistent storage location in the app's memory, instead of React where the state is managed in the component.
Also, @State is for simple value types like Int, String, Bool, etc. For more complex data types, we use @StateObject or @ObservedObject.
*/

@State private var entries: [HumanEntry] = []
@State private var text: String = ""
/*
In Swift, you can either explicitly declare it as Bool or let type inference determine it's a Boolean based on the false value. Both approaches are equivalent.
*/
@State private var isFullscreen = false

private let aiChatPrompt = """

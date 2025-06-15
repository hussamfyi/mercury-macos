import SwiftUI

struct TextInputView: View {
    @Binding var text: String
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var textHeight: CGFloat = 40
    
    var isInputDisabled: Bool = false
    var onHeightChange: ((CGFloat) -> Void)?
    var onPostRequested: (() -> Void)?
    var onEscapePressed: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    
    private let placeholderText = "What's on your mind?"
    private let lineHeight: CGFloat = 20
    private let minHeight: CGFloat = 40
    private let maxHeight: CGFloat = 200
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text input field with dynamic height
            ZStack(alignment: .topLeading) {
                // Background text for height measurement
                Text(text.isEmpty ? placeholderText : text)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(nil) // Allow unlimited lines for measurement
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    updateHeight(geometry.size.height)
                                }
                                .onChange(of: text) { _ in
                                    DispatchQueue.main.async {
                                        updateHeight(geometry.size.height)
                                    }
                                }
                        }
                    )
                    .opacity(0) // Hidden but used for measurement
                
                // Actual text field with scrolling when needed
                ScrollView(.vertical, showsIndicators: shouldShowScrollIndicator) {
                    TextField("", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...20) // Allow more lines for scrolling
                        .focused($isTextFieldFocused)
                        .padding(12)
                        .frame(minHeight: max(minHeight, min(maxHeight, textHeight)), alignment: .topLeading)
                        .overlay(
                            // Custom placeholder overlay
                            Group {
                                if text.isEmpty {
                                    HStack {
                                        Text(placeholderText)
                                            .foregroundColor(.secondary)
                                            .font(.body)
                                            .allowsHitTesting(false)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            }
                        )
                }
                .frame(height: max(minHeight, min(maxHeight, textHeight)))
                .background(textFieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    // Scroll fade indicator at bottom when content is scrollable
                    Group {
                        if shouldShowScrollIndicator {
                            VStack {
                                Spacer()
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.clear,
                                        textFieldBackgroundColor.opacity(0.8)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 12)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: isTextFieldFocused ? 1.0 : 0.5)
                )
            }
        }
        .onAppear {
            // Auto-focus when view appears with slight delay for reliability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: isTextFieldFocused) { focused in
            onFocusChange?(focused)
        }
        .onKeyPress(.escape) { pressed in
            if pressed.phase == .down {
                onEscapePressed?()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return, modifiers: .command) { pressed in
            if pressed.phase == .down && !isInputDisabled {
                onPostRequested?()
                return .handled
            } else if pressed.phase == .down && isInputDisabled {
                // Provide audio feedback when disabled
                NSSound.beep()
                return .handled
            }
            return .ignored
        }
    }
    
    private func updateHeight(_ newHeight: CGFloat) {
        let constrainedHeight = max(minHeight, min(maxHeight, newHeight))
        if abs(textHeight - constrainedHeight) > 1 {
            textHeight = constrainedHeight
            onHeightChange?(constrainedHeight)
        }
    }
    
    private var shouldShowScrollIndicator: Bool {
        // Show scroll indicators when text height exceeds max height and text is not empty
        textHeight >= maxHeight && !text.isEmpty
    }
    
    private var textFieldBackground: some ShapeStyle {
        if colorScheme == .dark {
            return Color(.controlBackgroundColor)
        } else {
            return Color(.textBackgroundColor)
        }
    }
    
    private var textFieldBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(.controlBackgroundColor)
        } else {
            return Color(.textBackgroundColor)
        }
    }
    
    private var borderColor: Color {
        if isTextFieldFocused {
            return .accentColor
        } else if colorScheme == .dark {
            return Color.white.opacity(0.1)
        } else {
            return Color.black.opacity(0.1)
        }
    }
}

struct TextInputView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TextInputView(
                text: .constant(""),
                isInputDisabled: false,
                onHeightChange: { height in
                    print("Height changed to: \(height)")
                },
                onPostRequested: {
                    print("Post requested")
                },
                onEscapePressed: {
                    print("Escape pressed")
                },
                onFocusChange: { focused in
                    print("Focus changed to: \(focused)")
                }
            )
            .frame(width: 320)
            
            TextInputView(
                text: .constant("This is some sample text to show how the input field looks with content"),
                isInputDisabled: true,
                onHeightChange: { height in
                    print("Height changed to: \(height)")
                },
                onPostRequested: {
                    print("Post requested")
                },
                onEscapePressed: {
                    print("Escape pressed")
                },
                onFocusChange: { focused in
                    print("Focus changed to: \(focused)")
                }
            )
            .frame(width: 320)
        }
        .padding()
    }
}
// Sources/DesktopCompanion/Views/StreamingTextView.swift
import SwiftUI
import CompanionCore

/// Displays the main response text with fade-out mask for overflow
/// and smooth spring animation on text changes.
struct StreamingTextView: View {
    let text: String
    let isStreaming: Bool
    let mood: Mood

    var body: some View {
        let expr = mood.expression
        let c = expr.color
        let moodColor = Color(red: c.red, green: c.green, blue: c.blue)

        Text(TextCleaner.clean(text))
            .font(.system(.title2, design: .rounded, weight: .medium))
            .foregroundStyle(.white.opacity(isStreaming ? 0.7 : 0.85))
            .multilineTextAlignment(.center)
            .lineLimit(6)
            .padding(.horizontal, 60)
            .animation(FridayAnimation.micro, value: text)
            .mask(
                // Fade out at top and bottom if text is long
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)

                    Color.white

                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 4)
                }
            )
            .shadow(color: moodColor.opacity(0.2), radius: 20, x: 0, y: 0)
    }
}

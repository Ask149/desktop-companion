// Sources/DesktopCompanion/Views/ListeningRingView.swift
import SwiftUI
import CompanionCore

/// Animated ring that appears around the face during voice listening.
/// Rotating dash pattern + opacity pulse.
struct ListeningRingView: View {
    let mood: Mood
    let isListening: Bool

    @State private var rotation: Double = 0

    var body: some View {
        let expr = mood.expression
        let c = expr.color
        let ringColor = Color(red: c.red, green: c.green, blue: c.blue)

        Circle()
            .strokeBorder(
                ringColor,
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: [8, 12]
                )
            )
            .frame(width: 370, height: 370)
            // Rotation runs continuously — no spring animation on this
            .rotationEffect(.degrees(rotation))
            // Opacity and scale respond to isListening with spring
            .opacity(isListening ? 0.5 : 0)
            .scaleEffect(isListening ? 1.0 : 0.95)
            .animation(FridayAnimation.standard, value: isListening)
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

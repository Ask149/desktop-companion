// Sources/DesktopCompanion/Views/ListeningRingView.swift
import SwiftUI
import CompanionCore

/// Animated ring that appears around the face during voice listening.
/// Rotating dash pattern + audio-reactive stroke/opacity/scale + outer ripple.
struct ListeningRingView: View {
    let mood: Mood
    let isListening: Bool
    let audioLevel: Double

    @State private var rotation: Double = 0

    var body: some View {
        let expr = mood.expression
        let c = expr.color
        let ringColor = Color(red: c.red, green: c.green, blue: c.blue)

        ZStack {
            // Outer ripple ring — expands with audio level
            Circle()
                .strokeBorder(
                    ringColor.opacity(0.15),
                    lineWidth: 1
                )
                .frame(width: 390, height: 390)
                .scaleEffect(isListening ? 1.0 + audioLevel * 0.05 : 0.95)
                .opacity(isListening ? audioLevel * 0.6 : 0)
                .animation(FridayAnimation.micro, value: audioLevel)
                .animation(FridayAnimation.standard, value: isListening)

            // Main listening ring — audio-reactive
            Circle()
                .strokeBorder(
                    ringColor,
                    style: StrokeStyle(
                        lineWidth: 1.5 + audioLevel * 2.5,
                        lineCap: .round,
                        dash: [8, 12]
                    )
                )
                .frame(width: 370, height: 370)
                // Rotation runs continuously — no spring animation on this
                .rotationEffect(.degrees(rotation))
                // Audio-reactive opacity and scale
                .opacity(isListening ? 0.3 + audioLevel * 0.4 : 0)
                .scaleEffect(isListening ? 1.0 + audioLevel * 0.02 : 0.95)
                .animation(FridayAnimation.micro, value: audioLevel)
                .animation(FridayAnimation.standard, value: isListening)
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

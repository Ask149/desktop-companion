// Sources/DesktopCompanion/Views/FaceView.swift
import SwiftUI
import CompanionCore

/// Animated geometric face view using TimelineView + Canvas.
/// Renders at 30fps with smooth mood transitions and speaking glow pulse.
struct FaceView: View {
    let mood: Mood
    let mouthOpenness: Double
    let blinkAmount: Double
    let isSpeaking: Bool

    init(mood: Mood, mouthOpenness: Double, blinkAmount: Double, isSpeaking: Bool = false) {
        self.mood = mood
        self.mouthOpenness = mouthOpenness
        self.blinkAmount = blinkAmount
        self.isSpeaking = isSpeaking
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let phase = seconds.truncatingRemainder(dividingBy: .pi * 4)

                let params = FaceRenderer.RenderParams(
                    mood: mood,
                    blinkAmount: blinkAmount,
                    mouthOpenness: mouthOpenness,
                    animationPhase: phase,
                    size: size
                )
                FaceRenderer.draw(in: context, params: params)
            }
        }
        .frame(width: 340, height: 340)
    }
}

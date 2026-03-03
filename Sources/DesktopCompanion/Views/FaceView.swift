// Sources/DesktopCompanion/Views/FaceView.swift
import SwiftUI
import CompanionCore

/// Animated geometric face view using TimelineView + Canvas.
/// Renders at 60fps with smooth mood transitions.
struct FaceView: View {
    let mood: Mood
    let mouthOpenness: Double
    let blinkAmount: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // Derive phase from timeline date for continuous animation
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
        .frame(width: 300, height: 300)
    }
}

// Sources/DesktopCompanion/Views/BackgroundView.swift
import SwiftUI
import CompanionCore

/// Ambient background for the overlay — subtle radial gradient + drifting particles.
/// Particle positions are derived purely from time (no @State mutation in Canvas).
struct BackgroundView: View {
    let mood: Mood

    /// Particle seeds — immutable after creation. Positions derived from time.
    @State private var particles: [ParticleSeed] = BackgroundView.generateSeeds()
    /// Captured once to serve as t=0 for time-based derivation.
    @State private var startTime: TimeInterval = Date.timeIntervalSinceReferenceDate

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                // --- Radial gradient background ---
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxDim = max(size.width, size.height)

                let outerRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                context.fill(Path(outerRect), with: .color(.black))

                // Mood-tinted radial glow at edges
                let glowRadius = maxDim * 0.8
                let glowRect = CGRect(
                    x: center.x - glowRadius, y: center.y - glowRadius,
                    width: glowRadius * 2, height: glowRadius * 2
                )
                let expr = mood.expression
                let c = expr.color
                let edgeColor = Color(red: c.red, green: c.green, blue: c.blue).opacity(0.04)
                context.fill(Path(ellipseIn: glowRect), with: .color(edgeColor))

                // --- Particles (pure function of time, no state mutation) ---
                let elapsed = timeline.date.timeIntervalSinceReferenceDate - startTime
                let seconds = timeline.date.timeIntervalSinceReferenceDate

                for seed in particles {
                    let pos = seed.position(at: elapsed, seconds: seconds, size: size)

                    let particleColor = Color(red: c.red, green: c.green, blue: c.blue)
                        .opacity(seed.opacity)
                    let rect = CGRect(
                        x: pos.x - seed.size / 2,
                        y: pos.y - seed.size / 2,
                        width: seed.size,
                        height: seed.size
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(particleColor))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Particle Seed (immutable)

    /// Immutable seed data for a particle. Position is derived from time, not mutated.
    struct ParticleSeed {
        let startNormX: Double   // 0...1 normalized initial X
        let startNormY: Double   // 0...1 normalized initial Y
        let size: Double         // 1-3 pts
        let opacity: Double      // 0.08-0.15
        let speed: Double        // pts per second drift upward
        let wobbleFreq: Double   // horizontal wobble frequency
        let wobblePhase: Double  // horizontal wobble phase offset

        /// Derive position purely from elapsed time and canvas size.
        func position(at elapsed: Double, seconds: Double, size: CGSize) -> CGPoint {
            let w = size.width
            let h = size.height

            // Vertical: drift upward, wrap using modulo
            let totalDrift = speed * elapsed
            // Start from normalized position, wrap within [0, h + 20] range
            let rawY = startNormY * h - totalDrift
            let wrapRange = h + 20
            let y = rawY.truncatingRemainder(dividingBy: wrapRange)
            let wrappedY = y < -10 ? y + wrapRange : y

            // Horizontal: wobble via sine, no cumulative drift
            let x = startNormX * w + sin(seconds * wobbleFreq + wobblePhase) * 20

            return CGPoint(x: x, y: wrappedY)
        }
    }

    static func generateSeeds(count: Int = 18) -> [ParticleSeed] {
        (0..<count).map { _ in
            ParticleSeed(
                startNormX: Double.random(in: 0...1),
                startNormY: Double.random(in: 0...1),
                size: Double.random(in: 1.0...3.0),
                opacity: Double.random(in: 0.08...0.15),
                speed: Double.random(in: 8...25),
                wobbleFreq: Double.random(in: 0.3...1.2),
                wobblePhase: Double.random(in: 0...(.pi * 2))
            )
        }
    }
}

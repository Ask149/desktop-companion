// Sources/CompanionCore/Rendering/FaceRenderer.swift
import SwiftUI

/// Draws Friday's geometric face in a SwiftUI Canvas.
/// Supports mood-based expressions, blink animation, and mouth sync for speech.
public struct FaceRenderer: Sendable {

    /// Parameters for rendering a single frame of the face.
    public struct RenderParams: Sendable {
        public let mood: Mood
        public let blinkAmount: Double      // 0 (open) to 1 (closed)
        public let mouthOpenness: Double    // 0 (closed) to 1 (fully open) — for speech
        public let animationPhase: Double   // 0 to 2π — drives idle animations
        public let size: CGSize             // canvas size

        public init(mood: Mood, blinkAmount: Double = 0, mouthOpenness: Double = 0,
                    animationPhase: Double = 0, size: CGSize = CGSize(width: 300, height: 300)) {
            self.mood = mood
            self.blinkAmount = blinkAmount
            self.mouthOpenness = mouthOpenness
            self.animationPhase = animationPhase
            self.size = size
        }
    }

    /// Draw the face into a GraphicsContext.
    public static func draw(in context: GraphicsContext, params: RenderParams) {
        let expr = params.mood.expression
        let c = expr.color
        let color = Color(red: c.red, green: c.green, blue: c.blue)
        let center = CGPoint(x: params.size.width / 2, y: params.size.height / 2)
        let faceWidth: CGFloat = min(params.size.width, params.size.height) * 0.85

        // Apply idle animation transform
        var context = context
        applyIdleAnimation(&context, animation: expr.idleAnimation,
                           phase: params.animationPhase, center: center)

        // --- Multi-layer bloom glow ---
        let glowBase = faceWidth * 0.6 * expr.glowIntensity
        if glowBase > 0 {
            // Layer 1: Wide, faint outer glow
            let outerRadius = glowBase * 1.8
            let outerRect = CGRect(
                x: center.x - outerRadius, y: center.y - outerRadius,
                width: outerRadius * 2, height: outerRadius * 2
            )
            context.fill(
                Path(ellipseIn: outerRect),
                with: .color(color.opacity(0.04 * expr.glowIntensity))
            )

            // Layer 2: Medium, softer middle glow
            let midRadius = glowBase * 1.2
            let midRect = CGRect(
                x: center.x - midRadius, y: center.y - midRadius,
                width: midRadius * 2, height: midRadius * 2
            )
            context.fill(
                Path(ellipseIn: midRect),
                with: .color(color.opacity(0.08 * expr.glowIntensity))
            )

            // Layer 3: Tight, bright inner glow
            let innerRadius = glowBase * 0.7
            let innerRect = CGRect(
                x: center.x - innerRadius, y: center.y - innerRadius,
                width: innerRadius * 2, height: innerRadius * 2
            )
            context.fill(
                Path(ellipseIn: innerRect),
                with: .color(color.opacity(0.15 * expr.glowIntensity))
            )
        }

        // --- Face outline ---
        let faceRect = CGRect(
            x: center.x - faceWidth / 2,
            y: center.y - faceWidth / 2,
            width: faceWidth,
            height: faceWidth
        )
        let facePath = RoundedRectangle(cornerRadius: faceWidth * 0.25)
            .path(in: faceRect)

        context.stroke(facePath, with: .color(color.opacity(0.6)), lineWidth: 2.0)
        // Subtle face fill for depth
        context.fill(facePath, with: .color(color.opacity(0.04)))

        // --- Eyes ---
        let eyeY = center.y - faceWidth * 0.12
        let eyeSpacing = faceWidth * 0.22
        let eyeSize = faceWidth * 0.13

        drawEyes(in: &context, shape: expr.eyeShape, color: color,
                 leftCenter: CGPoint(x: center.x - eyeSpacing, y: eyeY),
                 rightCenter: CGPoint(x: center.x + eyeSpacing, y: eyeY),
                 size: eyeSize, blink: params.blinkAmount)

        // --- Mouth ---
        let mouthY = center.y + faceWidth * 0.18
        let mouthWidth = faceWidth * 0.28
        drawMouth(in: &context, shape: expr.mouthShape, color: color,
                  center: CGPoint(x: center.x, y: mouthY),
                  width: mouthWidth, openness: params.mouthOpenness)
    }

    // MARK: - Eyes

    private static func drawEyes(in context: inout GraphicsContext,
                                  shape: MoodExpression.EyeShape, color: Color,
                                  leftCenter: CGPoint, rightCenter: CGPoint,
                                  size: CGFloat, blink: Double) {
        // If blinking, draw closed eyes regardless of shape
        if blink > 0.5 {
            for center in [leftCenter, rightCenter] {
                let path = Path { p in
                    p.move(to: CGPoint(x: center.x - size, y: center.y))
                    p.addLine(to: CGPoint(x: center.x + size, y: center.y))
                }
                context.stroke(path, with: .color(color), lineWidth: 2.5)
            }
            return
        }

        switch shape {
        case .halfClosedOvals:
            for center in [leftCenter, rightCenter] {
                let rect = CGRect(x: center.x - size, y: center.y - size * 0.5,
                                  width: size * 2, height: size)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }

        case .wideCircles:
            for center in [leftCenter, rightCenter] {
                let rect = CGRect(x: center.x - size, y: center.y - size,
                                  width: size * 2, height: size * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }

        case .asymmetric:
            // Left eye higher
            let leftRect = CGRect(x: leftCenter.x - size, y: leftCenter.y - size * 1.2,
                                  width: size * 2, height: size * 1.8)
            context.fill(Path(ellipseIn: leftRect), with: .color(color))
            let rightRect = CGRect(x: rightCenter.x - size, y: rightCenter.y - size * 0.6,
                                   width: size * 2, height: size * 1.2)
            context.fill(Path(ellipseIn: rightRect), with: .color(color))

        case .narrowedRectangles:
            for center in [leftCenter, rightCenter] {
                let rect = CGRect(x: center.x - size * 1.1, y: center.y - size * 0.3,
                                  width: size * 2.2, height: size * 0.6)
                let path = RoundedRectangle(cornerRadius: size * 0.15).path(in: rect)
                context.fill(path, with: .color(color))
            }

        case .angledDown:
            for (center, flipX) in [(leftCenter, false), (rightCenter, true)] {
                let path = Path { p in
                    let offset: CGFloat = flipX ? -size * 0.3 : size * 0.3
                    p.move(to: CGPoint(x: center.x - size, y: center.y - offset))
                    p.addLine(to: CGPoint(x: center.x + size, y: center.y + offset))
                    p.addLine(to: CGPoint(x: center.x + size, y: center.y + offset + size * 0.6))
                    p.addLine(to: CGPoint(x: center.x - size, y: center.y - offset + size * 0.6))
                    p.closeSubpath()
                }
                context.fill(path, with: .color(color))
            }

        case .wideOpen:
            for center in [leftCenter, rightCenter] {
                let rect = CGRect(x: center.x - size * 1.2, y: center.y - size * 1.2,
                                  width: size * 2.4, height: size * 2.4)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }

        case .droopingHalfMoons:
            for center in [leftCenter, rightCenter] {
                let path = Path { p in
                    p.addArc(center: CGPoint(x: center.x, y: center.y - size * 0.3),
                             radius: size,
                             startAngle: .degrees(20), endAngle: .degrees(160),
                             clockwise: false)
                }
                context.stroke(path, with: .color(color), lineWidth: 2.5)
            }

        case .winking:
            // Left eye: open circle
            let leftRect = CGRect(x: leftCenter.x - size, y: leftCenter.y - size,
                                  width: size * 2, height: size * 2)
            context.fill(Path(ellipseIn: leftRect), with: .color(color))
            // Right eye: closed line
            let rightPath = Path { p in
                p.move(to: CGPoint(x: rightCenter.x - size, y: rightCenter.y))
                p.addLine(to: CGPoint(x: rightCenter.x + size, y: rightCenter.y))
            }
            context.stroke(rightPath, with: .color(color), lineWidth: 2.5)
        }


    }

    // MARK: - Mouth

    private static func drawMouth(in context: inout GraphicsContext,
                                   shape: MoodExpression.MouthShape, color: Color,
                                   center: CGPoint, width: CGFloat, openness: Double) {
        // If speaking, override shape with open mouth proportional to openness
        if openness > 0.1 {
            let h = width * 0.5 * openness
            let rect = CGRect(x: center.x - width * 0.4, y: center.y - h / 2,
                              width: width * 0.8, height: h)
            let path = Path(ellipseIn: rect)
            context.stroke(path, with: .color(color), lineWidth: 2)
            return
        }

        switch shape {
        case .gentleSmile:
            let path = Path { p in
                p.move(to: CGPoint(x: center.x - width / 2, y: center.y))
                p.addQuadCurve(to: CGPoint(x: center.x + width / 2, y: center.y),
                               control: CGPoint(x: center.x, y: center.y + width * 0.3))
            }
            context.stroke(path, with: .color(color), lineWidth: 2)

        case .bigSmile:
            let path = Path { p in
                p.move(to: CGPoint(x: center.x - width * 0.6, y: center.y - width * 0.1))
                p.addQuadCurve(to: CGPoint(x: center.x + width * 0.6, y: center.y - width * 0.1),
                               control: CGPoint(x: center.x, y: center.y + width * 0.5))
            }
            context.stroke(path, with: .color(color), lineWidth: 2.5)

        case .slightO:
            let rect = CGRect(x: center.x - width * 0.15, y: center.y - width * 0.15,
                              width: width * 0.3, height: width * 0.3)
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)

        case .neutralLine:
            let path = Path { p in
                p.move(to: CGPoint(x: center.x - width * 0.3, y: center.y))
                p.addLine(to: CGPoint(x: center.x + width * 0.3, y: center.y))
            }
            context.stroke(path, with: .color(color), lineWidth: 2)

        case .slightFrown:
            let path = Path { p in
                p.move(to: CGPoint(x: center.x - width / 2, y: center.y))
                p.addQuadCurve(to: CGPoint(x: center.x + width / 2, y: center.y),
                               control: CGPoint(x: center.x, y: center.y - width * 0.2))
            }
            context.stroke(path, with: .color(color), lineWidth: 2)

        case .openOval:
            let rect = CGRect(x: center.x - width * 0.3, y: center.y - width * 0.2,
                              width: width * 0.6, height: width * 0.4)
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)

        case .smirk:
            let path = Path { p in
                p.move(to: CGPoint(x: center.x - width * 0.3, y: center.y + width * 0.05))
                p.addQuadCurve(to: CGPoint(x: center.x + width * 0.4, y: center.y - width * 0.15),
                               control: CGPoint(x: center.x + width * 0.1, y: center.y + width * 0.25))
            }
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
    }

    // MARK: - Idle Animations

    private static func applyIdleAnimation(_ context: inout GraphicsContext,
                                            animation: MoodExpression.IdleAnimation,
                                            phase: Double, center: CGPoint) {
        switch animation {
        case .breathingPulse:
            let scale = 1.0 + sin(phase) * 0.02 // ±2% scale
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -center.x, y: -center.y)

        case .gentleBounce:
            let offset = sin(phase) * 3 // ±3pt vertical
            context.translateBy(x: 0, y: offset)

        case .headTilt:
            let angle = sin(phase) * 0.03 // ±~2 degrees
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: Angle(radians: angle))
            context.translateBy(x: -center.x, y: -center.y)

        case .none:
            break

        case .subtleShake:
            let offset = sin(phase * 3) * 2 // faster horizontal jitter
            context.translateBy(x: offset, y: 0)

        case .rapidPulse:
            // Handled by glow intensity modulation in the draw call
            break

        case .slowDrift:
            let offset = sin(phase * 0.5) * 5 // slow vertical drift
            context.translateBy(x: 0, y: offset)

        case .wiggle:
            let angle = sin(phase * 2) * 0.05 // ±~3 degrees, faster
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: Angle(radians: angle))
            context.translateBy(x: -center.x, y: -center.y)
        }
    }
}

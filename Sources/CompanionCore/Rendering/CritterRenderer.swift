// Sources/CompanionCore/Rendering/CritterRenderer.swift
import AppKit
import CoreGraphics

/// Draws the companion critter icon for the menu bar.
/// Inspired by OpenClaw's CritterStatusLabel — programmatic Core Graphics drawing.
public struct CritterRenderer: Sendable {

    /// Create a menu bar icon for the given state.
    /// - Parameters:
    ///   - mode: Current companion mode (idle, thinking, alert, sleeping, dead)
    ///   - blink: Blink amount 0 (eyes open) to 1 (eyes closed)
    ///   - wiggle: Rotation amount -1 to 1
    /// - Returns: NSImage sized for menu bar (22x22 points)
    @MainActor
    public static func makeIcon(mode: CompanionMode, blink: CGFloat, wiggle: CGFloat) -> NSImage {
        let size = CGSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Apply wiggle rotation around center
            if wiggle != 0 {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: wiggle * 0.15) // Max ~8.5 degrees
                ctx.translateBy(x: -center.x, y: -center.y)
            }

            // Colors based on mode
            let bodyColor: NSColor
            let eyeColor: NSColor
            switch mode {
            case .idle:     bodyColor = .white;           eyeColor = .black
            case .thinking: bodyColor = .white;           eyeColor = .systemBlue
            case .alert:    bodyColor = .systemOrange;    eyeColor = .black
            case .sleeping: bodyColor = .systemGray;      eyeColor = .darkGray
            case .dead:     bodyColor = .systemRed;       eyeColor = .black
            }

            // --- Draw body (rounded rectangle) ---
            let bodyRect = CGRect(x: 3, y: 2, width: 16, height: 18)
            let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.setFillColor(bodyColor.cgColor)
            ctx.addPath(bodyPath)
            ctx.fillPath()

            // Outline
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setLineWidth(1.2)
            ctx.addPath(bodyPath)
            ctx.strokePath()

            // --- Draw eyes based on mode ---
            let eyeY: CGFloat = 12
            let leftEyeX: CGFloat = 7.5
            let rightEyeX: CGFloat = 14.5

            ctx.setFillColor(eyeColor.cgColor)

            switch mode {
            case .idle, .thinking:
                if blink > 0.5 {
                    // Eyes closed — horizontal lines
                    ctx.setStrokeColor(eyeColor.cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.move(to: CGPoint(x: leftEyeX - 1.5, y: eyeY))
                    ctx.addLine(to: CGPoint(x: leftEyeX + 1.5, y: eyeY))
                    ctx.move(to: CGPoint(x: rightEyeX - 1.5, y: eyeY))
                    ctx.addLine(to: CGPoint(x: rightEyeX + 1.5, y: eyeY))
                    ctx.strokePath()
                } else {
                    // Eyes open — dots
                    ctx.fillEllipse(in: CGRect(x: leftEyeX - 1.5, y: eyeY - 1.5, width: 3, height: 3))
                    ctx.fillEllipse(in: CGRect(x: rightEyeX - 1.5, y: eyeY - 1.5, width: 3, height: 3))
                }

            case .alert:
                // Exclamation marks for eyes
                ctx.setStrokeColor(eyeColor.cgColor)
                ctx.setLineWidth(1.5)
                // Left !
                ctx.move(to: CGPoint(x: leftEyeX, y: eyeY + 2.5))
                ctx.addLine(to: CGPoint(x: leftEyeX, y: eyeY - 0.5))
                ctx.strokePath()
                ctx.fillEllipse(in: CGRect(x: leftEyeX - 0.5, y: eyeY - 2.5, width: 1, height: 1))
                // Right !
                ctx.move(to: CGPoint(x: rightEyeX, y: eyeY + 2.5))
                ctx.addLine(to: CGPoint(x: rightEyeX, y: eyeY - 0.5))
                ctx.strokePath()
                ctx.fillEllipse(in: CGRect(x: rightEyeX - 0.5, y: eyeY - 2.5, width: 1, height: 1))

            case .sleeping:
                // Horizontal lines (closed eyes)
                ctx.setStrokeColor(eyeColor.cgColor)
                ctx.setLineWidth(1.5)
                ctx.move(to: CGPoint(x: leftEyeX - 1.5, y: eyeY))
                ctx.addLine(to: CGPoint(x: leftEyeX + 1.5, y: eyeY))
                ctx.move(to: CGPoint(x: rightEyeX - 1.5, y: eyeY))
                ctx.addLine(to: CGPoint(x: rightEyeX + 1.5, y: eyeY))
                ctx.strokePath()

            case .dead:
                // X eyes
                ctx.setStrokeColor(eyeColor.cgColor)
                ctx.setLineWidth(1.2)
                let xs: CGFloat = 1.5
                for ex in [leftEyeX, rightEyeX] {
                    ctx.move(to: CGPoint(x: ex - xs, y: eyeY - xs))
                    ctx.addLine(to: CGPoint(x: ex + xs, y: eyeY + xs))
                    ctx.move(to: CGPoint(x: ex + xs, y: eyeY - xs))
                    ctx.addLine(to: CGPoint(x: ex - xs, y: eyeY + xs))
                }
                ctx.strokePath()
            }

            // --- Draw mouth ---
            let mouthY: CGFloat = 7
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setLineWidth(1.0)

            switch mode {
            case .idle:
                // Slight smile
                ctx.move(to: CGPoint(x: 8, y: mouthY))
                ctx.addQuadCurve(to: CGPoint(x: 14, y: mouthY), control: CGPoint(x: 11, y: mouthY - 2))
                ctx.strokePath()
            case .thinking:
                // Three dots
                for dx: CGFloat in [0, 3, 6] {
                    ctx.fillEllipse(in: CGRect(x: 8 + dx, y: mouthY - 0.5, width: 1, height: 1))
                }
            case .alert:
                // Open mouth (surprise)
                ctx.strokeEllipse(in: CGRect(x: 9.5, y: mouthY - 2, width: 3, height: 3))
            case .sleeping:
                // Wavy line
                ctx.move(to: CGPoint(x: 8, y: mouthY))
                ctx.addCurve(to: CGPoint(x: 14, y: mouthY),
                            control1: CGPoint(x: 9.5, y: mouthY + 1.5),
                            control2: CGPoint(x: 12.5, y: mouthY - 1.5))
                ctx.strokePath()
            case .dead:
                // Flat line
                ctx.move(to: CGPoint(x: 8, y: mouthY))
                ctx.addLine(to: CGPoint(x: 14, y: mouthY))
                ctx.strokePath()
            }

            return true
        }

        image.isTemplate = false // Full color, not template
        return image
    }
}

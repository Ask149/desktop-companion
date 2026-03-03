// Sources/CompanionCore/Rendering/CritterRenderer.swift
import AppKit
import CoreGraphics

/// Draws the companion critter icon for the menu bar.
/// Uses bold, simplified features that remain legible at 22x22 points.
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
                ctx.rotate(by: wiggle * 0.12) // Max ~7 degrees
                ctx.translateBy(x: -center.x, y: -center.y)
            }

            // --- Body: rounded square filling most of the space ---
            let bodyRect = CGRect(x: 2, y: 1, width: 18, height: 20)
            let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 6, cornerHeight: 6, transform: nil)

            // Fill color based on mode
            let bodyColor: NSColor
            switch mode {
            case .idle:     bodyColor = .white
            case .thinking: bodyColor = NSColor(calibratedRed: 0.85, green: 0.92, blue: 1.0, alpha: 1.0) // light blue tint
            case .alert:    bodyColor = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.8, alpha: 1.0) // warm amber tint
            case .sleeping: bodyColor = NSColor(calibratedWhite: 0.82, alpha: 1.0)
            case .dead:     bodyColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
            }

            ctx.setFillColor(bodyColor.cgColor)
            ctx.addPath(bodyPath)
            ctx.fillPath()

            // Border — use label color for dark/light mode adaptivity
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setLineWidth(1.4)
            ctx.addPath(bodyPath)
            ctx.strokePath()

            // --- Eyes: positioned in upper third, large enough to see expressions ---
            let eyeY: CGFloat = 13.5
            let leftEyeX: CGFloat = 7
            let rightEyeX: CGFloat = 15
            let eyeRadius: CGFloat = 2.2

            let eyeColor: NSColor
            switch mode {
            case .idle:     eyeColor = .black
            case .thinking: eyeColor = .systemBlue
            case .alert:    eyeColor = NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.0, alpha: 1.0) // dark orange
            case .sleeping: eyeColor = NSColor(calibratedWhite: 0.4, alpha: 1.0)
            case .dead:     eyeColor = .black
            }

            switch mode {
            case .idle, .thinking:
                if blink > 0.5 {
                    // Eyes closed — bold horizontal lines
                    ctx.setStrokeColor(eyeColor.cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.move(to: CGPoint(x: leftEyeX - eyeRadius, y: eyeY))
                    ctx.addLine(to: CGPoint(x: leftEyeX + eyeRadius, y: eyeY))
                    ctx.move(to: CGPoint(x: rightEyeX - eyeRadius, y: eyeY))
                    ctx.addLine(to: CGPoint(x: rightEyeX + eyeRadius, y: eyeY))
                    ctx.strokePath()
                } else {
                    // Eyes open — solid circles
                    ctx.setFillColor(eyeColor.cgColor)
                    ctx.fillEllipse(in: CGRect(x: leftEyeX - eyeRadius, y: eyeY - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
                    ctx.fillEllipse(in: CGRect(x: rightEyeX - eyeRadius, y: eyeY - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
                }

            case .alert:
                // Wide open eyes (larger circles) — surprised look
                ctx.setFillColor(eyeColor.cgColor)
                let wideR: CGFloat = 2.5
                ctx.fillEllipse(in: CGRect(x: leftEyeX - wideR, y: eyeY - wideR, width: wideR * 2, height: wideR * 2))
                ctx.fillEllipse(in: CGRect(x: rightEyeX - wideR, y: eyeY - wideR, width: wideR * 2, height: wideR * 2))

            case .sleeping:
                // Arc-shaped closed eyes (curved lines)
                ctx.setStrokeColor(eyeColor.cgColor)
                ctx.setLineWidth(1.8)
                // Left eye — downward arc
                ctx.move(to: CGPoint(x: leftEyeX - eyeRadius, y: eyeY + 0.5))
                ctx.addQuadCurve(to: CGPoint(x: leftEyeX + eyeRadius, y: eyeY + 0.5),
                                control: CGPoint(x: leftEyeX, y: eyeY - 1.5))
                // Right eye — downward arc
                ctx.move(to: CGPoint(x: rightEyeX - eyeRadius, y: eyeY + 0.5))
                ctx.addQuadCurve(to: CGPoint(x: rightEyeX + eyeRadius, y: eyeY + 0.5),
                                control: CGPoint(x: rightEyeX, y: eyeY - 1.5))
                ctx.strokePath()

            case .dead:
                // Bold X eyes
                ctx.setStrokeColor(eyeColor.cgColor)
                ctx.setLineWidth(2.0)
                let xs: CGFloat = 2.0
                for ex in [leftEyeX, rightEyeX] {
                    ctx.move(to: CGPoint(x: ex - xs, y: eyeY - xs))
                    ctx.addLine(to: CGPoint(x: ex + xs, y: eyeY + xs))
                    ctx.move(to: CGPoint(x: ex + xs, y: eyeY - xs))
                    ctx.addLine(to: CGPoint(x: ex - xs, y: eyeY + xs))
                }
                ctx.strokePath()
            }

            // --- Mouth: positioned lower, bold enough to see ---
            let mouthY: CGFloat = 6.5
            let mouthColor: NSColor
            switch mode {
            case .idle, .thinking: mouthColor = .labelColor
            case .alert: mouthColor = NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.0, alpha: 1.0)
            case .sleeping, .dead: mouthColor = NSColor(calibratedWhite: 0.4, alpha: 1.0)
            }
            ctx.setStrokeColor(mouthColor.cgColor)
            ctx.setLineWidth(1.4)

            switch mode {
            case .idle:
                // Smile — wide arc
                ctx.move(to: CGPoint(x: 7, y: mouthY + 0.5))
                ctx.addQuadCurve(to: CGPoint(x: 15, y: mouthY + 0.5),
                                control: CGPoint(x: 11, y: mouthY - 2.5))
                ctx.strokePath()

            case .thinking:
                // Small open mouth — "o" shape
                ctx.strokeEllipse(in: CGRect(x: 9.5, y: mouthY - 1.5, width: 3, height: 3))

            case .alert:
                // Open wide mouth — bigger "O"
                ctx.strokeEllipse(in: CGRect(x: 8.5, y: mouthY - 2, width: 5, height: 4))

            case .sleeping:
                // Slight frown, relaxed
                ctx.move(to: CGPoint(x: 8, y: mouthY))
                ctx.addQuadCurve(to: CGPoint(x: 14, y: mouthY),
                                control: CGPoint(x: 11, y: mouthY + 1))
                ctx.strokePath()

            case .dead:
                // Flat line
                ctx.setLineWidth(1.8)
                ctx.move(to: CGPoint(x: 7, y: mouthY))
                ctx.addLine(to: CGPoint(x: 15, y: mouthY))
                ctx.strokePath()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    /// Create a menu bar icon tinted by the current mood color.
    @MainActor
    public static func makeIcon(mode: CompanionMode, mood: Mood, blink: CGFloat, wiggle: CGFloat) -> NSImage {
        let baseIcon = makeIcon(mode: mode, blink: blink, wiggle: wiggle)
        let moodColor = mood.expression.color

        // Create a tinted version
        let size = baseIcon.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            baseIcon.draw(in: rect)

            // Overlay mood color at low opacity
            let color = NSColor(
                calibratedRed: moodColor.red,
                green: moodColor.green,
                blue: moodColor.blue,
                alpha: 0.25
            )
            color.setFill()
            rect.fill(using: .sourceAtop)

            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}

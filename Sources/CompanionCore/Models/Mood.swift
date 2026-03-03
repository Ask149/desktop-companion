// Sources/CompanionCore/Models/Mood.swift
import Foundation

/// The 8 mood states Friday can express.
public enum Mood: String, Sendable, CaseIterable {
    case calm
    case happy
    case curious
    case focused
    case concerned
    case alert
    case sleepy
    case playful
}

/// Visual expression data for rendering a mood.
public struct MoodExpression: Sendable {
    public let eyeShape: EyeShape
    public let mouthShape: MouthShape
    public let color: MoodColor
    public let glowIntensity: Double // 0.0 – 1.0
    public let idleAnimation: IdleAnimation

    public enum EyeShape: Sendable {
        case halfClosedOvals
        case wideCircles
        case asymmetric        // one eye higher than the other
        case narrowedRectangles
        case angledDown        // inner corners tilted down
        case wideOpen
        case droopingHalfMoons
        case winking           // left open, right closed
    }

    public enum MouthShape: Sendable {
        case gentleSmile
        case bigSmile
        case slightO
        case neutralLine
        case slightFrown
        case openOval
        case smirk             // asymmetric upward curve
    }

    public enum IdleAnimation: Sendable {
        case breathingPulse    // slow 3s scale cycle
        case gentleBounce      // vertical oscillation
        case headTilt          // slight rotation
        case none              // perfectly still
        case subtleShake       // horizontal jitter
        case rapidPulse        // fast glow pulse
        case slowDrift         // downward drift
        case wiggle            // playful rotation
    }

    /// RGBA color for mood elements.
    public struct MoodColor: Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public static let softBlue    = MoodColor(red: 0.29, green: 0.62, blue: 1.0)
        public static let teal        = MoodColor(red: 0.20, green: 0.83, blue: 0.60)
        public static let purple      = MoodColor(red: 0.65, green: 0.55, blue: 0.98)
        public static let white       = MoodColor(red: 0.90, green: 0.91, blue: 0.93)
        public static let amber       = MoodColor(red: 0.98, green: 0.75, blue: 0.14)
        public static let redOrange   = MoodColor(red: 0.97, green: 0.51, blue: 0.44)
        public static let dimGray     = MoodColor(red: 0.42, green: 0.45, blue: 0.50)
        public static let brightTeal  = MoodColor(red: 0.18, green: 0.83, blue: 0.75)
    }
}

extension Mood {
    /// The visual expression mapping for this mood.
    public var expression: MoodExpression {
        switch self {
        case .calm:
            MoodExpression(eyeShape: .halfClosedOvals, mouthShape: .gentleSmile,
                           color: .softBlue, glowIntensity: 0.3, idleAnimation: .breathingPulse)
        case .happy:
            MoodExpression(eyeShape: .wideCircles, mouthShape: .bigSmile,
                           color: .teal, glowIntensity: 0.5, idleAnimation: .gentleBounce)
        case .curious:
            MoodExpression(eyeShape: .asymmetric, mouthShape: .slightO,
                           color: .purple, glowIntensity: 0.5, idleAnimation: .headTilt)
        case .focused:
            MoodExpression(eyeShape: .narrowedRectangles, mouthShape: .neutralLine,
                           color: .white, glowIntensity: 0.7, idleAnimation: .none)
        case .concerned:
            MoodExpression(eyeShape: .angledDown, mouthShape: .slightFrown,
                           color: .amber, glowIntensity: 0.5, idleAnimation: .subtleShake)
        case .alert:
            MoodExpression(eyeShape: .wideOpen, mouthShape: .openOval,
                           color: .redOrange, glowIntensity: 0.8, idleAnimation: .rapidPulse)
        case .sleepy:
            MoodExpression(eyeShape: .droopingHalfMoons, mouthShape: .gentleSmile,
                           color: .dimGray, glowIntensity: 0.15, idleAnimation: .slowDrift)
        case .playful:
            MoodExpression(eyeShape: .winking, mouthShape: .smirk,
                           color: .brightTeal, glowIntensity: 0.5, idleAnimation: .wiggle)
        }
    }
}

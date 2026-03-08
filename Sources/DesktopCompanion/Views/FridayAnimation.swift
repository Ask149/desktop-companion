// Sources/DesktopCompanion/Views/FridayAnimation.swift
import SwiftUI

/// Unified animation timing for all Friday UI.
/// Four tiers, all springs, nothing exceeds 0.6s.
enum FridayAnimation {
    /// Token fade-in, dot bounces, opacity flickers (0.2s, no bounce)
    static let micro = Animation.spring(duration: 0.2, bounce: 0.0)
    /// Message entrance, bubble resize, ring appear/disappear (0.35s, slight bounce)
    static let standard = Animation.spring(duration: 0.35, bounce: 0.15)
    /// Mood color transitions, glow shifts, background gradient (0.6s, subtle bounce)
    static let mood = Animation.spring(duration: 0.6, bounce: 0.1)
    /// Overlay show/dismiss scale + fade (0.3s, slight bounce)
    static let overlay = Animation.spring(duration: 0.3, bounce: 0.12)
}

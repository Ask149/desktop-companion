// Sources/CompanionCore/Services/MoodEngine.swift
import Foundation

/// Derives Friday's mood from system state + conversation state.
/// Pure deterministic — no LLM calls. Fast and predictable.
@MainActor
public final class MoodEngine {
    public private(set) var currentMood: Mood = .calm
    public private(set) var moodReason: String = "Starting up"

    private let heartbeat: HeartbeatMonitor

    /// Active hours range (used for sleepy mood detection).
    public let activeHoursStart: Int
    public let activeHoursEnd: Int

    public init(client: AidaemonClient?, heartbeat: HeartbeatMonitor, activeHoursStart: Int = 8, activeHoursEnd: Int = 22) {
        self.heartbeat = heartbeat
        self.activeHoursStart = activeHoursStart
        self.activeHoursEnd = activeHoursEnd
    }

    /// Refresh mood from system state + conversation state.
    public func refresh(aidaemonHealthy: Bool, isOverlayActive: Bool,
                        isChatting: Bool = false, isListening: Bool = false) {
        let systemMood = deriveSystemMood(aidaemonHealthy: aidaemonHealthy)

        if isOverlayActive, let convMood = deriveConversationMood(isChatting: isChatting, isListening: isListening) {
            if systemMood == .alert || systemMood == .sleepy {
                currentMood = systemMood
                moodReason = systemMoodReason(systemMood)
            } else {
                currentMood = convMood
                moodReason = conversationMoodReason(convMood)
            }
        } else {
            currentMood = systemMood
            moodReason = systemMoodReason(systemMood)
        }
    }

    /// Derive mood purely from system state (no API calls).
    public func deriveSystemMood(aidaemonHealthy: Bool) -> Mood {
        if !aidaemonHealthy {
            let stale = heartbeat.timeSinceLastAwareness().map { $0 > 3600 } ?? true
            return stale ? .alert : .concerned
        }

        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= activeHoursEnd || hour < activeHoursStart {
            return .sleepy
        }

        let report = heartbeat.readReport()
        if report.hasAlerts {
            return .concerned
        }

        return .calm
    }

    /// Derive mood from conversation state. Returns nil if not in a conversation.
    public func deriveConversationMood(isChatting: Bool, isListening: Bool) -> Mood? {
        if isChatting { return .focused }
        if isListening { return .curious }
        return nil
    }

    // MARK: - Private

    private func systemMoodReason(_ mood: Mood) -> String {
        switch mood {
        case .alert:     return "System needs attention"
        case .concerned: return "Something may need attention"
        case .sleepy:    return "Outside active hours"
        case .calm:      return "All systems normal"
        default:         return mood.rawValue
        }
    }

    private func conversationMoodReason(_ mood: Mood) -> String {
        switch mood {
        case .focused:  return "Thinking"
        case .curious:  return "Listening"
        default:        return mood.rawValue
        }
    }
}

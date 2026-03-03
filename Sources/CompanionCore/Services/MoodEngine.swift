// Sources/CompanionCore/Services/MoodEngine.swift
import Foundation

/// Derives Friday's mood from system state + optional LLM nuance.
/// Layer 1: deterministic (system state). Layer 2: LLM override (haiku calls).
@MainActor
public final class MoodEngine {
    public private(set) var currentMood: Mood = .calm
    public private(set) var moodReason: String = "Starting up"

    private let client: AidaemonClient?
    private let heartbeat: HeartbeatMonitor
    private var llmMood: Mood?
    private var llmReason: String?
    private var lastLLMCheck: Date = .distantPast

    /// How often to ask the LLM for mood (seconds).
    public var llmInterval: TimeInterval = 60

    /// The model to use for mood checks (fast + cheap).
    public let moodModel = "claude-haiku-4.5"

    public init(client: AidaemonClient?, heartbeat: HeartbeatMonitor) {
        self.client = client
        self.heartbeat = heartbeat
    }

    /// Refresh mood from system state + optionally LLM.
    /// - Parameter isOverlayActive: if true, checks LLM more frequently
    public func refresh(aidaemonHealthy: Bool, isOverlayActive: Bool) async {
        // Layer 1: deterministic mood from system state
        let systemMood = deriveSystemMood(aidaemonHealthy: aidaemonHealthy)

        // Layer 2: LLM nuance (only when overlay is active and aidaemon is up)
        let now = Date()
        let interval = isOverlayActive ? llmInterval : llmInterval * 5
        if aidaemonHealthy && now.timeIntervalSince(lastLLMCheck) >= interval {
            await refreshLLMMood()
            lastLLMCheck = now
        }

        // Merge: system alert always wins, otherwise LLM overrides
        if systemMood == .alert || systemMood == .sleepy {
            currentMood = systemMood
            moodReason = systemMoodReason(systemMood)
        } else if let llm = llmMood {
            currentMood = llm
            moodReason = llmReason ?? "LLM mood"
        } else {
            currentMood = systemMood
            moodReason = systemMoodReason(systemMood)
        }
    }

    /// Derive mood purely from system state (no API calls).
    public func deriveSystemMood(aidaemonHealthy: Bool) -> Mood {
        // Alert: aidaemon unreachable AND heartbeat stale
        if !aidaemonHealthy {
            let stale = heartbeat.timeSinceLastAwareness().map { $0 > 3600 } ?? true
            return stale ? .alert : .concerned
        }

        // Sleeping: outside active hours (10 PM - 8 AM IST)
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 22 || hour < 8 {
            return .sleepy
        }

        // Concerned: heartbeat has alerts
        let report = heartbeat.readReport()
        if report.hasAlerts {
            return .concerned
        }

        // Default: calm
        return .calm
    }

    // MARK: - Private

    private func refreshLLMMood() async {
        guard let client = client else { return }

        let report = heartbeat.readReport()
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let isWeekend = dayOfWeek == 1 || dayOfWeek == 7

        let prompt = """
        You are Friday, an AI companion. Given the current system state, respond with ONLY a JSON object (no markdown, no explanation):
        {"mood":"<one of: calm, happy, curious, focused, concerned, alert, sleepy, playful>","reason":"<brief reason, 5-10 words>"}

        System state:
        - Time: \(hour):00
        - Day: \(isWeekend ? "weekend" : "weekday")
        - Alerts: \(report.hasAlerts ? "yes" : "none")
        - Pending tasks: \(report.pendingTasks)
        - Watchman issues: \(report.watchmanIssues.count)
        - Awareness: \(String(report.summary.prefix(200)))
        """

        do {
            let response = try await client.chat(
                message: prompt,
                sessionID: "friday-mood",
                model: moodModel
            )
            parseMoodResponse(response.reply)
        } catch {
            // LLM mood is optional — fail silently
        }
    }

    private func parseMoodResponse(_ text: String) {
        // Extract JSON from response (handle potential markdown wrapping)
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let moodStr = json["mood"],
              let mood = Mood(rawValue: moodStr) else {
            return
        }

        llmMood = mood
        llmReason = json["reason"]
    }

    private func systemMoodReason(_ mood: Mood) -> String {
        switch mood {
        case .alert:     return "System needs attention"
        case .concerned: return "Something may need attention"
        case .sleepy:    return "Outside active hours"
        case .calm:      return "All systems normal"
        default:         return mood.rawValue
        }
    }
}

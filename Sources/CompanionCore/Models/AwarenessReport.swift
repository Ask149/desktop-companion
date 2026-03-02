// Sources/CompanionCore/Models/AwarenessReport.swift
import Foundation

/// A single signal from the awareness report table.
public struct AwarenessSignal: Sendable {
    public let source: String
    public let finding: String

    public init(source: String, finding: String) {
        self.source = source
        self.finding = finding
    }
}

/// An action item (emoji-prefixed line) from the awareness report.
public struct AwarenessAction: Sendable {
    public let emoji: String
    public let text: String

    public init(emoji: String, text: String) {
        self.emoji = emoji
        self.text = text
    }
}

/// Parsed data from heartbeat state files.
public struct AwarenessReport: Sendable {
    /// Raw content of last-awareness.txt
    public let summary: String
    /// File modification date of last-awareness.txt
    public let lastUpdated: Date?
    /// Whether the summary contains ALERT/WARNING markers
    public let hasAlerts: Bool
    /// Issues from watchman-report.txt (non-empty lines)
    public let watchmanIssues: [String]
    /// Number of lines in task-queue.txt
    public let pendingTasks: Int
    /// Whether curiosity-YYYY-MM-DD.done exists for today
    public let curiosityDoneToday: Bool

    /// Parsed signal entries from the markdown table
    public let signals: [AwarenessSignal]
    /// Parsed action items (emoji-prefixed lines after the table)
    public let actions: [AwarenessAction]

    public init(
        summary: String,
        lastUpdated: Date?,
        hasAlerts: Bool,
        watchmanIssues: [String],
        pendingTasks: Int,
        curiosityDoneToday: Bool
    ) {
        self.summary = summary
        self.lastUpdated = lastUpdated
        self.hasAlerts = hasAlerts
        self.watchmanIssues = watchmanIssues
        self.pendingTasks = pendingTasks
        self.curiosityDoneToday = curiosityDoneToday
        self.signals = AwarenessReport.parseSignals(from: summary)
        self.actions = AwarenessReport.parseActions(from: summary)
    }

    /// Parse markdown table rows like `| Calendar | **Event** tonight |`
    private static func parseSignals(from text: String) -> [AwarenessSignal] {
        var signals: [AwarenessSignal] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match table rows but skip header and separator rows
            guard trimmed.hasPrefix("|"),
                  !trimmed.contains("------"),
                  !trimmed.lowercased().contains("| source") else { continue }

            let parts = trimmed.split(separator: "|", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }

            let source = parts[0].trimmingCharacters(in: .whitespaces)
            let finding = parts[1].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "**", with: "") // Strip bold markers

            guard !source.isEmpty, !finding.isEmpty else { continue }
            signals.append(AwarenessSignal(source: source, finding: finding))
        }
        return signals
    }

    /// Parse emoji-prefixed action lines (e.g., "🫀 Important thing here")
    private static func parseActions(from text: String) -> [AwarenessAction] {
        var actions: [AwarenessAction] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Check if line starts with an emoji (first scalar is emoji)
            let first = trimmed.unicodeScalars.first
            guard let scalar = first,
                  scalar.properties.isEmoji,
                  scalar.value > 0x00FF else { continue } // Skip ASCII chars like | and *

            // Grab first character cluster as emoji
            let emoji = String(trimmed[trimmed.startIndex..<trimmed.index(after: trimmed.startIndex)])
            let rest = String(trimmed[trimmed.index(after: trimmed.startIndex)...])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "**", with: "") // Strip bold markers

            guard !rest.isEmpty else { continue }
            actions.append(AwarenessAction(emoji: emoji, text: rest))
        }
        return actions
    }
}

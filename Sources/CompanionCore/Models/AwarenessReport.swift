// Sources/CompanionCore/Models/AwarenessReport.swift
import Foundation

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
    }
}

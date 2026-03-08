// Sources/CompanionCore/Services/HeartbeatMonitor.swift
import Foundation

/// Reads heartbeat state files and provides parsed awareness data.
public final class HeartbeatMonitor: Sendable {
    public let stateDir: URL
    public let notesDir: URL

    /// Initialize with optional custom directories. Defaults to aidaemon heartbeat paths.
    public init(stateDir: String? = nil, notesDir: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let dir = stateDir {
            self.stateDir = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        } else {
            self.stateDir = home.appendingPathComponent(".config/aidaemon/heartbeat/state")
        }
        if let dir = notesDir {
            self.notesDir = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        } else {
            self.notesDir = home.appendingPathComponent(".config/aidaemon/notes")
        }
    }

    /// Read and parse all heartbeat state into an AwarenessReport.
    public func readReport() -> AwarenessReport {
        let awarenessContent = readFile("last-awareness.txt")
        let awarenessDate = fileModDate("last-awareness.txt")
        let watchmanContent = readFile("watchman-report.txt")
        let taskQueueContent = readFile("task-queue.txt")

        let watchmanIssues = watchmanContent
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let pendingTasks = taskQueueContent
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count

        return AwarenessReport(
            summary: awarenessContent,
            lastUpdated: awarenessDate,
            hasAlerts: hasAlertMarkers(awarenessContent),
            watchmanIssues: watchmanIssues,
            pendingTasks: pendingTasks,
            curiosityDoneToday: curiosityDoneToday()
        )
    }

    /// Check if text contains alert markers.
    public func hasAlertMarkers(_ text: String) -> Bool {
        let markers = ["ALERT:", "WARNING:", "⚠️", "🚨", "URGENT:", "ACTION REQUIRED"]
        return markers.contains { text.uppercased().contains($0.uppercased()) }
    }

    /// Check if today's curiosity has already run.
    public func curiosityDoneToday() -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let doneFile = stateDir.appendingPathComponent("curiosity-\(today).done")
        return FileManager.default.fileExists(atPath: doneFile.path)
    }

    /// Time since last awareness update.
    public func timeSinceLastAwareness() -> TimeInterval? {
        guard let date = fileModDate("last-awareness.txt") else { return nil }
        return Date().timeIntervalSince(date)
    }

    // MARK: - Private

    private func readFile(_ name: String) -> String {
        let path = stateDir.appendingPathComponent(name)
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    private func fileModDate(_ name: String) -> Date? {
        let path = stateDir.appendingPathComponent(name)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
        return attrs?[.modificationDate] as? Date
    }
}

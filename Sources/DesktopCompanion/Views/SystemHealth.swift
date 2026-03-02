// Sources/DesktopCompanion/Views/SystemHealth.swift
import SwiftUI
import CompanionCore

struct SystemHealth: View {
    let aidaemonHealthy: Bool
    let model: String
    let report: AwarenessReport?

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                healthRow("Aidaemon", ok: aidaemonHealthy, detail: model.isEmpty ? nil : model)
                healthRow("Heartbeat", ok: report?.lastUpdated != nil,
                         detail: report?.lastUpdated.map { "Last: \(timeAgo($0))" })
                healthRow("Curiosity", ok: report?.curiosityDoneToday ?? false,
                         detail: report?.curiosityDoneToday == true ? "Done today" : "Pending")

                if let tasks = report?.pendingTasks, tasks > 0 {
                    healthRow("Task Queue", ok: false, detail: "\(tasks) pending")
                }
            }
            .font(.caption)
            .padding(.top, 8)
        } label: {
            Label("System Health", systemImage: "heart.text.square")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func healthRow(_ name: String, ok: Bool, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .imageScale(.small)
            Text(name)
                .foregroundStyle(.primary)
            Spacer()
            if let detail = detail {
                Text(detail)
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

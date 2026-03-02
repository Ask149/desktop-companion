// Sources/DesktopCompanion/Views/AwarenessSummary.swift
import SwiftUI
import CompanionCore

struct AwarenessSummary: View {
    let report: AwarenessReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Awareness")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if let report = report, !report.summary.isEmpty {
                ScrollView {
                    if let attributed = try? AttributedString(markdown: report.summary) {
                        Text(attributed)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        // Fallback if markdown parsing fails
                        Text(report.summary)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxHeight: 150)
            } else {
                Text("No awareness data yet. Heartbeat hasn't run.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

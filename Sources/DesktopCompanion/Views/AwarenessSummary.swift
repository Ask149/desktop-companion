// Sources/DesktopCompanion/Views/AwarenessSummary.swift
import SwiftUI
import CompanionCore

struct AwarenessSummary: View {
    let report: AwarenessReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Awareness", systemImage: "brain.head.profile")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let report = report {
                // Action items first (most important)
                if !report.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(report.actions.enumerated()), id: \.offset) { _, action in
                            HStack(alignment: .top, spacing: 8) {
                                Text(action.emoji)
                                    .font(.callout)
                                Text(action.text)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }

                // Signals table
                if !report.signals.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(report.signals.enumerated()), id: \.offset) { _, signal in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(signal.source)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(sourcePillColor(signal.source), in: Capsule())
                                        .fixedSize()

                                    Text(signal.finding)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }

                // Fallback if no structured data parsed
                if report.signals.isEmpty && report.actions.isEmpty && !report.summary.isEmpty {
                    ScrollView {
                        Text(report.summary)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                }
            } else {
                Text("No awareness data yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sourcePillColor(_ source: String) -> Color {
        switch source.lowercased() {
        case "calendar": return .blue
        case "gmail": return .red
        case "goals": return .orange
        case "watchman": return .purple
        case "notes": return .green
        default: return .gray
        }
    }
}

// Sources/DesktopCompanion/Views/StatusCard.swift
import SwiftUI
import CompanionCore

struct StatusCard: View {
    let mode: CompanionMode
    let aidaemonHealthy: Bool
    let lastUpdated: Date?

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .shadow(color: statusColor.opacity(0.5), radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusText)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)

                if let date = lastUpdated {
                    Text("Updated \(date, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !aidaemonHealthy {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.small)
                    .help("Aidaemon is not responding")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch mode {
        case .idle: return .green
        case .thinking: return .blue
        case .alert: return .orange
        case .sleeping: return .gray
        case .dead: return .red
        }
    }

    private var statusText: String {
        switch mode {
        case .idle: return "All Good"
        case .thinking: return "Thinking…"
        case .alert: return "Needs Attention"
        case .sleeping: return "Sleeping"
        case .dead: return "Offline"
        }
    }
}

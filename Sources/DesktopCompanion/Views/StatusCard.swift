// Sources/DesktopCompanion/Views/StatusCard.swift
import SwiftUI
import CompanionCore

struct StatusCard: View {
    let mode: CompanionMode
    let aidaemonHealthy: Bool
    let lastUpdated: Date?

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let date = lastUpdated {
                    Text("Updated \(date, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !aidaemonHealthy {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .help("Aidaemon is not responding")
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
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
        case .idle: return "All good"
        case .thinking: return "Thinking..."
        case .alert: return "Needs attention"
        case .sleeping: return "Sleeping"
        case .dead: return "Offline"
        }
    }
}

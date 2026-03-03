// Sources/DesktopCompanion/Views/PopoverView.swift
import SwiftUI
import CompanionCore

struct PopoverView: View {
    @ObservedObject var state: CompanionState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Friday")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button(action: { Task { await state.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Refresh")

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Quit")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 10) {
                    StatusCard(
                        mode: state.mode,
                        aidaemonHealthy: state.aidaemonHealthy,
                        lastUpdated: state.awarenessReport?.lastUpdated
                    )

                    AwarenessSummary(report: state.awarenessReport)

                    QuickChat(state: state)

                    SystemHealth(
                        aidaemonHealthy: state.aidaemonHealthy,
                        model: state.aidaemonModel,
                        report: state.awarenessReport
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 360, height: 520)
    }
}

// Sources/DesktopCompanion/Views/PopoverView.swift
import SwiftUI
import CompanionCore

struct PopoverView: View {
    @ObservedObject var state: CompanionState

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Desktop Companion")
                    .font(.headline)
                Spacer()
                Button(action: { Task { await state.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
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
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 320, height: 450)
    }
}

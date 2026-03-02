// Sources/DesktopCompanion/Views/PopoverView.swift
import SwiftUI
import CompanionCore

struct PopoverView: View {
    @ObservedObject var state: CompanionState

    var body: some View {
        VStack(spacing: 12) {
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
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
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
                .padding(.bottom, 12)
            }
        }
        .frame(width: 340, height: 500)
    }
}

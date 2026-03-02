// Sources/CompanionCore/CompanionState.swift
import Foundation
import Combine

/// Central observable state for the desktop companion.
/// Polls aidaemon health and heartbeat files, derives companion mode.
@MainActor
public class CompanionState: ObservableObject {
    // Published state
    @Published public var mode: CompanionMode = .idle
    @Published public var aidaemonHealthy: Bool = false
    @Published public var aidaemonModel: String = ""
    @Published public var awarenessReport: AwarenessReport?
    @Published public var chatResponse: String = ""
    @Published public var isChatting: Bool = false

    // Services
    private var client: AidaemonClient?
    private let heartbeat = HeartbeatMonitor()
    private var healthTimer: Timer?
    private var heartbeatTimer: Timer?

    public init() {
        // Load aidaemon config
        if let config = AidaemonConfig.load() {
            client = AidaemonClient(config: config)
        }

        // Start polling
        startPolling()

        // Initial read
        Task { await refresh() }
    }

    // MARK: - Polling

    private func startPolling() {
        // Health check every 30 seconds
        healthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkHealth()
            }
        }

        // Heartbeat files every 60 seconds
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readHeartbeat()
            }
        }
    }

    // MARK: - Actions

    public func refresh() async {
        await checkHealth()
        readHeartbeat()
        deriveMode()
    }

    public func sendChat(message: String) async {
        guard let client = client, !message.isEmpty else { return }
        isChatting = true
        chatResponse = ""
        deriveMode() // Switch to .thinking
        defer {
            isChatting = false
            deriveMode() // Switch back from .thinking
        }

        do {
            let response = try await client.chat(message: message)
            chatResponse = response.reply
        } catch {
            chatResponse = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func checkHealth() async {
        guard let client = client else {
            aidaemonHealthy = false
            deriveMode()
            return
        }

        let health = await client.checkHealth()
        aidaemonHealthy = health != nil
        aidaemonModel = health?.model ?? ""
        deriveMode()
    }

    private func readHeartbeat() {
        awarenessReport = heartbeat.readReport()
        deriveMode()
    }

    private func deriveMode() {
        // Priority: dead > sleeping > alert > thinking > idle

        // Dead: aidaemon unreachable AND heartbeat stale > 1 hour
        if !aidaemonHealthy {
            let stale = heartbeat.timeSinceLastAwareness().map { $0 > 3600 } ?? true
            mode = stale ? .dead : .idle // If heartbeat is recent, just show idle
            return
        }

        // Sleeping: outside active hours (10 PM - 8 AM IST)
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        // IST = UTC+5:30. We check local time since the machine is in IST.
        if hour >= 22 || hour < 8 {
            mode = .sleeping
            return
        }

        // Alert: heartbeat found something important
        if awarenessReport?.hasAlerts == true {
            mode = .alert
            return
        }

        // Thinking: currently processing a chat
        if isChatting {
            mode = .thinking
            return
        }

        // Default: idle
        mode = .idle
    }
}

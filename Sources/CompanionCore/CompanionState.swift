// Sources/CompanionCore/CompanionState.swift
import Foundation
import Combine

/// Central observable state for Friday.
/// Manages mood, session, voice, overlay lifecycle, and polling.
@MainActor
public class CompanionState: ObservableObject {
    // --- Mode & Mood ---
    @Published public var mode: CompanionMode = .idle
    @Published public var mood: Mood = .calm
    @Published public var moodReason: String = "Starting up"

    // --- Health ---
    @Published public var aidaemonHealthy: Bool = false
    @Published public var aidaemonModel: String = ""
    @Published public var awarenessReport: AwarenessReport?

    // --- Chat (popover) ---
    @Published public var chatResponse: String = ""
    @Published public var isChatting: Bool = false

    // --- Overlay ---
    @Published public var isOverlayVisible: Bool = false
    @Published public var greeting: String = ""
    @Published public var partialTranscription: String = ""
    @Published public var mouthOpenness: Double = 0
    @Published public var blinkAmount: Double = 0

    // --- Voice ---
    @Published public var isMuted: Bool = false

    // --- Services ---
    private var client: AidaemonClient?
    public let heartbeat = HeartbeatMonitor()
    public let session = SessionStore()
    public let moodEngine: MoodEngine
    public let voiceInput = VoiceInput()
    public let voiceOutput = VoiceOutput()
    public let idleDetector = IdleDetector()
    public let hotkeyManager = HotkeyManager()

    private var healthTimer: Timer?
    private var heartbeatTimer: Timer?
    private var moodTimer: Timer?
    private var blinkTimer: Timer?

    /// Model for quick interactions (mood, greeting, casual chat).
    public let fastModel = "claude-haiku-4.5"
    /// Model for complex tasks.
    public let strongModel = "claude-sonnet-4.5"

    public init() {
        // Load aidaemon config
        if let config = AidaemonConfig.load() {
            client = AidaemonClient(config: config)
        }
        moodEngine = MoodEngine(client: client, heartbeat: heartbeat)

        // Wire voice output → mouth animation
        voiceOutput.onMouthUpdate = { [weak self] openness in
            self?.mouthOpenness = openness
        }
        voiceOutput.onFinished = { [weak self] in
            self?.mouthOpenness = 0
            // Restart listening after Friday finishes speaking
            if self?.isOverlayVisible == true {
                self?.voiceInput.startListening()
            }
        }

        // Wire voice input → chat
        voiceInput.onFinalResult = { [weak self] text in
            guard let self = self, !text.isEmpty else { return }
            self.partialTranscription = ""
            Task { await self.handleVoiceInput(text) }
        }
        voiceInput.onPartialResult = { [weak self] text in
            self?.partialTranscription = text
        }

        // Wire idle detector
        idleDetector.onIdleStart = { [weak self] in
            self?.showOverlay()
        }

        // Wire hotkey
        hotkeyManager.onHotkey = { [weak self] in
            guard let self = self else { return }
            if self.isOverlayVisible {
                self.hideOverlay()
            } else {
                self.showOverlay()
            }
        }

        // Start services
        startPolling()
        idleDetector.start()
        hotkeyManager.register()
        startBlinkLoop()

        // Request voice permissions
        Task { await voiceInput.requestAuthorization() }

        // Initial data load
        Task { await refresh() }
    }

    // MARK: - Overlay Lifecycle

    /// Show the overlay and generate a greeting.
    public func showOverlay() {
        guard !isOverlayVisible else { return }
        isOverlayVisible = true
        greeting = ""
        Task {
            await generateGreeting()
            // Start listening after greeting
            voiceInput.startListening()
        }
    }

    /// Hide the overlay, stop voice, preserve session.
    public func hideOverlay() {
        isOverlayVisible = false
        voiceInput.stopListening()
        voiceOutput.stop()
        partialTranscription = ""
    }

    // MARK: - Chat

    /// Send a chat message (from popover quick chat or voice).
    public func sendChat(message: String) async {
        guard !message.isEmpty else { return }
        guard let client = client else {
            chatResponse = "⚠️ aidaemon is offline — start it with `aidaemon start`"
            return
        }

        isChatting = true
        chatResponse = ""
        deriveMode()
        defer {
            isChatting = false
            deriveMode()
        }

        // Determine model based on complexity
        let model = isComplexQuery(message) ? strongModel : fastModel

        do {
            let response = try await client.chat(
                message: message,
                sessionID: session.sessionID,
                model: model
            )
            chatResponse = response.reply
            session.add(role: "user", content: message)
            session.add(role: "assistant", content: response.reply)

            // Speak the response if overlay is visible
            if isOverlayVisible {
                voiceInput.stopListening() // Don't listen while speaking
                voiceOutput.isMuted = isMuted
                voiceOutput.speak(response.reply)
            }
        } catch {
            chatResponse = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func handleVoiceInput(_ text: String) async {
        session.add(role: "user", content: text)
        await sendChat(message: text)
    }

    private func generateGreeting() async {
        guard let client = client else {
            greeting = "I'm offline right now, but I'm still here."
            speakGreeting()
            return
        }

        await moodEngine.refresh(aidaemonHealthy: aidaemonHealthy, isOverlayActive: true)
        mood = moodEngine.currentMood
        moodReason = moodEngine.moodReason

        let report = heartbeat.readReport()
        let resumeContext = session.hasHistory ? "We were talking earlier. " : ""

        let prompt = """
        You are Friday, an AI companion on a Mac. Generate a brief greeting (1-2 sentences).
        Be natural, warm, slightly witty. Don't be sycophantic.
        \(resumeContext)
        Context: \(String(report.summary.prefix(300)))
        Mood: \(mood.rawValue) (\(moodReason))
        Time: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))
        """

        do {
            let response = try await client.chat(
                message: prompt,
                sessionID: "friday-greeting",
                model: fastModel
            )
            greeting = response.reply
        } catch {
            greeting = "Hey. All systems running."
        }

        speakGreeting()
    }

    private func speakGreeting() {
        voiceOutput.isMuted = isMuted
        voiceOutput.speak(greeting)
    }

    private func startPolling() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkHealth() }
        }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readHeartbeat() }
        }
        moodTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshMood() }
        }
    }

    private func startBlinkLoop() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                // Random blink every 3-6 seconds
                if Int.random(in: 0...10) == 0 && self.blinkAmount == 0 {
                    self.blinkAmount = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.blinkAmount = 0
                    }
                }
            }
        }
    }

    public func refresh() async {
        await checkHealth()
        readHeartbeat()
        await refreshMood()
        deriveMode()
    }

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

    private func refreshMood() async {
        await moodEngine.refresh(aidaemonHealthy: aidaemonHealthy, isOverlayActive: isOverlayVisible)
        mood = moodEngine.currentMood
        moodReason = moodEngine.moodReason
    }

    private func deriveMode() {
        if !aidaemonHealthy {
            let stale = heartbeat.timeSinceLastAwareness().map { $0 > 3600 } ?? true
            mode = stale ? .dead : .idle
            return
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 22 || hour < 8 { mode = .sleeping; return }
        if awarenessReport?.hasAlerts == true { mode = .alert; return }
        if isChatting { mode = .thinking; return }
        mode = .idle
    }

    /// Heuristic: is this a complex query needing the strong model?
    private func isComplexQuery(_ text: String) -> Bool {
        let complexTriggers = ["analyze", "research", "explain in detail", "compare",
                               "write code", "implement", "debug", "review"]
        let lower = text.lowercased()
        return text.count > 100 || complexTriggers.contains(where: { lower.contains($0) })
    }
}

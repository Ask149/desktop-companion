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
    @Published public var sessionMessages: [SessionStore.Message] = []
    @Published public var mouthOpenness: Double = 0
    @Published public var blinkAmount: Double = 0
    @Published public var partialAssistantResponse: String = ""
    @Published public var streamStatus: String = ""

    // --- Voice ---
    @Published public var isMuted: Bool = false
    @Published public var isVoiceListening: Bool = false

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
    private var overlayTimeoutTimer: Timer?

    /// Model for quick interactions (mood, greeting, casual chat).
    public let fastModel: String
    /// Model for complex tasks (from config's chat_model, or default).
    public let strongModel: String

    public init() {
        // Load aidaemon config
        let config = AidaemonConfig.load()
        if let config = config {
            client = AidaemonClient(config: config)
        }
        
        // Model routing: strong model from config, fast model always haiku
        strongModel = config?.chatModel ?? "claude-sonnet-4.5"
        fastModel = "claude-haiku-4.5"
        
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
            if self.isOverlayVisible { self.resetOverlayTimeout() }
            Task { await self.handleVoiceInput(text) }
        }
        voiceInput.onPartialResult = { [weak self] text in
            self?.partialTranscription = text
        }
        voiceInput.onListeningChanged = { [weak self] listening in
            self?.isVoiceListening = listening
        }

        // Wire session → published messages
        session.onMessagesChanged = { [weak self] messages in
            self?.sessionMessages = messages
        }

        // Wire idle detector
        idleDetector.onIdleStart = { [weak self] in
            self?.showOverlay()
        }

        // Wire hotkey — always works, even outside active hours
        hotkeyManager.onHotkey = { [weak self] in
            guard let self = self else { return }
            if self.isOverlayVisible {
                self.hideOverlay()
            } else {
                self.showOverlay(force: true)
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
        Task {
            // Restore session history from aidaemon (survives app restarts)
            if let client = client {
                let history = await client.getSessionMessages(sessionID: session.sessionID)
                if !history.isEmpty {
                    session.restore(from: history.map {
                        SessionStore.Message(role: $0.role, content: $0.content)
                    })
                }
            }
            await refresh()
        }
    }

    // MARK: - Overlay Lifecycle

    /// Show the overlay and generate a greeting.
    /// - Parameter force: If true, bypass active hours check (used by hotkey).
    public func showOverlay(force: Bool = false) {
        guard !isOverlayVisible else { return }

        // Don't show outside active hours (8 AM – 10 PM) unless forced (hotkey)
        if !force {
            let hour = Calendar.current.component(.hour, from: Date())
            guard hour >= 8 && hour < 22 else { return }
        }

        isOverlayVisible = true
        greeting = ""
        // Safety timeout — auto-dismiss after 60s of no interaction
        resetOverlayTimeout()
        Task {
            await generateGreeting()
            // Start listening after greeting
            voiceInput.startListening()
        }
    }

    /// Hide the overlay, stop voice, preserve session.
    public func hideOverlay() {
        isOverlayVisible = false
        overlayTimeoutTimer?.invalidate()
        overlayTimeoutTimer = nil
        voiceInput.stopListening()
        voiceOutput.stop()
        partialTranscription = ""
    }

    // MARK: - Chat

    /// Send a chat message (from popover quick chat or voice).
    public func sendChat(message: String) async {
        guard !message.isEmpty else { return }
        guard let client = client else {
            let errorMsg = "I'm offline right now — aidaemon isn't running."
            chatResponse = errorMsg
            if isOverlayVisible {
                session.add(role: "assistant", content: errorMsg)
            }
            return
        }

        session.add(role: "user", content: message)
        isChatting = true
        chatResponse = ""
        partialAssistantResponse = ""
        streamStatus = ""
        deriveMode()
        defer {
            isChatting = false
            partialAssistantResponse = ""
            streamStatus = ""
            deriveMode()
        }

        // Determine model based on complexity
        let model = isComplexQuery(message) ? strongModel : fastModel

        // Use streaming when overlay is visible for progressive UX
        if isOverlayVisible {
            await sendChatStreaming(client: client, message: message, model: model)
        } else {
            await sendChatBlocking(client: client, message: message, model: model)
        }
    }

    /// Blocking chat path — used for popover quick chat.
    private func sendChatBlocking(client: AidaemonClient, message: String, model: String) async {
        do {
            let response = try await client.chat(
                message: message,
                sessionID: session.sessionID,
                model: model
            )
            chatResponse = response.reply
            session.add(role: "assistant", content: response.reply)
        } catch {
            let errorMsg = "Sorry, I couldn't process that. (\(error.localizedDescription))"
            chatResponse = errorMsg
            session.add(role: "assistant", content: errorMsg)
        }
    }

    /// Streaming chat path — used when overlay is visible for progressive response display.
    private func sendChatStreaming(client: AidaemonClient, message: String, model: String) async {
        voiceInput.stopListening() // Don't listen while processing

        var accumulated = ""
        var spokenUpTo = 0 // character index up to which we've queued TTS
        var finalText = ""

        do {
            let stream = client.chatStream(
                message: message,
                sessionID: session.sessionID,
                model: model
            )

            for try await event in stream {
                switch event {
                case .status(let text):
                    streamStatus = text
                case .toolUse(let name, let message):
                    streamStatus = "\(message.isEmpty ? "Using \(name)..." : message)"
                case .delta(let chunk):
                    streamStatus = "" // clear status when content starts flowing
                    accumulated += chunk
                    partialAssistantResponse = accumulated
                    // Speak completed sentences as they arrive
                    speakCompletedSentences(accumulated, spokenUpTo: &spokenUpTo)
                case .done(let text, _):
                    finalText = text
                case .error(let text):
                    finalText = "Sorry, something went wrong. (\(text))"
                }
            }
        } catch {
            finalText = "Sorry, I couldn't process that. (\(error.localizedDescription))"
        }

        // Finalize: use done text (server-authoritative) for storage,
        // but derive unspoken text from accumulated (matches spokenUpTo offsets)
        let reply = finalText.isEmpty ? accumulated : finalText
        chatResponse = reply
        partialAssistantResponse = ""
        session.add(role: "assistant", content: reply)

        // Speak any remaining unspoken text (use accumulated for correct offset)
        let sourceForSpeech = accumulated.isEmpty ? reply : accumulated
        if spokenUpTo < sourceForSpeech.count {
            let unspoken = String(sourceForSpeech.dropFirst(spokenUpTo)).trimmingCharacters(in: .whitespaces)
            if !unspoken.isEmpty {
                voiceOutput.isMuted = isMuted
                voiceOutput.enqueue(unspoken)
            }
        } else if spokenUpTo == 0 && !reply.isEmpty {
            // Nothing was spoken during streaming (short response) — speak it all
            voiceOutput.isMuted = isMuted
            voiceOutput.speak(reply)
        }

        resetOverlayTimeout()
    }

    /// Detect completed sentences in the accumulated text and enqueue them for TTS.
    /// Updates spokenUpTo to track what's already been queued for TTS.
    private func speakCompletedSentences(_ text: String, spokenUpTo: inout Int) {
        let sentenceEnders: [Character] = [".", "!", "?"]
        var lastSentenceEnd = spokenUpTo

        for i in text.indices {
            let offset = text.distance(from: text.startIndex, to: i)
            guard offset >= spokenUpTo else { continue }
            if sentenceEnders.contains(text[i]) {
                // Require sentence ender followed by whitespace or end-of-string
                // to avoid false triggers on abbreviations like "Dr." or "3.14"
                let nextIdx = text.index(after: i)
                if nextIdx == text.endIndex || text[nextIdx].isWhitespace {
                    lastSentenceEnd = offset + 1
                }
            }
        }

        if lastSentenceEnd > spokenUpTo {
            let startIdx = text.index(text.startIndex, offsetBy: spokenUpTo)
            let endIdx = text.index(text.startIndex, offsetBy: lastSentenceEnd)
            let sentence = String(text[startIdx..<endIdx]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty {
                voiceOutput.isMuted = isMuted
                voiceOutput.enqueue(sentence) // enqueue — don't interrupt current speech
            }
            spokenUpTo = lastSentenceEnd
        }
    }

    // MARK: - Private

    private func resetOverlayTimeout() {
        overlayTimeoutTimer?.invalidate()
        overlayTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideOverlay()
            }
        }
    }

    private func handleVoiceInput(_ text: String) async {
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
            Task { @MainActor in
                guard let self = self else { return }
                // Random blink every 3-6 seconds
                if Int.random(in: 0...10) == 0 && self.blinkAmount == 0 {
                    self.blinkAmount = 1
                    try? await Task.sleep(for: .milliseconds(150))
                    self.blinkAmount = 0
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

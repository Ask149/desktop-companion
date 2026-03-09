// Sources/CompanionCore/CompanionState.swift
import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.ask149.friday", category: "CompanionState")

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

    /// The text that was last spoken by TTS — persists on screen after speech ends.
    @Published public var lastSpokenText: String = ""

    // --- Voice ---
    @Published public var isMuted: Bool = false
    @Published public var isVoiceListening: Bool = false
    /// Microphone audio level (0.0–1.0), drives the audio-reactive listening ring.
    @Published public var audioLevel: Double = 0

    /// Buffered voice inputs received while Friday is busy (chatting or speaking).
    /// Flushed as a single combined message when TTS finishes.
    private var pendingInputs: [String] = []

    /// Called when the overlay can't show because voice permissions aren't granted.
    /// The UI layer (AppDelegate) should open System Settings → Privacy → Speech Recognition.
    public var onPermissionNeeded: (() -> Void)?

    // --- Services ---
    private var client: AidaemonClient?
    public let heartbeat: HeartbeatMonitor
    public let session = SessionStore()
    public let moodEngine: MoodEngine
    public let voiceInput: VoiceInput
    public let voiceOutput = VoiceOutput()
    public let interruptListener: InterruptListener
    public let idleDetector = IdleDetector()
    public let hotkeyManager = HotkeyManager()
    public let audioOutputDetector = AudioOutputDetector()
    public let fridayConfig: FridayConfig

    private var healthTimer: Timer?
    private var heartbeatTimer: Timer?
    private var moodTimer: Timer?
    private var blinkTimer: Timer?

    /// Post-TTS delay before restarting mic (seconds).
    /// Adaptive: long delay for built-in speakers (echo risk), short for headphones/Bluetooth.
    /// Echo word-matching (`isLikelyEcho`) provides a safety net.
    private var postTTSDelay: TimeInterval {
        audioOutputDetector.isBuiltInSpeaker ? 1.5 : 0.3
    }

    /// Model for quick interactions (mood, greeting, casual chat).
    public let fastModel: String
    /// Model for complex tasks (from config's chat_model, or default).
    public let strongModel: String

    /// System prompt for voice overlay — keeps responses conversational, brief, and markdown-free.
    private let voiceSystemPrompt: String

    public init() {
        // Load configs first (needed for component initialization)
        let config = AidaemonConfig.load()
        let friday = FridayConfig.load()
        self.fridayConfig = friday

        // Initialize locale-dependent components
        let locale = friday.locale.map { Locale(identifier: $0) } ?? .current
        voiceInput = VoiceInput(locale: locale)
        interruptListener = InterruptListener(locale: locale)

        // Initialize heartbeat with config paths
        heartbeat = HeartbeatMonitor(
            stateDir: friday.heartbeatStateDir,
            notesDir: friday.notesDir
        )

        if let config = config {
            client = AidaemonClient(config: config)
        }

        // Model routing: strong model from config, fast model always haiku
        strongModel = config?.chatModel ?? "claude-sonnet-4.5"
        fastModel = "claude-haiku-4.5"

        // Set voice system prompt with configured user name
        let userName = friday.userName ?? "the user"
        voiceSystemPrompt = """
            You are Friday, a voice AI companion on a Mac desktop. You are speaking aloud to \(userName).

            CRITICAL RULES:
            - You are a VOICE interface. Your responses will be spoken aloud by text-to-speech.
            - Keep responses to 1-2 sentences. Be concise and conversational.
            - NEVER use markdown formatting: no **bold**, no *italic*, no # headers, no - bullets, no `code`, no [links](url).
            - NEVER use emojis or emoticons. Plain text only.
            - Write in natural spoken English. Use plain text only.
            - Don't list things with bullet points. Instead, mention them conversationally.
            - If asked something complex, give the key insight first, then offer to elaborate.
            - Be warm but direct. You're a companion, not a document generator.
            - When using tools, just share the result naturally — don't describe the tool or format.
            """

        moodEngine = MoodEngine(client: client, heartbeat: heartbeat,
                               activeHoursStart: friday.activeHoursStart ?? 8,
                               activeHoursEnd: friday.activeHoursEnd ?? 22)

        // Configure components from FridayConfig
        voiceOutput.voiceIdentifier = friday.voiceIdentifier
        idleDetector.activeHoursStart = friday.activeHoursStart ?? 8
        idleDetector.activeHoursEnd = friday.activeHoursEnd ?? 22

        // Wire voice output → mouth animation
        voiceOutput.onMouthUpdate = { [weak self] openness in
            self?.mouthOpenness = openness
        }
        voiceOutput.onFinished = { [weak self] in
            logger.info("TTS finished, stopping interrupt listener, will restart voice input")
            self?.interruptListener.stop()
            self?.mouthOpenness = 0
            // Restart listening after Friday finishes speaking,
            // with a delay to avoid picking up tail-end audio/echo.
            // The delay must be long enough for speaker output buffers to drain
            // AND room echo to decay — MacBook speakers and mic are centimeters apart.
            // Guard on isChatting prevents mid-stream mic restart
            // (between sentences during streaming TTS).
            if self?.isOverlayVisible == true {
                let delay = self?.postTTSDelay ?? 2.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    guard self.isOverlayVisible else {
                        logger.info("Overlay no longer visible, skipping voice restart")
                        return
                    }
                    guard !self.voiceOutput.isSpeaking else {
                        logger.info("Still speaking, skipping voice restart")
                        return
                    }

                    // Flush any buffered inputs that arrived while we were busy.
                    // This sends them as a single combined message for a cohesive response.
                    if !self.pendingInputs.isEmpty {
                        let combined = self.pendingInputs.joined(separator: ". ")
                        self.pendingInputs.removeAll()
                        logger.info("Flushing \(combined.count) chars of buffered voice input")
                        Task { await self.sendChat(message: combined) }
                        return // sendChat will trigger TTS → onFinished → restart cycle
                    }

                    guard !self.isChatting else {
                        logger.info("Still chatting, skipping voice restart")
                        return
                    }
                    logger.info("Restarting voice input after TTS (post-delay)")
                    self.voiceInput.startListening()
                }
            }
        }

        // Wire interrupt listener → speech interrupt
        interruptListener.onInterrupt = { [weak self] in
            self?.interruptSpeech()
        }

        // Wire voice input → chat
        voiceInput.onFinalResult = { [weak self] text in
            guard let self = self, !text.isEmpty else { return }
            logger.info("Voice final result received: \(text.prefix(80))")
            self.partialTranscription = ""
            Task { await self.handleVoiceInput(text) }
        }
        voiceInput.onPartialResult = { [weak self] text in
            self?.partialTranscription = text
        }
        voiceInput.onListeningChanged = { [weak self] listening in
            self?.isVoiceListening = listening
        }
        voiceInput.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                // Smoothing: fast attack (instant rise), slow decay (gentle fall)
                self.audioLevel = level > self.audioLevel ? level : self.audioLevel * 0.7 + level * 0.3
            }
        }
        voiceInput.onError = { [weak self] errorMsg in
            logger.error("VoiceInput error surfaced: \(errorMsg)")
            // Speech recognizer timeouts are transient — Apple's SFSpeechRecognitionTask
            // ends after ~60s of silence. If the overlay is still visible, keep listening.
            guard let self, self.isOverlayVisible else { return }
            guard !self.voiceOutput.isSpeaking, !self.isChatting else { return }
            logger.info("Overlay still visible, restarting voice input after error recovery")
            DispatchQueue.main.asyncAfter(deadline: .now() + self.postTTSDelay) { [weak self] in
                guard let self, self.isOverlayVisible else { return }
                guard !self.voiceOutput.isSpeaking, !self.isChatting else { return }
                self.voiceInput.resetFailureCount()
                self.voiceInput.startListening()
            }
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

        // Start services (except overlay triggers — those wait for permissions)
        startPolling()
        startBlinkLoop()

        // Request voice permissions, then enable overlay triggers
        Task {
            await voiceInput.requestAuthorization()
            if voiceInput.isAuthorized {
                logger.info("Voice permissions granted, enabling overlay triggers")
                idleDetector.start()
                hotkeyManager.register()
            } else {
                logger.warning("Voice permissions not granted — overlay triggers disabled until authorized")
                // Register hotkey anyway so user can trigger permission flow
                hotkeyManager.register()
            }
        }

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

        // Voice permissions are required for the overlay (speech recognition + mic).
        // If not authorized, redirect to System Settings instead of covering the
        // permission dialog with a full-screen overlay.
        guard voiceInput.isAuthorized else {
            logger.warning("Cannot show overlay — voice permissions not granted, requesting settings")
            onPermissionNeeded?()
            return
        }

        // Don't show outside active hours unless forced (hotkey)
        if !force {
            let hour = Calendar.current.component(.hour, from: Date())
            let start = fridayConfig.activeHoursStart ?? 8
            let end = fridayConfig.activeHoursEnd ?? 22
            guard hour >= start && hour < end else { return }
        }

        isOverlayVisible = true
        greeting = ""
        Task {
            await generateGreeting()
            // Don't start listening here — onFinished callback handles it
            // after the greeting TTS completes, preventing echo
        }
    }

    /// Interrupt speech without dismissing the overlay — tap to stop TTS and start listening.
    public func interruptSpeech() {
        guard isOverlayVisible, voiceOutput.isSpeaking else { return }
        voiceOutput.stop()
        interruptListener.stop()
        mouthOpenness = 0
        // Brief delay before starting mic to avoid picking up tail-end audio
        DispatchQueue.main.asyncAfter(deadline: .now() + postTTSDelay) { [weak self] in
            guard self?.isOverlayVisible == true else { return }
            guard self?.voiceOutput.isSpeaking == false else { return }
            self?.voiceInput.startListening()
        }
    }

    /// Hide the overlay, stop voice, preserve session.
    public func hideOverlay() {
        isOverlayVisible = false
        voiceInput.stopListening()
        voiceOutput.stop()
        interruptListener.stop()
        partialTranscription = ""
        lastSpokenText = ""
        pendingInputs.removeAll()
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
            lastSpokenText = TextCleaner.clean(voiceOutput.lastSpokenText)
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
        voiceOutput.resetLastSpokenText()
        // Start interrupt listener so user can say "stop" during AI speech
        interruptListener.start()

        var accumulated = ""
        var spokenUpTo = 0 // character index up to which we've queued TTS
        var sentencesSpoken = 0
        var finalText = ""

        do {
            let stream = client.chatStream(
                message: message,
                sessionID: session.sessionID,
                model: model,
                systemPrompt: voiceSystemPrompt
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
                    speakCompletedSentences(accumulated, spokenUpTo: &spokenUpTo, sentencesSpoken: &sentencesSpoken)
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
        if sentencesSpoken < maxStreamingSentences && spokenUpTo < sourceForSpeech.count {
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
    }

    /// Maximum sentences to speak during streaming before going silent.
    private let maxStreamingSentences = 3

    private func speakCompletedSentences(_ text: String, spokenUpTo: inout Int, sentencesSpoken: inout Int) {
        guard sentencesSpoken < maxStreamingSentences else { return }

        let sentenceEnders: [Character] = [".", "!", "?"]
        var lastSentenceEnd = spokenUpTo

        for i in text.indices {
            let offset = text.distance(from: text.startIndex, to: i)
            guard offset >= spokenUpTo else { continue }
            if sentenceEnders.contains(text[i]) {
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
                voiceOutput.enqueue(sentence)
                sentencesSpoken += 1
            }
            spokenUpTo = lastSentenceEnd
        }
    }

    // MARK: - Private

    private func handleVoiceInput(_ text: String) async {
        // Echo detection: if the mic picks up residual TTS audio after the delay,
        // the speech recognizer may transcribe it as user speech. Compare against
        // what Friday just said and ignore if it's an echo.
        if isLikelyEcho(text) {
            logger.warning("Echo detected, ignoring transcription: \(text.prefix(80))")
            return
        }

        // Buffer when busy: if Friday is still chatting or speaking, queue the input.
        // The pending buffer is flushed as a single combined message when TTS finishes
        // (see onFinished callback), so stacked questions get one cohesive response.
        if isChatting || voiceOutput.isSpeaking {
            logger.info("Buffering voice input while busy: \(text.prefix(80))")
            pendingInputs.append(text)
            return
        }

        await sendChat(message: text)
    }

    /// Check if transcribed text is likely an echo of Friday's own TTS output.
    /// Compares heard words against the last spoken text — if most words match,
    /// it's probably the mic picking up speaker output, not the user talking.
    private func isLikelyEcho(_ text: String) -> Bool {
        let spoken = voiceOutput.lastSpokenText.lowercased()
        guard !spoken.isEmpty else { return false }
        let heard = text.lowercased()
        let heardWords = heard.split(separator: " ").map(String.init)
        guard !heardWords.isEmpty else { return false }

        // Count how many heard words appear in the spoken text
        let matchCount = heardWords.filter { spoken.contains($0) }.count
        let matchRatio = Double(matchCount) / Double(heardWords.count)

        // If ≥60% of heard words appear in what was just spoken, treat as echo
        if matchRatio >= 0.6 {
            logger.info("Echo match: \(matchCount)/\(heardWords.count) words (\(Int(matchRatio * 100))%) match TTS output")
            return true
        }
        return false
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
                model: fastModel,
                systemPrompt: voiceSystemPrompt
            )
            greeting = response.reply
        } catch {
            greeting = "Hey. All systems running."
        }

        speakGreeting()
    }

    private func speakGreeting() {
        // Add greeting to session so it appears in ConversationView naturally.
        session.add(role: "assistant", content: greeting)
        voiceOutput.isMuted = isMuted
        voiceOutput.resetLastSpokenText()
        interruptListener.start()
        voiceOutput.speak(greeting)
        lastSpokenText = TextCleaner.clean(voiceOutput.lastSpokenText)
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
        let start = fridayConfig.activeHoursStart ?? 8
        let end = fridayConfig.activeHoursEnd ?? 22
        if hour >= end || hour < start { mode = .sleeping; return }
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

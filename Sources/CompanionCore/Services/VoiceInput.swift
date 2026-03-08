// Sources/CompanionCore/Services/VoiceInput.swift
import Foundation
import Speech
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.ask149.friday", category: "VoiceInput")

/// Wraps SFSpeechRecognizer for on-device, real-time speech-to-text.
/// Active only when the overlay is visible.
@MainActor
public final class VoiceInput {
    /// Called with partial transcription as user speaks.
    public var onPartialResult: ((String) -> Void)?
    /// Called with final transcription when user stops speaking.
    public var onFinalResult: ((String) -> Void)?
    /// Called when an error occurs.
    public var onError: ((String) -> Void)?
    /// Called when `isListening` changes — use to drive SwiftUI `@Published` proxies.
    public var onListeningChanged: ((Bool) -> Void)?

    public private(set) var isListening = false {
        didSet {
            if isListening != oldValue {
                logger.info("isListening changed: \(self.isListening)")
                onListeningChanged?(isListening)
            }
        }
    }
    public private(set) var isAuthorized = false

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    /// Timer that fires when silence is detected (no new partial results).
    private var silenceTimer: Timer?
    /// Last partial transcription text, used for silence-based finalization.
    private var lastPartialText: String = ""
    /// Silence duration before treating partial result as final (seconds).
    private let silenceTimeout: TimeInterval = 2.0
    /// Tracks consecutive recognition failures for auto-recovery.
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 3

    /// Initialize with a locale for speech recognition. Defaults to system locale.
    public init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Request microphone + speech recognition permissions.
    /// NOTE: SFSpeechRecognizer.requestAuthorization calls its completion handler
    /// on an arbitrary dispatch queue (TCC's reply queue). In Swift 6 strict
    /// concurrency mode, resuming a CheckedContinuation from a non-main-actor
    /// context inside a @MainActor-isolated async function triggers a
    /// dispatch_assert_queue_fail crash. We work around this by performing the
    /// authorization request from a nonisolated context and hopping back.
    public func requestAuthorization() async {
        let authorized = await Self.requestSpeechAuth()
        self.isAuthorized = authorized
    }

    /// Perform the actual authorization request in a nonisolated context
    /// so the continuation doesn't carry @MainActor isolation.
    private nonisolated static func requestSpeechAuth() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start listening for speech. Call only when overlay is visible.
    public func startListening() {
        logger.info("startListening() called — authorized=\(self.isAuthorized), isListening=\(self.isListening)")
        guard isAuthorized, !isListening else {
            logger.warning("startListening() blocked — authorized=\(self.isAuthorized), isListening=\(self.isListening)")
            return
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            let supportsOnDevice = speechRecognizer?.supportsOnDeviceRecognition ?? false
            logger.error("Speech recognizer not available. supportsOnDevice=\(supportsOnDevice)")
            onError?("Speech recognizer not available")
            return
        }

        logger.info("Recognizer available. supportsOnDevice=\(recognizer.supportsOnDeviceRecognition)")

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Use on-device recognition if available, with fallback to server
        if #available(macOS 13, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                logger.info("Using on-device recognition for \(recognizer.locale.identifier)")
            } else {
                // On-device model not downloaded — fall back to server recognition
                request.requiresOnDeviceRecognition = false
                logger.warning("On-device recognition not supported for \(recognizer.locale.identifier), falling back to server")
            }
        }

        recognitionRequest = request

        let inputNode = audioEngine.inputNode

        // NOTE: Voice Processing IO (setVoiceProcessingEnabled) is intentionally DISABLED.
        // It creates an aggregate device that causes the echo canceller to suppress ALL
        // mic audio (hwmic has signal at -64dB but VP output is -120dB digital silence).
        // Echo prevention is handled temporally: 1-second delay after TTS finishes
        // before restarting speech recognition.

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logger.info("Audio format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        // Guard against invalid audio format (0 channels = no mic input)
        guard recordingFormat.channelCount > 0 else {
            logger.error("Audio input format has 0 channels — microphone not available")
            onError?("Microphone not available")
            return
        }

        // Install tap via nonisolated helper — AVAudio calls the tap block
        // from its realtime queue, NOT the main thread. If the closure
        // inherits @MainActor isolation, Swift 6 will crash with
        // dispatch_assert_queue_fail / EXC_BREAKPOINT.
        Self.installAudioTap(on: inputNode, format: recordingFormat, request: request)

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            logger.info("Audio engine started, now listening")
        } catch {
            logger.error("Audio engine failed to start: \(error.localizedDescription)")
            onError?("Audio engine failed: \(error.localizedDescription)")
            return
        }

        // Recognition callback — also via nonisolated helper to avoid
        // the same @MainActor inheritance issue on the result handler queue.
        recognitionTask = Self.startRecognitionTask(
            recognizer: recognizer,
            request: request,
            onResult: { [weak self] text, isFinal in
                Task { @MainActor in
                    guard let self else { return }
                    self.consecutiveFailures = 0 // reset on any successful result
                    if isFinal {
                        logger.info("Final result: \(text.prefix(80))")
                        self.silenceTimer?.invalidate()
                        self.silenceTimer = nil
                        self.lastPartialText = ""
                        self.onFinalResult?(text)
                    } else {
                        logger.debug("Partial result: \(text.prefix(80))")
                        self.onPartialResult?(text)
                        // Reset silence timer — if no new results for 2s,
                        // treat current text as final. On-device recognition
                        // may not reliably send isFinal=true.
                        self.lastPartialText = text
                        self.resetSilenceTimer()
                    }
                }
            },
            onError: { [weak self] errorMessage in
                Task { @MainActor in
                    guard let self else { return }
                    logger.error("Recognition error: \(errorMessage)")
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = nil
                    self.consecutiveFailures += 1
                    self.stopListening()
                    // Auto-retry after transient failures (e.g., stale recognizer)
                    if self.consecutiveFailures < self.maxConsecutiveFailures {
                        logger.info("Auto-retrying startListening (attempt \(self.consecutiveFailures + 1)/\(self.maxConsecutiveFailures))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            self?.startListening()
                        }
                    } else {
                        logger.error("Max consecutive failures (\(self.maxConsecutiveFailures)) reached, giving up")
                        self.onError?("Speech recognition failed after \(self.maxConsecutiveFailures) attempts: \(errorMessage)")
                    }
                }
            }
        )
    }

    /// Install the audio tap in a nonisolated context so the closure does NOT
    /// inherit @MainActor isolation. AVAudio calls tap blocks from its
    /// RealtimeMessenger queue — Swift 6 asserts main-queue otherwise.
    private nonisolated static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    /// Start a recognition task in a nonisolated context so the result handler
    /// closure does NOT inherit @MainActor isolation.
    private nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (String, Bool) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) -> SFSpeechRecognitionTask {
        return recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                onResult(text, result.isFinal)
            }
            if let error = error {
                onError(error.localizedDescription)
            }
        }
    }

    /// Reset the silence timer. If no new partial results arrive within
    /// `silenceTimeout`, finalize the current partial text as the result.
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.lastPartialText.isEmpty else { return }
                let text = self.lastPartialText
                self.lastPartialText = ""
                self.silenceTimer = nil
                // Stop current recognition and emit as final
                self.stopListening()
                self.onFinalResult?(text)
            }
        }
    }

    /// Stop listening for speech.
    public func stopListening() {
        logger.info("stopListening() called — wasListening=\(self.isListening)")
        silenceTimer?.invalidate()
        silenceTimer = nil
        lastPartialText = ""
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    /// Reset the failure counter — call after a successful interaction cycle.
    public func resetFailureCount() {
        consecutiveFailures = 0
    }
}

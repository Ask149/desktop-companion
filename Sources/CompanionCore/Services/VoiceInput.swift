// Sources/CompanionCore/Services/VoiceInput.swift
import Foundation
import Speech
import AVFoundation

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
            if isListening != oldValue { onListeningChanged?(isListening) }
        }
    }
    public private(set) var isAuthorized = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    /// Timer that fires when silence is detected (no new partial results).
    private var silenceTimer: Timer?
    /// Last partial transcription text, used for silence-based finalization.
    private var lastPartialText: String = ""
    /// Silence duration before treating partial result as final (seconds).
    private let silenceTimeout: TimeInterval = 2.0

    public init() {}

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
        guard isAuthorized, !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?("Speech recognizer not available")
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Use on-device recognition if available (macOS 13+)
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap via nonisolated helper — AVAudio calls the tap block
        // from its realtime queue, NOT the main thread. If the closure
        // inherits @MainActor isolation, Swift 6 will crash with
        // dispatch_assert_queue_fail / EXC_BREAKPOINT.
        Self.installAudioTap(on: inputNode, format: recordingFormat, request: request)

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
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
                    if isFinal {
                        self.silenceTimer?.invalidate()
                        self.silenceTimer = nil
                        self.lastPartialText = ""
                        self.onFinalResult?(text)
                    } else {
                        self.onPartialResult?(text)
                        // Reset silence timer — if no new results for 2s,
                        // treat current text as final. On-device recognition
                        // may not reliably send isFinal=true.
                        self.lastPartialText = text
                        self.resetSilenceTimer()
                    }
                }
            },
            onError: { [weak self] in
                Task { @MainActor in
                    self?.silenceTimer?.invalidate()
                    self?.silenceTimer = nil
                    self?.stopListening()
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
        onError: @escaping @Sendable () -> Void
    ) -> SFSpeechRecognitionTask {
        return recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                onResult(text, result.isFinal)
            }
            if error != nil {
                onError()
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
}

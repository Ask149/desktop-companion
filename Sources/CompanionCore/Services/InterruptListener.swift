// Sources/CompanionCore/Services/InterruptListener.swift
import Foundation
import Speech
import AVFoundation

/// Lightweight speech listener that runs DURING TTS to detect interrupt keywords.
/// Uses its own AVAudioEngine with Voice Processing IO for echo cancellation.
@MainActor
public final class InterruptListener {
    /// Called when an interrupt keyword is detected.
    public var onInterrupt: (() -> Void)?

    public private(set) var isListening = false

    /// Keywords that trigger an interrupt (checked against last few words of partial result).
    private let keywords: Set<String> = ["stop", "friday stop", "hey friday stop", "shut up"]

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    public init() {}

    /// Start listening for interrupt keywords. Call when TTS begins.
    public func start() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode

        // Enable Voice Processing IO for echo cancellation —
        // this lets us hear the user's voice through the AI's TTS output.
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("[InterruptListener] Voice processing unavailable: \(error.localizedDescription)")
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap — nonisolated to avoid @MainActor crash on audio thread
        Self.installAudioTap(on: inputNode, format: recordingFormat, request: request)

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("[InterruptListener] Audio engine failed: \(error.localizedDescription)")
            return
        }

        // Start recognition — nonisolated to avoid @MainActor crash
        recognitionTask = Self.startRecognitionTask(
            recognizer: recognizer,
            request: request,
            onResult: { [weak self] text in
                Task { @MainActor in
                    self?.checkForKeyword(text)
                }
            },
            onError: { [weak self] in
                Task { @MainActor in
                    self?.stop()
                }
            }
        )
    }

    /// Stop listening. Call when TTS ends or interrupt detected.
    public func stop() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Keyword Detection

    private func checkForKeyword(_ transcription: String) {
        let lower = transcription.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Check last few words to avoid false positives from accumulated text
        let words = lower.split(separator: " ")
        let tail = words.suffix(4).joined(separator: " ")

        for keyword in keywords {
            if tail.contains(keyword) {
                stop()
                onInterrupt?()
                return
            }
        }
    }

    // MARK: - Nonisolated Helpers (Swift 6 Strict Concurrency)

    private nonisolated static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable () -> Void
    ) -> SFSpeechRecognitionTask {
        return recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                onResult(result.bestTranscription.formattedString)
            }
            if error != nil {
                onError()
            }
        }
    }
}

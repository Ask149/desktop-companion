// Sources/CompanionCore/Services/InterruptListener.swift
import Foundation
import Speech
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.ask149.friday", category: "InterruptListener")

/// Lightweight speech listener that runs DURING TTS to detect interrupt keywords.
/// Uses its own AVAudioEngine with Voice Processing IO for echo cancellation.
@MainActor
public final class InterruptListener {
    /// Called when an interrupt keyword is detected.
    public var onInterrupt: (() -> Void)?

    public private(set) var isListening = false

    /// Keywords that trigger an interrupt (checked against last few words of partial result).
    private let keywords: Set<String> = ["stop", "friday stop", "hey friday stop", "shut up"]

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Initialize with a locale for speech recognition. Defaults to system locale.
    public init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Start listening for interrupt keywords. Call when TTS begins.
    public func start() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            logger.warning("Interrupt listener: recognizer not available")
            return
        }

        logger.info("Starting interrupt listener")

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            } else {
                request.requiresOnDeviceRecognition = false
            }
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode

        // NOTE: Voice Processing IO is intentionally DISABLED — see VoiceInput.swift.
        // Echo cancellation is handled temporally (1s delay after TTS).

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0 else {
            logger.error("Audio input format has 0 channels")
            return
        }

        // Install tap — nonisolated to avoid @MainActor crash on audio thread
        Self.installAudioTap(on: inputNode, format: recordingFormat, request: request)

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            logger.info("Interrupt listener started")
        } catch {
            logger.error("Audio engine failed: \(error.localizedDescription)")
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
                    logger.warning("Interrupt listener recognition error, stopping")
                    self?.stop()
                }
            }
        )
    }

    /// Stop listening. Call when TTS ends or interrupt detected.
    public func stop() {
        guard isListening else { return }
        logger.info("Stopping interrupt listener")
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
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

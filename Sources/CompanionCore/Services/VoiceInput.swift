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

    public private(set) var isListening = false
    public private(set) var isAuthorized = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    public init() {}

    /// Request microphone + speech recognition permissions.
    public func requestAuthorization() async {
        // Speech recognition authorization
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        self.isAuthorized = (status == .authorized)
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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            onError?("Audio engine failed: \(error.localizedDescription)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.onFinalResult?(text)
                    } else {
                        self.onPartialResult?(text)
                    }
                }

                if error != nil {
                    self.stopListening()
                }
            }
        }
    }

    /// Stop listening for speech.
    public func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
}

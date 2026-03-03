// Sources/CompanionCore/Services/VoiceOutput.swift
import Foundation
import AVFoundation

/// Text-to-speech with mouth animation callbacks.
/// Uses AVSpeechSynthesizer for on-device, free TTS.
@MainActor
public final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate {
    /// Called when mouth should be open/closed during speech (0.0 = closed, 1.0 = fully open).
    public var onMouthUpdate: ((Double) -> Void)?
    /// Called when speech finishes.
    public var onFinished: (() -> Void)?

    public private(set) var isSpeaking = false
    public var isMuted = false

    private let synthesizer = AVSpeechSynthesizer()
    private var mouthTimer: Timer?

    /// Maximum sentences to speak (truncate long responses).
    public let maxSpokenSentences = 3

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak text aloud (unless muted). Truncates to first 3 sentences for TTS.
    public func speak(_ text: String) {
        guard !isMuted else {
            // Still call onFinished so the UI knows to stop waiting
            onFinished?()
            return
        }

        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Truncate to first N sentences for speech
        let spokenText = truncateToSentences(text, max: maxSpokenSentences)

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Try to use a good voice
        if let voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe") {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        isSpeaking = true
        startMouthAnimation()
        synthesizer.speak(utterance)
    }

    /// Stop speaking immediately.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        stopMouthAnimation()
        isSpeaking = false
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                              didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.stopMouthAnimation()
            self.isSpeaking = false
            self.onFinished?()
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                              didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.stopMouthAnimation()
            self.isSpeaking = false
        }
    }

    // MARK: - Mouth Animation

    /// Simple sinusoidal mouth oscillation at ~10Hz during speech.
    private func startMouthAnimation() {
        var phase: Double = 0
        mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                phase += 0.6
                let openness = (sin(phase) + 1) / 2 // 0.0 to 1.0
                self?.onMouthUpdate?(openness)
            }
        }
    }

    private func stopMouthAnimation() {
        mouthTimer?.invalidate()
        mouthTimer = nil
        onMouthUpdate?(0) // Close mouth
    }

    // MARK: - Private

    private func truncateToSentences(_ text: String, max: Int) -> String {
        let sentenceEnders: [Character] = [".", "!", "?"]
        var count = 0
        var endIndex = text.startIndex

        for (i, char) in text.enumerated() {
            if sentenceEnders.contains(char) {
                count += 1
                endIndex = text.index(text.startIndex, offsetBy: i + 1)
                if count >= max { break }
            }
        }

        if count == 0 {
            // No sentence enders found — return first 200 chars
            return String(text.prefix(200))
        }

        return String(text[text.startIndex..<endIndex])
    }
}

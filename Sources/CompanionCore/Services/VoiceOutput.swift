// Sources/CompanionCore/Services/VoiceOutput.swift
import Foundation
import AVFoundation

/// Text-to-speech with mouth animation callbacks.
/// Uses AVSpeechSynthesizer for on-device, free TTS.
@MainActor
public final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate {
    /// Called when mouth should be open/closed during speech (0.0 = closed, 1.0 = fully open).
    public var onMouthUpdate: ((Double) -> Void)?
    /// Called when speech finishes (all queued utterances done).
    public var onFinished: (() -> Void)?

    public private(set) var isSpeaking = false
    public var isMuted = false

    private let synthesizer = AVSpeechSynthesizer()
    private var mouthTimer: Timer?
    private var mouthPhase: Double = 0

    /// Maximum sentences to speak (truncate long responses).
    public let maxSpokenSentences = 3

    /// Number of utterances currently queued or speaking.
    private var pendingUtterances = 0

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak text aloud (unless muted). Stops any current speech first.
    /// Truncates to first 3 sentences for TTS.
    /// Use for standalone responses (greeting, non-streaming chat).
    public func speak(_ text: String) {
        guard !isMuted else {
            onFinished?()
            return
        }

        // Stop any current speech and clear queue
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        pendingUtterances = 0

        let spokenText = truncateToSentences(text, max: maxSpokenSentences)
        enqueueUtterance(spokenText)
    }

    /// Enqueue text for speaking without interrupting current speech.
    /// AVSpeechSynthesizer natively queues utterances — this method
    /// leverages that for sentence-level streaming TTS.
    public func enqueue(_ text: String) {
        guard !isMuted else { return }
        guard !text.isEmpty else { return }
        enqueueUtterance(text)
    }

    /// Stop speaking immediately and clear the queue.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingUtterances = 0
        stopMouthAnimation()
        isSpeaking = false
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                              didFinish utterance: AVSpeechUtterance) {
        let stillSpeaking = synthesizer.isSpeaking
        Task { @MainActor in
            self.pendingUtterances = max(0, self.pendingUtterances - 1)
            // Only stop animation and fire onFinished when all queued utterances are done
            if self.pendingUtterances == 0 && !stillSpeaking {
                self.stopMouthAnimation()
                self.isSpeaking = false
                self.onFinished?()
            }
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                              didCancel utterance: AVSpeechUtterance) {
        let stillSpeaking = synthesizer.isSpeaking
        Task { @MainActor in
            self.pendingUtterances = max(0, self.pendingUtterances - 1)
            // Only clean up if nothing new started (prevents race with speak()/enqueue())
            guard !stillSpeaking && self.pendingUtterances == 0 else { return }
            self.stopMouthAnimation()
            self.isSpeaking = false
        }
    }

    // MARK: - Mouth Animation

    /// Simple sinusoidal mouth oscillation at ~10Hz during speech.
    private func startMouthAnimation() {
        mouthPhase = 0
        mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mouthPhase += 0.6
                let openness = (sin(self.mouthPhase) + 1) / 2 // 0.0 to 1.0
                self.onMouthUpdate?(openness)
            }
        }
    }

    private func stopMouthAnimation() {
        mouthTimer?.invalidate()
        mouthTimer = nil
        onMouthUpdate?(0) // Close mouth
    }

    // MARK: - Private

    /// Create an utterance with consistent voice settings and enqueue it.
    private func enqueueUtterance(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Try to use a good voice
        if let voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe") {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        pendingUtterances += 1
        if !isSpeaking {
            isSpeaking = true
            startMouthAnimation()
        }
        synthesizer.speak(utterance)
    }

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
            return String(text.prefix(200))
        }

        return String(text[text.startIndex..<endIndex])
    }
}

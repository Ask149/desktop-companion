// Sources/CompanionCore/Services/EchoDetector.swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.ask149.friday", category: "EchoDetector")

/// Detects whether transcribed speech is likely an echo of Friday's own TTS output.
/// Uses word-set intersection (not substring matching) with stop-word filtering.
public enum EchoDetector {
    /// Common stop words that shouldn't count toward echo matching.
    private static let stopWords: Set<String> = [
        "i", "me", "my", "we", "you", "your", "he", "she", "it", "they",
        "a", "an", "the", "is", "am", "are", "was", "were", "be", "been",
        "do", "does", "did", "has", "have", "had", "will", "would", "could",
        "should", "can", "may", "might", "shall", "must",
        "to", "of", "in", "on", "at", "for", "with", "from", "by", "about",
        "and", "or", "but", "not", "no", "so", "if", "then", "that", "this",
        "just", "very", "really", "also", "too", "up", "out", "all", "more",
    ]

    /// Check if transcribed text is likely an echo of TTS output.
    public static func isLikelyEcho(heard: String, spoken: String) -> Bool {
        guard !spoken.isEmpty, !heard.isEmpty else { return false }

        let heardWords = extractSignificantWords(heard)
        let spokenWords = Set(extractSignificantWords(spoken))

        // If all significant words were filtered out, the heard text is entirely
        // stop words / filler. Unlikely to be a real question — treat as echo
        // when we recently spoke (spoken is non-empty).
        guard !heardWords.isEmpty else {
            logger.info("Echo (all stop words): heard='\(heard.prefix(60))'")
            return true
        }
        guard !spokenWords.isEmpty else { return false }

        let matchCount = heardWords.filter { spokenWords.contains($0) }.count
        let matchRatio = Double(matchCount) / Double(heardWords.count)

        // Adaptive threshold: shorter fragments need a lower bar because
        // one misheard word drastically changes the ratio.
        let threshold: Double = heardWords.count <= 3 ? 0.6 : 0.5

        if matchRatio >= threshold {
            logger.info("Echo detected: \(matchCount)/\(heardWords.count) words (\(Int(matchRatio * 100))%, threshold \(Int(threshold * 100))%)")
            return true
        }
        logger.debug("Not echo: \(matchCount)/\(heardWords.count) words (\(Int(matchRatio * 100))%, threshold \(Int(threshold * 100))%) heard='\(heard.prefix(60))'")
        return false
    }

    private static func extractSignificantWords(_ text: String) -> [String] {
        text.lowercased()
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }
}

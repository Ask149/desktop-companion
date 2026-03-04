// Sources/CompanionCore/TextCleaner.swift
import Foundation

/// Unified text cleaning for display and TTS.
/// Strips markdown syntax, emojis, and other non-spoken artifacts.
public enum TextCleaner {
    /// Clean text for display and TTS — strips markdown and emojis.
    public static func clean(_ text: String) -> String {
        var result = text
        // Bold: **text** → text
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        // Italic: *text* → text
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        // Stray asterisks (unclosed bold/italic)
        result = result.replacingOccurrences(of: "*", with: "")
        // Headers: # Heading → Heading
        result = result.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        // Inline code: `code` → code
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Code fences: ``` → (remove)
        result = result.replacingOccurrences(of: "```[^\\n]*\\n?", with: "", options: .regularExpression)
        // Links: [text](url) → text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // List markers: - item or * item → item (asterisks already removed above)
        result = result.replacingOccurrences(of: "(?m)^[\\-]\\s+", with: "", options: .regularExpression)
        // Blockquotes: > text → text
        result = result.replacingOccurrences(of: "(?m)^>\\s+", with: "", options: .regularExpression)
        // Strip emojis (keep ASCII chars like digits and punctuation)
        result = result.unicodeScalars.filter { !$0.properties.isEmoji || $0.isASCII }.map(String.init).joined()
        // Collapse multiple spaces/newlines
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

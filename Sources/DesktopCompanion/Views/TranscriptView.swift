// Sources/DesktopCompanion/Views/TranscriptView.swift
import SwiftUI
import CompanionCore

/// Shows conversation transcript below the face on the overlay.
/// User speech appears on the right, Friday's responses on the left.
struct TranscriptView: View {
    let messages: [SessionStore.Message]
    let partialTranscription: String
    let partialAssistantResponse: String
    let streamStatus: String

    var body: some View {
        VStack(spacing: 8) {
            // Show last few messages
            ForEach(Array(recentMessages.enumerated()), id: \.offset) { _, msg in
                HStack {
                    if msg.role == "user" {
                        Spacer()
                        markdownText(msg.content)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.1))
                            )
                            .frame(maxWidth: 500, alignment: .trailing)
                    } else {
                        markdownText(msg.content)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: 500, alignment: .leading)
                        Spacer()
                    }
                }
            }

            // Show streaming assistant response (growing bubble)
            if !partialAssistantResponse.isEmpty {
                HStack {
                    markdownText(partialAssistantResponse)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: 500, alignment: .leading)
                        .animation(.easeOut(duration: 0.1), value: partialAssistantResponse)
                    Spacer()
                }
            }

            // Show stream status (tool use, thinking, etc.)
            if !streamStatus.isEmpty {
                Text(streamStatus)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .transition(.opacity)
            }

            // Show live transcription (partial)
            if !partialTranscription.isEmpty {
                HStack {
                    Spacer()
                    Text(partialTranscription)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .italic()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.05))
                        )
                        .frame(maxWidth: 500, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 40)
    }

    /// Show only the last 4 messages to keep the overlay clean.
    private var recentMessages: [SessionStore.Message] {
        Array(messages.suffix(4))
    }

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        Text(Self.stripForDisplay(text))
    }

    /// Strip markdown syntax and emojis for clean voice-UI display.
    private static func stripForDisplay(_ text: String) -> String {
        var result = text
        // Bold: **text** → text
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        // Italic: *text* → text
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        // Stray asterisks (unclosed bold/italic)
        result = result.replacingOccurrences(of: "\\*", with: "")
        // Headers: # Heading → Heading
        result = result.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        // Inline code: `code` → code
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Code fences: ``` → (remove)
        result = result.replacingOccurrences(of: "```[^\\n]*\\n?", with: "", options: .regularExpression)
        // Links: [text](url) → text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // List markers: - item → item
        result = result.replacingOccurrences(of: "(?m)^[\\-]\\s+", with: "", options: .regularExpression)
        // Blockquotes: > text → text
        result = result.replacingOccurrences(of: "(?m)^>\\s+", with: "", options: .regularExpression)
        // Strip emojis (keep ASCII chars like digits and punctuation)
        result = result.unicodeScalars.filter { !$0.properties.isEmoji || $0.isASCII }.map(String.init).joined()
        return result
    }
}

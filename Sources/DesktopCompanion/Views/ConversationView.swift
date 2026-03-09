// Sources/DesktopCompanion/Views/ConversationView.swift
import SwiftUI
import CompanionCore

/// Unified conversation view for the overlay — replaces the separate
/// StreamingTextView + TranscriptView with a single, bottom-anchored
/// scrolling conversation. Latest assistant message is visually prominent
/// (title3, high opacity, no bubble); older messages progressively dim.
struct ConversationView: View {
    let messages: [SessionStore.Message]
    let partialTranscription: String
    let partialAssistantResponse: String
    let streamStatus: String
    let isChatting: Bool
    var mood: Mood = .calm

    var body: some View {
        let expr = mood.expression
        let c = expr.color
        let moodColor = Color(red: c.red, green: c.green, blue: c.blue)

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // Top spacer pushes content to bottom when conversation is short
                    Spacer(minLength: 0)

                    // Older messages (all but the latest assistant)
                    ForEach(Array(olderMessages.enumerated()), id: \.element.stableID) { index, msg in
                        OlderMessageRow(
                            message: msg,
                            moodColor: moodColor,
                            opacity: opacityForOlderMessage(at: index, total: olderMessages.count)
                        )
                        .id(msg.stableID)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: msg.role == "user" ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .opacity.combined(with: .move(edge: .top))
                            )
                        )
                    }

                    // Latest assistant message — prominent hero style
                    if let latest = latestAssistantMessage, partialAssistantResponse.isEmpty {
                        LatestAssistantRow(text: latest.content, moodColor: moodColor)
                            .id(latest.stableID)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Streaming response — animates in as the hero text
                    if !partialAssistantResponse.isEmpty {
                        LatestAssistantRow(
                            text: partialAssistantResponse,
                            moodColor: moodColor,
                            isStreaming: true
                        )
                        .id("streaming")
                        .transition(.opacity)
                    }

                    // Stream status (e.g., "Using tool...")
                    if !streamStatus.isEmpty {
                        Text(streamStatus)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                            .transition(.opacity)
                            .id("status")
                    }

                    // Thinking dots — inline in conversation flow
                    if isChatting && partialAssistantResponse.isEmpty {
                        HStack {
                            ThinkingDotsView(mood: mood)
                            Spacer()
                        }
                        .padding(.leading, 4)
                        .transition(.opacity)
                        .id("thinking")
                    }

                    // Partial transcription — pulsing, right-aligned
                    if !partialTranscription.isEmpty {
                        HStack {
                            Spacer()
                            ConversationPulsingText(text: partialTranscription)
                        }
                        .id("transcription")
                    }

                    // Scroll anchor
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 40)
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottom)
            }
            .mask(
                VStack(spacing: 0) {
                    // Fade out at top so older messages dissolve
                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                    Color.white
                }
            )
            .onChange(of: messages.count) { _, _ in
                withAnimation(FridayAnimation.standard) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: partialAssistantResponse) { _, _ in
                withAnimation(FridayAnimation.micro) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: partialTranscription) { _, _ in
                withAnimation(FridayAnimation.micro) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .animation(FridayAnimation.standard, value: messages.count)
    }

    // MARK: - Message Partitioning

    /// The latest assistant message (shown in hero style).
    private var latestAssistantMessage: SessionStore.Message? {
        messages.last(where: { $0.role == "assistant" })
    }

    /// All messages except the latest assistant (shown in dimmed style).
    /// Keeps only recent messages to avoid scrolling overload.
    private var olderMessages: [SessionStore.Message] {
        guard let latest = latestAssistantMessage else {
            // No assistant messages yet — show all user messages
            return Array(messages.suffix(6))
        }
        // Remove the latest assistant message, keep recent context
        let withoutLatest = messages.filter { $0.stableID != latest.stableID }
        return Array(withoutLatest.suffix(6))
    }

    /// Progressive opacity: older messages are more transparent.
    private func opacityForOlderMessage(at index: Int, total: Int) -> Double {
        guard total > 1 else { return 0.5 }
        // Newest older message: 0.5, oldest: 0.25
        let position = Double(index) / Double(total - 1)
        return 0.25 + (1.0 - position) * 0.25
    }
}

// MARK: - Older Message Row

/// Older messages with subtle glass bubbles and reduced opacity.
private struct OlderMessageRow: View {
    let message: SessionStore.Message
    let moodColor: Color
    let opacity: Double

    var body: some View {
        let isUser = message.role == "user"

        HStack {
            if isUser { Spacer() }

            Text(TextCleaner.clean(message.content))
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(opacity))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isUser ? moodColor.opacity(0.08) : .white.opacity(0.04))
                        .overlay(
                            isUser
                                ? RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(moodColor.opacity(0.1), lineWidth: 1)
                                : nil
                        )
                )
                .frame(maxWidth: maxBubbleWidth, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer() }
        }
    }

    private var maxBubbleWidth: CGFloat {
        min(500, (NSScreen.main?.frame.width ?? 1440) * 0.4)
    }
}

// MARK: - Latest Assistant Row (Hero Style)

/// The most recent assistant message — prominent, no bubble, hero typography.
private struct LatestAssistantRow: View {
    let text: String
    let moodColor: Color
    var isStreaming: Bool = false

    var body: some View {
        Text(TextCleaner.clean(text))
            .font(.system(.title3, design: .rounded, weight: .medium))
            .foregroundStyle(.white.opacity(isStreaming ? 0.7 : 0.9))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: moodColor.opacity(0.15), radius: 12, x: 0, y: 0)
            .animation(FridayAnimation.micro, value: text)
    }
}

// MARK: - Pulsing Transcription (Conversation variant)

/// Live transcription text that pulses to indicate active listening.
private struct ConversationPulsingText: View {
    let text: String
    @State private var pulse = false

    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.white.opacity(pulse ? 0.5 : 0.3))
            .italic()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.04))
            )
            .frame(
                maxWidth: min(500, (NSScreen.main?.frame.width ?? 1440) * 0.4),
                alignment: .trailing
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

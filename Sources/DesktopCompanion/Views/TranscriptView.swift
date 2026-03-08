// Sources/DesktopCompanion/Views/TranscriptView.swift
import SwiftUI
import CompanionCore

/// Conversation transcript with slide-in animations, glass bubbles, and smooth scroll.
struct TranscriptView: View {
    let messages: [SessionStore.Message]
    let partialTranscription: String
    let partialAssistantResponse: String
    let streamStatus: String
    var mood: Mood = .calm

    var body: some View {
        let expr = mood.expression
        let c = expr.color
        let moodColor = Color(red: c.red, green: c.green, blue: c.blue)

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(recentMessages, id: \.stableID) { msg in
                        MessageBubble(
                            message: msg,
                            moodColor: moodColor
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

                    // Streaming assistant response
                    if !partialAssistantResponse.isEmpty {
                        HStack {
                            Text(TextCleaner.clean(partialAssistantResponse))
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.white.opacity(0.06))
                                )
                                .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                                .animation(FridayAnimation.micro, value: partialAssistantResponse)
                            Spacer()
                        }
                        .id("streaming")
                    }

                    // Stream status
                    if !streamStatus.isEmpty {
                        Text(streamStatus)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .transition(.opacity)
                            .id("status")
                    }

                    // Live transcription (pulsing)
                    if !partialTranscription.isEmpty {
                        HStack {
                            Spacer()
                            PulsingTranscription(text: partialTranscription)
                        }
                        .id("transcription")
                    }

                    // Scroll anchor
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 40)
            }
            .frame(maxHeight: 220)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
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
        }
        .animation(FridayAnimation.standard, value: messages.count)
    }

    private var recentMessages: [SessionStore.Message] {
        Array(messages.suffix(5))
    }

    private var maxBubbleWidth: CGFloat {
        min(500, (NSScreen.main?.frame.width ?? 1440) * 0.4)
    }
}

// MARK: - Stable Identity for ForEach

extension SessionStore.Message {
    /// Stable identity derived from role + timestamp, survives .suffix() re-indexing.
    var stableID: String {
        "\(role)-\(timestamp.timeIntervalSinceReferenceDate)"
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: SessionStore.Message
    let moodColor: Color

    var body: some View {
        let isUser = message.role == "user"

        HStack {
            if isUser { Spacer() }

            Text(TextCleaner.clean(message.content))
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(isUser ? 0.8 : 0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isUser ? moodColor.opacity(0.12) : .white.opacity(0.06))
                        .overlay(
                            isUser
                                ? RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(moodColor.opacity(0.15), lineWidth: 1)
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

// MARK: - Pulsing Transcription

private struct PulsingTranscription: View {
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
            .frame(maxWidth: min(500, (NSScreen.main?.frame.width ?? 1440) * 0.4),
                   alignment: .trailing)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

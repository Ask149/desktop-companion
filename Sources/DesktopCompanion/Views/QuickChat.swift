// Sources/DesktopCompanion/Views/QuickChat.swift
import SwiftUI
import CompanionCore

struct QuickChat: View {
    @ObservedObject var state: CompanionState
    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick Chat", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if !state.chatResponse.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(state.chatResponse.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            if !paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
                                if let attributed = try? AttributedString(markdown: paragraph) {
                                    Text(attributed)
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .lineSpacing(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } else {
                                    Text(paragraph)
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .lineSpacing(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            HStack(spacing: 8) {
                TextField("Ask something…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .onSubmit { send() }

                Button(action: send) {
                    Group {
                        if state.isChatting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .imageScale(.large)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .disabled(input.isEmpty || state.isChatting)
                .buttonStyle(.borderless)
                .foregroundStyle(input.isEmpty ? Color.gray : Color.accentColor)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func send() {
        let message = input
        input = ""
        Task {
            await state.sendChat(message: message)
        }
    }
}

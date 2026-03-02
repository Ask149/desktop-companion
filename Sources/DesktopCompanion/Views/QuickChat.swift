// Sources/DesktopCompanion/Views/QuickChat.swift
import SwiftUI
import CompanionCore

struct QuickChat: View {
    @ObservedObject var state: CompanionState
    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Chat")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if !state.chatResponse.isEmpty {
                ScrollView {
                    if let attributed = try? AttributedString(markdown: state.chatResponse) {
                        Text(attributed)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    } else {
                        // Fallback if markdown parsing fails
                        Text(state.chatResponse)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }
                }
                .frame(maxHeight: 100)
            }

            HStack {
                TextField("Ask something...", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { send() }

                Button(action: send) {
                    if state.isChatting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(input.isEmpty || state.isChatting)
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func send() {
        let message = input
        input = ""
        Task {
            await state.sendChat(message: message)
        }
    }
}

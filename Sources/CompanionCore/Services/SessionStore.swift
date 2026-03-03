// Sources/CompanionCore/Services/SessionStore.swift
import Foundation

/// In-memory conversation store that persists across overlay dismiss/summon cycles.
/// One session per day, auto-rotates at midnight.
@MainActor
public final class SessionStore {
    public struct Message: Sendable {
        public let role: String   // "user" or "assistant"
        public let content: String
        public let timestamp: Date

        public init(role: String, content: String, timestamp: Date = Date()) {
            self.role = role
            self.content = content
            self.timestamp = timestamp
        }
    }

    public private(set) var messages: [Message] = []
    /// Called whenever messages change — use to drive SwiftUI `@Published` proxies.
    public var onMessagesChanged: (([Message]) -> Void)?
    private var currentDate: String

    /// The session ID sent to aidaemon (one per day).
    public var sessionID: String { "friday-\(currentDate)" }

    public init() {
        self.currentDate = Self.todayString()
    }

    /// Add a message to the session.
    public func add(role: String, content: String) {
        rotateIfNeeded()
        messages.append(Message(role: role, content: content, timestamp: Date()))
        onMessagesChanged?(messages)
    }

    /// Clear the current session (e.g., user explicitly resets).
    public func clear() {
        messages.removeAll()
        onMessagesChanged?(messages)
    }

    /// Restore messages from aidaemon's session history (e.g., after app restart).
    /// Only restores if messages is non-empty; does not clear existing messages on empty input.
    public func restore(from restored: [Message]) {
        guard !restored.isEmpty else { return }
        messages = restored
        onMessagesChanged?(messages)
    }

    /// Check if there's prior conversation context (for "welcome back" greeting).
    public var hasHistory: Bool { !messages.isEmpty }

    /// Last assistant message (for display).
    public var lastResponse: String? {
        messages.last(where: { $0.role == "assistant" })?.content
    }

    // MARK: - Private

    private func rotateIfNeeded() {
        let today = Self.todayString()
        if today != currentDate {
            messages.removeAll()
            currentDate = today
            onMessagesChanged?(messages)
        }
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

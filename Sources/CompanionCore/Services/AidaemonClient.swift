// Sources/CompanionCore/Services/AidaemonClient.swift
import Foundation

/// HTTP client for aidaemon's REST API (port 8420).
public final class AidaemonClient: Sendable {
    public let baseURL: URL
    public let token: String
    private let session: URLSession

    /// Health check response from GET /health.
    public struct HealthResponse: Codable, Sendable {
        public let status: String
        public let model: String
    }

    /// Chat response from POST /chat.
    public struct ChatResponse: Codable, Sendable {
        public let reply: String
        public let toolCalls: [String]?

        enum CodingKeys: String, CodingKey {
            case reply
            case toolCalls = "tool_calls"
        }
    }

    /// Message from GET /sessions/{id}/messages.
    public struct SessionMessage: Codable, Sendable {
        public let role: String
        public let content: String
        public let createdAt: String

        enum CodingKeys: String, CodingKey {
            case role, content
            case createdAt = "created_at"
        }
    }

    public init(port: Int, token: String) {
        self.baseURL = URL(string: "http://localhost:\(port)")!
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // LLM calls can take 30-60s
        self.session = URLSession(configuration: config)
    }

    /// Convenience initializer from aidaemon config.
    public convenience init?(config: AidaemonConfig) {
        self.init(port: config.port, token: config.apiToken)
    }

    // MARK: - Health Check

    /// Check if aidaemon is alive. Returns nil if unreachable.
    public func checkHealth() async -> HealthResponse? {
        let url = baseURL.appendingPathComponent("health")
        guard let (data, response) = try? await session.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(HealthResponse.self, from: data)
    }

    // MARK: - Chat

    /// Send a chat message and get a response.
    public func chat(message: String, sessionID: String = "companion", model: String? = nil) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // LLM can take a while

        var body: [String: String] = ["message": message, "session_id": sessionID]
        if let model = model {
            body["model"] = model
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AidaemonClient", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: errorBody])
        }

        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    // MARK: - Streaming Chat

    /// A single SSE event from the streaming chat endpoint.
    public enum StreamEvent: Sendable {
        case status(String)                         // "Processing...", "🤔 Thinking..."
        case toolUse(name: String, message: String) // tool being executed
        case delta(String)                          // partial response text chunk
        case done(text: String, toolCalls: [String]) // final complete response
        case error(String)                          // error message
    }

    /// SSE payload from aidaemon (matches Go sseEvent struct).
    private struct SSEPayload: Codable {
        let type: String
        let text: String?
        let name: String?
        let message: String?
        let toolCalls: [String]?

        enum CodingKeys: String, CodingKey {
            case type, text, name, message
            case toolCalls = "tool_calls"
        }
    }

    /// Stream a chat response via SSE. Yields events as they arrive.
    /// The caller should accumulate delta events to build the partial response.
    public func chatStream(
        message: String,
        sessionID: String = "companion",
        model: String? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlComponents = URLComponents(url: baseURL.appendingPathComponent("chat"), resolvingAgainstBaseURL: false)!
                    urlComponents.queryItems = [URLQueryItem(name: "stream", value: "true")]

                    var request = URLRequest(url: urlComponents.url!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 120

                    var body: [String: String] = ["message": message, "session_id": sessionID]
                    if let model = model {
                        body["model"] = model
                    }
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw NSError(domain: "AidaemonClient", code: code,
                                     userInfo: [NSLocalizedDescriptionKey: "SSE stream failed with status \(code)"])
                    }

                    for try await line in bytes.lines {
                        // SSE format: "data: {json}"
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard let jsonData = jsonStr.data(using: .utf8),
                              let payload = try? JSONDecoder().decode(SSEPayload.self, from: jsonData) else {
                            continue
                        }

                        let event: StreamEvent
                        switch payload.type {
                        case "status":
                            event = .status(payload.text ?? "")
                        case "tool_use":
                            event = .toolUse(name: payload.name ?? "tool", message: payload.message ?? "")
                        case "delta":
                            event = .delta(payload.text ?? "")
                        case "done":
                            event = .done(text: payload.text ?? "", toolCalls: payload.toolCalls ?? [])
                        case "error":
                            event = .error(payload.text ?? "Unknown error")
                        default:
                            continue
                        }
                        continuation.yield(event)

                        // done and error are terminal events
                        if payload.type == "done" || payload.type == "error" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Session History

    /// Fetch session messages from aidaemon (for restoring history on launch).
    /// Returns empty array if session doesn't exist or aidaemon is unreachable.
    public func getSessionMessages(sessionID: String) async -> [SessionMessage] {
        let url = baseURL.appendingPathComponent("sessions/\(sessionID)/messages")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return []
        }
        return (try? JSONDecoder().decode([SessionMessage].self, from: data)) ?? []
    }
}

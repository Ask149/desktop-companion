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

    public init(port: Int, token: String) {
        self.baseURL = URL(string: "http://localhost:\(port)")!
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
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
}

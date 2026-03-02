// Sources/CompanionCore/Services/ConfigLoader.swift
import Foundation

/// Reads aidaemon's config to get API token and port.
public struct AidaemonConfig: Codable, Sendable {
    public let port: Int
    public let apiToken: String

    enum CodingKeys: String, CodingKey {
        case port
        case apiToken = "api_token"
    }

    /// Load from ~/.config/aidaemon/config.json
    public static func load() -> AidaemonConfig? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configPath = home.appendingPathComponent(".config/aidaemon/config.json")
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(AidaemonConfig.self, from: data)
    }

    /// Decode from raw JSON data (useful for testing).
    public static func decode(from data: Data) -> AidaemonConfig? {
        return try? JSONDecoder().decode(AidaemonConfig.self, from: data)
    }
}

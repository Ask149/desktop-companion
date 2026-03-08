// Sources/CompanionCore/Services/FridayConfig.swift
import Foundation

/// Friday-specific configuration loaded from ~/.config/friday/config.json.
/// All fields are optional — sensible defaults are used when absent.
public struct FridayConfig: Codable, Sendable {
    /// User's name for voice prompts (default: "the user").
    public var userName: String?
    /// Locale identifier for speech recognition, e.g. "en-US" (default: system locale).
    public var locale: String?
    /// AVSpeechSynthesisVoice identifier, e.g. "com.apple.voice.premium.en-US.Zoe" (default: system voice).
    public var voiceIdentifier: String?
    /// Hour (0-23) when idle detection starts (default: 8).
    public var activeHoursStart: Int?
    /// Hour (0-23) when idle detection stops (default: 22).
    public var activeHoursEnd: Int?
    /// Directory for heartbeat state files (default: ~/.config/aidaemon/heartbeat/state).
    public var heartbeatStateDir: String?
    /// Directory for notes files (default: ~/.config/aidaemon/notes).
    public var notesDir: String?

    /// Load from ~/.config/friday/config.json. Returns empty config (all defaults) if file is missing.
    public static func load() -> FridayConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configPath = home.appendingPathComponent(".config/friday/config.json")
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(FridayConfig.self, from: data)
        else { return FridayConfig() }
        return config
    }

    public init() {}
}

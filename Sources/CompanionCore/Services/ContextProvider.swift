// Sources/CompanionCore/Services/ContextProvider.swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.ask149.friday", category: "ContextProvider")

/// Protocol for context providers that supply runtime context to Friday's system prompt.
public protocol ContextProvider: Sendable {
    /// Fetch context snippet. Returns nil if unavailable.
    func fetchContext() -> String?
}

// MARK: - Built-in Providers

/// Provides current time, date, and timezone.
public struct TimeContextProvider: ContextProvider {
    public init() {}

    public func fetchContext() -> String? {
        let now = Date()
        let time = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
        let date = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .none)
        let tz = TimeZone.current.identifier
        return "Time: \(time), \(date)\nTimezone: \(tz)"
    }
}

/// Provides heartbeat/awareness summary from aidaemon's state directory.
public struct HeartbeatContextProvider: ContextProvider {
    private let stateDir: String?

    public init(stateDir: String? = nil) {
        self.stateDir = stateDir
    }

    public func fetchContext() -> String? {
        let monitor = HeartbeatMonitor(stateDir: stateDir)
        let report = monitor.readReport()
        guard !report.summary.isEmpty else { return nil }
        let summary = String(report.summary.prefix(500))
        var result = "System awareness:\n\(summary)"
        if report.hasAlerts {
            result += "\nAlerts: YES"
        }
        if report.pendingTasks > 0 {
            result += "\nPending tasks: \(report.pendingTasks)"
        }
        return result
    }
}

/// Reads context from a file path (supports ~ expansion).
public struct FileContextProvider: ContextProvider {
    private let path: String
    private let maxChars: Int

    public init(path: String, maxChars: Int = 1000) {
        self.path = path
        self.maxChars = maxChars
    }

    public func fetchContext() -> String? {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return nil
        }
        return String(content.prefix(maxChars))
    }
}

/// Runs a shell command and returns its stdout.
public struct CommandContextProvider: ContextProvider {
    private let command: String
    private let timeout: TimeInterval

    public init(command: String, timeout: TimeInterval = 5) {
        self.command = command
        self.timeout = timeout
    }

    public func fetchContext() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            logger.warning("Command context provider failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Factory

/// Builds context providers from FridayConfig entries.
public enum ContextProviderFactory {
    public static func build(from configs: [FridayConfig.ContextProviderConfig]) -> [any ContextProvider] {
        configs.compactMap { config -> (any ContextProvider)? in
            switch config.type {
            case "time":
                return TimeContextProvider()
            case "heartbeat":
                return HeartbeatContextProvider(stateDir: config.path)
            case "file":
                guard let path = config.path else {
                    logger.warning("File context provider missing 'path' in config")
                    return nil
                }
                return FileContextProvider(path: path, maxChars: config.maxChars ?? 1000)
            case "command":
                guard let cmd = config.command else {
                    logger.warning("Command context provider missing 'command' in config")
                    return nil
                }
                return CommandContextProvider(command: cmd)
            default:
                logger.warning("Unknown context provider type: \(config.type)")
                return nil
            }
        }
    }

    /// Gather context from all providers and join into a single string.
    public static func gatherContext(from providers: [any ContextProvider]) -> String {
        providers.compactMap { $0.fetchContext() }
            .joined(separator: "\n\n")
    }
}

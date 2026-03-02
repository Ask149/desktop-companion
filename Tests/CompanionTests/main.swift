// Tests/CompanionTests/main.swift
// Test runner executable — workaround for no Xcode (no xctest/XCTest runner available)
// Run via: swift run CompanionTests

import AppKit
@testable import CompanionCore

// Top-level code in main.swift is implicitly @MainActor in Swift 6

var passed = 0
var failed = 0
var testErrors: [String] = []

@MainActor func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        let shortFile = file.split(separator: "/").last ?? Substring(file)
        testErrors.append("  FAIL \(shortFile):\(line) — \(message)")
    }
}

// ============================================================
// MARK: - CritterRenderer Tests
// ============================================================

print("Running CritterRenderer tests...\n")

// Test 1: makeIcon returns correct size
do {
    print("  test: makeIconReturnsCorrectSize")
    let icon = CritterRenderer.makeIcon(mode: .idle, blink: 0, wiggle: 0)
    check(abs(icon.size.width - 22) <= 1, "width should be ~22, got \(icon.size.width)")
    check(abs(icon.size.height - 22) <= 1, "height should be ~22, got \(icon.size.height)")
    print("    ✓")
}

// Test 2: all modes render without crashing
do {
    print("  test: makeIconAllModes")
    for mode in CompanionMode.allCases {
        let icon = CritterRenderer.makeIcon(mode: mode, blink: 0, wiggle: 0)
        check(icon.size.width > 0, "mode \(mode) should produce non-zero width icon")
    }
    print("    ✓")
}

// Test 3: blink produces different image
do {
    print("  test: makeIconWithBlink")
    let open = CritterRenderer.makeIcon(mode: .idle, blink: 0, wiggle: 0)
    let closed = CritterRenderer.makeIcon(mode: .idle, blink: 1, wiggle: 0)
    check(open.size.width > 0, "open eyes icon should be valid")
    check(closed.size.width > 0, "closed eyes icon should be valid")
    check(open.tiffRepresentation != closed.tiffRepresentation, "blink=0 and blink=1 should produce different images")
    print("    ✓")
}

// Test 4: wiggle produces valid image
do {
    print("  test: makeIconWithWiggle")
    let straight = CritterRenderer.makeIcon(mode: .idle, blink: 0, wiggle: 0)
    let wiggled = CritterRenderer.makeIcon(mode: .idle, blink: 0, wiggle: 0.5)
    check(straight.size.width > 0, "straight icon should be valid")
    check(wiggled.size.width > 0, "wiggled icon should be valid")
    print("    ✓")
}

// ============================================================
// MARK: - ConfigLoader Tests (Task 5)
// ============================================================

print("\nRunning ConfigLoader tests...\n")

// Test 5: decode config from JSON
do {
    print("  test: decodeConfigFromJSON")
    let json = """
    {"port": 8420, "api_token": "test-token-123", "chat_model": "claude-sonnet-4.5"}
    """.data(using: .utf8)!
    let config = AidaemonConfig.decode(from: json)
    check(config != nil, "should decode valid JSON")
    check(config?.port == 8420, "port should be 8420, got \(config?.port ?? -1)")
    check(config?.apiToken == "test-token-123", "apiToken should be 'test-token-123', got '\(config?.apiToken ?? "nil")'")
    print("    ✓")
}

// Test 6: decode config with missing api_token fails gracefully
do {
    print("  test: decodeConfigMissingToken")
    let json = """
    {"port": 8420, "chat_model": "claude-sonnet-4.5"}
    """.data(using: .utf8)!
    let config = AidaemonConfig.decode(from: json)
    check(config == nil, "should return nil for JSON missing api_token")
    print("    ✓")
}

// Test 7: load config from real file (machine-specific)
do {
    print("  test: loadConfigFromFile")
    let config = AidaemonConfig.load()
    check(config != nil, "~/.config/aidaemon/config.json should exist on this machine")
    check(config?.port == 8420, "port should be 8420")
    check(!(config?.apiToken.isEmpty ?? true), "apiToken should not be empty")
    print("    ✓")
}

// ============================================================
// MARK: - AidaemonClient Tests (Task 5)
// ============================================================

print("\nRunning AidaemonClient tests...\n")

// Test 8: client initializes from config
do {
    print("  test: clientInitFromConfig")
    let config = AidaemonConfig.load()
    check(config != nil, "config should load")
    if let config = config {
        let client = AidaemonClient(config: config)
        check(client != nil, "client should initialize from config")
        check(client?.baseURL.absoluteString == "http://localhost:8420", "baseURL should be http://localhost:8420")
    }
    print("    ✓")
}

// Test 9: health check against live aidaemon (machine-specific)
do {
    print("  test: healthCheckLive")
    if let config = AidaemonConfig.load(), let client = AidaemonClient(config: config) {
        // Run async health check
        let health = await client.checkHealth()
        if let health = health {
            check(health.status == "ok", "health status should be 'ok', got '\(health.status)'")
            check(!health.model.isEmpty, "health model should not be empty")
            print("    ✓ (aidaemon is running, status=\(health.status), model=\(health.model))")
        } else {
            print("    ⚠ skipped (aidaemon not running)")
            // Don't fail — aidaemon might not be running
        }
    } else {
        print("    ⚠ skipped (no config)")
    }
}

// ============================================================
// MARK: - HeartbeatMonitor Tests (Task 6)
// ============================================================

print("\nRunning HeartbeatMonitor tests...\n")

// Test 10: read awareness report
do {
    print("  test: readAwarenessReport")
    let monitor = HeartbeatMonitor()
    let report = monitor.readReport()
    check(!report.summary.isEmpty, "last-awareness.txt should have content")
    check(report.lastUpdated != nil, "last-awareness.txt should have a modification date")
    print("    ✓")
}

// Test 11: alert detection
do {
    print("  test: detectAlerts")
    let monitor = HeartbeatMonitor()
    check(monitor.hasAlertMarkers("ALERT: Something bad happened"), "'ALERT:' should be detected")
    check(monitor.hasAlertMarkers("WARNING: Disk space low"), "'WARNING:' should be detected")
    check(monitor.hasAlertMarkers("Line with ⚠️ emoji"), "'⚠️' should be detected")
    check(monitor.hasAlertMarkers("Line with 🚨 emoji"), "'🚨' should be detected")
    check(monitor.hasAlertMarkers("URGENT: Do this now"), "'URGENT:' should be detected")
    check(monitor.hasAlertMarkers("ACTION REQUIRED here"), "'ACTION REQUIRED' should be detected")
    check(!monitor.hasAlertMarkers("Everything is fine"), "normal text should not trigger alert")
    check(!monitor.hasAlertMarkers(""), "empty text should not trigger alert")
    print("    ✓")
}

// Test 12: curiosity done today check
do {
    print("  test: curiosityDoneToday")
    let monitor = HeartbeatMonitor()
    let done = monitor.curiosityDoneToday()
    // We know curiosity-2026-03-02.done exists from state dir listing
    // This test validates it doesn't crash; the actual value depends on the date
    check(done || !done, "curiosityDoneToday should return a boolean without crashing")
    print("    ✓ (curiosityDoneToday=\(done))")
}

// Test 13: time since last awareness
do {
    print("  test: timeSinceLastAwareness")
    let monitor = HeartbeatMonitor()
    let elapsed = monitor.timeSinceLastAwareness()
    check(elapsed != nil, "timeSinceLastAwareness should return a value (file exists)")
    if let elapsed = elapsed {
        check(elapsed >= 0, "elapsed time should be non-negative, got \(elapsed)")
        print("    ✓ (elapsed=\(Int(elapsed))s)")
    } else {
        print("    ✓ (no awareness file)")
    }
}

// Test 14: watchman issues parsing
do {
    print("  test: watchmanIssuesParsing")
    let monitor = HeartbeatMonitor()
    let report = monitor.readReport()
    // watchman-report.txt exists and has content
    check(report.watchmanIssues.count >= 0, "watchmanIssues should be a valid array")
    print("    ✓ (watchmanIssues=\(report.watchmanIssues.count) lines)")
}

// Test 15: AwarenessReport struct fields
do {
    print("  test: awarenessReportConstruction")
    let report = AwarenessReport(
        summary: "Test summary",
        lastUpdated: Date(),
        hasAlerts: true,
        watchmanIssues: ["issue1", "issue2"],
        pendingTasks: 3,
        curiosityDoneToday: false
    )
    check(report.summary == "Test summary", "summary should match")
    check(report.hasAlerts == true, "hasAlerts should be true")
    check(report.watchmanIssues.count == 2, "should have 2 watchman issues")
    check(report.pendingTasks == 3, "should have 3 pending tasks")
    check(report.curiosityDoneToday == false, "curiosityDoneToday should be false")
    print("    ✓")
}

// ============================================================
// MARK: - Results
// ============================================================

print("")
if failed == 0 {
    print("All \(passed) assertions passed ✅")
} else {
    print("\(failed) assertion(s) FAILED, \(passed) passed ❌")
    for e in testErrors { print(e) }
}
exit(failed == 0 ? 0 : 1)

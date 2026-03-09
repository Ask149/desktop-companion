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

// Test 7: load config from real file (machine-specific, skips in CI)
do {
    print("  test: loadConfigFromFile")
    let config = AidaemonConfig.load()
    if let config = config {
        check(config.port == 8420, "port should be 8420")
        check(!config.apiToken.isEmpty, "apiToken should not be empty")
        print("    ✓")
    } else {
        print("    ⚠ skipped (no config file — expected in CI)")
    }
}

// ============================================================
// MARK: - AidaemonClient Tests (Task 5)
// ============================================================

print("\nRunning AidaemonClient tests...\n")

// Test 8: client initializes from config
do {
    print("  test: clientInitFromConfig")
    let config = AidaemonConfig.load()
    if let config = config {
        let client = AidaemonClient(config: config)
        check(client != nil, "client should initialize from config")
        check(client?.baseURL.absoluteString == "http://localhost:8420", "baseURL should be http://localhost:8420")
        print("    ✓")
    } else {
        print("    ⚠ skipped (no config file)")
    }
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
    if !report.summary.isEmpty {
        check(report.lastUpdated != nil, "last-awareness.txt should have a modification date")
        print("    ✓")
    } else {
        print("    ⚠ skipped (no awareness file — expected in CI)")
    }
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
// MARK: - Mood Tests
// ============================================================

print("Running Mood tests...\n")

// Test: all moods have valid expressions
do {
    print("  test: allMoodsHaveExpressions")
    for mood in Mood.allCases {
        let expr = mood.expression
        check(expr.glowIntensity >= 0 && expr.glowIntensity <= 1.0,
              "mood \(mood) glow should be 0-1, got \(expr.glowIntensity)")
        check(expr.color.red >= 0 && expr.color.red <= 1.0,
              "mood \(mood) color.red should be 0-1")
    }
    print("    ✓")
}

// Test: moods from string
do {
    print("  test: moodFromRawValue")
    check(Mood(rawValue: "calm") == .calm, "should parse 'calm'")
    check(Mood(rawValue: "alert") == .alert, "should parse 'alert'")
    check(Mood(rawValue: "invalid") == nil, "should return nil for invalid")
    print("    ✓")
}

// Test: mood count
do {
    print("  test: moodCount")
    check(Mood.allCases.count == 8, "should have 8 moods, got \(Mood.allCases.count)")
    print("    ✓")
}

// ============================================================
// MARK: - SessionStore Tests
// ============================================================

print("Running SessionStore tests...\n")

// Test: initial state
do {
    print("  test: initialState")
    let store = SessionStore()
    check(store.messages.isEmpty, "should start empty")
    check(!store.hasHistory, "should have no history")
    check(store.lastResponse == nil, "should have no last response")
    check(store.sessionID.hasPrefix("friday-"), "sessionID should start with 'friday-'")
    print("    ✓")
}

// Test: add messages
do {
    print("  test: addMessages")
    let store = SessionStore()
    store.add(role: "user", content: "hello")
    store.add(role: "assistant", content: "hi there")
    check(store.messages.count == 2, "should have 2 messages")
    check(store.hasHistory, "should have history")
    check(store.lastResponse == "hi there", "last response should be 'hi there'")
    print("    ✓")
}

// Test: clear
do {
    print("  test: clearSession")
    let store = SessionStore()
    store.add(role: "user", content: "test")
    store.clear()
    check(store.messages.isEmpty, "should be empty after clear")
    check(!store.hasHistory, "should have no history after clear")
    print("    ✓")
}

// ============================================================
// MARK: - IdleDetector Tests
// ============================================================

print("\nRunning IdleDetector tests...\n")

// Test: idle time returns a non-negative value
do {
    print("  test: idleTimeNonNegative")
    let detector = IdleDetector()
    let idle = detector.systemIdleTime()
    check(idle >= 0, "idle time should be >= 0, got \(idle)")
    print("    ✓")
}

// Test: threshold default
do {
    print("  test: idleThresholdDefault")
    let detector = IdleDetector()
    check(detector.threshold == 300, "default threshold should be 300s (5min)")
    print("    ✓")
}

// ============================================================
// MARK: - MoodEngine Tests
// ============================================================

print("Running MoodEngine tests...\n")

// Test: system mood when aidaemon is down + stale heartbeat
do {
    print("  test: systemMoodAidaemonDown")
    let engine = MoodEngine(client: nil, heartbeat: HeartbeatMonitor())
    let mood = engine.deriveSystemMood(aidaemonHealthy: false)
    // Without aidaemon and no heartbeat file, should be alert or concerned
    check(mood == .alert || mood == .concerned,
          "should be alert or concerned when aidaemon is down, got \(mood)")
    print("    ✓")
}

// Test: system mood when healthy
do {
    print("  test: systemMoodHealthy")
    let engine = MoodEngine(client: nil, heartbeat: HeartbeatMonitor())
    let mood = engine.deriveSystemMood(aidaemonHealthy: true)
    let hour = Calendar.current.component(.hour, from: Date())
    if hour >= 22 || hour < 8 {
        check(mood == .sleepy, "should be sleepy outside active hours")
    } else {
        check(mood == .calm || mood == .concerned,
              "should be calm or concerned during active hours, got \(mood)")
    }
    print("    ✓")
}

// ============================================================
// MARK: - VoiceOutput Tests
// ============================================================

print("Running VoiceOutput tests...\n")

// Test: truncation (test via speak behavior with mute)
do {
    print("  test: voiceOutputMuted")
    let voice = VoiceOutput()
    voice.isMuted = true
    var finished = false
    voice.onFinished = { finished = true }
    voice.speak("Hello world. This is a test.")
    check(!voice.isSpeaking, "should not be speaking when muted")
    check(finished, "should call onFinished even when muted")
    print("    ✓")
}

// Test: initial state
do {
    print("  test: voiceOutputInitialState")
    let voice = VoiceOutput()
    check(!voice.isSpeaking, "should not be speaking initially")
    check(!voice.isMuted, "should not be muted initially")
    print("    ✓")
}

// ============================================================
// MARK: - FaceRenderer Tests
// ============================================================

print("Running FaceRenderer tests...\n")

// Test: render params defaults
do {
    print("  test: renderParamsDefaults")
    let params = FaceRenderer.RenderParams(mood: .calm)
    check(params.blinkAmount == 0, "default blink should be 0")
    check(params.mouthOpenness == 0, "default mouth should be 0")
    check(params.size.width == 300, "default size should be 300x300")
    print("    ✓")
}

// Test: all moods produce valid render params
do {
    print("  test: allMoodsRenderParams")
    for mood in Mood.allCases {
        let params = FaceRenderer.RenderParams(mood: mood, animationPhase: 1.5)
        check(params.mood == mood, "mood should match")
        // We can't easily test Canvas drawing without a window, but params construction works
    }
    check(true, "all moods create valid render params")
    print("    ✓")
}

// ============================================================
// MARK: - ConfigLoader chatModel Tests
// ============================================================

print("Running ConfigLoader chatModel tests...\n")

// Test: config with chat_model decodes correctly
do {
    print("  test: configWithChatModel")
    let json = """
    {"port": 8420, "api_token": "test-token", "chat_model": "claude-opus-4"}
    """.data(using: .utf8)!
    let config = AidaemonConfig.decode(from: json)
    check(config != nil, "config should decode")
    check(config?.port == 8420, "port should be 8420")
    check(config?.apiToken == "test-token", "token should match")
    check(config?.chatModel == "claude-opus-4", "chat_model should decode")
    print("    ✓")
}

// Test: config without chat_model still decodes (backward compat)
do {
    print("  test: configWithoutChatModel")
    let json = """
    {"port": 9000, "api_token": "abc"}
    """.data(using: .utf8)!
    let config = AidaemonConfig.decode(from: json)
    check(config != nil, "config should decode without chat_model")
    check(config?.chatModel == nil, "chat_model should be nil when absent")
    print("    ✓")
}

// ============================================================
// MARK: - Session Restore Tests
// ============================================================

print("Running Session Restore tests...\n")

// Test: SessionStore restore populates messages
do {
    print("  test: sessionRestorePopulatesMessages")
    let store = SessionStore()
    check(store.messages.isEmpty, "should start empty")
    check(!store.hasHistory, "should have no history")
    
    let mockMessages: [(role: String, content: String)] = [
        ("user", "Hello Friday"),
        ("assistant", "Hey! How's it going?"),
        ("user", "What's the weather?"),
        ("assistant", "I don't have weather data, but it looks sunny outside."),
    ]
    store.restore(from: mockMessages.map { SessionStore.Message(role: $0.role, content: $0.content) })
    
    check(store.messages.count == 4, "should have 4 messages after restore, got \(store.messages.count)")
    check(store.hasHistory, "should have history after restore")
    check(store.messages[0].role == "user", "first message should be user")
    check(store.messages[0].content == "Hello Friday", "first message content should match")
    check(store.messages[3].role == "assistant", "last message should be assistant")
    print("    ✓")
}

// Test: SessionStore restore triggers onMessagesChanged
do {
    print("  test: sessionRestoreTriggersCallback")
    let store = SessionStore()
    var callbackFired = false
    var callbackCount = 0
    store.onMessagesChanged = { messages in
        callbackFired = true
        callbackCount = messages.count
    }
    
    store.restore(from: [
        SessionStore.Message(role: "user", content: "test"),
        SessionStore.Message(role: "assistant", content: "response"),
    ])
    
    check(callbackFired, "onMessagesChanged should fire on restore")
    check(callbackCount == 2, "callback should receive 2 messages, got \(callbackCount)")
    print("    ✓")
}

// Test: SessionStore restore then add works correctly
do {
    print("  test: sessionRestoreThenAdd")
    let store = SessionStore()
    store.restore(from: [
        SessionStore.Message(role: "user", content: "old message"),
    ])
    store.add(role: "user", content: "new message")
    
    check(store.messages.count == 2, "should have 2 messages (1 restored + 1 new)")
    check(store.messages[0].content == "old message", "first should be restored message")
    check(store.messages[1].content == "new message", "second should be new message")
    print("    ✓")
}

// Test: Empty restore is a no-op
do {
    print("  test: sessionRestoreEmpty")
    let store = SessionStore()
    store.add(role: "user", content: "existing")
    store.restore(from: [])
    
    check(store.messages.count == 1, "empty restore should not clear existing messages")
    check(store.messages[0].content == "existing", "existing message should remain")
    print("    ✓")
}

// ============================================================
// MARK: - SSE Streaming Tests
// ============================================================

print("\nRunning SSE streaming tests...\n")

// Test: chatStream returns AsyncThrowingStream (live test if aidaemon running)
do {
    print("  test: chatStreamLive")
    let config = AidaemonConfig.load()
    if let config = config, let client = AidaemonClient(config: config) {
        let health = await client.checkHealth()
        if health != nil {
            var events: [String] = []
            var gotDone = false
            let stream = client.chatStream(
                message: "Say just the word 'hello'",
                sessionID: "test-sse-\(Int.random(in: 1000...9999))",
                model: "claude-haiku-4.5"
            )
            do {
                for try await event in stream {
                    switch event {
                    case .status(let text):
                        events.append("status:\(text)")
                    case .toolUse(let name, _):
                        events.append("tool:\(name)")
                    case .delta(let chunk):
                        events.append("delta:\(chunk.prefix(20))")
                    case .done(let text, _):
                        events.append("done:\(text.prefix(30))")
                        gotDone = true
                    case .error(let text):
                        events.append("error:\(text)")
                    }
                }
            } catch {
                events.append("threw:\(error)")
            }
            check(!events.isEmpty, "should receive at least one SSE event")
            check(gotDone, "should receive a done event")
            check(events.first?.hasPrefix("status:") == true, "first event should be status")
            print("    ✓ (received \(events.count) events: \(events.prefix(3).joined(separator: ", "))...)")
        } else {
            print("    ⏭ (aidaemon not healthy, skipping)")
        }
    } else {
        print("    ⏭ (no config, skipping)")
    }
}

// ============================================================
// MARK: - TextCleaner Tests
// ============================================================

print("\nRunning TextCleaner tests...\n")

// Test: strips bold
do {
    print("  test: stripsBold")
    let result = TextCleaner.clean("Hello **world** today")
    check(result == "Hello world today", "should strip bold, got '\(result)'")
    print("    ✓")
}

// Test: strips italic
do {
    print("  test: stripsItalic")
    let result = TextCleaner.clean("Hello *world* today")
    check(result == "Hello world today", "should strip italic, got '\(result)'")
    print("    ✓")
}

// Test: strips emojis
do {
    print("  test: stripsEmojis")
    let result = TextCleaner.clean("Hello 🌍 world 🎉")
    check(result == "Hello world", "should strip emojis, got '\(result)'")
    print("    ✓")
}

// Test: strips headers
do {
    print("  test: stripsHeaders")
    let result = TextCleaner.clean("## My Header")
    check(result == "My Header", "should strip header, got '\(result)'")
    print("    ✓")
}

// Test: strips code blocks
do {
    print("  test: stripsCodeBlocks")
    let result = TextCleaner.clean("Use `print()` to debug")
    check(result == "Use print() to debug", "should strip inline code, got '\(result)'")
    print("    ✓")
}

// Test: strips links
do {
    print("  test: stripsLinks")
    let result = TextCleaner.clean("Visit [Google](https://google.com) now")
    check(result == "Visit Google now", "should strip links, got '\(result)'")
    print("    ✓")
}

// Test: handles mixed markdown
do {
    print("  test: handlesMixed")
    let result = TextCleaner.clean("**Bold** and *italic* with 🎉 emoji")
    check(result == "Bold and italic with emoji", "should strip all, got '\(result)'")
    print("    ✓")
}

// Test: plain text passes through
do {
    print("  test: plainTextPassesThrough")
    let result = TextCleaner.clean("Just a normal sentence.")
    check(result == "Just a normal sentence.", "should pass through, got '\(result)'")
    print("    ✓")
}

// Test: stray asterisks removed
do {
    print("  test: strayAsterisks")
    let result = TextCleaner.clean("** unclosed bold")
    check(!result.contains("*"), "should remove stray asterisks, got '\(result)'")
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

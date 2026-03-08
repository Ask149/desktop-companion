# Contributing to Friday

Thanks for your interest in contributing! This guide covers how to get started.

## Development Setup

```bash
# Clone
git clone https://github.com/Ask149/friday.git
cd friday

# Build
swift build

# Run tests
swift test

# Build the app bundle
scripts/bundle.sh
```

## Project Structure

```
Sources/
  CompanionCore/              Core library (all logic lives here)
    CompanionState.swift       Central observable state (mood, chat, overlay)
    Models/                    Data models (Mood, SessionStore, AwarenessReport)
    Rendering/
      CritterRenderer.swift    Menu bar animated critter
      FaceRenderer.swift       Full-screen geometric face (8 moods)
    Services/
      AidaemonClient.swift     HTTP + SSE streaming client to aidaemon
      ConfigLoader.swift       Reads aidaemon config (port, token, model)
      FridayConfig.swift       Reads Friday-specific config
      HeartbeatMonitor.swift   Reads heartbeat state files
      HotkeyManager.swift      Global ⌘⇧Space hotkey
      IdleDetector.swift       IOKit-based idle time detection
      InterruptListener.swift  Speech detection during TTS (for "stop" commands)
      MoodEngine.swift         2-layer mood derivation
      VoiceInput.swift         SFSpeechRecognizer wrapper
      VoiceOutput.swift        AVSpeechSynthesizer with mouth animation
  DesktopCompanion/
    main.swift                 App entry point, menu bar, popover, overlay

Tests/
  CompanionTests/
    main.swift                 Test runner (~45 tests)

scripts/
  bundle.sh                   Build + bundle + codesign
```

## Architecture

Friday follows a clean separation:

- **CompanionCore** — all logic, no UI framework dependency (can be tested independently)
- **DesktopCompanion** — SwiftUI app that wires CompanionCore to the UI

Key design decisions:
- **Zero external dependencies** — only Apple frameworks (AppKit, SwiftUI, Speech, AVFoundation, IOKit)
- **`@MainActor` everywhere** — all services run on the main actor for thread safety
- **Observable pattern** — `CompanionState` is `@ObservableObject`, SwiftUI views react to changes
- **SSE streaming** — real-time responses via Server-Sent Events from aidaemon

## Making Changes

1. **Fork** the repository
2. **Create a branch** from `main` (`feat/description` or `fix/description`)
3. **Make your changes** — keep commits focused
4. **Build and test:**
   ```bash
   swift build
   swift test
   ```
5. **Test the app** — run `scripts/bundle.sh && open build/Friday.app`
6. **Open a pull request** with a clear description

## Code Style

- **Swift conventions** — follow Swift API Design Guidelines
- **Access control** — use `public` for API, `private` for internals
- **Logging** — use `os.log` with `Logger(subsystem:category:)`
- **Error handling** — prefer `guard` for early returns
- **Comments** — explain _why_, not _what_

## Adding a New Mood

1. Add the case to `Mood` enum in `Sources/CompanionCore/Models/Mood.swift`
2. Add rendering in `FaceRenderer.swift` (geometric face expression)
3. Add rendering in `CritterRenderer.swift` (menu bar critter)
4. Add derivation logic in `MoodEngine.swift`
5. Add tests in `Tests/CompanionTests/main.swift`

## Reporting Issues

- Use [GitHub Issues](https://github.com/Ask149/friday/issues)
- Include: macOS version, Friday version, aidaemon version, steps to reproduce
- Screenshots of the face/critter are helpful for rendering issues

# Friday

A macOS desktop companion with an animated face, voice, and personality — powered by [aidaemon](https://github.com/Ask149/aidaemon).

Friday lives in your menu bar as a small animated critter. Click it for a quick chat popover, or press **⌘⇧Space** to summon a full-screen AI companion with a geometric face that reacts to your conversation.

## Features

- **Menu bar critter** — animated character that reflects the AI's current mood
- **Quick chat popover** — click the critter for fast text-based conversations
- **Full-screen face overlay** — geometric face with 8 mood states (calm, happy, curious, thinking, alert, concerned, excited, tired)
- **Voice input** — speak naturally using on-device speech recognition (Apple SFSpeechRecognizer)
- **Voice output** — responses spoken aloud with synchronized mouth animation
- **Interrupt detection** — say "stop" or "Friday stop" to interrupt speech mid-sentence
- **Mood engine** — 2-layer mood derivation from conversation sentiment and system health
- **Idle detection** — appears when you've been away, greets you when you return
- **Global hotkey** — ⌘⇧Space to toggle the overlay from anywhere

## Requirements

- macOS 14.0+ (Sonoma or later)
- [aidaemon](https://github.com/Ask149/aidaemon) running on `localhost:8420`
- (Optional) Microphone access for voice input

## Install

```bash
git clone https://github.com/Ask149/friday.git
cd friday
scripts/bundle.sh
open build/Friday.app
```

That's it. Friday connects to aidaemon automatically.

> **First time?** Make sure [aidaemon](https://github.com/Ask149/aidaemon) is running first. Friday will show a connection error in the popover if it can't reach the daemon.

## How It Works

```
┌─────────────────────────────────────────────────┐
│  Menu Bar          Popover          Overlay      │
│  ┌──────┐     ┌─────────────┐   ┌────────────┐ │
│  │Crit- │────▶│  Quick Chat │   │ Full-Screen │ │
│  │ter   │     │  (text)     │   │ Face + Voice│ │
│  └──────┘     └──────┬──────┘   └──────┬─────┘ │
│                      │                  │        │
│               ┌──────▼──────────────────▼──────┐ │
│               │     AidaemonClient             │ │
│               │  HTTP REST + SSE Streaming     │ │
│               └──────────────┬─────────────────┘ │
└──────────────────────────────┼───────────────────┘
                               │
                        localhost:8420
                               │
                     ┌─────────▼─────────┐
                     │     aidaemon      │
                     │  (AI daemon)      │
                     └───────────────────┘
```

### Mood States

| Mood | When | Face |
|------|------|------|
| Calm | Default / normal conversation | Neutral expression, steady eyes |
| Happy | Positive response, good news | Upturned mouth, bright eyes |
| Curious | Questions, exploring topics | Wide eyes, tilted expression |
| Thinking | Processing, tool calls in progress | Narrowed eyes, subtle animation |
| Alert | System warnings, stale heartbeat | Sharp expression, attention markers |
| Concerned | Errors, aidaemon unreachable | Worried expression |
| Excited | Great news, celebrations | Wide smile, animated |
| Tired | Late hours, low activity | Droopy eyes, slower animation |

## Configuration

Friday loads optional configuration from `~/.config/friday/config.json`. All fields are optional — sensible defaults are used when the file is absent.

See [CONFIGURATION.md](CONFIGURATION.md) for all options.

**Quick example:**
```json
{
  "userName": "Alex",
  "locale": "en-US",
  "voiceIdentifier": "com.apple.voice.premium.en-US.Zoe",
  "activeHoursStart": 9,
  "activeHoursEnd": 23
}
```

## Building from Source

```bash
# Build and bundle (creates Friday.app in build/)
scripts/bundle.sh

# Or build without bundling
swift build

# Run tests
swift test
```

### Build Requirements

- Xcode 15+ or Swift 5.9+ toolchain
- macOS 14.0+ SDK
- No external dependencies — uses only Apple frameworks

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

[MIT](LICENSE)

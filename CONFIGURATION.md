# Configuration

Friday loads configuration from `~/.config/friday/config.json`. All fields are optional — Friday works out of the box with sensible defaults.

## Config File

```json
{
  "userName": "Alex",
  "locale": "en-US",
  "voiceIdentifier": "com.apple.voice.premium.en-US.Zoe",
  "activeHoursStart": 9,
  "activeHoursEnd": 23,
  "heartbeatStateDir": "~/.config/aidaemon/heartbeat/state",
  "notesDir": "~/.config/aidaemon/notes"
}
```

## Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `userName` | string | `"the user"` | Your name, used in the voice system prompt ("You are speaking aloud to {userName}") |
| `locale` | string | System locale | Locale for speech recognition (e.g., `"en-US"`, `"en-GB"`, `"ja-JP"`) |
| `voiceIdentifier` | string | System default | AVSpeechSynthesisVoice identifier for text-to-speech |
| `activeHoursStart` | int (0-23) | `8` | Hour when idle detection activates (24-hour format) |
| `activeHoursEnd` | int (0-23) | `22` | Hour when idle detection deactivates |
| `heartbeatStateDir` | string | `~/.config/aidaemon/heartbeat/state` | Directory for heartbeat awareness state files |
| `notesDir` | string | `~/.config/aidaemon/notes` | Directory for notes files |

## Voice Selection

To find available voice identifiers on your Mac:

```bash
# List all available voices
say -v '?'

# List premium voices (higher quality)
say -v '?' | grep premium
```

Common voice identifiers:
- `com.apple.voice.premium.en-US.Zoe` — US English, female
- `com.apple.voice.premium.en-US.Evan` — US English, male
- `com.apple.voice.premium.en-GB.Kate` — British English, female
- `com.apple.voice.premium.en-AU.Lee` — Australian English, male

If the configured voice isn't available, Friday falls back to the default `en-US` system voice.

## Locale

The locale affects speech recognition accuracy. Set it to match the language you speak to Friday:

| Language | Locale |
|----------|--------|
| US English | `en-US` |
| UK English | `en-GB` |
| Indian English | `en-IN` |
| Japanese | `ja-JP` |
| German | `de-DE` |
| French | `fr-FR` |
| Spanish | `es-ES` |

If not set, Friday uses your system locale.

## Active Hours

Idle detection only triggers during active hours. Outside these hours, Friday won't appear when you're idle (e.g., won't interrupt you at 2 AM).

- `activeHoursStart: 8` + `activeHoursEnd: 22` → idle detection from 8 AM to 10 PM
- Set `activeHoursStart: 0` + `activeHoursEnd: 24` to enable idle detection 24/7

## Aidaemon Connection

Friday connects to aidaemon at `localhost:8420` (reading the port from aidaemon's config at `~/.config/aidaemon/config.json`). There's no separate config field for this — Friday reads aidaemon's config directly.

If aidaemon isn't running, Friday shows a connection error in the popover and retries periodically.

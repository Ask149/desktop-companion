# Bundle & Install Scripts

## Created Files
- `scripts/bundle.sh` — Builds release binary, creates .app bundle structure
- `scripts/install.sh` — Installs to /Applications, launches app, shows login item instructions

## Key Decisions

### Release Build Testing
- Added `-enable-testing` flag for CompanionCore in release builds
- Required for `@testable import` in CompanionTests executable
- Without this flag, release builds fail with "module was not compiled for testing"

### Bundle Structure
```
build/DesktopCompanion.app/
├── Contents/
│   ├── Info.plist (LSUIElement=true → no Dock icon)
│   ├── MacOS/
│   │   └── DesktopCompanion (499KB release binary)
│   └── Resources/ (empty for now, future: icon assets)
```

### Installation Process
1. `./scripts/bundle.sh` → builds release + creates bundle
2. `./scripts/install.sh` → kills existing instance, copies to /Applications, launches
3. Manual: Add to Login Items via System Settings or osascript

## Verification Results

**Bundle creation:** ✅ Success (10.30s build time)
**Release tests:** ✅ All 15 tests pass, 43 assertions
**App launch:** ✅ Process starts, no Dock icon, menu bar icon visible
**Binary size:** 499KB (release mode with optimizations)

## Usage

```bash
# Build bundle only
./scripts/bundle.sh

# Build + install to /Applications
./scripts/install.sh

# Add to login items (optional)
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/DesktopCompanion.app", hidden:false}'
```

## Next Steps (Post-Installation)
- Verify menu bar icon appears with animated critter
- Click icon → popover shows 4 sections (Status, Awareness, Chat, Health)
- Test Quick Chat → sends message to aidaemon, displays reply
- Monitor logs: `Console.app` filter for "DesktopCompanion"
- Test mode transitions: idle → thinking (chat) → alert (add ALERT: to awareness file)

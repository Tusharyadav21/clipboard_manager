# AGENTS.md — Clipboard Manager for macOS

See `CLAUDE.md` for detailed architecture and full component list. This file covers operational guidance.

## Build & Run

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project "clipboard manager.xcodeproj" -scheme "clipboard manager" build
```

Debug from Xcode: open `.xcodeproj`, select scheme `clipboard manager`, `Cmd+R`.

## Testing

**No test targets exist** — the project has no tests. Do not search for or attempt to run test/CI commands.

## Key Constraints

- `ENABLE_APP_SANDBOX = NO` (required for `CGEvent` keystroke simulation)
- `LSUIElement = YES` — menu bar app, no dock icon
- `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_VERSION = 6.0`, `MACOSX_DEPLOYMENT_TARGET = 14.0`
- Only dependency: `GRDB.swift` v6.29+ via SPM

## Architecture (brief)

`ClipboardManagerApp` (SwiftUI `@main`) → `AppDelegate` (real coordinator) → `ClipboardService` (background `actor`) → `GRDBClipboardRepository` (SQLite). `ClipboardMonitorService` polls pasteboard in an async `Task.sleep` loop. `SensitiveContentPolicy` screens regex + transient/concealed pasteboard types inline.

## Persistence

- WAL-mode SQLite at `~/Library/Application Support/ClipboardManager/clipboard_history.sqlite`
- Optional AES-GCM encryption via Keychain-backed keys (`SecurityService`)
- FTS5 full-text search via DB triggers
- Auto-prunes to 50 items / 7-day expiry
- Legacy `history.json` migrated to SQLite on first launch, backed up to `.bak`

## Hotkey

- Carbon Event Manager (`RegisterEventHotKey`), **not** Combine or `KeyboardShortcuts`
- Default: `Cmd+Shift+V`
- Key code / modifiers stored in `UserDefaults` under `hotkeyKeyCode` / `hotkeyModifiers`

## Direct Paste

- Requires Accessibility permission via `AXIsProcessTrustedWithOptions()`
- Simulates `Cmd+V` via `CGEvent` key-down post to `cghidEventTap`
- Up to 8 retry attempts at 80ms intervals to activate the target app

## Release & Distribution

```bash
# 1. Build Release + create DMG
./create_dmg.sh

# 2. Create GitHub release with DMG as asset
gh release create v<version> "./Clipboard Manager.dmg" --title "v<version>"
```

## Settings

- All settings stored in `UserDefaults` (keys defined in `SettingsKeys` enum in `Constants.swift`)
- No CloudKit, no sync
- Excluded apps stored as string array under `exclusions` key

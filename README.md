# Clipboard Manager

A privacy-first, local-only clipboard history manager for macOS 14+. Sits in your menu bar and keeps your copy history searchable, organized, and secure.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Tusharyadav21/clipboard_manager/main/install.sh | bash
```

Downloads the latest DMG from GitHub, installs to `/Applications`, and removes the quarantine flag.

Or grab the DMG manually from [Releases](https://github.com/Tusharyadav21/clipboard_manager/releases).

## Features

- **Menu bar app** — no dock icon, always accessible
- **Instant FTS5 search** across your full history
- **Auto-pruning** — keeps 50 items max, purges after 7 days
- **Sensitive content screening** — drops API keys, JWTs, SSH keys, and password manager output before they hit storage
- **AES-GCM encryption** at rest (optional, Keychain-backed keys)
- **Direct paste** — Cmd+Shift+V to open overlay, select and auto-paste via Accessibility API
- **Per-app exclusions** — exclude specific apps from history
- **Customizable hotkey** (default: Cmd+Shift+V)
- **Glassmorphism UI** with light/dark/system theme support

## Usage

| Action | Shortcut |
|--------|----------|
| Open overlay | `Cmd+Shift+V` |
| Select item | `↑` / `↓` |
| Paste + close | `Enter` |
| Close overlay | `Esc` |
| Pin item | Right-click → Pin |
| Delete item | Right-click → Delete |

Toggle persistent history, encryption, launch at login, and direct paste from **Settings**.

## Privacy

Everything is local. No telemetry, no sync, no cloud. Your clipboard never leaves your machine.

## Development

```bash
make build          # debug build
make dmg            # release build + DMG
make release        # build + DMG + tag + GitHub Release
```

Requires Xcode 15+ and Swift 6. Open `clipboard manager.xcodeproj` and press `Cmd+R`.

## Troubleshooting

- **Gatekeeper warning**: Right-click the app in Applications → Open, or run `xattr -cr "/Applications/clipboard manager.app"`
- **Direct paste doesn't work**: Enable the app in **System Settings > Privacy & Security > Accessibility**
- **Hotkey not responding**: Check for conflicts with other apps in Settings
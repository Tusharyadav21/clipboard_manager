# Clipboard Manager

A privacy-first, local-only clipboard history manager for macOS 14+. Sits in your menu bar and keeps your copy history searchable, organized, and secure.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Tusharyadav21/clipboard_manager/main/install.sh | bash
```

Downloads the latest DMG from GitHub, installs to `/Applications`, and removes the quarantine flag.

Or grab the DMG manually from [Releases](https://github.com/Tusharyadav21/clipboard_manager/releases).

## Features

### 🔍 Clipboard History & Search
- **Full clipboard history** — every text copy is saved, searchable, and organized
- **SQLite FTS5 full-text search** — instant sub-millisecond search across all stored items
- **Auto-pruning** — caps at 50 items with 7-day expiry, pinned items are preserved
- **Per-app exclusions** — exclude specific apps from being tracked

### 🛡️ Security & Privacy
- **100% local** — no network access, no telemetry, no cloud sync. Your data never leaves your machine
- **Sensitive content filtering** — automatically detects and drops AWS keys, GitHub tokens, Stripe/ Slack API keys, JWTs, SSH/PGP private keys, and password manager output (1Password, Bitwarden) before they are stored
- **AES-GCM encryption at rest** — optionally encrypts the entire clipboard history with a 256-bit key stored in the macOS Keychain
- **Per-app exclusions** — prevent specific applications from being recorded

### 🖱️ Interaction & Workflow
- **Menu bar app** — no dock icon, always one click away
- **Customizable hotkey** (default: `Cmd+Shift+V`) — toggle the overlay from anywhere
- **Direct paste** — select an item and it is automatically pasted into your active app via Accessibility API keystroke simulation
- **Keyboard navigation** — arrow keys to select, Enter to paste, Esc to close
- **Right-click context menu** — pin/unpin, delete individual items
- **Status bar menu** — browse last 15 items, open Settings, or Quit

### 🎨 Interface
- **Glassmorphism design** — frosted blur background with adjustable intensity
- **Light / Dark / System theme** — matches your system preference
- **App icons** — each item shows its source application icon
- **Onboarding flow** — first-launch setup for persistence and launch-at-login

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
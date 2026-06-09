# macOS Clipboard Manager (Modernized & Hardened)

A production-grade, high-performance status bar utility for macOS (14.0+) built from the ground up using **SwiftUI**, **Swift 6 Strict Concurrency**, and **GRDB SQLite** persistence. This application provides secure, local-first clipboard history tracking with advanced sensitive-content filtering and sub-millisecond full-text search.

---

## Key Features & Modernizations

### 🚀 Performance & Architecture (Swift 6 + GRDB)
- **Strict Concurrency**: Fully conformed to the Swift 6 concurrency model (`SWIFT_STRICT_CONCURRENCY = complete`). Heavy tasks are isolated off the main thread inside a background Swift `actor` (`ClipboardService.swift`).
- **GRDB.swift Database Engine**: Replaced legacy, slow, and insecure JSON file writes with a transactional SQLite repository utilizing Write-Ahead Logging (WAL) and synchronous normal mode for zero lag and high reliability.
- **Auto-Pruning & Storage Limits**: Enforces a strict capacity cap of **50 items** (pinned + recent) and a **7-day auto-expiry** policy to keep memory usage and disk footprint minimal.
- **SQLite FTS5 Full-Text Search**: Instantly query thousands of items with full-text search indexing synchronized automatically via database triggers.
- **Legacy Migration**: Gracefully migrates pre-existing JSON history items from `history.json` to the database on launch, backing up the old file to `history.json.bak`.

### 🛡️ Security Hardening (Sensitive Content Policy)
- **Automatic Screening**: Scans clipboard data in real-time to drop sensitive tokens before they are persisted:
  - AWS, GitHub, Stripe, Slack, and generic API tokens.
  - SSH / PGP private keys.
  - JWTs and high-entropy credentials.
- **Password Manager Integration**: Automatically ignores pasteboard types marked as transient or concealed (e.g., from **1Password**, **Bitwarden**, or native Keychain).
- **Secure Persistence**: Database initialization interfaces with **Keychain-backed database encryption keys** for state-of-the-art data confidentiality.

### 🎨 Premium UI/UX (Decomposed & Modernized)
- **Glassmorphic popover overlay panel** with blur effects and active hover animations.
- **Fully Decomposed Components**: Clean modular structure:
  - [AppIcon.swift](file:///Users/tusharyadav/Dev/clipboard_manager_macos/clipboard%20manager/Views/Components/AppIcon.swift) (with cached thumbnail rendering)
  - [SearchBar.swift](file:///Users/tusharyadav/Dev/clipboard_manager_macos/clipboard%20manager/Views/Components/SearchBar.swift)
  - [ClipboardRow.swift](file:///Users/tusharyadav/Dev/clipboard_manager_macos/clipboard%20manager/Views/Components/ClipboardRow.swift)
  - [OnboardingView.swift](file:///Users/tusharyadav/Dev/clipboard_manager_macos/clipboard%20manager/Views/Components/OnboardingView.swift)
  - [PermissionBanner.swift](file:///Users/tusharyadav/Dev/clipboard_manager_macos/clipboard%20manager/Views/Components/PermissionBanner.swift)
- **Automated Direct-Paste**: Simulated command-v keystroke injection using Accessibility APIs for instant paste triggers upon clipboard item selection.

---

## Directory Structure

```text
├── clipboard manager/
│   ├── Models/
│   │   ├── ClipboardItem.swift           # Codable Sendable DTO
│   │   └── SensitiveContentPolicy.swift  # Security scanning logic
│   ├── Persistence/
│   │   ├── DatabaseMigrator.swift        # SQLite scheme migrator
│   │   ├── GRDBClipboardRepository.swift # SQLite CRUD transactions
│   │   └── LegacyJSONImporter.swift      # JSON-to-SQLite migration
│   ├── Services/
│   │   ├── ClipboardService.swift        # Thread-safe background DB Actor
│   │   ├── ClipboardMonitorService.swift # Async pasteboard polling loop
│   │   ├── PasteService.swift            # Accessibility key-press simulator
│   │   └── SecurityService.swift         # Encryption & key manager
│   ├── ViewModels/
│   │   └── ClipboardViewModel.swift      # MainActor UI bindings controller
│   ├── Views/
│   │   └── Components/                   # Modular SwiftUI subviews
│   └── AppDelegate.swift                 # Application lifecycle coordinator
├── create_dmg.sh                         # Automated build & packaging script
├── CLAUDE.md                             # Local developer guidance reference
└── README.md                             # Project documentation (this file)
```

---

## Setup & Development

### Prerequisites
- macOS 14.0+
- Xcode 15.0+ (Swift 6.0 compatibility)
- GitHub CLI (`gh`) (optional, for release deployment)

### Build & Run
To run the debug builds directly via Xcode:
1. Open `clipboard manager.xcodeproj` in Xcode.
2. Select the `clipboard manager` scheme.
3. Press `Cmd + R` to build and run.

To build manually in a terminal session:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project "clipboard manager.xcodeproj" -scheme "clipboard manager" -configuration Debug build
```

---

## Release & Distribution (DMG Packaging)

For distributing outside of the Mac App Store (Sandbox disabled), the app is packaged as a `.dmg` installer. The build and packaging process has been fully automated:

### 1. Generate DMG Installer
Run the custom packaging script:
```bash
./create_dmg.sh
```
This script will:
- Clean the `./build` directory and old DMGs.
- Compile the app in **Release** configuration.
- Bundle the app along with an `/Applications` symlink inside a temporary folder.
- Execute native macOS `hdiutil` to package it into a compressed disk image: `Clipboard Manager.dmg`.

*Note: Both build caches (`build/`) and output binaries (`*.dmg`, `*.app`) are excluded in `.gitignore` to prevent repository bloat.*

### 2. Push Changes and Create GitHub Release
To publish updates and distribute the new DMG via GitHub Releases cleanly using the GitHub CLI:

1. **Verify your local branch status**:
   ```bash
   git status
   ```

2. **Commit configuration updates or documentation changes**:
   ```bash
   git add README.md create_dmg.sh
   git commit -m "Add documentation and DMG packaging automation"
   ```

3. **Push commits to GitHub**:
   ```bash
   git push origin main
   ```

4. **Create a GitHub Release and Upload the DMG Asset**:
   Rather than tracking the DMG binary in Git history, release it directly as a release asset:
   ```bash
   gh release create v1.0.0 "./Clipboard Manager.dmg" \
     --title "v1.0.0" \
     --notes "Production-ready release featuring Swift 6 concurrency, GRDB SQLite engine, and sensitive data protection."
   ```

---

## Troubleshooting & Debugging

- **Gatekeeper Warning ("Apple could not verify...")**: Since local and GitHub-built releases are not signed and notarized with a paid Apple Developer Program account, macOS Gatekeeper will block them by default.
  - To run the application:
    1. Drag the application to your `/Applications` directory.
    2. **Control-click (or right-click)** the app icon and choose **Open**, then click **Open** in the confirmation dialog. (This only needs to be done once).
    3. Alternatively, you can strip the macOS quarantine flag using terminal:
       ```bash
       xattr -cr "/Applications/clipboard manager.app"
       ```
- **Accessibility Permissions**: If automated pasting does not work, make sure that the app is enabled under **System Settings > Privacy & Security > Accessibility**. If problems persist, toggle it off and back on.
- **App Sandboxing**: Because this application simulates global keystrokes to automate pasting into active target programs, Sandboxing must remain disabled (`ENABLE_APP_SANDBOX = NO`).

# CLAUDE.md

This file provides guidance when working with code in this repository.

## Project Overview

Clipboard Manager for macOS - a menu bar application that monitors clipboard changes, filters sensitive data, and provides secure quick access to history via a popover overlay.

## Architecture

**Entry Point**: `ClipboardManagerApp.swift` - SwiftUI @main app with Settings scene

**Core Components**:
- `AppDelegate.swift` - Thin coordinator managing status item, overlay panel, hotkey, and initialization
- `Models/ClipboardItem.swift` - Domain item model with cached UTF-8 byte count, conformed to `Sendable`
- `Models/SensitiveContentPolicy.swift` - Screening rules ignoring credentials, private keys, API tokens, and transient/concealed pasteboard types
- `Persistence/ClipboardRepository.swift` - Abstraction protocol for clipboard persistence
- `Persistence/GRDBClipboardRepository.swift` - concrete SQLite-backed repo using FTS5 virtual table triggers for indexing
- `Persistence/DatabaseMigrator.swift` - Database schema versioning and setup
- `Persistence/LegacyJSONImporter.swift` - Automatically imports items from legacy `history.json` on launch
- `Services/ClipboardService.swift` - background `actor` isolating clipboard business logic and DB CRUDs
- `Services/ClipboardMonitorService.swift` - Runs an async `Task.sleep` loop scanning pasteboard state safely
- `Services/SecurityService.swift` - Encapsulates Keychain-backed AES-GCM database encryption keys
- `Services/PasteService.swift` - Uses async sleep cycles to programmatically paste items into active applications
- `ViewModels/ClipboardViewModel.swift` - `@MainActor` controller driving SwiftUI layouts and calling service actor
- `HotkeyManager.swift` - Carbon Event Manager for global hotkey registration (Cmd+Shift+V default)

**UI Components**:
- `PopoverView.swift` - Blur-effect popover container
- `Views/Components/` - Decomposed, reusable SwiftUI elements:
  - `AppIcon.swift` (with size-capped thumbnail cache)
  - `SearchBar.swift`, `SectionHeader.swift`, `ClipboardRow.swift`
  - `PermissionBanner.swift`, `OnboardingView.swift`
- `SettingsView.swift` - App configuration pane (filters, exclusions, shortcuts, appearance)

## Build & Run

```bash
# Set Developer directory path if running tools inside a terminal session:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Build project via xcodebuild
xcodebuild -project "clipboard manager.xcodeproj" -scheme "clipboard manager" build
```

## Dependencies & Settings

- **Dependencies**: Uses `GRDB.swift` (SQLite wrapper) integrated via Swift Package Manager.
- **Swift Version**: Target set to `SWIFT_VERSION = 6.0` with `SWIFT_STRICT_CONCURRENCY = complete`.
- **Sandbox**: Disabled (`ENABLE_APP_SANDBOX = NO`) to permit global direct-paste simulation.
- **Limits**: History capacity is capped at `50 items` (both recent and pinned) with a `7-day` auto-expiration policy.

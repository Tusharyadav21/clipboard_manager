# CLAUDE.md — Clipboard Manager for macOS

This is the detailed architecture reference. See `AGENTS.md` for build commands, testing, hotkey, release, and other operational guidance.

## Project Overview

Menu bar app that monitors clipboard changes, filters sensitive data, and provides secure quick access to history via a popover overlay.

## Architecture

**Entry Point**: `ClipboardManagerApp.swift` - SwiftUI @main app with Settings scene

**Core Components**:
- `AppDelegate.swift` - Application lifecycle coordinator managing status item, overlay panel, hotkey, and initialization
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

## Dependencies & Constraints

- `GRDB.swift` v6.29+ via SPM
- `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `MACOSX_DEPLOYMENT_TARGET = 14.0`
- `ENABLE_APP_SANDBOX = NO` (required for CGEvent paste)
- `LSUIElement = YES` — no dock icon
- 50-item cap / 7-day expiry

import Foundation
import AppKit

public enum Constants {
    // Clipboard Monitoring
    nonisolated public static let clipboardPollInterval: TimeInterval = 0.4
    
    // UI Dimensions
    nonisolated public static let overlayWidth: CGFloat = 400
    nonisolated public static let overlayHeight: CGFloat = 460
    nonisolated public static let settingsWidth: CGFloat = 520
    nonisolated public static let settingsHeight: CGFloat = 560
    
    // Direct Paste
    nonisolated public static let maxPasteAttempts = 8
    nonisolated public static let pasteAttemptDelay: TimeInterval = 0.08
    
    // Clipboard Storage Budgets
    nonisolated public static let maxRecentItems = 50
    nonisolated public static let maxPinnedItems = 50
    nonisolated public static let autoDeleteDays = 7
    nonisolated public static let maxCharactersPerItem = 80_000
    nonisolated public static let maxBytesPerItem = 256 * 1024
    nonisolated public static let maxTotalPinnedBytes = 4 * 1024 * 1024
    nonisolated public static let maxTotalRecentBytes = 6 * 1024 * 1024
    
    // Memory Pressure Budgets
    nonisolated public static let aggressivePinnedLimit = 12
    nonisolated public static let aggressiveRecentLimit = 10
    nonisolated public static let aggressiveByteLimit = 512 * 1024
    
    // UI Layout
    nonisolated public static let overlayAnchorOffset: CGFloat = 24
    nonisolated public static let overlayPadding: CGFloat = 8
    nonisolated public static let overlayBottomOffset: CGFloat = 10
}

public enum SettingsKeys {
    nonisolated public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    nonisolated public static let persistHistory = "persistHistory"
    nonisolated public static let launchAtLogin = "launchAtLogin"
    nonisolated public static let autoPaste = "autoPaste"
    nonisolated public static let hotkeyKeyCode = "hotkeyKeyCode"
    nonisolated public static let hotkeyModifiers = "hotkeyModifiers"
    nonisolated public static let glassIntensity = "glassIntensity"
    nonisolated public static let encryptHistoryAtRest = "encryptHistoryAtRest"
    nonisolated public static let appTheme = "appTheme"
    nonisolated public static let exclusions = "exclusions"
    nonisolated public static let hasDismissedAccessibilityNotice = "hasDismissedAccessibilityNotice"
}

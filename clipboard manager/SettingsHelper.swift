import AppKit
import Foundation
import ServiceManagement

enum SettingsHelper {
    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update login item: \(error)")
        }
    }

    static func excludeFrontmostApp() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmost.bundleIdentifier else { return }
        var exclusions = UserDefaults.standard.stringArray(forKey: SettingsKeys.exclusions) ?? []
        if !exclusions.contains(bundleId) {
            exclusions.append(bundleId)
            UserDefaults.standard.set(exclusions, forKey: SettingsKeys.exclusions)
        }
    }
}

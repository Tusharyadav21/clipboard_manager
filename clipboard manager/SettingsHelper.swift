import AppKit
import Foundation
import ServiceManagement

enum SettingsHelper {
    @MainActor
    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update login item: \(error)")
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
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

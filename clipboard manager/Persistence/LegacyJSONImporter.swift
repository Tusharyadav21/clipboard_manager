import Foundation

nonisolated public struct LegacyJSONImporter {
    public static func migrateIfNeeded(repository: ClipboardRepository) async {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
        let legacyJSONURL = dir.appendingPathComponent("history.json")
        
        guard FileManager.default.fileExists(atPath: legacyJSONURL.path) else {
            return
        }
        
        NSLog("Found legacy JSON history file. Starting migration to SQLite...")
        
        do {
            let data = try Data(contentsOf: legacyJSONURL)
            let encryptAtRest = UserDefaults.standard.bool(forKey: SettingsKeys.encryptHistoryAtRest)
            
            if let items = decodeItems(from: data, preferEncrypted: encryptAtRest) {
                NSLog("Decoded \(items.count) legacy items. Saving to database...")
                for item in items {
                    try? await repository.save(item)
                }
                
                // Back up the legacy file instead of deleting immediately, to prevent data loss
                let backupURL = legacyJSONURL.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.moveItem(at: legacyJSONURL, to: backupURL)
                NSLog("Migration successful! Legacy history backed up to history.json.bak")
            } else {
                NSLog("Failed to decode legacy history file.")
            }
        } catch {
            NSLog("Failed to migrate legacy JSON history: \(error)")
        }
    }
    
    private static func decodeItems(from data: Data, preferEncrypted: Bool) -> [ClipboardItem]? {
        if preferEncrypted {
            if let decrypted = try? SecurityService.decrypt(data),
               let items = try? JSONDecoder().decode([ClipboardItem].self, from: decrypted) {
                return items
            }
            if let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                return items
            }
            return nil
        }
        
        if let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            return items
        }
        if let decrypted = try? SecurityService.decrypt(data),
           let items = try? JSONDecoder().decode([ClipboardItem].self, from: decrypted) {
            return items
        }
        return nil
    }
}

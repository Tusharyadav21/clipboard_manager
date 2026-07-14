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
                try? await repository.saveBatch(items)
                
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
        let decoder = JSONDecoder()
        
        func tryDecode(data: Data) -> [ClipboardItem]? {
            do {
                return try decoder.decode([ClipboardItem].self, from: data)
            } catch {
                NSLog("JSON decoding failed: \(error)")
                return nil
            }
        }
        
        func tryDecryptAndDecode(data: Data) -> [ClipboardItem]? {
            do {
                let decrypted = try SecurityService.decrypt(data)
                return try decoder.decode([ClipboardItem].self, from: decrypted)
            } catch {
                NSLog("Decrypt and decode failed: \(error)")
                return nil
            }
        }
        
        if preferEncrypted {
            if let items = tryDecryptAndDecode(data: data) {
                return items
            }
            if let items = tryDecode(data: data) {
                return items
            }
            return nil
        } else {
            if let items = tryDecode(data: data) {
                return items
            }
            if let items = tryDecryptAndDecode(data: data) {
                return items
            }
            return nil
        }
    }
}

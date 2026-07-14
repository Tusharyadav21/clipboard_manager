import Foundation
import GRDB

nonisolated extension ClipboardItem: FetchableRecord, TableRecord, PersistableRecord {
    public static let databaseTableName = "clipboardItem"
}

nonisolated public final class GRDBClipboardRepository: ClipboardRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let encryptionEnabled: @Sendable () -> Bool
    
    public init(databaseURL: URL?, inMemory: Bool = false, encryptionEnabled: @escaping @Sendable () -> Bool = { false }) throws {
        self.encryptionEnabled = encryptionEnabled
        var config = Configuration()
        config.prepareDatabase { db in
            try? db.execute(sql: "PRAGMA journal_mode = WAL;")
            try? db.execute(sql: "PRAGMA synchronous = NORMAL;")
        }
        
        if inMemory {
            self.dbQueue = try DatabaseQueue(configuration: config)
        } else if let url = databaseURL {
            let fileManager = FileManager.default
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        } else {
            throw DatabaseError(message: "Database URL or inMemory must be provided")
        }
        
        let migrator = DatabaseMigratorFactory.makeMigrator()
        try migrator.migrate(dbQueue)
    }
    
    private func encryptItem(_ item: ClipboardItem) throws -> ClipboardItem {
        guard encryptionEnabled() else { return item }
        let textData = Data(item.text.utf8)
        let encrypted = try SecurityService.encrypt(textData)
        var copy = item
        copy.text = encrypted.base64EncodedString()
        return copy
    }
    
    private func decryptItem(_ item: ClipboardItem) -> ClipboardItem {
        guard encryptionEnabled(), let encryptedData = Data(base64Encoded: item.text) else { return item }
        guard let decryptedData = try? SecurityService.decrypt(encryptedData) else { return item }
        guard let decryptedText = String(data: decryptedData, encoding: .utf8) else { return item }
        var copy = item
        copy.text = decryptedText
        return copy
    }
    
    public func save(_ item: ClipboardItem) async throws {
        let itemToSave = try encryptItem(item)
        try await dbQueue.write { db in
            try itemToSave.save(db)
        }
    }
    
    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            try ClipboardItem.deleteOne(db, key: id.uuidString)
        }
    }
    
    public func fetchAll() async throws -> [ClipboardItem] {
        try await dbQueue.read { db in
            try ClipboardItem
                .order(
                    Column("isPinned").desc,
                    Column("lastUsedAt").desc,
                    Column("createdAt").desc
                )
                .fetchAll(db)
                .map { self.decryptItem($0) }
        }
    }
    
    public func search(query: String) async throws -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try await fetchAll()
        }
        
        if encryptionEnabled() {
            let allItems = try await fetchAll()
            return allItems.filter { $0.text.localizedStandardContains(trimmedQuery) }
        }
        
        return try await dbQueue.read { db in
            let sql = """
            SELECT c.* FROM clipboardItem c
            JOIN clipboardItem_fts f ON f.itemId = c.id
            WHERE f.text MATCH ?
            ORDER BY c.isPinned DESC, c.lastUsedAt DESC, c.createdAt DESC
            """
            let cleanQuery = self.cleanSearchQuery(trimmedQuery)
            return try ClipboardItem.fetchAll(db, sql: sql, arguments: [cleanQuery])
        }
    }
    
    private func cleanSearchQuery(_ query: String) -> String {
        let specialChars = CharacterSet(charactersIn: "^\"*+-~()<>")
        let components = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: specialChars).joined() }
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
        return components.isEmpty ? "" : components.joined(separator: " AND ")
    }
    
    public func clearNonPinned() async throws {
        try await dbQueue.write { db in
            try ClipboardItem
                .filter(Column("isPinned") == false)
                .deleteAll(db)
        }
    }
    
    public func prune(maxRecentCount: Int, maxPinnedCount: Int, maxAgeDays: Int) async throws -> Int {
        try await dbQueue.write { db in
            var deletedCount = 0
            
            if maxAgeDays > 0 {
                let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
                deletedCount += try ClipboardItem
                    .filter(Column("createdAt") < cutoffDate)
                    .deleteAll(db)
            }
            
            if maxPinnedCount > 0 {
                let pinnedItems = try ClipboardItem
                    .filter(Column("isPinned") == true)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
                
                if pinnedItems.count > maxPinnedCount {
                    let toKeepIds = pinnedItems.prefix(maxPinnedCount).map { $0.id.uuidString }
                    deletedCount += try ClipboardItem
                        .filter(Column("isPinned") == true)
                        .filter(!toKeepIds.contains(Column("id")))
                        .deleteAll(db)
                }
            }
            
            if maxRecentCount > 0 {
                let recentItems = try ClipboardItem
                    .filter(Column("isPinned") == false)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
                
                if recentItems.count > maxRecentCount {
                    let toKeepIds = recentItems.prefix(maxRecentCount).map { $0.id.uuidString }
                    deletedCount += try ClipboardItem
                        .filter(Column("isPinned") == false)
                        .filter(!toKeepIds.contains(Column("id")))
                        .deleteAll(db)
                }
            }
            
            return deletedCount
        }
    }
    
    public func deleteAll() async throws {
        try await dbQueue.write { db in
            try ClipboardItem.deleteAll(db)
        }
    }
    
    public func saveBatch(_ items: [ClipboardItem]) async throws {
        let itemsToSave = try items.map { try encryptItem($0) }
        try await dbQueue.write { db in
            for item in itemsToSave {
                try item.save(db)
            }
        }
    }
}
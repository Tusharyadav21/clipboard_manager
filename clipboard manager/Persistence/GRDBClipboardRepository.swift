import Foundation
import GRDB

nonisolated extension ClipboardItem: FetchableRecord, TableRecord, PersistableRecord {
    public static let databaseTableName = "clipboardItem"
}

nonisolated public final class GRDBClipboardRepository: ClipboardRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    
    public init(databaseURL: URL?, inMemory: Bool = false) throws {
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
        
        // Run migrations
        let migrator = DatabaseMigratorFactory.makeMigrator()
        try migrator.migrate(dbQueue)
    }
    
    public func save(_ item: ClipboardItem) async throws {
        try await dbQueue.write { db in
            try item.save(db)
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
        }
    }
    
    public func search(query: String) async throws -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try await fetchAll()
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
        let components = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
        return components.joined(separator: " AND ")
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
            
            // 1. Age-based expiration (e.g. 7 days old)
            if maxAgeDays > 0 {
                let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
                deletedCount += try ClipboardItem
                    .filter(Column("createdAt") < cutoffDate)
                    .deleteAll(db)
            }
            
            // 2. Count-based pruning of pinned items
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
            } else if maxPinnedCount == 0 {
                deletedCount += try ClipboardItem
                    .filter(Column("isPinned") == true)
                    .deleteAll(db)
            }
            
            // 3. Count-based pruning of recent items
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
            } else if maxRecentCount == 0 {
                deletedCount += try ClipboardItem
                    .filter(Column("isPinned") == false)
                    .deleteAll(db)
            }
            
            return deletedCount
        }
    }
}

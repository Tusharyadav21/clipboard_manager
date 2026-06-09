import Foundation
import GRDB

nonisolated public struct DatabaseMigratorFactory {
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.eraseDatabaseOnSchemaChange = false
        
        migrator.registerMigration("createClipboardItems") { db in
            try db.create(table: "clipboardItem") { t in
                t.column("id", .text).primaryKey()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("sourceAppBundleId", .text)
                t.column("sourceAppName", .text)
                t.column("isPinned", .boolean).notNull().defaults(to: false).indexed()
                t.column("lastUsedAt", .datetime)
                t.column("contentHash", .text).notNull().unique(onConflict: .replace).indexed()
                t.column("cachedByteCount", .integer).notNull()
            }
        }
        
        migrator.registerMigration("createFTS5Index") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE clipboardItem_fts USING fts5(
                    itemId UNINDEXED,
                    text
                );
                
                -- Triggers to keep FTS index in sync with clipboardItem table
                CREATE TRIGGER clipboardItem_ai AFTER INSERT ON clipboardItem BEGIN
                    INSERT INTO clipboardItem_fts(itemId, text) VALUES (new.id, new.text);
                END;
                
                CREATE TRIGGER clipboardItem_ad AFTER DELETE ON clipboardItem BEGIN
                    DELETE FROM clipboardItem_fts WHERE itemId = old.id;
                END;
                
                CREATE TRIGGER clipboardItem_au AFTER UPDATE OF text ON clipboardItem BEGIN
                    UPDATE clipboardItem_fts SET text = new.text WHERE itemId = new.id;
                END;
            """)
        }
        
        return migrator
    }
}

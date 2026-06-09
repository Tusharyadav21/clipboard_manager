import Foundation

public protocol ClipboardRepository: Sendable {
    /// Save or update an item in the repository.
    func save(_ item: ClipboardItem) async throws
    
    /// Delete an item by ID.
    func delete(id: UUID) async throws
    
    /// Fetch all items in the repository, ordered.
    func fetchAll() async throws -> [ClipboardItem]
    
    /// Search items matching the query.
    func search(query: String) async throws -> [ClipboardItem]
    
    /// Delete all items that are not pinned.
    func clearNonPinned() async throws
    
    /// Prune items exceeding the count limit or older than the specified age.
    /// Returns the list of deleted items (or just performs deletion).
    func prune(maxRecentCount: Int, maxPinnedCount: Int, maxAgeDays: Int) async throws -> Int
}

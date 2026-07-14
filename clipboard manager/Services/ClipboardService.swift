import AppKit
import Foundation

public actor ClipboardService {
    private let repository: ClipboardRepository
    private var items: [ClipboardItem] = []
    
    public init(repository: ClipboardRepository) {
        self.repository = repository
    }
    
    private func persist<T>(_ operation: String, _ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            NSLog("ClipboardService: \(operation) failed: \(error)")
            return nil
        }
    }
    
    private var isPersistenceEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.persistHistory)
    }
    
    public func loadItems() async throws -> [ClipboardItem] {
        if isPersistenceEnabled {
            do {
                self.items = try await repository.fetchAll()
            } catch {
                NSLog("Failed to load items from repository: \(error)")
                self.items = []
            }
        } else {
            self.items = []
        }
        return items
    }
    
    public func search(_ query: String) async throws -> [ClipboardItem] {
        guard isPersistenceEnabled else {
            return items.filter { $0.text.localizedStandardContains(query) }
        }
        return try await repository.search(query: query)
    }
    
    public func getItems() -> [ClipboardItem] {
        return items
    }
    
    public func addClipboardText(_ text: String, sourceAppBundleId: String?, sourceAppName: String?) async throws -> [ClipboardItem] {
        guard !text.isEmpty else { return items }
        if isExcluded(sourceAppBundleId) { return items }
        let normalizedText = normalizedTextForStorage(text)
        guard !normalizedText.isEmpty else { return items }
        
        // Drop if sensitive content
        guard !SensitiveContentPolicy.isSensitive(text: normalizedText) else { return items }
        
        let hash = ClipboardItem.hash(normalizedText)
        if let existingIndex = items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = items.remove(at: existingIndex)
            existing.lastUsedAt = Date()
            items.insert(existing, at: 0)
            
            if isPersistenceEnabled {
                await persist("save.existing") { try await repository.save(existing) }
            }
        } else {
            let newItem = ClipboardItem(
                text: normalizedText,
                sourceAppBundleId: sourceAppBundleId,
                sourceAppName: sourceAppName
            )
            items.insert(newItem, at: 0)
            
            if isPersistenceEnabled {
                await persist("save.new") { try await repository.save(newItem) }
            }
        }
        
        try await pruneItems()
        return items
    }
    
    public func togglePin(_ item: ClipboardItem) async throws -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }
        items[index].isPinned.toggle()
        
        if isPersistenceEnabled {
            await persist("togglePin.save") { try await repository.save(items[index]) }
        }
        
        sortPinnedFirst()
        try await pruneItems()
        return items
    }
    
    public func touchItem(_ item: ClipboardItem) async throws -> [ClipboardItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }
        items[index].lastUsedAt = Date()
        if isPersistenceEnabled {
            await persist("touchItem.save") { try await repository.save(items[index]) }
        }
        return items
    }
    
    public func delete(_ item: ClipboardItem) async throws -> [ClipboardItem] {
        items.removeAll { $0.id == item.id }
        if isPersistenceEnabled {
            await persist("delete") { try await repository.delete(id: item.id) }
        }
        return items
    }
    
    public func clearNonPinned() async throws -> [ClipboardItem] {
        items.removeAll { !$0.isPinned }
        if isPersistenceEnabled {
            await persist("clearNonPinned") { try await repository.clearNonPinned() }
        }
        return items
    }
    
    public func setPersistHistoryEnabled(_ enabled: Bool) async throws -> [ClipboardItem] {
        if enabled {
            await persist("saveBatch") { try await repository.saveBatch(items) }
        } else {
            await persist("deleteAll") { try await repository.deleteAll() }
        }
        return items
    }
    
    public func pruneItems() async throws {
        let maxRecent = Constants.maxRecentItems
        let maxPinned = Constants.maxPinnedItems
        let maxAgeDays = Constants.autoDeleteDays
        
        if isPersistenceEnabled {
            await persist("prune") { try await repository.prune(maxRecentCount: maxRecent, maxPinnedCount: maxPinned, maxAgeDays: maxAgeDays) }
            self.items = try await repository.fetchAll()
        } else {
            // In-memory only pruning
            let pinned = items.filter { $0.isPinned }.prefix(maxPinned)
            let recent = items.filter { !$0.isPinned }.prefix(maxRecent)
            
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
            let filteredPinned = pinned.filter { $0.createdAt > cutoffDate }
            let filteredRecent = recent.filter { $0.createdAt > cutoffDate }
            
            self.items = Array(filteredPinned) + Array(filteredRecent)
        }
    }
    
    public func trimMemory(aggressive: Bool) async -> [ClipboardItem] {
        let maxRecent = aggressive ? Constants.aggressiveRecentLimit : Constants.maxRecentItems
        let maxPinned = aggressive ? Constants.aggressivePinnedLimit : Constants.maxPinnedItems
        
        let pinned = items.filter { $0.isPinned }.prefix(maxPinned)
        let recent = items.filter { !$0.isPinned }.prefix(maxRecent)
        self.items = Array(pinned) + Array(recent)
        
        return items
    }
    
    private func sortPinnedFirst() {
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        items = pinned + unpinned
    }
    
    private func isExcluded(_ bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        let exclusions = UserDefaults.standard.stringArray(forKey: SettingsKeys.exclusions) ?? []
        return exclusions.contains(bundleId)
    }
    
    private func normalizedTextForStorage(_ text: String) -> String {
        var normalized = String(text.prefix(Constants.maxCharactersPerItem))
        if normalized.utf8.count > Constants.maxBytesPerItem {
            while normalized.utf8.count > Constants.maxBytesPerItem && !normalized.isEmpty {
                normalized.removeLast()
            }
        }
        return normalized
    }
}

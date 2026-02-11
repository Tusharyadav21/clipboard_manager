import AppKit
import Combine
import CryptoKit
import Foundation

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
    var sourceAppBundleId: String?
    var sourceAppName: String?
    var isPinned: Bool
    var lastUsedAt: Date?
    var contentHash: String

    init(text: String, sourceApp: NSRunningApplication?) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.sourceAppBundleId = sourceApp?.bundleIdentifier
        self.sourceAppName = sourceApp?.localizedName
        self.isPinned = false
        self.lastUsedAt = nil
        self.contentHash = ClipboardItem.hash(text)
    }

    static func hash(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0\(hex)" : hex
        }.joined()
    }
}

private final class PersistenceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func bump() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func isLatest(_ value: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == value
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var searchQuery: String = ""
    @Published var showOnboarding: Bool = false

    private var saveCancellable: AnyCancellable?
    private var persistTask: Task<Void, Never>?
    private let persistenceGate = PersistenceGate()
    private let maxItems = 25
    private let maxPinnedItems = 30
    private let maxStoredCharactersPerItem = 80_000
    private let maxStoredBytesPerItem = 256 * 1024
    private let maxTotalPinnedBytes = 2 * 1024 * 1024
    private let maxTotalRecentBytes = 3 * 1024 * 1024

    private let historyURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        saveCancellable = $items
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.persistIfEnabled()
            }
    }

    deinit {
        persistTask?.cancel()
    }

    var filteredItems: [ClipboardItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return items }
        return items.filter { $0.text.localizedStandardContains(query) }
    }

    var pinnedItems: [ClipboardItem] {
        filteredItems.filter { $0.isPinned }
    }

    var recentItems: [ClipboardItem] {
        filteredItems.filter { !$0.isPinned }
    }

    func addClipboardText(_ text: String, sourceApp: NSRunningApplication?) {
        guard !text.isEmpty else { return }
        if isExcluded(sourceApp) { return }
        let normalizedText = normalizedTextForStorage(text)
        guard !normalizedText.isEmpty else { return }

        let hash = ClipboardItem.hash(normalizedText)
        if let existingIndex = items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = items.remove(at: existingIndex)
            existing.lastUsedAt = Date()
            items.insert(existing, at: 0)
            return
        }

        var newItem = ClipboardItem(text: normalizedText, sourceApp: sourceApp)
        newItem.lastUsedAt = Date()
        items.insert(newItem, at: 0)
        pruneIfNeeded()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].isPinned.toggle()
        sortPinnedFirst()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearNonPinned() {
        items.removeAll { !$0.isPinned }
    }

    func copyItemToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)

        if let index = items.firstIndex(of: item) {
            items[index].lastUsedAt = Date()
        }

    }

    func presentOnboardingIfNeeded() {
        if UserDefaults.standard.object(forKey: SettingsKeys.hasCompletedOnboarding) == nil {
            showOnboarding = true
        }
    }

    func completeOnboarding(persistHistory: Bool, launchAtLogin: Bool) {
        UserDefaults.standard.set(true, forKey: SettingsKeys.hasCompletedOnboarding)
        UserDefaults.standard.set(persistHistory, forKey: SettingsKeys.persistHistory)
        UserDefaults.standard.set(launchAtLogin, forKey: SettingsKeys.launchAtLogin)
        SettingsHelper.setLaunchAtLogin(launchAtLogin)
        showOnboarding = false
        setPersistHistoryEnabled(persistHistory)
    }

    func loadOnLaunch() {
        if UserDefaults.standard.bool(forKey: SettingsKeys.persistHistory) {
            loadHistory()
        }
    }

    func setPersistHistoryEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.persistHistory)
        if enabled {
            persistIfEnabled()
        } else {
            persistTask?.cancel()
            _ = persistenceGate.bump()
            deletePersistedHistoryFile()
        }
    }

    func setEncryptHistoryAtRestEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.encryptHistoryAtRest)
        if enabled {
            SecureHistoryCrypto.prewarmKey()
        }
        guard UserDefaults.standard.bool(forKey: SettingsKeys.persistHistory) else { return }
        persistIfEnabled()
    }

    func trimMemory(aggressive: Bool) {
        let trimmed = aggressive ? applyingAggressiveBudgets(to: items) : applyingStorageBudgets(to: items)
        guard trimmed != items else { return }
        items = trimmed
    }

    private func persistIfEnabled() {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.persistHistory) else { return }
        let encryptAtRest = UserDefaults.standard.bool(forKey: SettingsKeys.encryptHistoryAtRest)
        // Snapshot on main to avoid concurrent mutation
        let itemsSnapshot = self.items
        let historyURL = self.historyURL
        let generation = persistenceGate.bump()

        persistTask?.cancel()
        persistTask = Task.detached(priority: .utility) { [persistenceGate] in
            guard !Task.isCancelled else { return }
            do {
                guard persistenceGate.isLatest(generation) else { return }
                let dir = historyURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                guard !Task.isCancelled, persistenceGate.isLatest(generation) else { return }
                let data = try JSONEncoder().encode(itemsSnapshot)
                guard !Task.isCancelled, persistenceGate.isLatest(generation) else { return }
                if encryptAtRest {
                    let encrypted = try SecureHistoryCrypto.encrypt(data)
                    guard !Task.isCancelled, persistenceGate.isLatest(generation) else { return }
                    try encrypted.write(to: historyURL, options: .atomic)
                } else {
                    guard !Task.isCancelled, persistenceGate.isLatest(generation) else { return }
                    try data.write(to: historyURL, options: .atomic)
                }
            } catch {
                NSLog("Failed to save history: \(error)")
            }
        }
    }

    private func loadHistory() {
        do {
            let data = try Data(contentsOf: historyURL)
            let encryptAtRest = UserDefaults.standard.bool(forKey: SettingsKeys.encryptHistoryAtRest)

            if let decoded = decodeItems(from: data, preferEncrypted: encryptAtRest) {
                self.items = sanitizedLoadedItems(decoded)
                if encryptAtRest, (try? JSONDecoder().decode([ClipboardItem].self, from: data)) != nil {
                    // Plaintext file encountered while encryption is enabled; rewrite encrypted.
                    persistIfEnabled()
                }
                return
            }
        } catch {
            NSLog("No saved history or failed to load: \(error)")
        }
    }

    private func deletePersistedHistoryFile() {
        do {
            if FileManager.default.fileExists(atPath: historyURL.path) {
                try FileManager.default.removeItem(at: historyURL)
            }
        } catch {
            NSLog("Failed to remove persisted history: \(error)")
        }
    }

    private func decodeItems(from data: Data, preferEncrypted: Bool) -> [ClipboardItem]? {
        if preferEncrypted {
            if let decrypted = try? SecureHistoryCrypto.decrypt(data),
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
        if let decrypted = try? SecureHistoryCrypto.decrypt(data),
           let items = try? JSONDecoder().decode([ClipboardItem].self, from: decrypted) {
            return items
        }
        return nil
    }

    private func pruneIfNeeded() {
        items = applyingStorageBudgets(to: items)
    }

    private func sortPinnedFirst() {
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        items = applyingStorageBudgets(to: pinned + unpinned)
    }

    private func isExcluded(_ sourceApp: NSRunningApplication?) -> Bool {
        guard let bundleId = sourceApp?.bundleIdentifier else { return false }
        let exclusions = UserDefaults.standard.stringArray(forKey: SettingsKeys.exclusions) ?? []
        return exclusions.contains(bundleId)
    }

    private func normalizedTextForStorage(_ text: String) -> String {
        var normalized = String(text.prefix(maxStoredCharactersPerItem))
        if normalized.utf8.count > maxStoredBytesPerItem {
            while normalized.utf8.count > maxStoredBytesPerItem && !normalized.isEmpty {
                normalized.removeLast()
            }
        }
        return normalized
    }

    private func sanitizedLoadedItems(_ loaded: [ClipboardItem]) -> [ClipboardItem] {
        var seenHashes = Set<String>()
        var sanitized: [ClipboardItem] = []
        sanitized.reserveCapacity(loaded.count)
        for item in loaded {
            let normalizedText = normalizedTextForStorage(item.text)
            guard !normalizedText.isEmpty else { continue }
            var normalizedItem = item
            normalizedItem.text = normalizedText
            normalizedItem.contentHash = ClipboardItem.hash(normalizedText)
            guard seenHashes.insert(normalizedItem.contentHash).inserted else { continue }
            sanitized.append(normalizedItem)
        }
        return applyingStorageBudgets(to: sanitized)
    }

    private func applyingStorageBudgets(to source: [ClipboardItem]) -> [ClipboardItem] {
        let pinned = budgetedItems(
            source.filter { $0.isPinned },
            countLimit: maxPinnedItems,
            byteLimit: maxTotalPinnedBytes
        )
        let recent = budgetedItems(
            source.filter { !$0.isPinned },
            countLimit: maxItems,
            byteLimit: maxTotalRecentBytes
        )
        return pinned + recent
    }

    private func applyingAggressiveBudgets(to source: [ClipboardItem]) -> [ClipboardItem] {
        let pinned = budgetedItems(
            source.filter { $0.isPinned },
            countLimit: min(12, maxPinnedItems),
            byteLimit: 512 * 1024
        )
        let recent = budgetedItems(
            source.filter { !$0.isPinned },
            countLimit: min(10, maxItems),
            byteLimit: 512 * 1024
        )
        return pinned + recent
    }

    private func budgetedItems(_ source: [ClipboardItem], countLimit: Int, byteLimit: Int) -> [ClipboardItem] {
        var limited = source
        if limited.count > countLimit {
            limited = Array(limited.prefix(countLimit))
        }

        let budget = max(byteLimit, 0)
        var consumedBytes = 0
        var result: [ClipboardItem] = []
        result.reserveCapacity(limited.count)
        for item in limited {
            let itemBytes = item.text.utf8.count
            if consumedBytes + itemBytes > budget {
                break
            }
            result.append(item)
            consumedBytes += itemBytes
        }
        return result
    }
}

enum SettingsKeys {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let persistHistory = "persistHistory"
    static let launchAtLogin = "launchAtLogin"
    static let autoPaste = "autoPaste"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let glassIntensity = "glassIntensity"
    static let encryptHistoryAtRest = "encryptHistoryAtRest"
    static let appTheme = "appTheme"
    static let exclusions = "exclusions"
}

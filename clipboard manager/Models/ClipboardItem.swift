import AppKit
import CryptoKit
import Foundation

nonisolated public struct ClipboardItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var createdAt: Date
    public var sourceAppBundleId: String?
    public var sourceAppName: String?
    public var isPinned: Bool
    public var lastUsedAt: Date?
    public var contentHash: String
    public var cachedByteCount: Int

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        isPinned: Bool = false,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName
        self.isPinned = isPinned
        self.lastUsedAt = lastUsedAt
        self.contentHash = ClipboardItem.hash(text)
        self.cachedByteCount = text.utf8.count
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, sourceAppBundleId, sourceAppName, isPinned, lastUsedAt, contentHash, cachedByteCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let text = try container.decode(String.self, forKey: .text)
        self.text = text
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.sourceAppBundleId = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleId)
        self.sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        self.contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash) ?? ClipboardItem.hash(text)
        self.cachedByteCount = try container.decodeIfPresent(Int.self, forKey: .cachedByteCount) ?? text.utf8.count
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(sourceAppBundleId, forKey: .sourceAppBundleId)
        try container.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(cachedByteCount, forKey: .cachedByteCount)
    }

    @MainActor
    public init(text: String, sourceApp: NSRunningApplication?) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.sourceAppBundleId = sourceApp?.bundleIdentifier
        self.sourceAppName = sourceApp?.localizedName
        self.isPinned = false
        self.lastUsedAt = nil
        self.contentHash = ClipboardItem.hash(text)
        self.cachedByteCount = text.utf8.count
    }

    public static func hash(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0\(hex)" : hex
        }.joined()
    }
}

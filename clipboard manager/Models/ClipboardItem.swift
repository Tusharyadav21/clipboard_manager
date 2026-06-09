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

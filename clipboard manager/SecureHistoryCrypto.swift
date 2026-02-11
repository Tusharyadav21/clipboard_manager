import CryptoKit
import Foundation
import Security

enum SecureHistoryCrypto {
    nonisolated private static let service = "com.clipboardmanager.history"
    nonisolated private static let account = "history-encryption-key"
    nonisolated private static let keyLock = NSLock()
    nonisolated private static let inMemoryKeyCache = NSCache<NSString, NSData>()
    nonisolated private static let inMemoryKeyCacheKey: NSString = "history-encryption-key"

    nonisolated private struct EncryptedPayload: Codable {
        let version: Int
        let nonce: Data
        let ciphertext: Data
        let tag: Data
    }

    nonisolated static func encrypt(_ data: Data) throws -> Data {
        let key = try loadOrCreateKey()
        let sealed = try AES.GCM.seal(data, using: key)
        let payload = EncryptedPayload(
            version: 1,
            nonce: Data(sealed.nonce),
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
        return try JSONEncoder().encode(payload)
    }

    nonisolated static func decrypt(_ data: Data) throws -> Data {
        let key = try loadOrCreateKey()
        let payload = try JSONDecoder().decode(EncryptedPayload.self, from: data)
        let nonce = try AES.GCM.Nonce(data: payload.nonce)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: payload.ciphertext, tag: payload.tag)
        return try AES.GCM.open(box, using: key)
    }

    nonisolated static func prewarmKey() {
        do {
            _ = try loadOrCreateKey()
        } catch {
            NSLog("Failed to prewarm history key: \(error)")
        }
    }

    nonisolated private static func loadOrCreateKey() throws -> SymmetricKey {
        if let cachedData = inMemoryKeyCache.object(forKey: inMemoryKeyCacheKey) {
            return SymmetricKey(data: cachedData as Data)
        }

        keyLock.lock()
        defer { keyLock.unlock() }

        if let cachedData = inMemoryKeyCache.object(forKey: inMemoryKeyCacheKey) {
            return SymmetricKey(data: cachedData as Data)
        }

        if let keyData = try readKey() {
            cacheKeyData(keyData)
            return SymmetricKey(data: keyData)
        }

        let candidateKey = SymmetricKey(size: .bits256)
        let candidateData = candidateKey.withUnsafeBytes { Data($0) }
        try saveKeyIfMissing(candidateData)

        if let persistedData = try readKey() {
            cacheKeyData(persistedData)
            return SymmetricKey(data: persistedData)
        }

        throw NSError(domain: "SecureHistoryCrypto", code: -1, userInfo: nil)
    }

    nonisolated private static func readKey() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: "SecureHistoryCrypto", code: Int(status), userInfo: nil)
        }
        return data
    }

    nonisolated private static func saveKeyIfMissing(_ data: Data) throws {
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess || status == errSecDuplicateItem {
            return
        }

        guard status == errSecSuccess else {
            throw NSError(domain: "SecureHistoryCrypto", code: Int(status), userInfo: nil)
        }
    }

    nonisolated private static func cacheKeyData(_ data: Data) {
        inMemoryKeyCache.setObject(data as NSData, forKey: inMemoryKeyCacheKey)
    }
}

import AppKit
import SwiftUI

public final class AppIconCache {
    public static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 2 * 1024 * 1024
    }

    public func image(for bundleId: String) -> NSImage? {
        cache.object(forKey: bundleId as NSString)
    }

    public func set(_ image: NSImage, for bundleId: String) {
        let thumbnail = thumbnailImage(from: image)
        cache.setObject(thumbnail, forKey: bundleId as NSString, cost: imageCost(thumbnail))
    }

    public func clear() {
        cache.removeAllObjects()
    }

    private func imageCost(_ image: NSImage) -> Int {
        if let rep = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return rep.pixelsWide * rep.pixelsHigh * 4
        }
        return 256 * 256 * 4
    }

    private func thumbnailImage(from image: NSImage) -> NSImage {
        let targetSize = NSSize(width: 36, height: 36)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()
        return thumbnail
    }
}

public struct AppIcon: View {
    public var bundleId: String?
    @State private var image: NSImage?

    public init(bundleId: String?) {
        self.bundleId = bundleId
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: bundleId) {
            image = resolveIcon(for: bundleId)
        }
    }

    private func resolveIcon(for bundleId: String?) -> NSImage? {
        guard let bundleId else { return nil }
        if let cached = AppIconCache.shared.image(for: bundleId) {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let resolved = NSWorkspace.shared.icon(forFile: appURL.path)
        AppIconCache.shared.set(resolved, for: bundleId)
        return resolved
    }
}

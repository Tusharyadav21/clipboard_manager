import AppKit
import Foundation

public final class ClipboardMonitorService: Sendable {
    private let onCheck: @Sendable (String, String?, String?) async -> Void
    private let interval: TimeInterval
    
    public init(
        interval: TimeInterval = Constants.clipboardPollInterval,
        onCheck: @escaping @Sendable (String, String?, String?) async -> Void
    ) {
        self.interval = interval
        self.onCheck = onCheck
    }
    
    /// Starts the clipboard monitoring loop in a background Task.
    /// Returns the Task so it can be cancelled later.
    public func start() -> Task<Void, Never> {
        Task {
            var lastChangeCount = await MainActor.run { NSPasteboard.general.changeCount }
            
            while !Task.isCancelled {
                do {
                    // Convert interval in seconds to nanoseconds
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }
                
                guard !Task.isCancelled else { break }
                
                let changeCount = await MainActor.run { NSPasteboard.general.changeCount }
                guard changeCount != lastChangeCount else { continue }
                lastChangeCount = changeCount
                
                let result = await MainActor.run { () -> (String, String?, String?)? in
                    autoreleasepool {
                        let pb = NSPasteboard.general
                        // Quick type-only check — full regex scan happens in ClipboardService
                        if let types = pb.types {
                            for type in SensitiveContentPolicy.sensitiveTypes where types.contains(type) {
                                return nil
                            }
                        }
                        
                        if let text = pb.string(forType: .string) {
                            let source = NSWorkspace.shared.frontmostApplication
                            return (text, source?.bundleIdentifier, source?.localizedName)
                        }
                        return nil
                    }
                }
                
                if let (text, bundleId, appName) = result {
                    await onCheck(text, bundleId, appName)
                }
            }
        }
    }
}

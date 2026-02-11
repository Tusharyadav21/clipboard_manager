import AppKit
import Foundation

final class ClipboardMonitor {
    var onChange: ((String, NSRunningApplication?) -> Void)?
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        autoreleasepool {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount != lastChangeCount else { return }
            lastChangeCount = pasteboard.changeCount

            if let text = pasteboard.string(forType: .string) {
                let source = NSWorkspace.shared.frontmostApplication
                onChange?(text, source)
            }
        }
    }
}

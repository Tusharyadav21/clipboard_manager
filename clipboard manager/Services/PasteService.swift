import AppKit
import ApplicationServices
import Foundation

@MainActor
public final class PasteService {
    public static let shared = PasteService()
    
    private init() {}
    
    public func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    public func requestIfNeeded() {
        guard !isTrusted() else { return }
        let key = "axTrustedCheckOptionPrompt" as CFString
        let options = [key: true as CFBoolean] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Prepares pasteboard content and initiates direct paste into the specified target application if auto-paste is enabled.
    public func paste(item: ClipboardItem, targetApp: NSRunningApplication?) async {
        // 1. Copy item to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        
        // 2. Check if auto-paste is enabled
        guard UserDefaults.standard.bool(forKey: SettingsKeys.autoPaste) else {
            return
        }
        
        // 3. Verify accessibility trust
        guard isTrusted() else {
            return
        }
        
        // 4. Perform the paste sequence
        await performPaste(targetApp: targetApp, attempt: 1)
    }
    
    private func performPaste(targetApp: NSRunningApplication?, attempt: Int) async {
        guard let target = targetApp else {
            await simulatePaste()
            return
        }
        
        if attempt > Constants.maxPasteAttempts {
            await simulatePaste()
            return
        }
        
        // Activate target application
        target.activate(options: [.activateIgnoringOtherApps])
        
        // Wait using async/await task sleep
        do {
            try await Task.sleep(nanoseconds: UInt64(Constants.pasteAttemptDelay * 1_000_000_000))
        } catch {
            return
        }
        
        let frontmost = NSWorkspace.shared.frontmostApplication
        let didActivateTarget = frontmost?.processIdentifier == target.processIdentifier
        
        if didActivateTarget {
            await simulatePaste()
        } else {
            // Retry activation
            await performPaste(targetApp: target, attempt: attempt + 1)
        }
    }
    
    private func simulatePaste() async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}

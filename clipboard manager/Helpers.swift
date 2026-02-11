import AppKit
import ApplicationServices
import Foundation
import ServiceManagement

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}

enum OverlayPositioningHelper {
    static func anchorPoint() -> CGPoint {
        if let caret = focusedCaretFrame() {
            return CGPoint(x: caret.midX, y: caret.minY)
        }
        if let frame = focusedElementFrame() {
            return CGPoint(x: frame.minX + 24, y: frame.minY)
        }
        return NSEvent.mouseLocation
    }

    private static func focusedCaretFrame() -> CGRect? {
        guard let focusedElement = focusedElement() else { return nil }

        var selectedRangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )

        guard rangeStatus == .success,
              let selectedRangeValue,
              CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else { return nil }

        var boundsValue: CFTypeRef?
        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsValue
        )

        guard boundsStatus == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        let axBounds = unsafeBitCast(boundsValue, to: AXValue.self)
        guard AXValueGetType(axBounds) == .cgRect else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(axBounds, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func focusedElementFrame() -> CGRect? {
        guard let focusedElement = focusedElement() else { return nil }

        var positionValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        guard positionResult == .success,
              let positionValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID() else { return nil }
        let axPosition = unsafeBitCast(positionValue, to: AXValue.self)
        guard AXValueGetType(axPosition) == .cgPoint else { return nil }

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSizeAttribute as CFString,
            &sizeValue
        )
        guard sizeResult == .success,
              let sizeValue,
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let axSize = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetType(axSize) == .cgSize else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(axPosition, .cgPoint, &origin) else { return nil }
        guard AXValueGetValue(axSize, .cgSize, &size) else { return nil }

        let frame = CGRect(origin: origin, size: size)
        return frame
    }

    private static func focusedElement() -> AXUIElement? {
        guard AccessibilityHelper.isTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusedResult == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(focused, to: AXUIElement.self)
    }
}

enum SettingsHelper {
    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update login item: \(error)")
        }
    }
}
extension SettingsHelper {
    static func excludeFrontmostApp() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmost.bundleIdentifier else { return }
        var exclusions = UserDefaults.standard.stringArray(forKey: SettingsKeys.exclusions) ?? []
        if !exclusions.contains(bundleId) {
            exclusions.append(bundleId)
            UserDefaults.standard.set(exclusions, forKey: SettingsKeys.exclusions)
        }
    }
}

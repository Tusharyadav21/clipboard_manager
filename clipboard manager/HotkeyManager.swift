import AppKit
import Carbon

final class HotkeyManager {
    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    static let defaultModifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)

    var onHotKey: (() -> Void)?

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?

    func registerDefault() {
        register(keyCode: Self.defaultKeyCode, modifiers: Self.defaultModifiers)
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        unregisterHotKey()
        installEventHandlerIfNeeded()

        let eventHotKeyID = EventHotKeyID(signature: OSType(0x434C5042), id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, eventHotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("Failed to register hotkey: \(status)")
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let this = self
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onHotKey?()
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(this).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("Failed to install hotkey handler: \(status)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    func cancel() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
        unregisterHotKey()
    }

    deinit {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}

import AppKit
import Carbon

final class HotkeyManager {
    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    static let defaultModifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)

    var onHotKey: (() -> Void)?

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private var userDataPtr: UnsafeMutableRawPointer?

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

        let userDataPtr = Unmanaged.passRetained(self).toOpaque()
        self.userDataPtr = userDataPtr

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
            userDataPtr,
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

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let userDataPtr {
            Unmanaged<HotkeyManager>.fromOpaque(userDataPtr).release()
        }
    }
}

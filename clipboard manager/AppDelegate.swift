import AppKit
import Carbon
import Dispatch
import SwiftUI

private let hotkeyDidChangeNotification = Notification.Name("hotkeyDidChange")
private let defaultHotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_V)
private let defaultHotkeyModifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore()
    private let monitor = ClipboardMonitor()
    private let hotkey = HotkeyManager()

    private var statusItem: NSStatusItem?
    private var overlayPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var eventMonitor: EventMonitor?
    private var keyMonitor: Any?
    private var pasteTargetApp: NSRunningApplication?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureHotkeyDefaults()
        setupOverlayPanel()
        setupStatusItem()
        setupHotkey()
        setupClipboardMonitor()
        setupOverlayDismissObservers()
        setupMemoryPressureMonitoring()
        store.loadOnLaunch()
        store.presentOnboardingIfNeeded()
    }

    private func setupOverlayPanel() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.transient]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = PopoverView(
            onSelectItem: { [weak self] item in
                self?.handleSelection(item: item)
            },
            onClose: { [weak self] in
                self?.closeOverlay()
            },
            onOpenSettings: { [weak self] in
                self?.showSettingsWindow()
            }
        )
        .environmentObject(store)
        .frame(width: 400, height: 460)

        panel.contentViewController = NSHostingController(rootView: rootView)
        overlayPanel = panel
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
            button.action = #selector(toggleOverlay(_:))
            button.target = self
        }

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self,
                  let panel = self.overlayPanel,
                  panel.isVisible else { return }
            if !panel.frame.contains(event.locationInWindow) {
                self.closeOverlay()
            }
        }
        eventMonitor?.start()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let panel = self.overlayPanel,
                  panel.isVisible else { return event }

            switch event.keyCode {
            case 53: // Esc
                self.closeOverlay()
                return nil
            case 125: // Down
                NotificationCenter.default.post(name: .overlaySelectNext, object: nil)
                return nil
            case 126: // Up
                NotificationCenter.default.post(name: .overlaySelectPrevious, object: nil)
                return nil
            case 36, 76: // Return / Enter
                NotificationCenter.default.post(name: .overlayConfirmSelection, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func setupHotkey() {
        hotkey.onHotKey = { [weak self] in
            self?.toggleOverlay(nil)
        }
        registerHotkeyFromSettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyChanged),
            name: hotkeyDidChangeNotification,
            object: nil
        )
    }

    private func setupClipboardMonitor() {
        monitor.onChange = { [weak self] text, source in
            self?.store.addClipboardText(text, sourceApp: source)
        }
        monitor.start()
    }

    private func setupOverlayDismissObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleActiveSpaceDidChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleScreenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func toggleOverlay(_ sender: Any?) {
        guard let panel = overlayPanel else { return }
        if panel.isVisible {
            closeOverlay()
        } else {
            showOverlay()
        }
    }

    private func showOverlay() {
        guard let panel = overlayPanel else { return }

        pasteTargetApp = NSWorkspace.shared.frontmostApplication
        positionOverlay(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func closeOverlay() {
        overlayPanel?.orderOut(nil)
        AppIconCache.shared.clear()
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let rootView = SettingsView().environmentObject(store)
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 560))
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        closeOverlay()
        NSApp.activate()
        settingsWindow?.center()
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func handleSelection(item: ClipboardItem) {
        store.copyItemToPasteboard(item)
        closeOverlay()
        let target = pasteTargetApp
        target?.activate()

        let directPasteEnabled = UserDefaults.standard.object(forKey: SettingsKeys.autoPaste) as? Bool ?? true
        guard directPasteEnabled else { return }

        guard AccessibilityHelper.isTrusted() else { return }

        pasteIntoTargetApp(target, attempt: 0)
    }

    private func positionOverlay(_ panel: NSPanel) {
        let panelSize = panel.frame.size
        let anchor = OverlayPositioningHelper.anchorPoint()
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(anchor) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let rawX = anchor.x - 24
        let rawY = anchor.y - panelSize.height - 10

        let x = min(max(rawX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let y = max(min(rawY, visibleFrame.maxY - panelSize.height - 8), visibleFrame.minY + 8)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func handleActiveSpaceDidChange() {
        closeOverlay()
    }

    @objc private func handleScreenParametersDidChange() {
        closeOverlay()
    }

    @objc private func handleAppDidResignActive() {
        closeOverlay()
    }

    @objc private func handleHotkeyChanged() {
        registerHotkeyFromSettings()
    }

    private func ensureHotkeyDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKeys.hotkeyKeyCode) == nil {
            defaults.set(Int(defaultHotkeyKeyCode), forKey: SettingsKeys.hotkeyKeyCode)
        }
        if defaults.object(forKey: SettingsKeys.hotkeyModifiers) == nil {
            defaults.set(Int(defaultHotkeyModifiers), forKey: SettingsKeys.hotkeyModifiers)
        }
    }

    private func registerHotkeyFromSettings() {
        let defaults = UserDefaults.standard
        let storedKeyCode = UInt32(defaults.integer(forKey: SettingsKeys.hotkeyKeyCode))
        let storedModifiers = UInt32(defaults.integer(forKey: SettingsKeys.hotkeyModifiers))
        let keyCode = storedKeyCode == 0 ? defaultHotkeyKeyCode : storedKeyCode
        let modifiers = storedModifiers == 0 ? defaultHotkeyModifiers : storedModifiers
        hotkey.register(keyCode: keyCode, modifiers: modifiers)
    }

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.memoryPressureSource else { return }
            let events = source.data
            if events.contains(.critical) {
                self.store.trimMemory(aggressive: true)
                AppIconCache.shared.clear()
            } else if events.contains(.warning) {
                self.store.trimMemory(aggressive: false)
                AppIconCache.shared.clear()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func pasteIntoTargetApp(_ target: NSRunningApplication?, attempt: Int) {
        let maxAttempts = 8
        if target == nil {
            AccessibilityHelper.simulatePaste()
            return
        }

        if attempt > maxAttempts {
            AccessibilityHelper.simulatePaste()
            return
        }

        target?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            let frontmost = NSWorkspace.shared.frontmostApplication
            let didActivateTarget = frontmost?.processIdentifier == target?.processIdentifier
            if didActivateTarget {
                AccessibilityHelper.simulatePaste()
            } else {
                self?.pasteIntoTargetApp(target, attempt: attempt + 1)
            }
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        memoryPressureSource?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension Notification.Name {
    static let overlaySelectNext = Notification.Name("overlaySelectNext")
    static let overlaySelectPrevious = Notification.Name("overlaySelectPrevious")
    static let overlayConfirmSelection = Notification.Name("overlayConfirmSelection")
}

final class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        stop()
    }
}

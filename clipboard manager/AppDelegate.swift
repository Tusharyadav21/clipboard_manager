import AppKit
import Carbon
import Dispatch
import SwiftUI

private let defaultHotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_V)
private let defaultHotkeyModifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let repository: GRDBClipboardRepository
    let service: ClipboardService
    let viewModel: ClipboardViewModel
    
    private var monitorTask: Task<Void, Never>?
    private let hotkey = HotkeyManager()

    private var statusItem: NSStatusItem?
    private var overlayPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var eventMonitor: EventMonitor?
    nonisolated(unsafe) private var keyMonitor: Any?
    private var pasteTargetApp: NSRunningApplication?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    override init() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
            let dbURL = dir.appendingPathComponent("clipboard_history.sqlite")
            
            let repo = try GRDBClipboardRepository(databaseURL: dbURL)
            self.repository = repo
            
            let service = ClipboardService(repository: repo)
            self.service = service
            
            self.viewModel = ClipboardViewModel(clipboardService: service)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureHotkeyDefaults()
        setupOverlayPanel()
        setupStatusItem()
        setupHotkey()
        setupClipboardMonitor()
        setupOverlayDismissObservers()
        setupMemoryPressureMonitoring()
        
        // Load data and migrate legacy history asynchronously
        Task {
            await LegacyJSONImporter.migrateIfNeeded(repository: repository)
            await MainActor.run {
                viewModel.loadOnLaunch()
                viewModel.presentOnboardingIfNeeded()
            }
        }
    }

    private func setupOverlayPanel() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.overlayWidth, height: Constants.overlayHeight),
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
        .environmentObject(viewModel)
        .frame(width: Constants.overlayWidth, height: Constants.overlayHeight)

        panel.contentViewController = NSHostingController(rootView: rootView)
        overlayPanel = panel
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu

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
            name: .hotkeyDidChange,
            object: nil
        )
    }

    private func setupClipboardMonitor() {
        let monitor = ClipboardMonitorService { [weak self] text, bundleId, appName in
            guard let self else { return }
            await MainActor.run {
                self.viewModel.addClipboardText(text, bundleId: bundleId, appName: appName)
            }
        }
        self.monitorTask = monitor.start()
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
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closeOverlay() {
        overlayPanel?.orderOut(nil)
        AppIconCache.shared.clear()
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let rootView = SettingsView().environmentObject(viewModel)
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: Constants.settingsWidth, height: Constants.settingsHeight))
            window.isReleasedWhenClosed = true
            window.delegate = self
            settingsWindow = window
        }

        closeOverlay()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        settingsWindow?.center()
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func handleSelection(item: ClipboardItem) {
        viewModel.copyItemToPasteboard(item)
        closeOverlay()
        
        let target = pasteTargetApp
        let directPasteEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.autoPaste)
        
        if directPasteEnabled {
            if PasteService.shared.isTrusted() {
                Task {
                    await PasteService.shared.paste(item: item, targetApp: target)
                }
            } else {
                let hasDismissed = UserDefaults.standard.bool(forKey: SettingsKeys.hasDismissedAccessibilityNotice)
                if !hasDismissed {
                    showAccessibilityAlert()
                } else {
                    target?.activate(options: [.activateIgnoringOtherApps])
                }
            }
        } else {
            // Just activate the target application and copy the text
            target?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func positionOverlay(_ panel: NSPanel) {
        let panelSize = panel.frame.size
        let anchor = OverlayPositioningHelper.anchorPoint()
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(anchor) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let rawX = anchor.x - Constants.overlayAnchorOffset
        let rawY = anchor.y - panelSize.height - Constants.overlayBottomOffset

        let x = min(max(rawX, visibleFrame.minX + Constants.overlayPadding), visibleFrame.maxX - panelSize.width - Constants.overlayPadding)
        let y = max(min(rawY, visibleFrame.maxY - panelSize.height - Constants.overlayPadding), visibleFrame.minY + Constants.overlayPadding)

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
                self.viewModel.trimMemory(aggressive: true)
                AppIconCache.shared.clear()
            } else if events.contains(.warning) {
                self.viewModel.trimMemory(aggressive: false)
                AppIconCache.shared.clear()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "Direct paste requires Accessibility access. Please enable it in System Preferences."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        alert.window.center()
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            PasteService.shared.openAccessibilitySettings()
        } else {
            UserDefaults.standard.set(true, forKey: SettingsKeys.hasDismissedAccessibilityNotice)
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        monitorTask?.cancel()
        memoryPressureSource?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let recentItems = viewModel.recentItems.prefix(15)
        for item in recentItems {
            let truncatedText = item.text.replacingOccurrences(of: "\n", with: " ")
            let title = truncatedText.count > 40 ? String(truncatedText.prefix(40)) + "..." : truncatedText
            let menuItem = NSMenuItem(title: title, action: #selector(handleMenuSelection(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item
            if let bundleId = item.sourceAppBundleId, let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                menuItem.image = NSWorkspace.shared.icon(forFile: appUrl.path)
                menuItem.image?.size = NSSize(width: 16, height: 16)
            }
            menu.addItem(menuItem)
        }
        
        if recentItems.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Items", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsWindowFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func handleMenuSelection(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? ClipboardItem {
            handleSelection(item: item)
        }
    }
    
    @objc private func showSettingsWindowFromMenu() {
        showSettingsWindow()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class EventMonitor {
    nonisolated(unsafe) private var monitor: Any?
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
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

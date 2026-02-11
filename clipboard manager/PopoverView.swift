import AppKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var store: ClipboardStore
    @AppStorage(SettingsKeys.autoPaste) private var autoPaste = true
    @AppStorage(SettingsKeys.glassIntensity) private var glassIntensity = 0.65
    @AppStorage(SettingsKeys.appTheme) private var appTheme = AppTheme.system.rawValue

    let onSelectItem: (ClipboardItem) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var showPermissionNotice = false
    @State private var selectedItemID: UUID?
    @State private var pendingScrollID: UUID?
    @State private var showClearConfirmation = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            GlassBackground(intensity: glassIntensity)
            RoundedRectangle(cornerRadius: 22)
                .fill(.white.opacity(0.08 + (glassIntensity * 0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .top) {
            if showPermissionNotice {
                PermissionBanner(onDismiss: { showPermissionNotice = false })
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            }
        }
        .onAppear {
            showPermissionNotice = autoPaste && !AccessibilityHelper.isTrusted()
            if showPermissionNotice {
                AccessibilityHelper.requestIfNeeded()
            }
            selectFirstIfNeeded()
            isSearchFocused = true
        }
        .onChange(of: store.searchQuery) { _, _ in
            selectFirstIfNeeded()
        }
        .sheet(isPresented: $store.showOnboarding) {
            OnboardingView { persist, login in
                store.completeOnboarding(persistHistory: persist, launchAtLogin: login)
            }
        }
        .onExitCommand {
            onClose()
        }
        .onMoveCommand(perform: handleMoveCommand)
        .onSubmit {
            pasteSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlaySelectNext)) { _ in
            handleMoveCommand(.down)
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlaySelectPrevious)) { _ in
            handleMoveCommand(.up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayConfirmSelection)) { _ in
            pasteSelected()
        }
        .preferredColorScheme(AppTheme.fromStored(appTheme).colorScheme)
        .padding(6)
        .alert("Clear non-pinned items?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                store.clearNonPinned()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all non-pinned items.")
        }
    }

    
    
    private var content: some View {
        VStack(spacing: 8) {
            SearchBar(text: $store.searchQuery, isFocused: $isSearchFocused)
            headerActions

            if store.pinnedItems.isEmpty && store.recentItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if !store.pinnedItems.isEmpty {
                                SectionHeader(title: "Pinned")
                                ForEach(store.pinnedItems) { item in
                                    ClipboardRow(
                                        item: item,
                                        isSelected: selectedItemID == item.id,
                                        onSelectItem: handleSelect
                                    )
                                    .id(item.id)
                                }
                            }
                            if !store.recentItems.isEmpty {
                                SectionHeader(title: "Recent")
                                ForEach(store.recentItems) { item in
                                    ClipboardRow(
                                        item: item,
                                        isSelected: selectedItemID == item.id,
                                        onSelectItem: handleSelect
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: pendingScrollID) { _, newValue in
                        guard let id = newValue else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                            proxy.scrollTo(id, anchor: .center)
                            pendingScrollID = nil
                        }
                    }
                }
            }
        }
        .padding(10)
        .environmentObject(store)
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button("Clear Non-Pinned") {
                showClearConfirmation = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Menu("More") {
                Button("Exclude Frontmost App") {
                    excludeFrontmostApp()
                }
                Button("Open Settings") {
                    onOpenSettings()
                }
                Divider()
                Button("Quit Clipboard Manager") {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
            Text("No clipboard items yet")
                .font(.headline)
            Text("Copy text to see it appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private func excludeFrontmostApp() {
        SettingsHelper.excludeFrontmostApp()
    }

    private var displayItems: [ClipboardItem] {
        store.pinnedItems + store.recentItems
    }

    private func selectFirstIfNeeded() {
        if displayItems.isEmpty {
            selectedItemID = nil
            return
        }
        if let selectedItemID,
           displayItems.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = displayItems.first?.id
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard !displayItems.isEmpty else { return }
        guard let current = selectedItemID,
              let index = displayItems.firstIndex(where: { $0.id == current }) else {
            selectedItemID = displayItems.first?.id
            return
        }

        switch direction {
        case .down:
            selectedItemID = displayItems[min(index + 1, displayItems.count - 1)].id
        case .up:
            selectedItemID = displayItems[max(index - 1, 0)].id
        default:
            break
        }

        pendingScrollID = selectedItemID
    }

    private func pasteSelected() {
        guard let selectedID = selectedItemID,
              let selected = displayItems.first(where: { $0.id == selectedID }) else { return }
        onSelectItem(selected)
    }

    private func handleSelect(_ item: ClipboardItem) {
        selectedItemID = item.id
        onSelectItem(item)
    }
}

struct ClipboardRow: View {
    @EnvironmentObject private var store: ClipboardStore

    let item: ClipboardItem
    let isSelected: Bool
    let onSelectItem: (ClipboardItem) -> Void

    var body: some View {
        Button(action: handlePaste) {
            HStack(alignment: .top, spacing: 8) {
                AppIcon(bundleId: item.sourceAppBundleId)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text)
                        .lineLimit(2)
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 8) {
                        Text(item.sourceAppName ?? "Unknown")
                        Text(".")
                        Text(item.createdAt, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? .blue.opacity(0.75) : .white.opacity(0.18), lineWidth: isSelected ? 1.6 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") {
                store.togglePin(item)
            }
            Button("Delete") {
                store.delete(item)
            }
        }
    }

    private func handlePaste() {
        onSelectItem(item)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search clipboard", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
        }
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 2 * 1024 * 1024
    }

    func image(for bundleId: String) -> NSImage? {
        cache.object(forKey: bundleId as NSString)
    }

    func set(_ image: NSImage, for bundleId: String) {
        let thumbnail = thumbnailImage(from: image)
        cache.setObject(thumbnail, forKey: bundleId as NSString, cost: imageCost(thumbnail))
    }

    func clear() {
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

struct AppIcon: View {
    var bundleId: String?
    @State private var image: NSImage?

    var body: some View {
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

struct PermissionBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Enable Accessibility for direct paste into active app.")
                .font(.caption)
            Spacer()
            Button("Open Settings") {
                AccessibilityHelper.requestIfNeeded()
                AccessibilityHelper.openAccessibilitySettings()
            }
            Button("Dismiss", action: onDismiss)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct OnboardingView: View {
    @State private var persistHistory = true
    @State private var launchAtLogin = true

    let onComplete: (Bool, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Clipboard Manager")
                .font(.title2.bold())
            Text("Choose how you want the app to behave. You can change these later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Persist clipboard history across restarts", isOn: $persistHistory)
            Toggle("Launch at login", isOn: $launchAtLogin)

            HStack {
                Spacer()
                Button("Continue") {
                    onComplete(persistHistory, launchAtLogin)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

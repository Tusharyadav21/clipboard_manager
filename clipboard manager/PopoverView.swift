import AppKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var viewModel: ClipboardViewModel
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
            showPermissionNotice = autoPaste && !PasteService.shared.isTrusted()
            selectFirstIfNeeded()
            isSearchFocused = true
        }
        .onChange(of: viewModel.searchQuery) { _, _ in
            selectFirstIfNeeded()
        }
        .sheet(isPresented: $viewModel.showOnboarding) {
            OnboardingView { persist, login in
                viewModel.completeOnboarding(persistHistory: persist, launchAtLogin: login)
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
                viewModel.clearNonPinned()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all non-pinned items.")
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            SearchBar(text: $viewModel.searchQuery, isFocused: $isSearchFocused)
            headerActions

            if viewModel.pinnedItems.isEmpty && viewModel.recentItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if !viewModel.pinnedItems.isEmpty {
                                SectionHeader(title: "Pinned")
                                ForEach(viewModel.pinnedItems) { item in
                                    ClipboardRow(
                                        item: item,
                                        isSelected: selectedItemID == item.id,
                                        onSelectItem: handleSelect
                                    )
                                    .id(item.id)
                                }
                            }
                            if !viewModel.recentItems.isEmpty {
                                SectionHeader(title: "Recent")
                                ForEach(viewModel.recentItems) { item in
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
        .environmentObject(viewModel)
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
        viewModel.pinnedItems + viewModel.recentItems
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

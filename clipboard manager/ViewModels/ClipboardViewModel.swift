import Combine
import Foundation
import SwiftUI

@MainActor
public final class ClipboardViewModel: ObservableObject {
    @Published public private(set) var items: [ClipboardItem] = []
    @Published public var searchQuery: String = ""
    @Published public var showOnboarding: Bool = false
    
    private let clipboardService: ClipboardService
    
    public init(clipboardService: ClipboardService) {
        self.clipboardService = clipboardService
    }
    
    public var filteredItems: [ClipboardItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return items }
        return items.filter { $0.text.localizedStandardContains(query) }
    }
    
    public var pinnedItems: [ClipboardItem] {
        filteredItems.filter { $0.isPinned }
    }
    
    public var recentItems: [ClipboardItem] {
        filteredItems.filter { !$0.isPinned }
    }
    
    public func loadOnLaunch() {
        Task {
            do {
                self.items = try await clipboardService.loadItems()
            } catch {
                NSLog("Error loading clipboard items: \(error)")
            }
        }
    }
    
    public func addClipboardText(_ text: String, bundleId: String?, appName: String?) {
        Task {
            do {
                self.items = try await clipboardService.addClipboardText(text, sourceAppBundleId: bundleId, sourceAppName: appName)
            } catch {
                NSLog("Error adding clipboard text: \(error)")
            }
        }
    }
    
    public func togglePin(_ item: ClipboardItem) {
        Task {
            do {
                self.items = try await clipboardService.togglePin(item)
            } catch {
                NSLog("Error toggling pin: \(error)")
            }
        }
    }
    
    public func delete(_ item: ClipboardItem) {
        Task {
            do {
                self.items = try await clipboardService.delete(item)
            } catch {
                NSLog("Error deleting item: \(error)")
            }
        }
    }
    
    public func clearNonPinned() {
        Task {
            do {
                self.items = try await clipboardService.clearNonPinned()
            } catch {
                NSLog("Error clearing items: \(error)")
            }
        }
    }
    
    public func copyItemToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        
        Task {
            do {
                self.items = try await clipboardService.touchItem(item)
            } catch {
                NSLog("Error touching item after copy: \(error)")
            }
        }
    }
    
    public func presentOnboardingIfNeeded() {
        if UserDefaults.standard.object(forKey: SettingsKeys.hasCompletedOnboarding) == nil {
            showOnboarding = true
        }
    }
    
    public func completeOnboarding(persistHistory: Bool, launchAtLogin: Bool) {
        UserDefaults.standard.set(true, forKey: SettingsKeys.hasCompletedOnboarding)
        UserDefaults.standard.set(persistHistory, forKey: SettingsKeys.persistHistory)
        UserDefaults.standard.set(launchAtLogin, forKey: SettingsKeys.launchAtLogin)
        SettingsHelper.setLaunchAtLogin(launchAtLogin)
        showOnboarding = false
        
        Task {
            do {
                self.items = try await clipboardService.setPersistHistoryEnabled(persistHistory)
            } catch {
                NSLog("Error setting persistence in onboarding: \(error)")
            }
        }
    }
    
    public func setPersistHistoryEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.persistHistory)
        Task {
            do {
                self.items = try await clipboardService.setPersistHistoryEnabled(enabled)
            } catch {
                NSLog("Error setting persistence enabled: \(error)")
            }
        }
    }
    
    public func setEncryptHistoryAtRestEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.encryptHistoryAtRest)
        if enabled {
            SecurityService.prewarmKey()
        }
        guard UserDefaults.standard.bool(forKey: SettingsKeys.persistHistory) else { return }
        Task {
            do {
                self.items = try await clipboardService.setPersistHistoryEnabled(true)
            } catch {
                NSLog("Error re-persisting history for encryption update: \(error)")
            }
        }
    }
    
    public func trimMemory(aggressive: Bool) {
        Task {
            self.items = await clipboardService.trimMemory(aggressive: aggressive)
        }
    }
}

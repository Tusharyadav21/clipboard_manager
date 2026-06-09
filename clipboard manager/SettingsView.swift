import AppKit
import Carbon
import SwiftUI

private enum ShortcutKeyOption: String, CaseIterable, Identifiable {
    case v = "V"
    case c = "C"
    case x = "X"
    case space = "Space"

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .v: return UInt32(kVK_ANSI_V)
        case .c: return UInt32(kVK_ANSI_C)
        case .x: return UInt32(kVK_ANSI_X)
        case .space: return UInt32(kVK_Space)
        }
    }

    static func from(_ keyCode: UInt32) -> ShortcutKeyOption {
        Self.allCases.first { $0.keyCode == keyCode } ?? .v
    }
}

private enum ShortcutModifierOption: String, CaseIterable, Identifiable {
    case commandShift = "Cmd+Shift"
    case commandOption = "Cmd+Option"
    case controlOption = "Ctrl+Option"
    case controlShift = "Ctrl+Shift"
    case commandControl = "Cmd+Ctrl"

    var id: String { rawValue }

    var carbonFlags: UInt32 {
        switch self {
        case .commandShift: return UInt32(cmdKey) | UInt32(shiftKey)
        case .commandOption: return UInt32(cmdKey) | UInt32(optionKey)
        case .controlOption: return UInt32(controlKey) | UInt32(optionKey)
        case .controlShift: return UInt32(controlKey) | UInt32(shiftKey)
        case .commandControl: return UInt32(cmdKey) | UInt32(controlKey)
        }
    }

    static func from(_ flags: UInt32) -> ShortcutModifierOption {
        Self.allCases.first { $0.carbonFlags == flags } ?? .commandShift
    }
}

struct SettingsView: View {
    @EnvironmentObject private var viewModel: ClipboardViewModel
    @AppStorage(SettingsKeys.persistHistory) private var persistHistory = true
    @AppStorage(SettingsKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(SettingsKeys.autoPaste) private var autoPaste = true
    @AppStorage(SettingsKeys.encryptHistoryAtRest) private var encryptHistoryAtRest = false
    @AppStorage(SettingsKeys.glassIntensity) private var glassIntensity = 0.65
    @AppStorage(SettingsKeys.appTheme) private var appTheme = AppTheme.system.rawValue
    @AppStorage(SettingsKeys.hotkeyKeyCode) private var hotkeyKeyCode = Int(UInt32(kVK_ANSI_V))
    @AppStorage(SettingsKeys.hotkeyModifiers) private var hotkeyModifiers = Int(UInt32(cmdKey) | UInt32(shiftKey))

    @State private var exclusions: [String] = UserDefaults.standard.stringArray(forKey: SettingsKeys.exclusions) ?? []
    @State private var newExclusion = ""
    @State private var isAccessibilityTrusted = PasteService.shared.isTrusted()

    private var selectedTheme: AppTheme {
        AppTheme.fromStored(appTheme)
    }

    private var normalizedGlass: Double {
        min(max(glassIntensity, 0), 1)
    }

    private var selectedKey: ShortcutKeyOption {
        ShortcutKeyOption.from(UInt32(hotkeyKeyCode))
    }

    private var selectedModifier: ShortcutModifierOption {
        ShortcutModifierOption.from(UInt32(hotkeyModifiers))
    }

    private var keyBinding: Binding<ShortcutKeyOption> {
        Binding(
            get: { selectedKey },
            set: { option in
                hotkeyKeyCode = Int(option.keyCode)
                NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            }
        )
    }

    private var modifierBinding: Binding<ShortcutModifierOption> {
        Binding(
            get: { selectedModifier },
            set: { option in
                hotkeyModifiers = Int(option.carbonFlags)
                NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            }
        )
    }

    var body: some View {
        ZStack {
            GlassBackground(intensity: glassIntensity)
            LinearGradient(
                colors: [
                    .white.opacity(0.06 + (normalizedGlass * 0.12)),
                    .white.opacity(0.03 + (normalizedGlass * 0.06))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    settingsHeader
                    appearanceSection
                    behaviorSection
                    shortcutSection
                    privacySection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
        .frame(width: 520, height: 560)
        .onAppear {
            isAccessibilityTrusted = PasteService.shared.isTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = PasteService.shared.isTrusted()
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
            Text("Configure behavior, appearance, and privacy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBackground)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.headline)

            Picker("Theme", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Glass intensity")
                    .font(.subheadline)
                Slider(value: $glassIntensity, in: 0...1)
                    .tint(.white.opacity(0.35 + (normalizedGlass * 0.5)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBackground)
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Behavior")
                .font(.headline)

            Toggle("Persist history", isOn: Binding(
                get: { persistHistory },
                set: { value in
                    persistHistory = value
                    viewModel.setPersistHistoryEnabled(value)
                }
            ))

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { value in
                    launchAtLogin = value
                    SettingsHelper.setLaunchAtLogin(value)
                }
            ))

            Toggle("Direct paste on selection", isOn: Binding(
                get: { autoPaste },
                set: { value in
                    autoPaste = value
                    if value { PasteService.shared.requestIfNeeded() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isAccessibilityTrusted = PasteService.shared.isTrusted()
                    }
                }
            ))

            HStack(spacing: 6) {
                Circle()
                    .fill(isAccessibilityTrusted ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isAccessibilityTrusted ? "Accessibility: Granted" : "Accessibility: Not Granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Request Accessibility Access") {
                PasteService.shared.requestIfNeeded()
                PasteService.shared.openAccessibilitySettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isAccessibilityTrusted = PasteService.shared.isTrusted()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBackground)
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcut")
                .font(.headline)

            HStack(spacing: 10) {
                Picker("Modifiers", selection: modifierBinding) {
                    ForEach(ShortcutModifierOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Key", selection: keyBinding) {
                    ForEach(ShortcutKeyOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Current: \(selectedModifier.rawValue) + \(selectedKey.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBackground)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy")
                .font(.headline)

            Toggle("Encrypt clipboard history at rest", isOn: Binding(
                get: { encryptHistoryAtRest },
                set: { value in
                    encryptHistoryAtRest = value
                    viewModel.setEncryptHistoryAtRestEnabled(value)
                }
            ))

            Text(encryptHistoryAtRest
                 ? "History is encrypted and stored locally on this device."
                 : "History is stored locally without encryption.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .foregroundStyle(.green)
                    Text("Sensitive Content Filtering: Active")
                        .font(.subheadline.weight(.medium))
                }
                Text("Credentials from password managers (like 1Password), SSH keys, private keys, and API tokens are automatically screened and never stored in your history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundStyle(.blue)
                    Text("Automatic Pruning: Active")
                        .font(.subheadline.weight(.medium))
                }
                Text("Clipboard history is limited to 50 items and automatically purged after 7 days to maximize privacy and minimize memory usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Divider()

            HStack(spacing: 8) {
                TextField("Bundle ID to exclude", text: $newExclusion)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addExclusion(newExclusion)
                }
                .buttonStyle(.borderedProminent)
            }

            if exclusions.isEmpty {
                Text("No exclusions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(exclusions, id: \.self) { item in
                    HStack {
                        Text(item)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") {
                            removeExclusion(item)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button("Exclude Frontmost App") {
                excludeFrontmost()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.78 + (normalizedGlass * 0.16)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.14 + (normalizedGlass * 0.18)), lineWidth: 1)
            )
    }

    private func addExclusion(_ bundleId: String) {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !exclusions.contains(trimmed) {
            exclusions.append(trimmed)
            UserDefaults.standard.set(exclusions, forKey: SettingsKeys.exclusions)
            newExclusion = ""
        }
    }

    private func removeExclusion(_ bundleId: String) {
        exclusions.removeAll { $0 == bundleId }
        UserDefaults.standard.set(exclusions, forKey: SettingsKeys.exclusions)
    }

    private func excludeFrontmost() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmost.bundleIdentifier else { return }
        addExclusion(bundleId)
    }
}

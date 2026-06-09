import SwiftUI

public struct PermissionBanner: View {
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text("Enable Accessibility for direct paste into active app.")
                .font(.caption)
            Spacer()
            Button("Open Settings") {
                PasteService.shared.requestIfNeeded()
                PasteService.shared.openAccessibilitySettings()
            }
            Button("Dismiss", action: onDismiss)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

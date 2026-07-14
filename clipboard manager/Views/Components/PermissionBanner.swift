import SwiftUI

public struct PermissionBanner: View {
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.raised")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Accessibility access needed for direct paste")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Open Settings") {
                PasteService.shared.requestIfNeeded()
                PasteService.shared.openAccessibilitySettings()
            }
            .buttonStyle(.plain)
            .font(.caption2.weight(.medium))
            .foregroundColor(.accentColor)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

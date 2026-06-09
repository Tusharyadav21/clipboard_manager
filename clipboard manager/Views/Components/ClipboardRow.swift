import SwiftUI

public struct ClipboardRow: View {
    @EnvironmentObject private var viewModel: ClipboardViewModel

    public let item: ClipboardItem
    public let isSelected: Bool
    public let onSelectItem: (ClipboardItem) -> Void

    public init(item: ClipboardItem, isSelected: Bool, onSelectItem: @escaping (ClipboardItem) -> Void) {
        self.item = item
        self.isSelected = isSelected
        self.onSelectItem = onSelectItem
    }

    public var body: some View {
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
                viewModel.togglePin(item)
            }
            Button("Delete") {
                viewModel.delete(item)
            }
        }
    }

    private func handlePaste() {
        onSelectItem(item)
    }
}

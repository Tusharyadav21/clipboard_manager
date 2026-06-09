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
            HStack(alignment: .top, spacing: 6) {
                AppIcon(bundleId: item.sourceAppBundleId)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .lineLimit(2)
                        .font(.system(size: 12, weight: .regular))
                    HStack(spacing: 6) {
                        Text(item.sourceAppName ?? "Unknown")
                        Text("•")
                        Text(item.createdAt, style: .time)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

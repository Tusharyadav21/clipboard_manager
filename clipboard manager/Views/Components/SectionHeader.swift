import SwiftUI

public struct SectionHeader: View {
    public let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.secondary.opacity(0.5))
                .frame(width: 4, height: 4)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .padding(.vertical, 2)
    }
}

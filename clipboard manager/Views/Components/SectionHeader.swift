import SwiftUI

public struct SectionHeader: View {
    public let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

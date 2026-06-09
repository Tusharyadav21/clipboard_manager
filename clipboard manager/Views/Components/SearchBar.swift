import SwiftUI

public struct SearchBar: View {
    @Binding public var text: String
    public var isFocused: FocusState<Bool>.Binding

    public init(text: Binding<String>, isFocused: FocusState<Bool>.Binding) {
        self._text = text
        self.isFocused = isFocused
    }

    public var body: some View {
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

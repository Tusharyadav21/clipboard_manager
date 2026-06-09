import SwiftUI

public struct OnboardingView: View {
    @State private var persistHistory = true
    @State private var launchAtLogin = true

    public let onComplete: (Bool, Bool) -> Void

    public init(onComplete: @escaping (Bool, Bool) -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Clipboard Manager")
                .font(.title2.bold())
            Text("Choose how you want the app to behave. You can change these later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Persist clipboard history across restarts", isOn: $persistHistory)
            Toggle("Launch at login", isOn: $launchAtLogin)

            HStack {
                Spacer()
                Button("Continue") {
                    onComplete(persistHistory, launchAtLogin)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

import AppKit
import SwiftUI

struct GlassBackground: NSViewRepresentable {
    var intensity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.isEmphasized = intensity >= 0.6
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.isEmphasized = intensity >= 0.6
    }
}

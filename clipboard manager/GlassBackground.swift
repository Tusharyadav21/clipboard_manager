import AppKit
import SwiftUI

struct GlassBackground: NSViewRepresentable {
    var intensity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .behindWindow
        view.material = .popover
        view.isEmphasized = intensity >= 0.6
        view.wantsLayer = true
        view.layer?.cornerRadius = 22
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.isEmphasized = intensity >= 0.6
    }
}

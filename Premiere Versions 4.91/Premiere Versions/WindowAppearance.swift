import AppKit
import SwiftUI

nonisolated enum PVWindowAppearance {
    static func opacity(_ value: Double, reduceTransparency: Bool = false) -> Double {
        guard !reduceTransparency, value.isFinite else { return 1 }
        return min(1, max(0.15, value))
    }
}

/// Native behind-window material blurs other windows without capturing the screen.
struct PVFrostedBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

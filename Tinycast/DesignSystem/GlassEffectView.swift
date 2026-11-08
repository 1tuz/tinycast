import SwiftUI

struct GlassEffectView: NSViewRepresentable {
    var style: NSGlassEffectView.Style = .regular
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = style
        view.cornerRadius = cornerRadius
        // Keep the material untinted: dark tints can become opaque on newer macOS.
        view.tintColor = nil
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.style = style
        nsView.cornerRadius = cornerRadius
        nsView.tintColor = nil
    }
}

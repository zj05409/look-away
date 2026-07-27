import AppKit
import SwiftUI

/// Clears the MenuBarExtra window chrome so only the app’s glass panel is visible.
/// Without this, the system window corner peeks out behind the panel (double border).
struct MenuBarWindowBackgroundClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        DispatchQueue.main.async {
            Self.clearWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.clearWindow(for: nsView)
        }
    }

    private static func clearWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
            contentView.layer?.cornerRadius = 0
            contentView.layer?.masksToBounds = false
        }
    }
}

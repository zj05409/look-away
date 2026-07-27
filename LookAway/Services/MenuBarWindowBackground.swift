import AppKit
import SwiftUI

/// Clears the MenuBarExtra window chrome so only the app’s glass panel is visible.
/// Without this, the system window corner peeks out behind the panel (double border).
struct MenuBarWindowBackgroundClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ClearerView()
        DispatchQueue.main.async {
            view.clearHostingWindow()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClearerView)?.clearHostingWindow()
    }

    private final class ClearerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearHostingWindow()
        }

        func clearHostingWindow() {
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.clear.cgColor
                contentView.layer?.cornerRadius = 0
                contentView.layer?.masksToBounds = false
            }
            // Neutralize visual-effect / material chrome some MenuBarExtra hosts inject.
            for subview in window.contentView?.subviews ?? [] {
                if let visualEffect = subview as? NSVisualEffectView {
                    visualEffect.isHidden = true
                    visualEffect.material = .hudWindow
                    visualEffect.state = .followsWindowActiveState
                    visualEffect.blendingMode = .behindWindow
                }
            }
        }
    }
}

import AppKit
import CoreGraphics

@MainActor
final class BreakInputShield {
    var onBlockedShortcut: ((String) -> Void)?
    var onStartWorking: (() -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?

    func activate() {
        deactivate()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            if event.type == .keyDown, (event.keyCode == 36 || event.keyCode == 49) {
                self?.onStartWorking?()
                return nil
            }
            guard let self, self.shouldBlock(event) else { return event }
            self.onBlockedShortcut?("Break in progress")
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.shouldBlock(event) else { return }
            Task { @MainActor in
                self.onBlockedShortcut?("Break in progress")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func deactivate() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func shouldBlock(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control) else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "q", "w":
            return true
        case "\t":
            return true
        default:
            break
        }

        return false
    }
}

enum BreakOverlayWindowLevel {
    static let shield = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    static let warning = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
}

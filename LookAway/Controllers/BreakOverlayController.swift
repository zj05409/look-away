import AppKit
import SwiftUI

@MainActor
final class BreakOverlayController: ObservableObject {
    private var panels: [NSPanel] = []
    private var warningPanel: NSPanel?
    private var warningDismissTimer: Timer?
    private weak var timerEngine: TimerEngine?
    private let inputShield = BreakInputShield()
    private var keepFrontTimer: Timer?

    func bind(to engine: TimerEngine) {
        timerEngine = engine
    }

    func installObservers() {
        NotificationCenter.default.addObserver(
            forName: .lookAwayPreBreakWarning,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.showPreBreakWarning() }
        }

        NotificationCenter.default.addObserver(
            forName: .lookAwayBreakStarted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showOverlay()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .lookAwayBreakEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideOverlay()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.panels.isEmpty else { return }
                self.hideOverlay()
                self.showOverlay()
            }
        }
    }

    func showOverlay() {
        hidePreBreakWarning()
        hideOverlay()
        MenuBarWindowDismisser.closeIfOpen()
        guard timerEngine != nil else { return }

        inputShield.activate()
        inputShield.onStartWorking = { [weak self] in
            guard let engine = self?.timerEngine else { return }
            engine.startWorkingAfterBreak()
        }
        mountOverlayPanels()
        startKeepFrontTimer()

        NSApp.activate(ignoringOtherApps: true)
    }

    func hideOverlay() {
        stopKeepFrontTimer()
        inputShield.deactivate()
        inputShield.onStartWorking = nil

        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
    }

    private func showPreBreakWarning() {
        guard let engine = timerEngine, panels.isEmpty else { return }
        hidePreBreakWarning()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = BreakOverlayWindowLevel.warning
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let hosting = NSHostingController(rootView: PreBreakWarningView(engine: engine))
        if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: 560, height: 300))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 280, y: screen.frame.midY - 150))
        }
        panel.orderFrontRegardless()
        warningPanel = panel
        warningDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hidePreBreakWarning() }
        }
    }

    private func hidePreBreakWarning() {
        warningDismissTimer?.invalidate()
        warningDismissTimer = nil
        warningPanel?.orderOut(nil)
        warningPanel?.close()
        warningPanel = nil
    }

    private func mountOverlayPanels() {
        guard let engine = timerEngine else { return }

        for (index, screen) in NSScreen.screens.enumerated() {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = BreakOverlayWindowLevel.shield
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = false

            let hosting = NSHostingController(
                rootView: BreakOverlayView(
                    engine: engine,
                    onSkipBreak: { [weak engine] in
                        engine?.abortBreakEarly()
                    },
                    onStartWorking: { [weak engine] in
                        engine?.startWorkingAfterBreak()
                    }
                )
            )
            if #available(macOS 13.0, *) {
                hosting.sizingOptions = []
            }
            panel.contentViewController = hosting
            pinHostingViewToPanel(hosting, panel: panel)
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()

            panels.append(panel)

            if index == 0 {
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func startKeepFrontTimer() {
        stopKeepFrontTimer()
        keepFrontTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.panels.isEmpty else { return }
                for panel in self.panels {
                    panel.orderFrontRegardless()
                }
            }
        }
        if let keepFrontTimer {
            RunLoop.main.add(keepFrontTimer, forMode: .common)
        }
    }

    private func stopKeepFrontTimer() {
        keepFrontTimer?.invalidate()
        keepFrontTimer = nil
    }

    private func pinHostingViewToPanel(_ hosting: NSHostingController<BreakOverlayView>, panel: NSPanel) {
        guard let contentView = panel.contentView else { return }
        let hostView = hosting.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}

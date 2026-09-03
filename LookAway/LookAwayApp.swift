import AppKit
import SwiftUI

@main
struct LookAwayApp: App {
    @StateObject private var viewModel = AppViewModel()

    private var isBreakLocked: Bool {
        viewModel.timerEngine.isBreakOverlayActive
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel, timerEngine: viewModel.timerEngine)
        } label: {
            MenuBarLabelView(engine: viewModel.timerEngine)
                .disabled(isBreakLocked)
                .opacity(isBreakLocked ? 0.35 : 1)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Isolated, lightweight menu-bar label — avoids re-rendering glass/heavy SwiftUI on every tick.
private struct MenuBarLabelView: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: engine.menuBarSymbol)
                .symbolRenderingMode(.hierarchical)
            Text(engine.menuBarCompactText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityLabel(engine.menuBarLabel)
    }
}

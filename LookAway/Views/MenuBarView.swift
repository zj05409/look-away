import AppKit
import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let configManager: ConfigManager
    let timerEngine: TimerEngine
    let microphoneMonitor: MicrophoneMonitor
    let sleepWakeMonitor: SleepWakeMonitor
    let breakOverlayController: BreakOverlayController
    private let notificationHandler = NotificationHandler()

    private var cancellables = Set<AnyCancellable>()

    init() {
        configManager = ConfigManager()
        timerEngine = TimerEngine(config: configManager.config)
        microphoneMonitor = MicrophoneMonitor()
        sleepWakeMonitor = SleepWakeMonitor()
        breakOverlayController = BreakOverlayController()
        breakOverlayController.bind(to: timerEngine)
        breakOverlayController.installObservers()

        notificationHandler.timerEngine = timerEngine
        notificationHandler.install()

        bind()

        configManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Defer until the app/run loop is ready so the first-launch alert can present.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            LaunchAtLoginManager.promptOnFirstLaunchIfNeeded(configManager: self.configManager)
        }
    }

    private func bind() {
        configManager.$config
            .sink { [weak self] config in
                self?.timerEngine.applyConfig(config)
            }
            .store(in: &cancellables)

        // Skip the initial value — first-launch prompt (or subsequent sync) owns login registration.
        configManager.$config
            .dropFirst()
            .sink { config in
                guard LaunchAtLoginManager.hasPrompted else { return }
                LaunchAtLoginManager.syncWithConfig(config.launchAtLogin)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            microphoneMonitor.$isMicActive,
            sleepWakeMonitor.$isSystemPaused,
            sleepWakeMonitor.$pauseDetail
        )
        .sink { [weak self] micActive, systemPaused, systemPauseDetail in
            self?.timerEngine.handleExternalPause(
                micActive: micActive,
                systemPaused: systemPaused,
                systemPauseDetail: systemPauseDetail
            )
        }
        .store(in: &cancellables)
    }

    func togglePause() {
        timerEngine.setManualPause(!timerEngine.isManuallyPaused)
        timerEngine.handleExternalPause(
            micActive: microphoneMonitor.isMicActive,
            systemPaused: sleepWakeMonitor.isSystemPaused,
            systemPauseDetail: sleepWakeMonitor.pauseDetail
        )
    }

    func restartTimer() {
        timerEngine.restartTimer()
        timerEngine.handleExternalPause(
            micActive: microphoneMonitor.isMicActive,
            systemPaused: sleepWakeMonitor.isSystemPaused,
            systemPauseDetail: sleepWakeMonitor.pauseDetail
        )
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var timerEngine: TimerEngine

    init(viewModel: AppViewModel, timerEngine: TimerEngine) {
        self.viewModel = viewModel
        self.timerEngine = timerEngine
    }

    var body: some View {
        LookAwayGlassPanel {
            VStack(alignment: .leading, spacing: MenuPanelMetrics.spacing) {
                compactHeader

                quickActions

                footer
            }
            .padding(MenuPanelMetrics.padding)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(MenuBarWindowBackgroundClearer())
        .onReceive(NotificationCenter.default.publisher(for: .lookAwayBreakStarted)) { _ in
            dismiss()
        }
        .disabled(timerEngine.phase == .onBreak)
        .opacity(timerEngine.phase == .onBreak ? 0.6 : 1)
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: MenuPanelMetrics.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timerEngine.displayTime)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                Text(timerEngine.phaseDisplayName)
                    .font(MenuPanelMetrics.controlFont)
                    .foregroundStyle(.secondary)

                if !timerEngine.statusDetail.isEmpty {
                    Text(timerEngine.statusDetail)
                        .font(MenuPanelMetrics.controlFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if timerEngine.phase == .onBreak {
                LookAwayStatusChip(text: "Break")
            } else if timerEngine.phase == .paused {
                LookAwayStatusChip(text: "Paused")
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: MenuPanelMetrics.spacing) {
            HStack(spacing: MenuPanelMetrics.spacing) {
                menuButton(
                    title: timerEngine.isManuallyPaused ? "Resume" : "Pause",
                    symbol: timerEngine.isManuallyPaused ? "play.fill" : "pause.fill",
                    centered: true
                ) {
                    viewModel.togglePause()
                }

                HoldToConfirmButton(
                    title: "Restart",
                    holdingTitle: "Keep holding…",
                    systemImage: "arrow.clockwise",
                    centered: true,
                    onConfirm: { viewModel.restartTimer() }
                )
            }

            if timerEngine.phase == .onBreak {
                HoldToConfirmButton(
                    title: "Skip",
                    holdingTitle: "Keep holding…",
                    systemImage: "forward.end.fill",
                    role: .destructive,
                    centered: true,
                    onConfirm: { viewModel.timerEngine.abortBreakEarly() }
                )
            } else if timerEngine.phase == .preBreakWarning {
                HStack(spacing: MenuPanelMetrics.spacing) {
                    menuButton(title: "Extend 3 min", symbol: "plus.circle", centered: true) {
                        viewModel.timerEngine.extendSession()
                    }

                    menuButton(title: "Break", symbol: "cup.and.saucer.fill", centered: true) {
                        viewModel.timerEngine.startBreakNow()
                    }
                }
            } else {
                menuButton(title: "Break", symbol: "cup.and.saucer.fill", centered: true) {
                    viewModel.timerEngine.startBreakNow()
                }
            }

            if timerEngine.pendingPenaltyMinutes > 0 && timerEngine.phase != .onBreak {
                Text("Next break +\(timerEngine.pendingPenaltyMinutes) min from skip")
                    .font(MenuPanelMetrics.controlFont)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
            }
        }
    }

    private var footer: some View {
        Button {
            viewModel.quit()
        } label: {
            Label("Quit", systemImage: "power")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MenuActionButtonStyle(role: .destructive))
        .disabled(timerEngine.phase == .onBreak)
        .keyboardShortcut("q")
    }

    private func menuButton(title: String, symbol: String, centered: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MenuActionButtonStyle(centered: centered))
    }
}

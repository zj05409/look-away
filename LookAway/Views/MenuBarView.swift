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
        L10n.apply(configManager.config.language)
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

        // Defer until the app/run loop is ready so the overlay and first-launch alert can present.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timerEngine.restoreInterruptedBreak()
            LaunchAtLoginManager.promptOnFirstLaunchIfNeeded(configManager: self.configManager)
        }
    }

    private func bind() {
        configManager.$config
            .sink { [weak self] config in
                L10n.apply(config.language)
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
        .disabled(timerEngine.isBreakOverlayActive)
        .opacity(timerEngine.isBreakOverlayActive ? 0.6 : 1)
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

            if timerEngine.isBreakOverlayActive {
                LookAwayStatusChip(text: L10n.text("Break", "休息"))
            } else if timerEngine.phase == .paused {
                LookAwayStatusChip(text: L10n.text("Paused", "已暂停"))
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: MenuPanelMetrics.spacing) {
            HStack(spacing: MenuPanelMetrics.spacing) {
                menuButton(
                    title: timerEngine.isManuallyPaused ? L10n.text("Resume", "继续") : L10n.text("Pause", "暂停"),
                    symbol: timerEngine.isManuallyPaused ? "play.fill" : "pause.fill",
                    centered: true
                ) {
                    viewModel.togglePause()
                }

                HoldToConfirmButton(
                    title: L10n.text("Restart", "重新计时"),
                    holdingTitle: L10n.text("Keep holding…", "继续按住…"),
                    systemImage: "arrow.clockwise",
                    centered: true,
                    onConfirm: { viewModel.restartTimer() }
                )
            }

            if timerEngine.phase == .onBreak {
                HoldToConfirmButton(
                    title: L10n.text("Skip", "跳过"),
                    holdingTitle: L10n.text("Keep holding…", "继续按住…"),
                    systemImage: "forward.end.fill",
                    role: .destructive,
                    centered: true,
                    onConfirm: { viewModel.timerEngine.abortBreakEarly() }
                )
            } else if timerEngine.phase == .preBreakWarning {
                HStack(spacing: MenuPanelMetrics.spacing) {
                    menuButton(
                        title: L10n.text("Extend \(TimerEngine.sessionExtensionMinutes) min", "延后 \(TimerEngine.sessionExtensionMinutes) 分钟"),
                        symbol: "plus.circle",
                        centered: true
                    ) {
                        viewModel.timerEngine.extendSession()
                    }

                    menuButton(title: L10n.text("Break", "立即休息"), symbol: "cup.and.saucer.fill", centered: true) {
                        viewModel.timerEngine.startBreakNow()
                    }
                }
            } else {
                menuButton(title: L10n.text("Break", "立即休息"), symbol: "cup.and.saucer.fill", centered: true) {
                    viewModel.timerEngine.startBreakNow()
                }
            }

            if timerEngine.pendingPenaltyMinutes > 0 && !timerEngine.isBreakOverlayActive {
                Text(L10n.text(
                    "Next break +\(timerEngine.pendingPenaltyMinutes) min from skip",
                    "因跳过休息，下次休息 +\(timerEngine.pendingPenaltyMinutes) 分钟"
                ))
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
            Label(L10n.text("Quit", "退出"), systemImage: "power")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MenuActionButtonStyle(role: .destructive))
        .disabled(timerEngine.isBreakOverlayActive)
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

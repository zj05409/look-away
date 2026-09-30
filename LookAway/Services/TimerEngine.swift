import AppKit
import Combine
import Foundation
import UserNotifications

enum TimerPhase: Equatable {
    case working
    case preBreakWarning
    case onBreak
    case breakComplete
    case paused
}

@MainActor
final class TimerEngine: ObservableObject {
    static let sessionExtensionMinutes = 3

    @Published private(set) var phase: TimerPhase = .working
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var isManuallyPaused = false
    @Published private(set) var statusDetail: String = ""
    /// Lightweight menu-bar fields — only published when their values change.
    @Published private(set) var menuBarCompactText: String = ""
    @Published private(set) var menuBarSymbol: String = "eyes"
    @Published private(set) var pendingPenaltyMinutes: Int = 0
    @Published private(set) var appliedPenaltyMinutes: Int = 0

    private var config: AppConfig
    private var tickTimer: Timer?
    private var lastTickDate: Date?
    private var preBreakWarningSent = false
    /// High-precision countdown; UI reads `remainingSeconds` at most once per second.
    private var internalRemaining: TimeInterval = 0
    private var lastPublishedDisplaySecond: Int = -1
    /// Tracks why the timer is paused without parsing the (localized) status text.
    private var pausedForCall = false

    var menuBarLabel: String {
        switch phase {
        case .onBreak:
            return L10n.text("Break: \(menuBarDisplayTime)", "休息中：\(menuBarDisplayTime)")
        case .breakComplete:
            return L10n.text("Break complete — waiting to start work", "休息已达标，等待开始工作")
        case .paused:
            if pausedForCall {
                return L10n.text("Call active", "通话中")
            }
            return L10n.text("Paused", "已暂停")
        case .preBreakWarning:
            return L10n.text("Break soon: \(menuBarDisplayTime)", "即将休息：\(menuBarDisplayTime)")
        case .working:
            return L10n.text("\(menuBarDisplayTime) left", "剩余 \(menuBarDisplayTime)")
        }
    }

    var displayTime: String {
        formattedTime(remainingSeconds)
    }

    var menuBarDisplayTime: String {
        formattedMenuBarTime(remainingSeconds)
    }

    var phaseDisplayName: String {
        switch phase {
        case .working:
            return L10n.text("Focus session", "专注中")
        case .preBreakWarning:
            return L10n.text("Break approaching", "即将休息")
        case .onBreak:
            return L10n.text("Rest your eyes", "让眼睛休息一下")
        case .breakComplete:
            return L10n.text("Break complete", "休息已达标")
        case .paused:
            return L10n.text("Paused", "已暂停")
        }
    }

    var phaseSymbol: String {
        switch phase {
        case .working:
            return "laptopcomputer"
        case .preBreakWarning:
            return "bell.badge"
        case .onBreak:
            return "eye.fill"
        case .breakComplete:
            return "checkmark.circle.fill"
        case .paused:
            return "pause.circle"
        }
    }

    var activePhaseDuration: TimeInterval {
        switch phase {
        case .working:
            return config.workDurationSeconds
        case .preBreakWarning:
            return config.preBreakWarningSeconds
        case .onBreak:
            return currentBreakTotalSeconds
        case .breakComplete:
            return 0
        case .paused:
            return config.workDurationSeconds
        }
    }

    var progressFraction: Double {
        let total = activePhaseDuration
        guard total > 0 else { return 0 }
        return max(0, min(1, 1 - (remainingSeconds / total)))
    }

    var isBreakOverlayActive: Bool {
        phase == .onBreak || phase == .breakComplete
    }

    var reminderMessage: String {
        config.reminderMessage
    }

    /// Configured break plus any skip penalty applied to the current break.
    private var currentBreakTotalSeconds: TimeInterval {
        config.breakDurationSeconds + TimeInterval(appliedPenaltyMinutes * 60)
    }

    init(config: AppConfig) {
        self.config = config
        internalRemaining = config.workDurationSeconds
        remainingSeconds = config.workDurationSeconds
        loadBreakStats()
        syncMenuBarPresentation(force: true)
        startTicking()
    }

    func applyConfig(_ config: AppConfig) {
        let previous = self.config
        self.config = config
        switch phase {
        case .working:
            if config.workDurationMinutes != previous.workDurationMinutes {
                internalRemaining = config.workDurationSeconds
            } else {
                internalRemaining = min(internalRemaining, config.workDurationSeconds)
            }
        case .onBreak:
            // Include the applied skip penalty: reloading config.json mid-break
            // (for any key) must not silently cut the penalty minutes.
            if config.breakDurationMinutes != previous.breakDurationMinutes {
                internalRemaining = currentBreakTotalSeconds
            } else {
                internalRemaining = min(internalRemaining, currentBreakTotalSeconds)
            }
            persistBreakSession()
        case .breakComplete:
            break
        case .preBreakWarning:
            if config.preBreakWarningMinutes != previous.preBreakWarningMinutes {
                internalRemaining = config.preBreakWarningSeconds
            } else {
                internalRemaining = min(internalRemaining, config.preBreakWarningSeconds)
            }
        case .paused:
            break
        }
        publishRemainingIfDisplayChanged(force: true)
    }

    /// Brings back a break that was still running (or awaiting confirmation) when
    /// the app last quit, crashed, or was killed. Call once observers are installed
    /// so the overlay controller receives the break-started notification.
    func restoreInterruptedBreak() {
        guard let session = BreakSessionStore.load() else { return }

        appliedPenaltyMinutes = max(0, session.appliedPenaltyMinutes)
        isManuallyPaused = false
        pausedForCall = false
        preBreakWarningSent = false
        statusDetail = ""

        let remaining = session.endsAt.timeIntervalSinceNow
        if session.phase == .onBreak, remaining > 0 {
            phase = .onBreak
            internalRemaining = min(remaining, currentBreakTotalSeconds)
            publishRemainingIfDisplayChanged(force: true)
            if tickTimer == nil { startTicking() }
            NotificationCenter.default.post(name: .lookAwayBreakStarted, object: nil)
            return
        }

        if session.phase == .onBreak {
            // The break elapsed while the app was not running: it still needs
            // the explicit "Start Working" confirmation.
            transitionToBreakComplete()
        } else {
            phase = .breakComplete
            internalRemaining = 0
            statusDetail = L10n.text("Break complete", "休息已达标")
            publishRemainingIfDisplayChanged(force: true)
            stopTicking()
        }
        NotificationCenter.default.post(name: .lookAwayBreakStarted, object: nil)
    }

    func setManualPause(_ paused: Bool) {
        isManuallyPaused = paused
        reevaluatePhase()
    }

    func startBreakNow() {
        beginBreak()
    }

    /// Adds time to the current work session and leaves the pre-break warning phase.
    func extendSession() {
        guard phase == .preBreakWarning || phase == .working else { return }

        internalRemaining += TimeInterval(Self.sessionExtensionMinutes * 60)
        phase = .working
        preBreakWarningSent = false
        statusDetail = ""
        publishRemainingIfDisplayChanged(force: true)
        syncMenuBarPresentation(force: true)
        if tickTimer == nil { startTicking() }

        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [LookAwayNotification.preBreakRequestID]
        )
    }

    /// Ends the current break early — adds penalty minutes to the next break.
    func abortBreakEarly() {
        guard phase == .onBreak else { return }
        recordEarlyAbort()
        transitionToWorkingAfterBreak()
    }

    /// Starts a fresh focus cycle only after the minimum break has completed
    /// and the user explicitly confirms that they are back at work.
    func startWorkingAfterBreak() {
        guard phase == .breakComplete else { return }
        transitionToWorkingAfterBreak()
    }

    func skipBreak() {
        abortBreakEarly()
    }

    /// Resets the work interval to the configured duration and resumes if only manually paused.
    func restartTimer() {
        if phase == .onBreak {
            abortBreakEarly()
        }

        phase = .working
        internalRemaining = config.workDurationSeconds
        preBreakWarningSent = false
        isManuallyPaused = false
        statusDetail = ""
        BreakSessionStore.clear()
        publishRemainingIfDisplayChanged(force: true)
        if tickTimer == nil { startTicking() }
    }

    /// Locking the screen, turning off the display, or sleeping the Mac must not
    /// stop the schedule. On wake, the elapsed wall-clock time is deducted by the
    /// regular timer tick. Only a call or an explicit manual pause stops it.
    func handleExternalPause(micActive: Bool, systemPaused _: Bool, systemPauseDetail _: String = "") {
        pausedForCall = micActive
        let newDetail: String
        if micActive {
            newDetail = L10n.text("Paused — call active", "已暂停 — 通话中")
        } else if isManuallyPaused {
            newDetail = L10n.text("Paused manually", "已手动暂停")
        } else {
            newDetail = ""
        }

        if newDetail != statusDetail {
            statusDetail = newDetail
            if phase == .paused {
                syncMenuBarPresentation(force: true)
            }
        }

        reevaluatePhase(micActive: micActive)
    }

    func confirmEndBreakEarly() {
        abortBreakEarly()
    }

    private func startTicking() {
        tickTimer?.invalidate()
        lastTickDate = Date()
        let timer = Timer(fire: Date(), interval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTickDate ?? now)
        lastTickDate = now

        internalRemaining = max(0, internalRemaining - elapsed)
        publishRemainingIfDisplayChanged()

        switch phase {
        case .working:
            handleWorkingTick()
        case .preBreakWarning:
            handlePreBreakWarningTick()
        case .onBreak:
            handleBreakTick()
        case .breakComplete:
            break
        case .paused:
            break
        }
    }

    private func publishRemainingIfDisplayChanged(force: Bool = false) {
        let displaySecond = Int(max(0, internalRemaining).rounded(.up))
        guard force || displaySecond != lastPublishedDisplaySecond else { return }
        lastPublishedDisplaySecond = displaySecond
        remainingSeconds = internalRemaining
        syncMenuBarPresentation(force: force)
    }

    private func syncMenuBarPresentation(force: Bool = false) {
        let newText: String
        switch phase {
        case .onBreak, .working, .preBreakWarning:
            newText = menuBarDisplayTime
        case .breakComplete:
            newText = L10n.text("Ready", "待开始")
        case .paused:
            newText = pausedForCall ? L10n.text("Call active", "通话中") : L10n.text("Paused", "已暂停")
        }
        if force || newText != menuBarCompactText {
            menuBarCompactText = newText
        }

        if force || menuBarSymbol != "eyes" {
            menuBarSymbol = "eyes"
        }
    }

    private func handleWorkingTick() {
        if config.preBreakWarningMinutes > 0,
           internalRemaining <= config.preBreakWarningSeconds,
           internalRemaining > 0 {
            if phase != .preBreakWarning {
                phase = .preBreakWarning
                syncMenuBarPresentation(force: true)
                NotificationCenter.default.post(name: .lookAwayPreBreakWarning, object: nil)
                sendPreBreakNotificationIfNeeded()
            }
        }

        if internalRemaining <= 0 {
            triggerBreakOrPauseForCall()
        }
    }

    private func handlePreBreakWarningTick() {
        if internalRemaining <= 0 {
            triggerBreakOrPauseForCall()
        }
    }

    private func triggerBreakOrPauseForCall() {
        if MicrophoneMonitor.checkMicrophoneInUse() {
            phase = .paused
            pausedForCall = true
            statusDetail = L10n.text("Paused — call active", "已暂停 — 通话中")
            internalRemaining = 0
            publishRemainingIfDisplayChanged(force: true)
            stopTicking()
        } else {
            beginBreak()
        }
    }

    private func handleBreakTick() {
        if internalRemaining <= 0 {
            transitionToBreakComplete()
        }
    }

    private func beginBreak() {
        phase = .onBreak
        appliedPenaltyMinutes = pendingPenaltyMinutes
        if appliedPenaltyMinutes > 0 {
            pendingPenaltyMinutes = 0
            persistBreakStats()
        }
        internalRemaining = currentBreakTotalSeconds
        preBreakWarningSent = false
        statusDetail = ""
        publishRemainingIfDisplayChanged(force: true)
        persistBreakSession()
        if tickTimer == nil { startTicking() }
        NotificationCenter.default.post(name: .lookAwayBreakStarted, object: nil)
    }

    private func transitionToBreakComplete() {
        phase = .breakComplete
        internalRemaining = 0
        statusDetail = L10n.text("Break complete", "休息已达标")
        publishRemainingIfDisplayChanged(force: true)
        persistBreakSession()
        stopTicking()
        BreakCompletionEventWriter.write()
    }

    private func transitionToWorkingAfterBreak() {
        phase = .working
        internalRemaining = config.workDurationSeconds
        preBreakWarningSent = false
        statusDetail = ""
        appliedPenaltyMinutes = 0
        BreakSessionStore.clear()
        publishRemainingIfDisplayChanged(force: true)
        if tickTimer == nil { startTicking() }
        NotificationCenter.default.post(name: .lookAwayBreakEnded, object: nil)
    }

    private func loadBreakStats() {
        pendingPenaltyMinutes = BreakStatsStore.load().pendingPenaltyMinutes
    }

    private func persistBreakStats() {
        BreakStatsStore.save(BreakStats(pendingPenaltyMinutes: pendingPenaltyMinutes))
    }

    private func persistBreakSession() {
        switch phase {
        case .onBreak:
            BreakSessionStore.save(BreakSession(
                phase: .onBreak,
                endsAt: Date().addingTimeInterval(max(0, internalRemaining)),
                appliedPenaltyMinutes: appliedPenaltyMinutes
            ))
        case .breakComplete:
            BreakSessionStore.save(BreakSession(
                phase: .breakComplete,
                endsAt: Date(),
                appliedPenaltyMinutes: appliedPenaltyMinutes
            ))
        case .working, .preBreakWarning, .paused:
            break
        }
    }

    private func recordEarlyAbort() {
        if config.skipPenaltyMinutes > 0 {
            pendingPenaltyMinutes += config.skipPenaltyMinutes
        }
        persistBreakStats()
    }

    private func reevaluatePhase(micActive: Bool? = nil) {
        let mic = micActive ?? MicrophoneMonitor.checkMicrophoneInUse()

        if phase == .onBreak {
            if tickTimer == nil {
                startTicking()
            }
            return
        }

        if phase == .breakComplete {
            stopTicking()
            return
        }

        let shouldPause = isManuallyPaused || mic

        if shouldPause {
            if phase != .paused {
                phase = .paused
                syncMenuBarPresentation(force: true)
                stopTicking()
            }
        } else if phase == .paused {
            if internalRemaining <= 0 {
                beginBreak()
            } else if config.preBreakWarningMinutes > 0 && internalRemaining <= config.preBreakWarningSeconds {
                phase = .preBreakWarning
                syncMenuBarPresentation(force: true)
                NotificationCenter.default.post(name: .lookAwayPreBreakWarning, object: nil)
                if tickTimer == nil { startTicking() }
            } else {
                phase = .working
                syncMenuBarPresentation(force: true)
                if tickTimer == nil { startTicking() }
            }
        } else if tickTimer == nil {
            startTicking()
        }
    }

    private func sendPreBreakNotificationIfNeeded() {
        guard !preBreakWarningSent else { return }
        preBreakWarningSent = true
        let warningMinutes = config.preBreakWarningMinutes
        let reminderMessage = config.reminderMessage
        let title = L10n.text(
            "Mandatory break in \(warningMinutes) min",
            "\(warningMinutes) 分钟后强制休息"
        )

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = reminderMessage
            content.categoryIdentifier = LookAwayNotification.preBreakCategory
            let request = UNNotificationRequest(
                identifier: LookAwayNotification.preBreakRequestID,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%dm %02ds", minutes, secs)
    }

    private func formattedMenuBarTime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(ceil(max(0, seconds) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

extension Notification.Name {
    static let lookAwayPreBreakWarning = Notification.Name("lookAwayPreBreakWarning")
    static let lookAwayBreakStarted = Notification.Name("lookAwayBreakStarted")
    static let lookAwayBreakEnded = Notification.Name("lookAwayBreakEnded")
}

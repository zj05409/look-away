import AppKit
import Combine
import Foundation
import UserNotifications

enum TimerPhase: Equatable {
    case working
    case preBreakWarning
    case onBreak
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
    private var wasSystemPaused = false
    /// Wall-clock start of display off, sleep, or screen lock; cleared on return.
    private var systemAwayStartedAt: Date?

    var menuBarLabel: String {
        switch phase {
        case .onBreak:
            return "Break: \(menuBarDisplayTime)"
        case .paused:
            if statusDetail.contains("call") {
                return "Call active"
            }
            return "Paused"
        case .preBreakWarning:
            return "Break soon: \(menuBarDisplayTime)"
        case .working:
            return "\(menuBarDisplayTime) left"
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
            return "Focus session"
        case .preBreakWarning:
            return "Break approaching"
        case .onBreak:
            return "Rest your eyes"
        case .paused:
            return "Paused"
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
            return config.breakDurationSeconds + TimeInterval(appliedPenaltyMinutes * 60)
        case .paused:
            return config.workDurationSeconds
        }
    }

    var progressFraction: Double {
        let total = activePhaseDuration
        guard total > 0 else { return 0 }
        return max(0, min(1, 1 - (remainingSeconds / total)))
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
            if config.breakDurationMinutes != previous.breakDurationMinutes {
                internalRemaining = config.breakDurationSeconds
            } else {
                internalRemaining = min(internalRemaining, config.breakDurationSeconds)
            }
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
        publishRemainingIfDisplayChanged(force: true)
        if tickTimer == nil { startTicking() }
    }

    func handleExternalPause(micActive: Bool, systemPaused: Bool, systemPauseDetail: String = "") {
        let systemJustPaused = !wasSystemPaused && systemPaused
        let systemJustResumed = wasSystemPaused && !systemPaused

        if systemJustPaused {
            systemAwayStartedAt = Date()
        }

        if systemJustResumed {
            handleReturnFromSystemAway()
        }

        wasSystemPaused = systemPaused

        let newDetail: String
        if micActive {
            newDetail = "Paused — call active"
        } else if systemPaused {
            newDetail = systemPauseDetail.isEmpty ? "Paused — away from screen" : systemPauseDetail
        } else if isManuallyPaused {
            newDetail = "Paused manually"
        } else {
            newDetail = ""
        }

        if newDetail != statusDetail {
            statusDetail = newDetail
            if phase == .paused {
                syncMenuBarPresentation(force: true)
            }
        }

        reevaluatePhase(micActive: micActive, systemPaused: systemPaused)
    }

    /// On return from display off, sleep, or lock: restart only if away time met the break threshold.
    private func handleReturnFromSystemAway() {
        defer { systemAwayStartedAt = nil }

        guard let startedAt = systemAwayStartedAt else { return }
        let awayDuration = Date().timeIntervalSince(startedAt)
        guard awayDuration >= config.breakDurationSeconds else { return }

        restartWorkSessionAfterLongAway()
    }

    /// Away long enough to count as a break — restart work and dismiss overlay if needed.
    private func restartWorkSessionAfterLongAway() {
        let wasOnBreak = phase == .onBreak

        if wasOnBreak {
            appliedPenaltyMinutes = 0
        }

        phase = .working
        internalRemaining = config.workDurationSeconds
        preBreakWarningSent = false
        publishRemainingIfDisplayChanged(force: true)

        if wasOnBreak {
            NotificationCenter.default.post(name: .lookAwayBreakEnded, object: nil)
        }
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
        case .paused:
            newText = statusDetail.contains("call") ? "Call active" : "Paused"
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
            statusDetail = "Paused — call active"
            internalRemaining = 0
            publishRemainingIfDisplayChanged(force: true)
            stopTicking()
        } else {
            beginBreak()
        }
    }

    private func handleBreakTick() {
        if internalRemaining <= 0 {
            endBreak()
        }
    }

    private func beginBreak() {
        phase = .onBreak
        appliedPenaltyMinutes = pendingPenaltyMinutes
        if appliedPenaltyMinutes > 0 {
            pendingPenaltyMinutes = 0
            persistBreakStats()
        }
        internalRemaining = config.breakDurationSeconds + TimeInterval(appliedPenaltyMinutes * 60)
        preBreakWarningSent = false
        statusDetail = ""
        publishRemainingIfDisplayChanged(force: true)
        if tickTimer == nil { startTicking() }
        NotificationCenter.default.post(name: .lookAwayBreakStarted, object: nil)
    }

    private func endBreak() {
        transitionToWorkingAfterBreak()
    }

    private func transitionToWorkingAfterBreak() {
        phase = .working
        internalRemaining = config.workDurationSeconds
        preBreakWarningSent = false
        statusDetail = ""
        appliedPenaltyMinutes = 0
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

    private func recordEarlyAbort() {
        if config.skipPenaltyMinutes > 0 {
            pendingPenaltyMinutes += config.skipPenaltyMinutes
        }
        persistBreakStats()
    }

    private func reevaluatePhase(micActive: Bool? = nil, systemPaused: Bool? = nil) {
        let mic = micActive ?? MicrophoneMonitor.checkMicrophoneInUse()
        let asleep = systemPaused ?? false

        if phase == .onBreak {
            if asleep {
                stopTicking()
            } else if tickTimer == nil {
                startTicking()
            }
            return
        }

        let shouldPause = isManuallyPaused || mic || asleep

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

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Break starting soon"
            content.body = "Your look-away break begins in \(Int(self.config.preBreakWarningMinutes)) minute(s). Extend for \(Self.sessionExtensionMinutes) more minutes if you need longer."
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
    static let lookAwayBreakStarted = Notification.Name("lookAwayBreakStarted")
    static let lookAwayBreakEnded = Notification.Name("lookAwayBreakEnded")
}

import AppKit
import CoreGraphics
import Foundation

/// Tracks macOS display, sleep, and lock state for callers that need it.
/// The timer intentionally continues using wall-clock time while any of these states apply.
@MainActor
final class SleepWakeMonitor: ObservableObject {
    @Published private(set) var isSystemPaused = false
    @Published private(set) var pauseDetail: String = ""

    private var isDisplayAsleep = false
    private var isSystemSleeping = false
    private var isScreenLocked = false

    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init() {
        refreshFromSystemState()
        registerObservers()
    }

    deinit {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
        for observer in distributedObservers {
            distributed.removeObserver(observer)
        }
    }

    private func registerObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSystemSleeping = true
                self?.syncPausedState()
            }
        })

        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplayAsleep = true
                self?.syncPausedState()
            }
        })

        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSystemSleeping = false
                self?.refreshFromSystemState()
            }
        })

        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplayAsleep = Self.areAllDisplaysAsleep()
                self?.syncPausedState()
            }
        })

        distributedObservers.append(distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = true
                self?.syncPausedState()
            }
        })

        distributedObservers.append(distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = false
                self?.syncPausedState()
            }
        })
    }

    private func refreshFromSystemState() {
        isDisplayAsleep = Self.areAllDisplaysAsleep()
        isScreenLocked = Self.isScreenLocked()
        syncPausedState()
    }

    private func syncPausedState() {
        let paused = isDisplayAsleep || isSystemSleeping || isScreenLocked
        let detail: String
        if isSystemSleeping {
            detail = "Paused — Mac asleep"
        } else if isDisplayAsleep {
            detail = "Paused — display off"
        } else if isScreenLocked {
            detail = "Paused — screen locked"
        } else {
            detail = ""
        }

        if paused != isSystemPaused {
            isSystemPaused = paused
        }
        if detail != pauseDetail {
            pauseDetail = detail
        }
    }

    /// Returns true when every online display is in reduced-power (non-drawable) mode.
    private static func areAllDisplaysAsleep() -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return false
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success, displayCount > 0 else {
            return false
        }

        return displays.allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }

    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }

        if let locked = session["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        if let locked = session["CGSSessionScreenIsLocked"] as? Int {
            return locked != 0
        }
        return false
    }
}

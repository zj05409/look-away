import Foundation
import UserNotifications

enum LookAwayNotification {
    static let preBreakCategory = "look-away-pre-break"
    static let extendSessionAction = "look-away-extend-session"
    static let preBreakRequestID = "look-away-pre-break"

    @MainActor
    static func registerCategories() {
        let extend = UNNotificationAction(
            identifier: extendSessionAction,
            title: L10n.text(
                "Extend \(TimerEngine.sessionExtensionMinutes) minutes",
                "延后 \(TimerEngine.sessionExtensionMinutes) 分钟"
            ),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: preBreakCategory,
            actions: [extend],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

@MainActor
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    weak var timerEngine: TimerEngine?

    func install() {
        LookAwayNotification.registerCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == LookAwayNotification.extendSessionAction else {
            completionHandler()
            return
        }

        Task { @MainActor in
            timerEngine?.extendSession()
            completionHandler()
        }
    }
}

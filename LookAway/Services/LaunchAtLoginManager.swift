import AppKit
import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginManager {
    private static let promptedKey = "lookAway.hasPromptedLaunchAtLogin"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var hasPrompted: Bool {
        UserDefaults.standard.bool(forKey: promptedKey)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return true }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            print("Launch at login error: \(error.localizedDescription)")
            return false
        }
    }

    static func syncWithConfig(_ shouldEnable: Bool) {
        let currentlyEnabled = isEnabled
        if shouldEnable != currentlyEnabled {
            _ = setEnabled(shouldEnable)
        }
    }

    /// Prompts once on first launch. Default button enables launch at login and writes the choice to config.
    static func promptOnFirstLaunchIfNeeded(configManager: ConfigManager) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: promptedKey) {
            syncWithConfig(configManager.config.launchAtLogin)
            return
        }

        defaults.set(true, forKey: promptedKey)

        let alert = NSAlert()
        alert.messageText = L10n.text("Open Look Away at login?", "登录时自动打开 Look Away？")
        alert.informativeText = L10n.text(
            "Look Away can start automatically when you log in to your Mac. You can change this later in System Settings → General → Login Items.",
            "Look Away 可以在你登录 Mac 时自动启动。之后可在“系统设置 → 通用 → 登录项”中更改。"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("Open at Login", "登录时打开"))
        alert.addButton(withTitle: L10n.text("Not Now", "暂不"))

        NSApp.activate(ignoringOtherApps: true)
        let enable = alert.runModal() == .alertFirstButtonReturn
        _ = setEnabled(enable)
        configManager.update { $0.launchAtLogin = enable }
    }
}

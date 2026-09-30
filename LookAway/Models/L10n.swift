import Foundation

/// Minimal two-language string lookup. The app ships without `.lproj` bundles
/// (build.sh compiles sources directly), so user-facing text is chosen here
/// from the `language` key in config.json: `zh`, `en`, or `auto`.
enum L10n {
    enum Language: String {
        case chinese = "zh"
        case english = "en"
        case automatic = "auto"
    }

    private static var usesChinese = true

    static func apply(_ rawValue: String) {
        switch Language(rawValue: rawValue) ?? .chinese {
        case .chinese:
            usesChinese = true
        case .english:
            usesChinese = false
        case .automatic:
            usesChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    static func text(_ english: String, _ chinese: String) -> String {
        usesChinese ? chinese : english
    }
}

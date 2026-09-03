import Foundation

struct AppConfig: Codable, Equatable {
    var workDurationMinutes: Int
    var breakDurationMinutes: Int
    var preBreakWarningMinutes: Int
    var skipPenaltyMinutes: Int
    var launchAtLogin: Bool
    var reminderMessage: String

    static let defaults = AppConfig(
        workDurationMinutes: 120,
        breakDurationMinutes: 15,
        preBreakWarningMinutes: 0,
        skipPenaltyMinutes: 5,
        launchAtLogin: true,
        reminderMessage: "喝杯水，并且去有光照的地方慢跑五分钟，回来冷水冲脸"
    )

    enum CodingKeys: String, CodingKey {
        case workDurationMinutes
        case breakDurationMinutes
        case preBreakWarningMinutes
        case skipPenaltyMinutes
        case launchAtLogin
        case reminderMessage
    }

    init(
        workDurationMinutes: Int,
        breakDurationMinutes: Int,
        preBreakWarningMinutes: Int,
        skipPenaltyMinutes: Int,
        launchAtLogin: Bool,
        reminderMessage: String
    ) {
        self.workDurationMinutes = workDurationMinutes
        self.breakDurationMinutes = breakDurationMinutes
        self.preBreakWarningMinutes = preBreakWarningMinutes
        self.skipPenaltyMinutes = skipPenaltyMinutes
        self.launchAtLogin = launchAtLogin
        self.reminderMessage = reminderMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workDurationMinutes = try container.decode(Int.self, forKey: .workDurationMinutes)
        breakDurationMinutes = try container.decode(Int.self, forKey: .breakDurationMinutes)
        preBreakWarningMinutes = try container.decode(Int.self, forKey: .preBreakWarningMinutes)
        skipPenaltyMinutes = try container.decodeIfPresent(Int.self, forKey: .skipPenaltyMinutes) ?? Self.defaults.skipPenaltyMinutes
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? Self.defaults.launchAtLogin
        reminderMessage = try container.decodeIfPresent(String.self, forKey: .reminderMessage) ?? Self.defaults.reminderMessage
    }

    var workDurationSeconds: TimeInterval {
        TimeInterval(workDurationMinutes * 60)
    }

    var breakDurationSeconds: TimeInterval {
        TimeInterval(breakDurationMinutes * 60)
    }

    var preBreakWarningSeconds: TimeInterval {
        TimeInterval(preBreakWarningMinutes * 60)
    }

    static func sanitized(_ config: AppConfig) -> AppConfig {
        var copy = config
        copy.workDurationMinutes = min(max(copy.workDurationMinutes, 1), 24 * 60)
        copy.breakDurationMinutes = min(max(copy.breakDurationMinutes, 1), 180)
        copy.preBreakWarningMinutes = min(max(copy.preBreakWarningMinutes, 0), 60)
        copy.skipPenaltyMinutes = min(max(copy.skipPenaltyMinutes, 0), 60)
        let trimmedMessage = copy.reminderMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.reminderMessage = trimmedMessage.isEmpty
            ? Self.defaults.reminderMessage
            : String(trimmedMessage.prefix(500))
        return copy
    }
}

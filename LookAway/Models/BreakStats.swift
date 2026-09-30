import Foundation

struct BreakStats: Codable, Equatable {
    var pendingPenaltyMinutes: Int = 0

    enum CodingKeys: String, CodingKey {
        case pendingPenaltyMinutes
    }

    init(pendingPenaltyMinutes: Int = 0) {
        self.pendingPenaltyMinutes = pendingPenaltyMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Ignore legacy `consecutiveBreaks` if present in older stats.json files.
        pendingPenaltyMinutes = try container.decodeIfPresent(Int.self, forKey: .pendingPenaltyMinutes) ?? 0
    }
}

enum BreakStatsStore {
    private static var statsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/look-away/stats.json", isDirectory: false)
    }

    static func load() -> BreakStats {
        guard FileManager.default.fileExists(atPath: statsURL.path),
              let data = try? Data(contentsOf: statsURL),
              let stats = try? JSONDecoder().decode(BreakStats.self, from: data) else {
            return BreakStats()
        }
        return stats
    }

    static func save(_ stats: BreakStats) {
        let directory = statsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: statsURL, options: .atomic)
    }
}

/// A break that is still owed or awaiting the explicit "Start Working" confirmation.
/// Persisted so quitting, crashing, or killing the app cannot bypass a break:
/// on relaunch the overlay comes back with the remaining time.
struct BreakSession: Codable, Equatable {
    enum Phase: String, Codable {
        case onBreak
        case breakComplete
    }

    var phase: Phase
    var endsAt: Date
    var appliedPenaltyMinutes: Int
}

enum BreakSessionStore {
    private static var sessionURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/look-away/session.json", isDirectory: false)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func load() -> BreakSession? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? makeDecoder().decode(BreakSession.self, from: data)
    }

    static func save(_ session: BreakSession) {
        let directory = sessionURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? makeEncoder().encode(session) else { return }
        try? data.write(to: sessionURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: sessionURL)
    }
}

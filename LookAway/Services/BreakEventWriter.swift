import Foundation

/// Publishes timer transitions for local automations.
enum BreakEventWriter {
    enum Event: String {
        case start = "break-start"
        case complete = "break-complete"

        var timestampKey: String {
            switch self {
            case .start: return "startedAt"
            case .complete: return "completedAt"
            }
        }
    }

    static func write(
        _ event: Event,
        in directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/look-away", isDirectory: true)
    ) {
        let payload: [String: String] = [
            "eventID": UUID().uuidString,
            "type": event.rawValue,
            event.timestampKey: ISO8601DateFormatter().string(from: Date()),
        ]

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let eventURL = directoryURL.appendingPathComponent("\(event.rawValue).json")
            try data.write(to: eventURL, options: .atomic)
        } catch {
            NSLog("Look Away: failed to publish \(event.rawValue) event — \(error.localizedDescription)")
        }
    }
}

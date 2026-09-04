import Foundation

/// Publishes one small local event whenever a required break is completed.
/// External helpers can react without inspecting the foreground application or
/// involving an AI model.
enum BreakCompletionEventWriter {
    private static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/look-away", isDirectory: true)
    private static let eventURL = directoryURL.appendingPathComponent("break-complete.json")

    static func write() {
        let payload: [String: String] = [
            "eventID": UUID().uuidString,
            "type": "break-complete",
            "completedAt": ISO8601DateFormatter().string(from: Date()),
        ]

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: eventURL, options: .atomic)
        } catch {
            NSLog("Look Away: failed to publish break-complete event — \(error.localizedDescription)")
        }
    }
}

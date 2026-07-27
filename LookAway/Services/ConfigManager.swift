import AppKit
import Foundation

@MainActor
final class ConfigManager: ObservableObject {
    @Published private(set) var config: AppConfig

    let configURL: URL

    private var fileWatcher: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32
    private var suppressWatcherReloadUntil: Date?

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/look-away", isDirectory: true)
        configURL = configDir.appendingPathComponent("config.json")

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let initialConfig: AppConfig
        if FileManager.default.fileExists(atPath: configURL.path) {
            initialConfig = (try? ConfigManager.load(from: configURL)) ?? .defaults
        } else {
            initialConfig = .defaults
            try? ConfigManager.save(initialConfig, to: configURL)
        }
        config = initialConfig

        fileDescriptor = open(configURL.path, O_EVTONLY)
        if fileDescriptor >= 0 {
            startWatching()
        }
    }

    deinit {
        fileWatcher?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    func reload() {
        if let until = suppressWatcherReloadUntil, Date() < until {
            return
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        if let loaded = try? ConfigManager.load(from: configURL) {
            config = loaded
        }
    }

    func update(_ transform: (inout AppConfig) -> Void) {
        var updated = config
        transform(&updated)
        updated = AppConfig.sanitized(updated)
        persist(updated)
    }

    func replace(with newConfig: AppConfig) {
        persist(AppConfig.sanitized(newConfig))
    }

    private func persist(_ updated: AppConfig) {
        config = updated
        suppressWatcherReloadUntil = Date().addingTimeInterval(0.5)
        do {
            try ConfigManager.save(config, to: configURL)
        } catch {
            NSLog("Look Away: failed to save config — \(error.localizedDescription)")
        }
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configURL)
    }

    private func startWatching() {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
        source.setCancelHandler { [fileDescriptor] in
            close(fileDescriptor)
        }
        source.resume()
        fileWatcher = source
    }

    private static func load(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(AppConfig.self, from: data)
    }

    private static func save(_ config: AppConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}

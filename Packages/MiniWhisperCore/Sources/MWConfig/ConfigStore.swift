import Foundation
import MWSupport

/// Seam over the `DispatchSource` file watch so tests can drive external edits (§5.9).
public protocol FileWatcher: Sendable {
    func start(url: URL, onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// Set from the watcher's thread, consumed on the actor.
private final class StaleFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.withLock { value = true }
    }

    @discardableResult
    func take() -> Bool {
        lock.withLock {
            defer { value = false }
            return value
        }
    }
}

/// Owns `~/.config/mini-whisper/config.json`: defaults on first run, corrupt-file backup,
/// the one-shot `daily_usage` migration, atomic writes and an in-memory cache invalidated
/// by out-of-process edits (F2, §5.9).
public actor ConfigStore {
    private let directory: URL
    private let watcher: any FileWatcher
    private let stale = StaleFlag()
    private var cached: Config?

    public nonisolated let changes: AsyncStream<Config>
    private nonisolated let continuation: AsyncStream<Config>.Continuation

    private var configURL: URL { directory.appendingPathComponent("config.json") }
    private var backupURL: URL { directory.appendingPathComponent("config.json.bak") }

    public init(directory: URL, watcher: any FileWatcher = DispatchSourceWatcher()) {
        self.directory = directory
        self.watcher = watcher
        (changes, continuation) = AsyncStream.makeStream()
        let stale = self.stale
        watcher.start(url: directory.appendingPathComponent("config.json")) { stale.set() }
    }

    deinit {
        watcher.stop()
        continuation.finish()
    }

    public func load() -> Config {
        if stale.take() { cached = nil }
        if let cached { return cached }
        let config = readFromDisk()
        cached = config
        return config
    }

    public func update(_ mutate: (inout Config) -> Void) throws {
        var config = load()
        mutate(&config)
        let validated = config.validated()
        try write(validated)
        // Our own write trips the watcher; drop that event so the next load stays cached.
        stale.take()
        cached = validated
        continuation.yield(validated)
    }

    private func readFromDisk() -> Config {
        guard let data = try? Data(contentsOf: configURL) else {
            return restoreDefaults()
        }
        guard let decoded = try? JSONDecoder().decode(Config.self, from: data) else {
            backUpCorruptFile()
            return restoreDefaults()
        }
        return migratingDailyUsage(decoded.validated())
    }

    private func restoreDefaults() -> Config {
        let defaults = Config()
        do {
            try write(defaults)
        } catch {
            Log.config.error("could not write config.json: \(AnyError(error).description)")
        }
        return defaults
    }

    private func backUpCorruptFile() {
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: configURL, to: backupURL)
        Log.config.warning("config.json was corrupt; defaults restored (backup: config.json.bak)")
    }

    /// `config.py:_migrate_daily_usage` — the legacy today-only store folds into `usage`
    /// and is dropped; a stale day is discarded outright.
    private func migratingDailyUsage(_ config: Config) -> Config {
        guard let legacy = config.extra["daily_usage"] else { return config }
        var migrated = config
        migrated.extra["daily_usage"] = nil
        let today = Self.todayKey()
        if case .object(let days) = legacy,
            case .object(let entry)? = days[today],
            !entry.isEmpty {
            migrated.usage[today] = DayUsage(
                inputTokens: Int(entry["input_tokens"]?.numberValue ?? 0),
                outputTokens: Int(entry["output_tokens"]?.numberValue ?? 0)
            )
        }
        try? write(migrated)
        Log.config.info("Migrated daily_usage to usage store")
        return migrated
    }

    /// `Data.write(options: .atomic)` writes a sibling temp file and renames it over the
    /// target, so a failure leaves the previous config.json untouched and no partial file.
    private func write(_ config: Config) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try config.encoded().write(to: configURL, options: .atomic)
    }

    private nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func todayKey() -> String {
        dayFormatter.string(from: Date())
    }
}

/// Watches config.json for out-of-process edits; an atomic replace arrives as a rename,
/// so the watch is re-armed on the new inode.
public final class DispatchSourceWatcher: FileWatcher, @unchecked Sendable {
    private let lock = NSLock()
    private var source: (any DispatchSourceFileSystemObject)?

    public init() {}

    deinit {
        stop()
    }

    public func start(url: URL, onChange: @escaping @Sendable () -> Void) {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self, weak source] in
            let events = source?.data ?? []
            onChange()
            if events.contains(.rename) || events.contains(.delete) {
                self?.start(url: url, onChange: onChange)
            }
        }
        source.setCancelHandler { close(descriptor) }
        lock.withLock { self.source = source }
        source.resume()
    }

    public func stop() {
        let previous = lock.withLock { () -> (any DispatchSourceFileSystemObject)? in
            defer { source = nil }
            return source
        }
        previous?.cancel()
    }
}

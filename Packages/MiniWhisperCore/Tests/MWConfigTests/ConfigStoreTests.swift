import Foundation
import Testing
@testable import MWConfig
import MWSupport
import MWTestSupport

private final class FakeFileWatcher: FileWatcher, @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (@Sendable () -> Void)?

    func start(url: URL, onChange: @escaping @Sendable () -> Void) {
        lock.withLock { self.onChange = onChange }
    }

    func stop() {
        lock.withLock { onChange = nil }
    }

    func trigger() {
        lock.withLock { onChange }?()
    }
}

@Suite struct ConfigStoreTests {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func dayKey(offsetDays: Int = 0) -> String {
        Self.dayFormatter.string(from: Date().addingTimeInterval(TimeInterval(offsetDays) * 86_400))
    }

    private func makeStore(_ directory: URL) -> ConfigStore {
        ConfigStore(directory: directory, watcher: FakeFileWatcher())
    }

    @Test func createsDefaultsOnFirstLoad() async throws {
        let directory = try TempDirectory()

        let config = await makeStore(directory.url).load()

        #expect(config == Config())
        #expect(try Data(contentsOf: directory.file("config.json")) == Config().encoded())
    }

    /// F32's platform default applies only while `streaming_engine` is absent, so a
    /// first run must not pin one: a new install on macOS 26 takes SpeechAnalyzer as
    /// soon as the model is installed, instead of being stuck on SFSpeechRecognizer.
    @Test func firstRunWritesNoEngineChoice() async throws {
        let directory = try TempDirectory()

        let config = await makeStore(directory.url).load()

        #expect(config.streamingEngine == nil)
        let object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.file("config.json"))
        ) as? [String: Any]
        #expect(object?.keys.contains("streaming_engine") == false)
    }

    @Test func backsUpCorruptJSONAndRestoresDefaults() async throws {
        let directory = try TempDirectory()
        try "not valid json{{{".write(to: directory.file("config.json"), atomically: true, encoding: .utf8)
        let sink = CapturingLogSink()

        let config = await Log.withSinks(debug: false, sinks: [sink]) {
            await makeStore(directory.url).load()
        }

        #expect(config == Config())
        let backup = directory.file("config.json.bak")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "not valid json{{{")
        #expect(sink.records.contains { $0.level == .warning && $0.category == "config" })
    }

    @Test func migratesDailyUsageForToday() async throws {
        let directory = try TempDirectory()
        let today = dayKey()
        let json = """
            {"hotkey": "shift+cmd_r",
             "daily_usage": {"\(today)": {"input_tokens": 7, "output_tokens": 9}}}
            """
        try json.write(to: directory.file("config.json"), atomically: true, encoding: .utf8)

        let config = await makeStore(directory.url).load()

        #expect(config.extra["daily_usage"] == nil)
        #expect(config.usage[today] == DayUsage(inputTokens: 7, outputTokens: 9))

        let onDisk = try #require(
            JSONSerialization.jsonObject(with: try Data(contentsOf: directory.file("config.json")))
                as? [String: Any]
        )
        #expect(onDisk["daily_usage"] == nil)
        let usage = try #require((onDisk["usage"] as? [String: Any])?[today] as? [String: Any])
        #expect(usage["input_tokens"] as? Int == 7)
        #expect(usage["output_tokens"] as? Int == 9)
    }

    @Test func dropsStaleDailyUsage() async throws {
        let directory = try TempDirectory()
        let json = """
            {"daily_usage": {"\(dayKey(offsetDays: -1))": {"input_tokens": 99, "output_tokens": 99}}}
            """
        try json.write(to: directory.file("config.json"), atomically: true, encoding: .utf8)

        let config = await makeStore(directory.url).load()

        #expect(config.extra["daily_usage"] == nil)
        #expect(config.usage.isEmpty)
    }

    @Test func updateWritesAtomically() async throws {
        let directory = try TempDirectory()
        let store = makeStore(directory.url)
        _ = await store.load()
        let before = try Data(contentsOf: directory.file("config.json"))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: directory.url.path
        )
        await #expect(throws: (any Error).self) {
            try await store.update { $0.cleanupEnabled = false }
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: directory.url.path
        )

        #expect(try Data(contentsOf: directory.file("config.json")) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == ["config.json"])
        #expect(await store.load().cleanupEnabled)
    }

    @Test func changesStreamEmitsAfterUpdate() async throws {
        let directory = try TempDirectory()
        let store = makeStore(directory.url)
        _ = await store.load()

        try await store.update { $0.soundVolume = 0.25 }

        var iterator = store.changes.makeAsyncIterator()
        #expect(await iterator.next()?.soundVolume == 0.25)
        #expect(await store.load().soundVolume == 0.25)
    }

    @Test func externalEditIsPickedUp() async throws {
        let directory = try TempDirectory()
        let watcher = FakeFileWatcher()
        let store = ConfigStore(directory: directory.url, watcher: watcher)
        #expect(await store.load().soundVolume == 1.0)

        var edited = Config()
        edited.soundVolume = 0.5
        try edited.encoded().write(to: directory.file("config.json"))
        #expect(await store.load().soundVolume == 1.0)

        watcher.trigger()

        #expect(await store.load().soundVolume == 0.5)
    }
}

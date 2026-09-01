import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWHistory

/// Storage rules for `history.jsonl` (F29, design §5.3, §5.7 rows 15–16, §5.8). The path
/// is always injected so no test can reach `~/.config/mini-whisper`.
@Suite struct HistoryStoreTests {
    /// Retention read through a closure on every call, so a test can change it mid-flight
    /// the way Settings does.
    private final class Retention: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int

        init(_ value: Int) { self.value = value }

        var days: Int {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    /// Formatting and parsing on `ISO8601DateFormatter` are thread-safe; this instance is
    /// never mutated after the initialiser runs.
    private nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func at(_ text: String) -> Date {
        guard let date = iso.date(from: text) else {
            preconditionFailure("malformed fixture timestamp \(text)")
        }
        return date
    }

    private func entry(
        id: String = UUID().uuidString,
        at timestamp: String = "2026-09-01T17:38:02Z",
        text: String = "hello world",
        appName: String = "Slack",
        bundleID: String? = "com.tinyspeck.slackmacgap",
        engine: String? = "speech_analyzer",
        streamedSeconds: Double = 6.2,
        costUSD: Double = 0.001
    ) -> HistoryEntry {
        HistoryEntry(
            id: id,
            timestamp: Self.at(timestamp),
            text: text,
            appName: appName,
            bundleID: bundleID,
            engine: engine,
            streamedSeconds: streamedSeconds,
            costUSD: costUSD
        )
    }

    private func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func object(_ line: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    @Test func appendWritesOneJSONLineWithAllFields() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let store = HistoryStore(url: url, retention: { 7 }, now: { Self.at("2026-09-01T18:00:00Z") })

        try await store.append(entry(id: "3f2b"))

        let lines = try lines(url)
        #expect(lines.count == 1)
        let object = try object(lines[0])
        #expect(object["id"] as? String == "3f2b")
        #expect(object["ts"] as? String == "2026-09-01T17:38:02Z")
        #expect(object["text"] as? String == "hello world")
        #expect(object["app_name"] as? String == "Slack")
        #expect(object["bundle_id"] as? String == "com.tinyspeck.slackmacgap")
        #expect(object["engine"] as? String == "speech_analyzer")
        #expect(object["streamed_seconds"] as? Double == 6.2)
        #expect(object["cost_usd"] as? Double == 0.001)
    }

    @Test func batchDictationWritesNullEngine() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let store = HistoryStore(url: url, retention: { 7 }, now: { Date() })

        try await store.append(entry(engine: nil, streamedSeconds: 0))

        let object = try object(try lines(url)[0])
        #expect(object["engine"] is NSNull)
        #expect(object["streamed_seconds"] as? Double == 0)
    }

    @Test func fileModeIs0600() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let store = HistoryStore(url: url, retention: { 7 }, now: { Date() })

        try await store.append(entry())
        let afterAppend = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(afterAppend[.posixPermissions] as? Int == 0o600)

        try await store.clear()
        let afterRewrite = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(afterRewrite[.posixPermissions] as? Int == 0o600)
    }

    @Test func entriesLoadNewestLast() async throws {
        let directory = try TempDirectory()
        let store = HistoryStore(
            url: directory.file("history.jsonl"),
            retention: { 7 },
            now: { Self.at("2026-09-01T18:00:00Z") }
        )

        try await store.append(entry(at: "2026-09-01T10:00:00Z", text: "first"))
        try await store.append(entry(at: "2026-09-01T11:00:00Z", text: "second"))
        try await store.append(entry(at: "2026-09-01T12:00:00Z", text: "third"))

        let reloaded = HistoryStore(
            url: directory.file("history.jsonl"),
            retention: { 7 },
            now: { Self.at("2026-09-01T18:00:00Z") }
        )
        #expect(await store.entries().map(\.text) == ["first", "second", "third"])
        #expect(await reloaded.entries().map(\.text) == ["first", "second", "third"])
    }

    @Test func deleteRewritesWithoutEntry() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let store = HistoryStore(url: url, retention: { 7 }, now: { Self.at("2026-09-01T18:00:00Z") })
        try await store.append(entry(id: "a", text: "first"))
        try await store.append(entry(id: "b", text: "second"))
        try await store.append(entry(id: "c", text: "third"))

        try await store.delete(id: "b")

        #expect(await store.entries().map(\.text) == ["first", "third"])
        #expect(try lines(url).count == 2)
    }

    @Test func clearRemovesAllLinesKeepsFile() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let store = HistoryStore(url: url, retention: { 7 }, now: { Self.at("2026-09-01T18:00:00Z") })
        try await store.append(entry())

        try await store.clear()

        #expect(await store.entries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try String(contentsOf: url, encoding: .utf8).isEmpty)
    }

    @Test func pruneDropsEntriesOlderThanRetention() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let seeding = HistoryStore(
            url: url,
            retention: { 30 },
            now: { Self.at("2026-09-01T12:00:00Z") }
        )
        try await seeding.append(entry(at: "2026-08-24T11:00:00Z", text: "eight days old"))
        try await seeding.append(entry(at: "2026-08-26T13:00:00Z", text: "six days old"))

        let store = HistoryStore(url: url, retention: { 7 }, now: { Self.at("2026-09-01T12:00:00Z") })
        try await store.prune()

        #expect(await store.entries().map(\.text) == ["six days old"])
        #expect(try lines(url).count == 1)
    }

    @Test func pruneRunsAfterAppend() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let seeding = HistoryStore(
            url: url,
            retention: { 30 },
            now: { Self.at("2026-08-01T12:00:00Z") }
        )
        try await seeding.append(entry(at: "2026-08-01T12:00:00Z", text: "old"))

        let store = HistoryStore(url: url, retention: { 7 }, now: { Self.at("2026-09-01T12:00:00Z") })
        try await store.append(entry(at: "2026-09-01T12:00:00Z", text: "new"))

        #expect(await store.entries().map(\.text) == ["new"])
        #expect(try lines(url).count == 1)
    }

    @Test func retentionZeroDeletesFileAndDisablesWrites() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let retention = Retention(7)
        let store = HistoryStore(url: url, retention: { retention.days }, now: { Date() })
        try await store.append(entry())
        #expect(FileManager.default.fileExists(atPath: url.path))

        retention.days = 0
        try await store.append(entry(text: "not written"))

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await store.entries().isEmpty)
    }

    @Test func retentionChangeFromZeroReenablesWrites() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let retention = Retention(0)
        let store = HistoryStore(url: url, retention: { retention.days }, now: { Date() })
        try await store.append(entry(text: "dropped"))
        #expect(!FileManager.default.fileExists(atPath: url.path))

        retention.days = 7
        try await store.append(entry(text: "kept"))

        #expect(await store.entries().map(\.text) == ["kept"])
        #expect(try lines(url).count == 1)
    }

    @Test func searchIsCaseInsensitiveSubstring() async throws {
        let directory = try TempDirectory()
        let store = HistoryStore(
            url: directory.file("history.jsonl"),
            retention: { 7 },
            now: { Self.at("2026-09-01T12:00:00Z") }
        )
        try await store.append(entry(at: "2026-09-01T10:00:00Z", text: "Ship the release notes"))
        try await store.append(entry(at: "2026-09-01T11:00:00Z", text: "buy milk"))

        #expect(await store.search("SHIP").map(\.text) == ["Ship the release notes"])
        #expect(await store.search("e rel").map(\.text) == ["Ship the release notes"])
        #expect(await store.search("zebra").isEmpty)
        #expect(await store.search("").count == 2)
    }

    @Test func corruptLineIsSkippedLoggedAndDroppedOnNextPrune() async throws {
        let directory = try TempDirectory()
        let url = directory.file("history.jsonl")
        let seeding = HistoryStore(url: url, retention: { 7 }, now: { Self.at("2026-09-01T12:00:00Z") })
        try await seeding.append(entry(at: "2026-09-01T10:00:00Z", text: "first"))
        try await seeding.append(entry(at: "2026-09-01T11:00:00Z", text: "second"))
        let written = try lines(url)
        let corrupted = [written[0], "{not json}", written[1]].joined(separator: "\n") + "\n"
        try Data(corrupted.utf8).write(to: url)

        let sink = CapturingLogSink()
        let store = HistoryStore(url: url, retention: { 7 }, now: { Self.at("2026-09-01T12:00:00Z") })
        let texts = await Log.withSinks(debug: false, sinks: [sink]) {
            await store.entries().map(\.text)
        }

        #expect(texts == ["first", "second"])
        #expect(sink.records.contains { $0.level == .warning && $0.message.contains("history") })

        try await store.prune()
        #expect(try lines(url).count == 2)
        #expect(!(try String(contentsOf: url, encoding: .utf8).contains("not json")))
    }
}

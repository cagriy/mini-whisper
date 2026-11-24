import Foundation
import MWConfig
import MWHistory
import MWMeetings
import MWSupport
import MWTestSupport
import MWUsage
import os
import Testing

import MWStats

@Suite struct StatsStoreSeedTests {
    /// The store's `now`, moved by the test.
    private final class Now: Sendable {
        private let value: OSAllocatedUnfairLock<Date>

        init(_ text: String) throws {
            value = OSAllocatedUnfairLock(initialState: try StatsStoreSeedTests.date(text))
        }

        var date: Date { value.withLock { $0 } }

        func set(_ text: String) throws {
            let date = try StatsStoreSeedTests.date(text)
            value.withLock { $0 = date }
        }
    }

    private static func date(_ text: String) throws -> Date {
        try #require(StatsTime.parse(text)).date
    }

    private static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Half an hour into 1 December in Berlin, still 30 November in UTC.
    private static let today = "2026-12-01T00:30:00+01:00"

    private func store(_ directory: URL, _ now: Now) -> StatsStore {
        StatsStore(directory: directory, now: { now.date }, calendar: { Self.berlin })
    }

    /// Two dictations, today's usage and one earlier meeting with cost, over three days.
    private func sample() throws -> StatsSeed {
        let history = [
            HistoryEntry(
                id: "old", timestamp: try Self.date("2026-11-20T09:00:00+01:00"), text: "Book the room",
                appName: "Notes", bundleID: "com.example.notes", engine: "speech_analyzer", streamedSeconds: 3,
                costUSD: 0.125
            ),
            HistoryEntry(
                id: "new", timestamp: try Self.date("2026-12-01T00:10:00+01:00"), text: "Send it", appName: "Mail",
                costUSD: 0.0625
            ),
        ]
        let meeting = Meeting(
            title: "Planning", startedAt: try Self.date("2026-11-05T10:00:00+01:00"),
            endedAt: try Self.date("2026-11-05T11:00:00+01:00"), mode: .remote, engine: .speechmaticsStandard,
            userName: "Alex", billing: Billing(engineSeconds: 3_600, costUSD: 0.375)
        )
        return StatsSeed(
            history: history, usage: ["2026-12-01": DayUsage(inputTokens: 40, costUSD: 0.25)], meetings: [meeting],
            now: try Self.date(Self.today), calendar: Self.berlin
        )
    }

    private func lines(_ url: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    private func rows<Row: Decodable>(_ type: Row.Type, _ url: URL) throws -> [Row] {
        try lines(url).map { try JSONDecoder().decode(Row.self, from: Data($0.utf8)) }
    }

    private func meta(_ folder: URL) throws -> StatsMeta {
        try JSONDecoder().decode(StatsMeta.self, from: Data(contentsOf: folder.appendingPathComponent("meta.json")))
    }

    private func contents(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func mode(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func setMode(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    @Test func needsSeedIsTrueWithoutMetaAndFalseOnceSeeded() async throws {
        let temp = try TempDirectory()
        let folder = temp.file("stats")
        let stats = store(folder, try Now(Self.today))

        #expect(await stats.needsSeed)
        await stats.seed(try sample())

        #expect(await !stats.needsSeed)
        #expect(await !store(folder, try Now(Self.today)).needsSeed)
    }

    @Test func seedEmptiesTheDirectoryThenWritesTheSeededFilesAndMetaLast() async throws {
        let temp = try TempDirectory()
        try JSONLFile(url: temp.file("days.jsonl")).append(DayRow(day: "2026-01-01", delivered: 9))
        try JSONLFile(url: temp.file("dictations.jsonl")).append(
            DictationRow(id: "stray", at: "2026-01-01T09:00:00+01:00", outcome: .silent)
        )
        try JSONLFile(url: temp.file("meetings.jsonl")).append(MeetingRow(id: UUID(), duration: 90))
        let stats = store(temp.url, try Now(Self.today))
        let seed = try sample()

        await stats.seed(seed)

        let meta = StatsMeta(schema: 1, since: "2026-12-01", created: "2026-11-30T23:30:00+00:00")
        #expect(try contents(temp.url) == ["days.jsonl", "dictations.jsonl", "meta.json"])
        #expect(try rows(DictationRow.self, temp.file("dictations.jsonl")) == seed.dictations)
        #expect(try rows(DayRow.self, temp.file("days.jsonl")) == seed.days)
        #expect(try self.meta(temp.url) == meta)
        #expect(try lines(temp.file("meta.json")).first?.contains(#""schema":1"#) == true)
        #expect(await stats.snapshot() == StatsSnapshot(dictations: seed.dictations, days: seed.days, meta: meta))
    }

    @Test func metaIsLeftUnwrittenWhenASeededFileCannotBeReplaced() async throws {
        let temp = try TempDirectory()
        let blocked = temp.file("dictations.jsonl")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        try Data().write(to: blocked.appendingPathComponent("held"))
        let stats = store(temp.url, try Now(Self.today))
        let seed = try sample()
        let sink = CapturingLogSink()

        try setMode(0o500, of: blocked)
        await Log.withSinks(debug: false, sinks: [sink]) { await stats.seed(seed) }
        try setMode(0o700, of: blocked)

        #expect(!FileManager.default.fileExists(atPath: temp.file("meta.json").path))
        #expect(await stats.needsSeed)
        #expect(sink.lines.contains { $0.hasPrefix("WARNING stats dictations.jsonl not written: ") })
    }

    @Test func seededFilesWithoutMetaStillNeedSeedAndReseedingGivesTheSameFiles() async throws {
        let temp = try TempDirectory()
        let now = try Now(Self.today)
        let seed = try sample()
        await store(temp.url, now).seed(seed)
        let dictations = try Data(contentsOf: temp.file("dictations.jsonl"))
        let days = try Data(contentsOf: temp.file("days.jsonl"))
        try FileManager.default.removeItem(at: temp.file("meta.json"))
        try JSONLFile(url: temp.file("meetings.jsonl")).append(MeetingRow(id: UUID(), duration: 90))

        let relaunched = store(temp.url, now)
        #expect(await relaunched.needsSeed)
        await relaunched.seed(seed)

        #expect(try Data(contentsOf: temp.file("dictations.jsonl")) == dictations)
        #expect(try Data(contentsOf: temp.file("days.jsonl")) == days)
        #expect(try contents(temp.url) == ["days.jsonl", "dictations.jsonl", "meta.json"])
        #expect(await !relaunched.needsSeed)
    }

    @Test func resetReplacesEverythingInOneCallAndSetsSinceToTheResetDate() async throws {
        let temp = try TempDirectory()
        let launch = "2026-11-02T09:00:00+01:00"
        let now = try Now(launch)
        let stats = store(temp.url, now)
        await stats.seed(StatsSeed(
            history: [], usage: ["2026-11-02": DayUsage(costUSD: 0.5)], meetings: [], now: try Self.date(launch),
            calendar: Self.berlin
        ))
        await stats.record(DictationAttempt(
            id: "live", bundleID: nil, engine: nil, seconds: 2, words: 3, outcome: .delivered, wait: nil, costUSD: 0
        ))
        await stats.record(spend: ProviderUsage(purpose: .meeting, costUSD: 0.5))
        await stats.upsert(MeetingRow(id: UUID(), duration: 120))
        try now.set(Self.today)
        let seed = try sample()
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) { await stats.reset(seed) }

        let meta = StatsMeta(since: "2026-12-01", created: "2026-11-30T23:30:00+00:00")
        #expect(try contents(temp.url) == ["days.jsonl", "dictations.jsonl", "meta.json"])
        #expect(try rows(DictationRow.self, temp.file("dictations.jsonl")) == seed.dictations)
        #expect(try rows(DayRow.self, temp.file("days.jsonl")) == seed.days)
        #expect(try self.meta(temp.url) == meta)
        #expect(await stats.snapshot() == StatsSnapshot(dictations: seed.dictations, days: seed.days, meta: meta))
        #expect(sink.lines == ["INFO stats reset", "INFO stats seeded 2 dictations, 3 days, 1 meetings with cost"])
    }

    @Test func anUnreadableMetaIsRewrittenAtOpenFromTheEarliestDayWithoutReseeding() async throws {
        let temp = try TempDirectory()
        let days = JSONLFile(url: temp.file("days.jsonl"))
        try days.append(DayRow(day: "2026-11-02", delivered: 1))
        try days.append(DayRow(day: "2026-10-04", delivered: 2))
        let row = DictationRow(id: "kept", at: "2026-11-02T09:00:00+01:00", outcome: .delivered)
        try JSONLFile(url: temp.file("dictations.jsonl")).append(row)
        try Data(#"{"schema":1,"sin"#.utf8).write(to: temp.file("meta.json"))
        let stats = store(temp.url, try Now(Self.today))
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) { await stats.open() }

        let meta = StatsMeta(since: "2026-10-04", created: "2026-11-30T23:30:00+00:00")
        #expect(try self.meta(temp.url) == meta)
        #expect(try mode(of: temp.file("meta.json")) == 0o600)
        #expect(await stats.snapshot().meta == meta)
        #expect(await stats.snapshot().dictations == [row])
        #expect(try rows(DictationRow.self, temp.file("dictations.jsonl")) == [row])
        #expect(await !stats.needsSeed)
        #expect(sink.lines.contains { $0.hasPrefix("WARNING stats meta.json not read: ") })
        #expect(!sink.lines.contains { $0.hasPrefix("INFO stats seeded") })
    }

    @Test func anUnreadableMetaWithoutDaysStartsToday() async throws {
        let temp = try TempDirectory()
        try Data("{".utf8).write(to: temp.file("meta.json"))
        let stats = store(temp.url, try Now(Self.today))

        await stats.open()

        #expect(try meta(temp.url) == StatsMeta(since: "2026-12-01", created: "2026-11-30T23:30:00+00:00"))
    }

    @Test func openReadsMetaAndWritesNoneWhenItIsAbsent() async throws {
        let temp = try TempDirectory()
        let absent = store(temp.url, try Now(Self.today))
        await absent.open()
        #expect(await absent.snapshot().meta == nil)
        #expect(try contents(temp.url).isEmpty)

        let meta = StatsMeta(since: "2026-09-01", created: "2026-09-01T07:00:00+00:00")
        try JSONLFile.writeAtomically(meta, to: temp.file("meta.json"))
        let written = try Data(contentsOf: temp.file("meta.json"))
        let present = store(temp.url, try Now(Self.today))
        await present.open()

        #expect(await present.snapshot().meta == meta)
        #expect(try Data(contentsOf: temp.file("meta.json")) == written)
    }

    @Test(.timeLimit(.minutes(1)))
    func changesYieldAfterSeedAndReset() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now(Self.today))
        var changes = stats.changes.makeAsyncIterator()

        await stats.seed(try sample())
        #expect(await changes.next() != nil)
        await stats.reset(try sample())
        #expect(await changes.next() != nil)
    }

    @Test func seedingLogsItsCountsOnly() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now(Self.today))
        let sink = CapturingLogSink()
        let seed = try sample()

        await Log.withSinks(debug: false, sinks: [sink]) { await stats.seed(seed) }

        #expect(sink.lines == ["INFO stats seeded 2 dictations, 3 days, 1 meetings with cost"])
    }

    @Test func seededFilesAreOwnerOnlyInAnOwnerOnlyFolder() async throws {
        let temp = try TempDirectory()
        let folder = temp.file("stats")
        await store(folder, try Now(Self.today)).seed(try sample())

        #expect(try mode(of: folder) == 0o700)
        for name in ["dictations.jsonl", "days.jsonl", "meta.json"] {
            #expect(try mode(of: folder.appendingPathComponent(name)) == 0o600)
        }
    }
}

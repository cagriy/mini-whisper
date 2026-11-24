import Foundation
import MWSupport
import MWTestSupport
import MWUsage
import os
import Testing

import MWStats

@Suite struct StatsStoreTests {
    private static let bundle = "com.example.notes"

    /// The store's `now`, moved by the test.
    private final class Now: Sendable {
        private let value: OSAllocatedUnfairLock<Date>

        init(_ text: String) throws {
            value = OSAllocatedUnfairLock(initialState: try StatsStoreTests.date(text))
        }

        var date: Date { value.withLock { $0 } }

        func set(_ text: String) throws {
            let date = try StatsStoreTests.date(text)
            value.withLock { $0 = date }
        }
    }

    private static func date(_ text: String) throws -> Date {
        try #require(StatsTime.parse(text)).date
    }

    private static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func store(_ directory: URL, _ now: Now) -> StatsStore {
        StatsStore(directory: directory, now: { now.date }, calendar: { Self.london })
    }

    private func attempt(
        id: String = UUID().uuidString,
        bundleID: String? = StatsStoreTests.bundle,
        seconds: Double = 6.5,
        words: Int = 12,
        outcome: DictationAttempt.Outcome = .delivered,
        wait: Double? = 1.5,
        costUSD: Double = 0.002
    ) -> DictationAttempt {
        DictationAttempt(
            id: id, bundleID: bundleID, engine: "speech_analyzer", seconds: seconds, words: words,
            outcome: outcome, wait: wait, costUSD: costUSD
        )
    }

    private func lines(_ url: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    private func rows<Row: Decodable>(_ type: Row.Type, _ url: URL) throws -> [Row] {
        try lines(url).map { try JSONDecoder().decode(Row.self, from: Data($0.utf8)) }
    }

    private func mode(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func setMode(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    private func meeting(_ id: UUID, duration: Double) -> MeetingRow {
        MeetingRow(id: id, at: "2026-11-30T09:00:00+00:00", duration: duration, figures: 1)
    }

    @Test func aDeliveredAttemptAppendsOneRowAndOneDayLine() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()

        await stats.record(attempt(id: "a1"))

        #expect(try rows(DictationRow.self, temp.file("dictations.jsonl")) == [DictationRow(
            id: "a1", at: "2026-11-30T09:14:03+00:00", app: Self.bundle, engine: "speech_analyzer",
            seconds: 6.5, words: 12, outcome: .delivered, wait: 1.5, usd: 0.002
        )])
        #expect(try lines(temp.file("days.jsonl")) == [
            #"{"apps":{"com.example.notes":1},"day":"2026-11-30","delivered":1,"hours":{"9":1},"#
                + #""seconds":6.5,"timed_words":12,"words":12}"#,
        ])
    }

    @Test func aDeliveredAttemptWithoutAnAppOrALengthCountsUnderOtherWithNoSeconds() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T21:05:00+00:00"))
        await stats.open()

        await stats.record(attempt(bundleID: nil, seconds: 0, words: 7))

        #expect(try rows(DayRow.self, temp.file("days.jsonl")) == [
            DayRow(day: "2026-11-30", delivered: 1, words: 7, apps: ["other": 1], hours: ["21": 1]),
        ])
    }

    @Test(arguments: DictationAttempt.Outcome.allCases.filter { $0 != .delivered })
    func anUndeliveredAttemptCountsItsOutcome(_ outcome: DictationAttempt.Outcome) async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()

        await stats.record(attempt(id: "u1", words: 0, outcome: outcome, wait: nil, costUSD: 0.001))

        #expect(try rows(DictationRow.self, temp.file("dictations.jsonl")).map(\.outcome) == [outcome])
        #expect(try rows(DayRow.self, temp.file("days.jsonl")) == [
            DayRow(day: "2026-11-30", undelivered: [outcome.rawValue: 1]),
        ])
    }

    @Test func twentyAttemptsGiveTwentyRowsWithDistinctIDs() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()

        for _ in 0..<20 { await stats.record(attempt()) }

        let written = try rows(DictationRow.self, temp.file("dictations.jsonl"))
        #expect(written.count == 20)
        #expect(Set(written.map(\.id)).count == 20)
        #expect(await stats.snapshot().dictations == written)
        #expect(await stats.snapshot().days.map(\.delivered) == [20])
    }

    @Test(arguments: [UsagePurpose.dictation, .meeting, .summary, .naming])
    func spendAppendsOneDayLineUnderItsPurpose(_ purpose: UsagePurpose) async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()

        await stats.record(spend: ProviderUsage(
            purpose: purpose, inputTokens: 100, outputTokens: 20, streamedSeconds: ["elevenlabs": 30], costUSD: 0.25
        ))

        #expect(try rows(DayRow.self, temp.file("days.jsonl")) == [DayRow(
            day: "2026-11-30",
            spend: [purpose.rawValue: Spend(usd: 0.25, tokensIn: 100, tokensOut: 20, seconds: ["elevenlabs": 30])]
        )])
    }

    @Test func aTestCallsSpendAppendsNothing() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()

        await stats.record(spend: ProviderUsage(purpose: .testCall, inputTokens: 5, costUSD: 0.4))
        await stats.record(spend: ProviderUsage(purpose: .meeting, costUSD: 0.1))

        let meetingOnly = [DayRow(day: "2026-11-30", spend: ["meeting": Spend(usd: 0.1)])]
        #expect(try rows(DayRow.self, temp.file("days.jsonl")) == meetingOnly)
        #expect(await stats.snapshot().days == meetingOnly)
    }

    @Test func anAttemptAndItsSpendAppendThreeLines() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()

        await stats.record(attempt())
        await stats.record(spend: ProviderUsage(purpose: .dictation, streamedSeconds: ["speech_analyzer": 6.5]))

        let written = try ["dictations.jsonl", "days.jsonl", "meetings.jsonl"].map { try lines(temp.file($0)).count }
        #expect(written == [1, 2, 0])
    }

    @Test func reopeningGivesTheFoldedState() async throws {
        let temp = try TempDirectory()
        let now = try Now("2026-11-29T22:10:00+00:00")
        let stats = store(temp.url, now)
        await stats.open()
        let first = UUID()
        let second = UUID()

        await stats.record(attempt(words: 4))
        await stats.record(spend: ProviderUsage(purpose: .dictation, inputTokens: 3, costUSD: 0.1))
        await stats.upsert(meeting(first, duration: 100))
        try now.set("2026-11-30T08:00:00+00:00")
        await stats.record(attempt(bundleID: nil, words: 9))
        await stats.record(attempt(outcome: .silent))
        await stats.record(spend: ProviderUsage(purpose: .meeting, streamedSeconds: ["speechmatics": 60], costUSD: 0.2))
        await stats.record(spend: ProviderUsage(purpose: .summary, outputTokens: 50, costUSD: 0.3))
        await stats.upsert(meeting(second, duration: 30))
        await stats.upsert(meeting(first, duration: 120))
        let before = await stats.snapshot()

        let reopened = store(temp.url, now)
        await reopened.open()

        #expect(await reopened.snapshot() == before)
        #expect(before.days.map(\.day) == ["2026-11-29", "2026-11-30"])
        #expect(before.days.map(\.delivered) == [1, 1])
        #expect(before.meetings.map(\.id) == [first, second])
        #expect(before.meetings.map(\.duration) == [120, 30])
        #expect(before.dictations.count == 3)
    }

    @Test func openPrunesDictationRowsPastTheCutoffAndRewritesTheFile() async throws {
        let temp = try TempDirectory()
        let file = JSONLFile(url: temp.file("dictations.jsonl"))
        // London is on GMT on 2025-10-30, so the cutoff for 2026-11-30 is 2025-10-30T00:00:00Z.
        try file.append(DictationRow(id: "old", at: "2025-10-29T23:59:59+00:00", outcome: .delivered))
        try file.append(DictationRow(id: "edge", at: "2025-10-30T00:00:00+00:00", outcome: .delivered))
        try file.append(DictationRow(id: "new", at: "2026-11-30T08:00:00+00:00", outcome: .silent))
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) { await stats.open() }

        #expect(await stats.snapshot().dictations.map(\.id) == ["edge", "new"])
        #expect(try rows(DictationRow.self, file.url).map(\.id) == ["edge", "new"])
        #expect(sink.lines == [
            "INFO stats pruned 1 dictation rows",
            "INFO stats opened, 2 dictations, 0 days, 0 meetings",
        ])
    }

    @Test func theFirstAttemptOnANewLocalDayPrunes() async throws {
        let temp = try TempDirectory()
        let file = JSONLFile(url: temp.file("dictations.jsonl"))
        try file.append(DictationRow(id: "aging", at: "2025-10-29T12:00:00+00:00", outcome: .delivered))
        let now = try Now("2026-11-29T23:00:00+00:00")
        let stats = store(temp.url, now)
        await stats.open()
        await stats.record(attempt(id: "late"))
        #expect(await stats.snapshot().dictations.map(\.id) == ["aging", "late"])

        try now.set("2026-11-30T00:30:00+00:00")
        await stats.record(attempt(id: "next"))

        #expect(await stats.snapshot().dictations.map(\.id) == ["late", "next"])
        #expect(try rows(DictationRow.self, file.url).map(\.id) == ["late", "next"])
    }

    @Test func openFoldsDaysToOneLineADay() async throws {
        let temp = try TempDirectory()
        let file = JSONLFile(url: temp.file("days.jsonl"))
        try file.append(DayRow(day: "2026-11-29", delivered: 1, words: 3))
        try file.append(DayRow(day: "2026-11-30", delivered: 2, words: 5))
        try file.append(DayRow(day: "2026-11-29", delivered: 1, words: 4, hours: ["9": 1]))
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) { await stats.open() }

        let folded = [
            DayRow(day: "2026-11-29", delivered: 2, words: 7, hours: ["9": 1]),
            DayRow(day: "2026-11-30", delivered: 2, words: 5),
        ]
        #expect(await stats.snapshot().days == folded)
        #expect(try rows(DayRow.self, file.url) == folded)
        #expect(sink.lines.contains("INFO stats compacted days.jsonl, 3 lines to 2"))
    }

    @Test func twoThousandAppendedDayLinesTriggerAFold() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()
        let usage = ProviderUsage(purpose: .naming, inputTokens: 1)

        for _ in 0..<1_999 { await stats.record(spend: usage) }
        #expect(try lines(temp.file("days.jsonl")).count == 1_999)

        await stats.record(spend: usage)

        #expect(try rows(DayRow.self, temp.file("days.jsonl")) == [
            DayRow(day: "2026-11-30", spend: ["naming": Spend(tokensIn: 2_000)]),
        ])
    }

    @Test func openCompactsMeetingsWhenTheyHoldMoreLinesThanIDs() async throws {
        let temp = try TempDirectory()
        let file = JSONLFile(url: temp.file("meetings.jsonl"))
        let first = UUID()
        let second = UUID()
        try file.append(meeting(first, duration: 100))
        try file.append(meeting(second, duration: 200))
        try file.append(meeting(first, duration: 150))
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) { await stats.open() }

        #expect(try rows(MeetingRow.self, file.url) == [meeting(first, duration: 150), meeting(second, duration: 200)])
        #expect(await stats.meetingRows()
            == [first: meeting(first, duration: 150), second: meeting(second, duration: 200)])
        #expect(sink.lines.contains("INFO stats compacted meetings.jsonl, 3 lines to 2"))
    }

    @Test func upsertKeepsTheLatestRowPerID() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()
        let first = UUID()
        let second = UUID()

        await stats.upsert(meeting(first, duration: 100))
        await stats.upsert(meeting(second, duration: 200))
        await stats.upsert(meeting(first, duration: 300))

        #expect(await stats.meetingRows()
            == [first: meeting(first, duration: 300), second: meeting(second, duration: 200)])
        #expect(await stats.snapshot().meetings == [meeting(first, duration: 300), meeting(second, duration: 200)])
        #expect(try lines(temp.file("meetings.jsonl")).count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func changesYieldAfterEveryRecordedRow() async throws {
        let temp = try TempDirectory()
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()
        var changes = stats.changes.makeAsyncIterator()

        await stats.record(attempt())
        #expect(await changes.next() != nil)
        await stats.record(spend: ProviderUsage(purpose: .dictation, costUSD: 0.1))
        #expect(await changes.next() != nil)
        await stats.upsert(meeting(UUID(), duration: 90))
        #expect(await changes.next() != nil)
    }

    @Test func aWriteFailureLeavesTheSnapshotUpdatedAndIsLogged() async throws {
        let temp = try TempDirectory()
        let folder = temp.file("stats")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let stats = store(folder, try Now("2026-11-30T09:14:03+00:00"))
        await stats.open()
        try setMode(0o500, of: folder)
        defer { try? setMode(0o700, of: folder) }
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) {
            await stats.record(attempt(id: "kept"))
            await stats.record(spend: ProviderUsage(purpose: .dictation, costUSD: 0.1))
            await stats.upsert(meeting(UUID(), duration: 90))
        }

        let snapshot = await stats.snapshot()
        #expect(snapshot.dictations.map(\.id) == ["kept"])
        #expect(snapshot.days.map(\.delivered) == [1])
        #expect(snapshot.days.first?.spend["dictation"]?.usd == 0.1)
        #expect(snapshot.meetings.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(sink.lines.filter { $0.hasPrefix("WARNING stats dictations.jsonl not written: ") }.count == 1)
        #expect(sink.lines.filter { $0.hasPrefix("WARNING stats days.jsonl not written: ") }.count == 2)
        #expect(sink.lines.filter { $0.hasPrefix("WARNING stats meetings.jsonl not written: ") }.count == 1)
    }

    @Test func aTornFinalLineIsSkippedAndGoneAfterTheFoldAtOpen() async throws {
        let temp = try TempDirectory()
        let fixture = try #require(
            Bundle.module.url(forResource: "torn-days", withExtension: "jsonl", subdirectory: "Fixtures")
        )
        try FileManager.default.copyItem(at: fixture, to: temp.file("days.jsonl"))
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))

        await stats.open()

        let days = [
            DayRow(day: "2026-11-01", delivered: 3, words: 120),
            DayRow(day: "2026-11-02", delivered: 1, words: 40),
        ]
        #expect(await stats.snapshot().days == days)
        let read = try JSONLFile(url: temp.file("days.jsonl")).read(DayRow.self)
        #expect(read.values == days)
        #expect(read.skipped == 0)
    }

    @Test func aTornDictationLineIsDroppedAtOpen() async throws {
        let temp = try TempDirectory()
        let url = temp.file("dictations.jsonl")
        try Data((#"{"at":"2026-11-30T08:00:00+00:00","id":"a","outcome":"silent"}"# + "\n" + #"{"at":"2026-11"#).utf8)
            .write(to: url)
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))

        await stats.open()

        let read = try JSONLFile(url: url).read(DictationRow.self)
        #expect(read.values.map(\.id) == ["a"])
        #expect(read.skipped == 0)
    }

    @Test func aFileThatCannotBeReadIsNeverRewrittenFromMemory() async throws {
        let temp = try TempDirectory()
        let url = temp.file("days.jsonl")
        try JSONLFile(url: url).append(DayRow(day: "2026-11-01", delivered: 5))
        try setMode(0o200, of: url)
        defer { try? setMode(0o600, of: url) }
        let stats = store(temp.url, try Now("2026-11-30T09:14:03+00:00"))
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) { await stats.open() }
        for _ in 0..<2_000 { await stats.record(spend: ProviderUsage(purpose: .naming, inputTokens: 1)) }

        try setMode(0o600, of: url)
        #expect(try lines(url).count == 2_001)
        #expect(try rows(DayRow.self, url).first == DayRow(day: "2026-11-01", delivered: 5))
        #expect(sink.lines.filter { $0.hasPrefix("WARNING stats days.jsonl not read: ") }.count == 1)
    }

    @Test func everyFileIsOwnerOnlyInAnOwnerOnlyFolder() async throws {
        let temp = try TempDirectory()
        let folder = temp.file("stats")
        let now = try Now("2026-11-30T09:14:03+00:00")
        let stats = store(folder, now)
        await stats.open()
        await stats.record(attempt())
        await stats.record(spend: ProviderUsage(purpose: .dictation, costUSD: 0.1))
        await stats.upsert(meeting(UUID(), duration: 90))

        let reopened = store(folder, now)
        await reopened.open()

        #expect(try mode(of: folder) == 0o700)
        #expect(try lines(folder.appendingPathComponent("days.jsonl")).count == 1)
        for name in ["dictations.jsonl", "days.jsonl", "meetings.jsonl"] {
            #expect(try mode(of: folder.appendingPathComponent(name)) == 0o600)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            == ["days.jsonl", "dictations.jsonl", "meetings.jsonl"])
    }

    @Test func noLogLineCarriesTheBundleIdentifier() async throws {
        let temp = try TempDirectory()
        let folder = temp.file("stats")
        let dictations = JSONLFile(url: folder.appendingPathComponent("dictations.jsonl"))
        for (id, at) in [("old", "2024-01-01T09:00:00+00:00"), ("new", "2026-11-30T08:00:00+00:00")] {
            try dictations.append(DictationRow(id: id, at: at, app: Self.bundle, outcome: .delivered))
        }
        try JSONLFile(url: folder.appendingPathComponent("days.jsonl"))
            .append(DayRow(day: "2026-11-30", delivered: 1, apps: [Self.bundle: 1]))
        try Data("{\"day\":".utf8).write(to: folder.appendingPathComponent("meetings.jsonl"))
        let stats = store(folder, try Now("2026-11-30T09:14:03+00:00"))
        let sink = CapturingLogSink()

        await Log.withSinks(debug: false, sinks: [sink]) {
            await stats.open()
            await stats.record(attempt())
            try? setMode(0o400, of: dictations.url)
            await stats.record(attempt(outcome: .failed))
            try? setMode(0o600, of: dictations.url)
        }

        #expect(sink.lines.contains { $0.hasPrefix("INFO stats pruned 1") })
        #expect(sink.lines.contains { $0.hasPrefix("WARNING stats dictations.jsonl not written: ") })
        #expect(!sink.lines.contains { $0.contains(Self.bundle) })
    }
}

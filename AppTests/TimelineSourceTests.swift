import Foundation
import MWConfig
import MWMeetings
import MWStats
import Testing
@testable import MiniWhisper

/// Timeline's inputs as the app gathers them: the record, the kept meetings, the typing speed and
/// the names of the apps dictated into.
@Suite(.timeLimit(.minutes(1))) struct TimelineSourceTests {
    /// Wednesday 25 November 2026, 12:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_795_608_000)

    private struct Index: MeetingSource {
        let entries: [IndexEntry]

        func index() throws -> [IndexEntry] { entries }
        func load(_ id: UUID) throws -> LoadedMeeting { throw CocoaError(.fileNoSuchFile) }
        func meeting(_ id: UUID) throws -> Meeting { throw CocoaError(.fileNoSuchFile) }
        func modified(_ id: UUID) -> Date? { nil }
    }

    private static func entry(_ id: UUID, _ title: String, ended: Bool = true) -> IndexEntry {
        IndexEntry(
            id: id, title: title, startedAt: now.addingTimeInterval(-90_000), endedAt: ended ? now : nil,
            duration: 3_600, mode: .remote, app: nil, engine: .speechmaticsStandard, speakerCount: 2, costUSD: 0,
            hasSummary: false, audioBytes: 0, excerpt: ""
        )
    }

    @Test func theReportReadsTheRecordTheKeptMeetingsAndTheTypingSpeed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mw-timeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = utc
        let now = Self.now
        let stats = StatsStore(
            directory: directory.appendingPathComponent("stats", isDirectory: true), now: { now }, calendar: { calendar }
        )
        await stats.seed(StatsSeed(history: [], usage: [:], meetings: [], now: now, calendar: calendar))
        let apps = Array(repeating: "com.example.notes", count: 12) + Array(repeating: "com.example.gone", count: 6)
            + [nil, nil]
        for (index, app) in apps.enumerated() {
            await stats.record(DictationAttempt(
                id: "d\(index)", bundleID: app, engine: nil, seconds: 6, words: 12, outcome: .delivered, wait: nil,
                costUSD: 0
            ))
        }
        let kept = UUID(), unfinished = UUID()
        await stats.upsert(MeetingRow(id: kept, at: "2026-11-23T09:00:00+00:00", duration: 7_200))
        await stats.upsert(MeetingRow(
            id: unfinished, at: "2026-11-24T09:00:00+00:00", duration: 1_800,
            speakers: (0..<5).map { MeetingRow.Speaker(id: $0, seconds: 60) }
        ))
        await stats.upsert(MeetingRow(id: UUID(), at: "2026-11-24T11:00:00+00:00", duration: 1_800))
        let config = ConfigStore(directory: directory)
        try await config.update { $0.typingWPM = 60 }
        let source = TimelineSource(
            stats: stats,
            meetings: Index(entries: [Self.entry(kept, "Board review"), Self.entry(unfinished, "Live", ended: false)]),
            config: config, apps: StubApps(names: ["com.example.notes": "Notes"]), now: { now }, calendar: { calendar }
        )

        let content = await source.report()

        #expect(content.since == "2026-11-25")
        #expect(content.report.dictation?.typingWPM == 60)
        #expect(content.report.records?.longestMeeting?.meeting?.title == "Board review")
        #expect(content.report.records?.mostSpeakers?.id == unfinished)
        #expect(content.report.records?.mostSpeakers?.meeting == nil)
        // The top apps' names: the Finder name, or the readable end of a bundle identifier.
        #expect(content.appNames == ["com.example.notes": "Notes", "com.example.gone": "gone"])
    }
}

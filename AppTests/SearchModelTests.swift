import Foundation
import MWHistory
import MWMeetings
import MWSupport
import Testing
@testable import MiniWhisper

/// The time limit turns a wait that never returns into a failure.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SearchModelTests {
    /// Monday 9 November 2026, 15:00 UTC.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_794_236_400)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Holds every `load` until `open()`, reporting each as it starts.
    private final class GatedLibrary: MeetingReading, @unchecked Sendable {
        let started: AsyncStream<Void>
        private let base: StubMeetingLibrary
        private let begin: AsyncStream<Void>.Continuation
        private let gate = NSCondition()
        private var isOpen = false

        init(_ base: StubMeetingLibrary) {
            self.base = base
            (started, begin) = AsyncStream.makeStream()
        }

        func index() throws -> [IndexEntry] { try base.index() }

        func load(_ id: UUID) throws -> LoadedMeeting {
            begin.yield()
            gate.lock()
            while !isOpen { gate.wait() }
            gate.unlock()
            return try base.load(id)
        }

        func open() {
            gate.lock()
            isOpen = true
            gate.broadcast()
            gate.unlock()
        }
    }

    private struct BrokenIndex: MeetingReading {
        func index() throws -> [IndexEntry] { throw CocoaError(.fileReadCorruptFile) }
        func load(_ id: UUID) throws -> LoadedMeeting { throw CocoaError(.fileNoSuchFile) }
    }

    @MainActor
    private final class Harness {
        let stub: StubMeetingLibrary
        let directory: URL
        let history: HistoryStore
        let clock = ManualClock()
        let model: SearchModel

        /// `unreadable` are indexed but fail to load.
        init(
            _ meetings: [LoadedMeeting] = [],
            unreadable: [LoadedMeeting] = [],
            library: ((StubMeetingLibrary) -> any MeetingReading)? = nil
        ) {
            stub = StubMeetingLibrary((meetings + unreadable).map(SearchModelTests.entry(from:)), meetings: meetings)
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-search-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            history = HistoryStore(
                url: directory.appendingPathComponent("history.jsonl"),
                retention: { 7 },
                now: { SearchModelTests.now }
            )
            model = SearchModel(deps: SearchModel.Dependencies(
                library: library?(stub) ?? stub,
                history: history,
                clock: clock,
                now: { SearchModelTests.now },
                calendar: SearchModelTests.calendar
            ))
        }

        func add(_ entries: HistoryEntry...) async throws {
            for entry in entries { try await history.append(entry) }
        }

        /// The next sleep the model asked of the clock.
        func nextSleep() async -> Duration? {
            var sleeps = clock.sleeps.makeAsyncIterator()
            return await sleeps.next()
        }

        /// Lets the delay pass and waits for the results.
        func run() async {
            _ = await nextSleep()
            clock.wake()
            await model.pending?.value
        }

        func search(_ query: String) async {
            model.query = query
            await run()
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - Debounce and cancellation

    @Test func searchWaits150MillisecondsBeforeRunning() async throws {
        let harness = Harness([Self.northwind])
        defer { harness.cleanUp() }
        try await harness.add(Self.dictation("Book the maintenance window", minutesAgo: 5))
        let model = harness.model

        model.query = "main"
        model.query = "maintenance"
        #expect(await harness.nextSleep() == .milliseconds(150))
        #expect(await harness.nextSleep() == .milliseconds(150))
        #expect(harness.stub.loads == 0)
        #expect(model.meetings.isEmpty)
        #expect(model.dictations.isEmpty)
        #expect(model.isSearching)

        harness.clock.wake()
        await model.pending?.value

        #expect(harness.stub.loads == 1)
        #expect(model.meetings.map(\.title) == ["Northwind rollout sync"])
        #expect(model.dictations.map(\.text) == ["Book the maintenance window"])
        #expect(!model.isSearching)
    }

    @Test func aNewQueryCancelsTheRunningSearch() async {
        var gate: GatedLibrary?
        let harness = Harness([Self.northwind, Self.standup]) { stub in
            let gated = GatedLibrary(stub)
            gate = gated
            return gated
        }
        defer { harness.cleanUp() }
        let model = harness.model
        var started = gate!.started.makeAsyncIterator()

        model.query = "maintenance"
        _ = await harness.nextSleep()
        harness.clock.wake()
        await started.next()
        let first = model.pending

        model.query = "nothing to see"
        gate!.open()
        await first?.value

        #expect(model.meetings.isEmpty)
        #expect(model.isSearching)
        // Loading stops with the search: the meeting being read is the last.
        #expect(harness.stub.loads == 1)

        await harness.run()
        #expect(model.meetings.map(\.title) == ["Standup"])
        #expect(!model.isSearching)
    }

    @Test func emptyQueryClearsResultsAndCache() async throws {
        let harness = Harness([Self.northwind])
        defer { harness.cleanUp() }
        try await harness.add(Self.dictation("Book the maintenance window", minutesAgo: 5))
        let model = harness.model

        await harness.search("maintenance")
        #expect(model.meetings.count == 1)
        #expect(model.dictations.count == 1)
        #expect(model.cache.meetings.count == 1)

        model.query = "  \n"
        #expect(model.meetings.isEmpty)
        #expect(model.dictations.isEmpty)
        #expect(model.cache.meetings.isEmpty)
        #expect(!model.isSearching)
        #expect(model.pending == nil)
    }

    // MARK: - Results

    @Test func meetingsAndDictationsNewestFirst() async throws {
        let harness = Harness([Self.planning, Self.northwind, Self.review])
        defer { harness.cleanUp() }
        try await harness.add(
            Self.dictation("maintenance yesterday", minutesAgo: 24 * 60),
            Self.dictation("maintenance just now", minutesAgo: 1),
            Self.dictation("nothing here", minutesAgo: 2),
            Self.dictation("Maintenance an hour ago", minutesAgo: 60)
        )

        await harness.search("maintenance")

        #expect(harness.model.meetings.map(\.title) == ["Northwind rollout sync", "Design review", "Q4 planning"])
        #expect(harness.model.dictations.map(\.text) == [
            "maintenance just now", "Maintenance an hour ago", "maintenance yesterday",
        ])
    }

    @Test func upToTwoLabelledSnippets() async {
        let harness = Harness([Self.northwind, Self.standup, Self.planning])
        defer { harness.cleanUp() }

        await harness.search("maintenance window")

        let hits = harness.model.meetings
        #expect(hits.map(\.title) == ["Northwind rollout sync", "Q4 planning"])
        #expect(hits.map { $0.snippets.map(\.label) } == [["Note · 00:40:05", "Summary"], ["Speaker 3 · 01:12:48", "Summary"]])
        #expect(hits.first?.snippets.first?.text == "Ask ops for a Wednesday maintenance window")
        #expect(hits.map(\.id) == [Self.northwind.meeting.id, Self.planning.meeting.id])
    }

    @Test func aTitleMatchCarriesNoSnippets() async {
        let harness = Harness([Self.northwind])
        defer { harness.cleanUp() }

        await harness.search("rollout")

        #expect(harness.model.meetings.map(\.title) == ["Northwind rollout sync"])
        #expect(harness.model.meetings.map(\.snippets) == [[]])
    }

    @Test func testMeetingsAreFound() async {
        let testCall = Self.loaded(
            "Test call · Sprint planning", note: "Sprint scope agreed",
            test: TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning", wer: 0.064)
        )
        let harness = Harness([testCall, Self.standup])
        defer { harness.cleanUp() }

        await harness.search("sprint")

        #expect(harness.model.meetings.map(\.title) == ["Test call · Sprint planning"])
        #expect(harness.model.meetings.map(\.isTest) == [true])
        #expect(harness.model.meetings.first?.snippets.map(\.label) == ["Note · 00:40:05"])
    }

    @Test func meetingMetaReadsDayDurationMode() async {
        let harness = Harness([Self.northwind, Self.review, Self.planning])
        defer { harness.cleanUp() }

        await harness.search("maintenance")

        let hits = harness.model.meetings
        #expect(hits.map(\.meta) == [
            "Today · 48 min · Remote call",
            "Yesterday · 1 h 12 min · In the room",
            "Tuesday 3 Nov · 48 min · Remote call",
        ])
        #expect(hits.map(\.time) == ["14:30", "16:00", "15:00"])
        #expect(hits.map(\.mode) == [.remote, .inRoom, .remote])
        #expect(hits.map(\.isTest) == [false, false, false])
    }

    @Test func dictationMetaReadsDayTimeApp() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let entries = [
            Self.dictation("maintenance today", minutesAgo: 19, app: "Mail", bundleID: "com.apple.mail"),
            Self.dictation("maintenance yesterday", minutesAgo: 24 * 60 - 161),
            Self.dictation("maintenance last week", minutesAgo: 6 * 24 * 60 + 360),
        ]
        for entry in entries { try await harness.add(entry) }

        await harness.search("maintenance")

        let hits = harness.model.dictations
        #expect(hits.map(\.meta) == ["Today 14:41 · Mail", "Yesterday 17:41 · Slack", "Tuesday 3 Nov 09:00 · Slack"])
        #expect(hits.map(\.id) == entries.map(\.id))
        #expect(hits.map(\.glyph) == [
            AppGlyph(appName: "Mail", bundleID: "com.apple.mail"),
            AppGlyph(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            AppGlyph(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
        ])
    }

    @Test func aLongDictationIsShownAsAnExcerpt() async throws {
        let long = String(repeating: "We talked about the roadmap for a while. ", count: 4)
            + "Then ops asked for a Wednesday maintenance window before the rollout. "
            + String(repeating: "After that the conversation moved on to hiring. ", count: 4)
        let short = "Book the maintenance window\nand tell Alex."
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(Self.dictation(long, minutesAgo: 1), Self.dictation(short, minutesAgo: 2))

        await harness.search("  Maintenance Window ")

        let excerpt = try #require(SearchExcerpt.around("Maintenance Window", in: long, context: 90))
        #expect(long.count > 200)
        #expect(excerpt.hasPrefix("…") && excerpt.hasSuffix("…"))
        #expect(harness.model.dictations.map(\.text) == [excerpt, short])
    }

    // MARK: - Cache

    @Test func cacheLoadsEachMeetingOncePerSession() async {
        let harness = Harness([Self.northwind, Self.planning, Self.standup])
        defer { harness.cleanUp() }
        #expect(Self.planning.segments.contains { !$0.words.isEmpty })

        await harness.search("maintenance")
        #expect(harness.stub.loads == 3)
        await harness.search("maintenance window")
        await harness.search("standup")

        #expect(harness.stub.loads == 3)
        #expect(harness.model.meetings.map(\.title) == ["Standup"])
        #expect(harness.model.cache.meetings.count == 3)
        #expect(harness.model.cache.meetings.values.allSatisfy { $0.segments.allSatisfy(\.words.isEmpty) })
    }

    @Test func invalidateEmptiesTheCacheAndReRuns() async throws {
        let harness = Harness([Self.northwind, Self.planning])
        defer { harness.cleanUp() }
        let model = harness.model
        await harness.search("maintenance")
        #expect(model.meetings.map(\.title) == ["Northwind rollout sync", "Q4 planning"])
        #expect(harness.stub.loads == 2)

        try await harness.stub.delete(Self.northwind.meeting.id)
        model.invalidate()
        #expect(model.cache.meetings.isEmpty)
        #expect(model.isSearching)
        await harness.run()

        #expect(harness.stub.loads == 3)
        #expect(model.meetings.map(\.title) == ["Q4 planning"])
    }

    @Test func invalidateWithoutAQueryRunsNothing() {
        let harness = Harness([Self.northwind])
        defer { harness.cleanUp() }

        harness.model.invalidate()

        #expect(harness.model.pending == nil)
        #expect(!harness.model.isSearching)
    }

    // MARK: - Failures

    @Test func aMeetingThatFailsToLoadIsSkippedAndCountedInTheLog() async {
        let harness = Harness([Self.northwind], unreadable: [Self.planning])
        defer { harness.cleanUp() }
        let sink = MessageSink()

        await logging(to: sink) {
            await harness.search("maintenance")
            await harness.search("maintenance window")
        }

        #expect(harness.model.meetings.map(\.title) == ["Northwind rollout sync"])
        // Read once and failed once: the second query retries neither.
        #expect(harness.stub.loads == 2)
        #expect(sink.messages.filter { $0.contains("skipped") } == ["search skipped 1 meetings"])
        #expect(!sink.messages.contains { $0.localizedCaseInsensitiveContains("maintenance") })
    }

    @Test func anUnreadableIndexLeavesTheDictationsAndIsLogged() async throws {
        let harness = Harness { _ in BrokenIndex() }
        defer { harness.cleanUp() }
        try await harness.add(Self.dictation("Book the maintenance window", minutesAgo: 5))
        let sink = MessageSink()

        await logging(to: sink) { await harness.search("maintenance") }

        #expect(harness.model.meetings.isEmpty)
        #expect(harness.model.dictations.map(\.text) == ["Book the maintenance window"])
        #expect(sink.messages.contains { $0.hasPrefix("search: index unreadable") })
        #expect(!sink.messages.contains { $0.localizedCaseInsensitiveContains("maintenance") })
    }

    // MARK: - Labels

    @Test func labelNamesTheSpeakerNoteOrSummary() {
        let meeting = Self.planning
        func label(_ source: SearchSnippet.Source, _ time: Double?) -> String {
            SearchModel.label(of: SearchSnippet(source: source, time: time, text: ""), in: meeting)
        }
        #expect(label(.transcript, 4368) == "Speaker 3 · 01:12:48")
        #expect(label(.transcript, 12) == "Transcript · 00:00:12")
        #expect(label(.note, 2405) == "Note · 00:40:05")
        #expect(label(.summary, nil) == "Summary")
    }

    // MARK: - Fixtures

    private static let northwind = loaded(
        "Northwind rollout sync",
        note: "Ask ops for a Wednesday maintenance window",
        summary: "## Action items\n- **Alex**: ask ops for a Wednesday maintenance window."
    )
    private static let standup = loaded("Standup", startedHoursAgo: 2, note: "Nothing to see")
    private static let review = loaded(
        "Design review", startedHoursAgo: 23, duration: 4320, mode: .inRoom, note: "Maintenance of the tokens"
    )
    private static let planning = loaded(
        "Q4 planning", startedHoursAgo: 6 * 24,
        segment: (speaker: 3, start: 4368, text: "We cannot move the database without a maintenance window."),
        summary: "## Summary\nThree themes, and a maintenance window for the database move."
    )

    private static func loaded(
        _ title: String,
        startedHoursAgo: Double = 0.5,
        duration: Double = 2932,
        mode: MeetingMode = .remote,
        segment: (speaker: Int, start: Double, text: String)? = nil,
        note: String? = nil,
        summary: String? = nil,
        test: TestCallTag? = nil
    ) -> LoadedMeeting {
        let start = now.addingTimeInterval(-startedHoursAgo * 3600)
        let meeting = Meeting(
            title: title, startedAt: start, endedAt: start.addingTimeInterval(duration), durationSeconds: duration,
            mode: mode, engine: .speechmaticsStandard, userName: "Alex",
            speakers: [SpeakerLabel(id: 0, name: "Alex", isUser: true), SpeakerLabel(id: 3, name: "Speaker 3")],
            summary: summary.map {
                Summary(text: $0, model: "claude-sonnet-5-5", createdAt: start, inputTokens: 1, outputTokens: 1, costUSD: 0)
            },
            test: test
        )
        let segments = segment.map {
            [Segment(
                speaker: $0.speaker, start: $0.start, end: $0.start + 3, text: $0.text,
                words: [Word(text: "We", start: $0.start, end: $0.start + 0.2)], session: 1
            )]
        }
        return LoadedMeeting(
            meeting: meeting,
            segments: segments ?? [],
            notes: note.map { [Note(time: 2405, text: $0, createdAt: start)] } ?? []
        )
    }

    private nonisolated static func entry(from loaded: LoadedMeeting) -> IndexEntry {
        let m = loaded.meeting
        return IndexEntry(
            id: m.id, title: m.title, startedAt: m.startedAt, endedAt: m.endedAt, duration: m.durationSeconds,
            mode: m.mode, app: nil, engine: m.engine, speakerCount: m.speakers.count, costUSD: 0.1,
            hasSummary: m.summary != nil, audioBytes: 0, excerpt: "Excerpt.", test: m.test
        )
    }

    private static func dictation(
        _ text: String,
        minutesAgo: Double,
        app: String = "Slack",
        bundleID: String? = "com.tinyspeck.slackmacgap"
    ) -> HistoryEntry {
        HistoryEntry(timestamp: now.addingTimeInterval(-minutesAgo * 60), text: text, appName: app, bundleID: bundleID)
    }
}

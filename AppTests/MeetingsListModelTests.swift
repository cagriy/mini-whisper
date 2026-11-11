import Foundation
import MWConfig
import MWMeetings
import MWSupport
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct MeetingsListModelTests {
    /// Monday 9 November 2026, 15:00 UTC.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_794_236_400)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func entry(
        _ title: String,
        hoursAgo: Double,
        duration: Double = 2932,
        mode: MeetingMode = .remote,
        speakers: Int = 3,
        cost: Double = 0.3976,
        summary: Bool = true,
        audio: Int = 23_000_000,
        excerpt: String = "The rollout stays on schedule.",
        engine: MeetingEngine = .speechmaticsStandard,
        test: TestCallTag? = nil
    ) -> IndexEntry {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        return IndexEntry(
            id: UUID(), title: title, startedAt: start, endedAt: start.addingTimeInterval(duration), duration: duration,
            mode: mode, app: "Zoom", engine: engine, speakerCount: speakers, costUSD: cost,
            hasSummary: summary, audioBytes: audio, excerpt: excerpt, test: test
        )
    }

    private static func sprintPlanning(wer: Double? = nil) -> TestCallTag {
        TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning", wer: wer)
    }

    /// The store as the list sees it: index entries plus whatever loads.
    private final class StubLibrary: MeetingLibrary, @unchecked Sendable {
        private let lock = NSLock()
        private var _entries: [IndexEntry]
        private var _meetings: [UUID: LoadedMeeting] = [:]
        private var _indexMissing = false
        private var _refreshes = 0
        private var _loads = 0
        private var _deleted: [UUID] = []
        private var _audioDeleted: [UUID] = []
        private var _retitled: [String] = []

        init(_ entries: [IndexEntry] = [], meetings: [LoadedMeeting] = []) {
            _entries = entries
            for meeting in meetings { _meetings[meeting.meeting.id] = meeting }
        }

        private func locked<T>(_ body: () throws -> T) rethrows -> T {
            lock.lock()
            defer { lock.unlock() }
            return try body()
        }

        var indexMissing: Bool {
            get { locked { _indexMissing } }
            set { locked { _indexMissing = newValue } }
        }

        var refreshes: Int { locked { _refreshes } }
        var loads: Int { locked { _loads } }
        var deleted: [UUID] { locked { _deleted } }
        var audioDeleted: [UUID] { locked { _audioDeleted } }
        var retitled: [String] { locked { _retitled } }

        var isIndexMissing: Bool { indexMissing }

        func index() throws -> [IndexEntry] { locked { _entries } }

        func load(_ id: UUID) throws -> LoadedMeeting {
            try locked {
                _loads += 1
                guard let meeting = _meetings[id] else { throw CocoaError(.fileNoSuchFile) }
                return meeting
            }
        }

        func refreshIndex() async throws -> [IndexEntry] {
            locked {
                _refreshes += 1
                _indexMissing = false
                return _entries
            }
        }

        func delete(_ id: UUID) async throws {
            locked {
                _deleted.append(id)
                _entries.removeAll { $0.id == id }
            }
        }

        func deleteAudio(_ id: UUID) async throws {
            locked {
                _audioDeleted.append(id)
                if let index = _entries.firstIndex(where: { $0.id == id }) { _entries[index].audioBytes = 0 }
            }
        }

        func retitle(_ id: UUID, to title: String) async throws {
            locked {
                _retitled.append(title)
                if let index = _entries.firstIndex(where: { $0.id == id }) { _entries[index].title = title }
            }
        }
    }

    /// Sleeps until `wake()`, reporting each sleep's duration.
    private final class ManualClock: MWSupport.Clock, @unchecked Sendable {
        let sleeps: AsyncStream<Duration>
        private let sleep: AsyncStream<Duration>.Continuation
        private let lock = NSLock()
        private var sleepers: [CheckedContinuation<Void, Never>] = []

        init() {
            (sleeps, sleep) = AsyncStream.makeStream()
        }

        var now: TimeInterval { 0 }

        func sleep(for duration: Duration) async throws {
            await withCheckedContinuation { continuation in
                lock.lock()
                sleepers.append(continuation)
                lock.unlock()
                sleep.yield(duration)
            }
        }

        func wake() {
            lock.lock()
            let woken = sleepers
            sleepers = []
            lock.unlock()
            woken.forEach { $0.resume() }
        }
    }

    @MainActor
    private final class Harness {
        let library: StubLibrary
        let clock = ManualClock()
        var openMeetings: Set<UUID> = []
        var opened: [UUID] = []
        var exports: [(kind: MeetingExporter.Kind, id: UUID)] = []
        var openRetitles: [String] = []
        var startedMeetings = 0
        var finderShows = 0
        lazy var model = MeetingsListModel(deps: MeetingsListModel.Dependencies(
            library: library,
            clock: clock,
            now: { MeetingsListModelTests.now },
            calendar: MeetingsListModelTests.calendar,
            hotkey: { "⌃⌥⌘M" },
            isOpen: { [unowned self] in openMeetings.contains($0) },
            retitleOpen: { [unowned self] id, title in
                guard openMeetings.contains(id) else { return false }
                openRetitles.append(title)
                return true
            },
            open: { [unowned self] in opened.append($0) },
            export: { [unowned self] kind, id in exports.append((kind, id)) },
            startMeeting: { [unowned self] in startedMeetings += 1 },
            showInFinder: { [unowned self] in finderShows += 1 }
        ))

        init(_ library: StubLibrary) {
            self.library = library
        }

        func loaded() async -> MeetingsListModel {
            await model.reload()
            return model
        }
    }

    private func rows(_ model: MeetingsListModel) -> [MeetingsListModel.Row] {
        model.days.flatMap(\.rows)
    }

    @Test func rowsGroupByDayNewestFirst() async {
        let harness = Harness(StubLibrary([
            Self.entry("Q4 planning", hoursAgo: 6 * 24),
            Self.entry("Northwind rollout sync", hoursAgo: 0.5),
            Self.entry("Design review", hoursAgo: 23),
            Self.entry("Standup", hoursAgo: 4),
        ]))
        let model = await harness.loaded()

        #expect(model.days.map(\.title) == ["Today", "Yesterday", "Tuesday 3 Nov"])
        #expect(model.days.map { $0.rows.map(\.title) } == [
            ["Northwind rollout sync", "Standup"], ["Design review"], ["Q4 planning"],
        ])
    }

    @Test func rowShowsSummaryExcerptOrItalicFirstLine() async {
        let harness = Harness(StubLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 1),
            Self.entry("Standup", hoursAgo: 2, summary: false, excerpt: "Morning everyone, let's start."),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.excerpt) == ["The rollout stays on schedule.", "Morning everyone, let's start."])
        #expect(rows.map(\.excerptIsTranscript) == [false, true])
        #expect(rows.map(\.mode) == [.remote, .remote])
    }

    @Test func metaLineShowsDurationSpeakersCostAndAudioSize() async {
        let harness = Harness(StubLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 0.5),
            Self.entry("Standup", hoursAgo: 4, duration: 1620, speakers: 2, cost: 0.2, summary: false, audio: 13_000_000),
            Self.entry("Design review", hoursAgo: 23, duration: 4320, mode: .inRoom, speakers: 1, cost: 0.57),
            Self.entry("Q4 planning", hoursAgo: 30, duration: 7440, cost: 0.96, audio: 1_400_000_000),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.meta) == [
            "14:30 · 48 min · Remote call · 3 speakers · $0.40 · Audio 23 MB",
            "11:00 · 27 min · Remote call · 2 speakers · $0.20 · No summary · Audio 13 MB",
            "16:00 · 1 h 12 min · In the room · 1 speaker · $0.57 · Audio 23 MB",
            "09:00 · 2 h 04 min · Remote call · 3 speakers · $0.96 · Audio 1.4 GB",
        ])
    }

    @Test func deletedAudioReadsAudioDeleted() async {
        let harness = Harness(StubLibrary([Self.entry("Hiring loop debrief", hoursAgo: 1, cost: 0.29, audio: 0)]))
        let rows = rows(await harness.loaded())

        #expect(rows.first?.meta == "14:00 · 48 min · Remote call · 3 speakers · $0.29 · Audio deleted")
    }

    @Test func testRowShowsTheChipAndTheWERMeta() async {
        let harness = Harness(StubLibrary([
            Self.entry(
                "Test call · Sprint planning", hoursAgo: 226 / 60, duration: 125, cost: 0.0215, summary: false,
                audio: 2_000_000, engine: .assemblyaiStreaming, test: Self.sprintPlanning(wer: 0.064)
            ),
            Self.entry("Sprint 14 planning", hoursAgo: 5),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.meta) == [
            "11:14 · 2 min · Remote call · WER 6.4% · AssemblyAI Universal-Streaming · $0.02",
            "10:00 · 48 min · Remote call · 3 speakers · $0.40 · Audio 23 MB",
        ])
        #expect(rows.map(\.isTest) == [true, false])
    }

    @Test func unscoredTestRowOmitsWER() async {
        let harness = Harness(StubLibrary([
            Self.entry(
                "Test call · Sprint planning", hoursAgo: 226 / 60, duration: 125, cost: 0.0215,
                engine: .assemblyaiStreaming, test: Self.sprintPlanning()
            ),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.first?.meta == "11:14 · 2 min · Remote call · AssemblyAI Universal-Streaming · $0.02")
        #expect(rows.first?.isTest == true)
    }

    @Test func footerCountsMeetingsAndAudio() async {
        let harness = Harness(StubLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 1),
            Self.entry("Standup", hoursAgo: 2, audio: 13_000_000),
            Self.entry("Retro", hoursAgo: 3, audio: 0),
        ]))
        #expect(await harness.loaded().footer == "3 meetings · 36 MB audio")

        let single = Harness(StubLibrary([Self.entry("Standup", hoursAgo: 2, audio: 0)]))
        #expect(await single.loaded().footer == "1 meeting")
    }

    @Test func searchWaits150MillisecondsBeforeRunning() async {
        let northwind = Self.loaded("Northwind rollout sync", note: "Ask ops for a Wednesday maintenance window")
        let harness = Harness(StubLibrary([Self.entry(from: northwind)], meetings: [northwind]))
        let model = await harness.loaded()
        var sleeps = harness.clock.sleeps.makeAsyncIterator()

        model.query = "main"
        model.query = "maintenance"
        #expect(await sleeps.next() == .milliseconds(150))
        #expect(await sleeps.next() == .milliseconds(150))
        #expect(harness.library.loads == 0)
        #expect(rows(model).first?.snippets == [])

        harness.clock.wake()
        await model.search?.value

        #expect(harness.library.loads == 1)
        #expect(rows(model).first?.snippets.map(\.label) == ["Note · 00:40:05"])
    }

    @Test func searchShowsUpToTwoLabelledSnippets() async {
        let northwind = Self.loaded(
            "Northwind rollout sync",
            note: "Ask ops for a Wednesday maintenance window",
            summary: "## Action items\n- **Alex**: ask ops for a Wednesday maintenance window."
        )
        let planning = Self.loaded(
            "Q4 planning", startedHoursAgo: 6 * 24,
            segment: (speaker: 3, start: 4368, text: "We cannot move the database without a maintenance window."),
            summary: "## Summary\nThree themes, and a maintenance window for the database move."
        )
        let standup = Self.loaded("Standup", startedHoursAgo: 2, note: "Nothing to see")
        let harness = Harness(StubLibrary(
            [northwind, standup, planning].map(Self.entry(from:)), meetings: [northwind, standup, planning]
        ))
        let model = await harness.loaded()
        var sleeps = harness.clock.sleeps.makeAsyncIterator()

        model.query = "maintenance window"
        _ = await sleeps.next()
        harness.clock.wake()
        await model.search?.value

        #expect(rows(model).map(\.title) == ["Northwind rollout sync", "Q4 planning"])
        #expect(rows(model).map { $0.snippets.map(\.label) } == [["Note · 00:40:05", "Summary"], ["Speaker 3 · 01:12:48", "Summary"]])
        #expect(rows(model)[0].snippets[0].text == "Ask ops for a Wednesday maintenance window")
        #expect(model.footer == "2 of 3 meetings match")

        model.query = ""
        #expect(rows(model).count == 3)
        #expect(model.footer.hasPrefix("3 meetings"))
    }

    @Test func searchStillFindsTestMeetings() async {
        let testCall = Self.loaded(
            "Test call · Sprint planning", note: "Sprint scope agreed", test: Self.sprintPlanning(wer: 0.064)
        )
        let standup = Self.loaded("Standup", startedHoursAgo: 2, note: "Nothing to see")
        let harness = Harness(StubLibrary([testCall, standup].map(Self.entry(from:)), meetings: [testCall, standup]))
        let model = await harness.loaded()
        var sleeps = harness.clock.sleeps.makeAsyncIterator()

        model.query = "sprint"
        _ = await sleeps.next()
        harness.clock.wake()
        await model.search?.value

        #expect(rows(model).map(\.title) == ["Test call · Sprint planning"])
        #expect(rows(model).map(\.isTest) == [true])
        #expect(rows(model).first?.snippets.map(\.label) == ["Note · 00:40:05"])
    }

    @Test func emptyStateNamesTheHotkey() async {
        let model = await Harness(StubLibrary()).loaded()

        #expect(model.days.isEmpty)
        #expect(model.emptyState == "Press ⌃⌥⌘M or choose Start Meeting… from the menu bar. Mini Whisper transcribes"
            + " live with speaker labels, keeps your notes beside the transcript and writes a summary when you stop.")
        #expect(model.footer == "0 meetings")

        let some = await Harness(StubLibrary([Self.entry("Standup", hoursAgo: 1)])).loaded()
        #expect(some.emptyState == nil)
    }

    @Test func footerActionsStartAMeetingAndShowTheFolder() async {
        let harness = Harness(StubLibrary())
        let model = await harness.loaded()

        model.startMeeting()
        model.showInFinder()

        #expect(harness.startedMeetings == 1)
        #expect(harness.finderShows == 1)
    }

    @Test func exportMenuOffersDeleteAudioWithItsSize() async throws {
        let harness = Harness(StubLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 1),
            Self.entry("Retro", hoursAgo: 2, audio: 0),
        ]))
        let rows = rows(await harness.loaded())

        #expect(harness.model.exportItems(for: rows[0]).map(\.title) == [
            "Export transcript…", "Export summary…", "Export both…", "Delete audio (23 MB)",
        ])
        #expect(harness.model.exportItems(for: rows[1]).map(\.title) == [
            "Export transcript…", "Export summary…", "Export both…",
        ])

        harness.model.perform(try #require(harness.model.exportItems(for: rows[0]).first), on: rows[0])
        #expect(harness.exports.map(\.kind) == [.transcript])
        #expect(harness.exports.map(\.id) == [rows[0].id])

        harness.model.perform(try #require(harness.model.exportItems(for: rows[0]).last), on: rows[0])
        #expect(harness.model.pendingDeletion?.prompt == "Delete the audio of “Northwind rollout sync”?")
        await harness.model.confirmDeletion()
        #expect(harness.library.audioDeleted == [rows[0].id])
        #expect(self.rows(harness.model).first?.meta.hasSuffix("Audio deleted") == true)
    }

    @Test func deleteAsksForConfirmationThenRemovesTheRow() async {
        let harness = Harness(StubLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 1),
            Self.entry("Standup", hoursAgo: 2),
        ]))
        let model = await harness.loaded()
        let standup = rows(model)[1]

        model.requestDelete(standup)
        #expect(model.pendingDeletion?.prompt == "Delete “Standup”?")
        #expect(harness.library.deleted.isEmpty)
        model.cancelDeletion()
        #expect(model.pendingDeletion == nil)

        model.requestDelete(standup)
        await model.confirmDeletion()
        #expect(harness.library.deleted == [standup.id])
        #expect(rows(model).map(\.title) == ["Northwind rollout sync"])
        #expect(model.pendingDeletion == nil)

        // A meeting with its window open stays.
        let northwind = rows(model)[0]
        harness.openMeetings = [northwind.id]
        #expect(model.canDelete(northwind) == false)
        model.requestDelete(northwind)
        #expect(model.pendingDeletion == nil)
    }

    @Test func renameUpdatesTheRowAndTheStore() async {
        let harness = Harness(StubLibrary([
            Self.entry("Zoom · 9 Nov 2026 14:30", hoursAgo: 1),
            Self.entry("Standup", hoursAgo: 2),
        ]))
        let model = await harness.loaded()
        let first = rows(model)[0]

        await model.rename(first, to: "  Northwind rollout sync ")
        #expect(harness.library.retitled == ["Northwind rollout sync"])
        #expect(rows(model).map(\.title) == ["Northwind rollout sync", "Standup"])

        await model.rename(first, to: "   ")
        #expect(harness.library.retitled == ["Northwind rollout sync"])

        // An open meeting renames through its window, which writes the store.
        let standup = rows(model)[1]
        harness.openMeetings = [standup.id]
        await model.rename(standup, to: "Daily standup")
        #expect(harness.openRetitles == ["Daily standup"])
        #expect(harness.library.retitled == ["Northwind rollout sync"])
    }

    @Test func missingIndexTriggersRefreshIndex() async {
        let library = StubLibrary([Self.entry("Standup", hoursAgo: 1)])
        library.indexMissing = true
        let harness = Harness(library)

        let model = await harness.loaded()
        #expect(library.refreshes == 1)
        #expect(rows(model).map(\.title) == ["Standup"])

        await model.reload()
        #expect(library.refreshes == 1)
    }

    @Test func openOpensTheMeeting() async {
        let harness = Harness(StubLibrary([Self.entry("Standup", hoursAgo: 1)]))
        let model = await harness.loaded()

        await model.open(rows(model)[0])

        #expect(harness.opened == [rows(model)[0].id])
    }

    // MARK: - Fixtures

    private static func loaded(
        _ title: String,
        startedHoursAgo: Double = 0.5,
        segment: (speaker: Int, start: Double, text: String)? = nil,
        note: String? = nil,
        summary: String? = nil,
        test: TestCallTag? = nil
    ) -> LoadedMeeting {
        let start = now.addingTimeInterval(-startedHoursAgo * 3600)
        let meeting = Meeting(
            title: title, startedAt: start, endedAt: start.addingTimeInterval(2932), durationSeconds: 2932,
            mode: .remote, engine: .speechmaticsStandard, userName: "Alex",
            speakers: [SpeakerLabel(id: 0, name: "Alex", isUser: true), SpeakerLabel(id: 3, name: "Speaker 3")],
            summary: summary.map {
                Summary(text: $0, model: "claude-sonnet-5-5", createdAt: start, inputTokens: 1, outputTokens: 1, costUSD: 0)
            },
            test: test
        )
        return LoadedMeeting(
            meeting: meeting,
            segments: segment.map { [Segment(speaker: $0.speaker, start: $0.start, end: $0.start + 3, text: $0.text, session: 1)] } ?? [],
            notes: note.map { [Note(time: 2405, text: $0, createdAt: start)] } ?? []
        )
    }

    private static func entry(from loaded: LoadedMeeting) -> IndexEntry {
        let m = loaded.meeting
        return IndexEntry(
            id: m.id, title: m.title, startedAt: m.startedAt, endedAt: m.endedAt, duration: m.durationSeconds,
            mode: m.mode, app: nil, engine: m.engine, speakerCount: m.speakers.count, costUSD: 0.1,
            hasSummary: m.summary != nil, audioBytes: 0, excerpt: "Excerpt.", test: m.test
        )
    }
}

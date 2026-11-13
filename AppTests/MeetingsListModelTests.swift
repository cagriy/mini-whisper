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

    @MainActor
    private final class Harness {
        let library: StubMeetingLibrary
        var openMeetings: Set<UUID> = []
        var opened: [UUID] = []
        var exports: [(kind: MeetingExporter.Kind, id: UUID)] = []
        var openRetitles: [String] = []
        var startedMeetings = 0
        var finderShows = 0
        lazy var model = MeetingsListModel(deps: MeetingsListModel.Dependencies(
            library: library,
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

        init(_ library: StubMeetingLibrary) {
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
        let harness = Harness(StubMeetingLibrary([
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

    @Test func rowSubLineIsTheTopicsOrTheFirstSentence() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry("Weekly platform sync", hoursAgo: 1, excerpt: "Catalog entries · Additions requested"),
            Self.entry("Quarterly planning", hoursAgo: 2, excerpt: "The team agreed to move the launch to March."),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.subLine) == [
            "Catalog entries · Additions requested", "The team agreed to move the launch to March.",
        ])
        #expect(rows.map(\.subLineIsTranscript) == [false, false])
        #expect(rows.map(\.mode) == [.remote, .remote])
    }

    @Test func rowSubLineQuotesTheFirstTranscriptLineWhenThereIsNoSummary() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry("Standup", hoursAgo: 2, summary: false, excerpt: "Morning everyone, let's start."),
            Self.entry("Silent", hoursAgo: 3, summary: false, excerpt: ""),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.subLine) == ["\u{201C}Morning everyone, let's start.\u{201D}", ""])
        #expect(rows.map(\.subLineIsTranscript) == [true, true])
    }

    @Test func metaReadsDurationModeSpeakersCost() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 0.5),
            Self.entry("Design review", hoursAgo: 23, duration: 4320, mode: .inRoom, speakers: 1, cost: 0.57),
            Self.entry("Q4 planning", hoursAgo: 30, duration: 7440, cost: 0.96, audio: 1_400_000_000),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.meta) == [
            "48 min · Remote call · 3 speakers · $0.40",
            "1 h 12 min · In the room · 1 speaker · $0.57",
            "2 h 04 min · Remote call · 3 speakers · $0.96",
        ])
    }

    @Test func metaMarksNoSummary() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry("Standup", hoursAgo: 4, duration: 1620, speakers: 2, cost: 0.2, summary: false),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.first?.meta == "27 min · Remote call · 2 speakers · $0.20 · No summary")
    }

    @Test func testCallMetaReadsDurationWerEngineCost() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry(
                "Test call · Sprint planning", hoursAgo: 226 / 60, duration: 125, cost: 0.0215, summary: false,
                audio: 2_000_000, engine: .assemblyaiStreaming, test: Self.sprintPlanning(wer: 0.064)
            ),
            Self.entry(
                "Test call · Budget review", hoursAgo: 5, duration: 125, cost: 0.0215,
                engine: .assemblyaiStreaming, test: Self.sprintPlanning()
            ),
            Self.entry("Sprint 14 planning", hoursAgo: 6),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.meta) == [
            "2 min · WER 6.4% · AssemblyAI Universal-Streaming · $0.02",
            "2 min · AssemblyAI Universal-Streaming · $0.02",
            "48 min · Remote call · 3 speakers · $0.40",
        ])
        #expect(rows.map(\.isTest) == [true, true, false])
    }

    @Test func startTimeSitsApartFromTheMeta() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 0.5),
            Self.entry("Standup", hoursAgo: 4),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.map(\.time) == ["14:30", "11:00"])
        #expect(rows.allSatisfy { !$0.meta.contains($0.time) })
    }

    @Test func audioSizeStaysInTheExportMenuOnly() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 1),
            Self.entry("Retro", hoursAgo: 2, audio: 0),
        ]))
        let rows = rows(await harness.loaded())

        #expect(rows.allSatisfy { !$0.meta.contains("Audio") && !$0.meta.contains("MB") })
        #expect(harness.model.exportItems(for: rows[0]).last?.title == "Delete audio (23 MB)")
        #expect(harness.model.exportItems(for: rows[1]).contains { $0.action == .deleteAudio } == false)
    }

    @Test func deleteIsBlockedWithHelpWhileOpen() async {
        let harness = Harness(StubMeetingLibrary([Self.entry("Northwind rollout sync", hoursAgo: 1)]))
        let model = await harness.loaded()
        let row = rows(model)[0]

        #expect(model.canDelete(row))
        #expect(model.deleteHelp(row) == nil)

        harness.openMeetings = [row.id]
        #expect(model.canDelete(row) == false)
        #expect(model.deleteHelp(row) == "This meeting is recording, on screen, or its summary is being written")
        model.requestDelete(row)
        #expect(model.pendingDeletion == nil)
    }

    @Test func footerCountsMeetingsAndAudio() async {
        let harness = Harness(StubMeetingLibrary([
            Self.entry("Northwind rollout sync", hoursAgo: 1),
            Self.entry("Standup", hoursAgo: 2, audio: 13_000_000),
            Self.entry("Retro", hoursAgo: 3, audio: 0),
        ]))
        #expect(await harness.loaded().footer == "3 meetings · 36 MB audio")

        let single = Harness(StubMeetingLibrary([Self.entry("Standup", hoursAgo: 2, audio: 0)]))
        #expect(await single.loaded().footer == "1 meeting")
    }

    @Test func emptyStateNamesTheHotkey() async {
        let model = await Harness(StubMeetingLibrary()).loaded()

        #expect(model.days.isEmpty)
        #expect(model.emptyState == "Press ⌃⌥⌘M or choose Start Meeting… from the menu bar. Mini Whisper transcribes"
            + " live with speaker labels, keeps your notes beside the transcript and writes a summary when you stop.")
        #expect(model.footer == "0 meetings")

        let some = await Harness(StubMeetingLibrary([Self.entry("Standup", hoursAgo: 1)])).loaded()
        #expect(some.emptyState == nil)
    }

    @Test func footerActionsStartAMeetingAndShowTheFolder() async {
        let harness = Harness(StubMeetingLibrary())
        let model = await harness.loaded()

        model.startMeeting()
        model.showInFinder()

        #expect(harness.startedMeetings == 1)
        #expect(harness.finderShows == 1)
    }

    @Test func exportMenuOffersDeleteAudioWithItsSize() async throws {
        let harness = Harness(StubMeetingLibrary([
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
        let reloaded = try #require(self.rows(harness.model).first)
        #expect(harness.model.exportItems(for: reloaded).contains { $0.action == .deleteAudio } == false)
    }

    @Test func deleteAsksForConfirmationThenRemovesTheRow() async {
        let harness = Harness(StubMeetingLibrary([
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
        let harness = Harness(StubMeetingLibrary([
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
        let library = StubMeetingLibrary([Self.entry("Standup", hoursAgo: 1)])
        library.indexMissing = true
        let harness = Harness(library)

        let model = await harness.loaded()
        #expect(library.refreshes == 1)
        #expect(rows(model).map(\.title) == ["Standup"])

        await model.reload()
        #expect(library.refreshes == 1)
    }

    @Test func openOpensTheMeeting() async {
        let harness = Harness(StubMeetingLibrary([Self.entry("Standup", hoursAgo: 1)]))
        let model = await harness.loaded()

        await model.open(rows(model)[0])

        #expect(harness.opened == [rows(model)[0].id])
    }
}

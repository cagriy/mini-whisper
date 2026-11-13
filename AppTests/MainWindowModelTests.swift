import Foundation
import MWConfig
import MWHistory
import MWMeetings
import MWPaste
import MWPipeline
import MWUsage
import Testing
@testable import MiniWhisper

/// The wiring between the sidebar, its pages and the search (design §5.7, §5.11, §5.12).
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MainWindowModelTests {
    /// Monday 9 November 2026, 15:00 UTC.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_794_236_400)

    private struct NoPaster: Pasting {
        func paste(_ text: String, into pid: pid_t, submit: SubmitKey?) async throws {}
    }

    private struct NoPasteboard: PasteboardAccess {
        func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: []) }
        func write(_ text: String) -> Int { 0 }
        var changeCount: Int { 0 }
        func restore(_ snapshot: PasteboardSnapshot) {}
    }

    private struct OpenFailed: LocalizedError {
        var errorDescription: String? { "meeting.json is unreadable" }
    }

    @MainActor
    private final class Harness {
        let directory: URL
        let history: HistoryStore
        let library: StubMeetingLibrary
        var opened: [UUID] = []
        var openFails = false
        var settingsOpened = 0
        lazy var model: MainWindowModel = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let now = MainWindowModelTests.now
            let meetings = MeetingsListModel(deps: MeetingsListModel.Dependencies(
                library: library,
                now: { now },
                calendar: calendar,
                hotkey: { "⌃⌥⌘M" },
                isOpen: { _ in false },
                retitleOpen: { _, _ in false },
                open: { _ in },
                export: { _, _ in },
                startMeeting: {},
                showInFinder: {}
            ))
            let dictations = HistoryListModel(deps: HistoryListModel.Dependencies(
                history: history,
                paster: NoPaster(),
                pasteboard: NoPasteboard(),
                isRunning: { _ in false },
                retentionDays: { 7 },
                clock: ManualClock(),
                now: { now },
                previousApp: { nil },
                hide: {},
                activate: { _ in },
                correct: { _ in },
                changed: {}
            ))
            let search = SearchModel(deps: SearchModel.Dependencies(
                library: library, history: history, clock: ManualClock(), now: { now }, calendar: calendar
            ))
            return MainWindowModel(
                meetings: meetings,
                dictations: dictations,
                search: search,
                deps: MainWindowModel.Dependencies(
                    openMeeting: { [unowned self] id in
                        if openFails { throw OpenFailed() }
                        opened.append(id)
                    },
                    openSettings: { [unowned self] in settingsOpened += 1 }
                )
            )
        }()

        init(_ library: StubMeetingLibrary = StubMeetingLibrary()) {
            self.library = library
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-main-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let now = MainWindowModelTests.now
            history = HistoryStore(
                url: directory.appendingPathComponent("history.jsonl"), retention: { 7 }, now: { now }
            )
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    private static func entry(_ title: String) -> IndexEntry {
        IndexEntry(
            id: UUID(), title: title, startedAt: now.addingTimeInterval(-3600), endedAt: now, duration: 3600,
            mode: .remote, app: nil, engine: .speechmaticsStandard, speakerCount: 2, costUSD: 0.4,
            hasSummary: true, audioBytes: 0, excerpt: "Catalog entries"
        )
    }

    @Test func typingAQueryShowsResultsAndSearches() {
        let harness = Harness()
        defer { harness.cleanUp() }

        harness.model.query = "catalog"

        #expect(harness.model.navigation.destination == .search)
        #expect(harness.model.navigation.query == "catalog")
        #expect(harness.model.search.query == "catalog")
    }

    @Test func leavingResultsEmptiesTheSearch() {
        let harness = Harness()
        defer { harness.cleanUp() }

        harness.model.query = "catalog"
        harness.model.navigation.go(.dictations)

        #expect(harness.model.query == "")
        #expect(harness.model.search.query == "")
    }

    @Test func clearingTheQueryReturnsToThePageBefore() {
        let harness = Harness()
        defer { harness.cleanUp() }

        harness.model.navigation.go(.dictations)
        harness.model.query = "catalog"
        #expect(harness.model.navigation.destination == .search)
        harness.model.query = ""

        #expect(harness.model.navigation.destination == .dictations)
        #expect(harness.model.search.query == "")
    }

    @Test func enteringAPageReloadsIt() async throws {
        let harness = Harness(StubMeetingLibrary([Self.entry("Weekly platform sync")]))
        defer { harness.cleanUp() }
        try await harness.history.append(HistoryEntry(timestamp: Self.now, text: "Move the review", appName: "Mail"))

        harness.model.navigation.go(.meetings)
        await harness.model.loading?.value
        #expect(harness.model.meetings.days.flatMap(\.rows).map(\.title) == ["Weekly platform sync"])

        harness.model.navigation.go(.dictations)
        await harness.model.loading?.value
        #expect(harness.model.dictations.days.flatMap(\.rows).map(\.text) == ["Move the review"])
    }

    @Test func aDictationResultOpensDictationsWithItsRowSelected() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let dictation = HistoryEntry(timestamp: Self.now, text: "Thanks for the catalog notes", appName: "Mail")
        try await harness.history.append(dictation)

        harness.model.query = "catalog"
        harness.model.navigation.revealDictation(dictation.id)
        await harness.model.loading?.value

        #expect(harness.model.navigation.destination == .dictations)
        #expect(harness.model.dictations.selection == dictation.id)
        #expect(harness.model.search.query == "")
    }

    @Test func aMeetingResultOpensTheMeeting() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let id = UUID()

        harness.model.query = "catalog"
        await harness.model.openMeeting(id)

        #expect(harness.opened == [id])
        #expect(harness.model.openError == nil)
    }

    @Test func aMeetingThatFailsToOpenShowsTheReasonAndTheResultsStay() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.openFails = true

        harness.model.query = "catalog"
        await harness.model.openMeeting(UUID())

        #expect(harness.model.openError == "meeting.json is unreadable")
        #expect(harness.model.navigation.destination == .search)

        harness.model.query = "catalogue"
        #expect(harness.model.openError == nil)
    }

    @Test func usageTableFollowsTheTotals() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let totals = UsageTotals(
            today: DayUsage(inputTokens: 1234, outputTokens: 340, streamedSeconds: ["on_device": 200], costUSD: 0.12),
            month: DayUsage(inputTokens: 48_600, outputTokens: 9100, streamedSeconds: ["speechmatics": 8040], costUSD: 1.5)
        )

        #expect(harness.model.usageTable == Pricing.usageTable(UsageTotals()))
        harness.model.usage = totals

        #expect(harness.model.usageTable == Pricing.usageTable(totals))
        #expect(harness.model.usageTable.month.audio == "2h 14m")
    }

    @Test func settingsOpensItsWindowForNow() {
        let harness = Harness()
        defer { harness.cleanUp() }

        harness.model.openSettings()

        #expect(harness.settingsOpened == 1)
    }
}

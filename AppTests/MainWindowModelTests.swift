import Foundation
import MWConfig
import MWHistory
import MWMeetings
import MWPaste
import MWPipeline
import MWStreaming
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
        let secrets = FakeSecrets()
        let hotkeys = FakeHotkeys()
        var opened: [UUID] = []
        var openFails = false
        var pagesLeft = 0
        var liveShown = 0
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
            let settings = SettingsModel(config: Config(), deps: SettingsModel.Dependencies(
                store: ConfigStore(directory: directory),
                secrets: secrets,
                hotkeys: hotkeys,
                sounds: FakeSounds(),
                updates: FakeUpdater(),
                platform: PlatformInfo(osMajor: 14, locale: Locale(identifier: "en_US")),
                assetStatus: { .unavailable },
                installAssets: {},
                prompts: PromptFiles(
                    directory: directory,
                    bundledCleanup: directory.appendingPathComponent("default_prompt.txt"),
                    bundledTranscribe: directory.appendingPathComponent("default_transcribe_prompt.txt"),
                    bundledSummary: directory.appendingPathComponent("default_summary_prompt.txt")
                ),
                apps: StubApps(),
                pruneHistory: { _ in },
                clearHistory: {},
                openCorrection: { _ in }
            ))
            return MainWindowModel(
                meetings: meetings,
                dictations: dictations,
                search: search,
                settings: settings,
                deps: MainWindowModel.Dependencies(
                    openMeeting: { [unowned self] id in
                        if openFails { throw OpenFailed() }
                        opened.append(id)
                    },
                    showLiveMeeting: { [unowned self] in liveShown += 1 },
                    meetingPageLeft: { [unowned self] in pagesLeft += 1 }
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

    @Test func enteringSettingsRereadsTheKeys() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let settings = harness.model.settings
        harness.secrets.stored[.openai] = "sk-test-5678"
        #expect(settings.mask(for: .openai).isEmpty)

        harness.model.navigation.go(.settings)

        #expect(harness.model.navigation.destination == .settings)
        #expect(settings.mask(for: .openai) == "sk-…5678")
    }

    @Test func leavingSettingsCancelsHotkeyCapture() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let settings = harness.model.settings
        let previous = settings.display(.paste)
        harness.model.navigation.go(.settings)
        settings.selection = .hotkeys
        settings.beginCapture(.paste)

        harness.model.navigation.go(.meetings)

        #expect(harness.hotkeys.cancelled == 1)
        #expect(settings.capturing == nil)
        #expect(settings.display(.paste) == previous)
    }

    private static func meeting() -> MeetingWindowModel {
        MeetingWindowModel(chooser: MeetingWindowModel.Chooser(
            config: Config(), platform: PlatformInfo(osMajor: 26, osMinor: 0), accountName: "Alex", hasKey: { _ in true }
        ))
    }

    private static var noActions: MeetingActions {
        MeetingActions(
            start: {}, startTestCall: { _ in }, cancel: {}, pauseOrResume: {}, stop: {}, skipLine: {},
            rename: { _, _ in }, addNote: { _ in }, summarise: {}, edit: { _, _ in }, reassign: { _, _ in },
            retitle: { _ in }, export: { _ in }, openSettings: {}, back: {}, copySummary: {}, regenerate: {}
        )
    }

    @Test func showMeetingPresentsTheSessionAndLeavingThePageClearsIt() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let meeting = Self.meeting()
        harness.model.navigation.go(.dictations)

        harness.model.showMeeting(meeting, actions: Self.noActions)

        #expect(harness.model.navigation.destination == .meeting)
        #expect(harness.model.navigation.origin == .dictations)
        #expect(harness.model.presented?.model === meeting)

        harness.model.navigation.back()

        #expect(harness.model.navigation.destination == .dictations)
        #expect(harness.model.presented == nil)
        #expect(harness.pagesLeft == 1)
    }

    @Test func presentingAnotherSessionOnTheMeetingPageDoesNotLeaveIt() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let next = Self.meeting()
        harness.model.showMeeting(Self.meeting(), actions: Self.noActions)

        harness.model.showMeeting(next, actions: Self.noActions)

        #expect(harness.model.presented?.model === next)
        #expect(harness.model.navigation.origin == .meetings)
        #expect(harness.pagesLeft == 0)
    }

    @Test func recordingPillShowsTheLiveMeeting() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let live = Self.meeting()

        harness.model.liveMeeting = live
        harness.model.showLiveMeeting()

        #expect(harness.model.liveMeeting === live)
        #expect(harness.liveShown == 1)
    }
}

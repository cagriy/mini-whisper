import CoreGraphics
import Foundation
import MWStats
import Testing
@testable import MiniWhisper

/// Timeline's states, replay and return, and its records (design §5 Control flow, R17, R19, R21).
@MainActor
@Suite(.timeLimit(.minutes(1))) struct TimelineModelTests {
    /// Wednesday 25 November 2026, 12:00 UTC.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_795_608_000)

    private struct OpenFailed: LocalizedError {
        var errorDescription: String? { "meeting.json is unreadable" }
    }

    @MainActor
    private final class Harness {
        /// What each report call returns, in turn; the last repeats.
        var contents: [TimelineContent]
        var reports = 0
        var reconciled = false
        var reconciles = 0
        /// The page as the reconcile found it.
        var duringReconcile: (content: TimelineContent?, playID: Int)?
        var opened: [UUID] = []
        var openFails = false
        var settingsOpened = 0
        let progress: AsyncStream<ReconcileProgress?>.Continuation

        lazy var model: TimelineModel = TimelineModel(deps: TimelineModel.Dependencies(
            report: { @MainActor [unowned self] in
                defer { reports += 1 }
                return contents[min(reports, contents.count - 1)]
            },
            reconcile: { @MainActor [unowned self] in
                reconciles += 1
                duringReconcile = (model.content, model.playID)
                return reconciled
            },
            progress: stream,
            openMeeting: { [unowned self] id in
                if openFails { throw OpenFailed() }
                opened.append(id)
            },
            openSettings: { [unowned self] in settingsOpened += 1 }
        ))

        private let stream: AsyncStream<ReconcileProgress?>

        init(_ contents: TimelineContent...) {
            self.contents = contents.isEmpty ? [TimelineModelTests.content()] : contents
            (stream, progress) = AsyncStream.makeStream()
        }
    }

    private nonisolated static func content(
        meetings: [MeetingRow] = [], days: [DayRow] = [], kept: [UUID: TimelineInputs.KeptMeeting] = [:],
        since: String? = nil
    ) -> TimelineContent {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let report = TimelineStats.compute(TimelineInputs(
            snapshot: StatsSnapshot(days: days, meetings: meetings), kept: kept, typingWPM: 40, now: now,
            calendar: calendar
        ))
        return TimelineContent(report: report, since: since)
    }

    /// One delivered dictation on each day.
    private nonisolated static func dictated(_ days: String...) -> TimelineContent {
        content(days: days.map { DayRow(day: $0, delivered: 1) })
    }

    /// The model follows the reconciler on its own task; this yields until it has.
    private func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
    }

    // MARK: - States

    @Test func nothingIsShownUntilTheFirstReport() {
        let harness = Harness()

        #expect(harness.model.state == nil)
    }

    @Test func noDataShowsTheEmptyState() async {
        let harness = Harness(Self.content())

        await harness.model.reload(replay: true)

        #expect(harness.model.state == .empty)
    }

    @Test func aReportShowsThePanels() async {
        let harness = Harness(Self.dictated("2026-11-24"))

        await harness.model.reload(replay: true)

        #expect(harness.model.state == .report)
        #expect(harness.model.report?.totals?.dictations == 1)
    }

    @Test func theRecordsStartIsShownWithTheReport() async {
        let harness = Harness(Self.content(since: "2026-11-02"))

        await harness.model.reload(replay: true)

        #expect(harness.model.content?.since == "2026-11-02")
    }

    @Test func fiveOrMoreMeetingsToReadShowTheProgress() async {
        let harness = Harness(Self.dictated("2026-11-24"))
        await harness.model.reload(replay: true)

        harness.progress.yield(ReconcileProgress(done: 1, total: 4))
        await until { harness.model.progress != nil }
        #expect(harness.model.state == .report)

        harness.progress.yield(nil)
        harness.progress.yield(ReconcileProgress(done: 2, total: 5))
        await until { harness.model.progress?.total == 5 }
        #expect(harness.model.state == .reading(done: 2, total: 5))

        harness.progress.yield(nil)
        await until { harness.model.progress == nil }
        #expect(harness.model.state == .report)
    }

    @Test func readingShowsBeforeTheFirstReport() async {
        let harness = Harness()

        harness.progress.yield(ReconcileProgress(done: 41, total: 62))
        await until { harness.model.progress != nil }

        #expect(harness.model.state == .reading(done: 41, total: 62))
    }

    // MARK: - Replay and return

    @Test func anOpeningReplaysAndStartsOverAtTheTop() async {
        let harness = Harness(Self.dictated("2024-03-02", "2026-11-24"))
        let model = harness.model
        await model.reload(replay: true)
        model.anchor = .records
        model.selectedYear = 2024
        model.yearMode = .dictation
        model.rhythmMode = .dictation

        await model.reload(replay: true)

        #expect(model.playID == 2)
        #expect(model.anchor == nil)
        #expect(model.selectedYear == nil)
        #expect(model.shownYear?.year == 2026)
        #expect(model.yearMode == .meetings)
        #expect(model.rhythmMode == .meetings)
    }

    @Test func aReturnKeepsThePlaceTheYearAndTheSwitches() async {
        let harness = Harness(Self.dictated("2024-03-02", "2026-11-24"))
        let model = harness.model
        await model.reload(replay: true)
        model.anchor = .records
        model.selectedYear = 2024
        model.yearMode = .dictation
        model.rhythmMode = .dictation

        await model.reload(replay: false)

        #expect(model.playID == 1)
        #expect(model.anchor == .records)
        #expect(model.shownYear?.year == 2024)
        #expect(model.yearMode == .dictation)
        #expect(model.rhythmMode == .dictation)
    }

    @Test func aReplayClearsThePanelsPlayed() async {
        let harness = Harness(Self.dictated("2026-11-24"))
        let model = harness.model
        let viewport = CGRect(x: 0, y: 0, width: 672, height: 600)
        await model.reload(replay: true)
        model.playback.update([.totals: CGRect(x: 0, y: 0, width: 672, height: 80)], in: viewport)

        await model.reload(replay: false)
        #expect(model.playback.play(.totals).played)

        await model.reload(replay: true)
        #expect(!model.playback.play(.totals).played)
    }

    @Test func theReportIsShownBeforeTheReconcile() async {
        let first = Self.dictated("2026-11-24")
        let harness = Harness(first)

        await harness.model.reload(replay: true)

        #expect(harness.reconciles == 1)
        #expect(harness.duringReconcile?.content == first)
        #expect(harness.duringReconcile?.playID == 1)
    }

    @Test func aReconcileThatChangedARowShowsTheNewReportWithoutReplaying() async {
        let second = Self.dictated("2026-11-23", "2026-11-24")
        let harness = Harness(Self.dictated("2026-11-24"), second)
        harness.reconciled = true

        await harness.model.reload(replay: true)

        #expect(harness.reports == 2)
        #expect(harness.model.content == second)
        #expect(harness.model.playID == 1)
    }

    @Test func aReconcileThatChangedNothingBuildsOneReport() async {
        let harness = Harness(Self.dictated("2026-11-24"))

        await harness.model.reload(replay: false)

        #expect(harness.reports == 1)
        #expect(harness.model.playID == 0)
    }

    // MARK: - The year

    @Test func theYearStepsWithinTheYearsShown() async throws {
        let harness = Harness(Self.dictated("2024-03-02", "2026-11-24"))
        let model = harness.model
        await model.reload(replay: true)

        #expect(model.canStepYear(by: 1) == false)
        #expect(model.canStepYear(by: -1))
        model.stepYear(by: -1)
        #expect(model.shownYear?.year == 2025)
        model.stepYear(by: -1)
        #expect(model.shownYear?.year == 2024)
        #expect(model.canStepYear(by: -1) == false)
        model.stepYear(by: -1)
        #expect(model.shownYear?.year == 2024)
        model.stepYear(by: 1)
        #expect(model.shownYear?.year == 2025)
    }

    // MARK: - Records and settings

    /// Three counted meetings, the longest kept as "Board review".
    private static func recorded() -> (content: TimelineContent, longest: UUID) {
        let longest = UUID()
        let meetings = [
            MeetingRow(id: longest, at: "2026-11-23T09:00:00+00:00", duration: 5_400),
            MeetingRow(id: UUID(), at: "2026-11-24T09:00:00+00:00", duration: 1_800),
            MeetingRow(id: UUID(), at: "2026-11-25T09:00:00+00:00", duration: 1_800),
        ]
        let kept = [longest: TimelineInputs.KeptMeeting(title: "Board review", start: now)]
        return (content(meetings: meetings, kept: kept), longest)
    }

    @Test func aRecordOpensItsMeeting() async throws {
        let (content, longest) = Self.recorded()
        let harness = Harness(content)
        await harness.model.reload(replay: true)
        let record = try #require(harness.model.report?.records?.longestMeeting)

        await harness.model.open(record)

        #expect(harness.opened == [longest])
        #expect(harness.reports == 1)
    }

    @Test func aRecordThatFailsToOpenIsLoggedAndTheReportRebuilt() async throws {
        let (content, longest) = Self.recorded()
        let deleted = Self.recorded().content
        let harness = Harness(content, deleted)
        harness.openFails = true
        await harness.model.reload(replay: true)
        let record = try #require(harness.model.report?.records?.longestMeeting)
        let sink = MessageSink()

        await logging(to: sink) { await harness.model.open(record) }

        #expect(harness.reports == 2)
        #expect(harness.model.content == deleted)
        #expect(harness.model.playID == 1)
        #expect(sink.messages == ["timeline: meeting \(longest.uuidString) not opened: meeting.json is unreadable"])
        #expect(!sink.messages.joined().contains("Board review"))
    }

    @Test func changeOpensTheStatisticsSettings() {
        let harness = Harness()

        harness.model.changeTypingSpeed()

        #expect(harness.settingsOpened == 1)
    }
}

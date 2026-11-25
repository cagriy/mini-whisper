import Foundation
import MWStats
import MWSupport
import Observation

/// Timeline's state (design §5 Control flow, R17, R19, R21): the report, a reconcile's progress, the
/// reader's place, year and switches, and which panels have played since the page last opened.
@MainActor
@Observable
final class TimelineModel {
    struct Dependencies {
        /// Built off the main actor.
        var report: @Sendable () async -> TimelineContent
        /// One pass, or the one under way; true when a row changed.
        var reconcile: @Sendable () async -> Bool
        /// The reconciler's progress; this model is its one reader.
        var progress: AsyncStream<ReconcileProgress?>
        /// Throws when the meeting cannot be opened, as once it is deleted.
        var openMeeting: @MainActor (UUID) async throws -> Void
        /// Settings › Statistics.
        var openSettings: @MainActor () -> Void
    }

    enum State: Equatable {
        /// No panel has anything to show.
        case empty
        /// A reconcile has `readingThreshold` or more meetings to read; the panels show what the rows
        /// already give.
        case reading(done: Int, total: Int)
        case report
    }

    /// In page order.
    enum Panel: Hashable, CaseIterable {
        case totals, year, rhythm, talkShare, spend, dictation, records, milestones
    }

    /// What the year and the rhythm show.
    enum Mode: Hashable {
        case meetings, dictation
    }

    /// Fewer meetings to read than this are read without a progress line.
    static let readingThreshold = 5

    private(set) var content: TimelineContent?
    /// The pass under way; nil between passes.
    private(set) var progress: ReconcileProgress?
    /// A new value plays the panels again: every opening but a return.
    private(set) var playID = 0
    /// The panel at the top of the scroll view; nil is the top of the page.
    var anchor: Panel?
    /// Nil shows this year.
    var selectedYear: Int?
    var yearMode = Mode.meetings
    var rhythmMode = Mode.meetings
    var playback = PanelPlayback<Panel>()

    @ObservationIgnored private let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
        Task { [weak self, progress = deps.progress] in
            for await value in progress {
                guard let self else { return }
                self.progress = value
            }
        }
    }

    var report: TimelineReport? { content?.report }

    /// Nil until the first report is built.
    var state: State? {
        if let progress, progress.total >= Self.readingThreshold {
            return .reading(done: progress.done, total: progress.total)
        }
        guard let report else { return nil }
        return Self.isEmpty(report) ? .empty : .report
    }

    /// The selected year, or this year.
    var shownYear: TimelineReport.CalendarYear? {
        guard let years = report?.year?.years else { return nil }
        return years.first { $0.year == selectedYear } ?? years.last
    }

    func canStepYear(by offset: Int) -> Bool {
        guard let shown = shownYear else { return false }
        return report?.year?.years.contains { $0.year == shown.year + offset } ?? false
    }

    func stepYear(by offset: Int) {
        guard canStepYear(by: offset), let shown = shownYear else { return }
        selectedYear = shown.year + offset
    }

    /// Shows the report, then reconciles and shows it again if a row changed. An opening that is not a
    /// return plays the panels from the top, on this year and on Meetings; the redraw after a reconcile
    /// plays nothing.
    func reload(replay: Bool) async {
        show(await deps.report(), replay: replay)
        guard await deps.reconcile() else { return }
        show(await deps.report(), replay: false)
    }

    /// A record of a deleted meeting fails to open; the rebuilt report then shows it as deleted.
    func open(_ record: TimelineReport.MeetingRecord) async {
        do {
            try await deps.openMeeting(record.id)
        } catch {
            Log.stats.warning("timeline: meeting \(record.id.uuidString) not opened: \(AnyError(error).description)")
            show(await deps.report(), replay: false)
        }
    }

    func changeTypingSpeed() {
        deps.openSettings()
    }

    private func show(_ content: TimelineContent, replay: Bool) {
        self.content = content
        guard replay else { return }
        playID += 1
        playback.replay(playID)
        anchor = nil
        selectedYear = nil
        yearMode = .meetings
        rhythmMode = .meetings
    }

    private static func isEmpty(_ report: TimelineReport) -> Bool {
        report.totals == nil && report.year == nil && report.rhythm == nil && report.talkShare == nil
            && report.spend == nil && report.dictation == nil && report.records == nil && report.milestones == nil
    }
}

import Foundation
import MWHistory
import MWMeetings
import MWSupport
import Observation

/// The one search over meetings and dictations (design §5.12, R19): debounced, cancelled by
/// the next keystroke, and reading each meeting once for as long as a query is being typed.
@MainActor
@Observable
final class SearchModel {
    struct Dependencies {
        var library: any MeetingReading
        var history: HistoryStore
        var clock: any MWSupport.Clock
        var now: @Sendable () -> Date
        /// Its time zone sets the days and times shown.
        var calendar: Calendar
    }

    /// An excerpt around a match: "Note · 00:40:05", "Speaker 3 · 01:12:48" or "Summary".
    struct Snippet: Equatable, Sendable {
        let label: String
        let text: String
    }

    struct MeetingHit: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let mode: MeetingMode
        let isTest: Bool
        /// Two at most; none when only the title matches.
        let snippets: [Snippet]
        /// "Today · 48 min · Remote call".
        let meta: String
        /// The start, "14:30".
        let time: String
    }

    struct DictationHit: Identifiable, Equatable, Sendable {
        let id: String
        /// The dictation, or an excerpt around the match when it is long.
        let text: String
        /// "Yesterday 17:41 · Mail".
        let meta: String
        let glyph: AppGlyph
    }

    /// The meetings read since the query was last empty, without their word timings.
    struct Cache: Sendable {
        var meetings: [UUID: LoadedMeeting] = [:]
        /// Failed to load; not tried again until the cache is emptied.
        var unreadable: Set<UUID> = []
    }

    static let delay = Duration.milliseconds(150)
    /// A dictation longer than this is shown as an excerpt.
    private nonisolated static let longDictation = 200
    private nonisolated static let dictationContext = 90

    private let deps: Dependencies
    @ObservationIgnored private let timeFormat: DateFormatter
    @ObservationIgnored private let dayFormat: DateFormatter

    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }

    /// Newest first.
    private(set) var meetings: [MeetingHit] = []
    /// Newest first.
    private(set) var dictations: [DictationHit] = []
    /// A query is waiting for its results; what is published belongs to an earlier one.
    private(set) var isSearching = false
    /// The search under way, if any.
    @ObservationIgnored private(set) var pending: Task<Void, Never>?
    @ObservationIgnored private(set) var cache = Cache()

    init(deps: Dependencies) {
        self.deps = deps
        timeFormat = MeetingsListModel.formatter("HH:mm", deps.calendar)
        dayFormat = MeetingsListModel.formatter("EEEE d MMM", deps.calendar)
    }

    /// Stored meetings or dictations changed: what was read is stale.
    func invalidate() {
        cache = Cache()
        schedule()
    }

    // MARK: - Search

    private func schedule() {
        pending?.cancel()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            pending = nil
            meetings = []
            dictations = []
            isSearching = false
            cache = Cache()
            return
        }
        isSearching = true
        let library = deps.library
        let history = deps.history
        let clock = deps.clock
        pending = Task { [weak self] in
            try? await clock.sleep(for: Self.delay)
            guard !Task.isCancelled, let cache = self?.cache else { return }
            let work = Task.detached { await Self.find(needle, library: library, history: history, cache: cache) }
            let found = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self else { return }
            // Logged here: a detached task does not carry the caller's log sinks.
            if let reason = found.indexFailure { Log.meeting.warning("search: index unreadable: \(reason)") }
            if found.skipped > 0 { Log.meeting.warning("search skipped \(found.skipped) meetings") }
            self.cache = found.cache
            meetings = found.meetings.map(meetingHit)
            dictations = found.dictations.map(dictationHit)
            isSearching = false
        }
    }

    private struct Match: Sendable {
        let meeting: Meeting
        let snippets: [Snippet]
    }

    private struct Found: Sendable {
        var cache: Cache
        /// Meetings that failed to load in this run.
        var skipped = 0
        var indexFailure: String?
        var meetings: [Match] = []
        var dictations: [HistoryEntry] = []
    }

    /// Reads what the cache lacks, then matches. Stops reading once cancelled.
    private nonisolated static func find(
        _ needle: String, library: any MeetingReading, history: HistoryStore, cache: Cache
    ) async -> Found {
        var found = Found(cache: cache)
        var ids: [UUID] = []
        do {
            ids = try library.index().map(\.id)
        } catch {
            found.indexFailure = AnyError(error).description
        }
        for id in ids where found.cache.meetings[id] == nil && !found.cache.unreadable.contains(id) {
            guard !Task.isCancelled else { return found }
            guard var meeting = try? library.load(id) else {
                found.cache.unreadable.insert(id)
                found.skipped += 1
                continue
            }
            for index in meeting.segments.indices { meeting.segments[index].words = [] }
            found.cache.meetings[id] = meeting
        }
        let read = found.cache.meetings
        let stored = ids.compactMap { read[$0] }.sorted { $0.meeting.startedAt > $1.meeting.startedAt }
        found.meetings = MeetingSearch().search(needle, in: stored).compactMap { hit in
            guard let loaded = read[hit.meetingID] else { return nil }
            let snippets = hit.snippets.map { Snippet(label: label(of: $0, in: loaded), text: $0.text) }
            return Match(meeting: loaded.meeting, snippets: snippets)
        }
        found.dictations = await history.search(needle).sorted { $0.timestamp > $1.timestamp }.map { entry in
            guard entry.text.count > longDictation,
                  let excerpt = SearchExcerpt.around(needle, in: entry.text, context: dictationContext)
            else { return entry }
            var entry = entry
            entry.text = excerpt
            return entry
        }
        return found
    }

    nonisolated static func label(of snippet: SearchSnippet, in meeting: LoadedMeeting) -> String {
        let time = snippet.time.map(MeetingTime.format) ?? ""
        switch snippet.source {
        case .summary:
            return "Summary"
        case .note:
            return "Note · \(time)"
        case .transcript:
            let speaker = meeting.segments.first { $0.start == snippet.time }?.speaker
            let name = speaker.map { id in meeting.meeting.speakers.first { $0.id == id }?.name ?? "Speaker \(id)" }
            return "\(name ?? "Transcript") · \(time)"
        }
    }

    // MARK: - Presentation

    private func meetingHit(_ match: Match) -> MeetingHit {
        let meeting = match.meeting
        let meta = [
            day(of: meeting.startedAt),
            MeetingsListModel.duration(meeting.durationSeconds),
            MeetingWindowModel.title(of: meeting.mode),
        ]
        return MeetingHit(
            id: meeting.id,
            title: meeting.title,
            mode: meeting.mode,
            isTest: meeting.test != nil,
            snippets: match.snippets,
            meta: meta.joined(separator: " · "),
            time: timeFormat.string(from: meeting.startedAt)
        )
    }

    private func dictationHit(_ entry: HistoryEntry) -> DictationHit {
        DictationHit(
            id: entry.id,
            text: entry.text,
            meta: "\(day(of: entry.timestamp)) \(timeFormat.string(from: entry.timestamp)) · \(entry.appName)",
            glyph: AppGlyph(appName: entry.appName, bundleID: entry.bundleID)
        )
    }

    private func day(of date: Date) -> String {
        MeetingsListModel.dayTitle(
            deps.calendar.startOfDay(for: date), now: deps.now(), calendar: deps.calendar, format: dayFormat
        )
    }
}

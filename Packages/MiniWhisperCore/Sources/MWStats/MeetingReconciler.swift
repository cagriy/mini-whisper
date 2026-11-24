import Foundation
import MWMeetings
import MWSupport

/// The stored meetings the reconciler reads. `modified` is the newest modification of a
/// meeting's `meeting.json`, `segments.jsonl` and `notes.jsonl`.
public protocol MeetingSource: Sendable {
    func index() throws -> [IndexEntry]
    func load(_ id: UUID) throws -> LoadedMeeting
    func meeting(_ id: UUID) throws -> Meeting
    func modified(_ id: UUID) -> Date?
}

extension MeetingStore: MeetingSource {}

extension MeetingSource {
    /// The meetings the record holds rows for: ended, and not test calls.
    public func keptMeetings() throws -> [IndexEntry] {
        try index().filter { isKept(test: $0.test, endedAt: $0.endedAt) }
    }
}

private func isKept(test: TestCallTag?, endedAt: Date?) -> Bool {
    test == nil && endedAt != nil
}

/// Meetings read so far in a pass, of those it found out of date.
public struct ReconcileProgress: Sendable, Equatable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// Brings `meetings.jsonl` up to date with the stored meetings. A meeting is read only when its
/// row is missing, from an earlier figures version, or older than its files; an unchanged one
/// costs a stat call. Nothing here throws: a meeting that cannot be read is logged and skipped.
public actor MeetingReconciler: MeetingStatsRecording {
    /// Each meeting read in a pass, then nil once the pass ends.
    public nonisolated let progress: AsyncStream<ReconcileProgress?>
    private let published: AsyncStream<ReconcileProgress?>.Continuation
    private let stats: StatsStore
    private let source: any MeetingSource
    /// Stands in for a meeting stored without its UTC offset.
    private let timeZone: @Sendable () -> TimeZone
    private let now: @Sendable () -> Date
    private var pass: Task<Bool, Never>?

    public init(
        stats: StatsStore,
        source: any MeetingSource,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.stats = stats
        self.source = source
        self.timeZone = timeZone
        self.now = now
        // Unbounded so a reader sees every step in order; a pass yields one value per meeting read.
        (progress, published) = AsyncStream.makeStream()
    }

    /// One pass at a time: a call during a pass waits for that pass and returns its result.
    /// True when a row was computed.
    @discardableResult
    public func reconcile() async -> Bool {
        if let pass { return await pass.value }
        let pass = Task { await self.run() }
        self.pass = pass
        return await pass.value
    }

    /// After any running pass, the stopped meeting's row, whether or not it looks out of date.
    public func meetingStopped(_ id: UUID) async {
        if let pass { _ = await pass.value }
        await refresh(id)
    }

    private func run() async -> Bool {
        defer {
            pass = nil
            published.yield(nil)
        }
        let started = ContinuousClock.now
        let kept: [IndexEntry]
        do {
            kept = try source.keptMeetings()
        } catch {
            Log.stats.warning("index.json not read: \(AnyError(error).description)")
            return false
        }
        let rows = await stats.meetingRows()
        let due = kept.filter { isDue(rows[$0.id], modified: source.modified($0.id)) }
        var computed = 0
        for (done, entry) in due.enumerated() {
            if await refresh(entry.id) { computed += 1 }
            published.yield(ReconcileProgress(done: done + 1, total: due.count))
        }
        let milliseconds = Int((ContinuousClock.now - started) / .milliseconds(1))
        Log.stats.info("reconcile, \(computed) computed, 0 word entries, 0 removed, \(milliseconds) ms")
        return computed > 0
    }

    /// `computed` holds whole seconds, so the modification time is cut to whole seconds too:
    /// files written in the second a row was computed do not make it stale.
    private func isDue(_ row: MeetingRow?, modified: Date?) -> Bool {
        guard let row, row.figures >= MeetingFigures.version,
              let computed = StatsTime.parse(row.computed)?.date
        else { return true }
        guard let modified else { return false }
        return modified.timeIntervalSince1970.rounded(.down) > computed.timeIntervalSince1970
    }

    /// True when the meeting is kept and its row was written.
    @discardableResult
    private func refresh(_ id: UUID) async -> Bool {
        let loaded: LoadedMeeting
        do {
            loaded = try source.load(id)
        } catch {
            Log.stats.warning("meeting \(id.uuidString) not reconciled: \(AnyError(error).description)")
            return false
        }
        guard isKept(test: loaded.meeting.test, endedAt: loaded.meeting.endedAt) else { return false }
        await stats.upsert(MeetingFigures.compute(loaded, fallback: timeZone(), now: now()))
        return true
    }
}

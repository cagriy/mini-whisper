import Foundation
import MWConfig
import MWMeetings
import MWStats
import MWSupport

/// What Timeline shows: the report, and the day the record began for the sub line.
struct TimelineContent: Equatable, Sendable {
    let report: TimelineReport
    /// `meta.since`, a local `yyyy-MM-dd`; nil before the record is seeded.
    let since: String?
}

/// Gathers the report's inputs, the record, the kept meetings and the typing speed, and computes it,
/// all off the main actor (design §5 Architecture, R32).
struct TimelineSource: Sendable {
    let stats: StatsStore
    let meetings: any MeetingSource
    let config: ConfigStore
    var now: @Sendable () -> Date = { Date() }
    var calendar: @Sendable () -> Calendar = { .current }

    func report() async -> TimelineContent {
        await Task.detached(priority: .userInitiated) { [self] in await gather() }.value
    }

    private func gather() async -> TimelineContent {
        let snapshot = await stats.snapshot()
        let typingWPM = await config.load().typingWPM
        var kept: [UUID: TimelineInputs.KeptMeeting] = [:]
        do {
            for entry in try meetings.keptMeetings() {
                kept[entry.id] = TimelineInputs.KeptMeeting(title: entry.title, start: entry.startedAt)
            }
        } catch {
            // Every record then reads as a deleted meeting until the index can be read again.
            Log.stats.warning("timeline: index.json not read: \(AnyError(error).description)")
        }
        let report = TimelineStats.compute(TimelineInputs(
            snapshot: snapshot, kept: kept, typingWPM: typingWPM, now: now(), calendar: calendar()
        ))
        return TimelineContent(report: report, since: snapshot.meta?.since)
    }
}

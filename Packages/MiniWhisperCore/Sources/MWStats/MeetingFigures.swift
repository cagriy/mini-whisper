import Foundation
import MWMeetings

/// A meeting's `meetings.jsonl` row from its files. Only numbers and identifiers are taken: no
/// transcript text, title or name reaches the row.
public enum MeetingFigures {
    /// A row computed by an earlier version is recomputed.
    public static let version = 1

    /// `fallback` stands in for a meeting stored without its UTC offset.
    public static func compute(_ loaded: LoadedMeeting, fallback: TimeZone, now: Date) -> MeetingRow {
        let meeting = loaded.meeting
        // One offset per row, the start's, as a recorded offset is.
        let offset = meeting.utcOffsetSeconds ?? fallback.secondsFromGMT(for: meeting.startedAt)
        let zone = TimeZone(secondsFromGMT: offset) ?? fallback
        let user = meeting.speakers.first(where: \.isUser)?.id

        var speakers: [Int: MeetingRow.Speaker] = [:]
        var sessions = Set<Int>()
        var speech = 0.0, words = 0, questions = 0, turns = 0, longestTurn = 0.0
        var turnSpeaker: Int?
        var turnSeconds = 0.0
        for segment in loaded.segments.sorted(by: { $0.start < $1.start }) {
            let seconds = segment.end - segment.start
            let count = segment.edited || segment.words.isEmpty ? WordCount.count(segment.text) : segment.words.count
            let asked = isQuestion(segment.text) ? 1 : 0
            var speaker = speakers[segment.speaker] ?? MeetingRow.Speaker(id: segment.speaker)
            speaker.seconds += seconds
            speaker.words += count
            speaker.questions += asked
            speakers[segment.speaker] = speaker
            speech += seconds
            words += count
            questions += asked
            sessions.insert(segment.session)
            if segment.speaker == turnSpeaker {
                turnSeconds += seconds
            } else {
                if turnSpeaker != nil { turns += 1 }
                turnSpeaker = segment.speaker
                turnSeconds = seconds
            }
            longestTurn = max(longestTurn, turnSeconds)
        }

        var gaps = 0.0, paused = 0.0
        for marker in meeting.markers {
            switch marker.kind {
            case .gap: gaps += marker.end - marker.start
            case .paused, .sleep: paused += marker.end - marker.start
            }
        }

        return MeetingRow(
            id: meeting.id,
            at: StatsTime.iso(meeting.startedAt, timeZone: zone),
            end: meeting.endedAt.map { StatsTime.iso($0, timeZone: zone) } ?? "",
            duration: meeting.durationSeconds,
            mode: meeting.mode.rawValue,
            engine: meeting.engine.rawValue,
            speech: speech,
            words: words,
            user: user,
            userKnown: meeting.mode == .remote || (user.flatMap { speakers[$0]?.words } ?? 0) > 0,
            speakers: speakers.values.sorted { $0.id < $1.id },
            named: meeting.speakers.count { !$0.isUser && $0.name != SpeakerLabel.defaultName($0.id) },
            turns: turns,
            longestTurn: longestTurn,
            questions: questions,
            notes: loaded.notes.count,
            gaps: gaps,
            paused: paused,
            reconnects: max(0, sessions.count - 1),
            silenceStop: meeting.silenceStopSeconds != nil,
            summary: meeting.summary != nil,
            usd: MeetingRow.Costs(
                meeting: meeting.billing.costUSD,
                summary: (meeting.summary?.costUSD ?? 0) + meeting.billing.replacedSummaryCostUSD,
                naming: meeting.billing.namingCostUSD
            ),
            delay: meeting.timing?.transcriptDelay.map {
                MeetingRow.Delay(median: $0.median, p90: $0.p90, count: $0.count)
            },
            summaryWait: meeting.timing?.summaryWaitSeconds,
            figures: version,
            computed: StatsTime.iso(now, timeZone: .gmt)
        )
    }

    private static func isQuestion(_ text: String) -> Bool {
        let last = text.last { !$0.isWhitespace }
        return last == "?" || last == "？"
    }
}

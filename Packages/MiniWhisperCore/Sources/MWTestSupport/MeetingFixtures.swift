import Foundation
import MWConfig
import MWMeetings

/// Meetings for tests. `northwind()` is the meeting of the accepted export mockup
/// (`features/feature-v4-Meeting-transcripts/mockups/mockup-v4-export-markdown.html`).
public enum MeetingFixtures {
    public static let northwindID = UUID(uuidString: "7f3a9c2e-5b1d-4e0a-9c77-2d8f1a6b3c40")!

    public static func northwind() -> LoadedMeeting {
        let startedAt = Date(timeIntervalSince1970: 1_794_234_600)  // 2026-11-09T14:30:00Z
        let alex = 0, marta = 1, priya = 2
        // Segment 0 stands for the part of the meeting the mockup elides, where Alex speaks first.
        let segments = [
            segment(0, alex, 4, 8, session: 1, label: "S3", """
                Thanks for joining. Let's start with the Northwind rollout.
                """),
            segment(1, marta, 2342, 2358, session: 1, label: "S1", """
                So the Northwind rollout slips a week if the migration script is not signed off by \
                Thursday. Priya, can your team take the review?
                """),
            segment(2, alex, 2361, 2378, session: 1, label: "S3", """
                Yes, if the staging data is refreshed first. The last snapshot is from October and the \
                new columns are missing.
                """),
            segment(3, priya, 2380, 2397, session: 1, label: "S2", """
                I can do the refresh tonight. Let's put the sign-off on Wednesday instead so there is a \
                day of slack.
                """),
            segment(4, marta, 2412, 2428, session: 1, label: "S1", """
                Agreed. One more thing on pricing: the enterprise tier needs the per-seat cap before the demo.
                """),
            segment(5, alex, 2523, 2538, session: 2, label: "S1", """
                I think the cap should default to twenty-five seats and trial accounts stay uncapped until \
                we hear from legal.
                """),
            segment(6, priya, 2791, 2797, session: 3, label: "S1", """
                Back. Shall we close with the demo date? It is the 18th, not the 20th.
                """),
        ]
        let notes = [
            Note(id: id(0x201), time: 760, text: "Marta owns the migration script; review by Thu",
                 createdAt: startedAt.addingTimeInterval(760)),
            Note(id: id(0x202), time: 1635, text: "Demo is on the 18th, not the 20th",
                 createdAt: startedAt.addingTimeInterval(1635)),
            Note(id: id(0x203), time: 2405, text: "Ask ops for a Wednesday maintenance window",
                 createdAt: startedAt.addingTimeInterval(2405)),
        ]
        let summary = Summary(
            text: """
                ## Summary

                The Northwind rollout stays on schedule provided the migration script is reviewed by \
                Wednesday, after Priya refreshes staging data tonight. The enterprise pricing demo on the \
                18th needs the per-seat cap in place.

                ## Decisions

                - Migration script sign-off moves to Wednesday (Priya).
                - Per-seat cap defaults to 25 seats for the demo.

                ## Action items

                - **Priya**: refresh staging data tonight.
                - **Marta**: migration script ready for review by Wednesday.
                - **Alex**: ask ops for a Wednesday maintenance window.

                ## Open questions

                - Whether the cap applies to trial accounts (not settled in the meeting).
                """,
            model: "claude-sonnet-5-5",
            createdAt: Date(timeIntervalSince1970: 1_794_237_580),  // 2026-11-09T15:19:40Z
            inputTokens: 12480,
            outputTokens: 610,
            costUSD: 0.03106
        )
        let meeting = Meeting(
            id: northwindID,
            title: "Northwind rollout sync",
            startedAt: startedAt,
            endedAt: Date(timeIntervalSince1970: 1_794_237_560),  // 2026-11-09T15:19:20Z
            durationSeconds: 2932,
            mode: .remote,
            app: "Zoom",
            engine: .speechmaticsStandard,
            userName: "Alex",
            speakers: [
                SpeakerLabel(id: alex, name: "Alex", isUser: true, providerKeys: ["1:S3", "2:S1"]),
                SpeakerLabel(id: marta, name: "Marta", providerKeys: ["1:S1"]),
                SpeakerLabel(id: priya, name: "Priya", providerKeys: ["1:S2", "3:S1"]),
            ],
            markers: [
                Marker(kind: .gap, start: 2508, end: 2523, reason: "connection lost"),
                Marker(kind: .paused, start: 2650, end: 2790),
            ],
            summary: summary,
            billing: Billing(engineSeconds: 2932, costUSD: 0.3665)
        )
        return LoadedMeeting(meeting: meeting, segments: segments, notes: notes)
    }

    /// A small meeting: the user alone, no summary.
    public static func make(
        id: UUID = UUID(),
        title: String = "Zoom · 9 Nov 2026 11:00",
        startedAt: Date = Date(timeIntervalSince1970: 1_794_222_000),  // 2026-11-09T11:00:00Z
        mode: MeetingMode = .remote,
        engine: MeetingEngine = .speechmaticsStandard,
        segments: [Segment] = [],
        notes: [Note] = [],
        summary: Summary? = nil,
        test: TestCallTag? = nil
    ) -> LoadedMeeting {
        let meeting = Meeting(
            id: id,
            title: title,
            startedAt: startedAt,
            mode: mode,
            app: "Zoom",
            engine: engine,
            userName: "Alex",
            speakers: [SpeakerLabel(id: 0, name: "Alex", isUser: true)],
            summary: summary,
            test: test
        )
        return LoadedMeeting(meeting: meeting, segments: segments, notes: notes)
    }

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "7f3a9c2e-0000-4000-8000-%012x", number))!
    }

    private static func segment(
        _ number: Int, _ speaker: Int, _ start: Double, _ end: Double,
        session: Int, label: String, _ text: String
    ) -> Segment {
        Segment(
            id: id(0x100 + number), speaker: speaker, start: start, end: end, text: text,
            session: session, providerLabel: label
        )
    }
}

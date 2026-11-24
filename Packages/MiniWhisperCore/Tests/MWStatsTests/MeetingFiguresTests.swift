import Foundation
import Testing

import MWMeetings
import MWStats
import MWTestSupport

@Suite struct MeetingFiguresTests {
    private static let newYork = TimeZone(identifier: "America/New_York")!
    private static let now = Date(timeIntervalSince1970: 1_795_540_278)  // 2026-11-24T17:11:18Z

    private func figures(_ loaded: LoadedMeeting, fallback: TimeZone = newYork) -> MeetingRow {
        MeetingFigures.compute(loaded, fallback: fallback, now: Self.now)
    }

    /// `MeetingFixtures.make`: remote, Alex as the user with id 0, unfinished.
    private func loaded(
        mode: MeetingMode = .remote,
        speakers: [SpeakerLabel] = [SpeakerLabel(id: 0, name: "Alex", isUser: true)],
        segments: [Segment] = [],
        change: (inout Meeting) -> Void = { _ in }
    ) -> LoadedMeeting {
        var loaded = MeetingFixtures.make(mode: mode, segments: segments)
        loaded.meeting.speakers = speakers
        change(&loaded.meeting)
        return loaded
    }

    private func segment(
        _ speaker: Int, _ start: Double, _ end: Double, _ text: String = "",
        words: Int = 0, session: Int = 1, edited: Bool = false
    ) -> Segment {
        Segment(
            speaker: speaker, start: start, end: end, text: text,
            words: (0..<words).map { Word(text: "w\($0)", start: start, end: end) },
            session: session, edited: edited
        )
    }

    private func strings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap(strings)
        case let object as [String: Any]: object.values.flatMap(strings)
        default: []
        }
    }

    @Test func northwindGivesEveryFigure() {
        let expected = MeetingRow(
            id: MeetingFixtures.northwindID,
            at: "2026-11-09T09:30:00-05:00",
            end: "2026-11-09T10:19:20-05:00",
            duration: 2_932,
            mode: "remote",
            engine: "speechmatics_standard",
            speech: 91,
            words: 126,
            user: 0,
            userKnown: true,
            speakers: [
                MeetingRow.Speaker(id: 0, seconds: 36, words: 49),
                MeetingRow.Speaker(id: 1, seconds: 32, words: 41, questions: 1),
                MeetingRow.Speaker(id: 2, seconds: 23, words: 36),
            ],
            named: 2,
            turns: 6,
            longestTurn: 17,
            questions: 1,
            notes: 3,
            gaps: 15,
            paused: 140,
            reconnects: 2,
            silenceStop: false,
            summary: true,
            usd: MeetingRow.Costs(meeting: 0.3665, summary: 0.03106),
            delay: nil,
            summaryWait: nil,
            figures: 1,
            computed: "2026-11-24T17:11:18+00:00"
        )
        #expect(figures(MeetingFixtures.northwind()) == expected)
    }

    @Test func atAndEndTakeTheMeetingsOwnOffset() {
        var loaded = MeetingFixtures.northwind()
        loaded.meeting.utcOffsetSeconds = 19_800
        let row = figures(loaded)
        #expect(row.at == "2026-11-09T20:00:00+05:30")
        #expect(row.end == "2026-11-09T20:49:20+05:30")
    }

    @Test func withoutAnOffsetTheFallbacksOffsetAtTheStartHoldsForBoth() {
        // 01:30 EDT, and an hour later 01:30 EST: one offset per row, as a recorded one would be.
        let row = figures(loaded { meeting in
            meeting.startedAt = Date(timeIntervalSince1970: 1_793_511_000)
            meeting.endedAt = Date(timeIntervalSince1970: 1_793_514_600)
        })
        #expect(row.at == "2026-11-01T01:30:00-04:00")
        #expect(row.end == "2026-11-01T02:30:00-04:00")
    }

    @Test func anUnfinishedMeetingHasNoEnd() {
        let row = figures(loaded())
        #expect(row.at == "2026-11-09T06:00:00-05:00")
        #expect(row.end == "")
    }

    @Test func durationIsTheRecordedSecondsAndModeAndEngineTheirRawValues() {
        let row = figures(loaded(mode: .inRoom) { meeting in
            meeting.engine = .assemblyaiPro
            meeting.endedAt = meeting.startedAt.addingTimeInterval(900)
            meeting.durationSeconds = 600
            meeting.markers = [Marker(kind: .paused, start: 200, end: 500)]
        })
        #expect(row.duration == 600)
        #expect(row.mode == "in-room")
        #expect(row.engine == "assemblyai_pro")
    }

    @Test func aSegmentCountsItsWordListUnlessEditedOrWithoutOne() {
        let row = figures(loaded(segments: [
            segment(0, 0, 4, "one two three four five", words: 3),
            segment(0, 5, 9, "one two three four five", words: 3, edited: true),
            segment(0, 10, 12.5, "one two three four"),
        ]))
        #expect(row.words == 12)
        #expect(row.speech == 10.5)
    }

    @Test func theUserIsKnownWhenRemoteOrWhenTheUserHasWords() {
        let other = segment(1, 0, 5, "Hello there")

        let remoteSilent = figures(loaded(mode: .remote, segments: [other]))
        #expect(remoteSilent.user == 0)
        #expect(remoteSilent.userKnown)

        let inRoomSilent = figures(loaded(mode: .inRoom, segments: [other]))
        #expect(inRoomSilent.user == 0)
        #expect(!inRoomSilent.userKnown)

        let inRoomSpoken = figures(loaded(
            mode: .inRoom, speakers: [SpeakerLabel(id: 2, name: "Alex", isUser: true)],
            segments: [other, segment(2, 6, 8, "Agreed")]
        ))
        #expect(inRoomSpoken.user == 2)
        #expect(inRoomSpoken.userKnown)

        let nobodyMarked = figures(loaded(
            mode: .inRoom, speakers: [SpeakerLabel(id: 1, name: SpeakerLabel.defaultName(1))], segments: [other]
        ))
        #expect(nobodyMarked.user == nil)
        #expect(!nobodyMarked.userKnown)
    }

    @Test func speakersHoldTheirSecondsWordsAndQuestionsInIdOrder() {
        let row = figures(loaded(segments: [
            segment(2, 0, 3, "Ready to start?"),
            segment(0, 3, 7.5, "Yes. Shall we begin?  \n"),
            segment(2, 8, 10, "Is it ready？"),
            segment(0, 10, 11, "Why? Because."),
        ]))
        #expect(row.speakers == [
            MeetingRow.Speaker(id: 0, seconds: 5.5, words: 6, questions: 1),
            MeetingRow.Speaker(id: 2, seconds: 5, words: 6, questions: 2),
        ])
        #expect(row.questions == 3)
    }

    @Test func namedCountsOtherSpeakersWithARealName() {
        let row = figures(loaded(speakers: [
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: SpeakerLabel.defaultName(1)),
            SpeakerLabel(id: 2, name: "Marta"),
            SpeakerLabel(id: 3, name: "Priya"),
            SpeakerLabel(id: 4, name: SpeakerLabel.defaultName(4)),
        ]))
        #expect(row.named == 2)
    }

    @Test func turnsCountSpeakerChangesInTimeOrderAndTheLongestTurnSumsItsRun() {
        let row = figures(loaded(segments: [
            segment(1, 21, 25),
            segment(0, 0, 10),
            segment(0, 26, 30),
            segment(0, 12, 20),
        ]))
        #expect(row.turns == 2)
        #expect(row.longestTurn == 18)
    }

    @Test func markersGiveGapsAndPausedAndSessionsGiveReconnects() {
        let row = figures(loaded(segments: [
            segment(0, 0, 2, session: 1),
            segment(0, 3, 4, session: 1),
            segment(0, 50, 52, session: 3),
        ]) { meeting in
            meeting.markers = [
                Marker(kind: .gap, start: 10, end: 15),
                Marker(kind: .paused, start: 20, end: 40),
                Marker(kind: .gap, start: 41, end: 46),
                Marker(kind: .sleep, start: 60, end: 100),
            ]
        })
        #expect(row.gaps == 10)
        #expect(row.paused == 60)
        #expect(row.reconnects == 1)

        let silent = figures(loaded())
        #expect(silent.reconnects == 0)
        #expect(silent.turns == 0)
        #expect(silent.longestTurn == 0)
    }

    @Test func silenceStopSummaryAndCostsComeFromTheMeeting() {
        let row = figures(loaded { meeting in
            meeting.silenceStopSeconds = 300
            meeting.summary = Summary(
                text: "## Topic", model: "model", createdAt: Self.now, inputTokens: 10, outputTokens: 5,
                costUSD: 0.25
            )
            meeting.billing = Billing(
                engineSeconds: 600, costUSD: 1.5, replacedSummaryCostUSD: 0.5, namingCostUSD: 0.125
            )
        })
        #expect(row.silenceStop)
        #expect(row.summary)
        #expect(row.usd == MeetingRow.Costs(meeting: 1.5, summary: 0.75, naming: 0.125))

        let plain = figures(loaded())
        #expect(!plain.silenceStop)
        #expect(!plain.summary)
        #expect(plain.usd == MeetingRow.Costs())
    }

    @Test func delayAndSummaryWaitAreCopiedFromTheTiming() {
        var loaded = MeetingFixtures.northwind()
        loaded.meeting.timing = MeetingTiming(
            transcriptDelay: DelayStats(median: 1.25, p90: 2.5, count: 40), summaryWaitSeconds: 12.5
        )
        let row = figures(loaded)
        #expect(row.delay == MeetingRow.Delay(median: 1.25, p90: 2.5, count: 40))
        #expect(row.summaryWait == 12.5)

        loaded.meeting.timing = MeetingTiming(summaryWaitSeconds: 3)
        let waitOnly = figures(loaded)
        #expect(waitOnly.delay == nil)
        #expect(waitOnly.summaryWait == 3)
    }

    @Test func theRowCarriesTheVersionAndTheUTCInstantItWasComputed() {
        let row = figures(loaded(), fallback: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(MeetingFigures.version == 1)
        #expect(row.figures == MeetingFigures.version)
        #expect(row.computed == "2026-11-24T17:11:18+00:00")
    }

    @Test func theEncodedRowHoldsNoTextTitleOrName() throws {
        let loaded = MeetingFixtures.northwind()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(figures(loaded))
        let text = String(decoding: data, as: UTF8.self)

        let meeting = loaded.meeting
        let forbidden = [meeting.title, meeting.userName, meeting.app, meeting.summary?.text, "Northwind"].compactMap { $0 }
            + meeting.speakers.map(\.name) + loaded.segments.map(\.text) + loaded.notes.map(\.text)
        for string in forbidden {
            #expect(!text.contains(string), "\(string)")
        }
        // Only identifiers, times, mode and engine are strings.
        #expect(Set(strings(in: try JSONSerialization.jsonObject(with: data))) == [
            MeetingFixtures.northwindID.uuidString,
            "2026-11-09T09:30:00-05:00", "2026-11-09T10:19:20-05:00", "2026-11-24T17:11:18+00:00",
            "remote", "speechmatics_standard",
        ])
    }
}

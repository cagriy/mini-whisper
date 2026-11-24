import Foundation
import Testing

import MWStats

@Suite struct StatsRowsTests {
    private static let meetingID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func decode<Row: Decodable>(_ type: Row.Type, _ text: String) throws -> Row {
        try JSONDecoder().decode(Row.self, from: Data(text.utf8))
    }

    private func keys(_ value: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        return Set(try #require(object as? [String: Any]).keys)
    }

    private func fullMeeting() -> MeetingRow {
        MeetingRow(
            id: Self.meetingID,
            at: "2026-11-30T09:00:00+00:00",
            end: "2026-11-30T10:00:00+00:00",
            duration: 3_540,
            mode: "remote",
            engine: "speechmatics",
            speech: 3_100,
            words: 8_200,
            user: 0,
            userKnown: true,
            speakers: [
                MeetingRow.Speaker(id: 0, seconds: 1_200, words: 3_000, questions: 4),
                MeetingRow.Speaker(id: 1, seconds: 1_900, words: 5_200, questions: 7),
            ],
            named: 1,
            turns: 88,
            longestTurn: 240,
            questions: 11,
            notes: 2,
            gaps: 12,
            paused: 60,
            reconnects: 1,
            silenceStop: true,
            summary: true,
            usd: MeetingRow.Costs(meeting: 0.44, summary: 0.03, naming: 0.001),
            delay: MeetingRow.Delay(median: 1.2, p90: 2.5, count: 140),
            summaryWait: 18.5,
            figures: 1,
            computed: "2026-11-30T10:02:11+00:00"
        )
    }

    @Test func aDeliveredDictationRowEncodesSortedWithoutItsZeroFields() throws {
        let delivered = DictationRow(
            id: "a1", at: "2026-11-30T09:14:03+00:00", app: "com.example.notes", engine: "speech_analyzer",
            seconds: 6.5, words: 12, outcome: .delivered, wait: 1.5, usd: 0.002
        )
        let tooShort = DictationRow(id: "a2", at: "2026-11-30T09:15:00+00:00", outcome: .tooShort)
        let seeded = DictationRow(id: "a3", at: "2026-11-30T09:16:00+00:00", outcome: .delivered, seeded: true)

        #expect(try json(delivered) == #"{"app":"com.example.notes","at":"2026-11-30T09:14:03+00:00","#
            + #""engine":"speech_analyzer","id":"a1","outcome":"delivered","seconds":6.5,"usd":0.002,"#
            + #""wait":1.5,"words":12}"#)
        #expect(try json(tooShort) == #"{"at":"2026-11-30T09:15:00+00:00","id":"a2","outcome":"too_short"}"#)
        #expect(try json(seeded)
            == #"{"at":"2026-11-30T09:16:00+00:00","id":"a3","outcome":"delivered","seeded":true}"#)
    }

    @Test func anEmptyDayRowEncodesOnlyItsDay() throws {
        #expect(try json(DayRow(day: "2026-11-30")) == #"{"day":"2026-11-30"}"#)
        #expect(try json(Spend()) == "{}")
        #expect(try json(MeetingRow(id: Self.meetingID)) == #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}"#)
    }

    @Test func missingFieldsReadAsZeroAndUnknownKeysAreIgnored() throws {
        #expect(try decode(DayRow.self, #"{"day":"2026-11-30","later":{"x":1}}"#) == DayRow(day: "2026-11-30"))
        #expect(try decode(
            DictationRow.self, #"{"id":"a","at":"2026-11-30T09:14:03+00:00","outcome":"silent","later":true}"#
        ) == DictationRow(id: "a", at: "2026-11-30T09:14:03+00:00", outcome: .silent))
        #expect(try decode(Spend.self, #"{"later":2}"#) == Spend())
        #expect(try decode(MeetingRow.Speaker.self, #"{"words":3}"#) == MeetingRow.Speaker(id: 0, words: 3))
    }

    @Test func aMeetingRowWithOnlyAnIDDecodes() throws {
        let row = try decode(MeetingRow.self, #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}"#)

        #expect(row == MeetingRow(id: Self.meetingID))
        #expect(row.duration == 0)
        #expect(row.user == nil)
        #expect(row.delay == nil)
        #expect(row.usd == MeetingRow.Costs())
    }

    @Test func theDesignsKeysHold() throws {
        let day = DayRow(
            day: "2026-11-30", delivered: 2, words: 30, seconds: 12, timedWords: 30,
            undelivered: ["silent": 1], apps: ["other": 2], hours: ["9": 2],
            spend: ["dictation": Spend(usd: 0.01, tokensIn: 100, tokensOut: 20, seconds: ["elevenlabs": 12])]
        )
        let dictation = DictationRow(
            id: "a1", at: "2026-11-30T09:14:03+00:00", app: "com.example.notes", engine: "elevenlabs",
            seconds: 6, words: 12, outcome: .delivered, wait: 1, usd: 0.001, seeded: true
        )
        let meeting = fullMeeting()
        let delay = try #require(meeting.delay)

        #expect(try keys(day) == [
            "day", "delivered", "words", "seconds", "timed_words", "undelivered", "apps", "hours", "spend",
        ])
        #expect(try keys(Spend(usd: 1, tokensIn: 1, tokensOut: 1, seconds: ["x": 1])) == [
            "usd", "tokens_in", "tokens_out", "seconds",
        ])
        #expect(try keys(dictation) == [
            "id", "at", "app", "engine", "seconds", "words", "outcome", "wait", "usd", "seeded",
        ])
        #expect(try keys(meeting) == [
            "id", "at", "end", "duration", "mode", "engine", "speech", "words", "user", "user_known",
            "speakers", "named", "turns", "longest_turn", "questions", "notes", "gaps", "paused",
            "reconnects", "silence_stop", "summary", "usd", "delay", "summary_wait", "figures", "computed",
        ])
        #expect(try keys(meeting.speakers[1]) == ["id", "seconds", "words", "questions"])
        #expect(try keys(meeting.usd) == ["meeting", "summary", "naming"])
        #expect(try keys(delay) == ["median", "p90", "count"])
        #expect(try keys(StatsMeta(since: "2026-11-30", created: "2026-11-30T09:14:03+00:00")) == [
            "schema", "since", "created",
        ])
    }

    @Test func everyRowRoundTripsWithAZeroOptionalKept() throws {
        let day = DayRow(
            day: "2026-11-30", delivered: 2, words: 30, seconds: 12.5, timedWords: 30,
            undelivered: ["no_key": 1], apps: ["com.example.notes": 2], hours: ["23": 2],
            spend: ["unsplit": Spend(usd: 0.4, tokensIn: 9, tokensOut: 3, seconds: ["assemblyai": 60])]
        )
        let dictation = DictationRow(
            id: "a1", at: "2026-11-30T09:14:03+00:00", app: nil, engine: nil,
            seconds: 6, words: 12, outcome: .delivered, wait: 0, usd: 0.001
        )
        let meta = StatsMeta(since: "2026-11-30", created: "2026-11-30T09:14:03+00:00")

        #expect(try decode(DayRow.self, json(day)) == day)
        #expect(try decode(DictationRow.self, json(dictation)) == dictation)
        #expect(try json(dictation).contains(#""wait":0"#))
        #expect(try decode(MeetingRow.self, json(fullMeeting())) == fullMeeting())
        #expect(try json(fullMeeting()).contains(#""user":0"#))
        #expect(try decode(StatsMeta.self, json(meta)) == meta)
        #expect(try json(meta) == #"{"created":"2026-11-30T09:14:03+00:00","schema":1,"since":"2026-11-30"}"#)
    }

    @Test func dayRowAddSumsFieldByFieldMapsIncluded() {
        var day = DayRow(
            day: "2026-11-30", delivered: 1, words: 10, seconds: 4, timedWords: 10,
            undelivered: ["silent": 1], apps: ["com.example.notes": 1], hours: ["9": 1],
            spend: ["dictation": Spend(usd: 0.25, tokensIn: 10, tokensOut: 2, seconds: ["elevenlabs": 4])]
        )

        day.add(DayRow(
            day: "2026-11-30", delivered: 2, words: 5, seconds: 2, timedWords: 3,
            undelivered: ["silent": 2, "empty": 1], apps: ["com.example.notes": 1, "other": 1],
            hours: ["9": 1, "14": 1],
            spend: [
                "dictation": Spend(usd: 0.5, tokensIn: 1, tokensOut: 1, seconds: ["elevenlabs": 1, "on_device": 3]),
                "meeting": Spend(usd: 1, seconds: ["speechmatics": 60]),
            ]
        ))

        #expect(day == DayRow(
            day: "2026-11-30", delivered: 3, words: 15, seconds: 6, timedWords: 13,
            undelivered: ["silent": 3, "empty": 1], apps: ["com.example.notes": 2, "other": 1],
            hours: ["9": 2, "14": 1],
            spend: [
                "dictation": Spend(usd: 0.75, tokensIn: 11, tokensOut: 3, seconds: ["elevenlabs": 5, "on_device": 3]),
                "meeting": Spend(usd: 1, seconds: ["speechmatics": 60]),
            ]
        ))
    }

    @Test(arguments: [(59.9, false), (60, true), (0, false), (3_600, true)])
    func aMeetingCountsFromSixtySeconds(_ duration: Double, _ counted: Bool) {
        #expect(MeetingRow(id: Self.meetingID, duration: duration).isCounted == counted)
    }

    @Test func localStartAndEndUseTheOffsetInsideTheRow() throws {
        let row = MeetingRow(id: Self.meetingID, at: "2026-11-30T23:30:00-08:00", end: "2026-12-01T01:15:00-08:00")

        let start = try #require(row.localStart)
        let end = try #require(row.localEnd)

        #expect([start.year, start.month, start.day, start.hour, start.minute] == [2026, 11, 30, 23, 30])
        #expect(start.weekday == 2)
        #expect(start.timeZone?.secondsFromGMT() == -8 * 3600)
        #expect(start.date == StatsTime.parse("2026-11-30T23:30:00-08:00")?.date)
        #expect([end.month, end.day, end.hour, end.minute] == [12, 1, 1, 15])
        #expect(MeetingRow(id: Self.meetingID).localStart == nil)
        #expect(MeetingRow(id: Self.meetingID, at: "2026-11-30T23:30:00Z").localStart == nil)
    }
}

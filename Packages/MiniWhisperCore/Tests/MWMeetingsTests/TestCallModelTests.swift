import Foundation
import MWConfig
import MWTestSupport
import Testing

import MWMeetings

@Suite struct TestCallModelTests {
    private static let legacyID = UUID(uuidString: "5C0D1A2B-3E4F-4A5B-8C6D-7E8F9A0B1C2D")!

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

    @Test func legacyMeetingAndIndexDecodeWithoutATag() throws {
        let meetingData = try fixture("meeting-v0.5")
        let indexData = try fixture("index-v0.5")

        let meeting = try MeetingCoding.decoder().decode(Meeting.self, from: meetingData)
        let index = try MeetingCoding.decoder().decode([IndexEntry].self, from: indexData)

        #expect(meeting == MeetingFixtures.make(id: Self.legacyID).meeting)
        #expect(meeting.test == nil)
        #expect(index.map(\.id) == [Self.legacyID])
        #expect(index.first?.test == nil)
        // Rewritten untouched, the index keeps its bytes and the meeting gains only the replaced-cost key.
        let rewritten = String(decoding: meetingData, as: UTF8.self).replacingOccurrences(
            of: #""engineSeconds":0}"#, with: #""engineSeconds":0,"replacedSummaryCostUSD":0}"#
        )
        #expect(try MeetingCoding.encoder().encode(meeting) == Data(rewritten.utf8))
        #expect(try MeetingCoding.encoder().encode(index) == indexData)
    }

    @Test func untaggedMeetingEncodesNoTestKey() throws {
        let json = try object(MeetingCoding.encoder().encode(MeetingFixtures.make().meeting))

        #expect(json["test"] == nil)
        #expect(json["title"] != nil)
    }

    @Test func taggedMeetingRoundTrips() throws {
        var meeting = MeetingFixtures.make(test: tag).meeting
        var data = try MeetingCoding.encoder().encode(meeting)

        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: data) == meeting)
        var test = try #require(try object(data)["test"] as? [String: Any])
        #expect(Set(test.keys) == ["scenarioID", "revision", "scenarioTitle"])
        #expect(test["scenarioID"] as? String == "sprint-planning")

        meeting.test?.wer = 0.064
        data = try MeetingCoding.encoder().encode(meeting)

        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: data).test?.wer == 0.064)
        test = try #require(try object(data)["test"] as? [String: Any])
        #expect(test["wer"] as? Double == 0.064)
    }

    @Test func recordEncodesTheSchemaOneShape() throws {
        let record = TestCallRecord(
            scenario: .init(id: "sprint-planning", revision: 1, title: "Sprint planning"),
            engine: .assemblyaiStreaming,
            overlap: false,
            scoredAt: Date(timeIntervalSince1970: 1_794_395_762),  // 2026-11-11T11:16:02Z
            voices: [
                .init(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
                .init(role: .b, character: "Priya", requested: "Karen", voice: "Karen"),
            ],
            lines: [
                .init(
                    index: 6, role: .b, status: .done, start: 41.0, end: 47.6, overlapped: false,
                    reference: "Then the remaining risk is the Kubernetes upgrade.",
                    counts: .init(words: 17, substitutions: 1, deletions: 0, insertions: 1),
                    heard: [
                        .init(text: "Then", op: .match),
                        .init(text: "Cooper Netties", op: .error, script: "Kubernetes"),
                        .init(op: .missed, script: "a"),
                    ],
                    labels: ["2": 17], segmentStart: 41.2, latency: 2.9
                ),
                .init(index: 11, role: .you, status: .skipped, reference: "Agreed. I'll move the export ticket."),
            ],
            roles: [
                .init(role: .you, words: 48, substitutions: 1, deletions: 1, insertions: 0,
                      majorityLabel: 0, majorityLabelName: "Alex", purity: 1.0),
            ],
            overall: .init(words: 157, substitutions: 6, deletions: 1, insertions: 3),
            crossCredited: .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0),
            latency: .init(median: 1.3, max: 2.9, maxLine: 6)
        )
        let data = try MeetingCoding.encoder().encode(record)
        let json = try object(data)

        #expect(try MeetingCoding.decoder().decode(TestCallRecord.self, from: data) == record)
        #expect(Set(json.keys) == [
            "schema", "scenario", "engine", "overlap", "scoredAt", "voices", "lines", "roles", "overall",
            "crossCredited", "latency",
        ])
        #expect(json["schema"] as? Int == 1)
        let scenario = try #require(json["scenario"] as? [String: Any])
        #expect(scenario["id"] as? String == "sprint-planning")
        #expect(scenario["revision"] as? Int == 1)
        #expect(scenario["title"] as? String == "Sprint planning")
        #expect(json["engine"] as? String == "assemblyai_streaming")
        #expect(json["overlap"] as? Bool == false)
        #expect(json["scoredAt"] as? String == "2026-11-11T11:16:02Z")

        let voices = try #require(json["voices"] as? [[String: Any]])
        #expect(Set(voices[0].keys) == ["role", "character", "requested", "voice"])
        #expect(voices[0]["role"] as? String == "a")
        #expect(voices[1]["character"] as? String == "Priya")

        let lines = try #require(json["lines"] as? [[String: Any]])
        let done = lines[0]
        #expect(done["status"] as? String == "done")
        #expect(done["role"] as? String == "b")
        #expect(done["labels"] as? [String: Int] == ["2": 17])
        let counts = try #require(done["counts"] as? [String: Any])
        #expect(Set(counts.keys) == ["words", "substitutions", "deletions", "insertions"])
        let heard = try #require(done["heard"] as? [[String: Any]])
        #expect(heard[0]["op"] as? String == "match")
        #expect(heard[0]["script"] == nil)
        #expect(heard[1]["text"] as? String == "Cooper Netties")
        #expect(heard[1]["op"] as? String == "error")
        #expect(heard[1]["script"] as? String == "Kubernetes")
        #expect(Set(heard[2].keys) == ["op", "script"])
        #expect(done["segmentStart"] as? Double == 41.2)
        #expect(done["latency"] as? Double == 2.9)
        let skipped = lines[1]
        #expect(Set(skipped.keys) == ["index", "role", "status", "reference"])
        #expect(skipped["role"] as? String == "you")
        #expect(skipped["status"] as? String == "skipped")

        let role = try #require((json["roles"] as? [[String: Any]])?.first)
        #expect(Set(role.keys) == [
            "role", "words", "substitutions", "deletions", "insertions", "majorityLabel", "majorityLabelName",
            "purity",
        ])
        let overall = try #require(json["overall"] as? [String: Any])
        #expect(overall["words"] as? Int == 157)
        let crossCredited = try #require(json["crossCredited"] as? [String: Any])
        #expect(Set(crossCredited.keys) == ["voiceWordsAsYou", "yourWordsAsVoices"])
        let latency = try #require(json["latency"] as? [String: Any])
        #expect(latency["maxLine"] as? Int == 6)
    }

    @Test func lineStatusesEncodeAsTheirSchemaNames() throws {
        let statuses: [TestCallLineStatus] = [.done, .skipped, .stopped, .notReached]
        let data = try MeetingCoding.encoder().encode(statuses)

        #expect(String(decoding: data, as: UTF8.self) == #"["done","skipped","stopped","notReached"]"#)
    }

    @Test func countsDeriveWER() throws {
        let wer = try #require(TestCallRecord.Counts(words: 157, substitutions: 6, deletions: 1, insertions: 3).wer)
        #expect(abs(wer - 10.0 / 157) < 1e-12)
        #expect(abs(wer - 0.0637) < 0.0001)
        #expect(TestCallRecord.Counts(words: 0, substitutions: 0, deletions: 0, insertions: 2).wer == nil)
        let role = TestCallRecord.RoleScore(role: .you, words: 48, substitutions: 1, deletions: 1, insertions: 0)
        #expect(role.counts == TestCallRecord.Counts(words: 48, substitutions: 1, deletions: 1, insertions: 0))
    }
}

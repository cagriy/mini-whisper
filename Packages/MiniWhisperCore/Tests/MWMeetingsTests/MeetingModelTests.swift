import Foundation
import MWTestSupport
import Testing

import MWMeetings

@Suite struct MeetingModelTests {
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func meetingJSONRoundTripsWithSchemaOne() throws {
        let meeting = MeetingFixtures.northwind().meeting
        let data = try MeetingCoding.encoder().encode(meeting)

        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: data) == meeting)
        let json = try object(data)
        #expect(json["schema"] as? Int == 1)
        #expect(json["mode"] as? String == "remote")
        #expect(json["engine"] as? String == "speechmatics_standard")
        #expect(json["startedAt"] as? String == "2026-11-09T14:30:00Z")
    }

    @Test func inRoomModeIsHyphenated() throws {
        let meeting = MeetingFixtures.make(mode: .inRoom).meeting
        #expect(try object(MeetingCoding.encoder().encode(meeting))["mode"] as? String == "in-room")
    }

    @Test func segmentEncodesAsOneLine() throws {
        let segment = Segment(
            speaker: 1, start: 1, end: 2.5, text: "First line\nsecond line",
            words: [Word(text: "First", start: 1, end: 1.4)], session: 2, providerLabel: "S1"
        )
        let data = try MeetingCoding.encoder().encode(segment)

        #expect(data.contains(0x0A) == false)
        #expect(try MeetingCoding.decoder().decode(Segment.self, from: data) == segment)
        let words = try #require(try object(data)["words"] as? [[String: Any]])
        #expect(words.first?["t"] as? String == "First")
        #expect(words.first?["s"] as? Double == 1)
        #expect(words.first?["e"] as? Double == 1.4)
    }

    @Test func speakerLabelKeepsProviderKeys() throws {
        let label = SpeakerLabel(id: 3, name: "Speaker 3", isUser: false, providerKeys: ["1:S1", "2:S2"])
        let data = try MeetingCoding.encoder().encode(label)

        #expect(try MeetingCoding.decoder().decode(SpeakerLabel.self, from: data) == label)
        #expect(try object(data)["providerKeys"] as? [String] == ["1:S1", "2:S2"])
    }
}

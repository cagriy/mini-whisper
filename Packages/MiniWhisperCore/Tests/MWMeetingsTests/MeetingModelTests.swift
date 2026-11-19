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

    @Test func silenceStopAbsentDecodesAsNil() throws {
        let data = try MeetingCoding.encoder().encode(MeetingFixtures.northwind().meeting)
        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: data).silenceStopSeconds == nil)
    }

    @Test func silenceStopRoundTrips() throws {
        let meeting = Meeting(
            title: "Zoom · 9 Nov 2026 11:00", startedAt: Date(timeIntervalSince1970: 1_794_222_000),
            mode: .remote, engine: .speechmaticsStandard, userName: "Alex", silenceStopSeconds: 120
        )
        let data = try MeetingCoding.encoder().encode(meeting)
        let decoded = try MeetingCoding.decoder().decode(Meeting.self, from: data)

        #expect(try object(data)["silenceStopSeconds"] as? Int == 120)
        #expect(decoded.silenceStopSeconds == 120)
        #expect(decoded == meeting)
    }

    @Test func silenceStopIsOmittedWhenUnset() throws {
        let json = try object(MeetingCoding.encoder().encode(MeetingFixtures.make().meeting))

        #expect(json.keys.contains("silenceStopSeconds") == false)
        #expect(json["schema"] as? Int == 1)
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

    @Test func billingWithoutReplacedCostDecodesAsZero() throws {
        let data = Data(#"{"engineSeconds":1,"diarizationSeconds":0,"costUSD":0.4}"#.utf8)
        let billing = try MeetingCoding.decoder().decode(Billing.self, from: data)

        #expect(billing == Billing(engineSeconds: 1, diarizationSeconds: 0, costUSD: 0.4))
        #expect(billing.replacedSummaryCostUSD == 0)
        #expect(throws: DecodingError.self) {
            try MeetingCoding.decoder().decode(Billing.self, from: Data(#"{"replacedSummaryCostUSD":0.1}"#.utf8))
        }
    }

    @Test func billingAlwaysEncodesReplacedCost() throws {
        #expect(try object(MeetingCoding.encoder().encode(Billing()))["replacedSummaryCostUSD"] as? Double == 0)

        let billing = Billing(engineSeconds: 60, costUSD: 0.4, replacedSummaryCostUSD: 0.03106)
        let data = try MeetingCoding.encoder().encode(billing)
        #expect(try object(data)["replacedSummaryCostUSD"] as? Double == 0.03106)
        #expect(try MeetingCoding.decoder().decode(Billing.self, from: data) == billing)
    }

    @Test func totalCostAddsBillingReplacedAndSummary() {
        var meeting = MeetingFixtures.northwind().meeting
        meeting.billing.replacedSummaryCostUSD = 0.02

        #expect(abs(meeting.totalCostUSD - (0.3665 + 0.02 + 0.03106)) < 1e-9)
        meeting.summary = nil
        #expect(abs(meeting.totalCostUSD - (0.3665 + 0.02)) < 1e-9)
    }

    // MARK: - Title

    private func meeting(title: String = "Zoom · 9 Nov 2026 11:00", byUser: Bool? = nil) -> Meeting {
        var meeting = MeetingFixtures.make(title: title).meeting
        meeting.titleByUser = byUser
        return meeting
    }

    @Test func aSummaryNamesAMeetingWhoseTitleIsTheApps() {
        var meeting = meeting(byUser: false)
        let named = meeting.name(after: "API Platform Options")
        #expect(named)
        #expect(meeting.title == "API Platform Options · 9 Nov 2026 11:00")
        #expect(meeting.titleByUser == false)

        // A regenerated summary names it again.
        let renamed = meeting.name(after: "Pricing")
        #expect(renamed)
        #expect(meeting.title == "Pricing · 9 Nov 2026 11:00")
    }

    @Test func aSummaryLeavesATitleTheUserGave() {
        var meeting = meeting(byUser: false)
        meeting.rename("Northwind sync")
        #expect(meeting.titleByUser == true)

        let named = meeting.name(after: "Pricing")
        #expect(!named)
        #expect(meeting.title == "Northwind sync")
    }

    @Test func aSummaryLeavesATestCallsTitle() {
        var meeting = meeting(title: "Test call · Standup", byUser: false)
        meeting.test = TestCallTag(scenarioID: "standup", revision: 1, scenarioTitle: "Standup")
        let named = meeting.name(after: "Pricing")
        #expect(!named)
        #expect(meeting.title == "Test call · Standup")
    }

    @Test func anOlderFileFollowsItsSummaryOnlyWhileItsTitleIsTheDefault() {
        var unnamed = meeting()
        let named = unnamed.name(after: "Pricing")
        #expect(named)
        #expect(unnamed.title == "Pricing · 9 Nov 2026 11:00")
        #expect(unnamed.titleByUser == false)

        var renamed = meeting(title: "Northwind sync")
        let changed = renamed.name(after: "Pricing")
        #expect(!changed)
        #expect(renamed.title == "Northwind sync")
    }

    @Test func aBlankSubjectChangesNothing() {
        var meeting = meeting(byUser: false)
        let named = meeting.name(after: "  ")
        #expect(!named)
        #expect(meeting.title == "Zoom · 9 Nov 2026 11:00")
    }

    @Test func titleByUserRoundTripsAndIsOmittedWhenUnset() throws {
        let unset = meeting()
        let unsetData = try MeetingCoding.encoder().encode(unset)
        #expect(try object(unsetData)["titleByUser"] == nil)
        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: unsetData).titleByUser == nil)

        let set = meeting(byUser: true)
        let data = try MeetingCoding.encoder().encode(set)
        #expect(try object(data)["titleByUser"] as? Bool == true)
        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: data) == set)
    }
}

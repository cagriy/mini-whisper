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

    @Test func billingWithoutNamingCostEncodesAsToday() throws {
        let data = try MeetingCoding.encoder().encode(Billing(engineSeconds: 60, costUSD: 0.4, replacedSummaryCostUSD: 0.03106))

        #expect(String(decoding: data, as: UTF8.self)
            == #"{"costUSD":0.4,"diarizationSeconds":0,"engineSeconds":60,"replacedSummaryCostUSD":0.03106}"#)
    }

    @Test func billingWithoutNamingCostDecodesAsZero() throws {
        let data = Data(#"{"engineSeconds":60,"diarizationSeconds":0,"costUSD":0.4,"replacedSummaryCostUSD":0.03106}"#.utf8)

        #expect(try MeetingCoding.decoder().decode(Billing.self, from: data).namingCostUSD == 0)
    }

    @Test func billingWritesAndRoundTripsANamingCost() throws {
        let billing = Billing(engineSeconds: 60, costUSD: 0.4, replacedSummaryCostUSD: 0.03106, namingCostUSD: 0.0125)
        let data = try MeetingCoding.encoder().encode(billing)

        #expect(try object(data)["namingCostUSD"] as? Double == 0.0125)
        #expect(try MeetingCoding.decoder().decode(Billing.self, from: data) == billing)
    }

    @Test func totalCostAddsBillingReplacedNamingAndSummary() {
        var meeting = MeetingFixtures.northwind().meeting
        meeting.billing.replacedSummaryCostUSD = 0.02
        meeting.billing.namingCostUSD = 0.0125

        #expect(abs(meeting.totalCostUSD - (0.3665 + 0.02 + 0.0125 + 0.03106)) < 1e-9)
        meeting.summary = nil
        #expect(abs(meeting.totalCostUSD - (0.3665 + 0.02 + 0.0125)) < 1e-9)
    }

    // MARK: - Timing

    /// The id in `meeting-v0.5.json`.
    private let v05 = UUID(uuidString: "5C0D1A2B-3E4F-4A5B-8C6D-7E8F9A0B1C2D")!

    @Test func aMeetingWithoutTimingEncodesAsToday() throws {
        let data = try MeetingCoding.encoder().encode(MeetingFixtures.make(id: v05).meeting)

        #expect(String(decoding: data, as: UTF8.self) == """
            {"app":"Zoom","billing":{"costUSD":0,"diarizationSeconds":0,"engineSeconds":0,"replacedSummaryCostUSD":0},\
            "durationSeconds":0,"engine":"speechmatics_standard","id":"\(v05.uuidString)","markers":[],"mode":"remote",\
            "schema":1,"speakers":[{"id":0,"isUser":true,"name":"Alex","providerKeys":[]}],\
            "startedAt":"2026-11-09T11:00:00Z","title":"Zoom · 9 Nov 2026 11:00","userName":"Alex"}
            """)
    }

    @Test func timingAndOffsetAbsentDecodeAsNil() throws {
        let url = try #require(Bundle.module.url(forResource: "meeting-v0.5", withExtension: "json", subdirectory: "Fixtures"))
        let meeting = try MeetingCoding.decoder().decode(Meeting.self, from: Data(contentsOf: url))

        #expect(meeting.utcOffsetSeconds == nil)
        #expect(meeting.timing == nil)
        #expect(meeting == MeetingFixtures.make(id: v05).meeting)
    }

    @Test func timingAndOffsetRoundTrip() throws {
        var meeting = MeetingFixtures.make(id: v05).meeting
        meeting.utcOffsetSeconds = 3600
        meeting.timing = MeetingTiming(
            transcriptDelay: DelayStats(median: 1, p90: 2, count: 5), summaryWaitSeconds: 7.5
        )
        let data = try MeetingCoding.encoder().encode(meeting)

        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: data) == meeting)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""timing":{"summaryWaitSeconds":7.5,"transcriptDelay":{"count":5,"median":1,"p90":2}}"#))
        #expect(json.contains(#""utcOffsetSeconds":3600"#))

        meeting.timing = MeetingTiming(summaryWaitSeconds: 4)
        let waitOnly = try MeetingCoding.encoder().encode(meeting)
        #expect(try MeetingCoding.decoder().decode(Meeting.self, from: waitOnly) == meeting)
        #expect(String(decoding: waitOnly, as: UTF8.self).contains(#""timing":{"summaryWaitSeconds":4}"#))
    }

    @Test func delayStatsTakeTheMedianAndTheNearestRankP90() {
        #expect(DelayStats(samples: [0.4, 1.2, 0.8, 2.0, 1.0]) == DelayStats(median: 1.0, p90: 2.0, count: 5))
        #expect(DelayStats(samples: [1, 2, 3, 4]) == DelayStats(median: 2.5, p90: 4, count: 4))
        #expect(DelayStats(samples: [3]) == DelayStats(median: 3, p90: 3, count: 1))
    }

    @Test func delayStatsOfNoSamplesIsNil() {
        #expect(DelayStats(samples: []) == nil)
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

    // MARK: - Voices

    private let alice = UUID(uuidString: "0B6F7C1E-2D3A-4B5C-8D9E-0F1A2B3C4D5E")!
    private let bob = UUID(uuidString: "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D")!

    @Test func aLabelFromAnOldFileHasNoVoiceFields() throws {
        let url = try #require(Bundle.module.url(forResource: "meeting-v0.5", withExtension: "json", subdirectory: "Fixtures"))
        let label = try #require(try MeetingCoding.decoder().decode(Meeting.self, from: Data(contentsOf: url)).speakers.first)

        #expect(label.person == nil)
        #expect(label.matches == [])
        #expect(label.rejected == [])
    }

    @Test func aLabelWithoutVoiceFieldsEncodesAsToday() throws {
        let data = try MeetingCoding.encoder().encode(SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"]))

        #expect(String(decoding: data, as: UTF8.self) == #"{"id":1,"isUser":false,"name":"Speaker 1","providerKeys":["1:A"]}"#)
    }

    @Test func aLabelWithAllThreeRoundTrips() throws {
        let label = SpeakerLabel(
            id: 2, name: "Alice", providerKeys: ["1:A", "2:B"], person: alice,
            matches: [NameMatch(key: "2:B", name: "Alice", person: alice, state: .applied, score: 0.83)],
            rejected: [bob]
        )
        let data = try MeetingCoding.encoder().encode(label)

        #expect(try MeetingCoding.decoder().decode(SpeakerLabel.self, from: data) == label)
        let json = try object(data)
        #expect(json["person"] as? String == alice.uuidString)
        #expect(json["rejected"] as? [String] == [bob.uuidString])
        #expect((json["matches"] as? [Any])?.count == 1)
    }

    @Test func nameMatchEncodesItsSixFields() throws {
        let match = NameMatch(key: "1:A", name: "Alice", person: alice, source: "voice", state: .suggested, score: 0.62)
        let data = try MeetingCoding.encoder().encode(match)

        #expect(String(decoding: data, as: UTF8.self) == """
            {"key":"1:A","name":"Alice","person":"\(alice.uuidString)","score":0.62,"source":"voice","state":"suggested"}
            """)
        #expect(try MeetingCoding.decoder().decode(NameMatch.self, from: data) == match)
        #expect(NameMatch(key: "1:A", name: "Alice", person: alice, state: .applied).source == "voice")
    }

    // MARK: - Naming

    private let segment = UUID(uuidString: "5C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F")!

    @Test func aConversationMatchRoundTripsWithEvidenceAndKind() throws {
        let match = NameMatch(
            key: "1:B", name: "Kate", person: nil, source: "conversation", state: .suggested,
            evidence: NameEvidence(segment: segment, time: 42.5, text: "Hi, I'm Kate from finance."),
            kind: "self_introduction"
        )
        let data = try MeetingCoding.encoder().encode(match)

        #expect(try MeetingCoding.decoder().decode(NameMatch.self, from: data) == match)
        let json = try object(data)
        #expect(json["kind"] as? String == "self_introduction")
        let evidence = try #require(json["evidence"] as? [String: Any])
        #expect(evidence["segment"] as? String == segment.uuidString)
        #expect(evidence["time"] as? Double == 42.5)
        #expect(evidence["text"] as? String == "Hi, I'm Kate from finance.")
    }

    @Test func aMatchWithoutEvidenceOmitsItAndDecodesAnOlderLine() throws {
        let json = try object(MeetingCoding.encoder().encode(
            NameMatch(key: "1:A", name: "Alice", person: alice, state: .applied, score: 0.83)
        ))
        #expect(json.keys.contains("evidence") == false)
        #expect(json.keys.contains("kind") == false)

        let older = Data("""
            {"key":"1:A","name":"Alice","person":"\(alice.uuidString)","score":0.62,"source":"voice","state":"suggested"}
            """.utf8)
        let decoded = try MeetingCoding.decoder().decode(NameMatch.self, from: older)
        #expect(decoded.evidence == nil)
        #expect(decoded.kind == nil)
        #expect(decoded == NameMatch(key: "1:A", name: "Alice", person: alice, state: .suggested, score: 0.62))
    }

    @Test func rejectedNamesAreEmptyWhenAbsentAndOmittedWhenEmpty() throws {
        let older = Data(#"{"id":1,"isUser":false,"name":"Speaker 1","providerKeys":["1:A"]}"#.utf8)
        #expect(try MeetingCoding.decoder().decode(SpeakerLabel.self, from: older).rejectedNames == [])

        let data = try MeetingCoding.encoder().encode(SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], rejectedNames: []))
        #expect(try object(data).keys.contains("rejectedNames") == false)
    }

    @Test func rejectedNamesRoundTrip() throws {
        let label = SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], rejectedNames: ["Kate", "Siân"])
        let data = try MeetingCoding.encoder().encode(label)

        #expect(try object(data)["rejectedNames"] as? [String] == ["Kate", "Siân"])
        #expect(try MeetingCoding.decoder().decode(SpeakerLabel.self, from: data) == label)
    }

    @Test func defaultNameIsSpeakerAndTheID() {
        #expect(SpeakerLabel.defaultName(3) == "Speaker 3")
    }

    @Test func meetingVoicesDecodesTheDesignsTwoShapes() throws {
        let vector = VoiceVector((0..<VoiceVector.dimension).map { Float(cos(Double($0) / 7)) / 11 })
        let base64 = String(String(decoding: try MeetingCoding.encoder().encode(vector), as: UTF8.self).dropFirst().dropLast())
        let local = Data("""
            {"schema":1,"route":"local","model":"wespeaker_v2",
             "keys":{"1:A":{"seconds":212.4,"vector":"\(base64)"},
                     "user":{"seconds":640.0,"vector":"\(base64)"}}}
            """.utf8)
        let speechmatics = Data("""
            {"schema":1,"route":"speechmatics","model":"standard",
             "keys":{"1:S2":{"seconds":88.1,"identifier":"opaque-identifier"}}}
            """.utf8)

        let localVoices = try MeetingCoding.decoder().decode(MeetingVoices.self, from: local)
        #expect(localVoices.schema == 1)
        #expect(localVoices.route == .local)
        #expect(localVoices.model == "wespeaker_v2")
        #expect(localVoices.keys["1:A"] == MeetingVoices.Entry(seconds: 212.4, vector: vector))
        #expect(localVoices.keys[MeetingVoices.userKey] == MeetingVoices.Entry(seconds: 640, vector: vector))
        #expect(MeetingVoices.userKey == "user")

        let speechmaticsVoices = try MeetingCoding.decoder().decode(MeetingVoices.self, from: speechmatics)
        #expect(speechmaticsVoices == MeetingVoices(
            route: .speechmatics, model: "standard",
            keys: ["1:S2": MeetingVoices.Entry(seconds: 88.1, identifier: "opaque-identifier")]
        ))

        for (voices, source) in [(localVoices, local), (speechmaticsVoices, speechmatics)] {
            let encoded = try MeetingCoding.encoder().encode(voices)
            #expect(try MeetingCoding.decoder().decode(MeetingVoices.self, from: encoded) == voices)
            #expect(try object(encoded) as NSDictionary == object(source) as NSDictionary)
        }
    }
}

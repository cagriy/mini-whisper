import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestSupport
import MWVoices

/// Accept, Dismiss, "Not <name>" and That's me on conversation matches, on stored meetings
/// (design §5 Control flow): R19–R21, R23, R29. The user is "Alex".
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerNamingActionsTests {
    // MARK: - Accept (R19)

    @Test func acceptRenamesAndLeavesNoConversationMatch() async throws {
        let harness = try await MeetingHarness()
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggested("Kate", "1:A")]),
        ])

        await harness.controller.acceptSuggestion(key: "1:A")

        #expect(try harness.stored().meeting.speakers.dropFirst() == [
            SpeakerLabel(id: 1, name: "Kate", providerKeys: ["1:A"]),
        ])
    }

    @Test func acceptMergesIntoASpeakerAlreadyOfThatName() async throws {
        let harness = try await MeetingHarness()
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Kate", providerKeys: ["1:A"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [suggested("Kate", "1:B")]),
        ])

        await harness.controller.acceptSuggestion(key: "1:B")

        let stored = try harness.stored()
        #expect(stored.meeting.speakers.dropFirst() == [SpeakerLabel(id: 1, name: "Kate", providerKeys: ["1:A", "1:B"])])
        #expect(stored.segments.map(\.speaker) == [1, 1])
    }

    @Test func acceptWithTheVoiceRouteLinksThePeopleEntryAndTeachesWithoutAnAcceptedLine() async throws {
        let harness = try await MeetingHarness.local()
        let kate = try await harness.remember("Kate Morgan", voice: .unit(3))
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggested("Kate Morgan", "1:A")]),
        ], sidecar: ["1:A": .init(seconds: 30, vector: .unit(5))])

        await harness.controller.acceptSuggestion(key: "1:A")

        #expect(try harness.stored().meeting.speakers.dropFirst() == [
            SpeakerLabel(id: 1, name: "Kate Morgan", providerKeys: ["1:A"], person: kate.id),
        ])
        #expect(await harness.voices?.store.people().map(\.id) == [kate.id])
        #expect(await harness.sample(of: kate.id)?.vector == .unit(5))
        #expect(try harness.matchLog().isEmpty)
    }

    // MARK: - Dismiss (R20)

    @Test func dismissRecordsTheNameAndTeachesNothing() async throws {
        let harness = try await MeetingHarness.local()
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggested("Kate", "1:A")]),
        ], sidecar: ["1:A": .init(seconds: 30, vector: .unit(5))])

        await harness.controller.dismissSuggestion(key: "1:A")

        #expect(try harness.stored().meeting.speakers.dropFirst() == [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], rejectedNames: ["Kate"]),
        ])
        #expect(try harness.matchLog().isEmpty)
    }

    // MARK: - Not <name> (R23)

    @Test func notRevertsTheWholeSpeakerAndRecordsTheName() async throws {
        let harness = try await MeetingHarness.local()
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Kate", providerKeys: ["1:A", "1:B"], matches: [applied("Kate", "1:A")]),
        ], sidecar: ["1:A": .init(seconds: 30, vector: .unit(5))])

        await harness.controller.rejectMatch(key: "1:A")

        let stored = try harness.stored()
        #expect(stored.meeting.speakers.dropFirst() == [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A", "1:B"], rejectedNames: ["Kate"]),
        ])
        #expect(stored.segments.map(\.speaker) == [1, 1])
        #expect(try harness.matchLog().isEmpty)
    }

    // MARK: - That's me (R21)

    @Test func thatsMeStoresTheSpellingAndWithdrawsEverySuggestionOfIt() async throws {
        let harness = try await MeetingHarness()
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggested("Neve", "1:A")]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [suggested("NÉVE", "1:B")]),
            SpeakerLabel(id: 3, name: "Speaker 3", providerKeys: ["1:C"], matches: [suggested("Kate", "1:C")]),
        ])

        await harness.controller.thatsMe(key: "1:A")

        #expect(await harness.config.load().meetingUserNameAliases == ["Neve"])
        #expect(try harness.stored().meeting.speakers.dropFirst() == [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"]),
            SpeakerLabel(id: 3, name: "Speaker 3", providerKeys: ["1:C"], matches: [suggested("Kate", "1:C")]),
        ])
    }

    @Test func thatsMeAddsNoSpellingAlreadyStoredIgnoringCaseAndDiacritics() async throws {
        let harness = try await MeetingHarness { $0.meetingUserNameAliases = ["neve"] }
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggested("Névé", "1:A")]),
        ])

        await harness.controller.thatsMe(key: "1:A")

        #expect(await harness.config.load().meetingUserNameAliases == ["neve"])
        #expect(try harness.stored().meeting.speakers.dropFirst() == [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"]),
        ])
    }

    @Test(arguments: ["9:Z", "1:A", "1:B", "1:C"])
    func thatsMeDoesNothingWithoutAConversationSuggestionOfAnotherName(key: String) async throws {
        let harness = try await MeetingHarness()
        let speakers = [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggested("ALEX", "1:A")]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [
                NameMatch(key: "1:B", name: "Bob", person: UUID(), state: .suggested, score: 0.6),
            ]),
            SpeakerLabel(id: 3, name: "Kate", providerKeys: ["1:C"], matches: [applied("Kate", "1:C")]),
        ]
        try await opened(harness, speakers)

        await harness.controller.thatsMe(key: key)

        #expect(await harness.config.load().meetingUserNameAliases.isEmpty)
        #expect(try harness.stored().meeting.speakers.dropFirst() == ArraySlice(speakers))
    }

    // MARK: - Logs (R29)

    @Test func actionLogsCarryTheActionAndCountsOnly() async throws {
        let sink = CapturingLogSink()
        let harness = try await MeetingHarness()
        try await opened(harness, [
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggested("Kate", "1:A")]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [suggested("Dan", "1:B")]),
            SpeakerLabel(id: 3, name: "Priya", providerKeys: ["1:C"], matches: [applied("Priya", "1:C")]),
            SpeakerLabel(id: 4, name: "Speaker 4", providerKeys: ["1:D"], matches: [suggested("Neve", "1:D")]),
            SpeakerLabel(id: 5, name: "Speaker 5", providerKeys: ["1:E"], matches: [suggested("neve", "1:E")]),
        ])

        try await logging(to: sink) {
            await harness.controller.acceptSuggestion(key: "1:A")
            await harness.controller.dismissSuggestion(key: "1:B")
            await harness.controller.rejectMatch(key: "1:C")
            await harness.controller.thatsMe(key: "1:D")
        }

        #expect(sink.records.filter { $0.category == "naming" }.map(\.message) == [
            "user action: accepted",
            "user action: dismissed",
            "user action: not",
            "user action: that's me, 2 withdrawn",
        ])
    }

    // MARK: - Helpers

    private static let evidence = UUID()

    private func suggested(_ name: String, _ key: String) -> NameMatch {
        NameMatch(
            key: key, name: name, person: nil, source: "conversation", state: .suggested,
            evidence: NameEvidence(segment: Self.evidence, time: 3, text: "Thanks, \(name)."), kind: "addressed"
        )
    }

    private func applied(_ name: String, _ key: String) -> NameMatch {
        NameMatch(
            key: key, name: name, person: nil, source: "conversation", state: .applied,
            evidence: NameEvidence(segment: Self.evidence, time: 3, text: "I'm \(name)."), kind: "self_introduction"
        )
    }

    /// A stored meeting with these speakers after the user, a segment per key, opened.
    private func opened(
        _ harness: MeetingHarness, _ speakers: [SpeakerLabel], sidecar: [String: MeetingVoices.Entry]? = nil
    ) async throws {
        try await harness.controller.open(harness.seedVoiced(speakers: speakers, sidecar: sidecar))
        await harness.waitFor(.state(.stopped))
    }
}

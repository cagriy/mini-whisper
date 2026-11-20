import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWTestSupport
import MWVoices

/// Forget on a meeting a session holds (design v8 §5 People actions; Failure cases "Forget while a
/// stored meeting is open"): its controller scrubs its own links, matches, rejections and sidecar,
/// and names stay as text (R21, R24).
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerVoiceScrubTests {
    private static let alice = UUID()
    private static let bob = UUID()

    /// A stored meeting, open: Alice linked on 1:A; Speaker 2 offered Bob on 1:B, having rejected
    /// Alice; Bob linked on 1:C; a sidecar holding all three keys.
    @discardableResult
    private func opened(_ harness: MeetingHarness) async throws -> UUID {
        let id = try await harness.seedVoiced(
            speakers: [
                SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: Self.alice),
                SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [
                    NameMatch(key: "1:B", name: "Bob", person: Self.bob, state: .suggested, score: 0.6),
                ], rejected: [Self.alice]),
                SpeakerLabel(id: 3, name: "Bob", providerKeys: ["1:C"], person: Self.bob),
            ],
            sidecar: [
                "1:A": .init(seconds: 20, vector: .unit(1)), "1:B": .init(seconds: 20, vector: .unit(2)),
                "1:C": .init(seconds: 20, vector: .unit(3)),
            ]
        )
        try await harness.controller.open(id)
        await harness.waitFor(.state(.stopped))
        return id
    }

    @Test func scrubbingAPersonClearsTheOpenMeetingAndItsSidecar() async throws {
        let harness = try await MeetingHarness.local()
        try await opened(harness)

        await harness.controller.scrubVoices(people: [Self.alice])

        let events = await harness.waitFor { $0.isVoiceData }
        #expect(events.last == .voiceData(active: false, keys: ["1:B", "1:C"]))
        let labels = await harness.waitForSpeakers { $0.named("Alice")?.person == nil }
        #expect(labels.dropFirst() == [
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [
                NameMatch(key: "1:B", name: "Bob", person: Self.bob, state: .suggested, score: 0.6),
            ]),
            SpeakerLabel(id: 3, name: "Bob", providerKeys: ["1:C"], person: Self.bob),
        ])
        #expect(try harness.stored().meeting.speakers == labels)
        #expect(Set(try #require(try harness.sidecar()).keys.keys) == ["1:B", "1:C"])
    }

    @Test func scrubbingEveryoneDeletesTheSidecar() async throws {
        let harness = try await MeetingHarness.local()
        try await opened(harness)

        await harness.controller.scrubVoices(people: nil)

        let events = await harness.waitFor { $0.isVoiceData }
        #expect(events.last == .voiceData(active: false, keys: []))
        let labels = try harness.stored().meeting.speakers
        #expect(labels.map(\.name) == ["Alex", "Alice", "Speaker 2", "Bob"])
        #expect(labels.allSatisfy { $0.person == nil && $0.matches.isEmpty && $0.rejected.isEmpty })
        #expect(harness.speakers == labels)
        #expect(try harness.sidecar() == nil)
        #expect(!FileManager.default.fileExists(atPath: try harness.sidecarURL().path))
    }

    @Test func otherPeopleAreLeftAlone() async throws {
        let harness = try await MeetingHarness.local()
        try await opened(harness)
        let before = try harness.stored()

        await harness.controller.scrubVoices(people: [UUID()])

        #expect(try harness.stored().meeting == before.meeting)
        #expect(Set(try #require(try harness.sidecar()).keys.keys) == ["1:A", "1:B", "1:C"])
    }

    @Test func anUnreadableSidecarOfAnOpenMeetingGoesWithItsPeople() async throws {
        let harness = try await MeetingHarness.local()
        let id = try await harness.seedVoiced(
            speakers: [SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: Self.alice)], sidecar: nil
        )
        let url = harness.store.directory.appendingPathComponent(id.uuidString).appendingPathComponent("voices.json")
        try Data("not json".utf8).write(to: url)
        try await harness.controller.open(id)
        await harness.waitFor(.state(.stopped))

        await harness.controller.scrubVoices(people: [Self.alice])

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try harness.stored().meeting.speakers.named("Alice")?.person == nil)
    }

    @Test func aStoppedMeetingTeachesNothingForgottenAfterwards() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.controller.stop(summarise: false)
        #expect(try harness.sidecar()?.keys["1:A"] != nil)

        await harness.controller.scrubVoices(people: nil)
        await harness.controller.rename(speaker: 1, to: "Alice")

        // The recogniser's vectors are not voice data any more.
        let alice = try #require(await harness.person(named: "Alice"))
        #expect(await harness.sample(of: alice.id) == nil)
        #expect(try harness.sidecar() == nil)
    }
}

import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestSupport
import MWVoices

/// Accept, Dismiss, "Not <name>", rename and what each teaches, live and on a stored meeting
/// (design v8 §5 Control flow: Accept / Dismiss / Not, Rename, Link, Stop, Open): R15, R17–R20,
/// R22, R23. Bob's voice is `.unit(5)` at a cosine of 0.6: a suggestion for speaker A, whose
/// arrival also shows A's voice has been embedded.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerVoiceLearningTests {
    private static let bobsVoice = voice([5: 0.6, 2: 0.8])

    // MARK: - Accept, Dismiss, Not (R15)

    @Test func acceptNamesLinksAndLearns() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: Self.bobsVoice)
        try await harness.suggestA()

        await harness.controller.acceptSuggestion(key: "1:A")

        let labels = await harness.waitForSpeakers { $0.named("Alice") != nil }
        #expect(labels.named("Alice") == SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: alice.id))
        #expect(try harness.stored().meeting.speakers == labels)
        let sample = try #require(await harness.sample(of: alice.id))
        #expect(sample.vector == .unit(5))
        #expect(isClose(sample.seconds, 6))
        #expect(try harness.matchLog().map(\.event) == [.suggested, .accepted])
        #expect(try harness.matchLog().last?.person == alice.id)
    }

    @Test func acceptOntoAnExistingSpeakerMerges() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: Self.bobsVoice)
        try await harness.start(.remote)
        harness.speak(0.09, for: 6)
        try await harness.deliverWords(label: "B", from: 0, to: 6)
        await harness.controller.rename(speaker: 1, to: "Alice")
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 6, to: 12)
        await harness.waitForSpeakers { $0.owning("1:A")?.matches.first?.state == .suggested }

        await harness.controller.acceptSuggestion(key: "1:A")

        let labels = await harness.waitForSpeakers { $0.count == 2 }
        #expect(labels.last == SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:B", "1:A"], person: alice.id))
        #expect(try harness.stored().segments.map(\.speaker) == [1, 1])
        let sample = try #require(await harness.sample(of: alice.id))
        #expect(sample.vector.cosine(voice([5: 1, 9: 1])) > 0.9999)
        #expect(isClose(sample.seconds, 12))
    }

    @Test func dismissReturnsToSpeakerNAndNeverOffersThatPersonAgain() async throws {
        let harness = try await MeetingHarness.local()
        let bob = try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.suggestA()

        await harness.controller.dismissSuggestion(key: "1:A")
        let labels = await harness.waitForSpeakers { $0.owning("1:A")?.matches.isEmpty == true }
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 6, to: 12)
        await harness.controller.stop(summarise: false)

        #expect(labels.owning("1:A") == SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], rejected: [bob.id]))
        #expect(try harness.stored().meeting.speakers.owning("1:A") == labels.owning("1:A"))
        #expect(try harness.matchLog().map(\.event) == [.suggested, .dismissed])
        #expect(await harness.sample(of: bob.id) == nil)
    }

    @Test func notOnASoleKeyReturnsTheVoiceToSpeakerN() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(5))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.waitForSpeakers { $0.named("Alice") != nil }

        await harness.controller.rejectMatch(key: "1:A")

        let labels = await harness.waitForSpeakers { $0.named("Alice") == nil }
        #expect(labels.owning("1:A") == SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], rejected: [alice.id]))
        #expect(try harness.stored().meeting.speakers == labels)
        #expect(try harness.matchLog().map(\.event) == [.applied, .rejected])
    }

    @Test func notOnOneOfSeveralKeysMovesItsUnpinnedSegmentsToANewSpeaker() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(5))
        try await harness.start(.remote)
        harness.speak(0.09, for: 6)
        try await harness.deliverWords(label: "B", from: 0, to: 6)
        await harness.controller.rename(speaker: 1, to: "Alice")
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 6, to: 12)
        await harness.waitForSpeakers { $0.named("Alice")?.providerKeys == ["1:B", "1:A"] }
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 12, to: 18)
        await harness.controller.stop(summarise: false)
        let pinned = try #require(try harness.stored().segments.first { $0.providerLabel == "A" })
        await harness.controller.reassign(segment: pinned.id, to: 1)

        await harness.controller.rejectMatch(key: "1:A")

        let labels = await harness.waitForSpeakers { $0.count == 3 }
        #expect(labels.dropFirst() == [
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:B"], person: alice.id),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:A"], rejected: [alice.id]),
        ])
        let segments = try harness.stored().segments
        #expect(segments.map(\.speaker) == [1, 1, 2])
        #expect(segments[1].id == pinned.id)
        #expect(harness.seen.contains(.segmentUpdated(segments[2])))
        let sample = try #require(await harness.sample(of: alice.id))
        #expect(sample.vector == .unit(9))
        #expect(isClose(sample.seconds, 6))
    }

    @Test func aMatchLogThatCannotBeWrittenIsLoggedAndTheActionStands() async throws {
        let logs = CapturingLogSink()
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: Self.bobsVoice)
        try FileManager.default.createDirectory(
            at: harness.directory.file("voice-matches.jsonl"), withIntermediateDirectories: false
        )

        try await logging(to: logs) {
            try await harness.suggestA()
            await harness.controller.acceptSuggestion(key: "1:A")
            await harness.controller.stop(summarise: false)
        }

        #expect(try harness.stored().meeting.speakers.named("Alice")?.person == alice.id)
        #expect(await harness.sample(of: alice.id) != nil)
        #expect(harness.controller.state == .stopped)
        #expect(logs.lines.contains { $0.hasPrefix("WARNING voice match log not written: ") })
    }

    // MARK: - Rename (R17, R18)

    @Test func renameLinksAndLearns() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.suggestA()

        await harness.controller.rename(speaker: 1, to: "Alice")

        let alice = try #require(await harness.person(named: "Alice"))
        let label = try #require(await harness.waitForSpeakers { $0.named("Alice")?.person != nil }.named("Alice"))
        #expect(label.person == alice.id)
        #expect(label.matches.isEmpty)
        #expect(try harness.stored().meeting.speakers.named("Alice") == label)
        let sample = try #require(await harness.sample(of: alice.id))
        #expect(sample.vector == .unit(5))
        #expect(isClose(sample.seconds, 6))
    }

    @Test func renameOntoAPeopleNameIsThatPerson() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(9))
        try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.suggestA()

        await harness.controller.rename(speaker: 1, to: " Alice ")

        await harness.waitForSpeakers { $0.named("Alice")?.person == alice.id }
        let people = try #require(harness.voices).store
        #expect(await people.people().map(\.name).sorted() == ["Alice", "Bob"])
        #expect(await people.person(alice.id)?.local.map(\.vector) == [.unit(9), .unit(5)])
    }

    @Test func renameToSpeakerNNeverCreatesAPersonAndClearsTheLink() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.suggestA()
        await harness.controller.rename(speaker: 1, to: "Alice")
        let alice = try #require(await harness.person(named: "Alice"))

        await harness.controller.rename(speaker: 1, to: "Speaker 7")

        let label = try #require(harness.controller.meeting?.speakers.named("Speaker 7"))
        #expect(label.person == nil)
        #expect(try harness.stored().meeting.speakers.named("Speaker 7") == label)
        #expect(await harness.person(named: "Speaker 7") == nil)
        #expect(await harness.sample(of: alice.id) == nil)
    }

    @Test func renameAwayFromASuggestionRejectsItsPersonAndLogsRenamed() async throws {
        let harness = try await MeetingHarness.local()
        let bob = try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.suggestA()

        await harness.controller.rename(speaker: 1, to: "Carol")

        let label = try #require(await harness.waitForSpeakers { $0.named("Carol")?.person != nil }.named("Carol"))
        #expect(label.rejected == [bob.id])
        #expect(label.matches.isEmpty)
        #expect(try harness.matchLog().map(\.event) == [.suggested, .renamed])
        #expect(try harness.matchLog().last?.person == bob.id)
        #expect(try harness.matchLog().last?.key == "1:A")
    }

    @Test func nothingIsLearnedWithTheSwitchOff() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.suggestA()
        try await harness.config.update { @Sendable in $0.voice.localEnabled = false }

        await harness.controller.rename(speaker: 1, to: "Alice")
        await harness.controller.stop(summarise: false)

        #expect(await harness.person(named: "Alice") == nil)
        #expect(try harness.stored().meeting.speakers.named("Alice")?.person == nil)
        #expect(try harness.matchLog().map(\.event) == [.suggested])
        #expect(try harness.sidecar() == nil)
    }

    @Test func anAppliedNameTeachesNothing() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(5))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.waitForSpeakers { $0.named("Alice") != nil }

        await harness.controller.rename(speaker: 1, to: "Alice")
        await harness.controller.stop(summarise: false)

        #expect(await harness.sample(of: alice.id) == nil)
        #expect(try harness.stored().meeting.speakers.named("Alice")?.person == nil)
    }

    @Test func aRenameBeforeEnoughSpeechLearnsAtStop() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.start(.remote)
        harness.speak(0.05, for: 3)
        try await harness.deliverWords(label: "A", from: 0, to: 3)
        await harness.controller.rename(speaker: 1, to: "Alice")
        harness.speak(0.05, for: 3)
        try await harness.deliverWords(label: "A", from: 3, to: 6)

        await harness.controller.stop(summarise: false)

        let alice = try #require(await harness.person(named: "Alice"))
        let sample = try #require(await harness.sample(of: alice.id))
        #expect(sample.vector == .unit(5))
        #expect(isClose(sample.seconds, 6))
    }

    @Test func relinkingRemovesThePreviousPersonsSample() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.suggestA()
        await harness.controller.rename(speaker: 1, to: "Alice")
        let alice = try #require(await harness.person(named: "Alice"))
        #expect(await harness.sample(of: alice.id) != nil)

        await harness.controller.rename(speaker: 1, to: "Carol")

        let carol = try #require(await harness.person(named: "Carol"))
        #expect(await harness.sample(of: alice.id) == nil)
        #expect(await harness.sample(of: carol.id)?.vector == .unit(5))
    }

    // MARK: - The user's voice (R19)

    @Test func theUsersMicrophoneVoiceIsLearnedAtStopInARemoteMeeting() async throws {
        let first = try await MeetingHarness.local()
        try await first.start(.remote)
        first.speakAsUser(for: 6)
        try await first.deliverWords(label: "U", from: 0, to: 6)
        await first.controller.stop(summarise: false)

        let people = try await #require(first.voices).store.people()
        let user = try #require(people.first)
        #expect(people.count == 1)
        #expect(user.isUser)
        #expect(user.name == "Alex")
        #expect(user.local.map(\.meeting) == [try #require(first.controller.meeting?.id)])
        #expect(user.local.first?.vector == (try first.sidecar())?.keys[MeetingVoices.userKey]?.vector)
        #expect(try first.stored().meeting.speakers.first?.person == user.id)

        let second = try await MeetingHarness.local()
        let known = try await second.remember("Alex", voice: .unit(40), isUser: true)
        try await second.start(.remote)
        second.speakAsUser(for: 6)
        try await second.deliverWords(label: "U", from: 0, to: 6)
        await second.controller.stop(summarise: false)

        let again = try await #require(second.voices).store.people()
        #expect(again.map(\.id) == [known.id])
        #expect(again.first?.local.count == 2)
    }

    @Test func lessThanTheMinimumSpeechTeachesNoUserVoice() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.start(.remote)
        harness.speakAsUser(for: 4)
        try await harness.deliverWords(label: "U", from: 0, to: 4)

        await harness.controller.stop(summarise: false)

        #expect(await harness.voices?.store.people().isEmpty == true)
        #expect(try harness.stored().meeting.speakers.first?.person == nil)
        #expect(isClose(try harness.sidecar()?.keys[MeetingVoices.userKey]?.seconds, 4))
    }

    @Test func renamingASpeakerToTheUserInTheRoomTeachesTheUser() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.start(.inRoom)
        harness.speak(0.05, for: 6, mode: .inRoom)
        try await harness.deliverWords(label: "A", from: 0, to: 6)

        await harness.controller.rename(speaker: 1, to: "Alex")
        await harness.controller.stop(summarise: false)

        let user = try #require(await harness.voices?.store.people().first)
        #expect(user.isUser)
        #expect(user.local.map(\.vector) == [.unit(5)])
        #expect(try harness.stored().meeting.speakers == [
            SpeakerLabel(id: 0, name: "Alex", isUser: true, providerKeys: ["1:A"], person: user.id),
        ])
    }

    @Test func lastHeardIsSetForLinkedAndAppliedPeopleAtStop() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(9))
        let bob = try await harness.remember("Bob", voice: Self.bobsVoice)
        try await harness.start(.remote)
        harness.speak(0.09, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.waitForSpeakers { $0.named("Alice") != nil }
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "B", from: 6, to: 12)
        await harness.waitForSpeakers { $0.owning("1:B")?.matches.isEmpty == false }
        harness.speak(0.07, for: 6)
        try await harness.deliverWords(label: "C", from: 12, to: 18)
        await harness.controller.rename(speaker: 3, to: "Carol")
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 30)

        await harness.controller.stop(summarise: false)

        let heard = MeetingHarness.wallStart.addingTimeInterval(30)
        let people = try #require(harness.voices).store
        #expect(await people.person(alice.id)?.lastHeard == heard)
        #expect(await harness.person(named: "Carol")?.lastHeard == heard)
        #expect(await people.person(bob.id)?.lastHeard == nil)
    }

    // MARK: - Stored meetings (R22)

    @Test func aStoredMeetingEmitsItsVoiceDataAndLearnsFromItsSidecar() async throws {
        let harness = try await MeetingHarness.local()
        let id = try await harness.seedVoiced(
            speakers: [SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"])],
            sidecar: ["1:A": .init(seconds: 30, vector: .unit(5))]
        )

        try await harness.controller.open(id)
        let events = await harness.waitFor(.state(.stopped))
        await harness.controller.rename(speaker: 1, to: "Alice")

        #expect(events.contains(.voiceData(active: false, keys: ["1:A"])))
        let alice = try #require(await harness.person(named: "Alice"))
        let sample = try #require(await harness.sample(of: alice.id))
        #expect(sample.meeting == id)
        #expect(sample.vector == .unit(5))
        #expect(sample.seconds == 30)
        #expect(try harness.stored().meeting.speakers.named("Alice")?.person == alice.id)
    }

    @Test func aStoredMeetingWithoutASidecarLearnsNothing() async throws {
        let harness = try await MeetingHarness.local()
        let id = try await harness.seedVoiced(
            speakers: [SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"])], sidecar: nil
        )

        try await harness.controller.open(id)
        let events = await harness.waitFor(.state(.stopped))
        await harness.controller.rename(speaker: 1, to: "Alice")

        #expect(!events.contains { $0.isVoiceData })
        #expect(await harness.voices?.store.people().isEmpty == true)
        #expect(try harness.stored().meeting.speakers.named("Alice")?.person == nil)
    }

    @Test func actionsOnAStoredMeetingPersist() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(3))
        let bob = try await harness.remember("Bob", voice: .unit(4))
        let carol = try await harness.remember("Carol", voice: .unit(6))
        let id = try await harness.seedVoiced(
            speakers: [
                SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [
                    NameMatch(key: "1:A", name: "Alice", person: alice.id, state: .suggested, score: 0.6),
                ]),
                SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [
                    NameMatch(key: "1:B", name: "Bob", person: bob.id, state: .suggested, score: 0.55),
                ]),
                SpeakerLabel(id: 3, name: "Carol", providerKeys: ["1:C"], matches: [
                    NameMatch(key: "1:C", name: "Carol", person: carol.id, state: .applied, score: 0.8),
                ]),
            ],
            sidecar: [
                "1:A": .init(seconds: 10, vector: .unit(5)), "1:B": .init(seconds: 10, vector: .unit(7)),
                "1:C": .init(seconds: 10, vector: .unit(9)),
            ]
        )
        try await harness.controller.open(id)

        await harness.controller.acceptSuggestion(key: "1:A")
        await harness.controller.dismissSuggestion(key: "1:B")
        await harness.controller.rejectMatch(key: "1:C")

        #expect(try harness.stored().meeting.speakers.dropFirst() == [
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: alice.id),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], rejected: [bob.id]),
            SpeakerLabel(id: 3, name: "Speaker 3", providerKeys: ["1:C"], rejected: [carol.id]),
        ])
        #expect(try harness.matchLog().map(\.event) == [.accepted, .dismissed, .rejected])
        #expect(try harness.matchLog().allSatisfy { $0.meeting == id })
        #expect(await harness.sample(of: alice.id)?.vector == .unit(5))
    }
}

// MARK: - Helpers

extension MeetingHarness {
    /// A remote meeting where speaker A's six seconds of `.unit(5)` stand as a suggestion.
    func suggestA() async throws {
        try await start(.remote)
        speak(0.05, for: 6)
        try await deliverWords(label: "A", from: 0, to: 6)
        await waitForSpeakers { $0.owning("1:A")?.matches.first?.state == .suggested }
    }

    func person(named name: String) async -> Person? {
        await voices?.store.people().first { $0.name == name }
    }

    /// The person's local sample from this harness's meeting.
    func sample(of person: UUID) async -> LocalSample? {
        guard let id = controller.meeting?.id else { return nil }
        return await voices?.store.person(person)?.local.first { $0.meeting == id }
    }

    /// A stored AssemblyAI meeting with these speakers after the user, a segment per key, and a
    /// local sidecar of `sidecar` when given.
    func seedVoiced(speakers: [SpeakerLabel], sidecar: [String: MeetingVoices.Entry]?) async throws -> UUID {
        var loaded = MeetingFixtures.make(engine: .assemblyaiPro)
        loaded.meeting.speakers += speakers
        loaded.segments = speakers.flatMap { speaker in
            speaker.providerKeys.map { key in
                Segment(speaker: speaker.id, start: 0, end: 6, text: "secret", session: 1, providerLabel: String(key.dropFirst(2)))
            }
        }
        let id = try await seed(loaded)
        if let sidecar {
            try await store.writeVoices(MeetingVoices(route: .local, model: "wespeaker_v2", keys: sidecar), of: id)
        }
        return id
    }
}

import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestSupport
import MWVoices

/// The Speechmatics route in a meeting (design v8 §5 Control flow: Start, Segment arrives,
/// Link, SpeakersResult, Identifier ignored, Stop): R2, R3, R10–R13, R19–R21, R27. A
/// session-limit warning rolls over at once, so it opens the next session without the clock.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerSpeechmaticsVoiceTests {
    private static let notice = "Speechmatics ignored some remembered voices. Rename those speakers to learn them again."

    // MARK: - Enrolment (R2, R10)

    @Test func withTheSwitchOffStartRecognitionIsUnchanged() async throws {
        let harness = try await MeetingHarness.speechmatics(on: false)
        try await harness.rememberSpeechmatics("Bob", identifier: "id-bob")

        try await harness.start(.remote)
        await harness.waitFor(.state(.recording))

        #expect(harness.engines.calls.map(\.voices) == [nil])
        #expect(!harness.seen.contains { $0.isVoiceData })
    }

    @Test func theTiersPeopleAreEnrolledNewestHeardFirst() async throws {
        let harness = try await MeetingHarness.speechmatics { $0.voice.speechmaticsSensitivity = 0.7 }
        let ann = try await harness.rememberSpeechmatics("Ann", identifier: "id-ann", heard: -7_200)
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob", heard: -3_600)
        try await harness.rememberSpeechmatics("Cid", identifier: "id-cid", tier: "enhanced")

        try await harness.start(.remote)

        #expect(harness.engines.calls.map(\.voices) == [VoiceSessionConfig(
            speakers: [
                .init(label: SpeechmaticsEnrolment.label(for: bob.id), identifier: "id-bob"),
                .init(label: SpeechmaticsEnrolment.label(for: ann.id), identifier: "id-ann"),
            ],
            sensitivity: 0.7
        )])
        #expect(await harness.waitFor(.state(.recording)).contains(.voiceData(active: true, keys: [])))
    }

    @Test func theEnrolmentIsRebuiltAtEverySessionOpen() async throws {
        let harness = try await MeetingHarness.speechmatics()
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob", heard: -3_600)
        try await harness.start(.remote)
        try await harness.deliverWords(label: "S1", from: 0, to: 6)
        await harness.controller.rename(speaker: 1, to: "Alice")
        try harness.sink(1).onSpeakers([ProviderSpeaker(label: "S1", identifiers: ["id-alice"])])
        try await harness.settle()
        try await harness.config.update { @Sendable in $0.voice.speechmaticsSensitivity = 0.6 }
        _ = await harness.tick(to: 1)
        _ = await harness.tick(to: 2)

        try harness.sink(1).onSessionLimit(.warning)

        let alice = try #require(await harness.person(named: "Alice"))
        #expect(harness.engines.calls.count == 2)
        #expect(harness.engines.calls.last?.voices == VoiceSessionConfig(
            speakers: [
                .init(label: SpeechmaticsEnrolment.label(for: alice.id), identifier: "id-alice"),
                .init(label: SpeechmaticsEnrolment.label(for: bob.id), identifier: "id-bob"),
            ],
            sensitivity: 0.6
        ))
    }

    // MARK: - mw: labels (R11)

    @Test func aKnownLabelIsSuggestedUntilTrusted() async throws {
        let harness = try await MeetingHarness.speechmatics()
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob")
        let label = SpeechmaticsEnrolment.label(for: bob.id)

        try await harness.start(.remote)
        try await harness.deliverWords(label: label, from: 0, to: 6)

        let labels = await harness.waitForSpeakers { $0.owning("1:\(label)")?.matches.isEmpty == false }
        #expect(labels.owning("1:\(label)") == SpeakerLabel(
            id: 1, name: "Speaker 1", providerKeys: ["1:\(label)"],
            matches: [NameMatch(key: "1:\(label)", name: "Bob", person: bob.id, state: .suggested)]
        ))
        let entry = try #require(try harness.matchLog().first)
        #expect(entry.event == .suggested)
        #expect(entry.route == .speechmatics)
        #expect(entry.score == nil)
    }

    @Test func aTrustedPersonIsApplied() async throws {
        let harness = try await MeetingHarness.speechmatics()
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob", trusted: true)
        let label = SpeechmaticsEnrolment.label(for: bob.id)

        try await harness.start(.remote)
        try await harness.deliverWords(label: label, from: 0, to: 6)

        let labels = await harness.waitForSpeakers { $0.named("Bob") != nil }
        #expect(labels.named("Bob")?.matches == [NameMatch(key: "1:\(label)", name: "Bob", person: bob.id, state: .applied)])
        #expect(try harness.matchLog().map(\.event) == [.applied])
    }

    @Test func anUnknownMwLabelIsAnOrdinarySpeaker() async throws {
        let harness = try await MeetingHarness.speechmatics()
        try await harness.rememberSpeechmatics("Bob", identifier: "id-bob", trusted: true)
        let stranger = SpeechmaticsEnrolment.label(for: UUID())

        try await harness.start(.remote)
        try await harness.deliverWords(label: stranger, from: 0, to: 6)
        await harness.controller.stop(summarise: false)

        #expect(try harness.stored().meeting.speakers.owning("1:\(stranger)") == SpeakerLabel(
            id: 1, name: "Speaker 1", providerKeys: ["1:\(stranger)"]
        ))
        #expect(try harness.matchLog().isEmpty)
    }

    // MARK: - Identifiers and links (R12, R19, R20)

    @Test func speakersResultStoresIdentifiersPerKey() async throws {
        let harness = try await MeetingHarness.speechmatics()
        try await harness.start(.remote)
        try await harness.deliverWords(label: "S1", from: 0, to: 6)
        try await harness.deliverWords(label: "S2", from: 6, to: 9)
        try harness.sink(1).onSpeakers([
            ProviderSpeaker(label: "S1", identifiers: ["id-1", "id-1b"]), ProviderSpeaker(label: "S2", identifiers: ["id-2"]),
        ])
        try harness.sink(1).onSessionLimit(.warning)
        try await harness.deliverWords(session: 2, label: "S1", from: 0, to: 4)
        try harness.sink(2).onSpeakers([ProviderSpeaker(label: "S1", identifiers: ["id-3"])])

        await harness.controller.stop(summarise: false)

        let sidecar = try #require(try harness.sidecar())
        #expect(sidecar.keys.mapValues(\.identifier) == ["1:S1": "id-1", "1:S2": "id-2", "2:S1": "id-3"])
    }

    @Test func aLiveLinkRequestsSpeakersAndLearnsTheIdentifier() async throws {
        let harness = try await MeetingHarness.speechmatics()
        try await harness.start(.remote)
        try await harness.deliverWords(label: "S1", from: 0, to: 6)

        await harness.controller.rename(speaker: 1, to: "Alice")
        #expect(harness.engines.engines.first?.commands == [.requestSpeakers])
        try harness.sink(1).onSpeakers([ProviderSpeaker(label: "S1", identifiers: ["id-alice"])])
        try await harness.settle()

        let alice = try #require(await harness.person(named: "Alice"))
        #expect(alice.speechmatics["standard"]?.identifier == "id-alice")
        #expect(alice.speechmatics["standard"]?.meeting == harness.controller.meeting?.id)
        #expect(alice.speechmaticsTrusted)
    }

    @Test func acceptLearnsTheIdentifierOfTheKeyWithTheMostSpeech() async throws {
        let harness = try await MeetingHarness.speechmatics()
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob")
        let label = SpeechmaticsEnrolment.label(for: bob.id)
        try await harness.start(.remote)
        try await harness.deliverWords(label: label, from: 0, to: 8)
        await harness.waitForSpeakers { $0.owning("1:\(label)")?.matches.isEmpty == false }
        try await harness.deliverWords(label: "S2", from: 8, to: 11)
        try harness.sink(1).onSpeakers([
            ProviderSpeaker(label: label, identifiers: ["id-long"]), ProviderSpeaker(label: "S2", identifiers: ["id-short"]),
        ])
        try await harness.settle()
        await harness.controller.rename(speaker: 2, to: "Bob")
        #expect(await harness.person(named: "Bob")?.speechmatics["standard"]?.identifier == "id-short")

        await harness.controller.acceptSuggestion(key: "1:\(label)")

        let labels = await harness.waitForSpeakers { $0.count == 2 }
        #expect(labels.named("Bob")?.providerKeys == ["1:S2", "1:\(label)"])
        #expect(await harness.person(named: "Bob")?.speechmatics["standard"]?.identifier == "id-long")
        #expect(harness.engines.engines.first?.commands == [.requestSpeakers, .requestSpeakers])
    }

    @Test func notOnASpeechmaticsMatchResetsTrust() async throws {
        let harness = try await MeetingHarness.speechmatics()
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob", trusted: true)
        let label = SpeechmaticsEnrolment.label(for: bob.id)
        try await harness.start(.remote)
        try await harness.deliverWords(label: label, from: 0, to: 6)
        await harness.waitForSpeakers { $0.named("Bob") != nil }

        await harness.controller.rejectMatch(key: "1:\(label)")

        #expect(await harness.person(named: "Bob")?.speechmaticsTrusted == false)
        #expect(try harness.matchLog().map(\.event) == [.applied, .rejected])
    }

    @Test func theGateBoundLabelTeachesTheUserAtStop() async throws {
        let harness = try await MeetingHarness.speechmatics()
        try await harness.start(.remote)
        harness.speakAsUser(for: 6)
        try await harness.deliverWords(label: "S1", from: 0, to: 6)
        try harness.sink(1).onSpeakers([ProviderSpeaker(label: "S1", identifiers: ["id-me"])])

        await harness.controller.stop(summarise: false)

        let user = try #require(await harness.voices?.store.people().first)
        #expect(user.isUser)
        #expect(user.name == "Alex")
        #expect(user.speechmatics["standard"]?.identifier == "id-me")
        #expect(try harness.stored().meeting.speakers.first == SpeakerLabel(
            id: 0, name: "Alex", isUser: true, providerKeys: ["1:S1"], person: user.id
        ))
    }

    @Test func theSidecarRecordsIdentifiersNeverAudio() async throws {
        let harness = try await MeetingHarness.speechmatics()
        try await harness.start(.remote)
        try await harness.deliverWords(label: "S1", from: 0, to: 6)
        try await harness.deliverWords(label: "S2", from: 6, to: 9)
        try harness.sink(1).onSpeakers([
            ProviderSpeaker(label: "S1", identifiers: ["id-1"]), ProviderSpeaker(label: "S2", identifiers: ["id-2"]),
        ])

        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        let sidecar = try #require(try harness.sidecar())
        #expect(sidecar.route == .speechmatics)
        #expect(sidecar.model == "standard")
        #expect(sidecar.keys.mapValues(\.identifier) == ["1:S1": "id-1", "1:S2": "id-2"])
        #expect(sidecar.keys.values.allSatisfy { $0.vector == nil })
        #expect(isClose(sidecar.keys["1:S1"]?.seconds, 6))
        #expect(isClose(sidecar.keys["1:S2"]?.seconds, 3))
        #expect(harness.seen.contains(.voiceData(active: true, keys: ["1:S1", "1:S2"])))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: harness.sidecarURL())) as? [String: Any])
        let entries = try #require(json["keys"] as? [String: [String: Any]])
        #expect(entries.values.allSatisfy { Set($0.keys) == ["seconds", "identifier"] })
    }

    // MARK: - Ignored identifiers (R13)

    @Test func anIgnoredIdentifierIsDroppedAndNoticedOnce() async throws {
        let harness = try await MeetingHarness.speechmatics()
        let ann = try await harness.rememberSpeechmatics("Ann", identifier: "id-ann")
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob")
        try await harness.start(.remote)

        try harness.sink(1).onIdentifierIgnored(label: SpeechmaticsEnrolment.label(for: bob.id), identifier: "id-bob")
        try harness.sink(1).onIdentifierIgnored(label: SpeechmaticsEnrolment.label(for: ann.id), identifier: "id-ann")
        try await harness.settle()
        try harness.sink(1).onSessionLimit(.warning)

        #expect(harness.seen.filter { $0 == .notice(Self.notice) }.count == 1)
        #expect(await harness.person(named: "Bob")?.speechmatics.isEmpty == true)
        #expect(await harness.person(named: "Ann")?.speechmatics.isEmpty == true)
        #expect(harness.engines.calls.last?.voices == VoiceSessionConfig(speakers: [], sensitivity: 0.8))
    }

    @Test func anUnparsedWarningOnlyNotices() async throws {
        let harness = try await MeetingHarness.speechmatics()
        try await harness.rememberSpeechmatics("Bob", identifier: "id-bob")
        try await harness.start(.remote)

        try harness.sink(1).onIdentifierIgnored(label: nil, identifier: nil)

        await harness.waitFor(.notice(Self.notice))
        #expect(await harness.person(named: "Bob")?.speechmatics["standard"]?.identifier == "id-bob")
    }

    // MARK: - Switch (R3) and logs (R27)

    @Test func switchedOffMidMeetingTheNextSessionEnrolsNoOneAndMwLabelsStaySpeakerN() async throws {
        let harness = try await MeetingHarness.speechmatics()
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob", trusted: true)
        let label = SpeechmaticsEnrolment.label(for: bob.id)
        try await harness.start(.remote)
        try await harness.config.update { @Sendable in $0.voice.speechmaticsEnabled = false }
        _ = await harness.tick(to: 1)
        _ = await harness.tick(to: 2)

        try harness.sink(1).onSessionLimit(.warning)
        try await harness.deliverWords(label: label, from: 0, to: 6)
        try await harness.deliverWords(session: 2, label: label, from: 0, to: 6)
        await harness.controller.stop(summarise: false)

        #expect(harness.engines.calls.map { $0.voices == nil } == [false, true])
        let speakers = try harness.stored().meeting.speakers
        #expect(speakers.map(\.name) == ["Alex", "Speaker 1", "Speaker 2"])
        #expect(speakers.allSatisfy { $0.matches.isEmpty })
        #expect(try harness.matchLog().isEmpty)
        #expect(try harness.sidecar() == nil)
    }

    @Test func logsNeverCarryIdentifiersOrNames() async throws {
        let logs = CapturingLogSink()
        let harness = try await MeetingHarness.speechmatics()
        let bob = try await harness.rememberSpeechmatics("Bob", identifier: "id-bob", trusted: true)
        let ann = try await harness.rememberSpeechmatics("Ann", identifier: "id-ann")
        let label = SpeechmaticsEnrolment.label(for: bob.id)

        try await logging(to: logs) {
            try await harness.start(.remote)
            try await harness.deliverWords(label: label, from: 0, to: 6)
            try await harness.deliverWords(label: "S2", from: 6, to: 9)
            await harness.controller.rename(speaker: 2, to: "Carol")
            try harness.sink(1).onSpeakers([ProviderSpeaker(label: "S2", identifiers: ["id-carol"])])
            try harness.sink(1).onIdentifierIgnored(label: SpeechmaticsEnrolment.label(for: ann.id), identifier: "id-ann")
            await harness.waitFor(.notice(Self.notice))
            await harness.controller.stop(summarise: false)
        }

        let voiceLines = logs.records.filter { $0.category == "voice" }.map(\.message)
        let short = String(bob.id.uuidString.prefix(8)).lowercased()
        #expect(voiceLines.contains("match 1:mw:\(short) sure, person \(short)"))
        #expect(voiceLines.contains("speechmatics dropped 1 identifier (standard)"))
        let forbidden = [
            "Bob", "Ann", "Carol", "Alex", "secret", "id-bob", "id-ann", "id-carol",
            bob.id.uuidString, bob.id.uuidString.lowercased(), ann.id.uuidString.lowercased(),
        ]
        #expect(!logs.lines.contains { line in forbidden.contains { line.contains($0) } })
    }
}

// MARK: - Helpers

extension MeetingHarness {
    /// The Speechmatics route's setting: a Speechmatics Standard meeting with its switch `on`.
    static func speechmatics(
        on: Bool = true, _ configure: @escaping @Sendable (inout Config) -> Void = { _ in }
    ) async throws -> MeetingHarness {
        try await MeetingHarness.local(engine: .speechmaticsStandard, on: false) {
            $0.voice.speechmaticsEnabled = on
            configure(&$0)
        }
    }

    /// A remembered person holding `identifier` for `tier`, heard `heard` seconds from the
    /// harness's start when given.
    @discardableResult
    func rememberSpeechmatics(
        _ name: String, identifier: String, tier: String = "standard", trusted: Bool = false, heard: Double? = nil
    ) async throws -> Person {
        let people = try #require(voices).store
        let at = Self.wallStart.addingTimeInterval(-86_400)
        let person = try #require(try await people.findOrCreate(named: name, at: at))
        try await people.setIdentifier(SpeechmaticsIdentifier(meeting: UUID(), at: at, identifier: identifier), tier: tier, for: person.id)
        if trusted { try await people.setTrusted(true, for: person.id) }
        if let heard { try await people.markHeard([person.id], at: Self.wallStart.addingTimeInterval(heard)) }
        return try #require(await people.person(person.id))
    }

    /// Waits until the controller has handled every session event sent so far: a partial sent
    /// now arrives after them.
    func settle() async throws {
        try sink(engines.engines.count).onPartial("…")
        _ = await nextPartial()
    }
}

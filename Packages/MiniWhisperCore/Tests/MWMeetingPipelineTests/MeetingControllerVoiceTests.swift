import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestSupport
import MWVoices

/// The local route in a meeting (design v8 §5 Control flow: Start, Segment arrives, Revision,
/// Stop): R2, R3, R5, R7–R9, R14, R16, R21, R23, R25, R27. "Voices" are constant-amplitude audio,
/// which `FakeVoiceEmbedder` hears as `.unit(<hundredths>)`: 0.05 is `.unit(5)`.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerVoiceTests {
    private static let alex = SpeakerLabel(id: 0, name: "Alex", isUser: true)
    private static let modelError = "Voice recognition is off for this meeting: the voice model could not be loaded."

    // MARK: - Activation (R2, R25)

    @Test func withTheSwitchOffNothingChanges() async throws {
        let harness = try await MeetingHarness.local(on: false)
        try await harness.remember("Alice", voice: .unit(5))

        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        #expect(harness.embedder?.prepareCount == 0)
        #expect(harness.embedder?.windows.isEmpty == true)
        #expect(!harness.seen.contains { $0.isVoiceData })
        #expect(try harness.sidecar() == nil)
        #expect(try harness.stored().meeting.speakers == [
            Self.alex, SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"]),
        ])
    }

    @Test func aTestCallNeitherPreparesNorRecognises() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Alice", voice: .unit(5))
        let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

        try await harness.controller.start(mode: .remote, title: "Test call", engine: .assemblyaiPro, test: tag)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        #expect(harness.embedder?.prepareCount == 0)
        #expect(harness.embedder?.windows.isEmpty == true)
        #expect(!harness.seen.contains { $0.isVoiceData })
        #expect(try harness.sidecar() == nil)
        #expect(try harness.stored().meeting.speakers.map(\.name) == ["Alex", "Speaker 1"])
    }

    @Test func withoutVoiceDependenciesNothingChanges() async throws {
        let harness = try await MeetingHarness(secrets: [.assemblyai: MeetingHarness.key]) {
            $0.meetingEngine = .assemblyaiPro
            $0.voice.localEnabled = true
        }

        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        #expect(!harness.seen.contains { $0.isVoiceData })
        #expect(try harness.sidecar() == nil)
        #expect(try harness.stored().meeting.speakers == [
            Self.alex, SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"]),
        ])
    }

    @Test func aSpeechmaticsMeetingNeverStartsTheLocalRoute() async throws {
        let harness = try await MeetingHarness.local(engine: .speechmaticsStandard)
        try await harness.remember("Alice", voice: .unit(5))

        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "S1", from: 0, to: 6)
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        #expect(harness.embedder?.prepareCount == 0)
        #expect(harness.embedder?.windows.isEmpty == true)
        #expect(!harness.seen.contains { $0.isVoiceData })
        #expect(harness.engines.calls.map(\.voices) == [nil])
        #expect(try harness.sidecar() == nil)
    }

    @Test func startDoesNotWaitForTheModel() async throws {
        let embedder = FakeVoiceEmbedder()
        embedder.hold()
        let harness = try await MeetingHarness.local(embedder)

        try await harness.start(.remote)

        let events = await harness.waitFor(.state(.recording))
        #expect(events.contains(.voiceData(active: true, keys: [])))
        embedder.release()
        await harness.controller.stop(summarise: false)
        #expect(embedder.prepareCount == 1)
    }

    @Test func aModelThatFailsToLoadTurnsTheRouteOffWithAnError() async throws {
        let embedder = FakeVoiceEmbedder()
        embedder.prepareFailure = VoiceEmbeddingError.modelUnavailable
        let harness = try await MeetingHarness.local(embedder)
        try await harness.remember("Alice", voice: .unit(5))

        try await harness.start(.remote)
        await harness.waitFor(.error(Self.modelError))
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        #expect(harness.seen.contains(.voiceData(active: false, keys: [])))
        #expect(embedder.windows.isEmpty)
        #expect(try harness.sidecar() == nil)
        #expect(try harness.stored().meeting.speakers.map(\.name) == ["Alex", "Speaker 1"])
    }

    // MARK: - Matching (R8, R9, R14, R16)

    @Test func aSureMatchAppliesTheName() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(5))

        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)

        let labels = await harness.waitForSpeakers { $0.named("Alice") != nil }
        let label = try #require(labels.named("Alice"))
        #expect(label.id == 1)
        #expect(label.providerKeys == ["1:A"])
        #expect(label.person == nil)
        let match = try #require(label.matches.first)
        #expect(label.matches.count == 1)
        #expect(match.key == "1:A")
        #expect(match.name == "Alice")
        #expect(match.person == alice.id)
        #expect(match.state == .applied)
        #expect(isClose(match.score, 1))
        #expect(try harness.stored().meeting.speakers == labels)
    }

    @Test func aSureMatchOntoAnExistingNameMergesSpeakers() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Alice", voice: .unit(5))
        try await harness.start(.remote)
        harness.speak(0.09, for: 6)
        try await harness.deliverWords(label: "B", from: 0, to: 6)
        await harness.controller.rename(speaker: 1, to: "Alice")

        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 6, to: 12)

        let labels = await harness.waitForSpeakers { $0.named("Alice")?.providerKeys == ["1:B", "1:A"] }
        #expect(labels.map(\.id) == [0, 1])
        #expect(labels.named("Alice")?.matches.map(\.state) == [.applied])
        let updated = harness.seen.compactMap { if case .segmentUpdated(let segment) = $0 { segment } else { nil } }
        #expect(updated.map(\.providerLabel) == ["A"])
        #expect(updated.map(\.speaker) == [1])
        #expect(try harness.stored().segments.map(\.speaker) == [1, 1])
    }

    @Test func aSuggestionLeavesTheName() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: voice([5: 0.6, 2: 0.8]))

        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)

        let labels = await harness.waitForSpeakers { $0.owning("1:A")?.matches.isEmpty == false }
        let label = try #require(labels.owning("1:A"))
        #expect(label.name == "Speaker 1")
        let match = try #require(label.matches.first)
        #expect(match.state == .suggested)
        #expect(match.name == "Alice")
        #expect(match.person == alice.id)
        #expect(isClose(match.score, 0.6))
        #expect(try harness.stored().meeting.speakers == labels)
    }

    @Test func aLaterSureMatchReplacesASuggestion() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Alice", voice: voice([5: 0.6, 7: 0.8]))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.waitForSpeakers { $0.owning("1:A")?.matches.first?.state == .suggested }

        harness.speak(0.07, for: 6)
        try await harness.deliverWords(label: "A", from: 6, to: 12)

        let labels = await harness.waitForSpeakers { $0.named("Alice") != nil }
        let match = try #require(labels.named("Alice")?.matches.first)
        #expect(labels.named("Alice")?.matches.count == 1)
        #expect(match.state == .applied)
        #expect(isClose(match.score, 1.4 / 2.0.squareRoot()))
    }

    @Test func aLaterNothingLeavesTheSuggestion() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Alice", voice: voice([5: 0.6, 2: 0.8]))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.waitForSpeakers { $0.owning("1:A")?.matches.isEmpty == false }

        harness.speak(0.09, for: 6)
        try await harness.deliverWords(label: "A", from: 6, to: 12)
        await harness.controller.stop(summarise: false)

        let label = try #require(try harness.stored().meeting.speakers.owning("1:A"))
        #expect(label.name == "Speaker 1")
        #expect(label.matches.map(\.state) == [.suggested])
        #expect(isClose(label.matches.first?.score, 0.6))
    }

    @Test func aRenamedSpeakerIsNeverChanged() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Alice", voice: .unit(5))
        try await harness.start(.remote)
        harness.speak(0.05, for: 3)
        try await harness.deliverWords(label: "A", from: 0, to: 3)
        await harness.controller.rename(speaker: 1, to: "Zed")

        harness.speak(0.05, for: 3)
        try await harness.deliverWords(label: "A", from: 3, to: 6)
        await harness.controller.stop(summarise: false)

        let label = try #require(try harness.stored().meeting.speakers.owning("1:A"))
        #expect(label.name == "Zed")
        #expect(label.matches.isEmpty)
        #expect(try harness.matchLog().filter { $0.event == .applied || $0.event == .suggested }.isEmpty)
    }

    @Test func theUserIsACandidateOnlyInTheRoom() async throws {
        let remote = try await MeetingHarness.local()
        try await remote.remember("Alex", voice: .unit(5), isUser: true)
        try await remote.start(.remote)
        remote.speak(0.05, for: 6)
        try await remote.deliverWords(label: "A", from: 0, to: 6)
        await remote.controller.stop(summarise: false)
        #expect(try remote.stored().meeting.speakers.owning("1:A")?.matches == [])
        #expect(try remote.stored().meeting.speakers.owning("1:A")?.name == "Speaker 1")

        let inRoom = try await MeetingHarness.local()
        let user = try await inRoom.remember("Alex", voice: .unit(5), isUser: true)
        try await inRoom.start(.inRoom)
        inRoom.speak(0.05, for: 6, mode: .inRoom)
        try await inRoom.deliverWords(label: "A", from: 0, to: 6)

        let labels = await inRoom.waitForSpeakers { $0.count == 1 }
        #expect(labels.map(\.id) == [0])
        #expect(labels.first?.providerKeys == ["1:A"])
        #expect(labels.first?.matches.map(\.person) == [user.id])
        #expect(labels.first?.matches.map(\.name) == ["Alex"])
        #expect(labels.first?.matches.map(\.state) == [.applied])
        #expect(inRoom.seen.contains { if case .segmentUpdated(let segment) = $0 { segment.speaker == 0 } else { false } })
    }

    @Test func aKeyTheGateGivesTheUserLosesItsMatch() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Alice", voice: voice([5: 0.6, 2: 0.8]))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "X", from: 0, to: 6)
        await harness.waitForSpeakers { $0.owning("1:X")?.matches.isEmpty == false }

        harness.speakAsUser(for: 14)
        try await harness.deliverWords(label: "X", from: 6, to: 20)

        let labels = await harness.waitForSpeakers { $0.owning("1:X")?.isUser == true }
        #expect(labels.map(\.matches) == [[], []])
    }

    // MARK: - Switch, revision, sidecar (R3, R7, R21)

    @Test func switchingOffMidMeetingStopsMatchingLoggingAndTheSidecar() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Alice", voice: .unit(5))
        try await harness.remember("Bob", voice: .unit(7))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.waitForSpeakers { $0.named("Alice") != nil }

        try await harness.config.update { @Sendable in $0.voice.localEnabled = false }
        harness.speak(0.07, for: 6)
        try await harness.deliverWords(label: "B", from: 6, to: 12)
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        let speakers = try harness.stored().meeting.speakers
        #expect(speakers.owning("1:B")?.name == "Speaker 2")
        #expect(speakers.owning("1:B")?.matches == [])
        #expect(try harness.matchLog().map(\.event) == [.applied])
        #expect(try harness.sidecar() == nil)
        #expect(harness.seen.last { $0.isVoiceData } == .voiceData(active: false, keys: []))
    }

    @Test func switchedBackOnMidMeetingStaysOffUntilTheNextMeeting() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Bob", voice: .unit(7))
        try await harness.start(.remote)
        try await harness.config.update { @Sendable in $0.voice.localEnabled = false }
        _ = await harness.tick(to: 1)
        try await harness.config.update { @Sendable in $0.voice.localEnabled = true }
        _ = await harness.tick(to: 2)

        harness.speak(0.07, for: 6)
        try await harness.deliverWords(label: "B", from: 0, to: 6)
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        let speakers = try harness.stored().meeting.speakers
        #expect(speakers.owning("1:B")?.name == "Speaker 1")
        #expect(speakers.owning("1:B")?.matches == [])
        #expect(try harness.matchLog().isEmpty)
        #expect(try harness.sidecar() == nil)
        #expect(harness.seen.last { $0.isVoiceData } == .voiceData(active: false, keys: []))
    }

    @Test func aRevisionMovesTheVectorsToTheNewKey() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.remember("Carol", voice: .unit(9))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6, turnOrder: 0)
        harness.speak(0.07, for: 6)
        try await harness.deliverWords(label: "A", from: 6, to: 12, turnOrder: 1)
        harness.speak(0.09, for: 6)
        try await harness.deliverWords(label: "C", from: 12, to: 18, turnOrder: 2)
        // The queue is in order: once Carol is named, both turns of A were evaluated, against her only.
        await harness.waitForSpeakers { $0.named("Carol") != nil }
        let alice = try await harness.remember("Alice", voice: .unit(5))
        let bob = try await harness.remember("Bob", voice: .unit(7))

        try harness.sink(1).onSpeakerRevision([SpeakerRevision(turnOrder: 1, speaker: "B")])

        let labels = await harness.waitForSpeakers { $0.named("Alice") != nil && $0.named("Bob") != nil }
        #expect(labels.owning("1:A")?.matches.map(\.person) == [alice.id])
        #expect(labels.owning("1:B")?.matches.map(\.person) == [bob.id])
        await harness.controller.stop(summarise: false)
        let sidecar = try #require(try harness.sidecar())
        #expect(sidecar.keys["1:A"]?.vector == .unit(5))
        #expect(sidecar.keys["1:B"]?.vector == .unit(7))
        #expect(isClose(sidecar.keys["1:A"]?.seconds, 6))
        #expect(isClose(sidecar.keys["1:B"]?.seconds, 6))
    }

    @Test func theSidecarIsWrittenAtStopWithVectorsNeverAudio() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        harness.speakAsUser(for: 6)
        try await harness.deliverWords(label: "U", from: 6, to: 12)

        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        let sidecar = try #require(try harness.sidecar())
        #expect(sidecar.route == .local)
        #expect(sidecar.model == "wespeaker_v2")
        #expect(Set(sidecar.keys.keys) == ["1:A", MeetingVoices.userKey])
        #expect(sidecar.keys["1:A"]?.vector == .unit(5))
        #expect(isClose(sidecar.keys["1:A"]?.seconds, 6))
        #expect(sidecar.keys[MeetingVoices.userKey]?.vector != nil)
        #expect(isClose(sidecar.keys[MeetingVoices.userKey]?.seconds, 6))
        #expect(harness.seen.contains(.voiceData(active: true, keys: ["1:A", MeetingVoices.userKey])))
        let url = try harness.sidecarURL()
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(Set(json.keys) == ["schema", "route", "model", "keys"])
        let entries = try #require(json["keys"] as? [String: [String: Any]])
        #expect(entries.values.allSatisfy { Set($0.keys) == ["seconds", "vector"] })
    }

    @Test func aFailedSidecarWriteEmitsAnError() async throws {
        let harness = try await MeetingHarness.local()
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        try FileManager.default.createDirectory(at: harness.sidecarURL(), withIntermediateDirectories: false)

        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        #expect(harness.seen.contains {
            if case .error(let message) = $0 { message.hasPrefix("Could not save this meeting's voice data (") } else { false }
        })
        #expect(try harness.stored().meeting.endedAt != nil)
    }

    // MARK: - Logs (R23, R27)

    @Test func eachMatchIsLogged() async throws {
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: voice([5: 0.6, 2: 0.8]))
        let bob = try await harness.remember("Bob", voice: .unit(7))
        try await harness.start(.remote)
        harness.speak(0.05, for: 6)
        try await harness.deliverWords(label: "A", from: 0, to: 6)
        await harness.waitForSpeakers { $0.owning("1:A")?.matches.isEmpty == false }
        harness.speak(0.07, for: 6)
        try await harness.deliverWords(label: "B", from: 6, to: 12)
        await harness.waitForSpeakers { $0.named("Bob") != nil }

        await harness.controller.stop(summarise: false)

        let id = try #require(harness.controller.meeting?.id)
        let entries = try harness.matchLog()
        #expect(entries.map(\.event) == [.suggested, .applied])
        #expect(entries.map(\.key) == ["1:A", "1:B"])
        #expect(entries.map(\.person) == [alice.id, bob.id])
        #expect(entries.allSatisfy { $0.meeting == id && $0.route == .local })
        #expect(isClose(entries.first?.score, 0.6))
        #expect(isClose(entries.first?.runnerUp, 0))
        #expect(isClose(entries.first?.seconds, 6))
        #expect(isClose(entries.last?.score, 1))
    }

    @Test func logsCarryKeysAndScoresNeverNamesOrVectors() async throws {
        let logs = CapturingLogSink()
        let harness = try await MeetingHarness.local()
        let alice = try await harness.remember("Alice", voice: .unit(5))

        try await logging(to: logs) {
            try await harness.start(.remote)
            harness.speak(0.05, for: 6)
            try await harness.deliverWords(label: "A", from: 0, to: 6)
            await harness.waitForSpeakers { $0.named("Alice") != nil }
            await harness.controller.stop(summarise: false)
        }

        let voiceLines = logs.records.filter { $0.category == "voice" }.map(\.message)
        let prefix = String(alice.id.uuidString.prefix(8)).lowercased()
        #expect(voiceLines.contains("match 1:A sure 1.00 (next 0.00) after 6 s, person \(prefix)"))
        #expect(voiceLines.contains("sidecar written: 1 key"))
        #expect(voiceLines.contains { $0.hasPrefix("model loaded in ") })
        let vector = try #require(String(data: JSONEncoder().encode(VoiceVector.unit(5)), encoding: .utf8))
        let forbidden = ["Alice", "Alex", "secret", alice.id.uuidString, alice.id.uuidString.lowercased(), String(vector.dropFirst().prefix(24))]
        #expect(!logs.lines.contains { line in forbidden.contains { line.contains($0) } })
    }
}

// MARK: - Helpers (shared by the voice suites)

extension MeetingHarness {
    /// The local route's setting: an AssemblyAI meeting (both keys stored), the switch `on` and a
    /// five-second minimum of speech.
    static func local(
        _ embedder: FakeVoiceEmbedder = FakeVoiceEmbedder(),
        engine: MeetingEngine = .assemblyaiPro,
        on: Bool = true,
        _ configure: @escaping @Sendable (inout Config) -> Void = { _ in }
    ) async throws -> MeetingHarness {
        try await MeetingHarness(
            secrets: [.assemblyai: MeetingHarness.key, .speechmatics: MeetingHarness.key], voices: embedder
        ) {
            $0.meetingEngine = engine
            $0.voice.localEnabled = on
            $0.voice.minimumSpeechSeconds = 5
            configure(&$0)
        }
    }

    var embedder: FakeVoiceEmbedder? { voices?.embedder as? FakeVoiceEmbedder }

    /// A remembered person whose one local sample is `voice`.
    @discardableResult
    func remember(_ name: String, voice: VoiceVector, isUser: Bool = false) async throws -> Person {
        let people = try #require(voices).store
        let at = Self.wallStart.addingTimeInterval(-86_400)
        let person = isUser
            ? try await people.user(named: name, at: at)
            : try #require(try await people.findOrCreate(named: name, at: at))
        try await people.addLocalSample(LocalSample(meeting: UUID(), at: at, seconds: 20, vector: voice), to: person.id)
        return try #require(await people.person(person.id))
    }

    /// `seconds` of a voice of constant `amplitude`: other apps' audio under a quiet microphone in
    /// a remote meeting, the microphone in the room.
    func speak(_ amplitude: Float, for seconds: Double, mode: MeetingMode = .remote) {
        let tick = [Float](repeating: amplitude, count: 1_600)
        for _ in 0..<Int((seconds * 10).rounded()) {
            if mode == .remote {
                pushSystem(tick)
                feed(Self.quiet(0.1))
            } else {
                feed(tick)
            }
        }
    }

    /// `seconds` of the user at the microphone, with short pauses the gate keeps open through.
    func speakAsUser(for seconds: Int) {
        for _ in 0..<seconds { feed(Self.loud(0.8) + Self.quiet(0.2)) }
    }

    /// The speakers once they satisfy `match`: the latest `.speakers` already pulled, or the next
    /// one that does.
    @discardableResult
    func waitForSpeakers(_ match: ([SpeakerLabel]) -> Bool) async -> [SpeakerLabel] {
        if let latest = speakers, match(latest) { return latest }
        let event = await waitFor { if case .speakers(let labels) = $0 { match(labels) } else { false } }.last
        if case .speakers(let labels)? = event { return labels }
        return []
    }

    /// The latest `.speakers` pulled.
    var speakers: [SpeakerLabel]? {
        seen.lazy.reversed().compactMap { if case .speakers(let labels) = $0 { labels } else { nil } }.first
    }

    func sidecarURL() throws -> URL {
        let id = try #require(controller.meeting?.id)
        return store.directory.appendingPathComponent(id.uuidString).appendingPathComponent("voices.json")
    }

    func sidecar() throws -> MeetingVoices? {
        try store.readVoices(#require(controller.meeting?.id))
    }

    func matchLog() throws -> [MatchLog.Entry] {
        let url = directory.file("voice-matches.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 0x0A).map {
            try MeetingCoding.decoder().decode(MatchLog.Entry.self, from: Data($0))
        }
    }
}

extension [SpeakerLabel] {
    func named(_ name: String) -> SpeakerLabel? { first { $0.name == name } }
    func owning(_ key: String) -> SpeakerLabel? { first { $0.providerKeys.contains(key) } }
}

extension MeetingEvent {
    var isVoiceData: Bool {
        if case .voiceData = self { true } else { false }
    }
}

/// A unit vector with these components, the rest zero.
func voice(_ components: [Int: Float]) -> VoiceVector {
    var values = [Float](repeating: 0, count: VoiceVector.dimension)
    for (axis, value) in components { values[axis] = value }
    return VoiceVector(values).normalised
}

func isClose(_ value: Double?, _ expected: Double) -> Bool {
    value.map { abs($0 - expected) < 0.001 } ?? false
}

import Foundation
import MWMeetings
import MWSupport
import MWTestSupport
import Testing

import MWVoices

@Suite struct VoiceScrubberTests {
    private struct Fixture {
        let temp: TempDirectory
        let store: MeetingStore
        let scrubber: VoiceScrubber

        init() throws {
            temp = try TempDirectory()
            store = MeetingStore(directory: temp.file("meetings"))
            scrubber = VoiceScrubber(store: store)
        }

        func file(_ name: String, of id: UUID) -> URL {
            store.directory.appendingPathComponent(id.uuidString).appendingPathComponent(name)
        }

        var index: URL { store.directory.appendingPathComponent("index.json") }

        func put(_ meeting: Meeting, voices: MeetingVoices?, segments: [Segment] = []) async throws {
            try await store.create(meeting)
            for segment in segments { try await store.append(segment, to: meeting.id) }
            if let voices { try await store.writeVoices(voices, of: meeting.id) }
        }

        func meeting(_ id: UUID) throws -> Meeting {
            try store.load(id).meeting
        }
    }

    private let alice = UUID(uuidString: "0B6F7C1E-2D3A-4B5C-8D9E-0F1A2B3C4D5E")!
    /// Merged into Alice: her `aliases` hold it.
    private let aliceBefore = UUID(uuidString: "5D4C3B2A-1F0E-4D9C-8B7A-6F5E4D3C2B1A")!
    private let bob = UUID(uuidString: "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D")!
    /// The user's own entry.
    private let you = UUID(uuidString: "3C2B1A09-8F7E-4D6C-9B5A-4E3D2C1B0A9F")!

    private func entry(_ axis: Int) -> MeetingVoices.Entry {
        MeetingVoices.Entry(seconds: 20 + Double(axis), vector: .unit(axis))
    }

    private func plain(_ speakers: [SpeakerLabel], id: UUID = UUID()) -> Meeting {
        var meeting = MeetingFixtures.make(id: id, engine: .assemblyaiStreaming).meeting
        meeting.speakers = speakers
        return meeting
    }

    /// A remote local-route meeting: the user linked to their entry, Alice linked over two keys,
    /// a speaker offered Alice who rejected Bob, and Bob linked who rejected Alice.
    private func mixed(id: UUID = UUID()) -> (meeting: Meeting, voices: MeetingVoices) {
        let meeting = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true, person: you),
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A", "2:A"], person: alice),
            SpeakerLabel(
                id: 2, name: "Speaker 2", providerKeys: ["1:C"],
                matches: [NameMatch(key: "1:C", name: "Alice", person: alice, state: .suggested, score: 0.61)],
                rejected: [bob]
            ),
            SpeakerLabel(id: 3, name: "Bob", providerKeys: ["1:B"], person: bob, rejected: [alice]),
        ], id: id)
        let voices = MeetingVoices(route: .local, model: "wespeaker_v2", keys: [
            "1:A": entry(1), "2:A": entry(2), "1:C": entry(3), "1:B": entry(4), MeetingVoices.userKey: entry(5),
        ])
        return (meeting, voices)
    }

    /// `mixed()` after Alice is forgotten.
    private func mixedWithoutAlice(_ original: (meeting: Meeting, voices: MeetingVoices)) -> (Meeting, MeetingVoices) {
        var meeting = original.meeting
        meeting.speakers = [
            SpeakerLabel(id: 0, name: "Alex", isUser: true, person: you),
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A", "2:A"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:C"], rejected: [bob]),
            SpeakerLabel(id: 3, name: "Bob", providerKeys: ["1:B"], person: bob),
        ]
        var voices = original.voices
        voices.keys = voices.keys.filter { !["1:A", "2:A"].contains($0.key) }
        return (meeting, voices)
    }

    private func inode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.systemFileNumber] as? Int)
    }

    private func snapshot(_ url: URL) throws -> (Data, Int) {
        (try Data(contentsOf: url), try inode(url))
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func isClear(_ speaker: SpeakerLabel) -> Bool {
        speaker.person == nil && speaker.matches.isEmpty && speaker.rejected.isEmpty
    }

    @Test func scrubbingAPersonClearsTheirLinksMatchesRejectedAndSidecarKeys() async throws {
        let fixture = try Fixture()
        let original = mixed()
        try await fixture.put(original.meeting, voices: original.voices)

        await fixture.scrubber.scrub(people: [alice], skipping: [])

        let (meeting, voices) = mixedWithoutAlice(original)
        #expect(try fixture.meeting(meeting.id) == meeting)
        #expect(try fixture.store.readVoices(meeting.id) == voices)
        #expect(Set(voices.keys.keys) == ["1:B", "1:C", MeetingVoices.userKey])
        #expect(try permissions(fixture.file("voices.json", of: meeting.id)) == 0o600)
    }

    @Test func anEmptiedSidecarIsDeleted() async throws {
        let fixture = try Fixture()
        let meeting = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: alice),
        ])
        try await fixture.put(meeting, voices: MeetingVoices(route: .local, model: "wespeaker_v2", keys: ["1:A": entry(1)]))

        await fixture.scrubber.scrub(people: [alice], skipping: [])

        #expect(try fixture.store.readVoices(meeting.id) == nil)
        #expect(exists(fixture.file("voices.json", of: meeting.id)) == false)
        #expect(try fixture.meeting(meeting.id).speakers[1] == SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"]))
    }

    @Test func everyIdInTheSetIsScrubbed() async throws {
        let fixture = try Fixture()
        let recent = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: alice),
        ])
        let older = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Ali", providerKeys: ["1:S1"], person: aliceBefore),
            SpeakerLabel(
                id: 2, name: "Speaker 2", providerKeys: ["1:S2"],
                matches: [NameMatch(key: "1:S2", name: "Ali", person: aliceBefore, state: .suggested)]
            ),
            SpeakerLabel(id: 3, name: "Speaker 3", providerKeys: ["1:S3"], rejected: [aliceBefore, bob]),
        ])
        try await fixture.put(recent, voices: MeetingVoices(route: .local, model: "wespeaker_v2", keys: ["1:A": entry(1)]))
        try await fixture.put(older, voices: MeetingVoices(route: .speechmatics, model: "standard", keys: [
            "1:S1": .init(seconds: 40, identifier: "opaque-1"), "1:S3": .init(seconds: 12, identifier: "opaque-3"),
        ]))

        await fixture.scrubber.scrub(people: [alice, aliceBefore], skipping: [])

        #expect(try fixture.meeting(recent.id).speakers[1].person == nil)
        #expect(try fixture.store.readVoices(recent.id) == nil)
        let speakers = try fixture.meeting(older.id).speakers
        #expect(speakers.map(\.name) == ["Alex", "Ali", "Speaker 2", "Speaker 3"])
        #expect(speakers[1].person == nil)
        #expect(speakers[2].matches.isEmpty)
        #expect(speakers[3].rejected == [bob])
        #expect(try fixture.store.readVoices(older.id)?.keys == ["1:S3": .init(seconds: 12, identifier: "opaque-3")])
    }

    @Test func skippedMeetingsAreLeftAlone() async throws {
        let fixture = try Fixture()
        let held = mixed()
        let stored = mixed()
        try await fixture.put(held.meeting, voices: held.voices)
        try await fixture.put(stored.meeting, voices: stored.voices)
        let heldMeeting = try snapshot(fixture.file("meeting.json", of: held.meeting.id))
        let heldVoices = try snapshot(fixture.file("voices.json", of: held.meeting.id))

        await fixture.scrubber.scrub(people: [alice], skipping: [held.meeting.id])

        #expect(try snapshot(fixture.file("meeting.json", of: held.meeting.id)) == heldMeeting)
        #expect(try snapshot(fixture.file("voices.json", of: held.meeting.id)) == heldVoices)
        let (meeting, voices) = mixedWithoutAlice(stored)
        #expect(try fixture.meeting(stored.meeting.id) == meeting)
        #expect(try fixture.store.readVoices(stored.meeting.id) == voices)

        await fixture.scrubber.scrub(people: nil, skipping: [held.meeting.id])
        #expect(try snapshot(fixture.file("voices.json", of: held.meeting.id)) == heldVoices)
        #expect(try fixture.store.readVoices(stored.meeting.id) == nil)
    }

    @Test func everyoneDeletesEverySidecarAndClearsEveryLinkMatchAndRejection() async throws {
        let fixture = try Fixture()
        let linked = mixed()
        let unlinked = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"]),
        ])
        let unvoiced = MeetingFixtures.make().meeting
        try await fixture.put(linked.meeting, voices: linked.voices)
        try await fixture.put(unlinked, voices: MeetingVoices(route: .local, model: "wespeaker_v2", keys: ["1:A": entry(1)]))
        try await fixture.put(unvoiced, voices: nil)
        let unlinkedMeeting = try snapshot(fixture.file("meeting.json", of: unlinked.id))
        let unvoicedMeeting = try snapshot(fixture.file("meeting.json", of: unvoiced.id))

        await fixture.scrubber.scrub(people: nil, skipping: [])

        for id in [linked.meeting.id, unlinked.id, unvoiced.id] {
            #expect(try fixture.store.readVoices(id) == nil)
            #expect(try fixture.meeting(id).speakers.allSatisfy(isClear))
        }
        #expect(try fixture.meeting(linked.meeting.id).speakers.map(\.name) == ["Alex", "Alice", "Speaker 2", "Bob"])
        #expect(try fixture.meeting(linked.meeting.id).speakers.map(\.providerKeys) == linked.meeting.speakers.map(\.providerKeys))
        #expect(try snapshot(fixture.file("meeting.json", of: unlinked.id)) == unlinkedMeeting)
        #expect(try snapshot(fixture.file("meeting.json", of: unvoiced.id)) == unvoicedMeeting)
    }

    @Test func namesInTheTranscriptStay() async throws {
        let fixture = try Fixture()
        let original = mixed()
        let segments = [
            Segment(speaker: 1, start: 4, end: 9, text: "Alice here, morning.", session: 1, providerLabel: "A"),
            Segment(speaker: 3, start: 10, end: 12, text: "Thanks, Alice.", session: 1, providerLabel: "B"),
            Segment(speaker: 2, start: 13, end: 15, text: "Bob, over to you.", session: 1, providerLabel: "C"),
        ]
        try await fixture.put(original.meeting, voices: original.voices, segments: segments)
        let transcript = try Data(contentsOf: fixture.file("segments.jsonl", of: original.meeting.id))

        await fixture.scrubber.scrub(people: [alice], skipping: [])
        await fixture.scrubber.scrub(people: nil, skipping: [])

        let loaded = try fixture.store.load(original.meeting.id)
        #expect(loaded.meeting.speakers.map(\.name) == original.meeting.speakers.map(\.name))
        #expect(loaded.segments == segments)
        #expect(try Data(contentsOf: fixture.file("segments.jsonl", of: original.meeting.id)) == transcript)
    }

    @Test func aMeetingWithoutVoiceDataIsNotRewritten() async throws {
        let fixture = try Fixture()
        let unvoiced = MeetingFixtures.make().meeting
        let bobsOnly = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Bob", providerKeys: ["1:B"], person: bob),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:C"], rejected: [bob]),
        ])
        try await fixture.put(unvoiced, voices: nil)
        try await fixture.put(bobsOnly, voices: MeetingVoices(route: .local, model: "wespeaker_v2", keys: [
            "1:B": entry(1), "1:C": entry(2),
        ]))
        let before = try [
            snapshot(fixture.file("meeting.json", of: unvoiced.id)),
            snapshot(fixture.file("meeting.json", of: bobsOnly.id)),
            snapshot(fixture.file("voices.json", of: bobsOnly.id)),
            snapshot(fixture.index),
        ]

        await fixture.scrubber.scrub(people: [alice, you], skipping: [])

        let after = try [
            snapshot(fixture.file("meeting.json", of: unvoiced.id)),
            snapshot(fixture.file("meeting.json", of: bobsOnly.id)),
            snapshot(fixture.file("voices.json", of: bobsOnly.id)),
            snapshot(fixture.index),
        ]
        #expect(after.map { $0.0 } == before.map { $0.0 })
        #expect(after.map { $0.1 } == before.map { $0.1 })
    }

    @Test func anUnreadableSidecarGoesOnlyWhereItCouldHoldTheirVoice() async throws {
        let fixture = try Fixture()
        let hers = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: alice),
        ])
        let his = plain([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Bob", providerKeys: ["1:B"], person: bob),
        ])
        try await fixture.put(hers, voices: nil)
        try await fixture.put(his, voices: nil)
        for id in [hers.id, his.id] { try Data("not json".utf8).write(to: fixture.file("voices.json", of: id)) }
        let hisVoices = try snapshot(fixture.file("voices.json", of: his.id))

        await fixture.scrubber.scrub(people: [alice], skipping: [])

        #expect(exists(fixture.file("voices.json", of: hers.id)) == false)
        #expect(try fixture.meeting(hers.id).speakers[1].person == nil)
        #expect(try snapshot(fixture.file("voices.json", of: his.id)) == hisVoices)

        await fixture.scrubber.scrub(people: nil, skipping: [])
        #expect(exists(fixture.file("voices.json", of: his.id)) == false)
    }

    @Test func anUnreadableMeetingIsSkippedAndTheRestScrubbed() async throws {
        let fixture = try Fixture()
        let broken = mixed()
        let fine = mixed()
        try await fixture.put(broken.meeting, voices: broken.voices)
        try await fixture.put(fine.meeting, voices: fine.voices)
        try Data("{".utf8).write(to: fixture.file("meeting.json", of: broken.meeting.id))
        let sink = CapturingLogSink()

        await Log.withSinks(debug: true, sinks: [sink]) {
            await fixture.scrubber.scrub(people: [alice], skipping: [])
        }

        let (meeting, voices) = mixedWithoutAlice(fine)
        #expect(try fixture.meeting(fine.meeting.id) == meeting)
        #expect(try fixture.store.readVoices(fine.meeting.id) == voices)
        #expect(try fixture.store.readVoices(broken.meeting.id) == broken.voices)
        #expect(sink.lines.contains { $0.hasPrefix("WARNING voice") })
        #expect(sink.lines.allSatisfy { !$0.contains("Alice") && !$0.contains(alice.uuidString) })
    }

    @Test func thePureScrubOfOneMeeting() {
        let original = mixed()
        let (withoutAlice, voicesWithoutAlice) = mixedWithoutAlice(original)

        var meeting = original.meeting
        #expect(VoiceScrubber.scrub(&meeting, voices: original.voices, people: [alice]) == voicesWithoutAlice)
        #expect(meeting == withoutAlice)

        meeting = original.meeting
        #expect(VoiceScrubber.scrub(&meeting, voices: nil, people: [alice]) == nil)
        #expect(meeting == withoutAlice)

        meeting = original.meeting
        var withoutYou = original.voices
        withoutYou.keys[MeetingVoices.userKey] = nil
        #expect(VoiceScrubber.scrub(&meeting, voices: original.voices, people: [you]) == withoutYou)
        #expect(meeting.speakers[0] == SpeakerLabel(id: 0, name: "Alex", isUser: true))
        #expect(Array(meeting.speakers.dropFirst()) == Array(original.meeting.speakers.dropFirst()))

        meeting = original.meeting
        #expect(VoiceScrubber.scrub(&meeting, voices: original.voices, people: [UUID()]) == original.voices)
        #expect(meeting == original.meeting)

        let empty = MeetingVoices(route: .local, model: "wespeaker_v2")
        meeting = original.meeting
        #expect(VoiceScrubber.scrub(&meeting, voices: empty, people: [bob]) == empty)

        meeting = original.meeting
        #expect(VoiceScrubber.scrub(&meeting, voices: original.voices, people: nil) == nil)
        #expect(meeting.speakers.allSatisfy(isClear))
        #expect(meeting.speakers.map(\.name) == original.meeting.speakers.map(\.name))
        #expect(meeting.speakers.map(\.providerKeys) == original.meeting.speakers.map(\.providerKeys))
    }
}

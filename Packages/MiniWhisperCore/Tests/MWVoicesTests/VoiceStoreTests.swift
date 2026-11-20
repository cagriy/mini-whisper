import Foundation
import MWMeetings
import MWSupport
import MWTestSupport
import Testing

import MWVoices

@Suite struct VoiceStoreTests {
    private static let start = Date(timeIntervalSince1970: 1_793_491_200)  // 2026-11-01T00:00:00Z

    /// Cosine with `.unit(0)` exactly 17/20 = 0.85.
    private let atPointEightFive = VoiceVector.padded([17, 10, 3, 1, 1])

    private func day(_ n: Int) -> Date {
        Self.start.addingTimeInterval(Double(n) * 86_400)
    }

    private func sample(_ vector: VoiceVector, day n: Int, meeting: UUID = UUID()) -> LocalSample {
        LocalSample(meeting: meeting, at: day(n), seconds: 30, vector: vector)
    }

    private func identifier(_ value: String, day n: Int) -> SpeechmaticsIdentifier {
        SpeechmaticsIdentifier(meeting: UUID(), at: day(n), identifier: value)
    }

    private func create(_ name: String, in store: VoiceStore) async throws -> Person {
        try #require(try await store.findOrCreate(named: name, at: day(0)))
    }

    /// What a fresh store reads from the folder.
    private func onDisk(_ directory: TempDirectory) async -> [Person] {
        await VoiceStore(directory: directory.url).people()
    }

    private func mode(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func setMode(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    // MARK: - Find or create

    @Test func findOrCreateMatchesTheTrimmedNameExactly() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)

        #expect(try await store.findOrCreate(named: "  Alice\n", at: day(2)) == alice)
        #expect(try await store.findOrCreate(named: "alice", at: day(2))?.id != alice.id)
        #expect(try await store.findOrCreate(named: "Alice B", at: day(2))?.id != alice.id)
        #expect(await store.people().map(\.name) == ["Alice", "alice", "Alice B"])
        #expect(await onDisk(directory).map(\.name) == ["Alice", "alice", "Alice B"])
    }

    @Test func aNewNameCreatesAPerson() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)

        let bob = try #require(try await store.findOrCreate(named: " Bob ", at: day(3)))

        #expect(bob.name == "Bob")
        #expect(bob.isUser == false)
        #expect(bob.createdAt == day(3))
        #expect(bob.lastHeard == nil)
        #expect(bob.aliases.isEmpty)
        #expect(bob.local.isEmpty)
        #expect(bob.speechmatics.isEmpty)
        #expect(bob.speechmaticsTrusted == false)
        #expect(await store.people() == [bob])
        #expect(await store.person(bob.id) == bob)
        #expect(await onDisk(directory) == [bob])
    }

    @Test func aDefaultSpeakerNameNeverCreatesAPerson() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)

        for name in ["Speaker 3", " Speaker 12 ", "", "   "] {
            #expect(try await store.findOrCreate(named: name, at: day(1)) == nil, "\(name)")
        }

        #expect(await store.people().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.file("voices.json").path))
        #expect(try await store.findOrCreate(named: "Speaker 3b", at: day(1))?.name == "Speaker 3b")
    }

    // MARK: - The user's entry

    @Test func theUsersEntryIsCreatedOnceAndMarkedIsUser() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)

        let user = try await store.user(named: " Alex ", at: day(1))

        #expect(user.isUser)
        #expect(user.name == "Alex")
        #expect(user.createdAt == day(1))
        #expect(try await store.user(named: "Someone else", at: day(2)) == user)
        #expect(try await store.findOrCreate(named: "Alex", at: day(3)) == user)
        #expect(await store.people() == [user])
        #expect(await onDisk(directory) == [user])
    }

    // MARK: - Rename

    @Test func renameRefusesANameAnotherPersonHas() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)
        let bob = try await create("Bob", in: store)

        await #expect(throws: VoiceStoreError.nameTaken) { try await store.rename(bob.id, to: " Alice ") }
        #expect(await store.person(bob.id)?.name == "Bob")

        try await store.rename(bob.id, to: " Robert ")
        try await store.rename(alice.id, to: "Alice")
        try await store.rename(alice.id, to: "Bob")

        #expect(await store.people().map(\.name) == ["Bob", "Robert"])
        #expect(await onDisk(directory).map(\.name) == ["Bob", "Robert"])
    }

    @Test func renameRefusesABlankOrADefaultSpeakerName() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let bob = try await create("Bob", in: store)

        for name in ["Speaker 2", "  ", ""] {
            await #expect(throws: VoiceStoreError.invalidName, "\(name)") { try await store.rename(bob.id, to: name) }
        }

        #expect(await onDisk(directory).map(\.name) == ["Bob"])
    }

    @Test func theUsersEntryHasNoRename() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let user = try await store.user(named: "Alex", at: day(1))

        await #expect(throws: VoiceStoreError.userEntry) { try await store.rename(user.id, to: "Alexander") }

        #expect(await store.person(user.id)?.name == "Alex")
        #expect(await onDisk(directory) == [user])
    }

    // MARK: - Merge

    @Test func mergeFeedsBothPeoplesSamplesOldestFirstKeepsTheNewerIdentifierPerTierOrsTrustAndAppendsAliases() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)
        let bob = try await create("Bob", in: store)
        let carol = try await create("Carol", in: store)
        let dave = try await create("Dave", in: store)
        let eve = try await create("Eve", in: store)
        try await store.merge(carol.id, into: bob.id)
        try await store.merge(dave.id, into: alice.id)

        let a1 = sample(.unit(1), day: 1)
        let b1 = sample(.unit(0), day: 2)
        let a2 = sample(atPointEightFive, day: 3)  // replaces b1 once both are fed
        let b2 = sample(.unit(2), day: 4)
        let a3to7 = (3...7).map { sample(.unit($0), day: $0 + 2) }
        let b3 = sample(.unit(8), day: 10)  // the ninth: a1, the oldest, goes
        for local in [a1, a2] + a3to7 { try await store.addLocalSample(local, to: alice.id) }
        for local in [b1, b2, b3] { try await store.addLocalSample(local, to: bob.id) }

        let bobStandard = identifier("bob-standard", day: 5)
        let aliceEnhanced = identifier("alice-enhanced", day: 4)
        try await store.setIdentifier(bobStandard, tier: "standard", for: bob.id)
        try await store.setIdentifier(identifier("bob-enhanced", day: 1), tier: "enhanced", for: bob.id)
        try await store.setIdentifier(identifier("alice-standard", day: 3), tier: "standard", for: alice.id)
        try await store.setIdentifier(aliceEnhanced, tier: "enhanced", for: alice.id)
        try await store.setTrusted(true, for: alice.id)
        try await store.markHeard([bob.id], at: day(5))
        try await store.markHeard([alice.id], at: day(9))
        var expected = try #require(await store.person(bob.id))

        try await store.merge(alice.id, into: bob.id)

        expected.local = [a2, b2] + a3to7 + [b3]
        expected.speechmatics = ["standard": bobStandard, "enhanced": aliceEnhanced]
        expected.speechmaticsTrusted = true
        expected.lastHeard = day(9)
        expected.aliases = [carol.id, alice.id, dave.id]
        #expect(await store.person(bob.id) == expected)
        #expect(await store.people() == [expected, eve])
        #expect(await onDisk(directory) == [expected, eve])
    }

    @Test func theUserIsNeverMergedIntoAnother() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let user = try await store.user(named: "Alex", at: day(1))
        let bob = try await create("Bob", in: store)

        await #expect(throws: VoiceStoreError.userEntry) { try await store.merge(user.id, into: bob.id) }
        #expect(await store.people() == [user, bob])

        try await store.merge(bob.id, into: user.id)

        var expected = user
        expected.aliases = [bob.id]
        #expect(await store.people() == [expected])
        #expect(await onDisk(directory) == [expected])
    }

    // MARK: - Forget

    @Test func forgetReturnsTheIdAndItsAliases() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)
        let bob = try await create("Bob", in: store)
        let carol = try await create("Carol", in: store)
        let dave = try await create("Dave", in: store)
        try await store.merge(bob.id, into: alice.id)
        try await store.merge(carol.id, into: alice.id)

        #expect(try await store.forget(alice.id) == [alice.id, bob.id, carol.id])

        #expect(await store.people() == [dave])
        #expect(await onDisk(directory) == [dave])
        let unknown = UUID()
        #expect(try await store.forget(unknown) == [unknown])
    }

    @Test func forgetEveryoneDeletesTheFile() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        try await store.forgetEveryone()
        _ = try await create("Alice", in: store)
        _ = try await create("Bob", in: store)
        try Data("earlier unreadable copy".utf8).write(to: directory.file("voices.json.bak"))

        try await store.forgetEveryone()

        #expect(await store.people().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)
        #expect(await onDisk(directory).isEmpty)
        _ = try await create("Carol", in: store)
        #expect(await onDisk(directory).map(\.name) == ["Carol"])
    }

    // MARK: - Local samples

    @Test func aLocalSampleGoesThroughSampleSet() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let bob = try await create("Bob", in: store)
        let first = sample(.unit(0), day: 1)
        let distant = sample(.unit(1), day: 2)
        let close = sample(atPointEightFive, day: 3)

        for local in [first, distant, close] { try await store.addLocalSample(local, to: bob.id) }
        try await store.addLocalSample(sample(.unit(2), day: 4), to: UUID())

        #expect(await store.person(bob.id)?.local == [distant, close])
        #expect(await onDisk(directory).map(\.local) == [[distant, close]])
    }

    @Test func removeLocalSampleDropsThatMeetingsSample() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)
        let bob = try await create("Bob", in: store)
        let meeting = UUID()
        let dropped = sample(.unit(0), day: 1, meeting: meeting)
        let kept = sample(.unit(1), day: 2)
        let alices = sample(.unit(2), day: 1, meeting: meeting)
        try await store.addLocalSample(dropped, to: bob.id)
        try await store.addLocalSample(kept, to: bob.id)
        try await store.addLocalSample(alices, to: alice.id)

        try await store.removeLocalSample(meeting: meeting, from: bob.id)

        #expect(await store.person(bob.id)?.local == [kept])
        #expect(await store.person(alice.id)?.local == [alices])
        #expect(await onDisk(directory).map(\.local) == [[alices], [kept]])
    }

    // MARK: - Speechmatics identifiers and trust

    @Test func anIdentifierIsKeptOnePerTierNewest() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let bob = try await create("Bob", in: store)
        let enhanced = identifier("enhanced-1", day: 1)
        let sameDay = identifier("standard-3", day: 3)

        try await store.setIdentifier(identifier("standard-2", day: 2), tier: "standard", for: bob.id)
        try await store.setIdentifier(enhanced, tier: "enhanced", for: bob.id)
        try await store.setIdentifier(identifier("standard-3a", day: 3), tier: "standard", for: bob.id)
        try await store.setIdentifier(sameDay, tier: "standard", for: bob.id)
        try await store.setIdentifier(identifier("standard-1", day: 1), tier: "standard", for: bob.id)

        #expect(await store.person(bob.id)?.speechmatics == ["standard": sameDay, "enhanced": enhanced])
        #expect(await onDisk(directory).map(\.speechmatics) == [["standard": sameDay, "enhanced": enhanced]])
    }

    @Test func dropIdentifierRemovesItAndReturnsItsPerson() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)
        let bob = try await create("Bob", in: store)
        let bobStandard = identifier("bob-standard", day: 1)
        try await store.setIdentifier(bobStandard, tier: "standard", for: bob.id)
        try await store.setIdentifier(identifier("bob-enhanced", day: 1), tier: "enhanced", for: bob.id)
        try await store.setIdentifier(identifier("alice-standard", day: 1), tier: "standard", for: alice.id)
        let aliceBefore = await store.person(alice.id)

        let dropped = try await store.dropIdentifier("bob-enhanced")

        #expect(dropped?.id == bob.id)
        #expect(dropped?.speechmatics == ["standard": bobStandard])
        #expect(await store.person(bob.id) == dropped)
        #expect(await store.person(alice.id) == aliceBefore)
        #expect(try await store.dropIdentifier("never-stored") == nil)
        #expect(await onDisk(directory).map(\.speechmatics.count) == [1, 1])
    }

    @Test func markHeardSetsLastHeard() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)
        let bob = try await create("Bob", in: store)
        let carol = try await create("Carol", in: store)

        try await store.markHeard([alice.id, bob.id, UUID()], at: day(5))
        try await store.markHeard([alice.id], at: day(7))

        #expect(await store.person(alice.id)?.lastHeard == day(7))
        #expect(await store.person(bob.id)?.lastHeard == day(5))
        #expect(await store.person(carol.id)?.lastHeard == nil)
        #expect(await onDisk(directory).map(\.lastHeard) == [day(7), day(5), nil])
    }

    // MARK: - The file

    @Test func writesAre0600AndLeaveNoTempFile() async throws {
        let directory = try TempDirectory()
        let folder = directory.url.appendingPathComponent("mini-whisper", isDirectory: true)
        let store = VoiceStore(directory: folder)
        let alice = try await create("Alice", in: store)
        try await store.addLocalSample(sample(.unit(0), day: 1), to: alice.id)
        try await store.rename(alice.id, to: "Alicia")

        let file = folder.appendingPathComponent("voices.json")
        #expect(try mode(of: file) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["voices.json"])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(Set(json.keys) == ["schema", "people"])
        #expect(json["schema"] as? Int == 1)
        #expect((json["people"] as? [[String: Any]])?.first?["name"] as? String == "Alicia")
    }

    @Test func anUnreadableFileMovesToBakAndTheStoreStartsEmpty() async throws {
        let directory = try TempDirectory()
        let file = directory.file("voices.json")
        let backup = directory.file("voices.json.bak")
        let corrupt = Data(#"{"schema":1,"people":[{"name":"Alice","#.utf8)
        try corrupt.write(to: file)
        try Data("an older backup".utf8).write(to: backup)
        let sink = CapturingLogSink()

        let people = await Log.withSinks(debug: true, sinks: [sink]) {
            await VoiceStore(directory: directory.url).people()
        }

        #expect(people.isEmpty)
        #expect(try Data(contentsOf: backup) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let lines = sink.records.filter { $0.category == "voice" }
        #expect(lines.map(\.level) == [.warning])
        #expect(!sink.lines.contains { $0.contains("Alice") })

        try Data(#"{"schema":1,"people":[]}"#.utf8).write(to: file)
        try setMode(0o000, of: file)
        #expect(await VoiceStore(directory: directory.url).people().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try setMode(0o600, of: backup)
        #expect(try Data(contentsOf: backup) == Data(#"{"schema":1,"people":[]}"#.utf8))
    }

    @Test func everyWritePublishesOnChanges() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let meeting = UUID()

        let alice = try await create("Alice", in: store)
        var expected = [await store.people()]
        let bob = try await create("Bob", in: store)
        expected.append(await store.people())
        _ = try await store.findOrCreate(named: "Alice", at: day(1))
        _ = try await store.user(named: "Alex", at: day(1))
        expected.append(await store.people())
        _ = try await store.user(named: "Alex", at: day(2))
        try await store.rename(bob.id, to: "Robert")
        expected.append(await store.people())
        try await store.addLocalSample(sample(.unit(0), day: 1, meeting: meeting), to: alice.id)
        expected.append(await store.people())
        try await store.removeLocalSample(meeting: meeting, from: alice.id)
        expected.append(await store.people())
        try await store.setIdentifier(identifier("bob-standard", day: 1), tier: "standard", for: bob.id)
        expected.append(await store.people())
        try await store.setTrusted(true, for: bob.id)
        expected.append(await store.people())
        try await store.dropIdentifier("bob-standard")
        expected.append(await store.people())
        try await store.markHeard([alice.id], at: day(2))
        expected.append(await store.people())
        try await store.merge(bob.id, into: alice.id)
        expected.append(await store.people())
        _ = try await store.forget(alice.id)
        expected.append(await store.people())
        try await store.forgetEveryone()
        expected.append(await store.people())

        var iterator = store.changes.makeAsyncIterator()
        for (step, people) in expected.enumerated() {
            #expect(await iterator.next() == people, "step \(step)")
        }
        #expect(expected.last == [])
        #expect(!FileManager.default.fileExists(atPath: directory.file("voices.json").path))
    }

    @Test func aFailedWriteThrowsAndKeepsTheChangeForTheNextWrite() async throws {
        let directory = try TempDirectory()
        let store = VoiceStore(directory: directory.url)
        let alice = try await create("Alice", in: store)
        var iterator = store.changes.makeAsyncIterator()
        _ = await iterator.next()

        try setMode(0o500, of: directory.url)
        defer { try? setMode(0o700, of: directory.url) }
        await #expect(throws: (any Error).self) { try await store.rename(alice.id, to: "Alicia") }

        #expect(await store.person(alice.id)?.name == "Alicia")
        #expect(await iterator.next()?.map(\.name) == ["Alicia"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == ["voices.json"])
        #expect(await onDisk(directory).map(\.name) == ["Alice"])

        try setMode(0o700, of: directory.url)
        _ = try await create("Bob", in: store)

        #expect(await onDisk(directory).map(\.name) == ["Alicia", "Bob"])
    }
}

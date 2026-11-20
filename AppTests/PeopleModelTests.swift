import Foundation
import MWMeetings
import MWVoices
import Testing
@testable import MiniWhisper

/// Settings › People (design v8 R24, §5 UI surfaces) over closure dependencies; no store.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PeopleModelTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-20 13:00 UTC.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_795_179_600)
    private static let day = 86_400.0

    private static let vector = VoiceVector(Array(repeating: 0.0625, count: VoiceVector.dimension))

    private static func person(
        _ name: String, isUser: Bool = false, heard: Double? = nil, local: Bool = false, tiers: [String] = []
    ) -> Person {
        let at = now.addingTimeInterval(-30 * day)
        return Person(
            name: name, isUser: isUser, createdAt: at, lastHeard: heard.map { now.addingTimeInterval($0) },
            local: local ? [LocalSample(meeting: UUID(), at: at, seconds: 40, vector: vector)] : [],
            speechmatics: Dictionary(uniqueKeysWithValues: tiers.map {
                ($0, SpeechmaticsIdentifier(meeting: UUID(), at: at, identifier: "opaque"))
            })
        )
    }

    private static let you = person("Sample User", isUser: true, heard: -60, local: true, tiers: ["standard"])
    private static let merged = UUID()
    private static let alice: Person = {
        var alice = person("Alice", heard: -2 * day, local: true, tiers: ["standard"])
        alice.aliases = [merged]
        return alice
    }()
    private static let bob = person("Bob", heard: -2 * day - 60, local: true)
    private static let carol = person("Carol", heard: -8 * day, tiers: ["enhanced"])

    /// What the model asked of its dependencies.
    @MainActor
    private final class Calls {
        var renames: [(UUID, String)] = []
        var merges: [(UUID, UUID)] = []
        var openedMeetings = 0
        var renameFailure: (any Error)?
        /// Forget's steps in order, and what each was given.
        var steps: [String] = []
        var forgets: [UUID?] = []
        var forgetFailure: (any Error)?
        var heldScrubs: [Set<UUID>?] = []
        /// The meetings sessions hold.
        let held: Set<UUID> = [UUID(), UUID()]
        var storedScrubs: [(people: Set<UUID>?, skipping: Set<UUID>)] = []
        var logRemovals: [Set<UUID>?] = []
    }

    private struct DiskFull: LocalizedError {
        var errorDescription: String? { "disk full" }
    }

    private func model(
        _ people: [Person] = [carol, bob, you, alice],
        changes: AsyncStream<[Person]> = AsyncStream { $0.finish() },
        calls: Calls = Calls()
    ) async -> PeopleModel {
        let model = PeopleModel(deps: PeopleModel.Dependencies(
            load: { people },
            changes: changes,
            rename: { id, name in
                try await MainActor.run {
                    if let failure = calls.renameFailure { throw failure }
                    calls.renames.append((id, name))
                }
            },
            merge: { source, target in await MainActor.run { calls.merges.append((source, target)) } },
            forget: { id in
                try await MainActor.run {
                    calls.steps.append("store")
                    calls.forgets.append(id)
                    if let failure = calls.forgetFailure { throw failure }
                }
            },
            scrubOpenMeetings: { people in
                calls.steps.append("held")
                calls.heldScrubs.append(people)
                return calls.held
            },
            scrubStoredMeetings: { people, skipping in
                await MainActor.run {
                    calls.steps.append("stored")
                    calls.storedScrubs.append((people, skipping))
                }
            },
            removeMatches: { people in
                await MainActor.run {
                    calls.steps.append("log")
                    calls.logRemovals.append(people)
                }
            },
            openMeetingsSettings: { calls.openedMeetings += 1 },
            now: { Self.now },
            calendar: Self.utc
        ))
        await until { model.rows.count == people.count }
        return model
    }

    /// The model loads and follows the store on its own task; this yields until it has.
    private func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
    }

    private func row(_ model: PeopleModel, _ name: String) throws -> PeopleModel.Row {
        try #require(model.rows.first { $0.name == name })
    }

    @Test func rowsAreSortedByLastHeardNewestFirst() async {
        let never = Self.person("Dan")
        let model = await model([Self.carol, never, Self.bob, Self.you, Self.alice])

        // Never heard sorts by when the person was first named.
        #expect(model.rows.map(\.name) == ["Sample User", "Alice", "Bob", "Carol", "Dan"])
    }

    @Test func aRowListsTheRoutesThatHoldDataAndTheLastHeardDate() async throws {
        let model = await model()

        #expect(try row(model, "Alice").detail == "Local model · Speechmatics Standard · last heard 18 Nov")
        #expect(try row(model, "Carol").detail == "Speechmatics Enhanced · last heard 12 Nov")
        #expect(try row(model, "Sample User").detail == "Local model · Speechmatics Standard · last heard today")

        let model2 = await self.model([
            Self.person("Dan", local: true, tiers: ["enhanced", "standard"]),
            Self.person("Erin", heard: -400 * Self.day),
        ])
        #expect(try row(model2, "Dan").detail == "Local model · Speechmatics Standard · Speechmatics Enhanced")
        #expect(try row(model2, "Erin").detail == "last heard 16 Oct 2025")
    }

    @Test func theUsersRowCarriesYouAndOffersNoRenameOrMerge() async throws {
        let model = await model()
        let you = try row(model, "Sample User")
        let alice = try row(model, "Alice")

        #expect(you.isUser)
        #expect(you.offersRename == false)
        #expect(you.offersMerge == false)
        #expect(model.mergeTargets(for: you).isEmpty)
        #expect(alice.isUser == false)
        #expect(alice.offersRename)
        #expect(alice.offersMerge)
        // Others can be merged into the user's entry.
        #expect(model.mergeTargets(for: alice).map(model.mergeTitle(of:)).contains("Sample User (you)"))
    }

    @Test func rowsFollowTheStoresChanges() async {
        let (changes, change) = AsyncStream.makeStream(of: [Person].self)
        let model = await model([Self.alice], changes: changes)
        #expect(model.rows.map(\.name) == ["Alice"])

        change.yield([Self.alice, Self.bob])
        await until { model.rows.count == 2 }
        #expect(model.rows.map(\.name) == ["Alice", "Bob"])
        #expect(model.groupTitle == "Remembered voices · 2")

        change.yield([])
        await until { model.rows.isEmpty }
        #expect(model.rows.isEmpty)
    }

    @Test func renameRefusesATakenNameWithTheMessage() async throws {
        let calls = Calls()
        let model = await model(calls: calls)

        let refusal = await model.rename(try row(model, "Bob"), to: " Alice ")

        #expect(refusal == "Alice already exists. Use Merge into… instead.")
        #expect(calls.renames.isEmpty)
    }

    @Test func renameWritesThroughTheStore() async throws {
        let calls = Calls()
        let model = await model(calls: calls)
        let bob = try row(model, "Bob")

        #expect(model.renameTitle(of: bob) == "Rename Bob")
        #expect(PeopleModel.renameNote == "Past meetings keep the old name.")
        #expect(await model.rename(bob, to: " Robert ") == nil)
        #expect(calls.renames.map(\.0) == [bob.id])
        #expect(calls.renames.map(\.1) == ["Robert"])

        // Nothing to write: blank, unchanged, or a default speaker name.
        #expect(PeopleModel.acceptsName("  ") == false)
        #expect(PeopleModel.acceptsName("Speaker 4") == false)
        #expect(PeopleModel.acceptsName("Robert"))
        #expect(await model.rename(bob, to: "Bob") == nil)
        #expect(await model.rename(bob, to: "Speaker 4") == nil)
        #expect(calls.renames.count == 1)

        // The store refuses a name taken since the list was read.
        calls.renameFailure = VoiceStoreError.nameTaken
        #expect(await model.rename(bob, to: "Dora") == "Dora already exists. Use Merge into… instead.")
    }

    @Test func mergeOffersTheOtherPeople() async throws {
        let model = await model()
        let bob = try row(model, "Bob")

        #expect(model.mergeTargets(for: bob).map(\.name) == ["Sample User", "Alice", "Carol"])
        #expect(model.mergeMenuTitle(of: bob) == "Merge Bob into")
        #expect(model.mergeTitle(of: try row(model, "Alice")) == "Alice")
    }

    @Test func theMergeDialogCopy() async throws {
        let calls = Calls()
        let model = await model(calls: calls)
        let bob = try row(model, "Bob")
        let alice = try row(model, "Alice")

        model.requestMerge(bob, into: alice)

        let pending = try #require(model.pending)
        #expect(pending.title == "Merge Bob into Alice?")
        #expect(pending.message == "Alice keeps the name and gets both voices. Past meetings are not changed.")
        #expect(pending.confirmTitle == "Merge")

        await model.confirm()
        #expect(model.pending == nil)
        #expect(calls.merges.map(\.0) == [bob.id])
        #expect(calls.merges.map(\.1) == [alice.id])

        model.requestMerge(alice, into: bob)
        model.cancelConfirmation()
        await model.confirm()
        #expect(calls.merges.count == 1)
    }

    @Test func whileAMeetingRecordsEveryActionIsDisabledWithTheInfoLine() async throws {
        let calls = Calls()
        let model = await model(calls: calls)
        let bob = try row(model, "Bob")
        let alice = try row(model, "Alice")
        #expect(model.recordingLine == nil)
        #expect(model.canAct)

        model.requestMerge(bob, into: alice)
        model.isRecording = true

        #expect(model.recordingLine == "A meeting is recording. Rename, merge and forget are available when it stops.")
        #expect(model.canAct == false)
        #expect(model.pending == nil)
        model.requestMerge(bob, into: alice)
        #expect(model.pending == nil)
        #expect(await model.rename(bob, to: "Robert") == nil)
        #expect(calls.renames.isEmpty)
        #expect(calls.merges.isEmpty)

        model.isRecording = false
        #expect(model.canAct)
    }

    @Test func theEmptyStateCopy() async {
        let model = await model([])

        #expect(model.rows.isEmpty)
        #expect(PeopleModel.emptyTitle == "No one yet")
        #expect(PeopleModel.emptyMessage == "Turn on Remember voices under Meetings, then name a speaker in a meeting."
            + " The people you name appear here.")
        #expect(PeopleModel.openMeetingsTitle == "Open Meetings Settings")
        #expect(PeopleModel.lead == "People you named in meetings while a Remember voices switch was on. Mini Whisper"
            + " keeps a voiceprint or a Speechmatics identifier for each, never audio.")
    }

    @Test func openMeetingsSettingsSelectsMeetings() async {
        let calls = Calls()
        let model = await model([], calls: calls)

        model.openMeetingsSettings()

        #expect(calls.openedMeetings == 1)
    }

    // MARK: - Forget (Stage 20)

    @Test func forgetRunsStoreThenHeldMeetingsThenStoredMeetingsThenTheLog() async throws {
        let calls = Calls()
        let model = await model(calls: calls)

        model.requestForget(try row(model, "Alice"))
        await model.confirm()

        let ids: Set<UUID> = [Self.alice.id, Self.merged]
        #expect(calls.steps == ["store", "held", "stored", "log"])
        #expect(calls.forgets == [Self.alice.id])
        #expect(calls.heldScrubs == [ids])
        #expect(calls.storedScrubs.map(\.people) == [ids])
        #expect(calls.storedScrubs.map(\.skipping) == [calls.held])
        #expect(calls.logRemovals == [ids])
        #expect(model.pending == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func forgetEveryoneClearsEverything() async {
        let calls = Calls()
        let model = await model(calls: calls)

        model.requestForgetEveryone()
        await model.confirm()

        #expect(calls.steps == ["store", "held", "stored", "log"])
        #expect(calls.forgets == [nil])
        #expect(calls.heldScrubs == [nil])
        #expect(calls.storedScrubs.map(\.people) == [nil])
        #expect(calls.storedScrubs.map(\.skipping) == [calls.held])
        #expect(calls.logRemovals == [nil])
    }

    @Test func aFailedStoreWriteStillScrubsAndSaysSo() async throws {
        let calls = Calls()
        calls.forgetFailure = DiskFull()
        let model = await model(calls: calls)

        model.requestForget(try row(model, "Bob"))
        await model.confirm()

        #expect(calls.steps == ["store", "held", "stored", "log"])
        #expect(calls.logRemovals == [[Self.bob.id]])
        #expect(model.errorMessage == "Could not save the remembered voices (disk full)")
    }

    @Test func theForgetDialogsCopy() async throws {
        let model = await model()

        model.requestForget(try row(model, "Alice"))
        let one = try #require(model.pending)
        #expect(one.title == "Forget Alice?")
        #expect(one.message == "Their stored voice, their voice data in past meetings and their lines in the match"
            + " log are deleted. Transcripts keep the name as text.")
        #expect(one.confirmTitle == "Forget")

        model.requestForgetEveryone()
        let everyone = try #require(model.pending)
        #expect(everyone.title == "Forget everyone?")
        #expect(everyone.message == "Deletes all 4 people, the voice data kept inside every past meeting and the match"
            + " log. Transcripts keep their names as text. This cannot be undone.")
        #expect(everyone.confirmTitle == "Forget everyone")

        let single = await self.model([Self.bob])
        single.requestForgetEveryone()
        #expect(single.pending?.message.hasPrefix("Deletes 1 person, the voice data") == true)

        #expect(PeopleModel.forgetEveryoneTitle == "Forget everyone")
        #expect(PeopleModel.forgetEveryoneDetail == "Deletes every remembered voice, the voice data kept inside past"
            + " meetings and the match log. Names already written in transcripts stay.")
        #expect(PeopleModel.forgetEveryoneAction == "Forget Everyone…")
    }

    @Test func forgetIsUnavailableWhileRecording() async throws {
        let calls = Calls()
        let model = await model(calls: calls)
        model.isRecording = true

        model.requestForget(try row(model, "Alice"))
        #expect(model.pending == nil)
        model.requestForgetEveryone()
        #expect(model.pending == nil)
        await model.confirm()

        #expect(calls.steps.isEmpty)
    }

    @Test func theUsersEntryCanBeForgotten() async throws {
        let calls = Calls()
        let model = await model(calls: calls)

        model.requestForget(try row(model, "Sample User"))
        let pending = try #require(model.pending)
        #expect(pending.title == "Forget Sample User?")
        #expect(pending.message == "Your stored voice, your voice data in past meetings and your lines in the match"
            + " log are deleted. Your voice is learned again in your next remote meeting while a Remember voices"
            + " switch is on.")
        await model.confirm()

        #expect(calls.forgets == [Self.you.id])
    }
}

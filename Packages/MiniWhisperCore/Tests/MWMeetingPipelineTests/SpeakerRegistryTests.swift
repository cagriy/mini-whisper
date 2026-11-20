import Foundation
import MWMeetings
import MWTestSupport
import Testing

import MWMeetingPipeline

@Suite struct SpeakerRegistryTests {
    @Test func userIsIdZeroWithTheUsersName() {
        let registry = SpeakerRegistry(userName: "Alex")
        #expect(registry.labels == [SpeakerLabel(id: 0, name: "Alex", isUser: true)])
        #expect(SpeakerRegistry.userID == 0)
    }

    @Test func firstSightAllocatesTheNextSpeakerNumber() {
        var registry = SpeakerRegistry(userName: "Alex")
        #expect(registry.resolve(session: 1, label: "S1") == 1)
        #expect(registry.resolve(session: 1, label: "S2") == 2)
        #expect(registry.labels.map(\.name) == ["Alex", "Speaker 1", "Speaker 2"])
        #expect(registry.labels.map(\.providerKeys) == [[], ["1:S1"], ["1:S2"]])
        #expect(registry.labels.dropFirst().allSatisfy { !$0.isUser })
    }

    @Test func sameSessionAndLabelMapToOneID() {
        var registry = SpeakerRegistry(userName: "Alex")
        let first = registry.resolve(session: 1, label: "S1")
        #expect(registry.resolve(session: 1, label: "S1") == first)
        #expect(registry.id(session: 1, label: "S1") == first)
        #expect(registry.labels.count == 2)
    }

    @Test func aNewSessionsLabelsAllocateFreshNumbers() {
        var registry = SpeakerRegistry(userName: "Alex")
        #expect(registry.resolve(session: 1, label: "S1") == 1)
        #expect(registry.id(session: 2, label: "S1") == nil)
        #expect(registry.resolve(session: 2, label: "S1") == 2)
        #expect(registry.labels.map(\.name) == ["Alex", "Speaker 1", "Speaker 2"])
    }

    @Test func renameChangesTheNameOnly() {
        var registry = SpeakerRegistry(userName: "Alex")
        _ = registry.resolve(session: 1, label: "S1")
        _ = registry.resolve(session: 1, label: "S2")

        #expect(registry.rename(1, to: "Marta") == nil)
        #expect(registry.labels == [
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Marta", providerKeys: ["1:S1"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:S2"]),
        ])
        #expect(registry.rename(0, to: "Alexandra") == nil)
        #expect(registry.labels[0] == SpeakerLabel(id: 0, name: "Alexandra", isUser: true))
        #expect(registry.rename(9, to: "Nobody") == nil)
        #expect(registry.labels.count == 3)
    }

    @Test func renameToAnExistingNameMergesAndRepointsProviderKeys() {
        var registry = SpeakerRegistry(userName: "Alex")
        _ = registry.resolve(session: 1, label: "S1")
        registry.rename(1, to: "Marta")
        #expect(registry.resolve(session: 2, label: "S1") == 2)

        #expect(registry.rename(2, to: "Marta") == SpeakerRegistry.Merge(from: 2, into: 1))
        #expect(registry.labels == [
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Marta", providerKeys: ["1:S1", "2:S1"]),
        ])
        #expect(registry.resolve(session: 2, label: "S1") == 1)
        #expect(registry.labels.count == 2)

        // The merged-away number is free again.
        #expect(registry.resolve(session: 2, label: "S2") == 2)

        // Onto the user's name, or the user onto another's, the user survives as 0.
        #expect(registry.rename(2, to: "Alex") == SpeakerRegistry.Merge(from: 2, into: 0))
        #expect(registry.rename(0, to: "Marta") == SpeakerRegistry.Merge(from: 1, into: 0))
        #expect(registry.labels == [
            SpeakerLabel(id: 0, name: "Marta", isUser: true, providerKeys: ["2:S2", "1:S1", "2:S1"]),
        ])
        #expect(registry.resolve(session: 1, label: "S1") == 0)
    }

    @Test func bindingALabelToTheUserMapsItToZero() {
        var registry = SpeakerRegistry(userName: "Alex")
        #expect(registry.resolve(session: 1, label: "S1") == 1)

        registry.bindToUser(session: 1, label: "S1")
        registry.bindToUser(session: 1, label: "S2")
        #expect(registry.resolve(session: 1, label: "S1") == 0)
        #expect(registry.resolve(session: 1, label: "S2") == 0)
        // Speaker 1 keeps its number for the segments it already has.
        #expect(registry.labels == [
            SpeakerLabel(id: 0, name: "Alex", isUser: true, providerKeys: ["1:S1", "1:S2"]),
            SpeakerLabel(id: 1, name: "Speaker 1"),
        ])
        #expect(registry.resolve(session: 1, label: "S3") == 2)
    }

    @Test func restoresFromStoredSpeakerLabels() {
        let stored = MeetingFixtures.northwind().meeting.speakers
        var registry = SpeakerRegistry(labels: stored)

        #expect(registry.labels == stored)
        #expect(registry.resolve(session: 2, label: "S1") == 0)
        #expect(registry.resolve(session: 1, label: "S1") == 1)
        #expect(registry.resolve(session: 3, label: "S1") == 2)
        #expect(registry.resolve(session: 4, label: "S1") == 3)
        #expect(registry.labels.last == SpeakerLabel(id: 3, name: "Speaker 3", providerKeys: ["4:S1"]))
        #expect(registry.rename(3, to: "Priya") == SpeakerRegistry.Merge(from: 3, into: 2))
    }

    // MARK: Voice matches

    private let alice = UUID(uuidString: "0B6F7C1E-2D3A-4B5C-8D9E-0F1A2B3C4D5E")!
    private let bob = UUID(uuidString: "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D")!
    private let carol = UUID(uuidString: "3C2B1A09-8F7E-4D6C-9B5A-4F3E2D1C0B9A")!
    private let dave = UUID(uuidString: "7E6D5C4B-3A29-4F18-8E07-D6C5B4A39281")!
    private let me = UUID(uuidString: "1F2E3D4C-5B6A-4798-8A6B-5C4D3E2F1A0B")!
    private let user = SpeakerLabel(id: 0, name: "Alex", isUser: true)

    private func match(
        _ key: String, _ name: String, _ person: UUID?, _ state: NameMatch.State = .suggested, score: Double? = 0.6
    ) -> NameMatch {
        NameMatch(key: key, name: name, person: person, state: state, score: score)
    }

    /// The user, then one default-named speaker per `"1:<label>"`.
    private func numbered(_ labels: String...) -> SpeakerRegistry {
        var registry = SpeakerRegistry(userName: "Alex")
        for label in labels { _ = registry.resolve(session: 1, label: label) }
        return registry
    }

    @Test func suggestStoresTheMatchAndKeepsTheName() {
        var registry = numbered("A", "B")
        let suggestion = match("1:A", "Alice", alice)

        registry.suggest(suggestion)
        #expect(registry.labels == [
            user,
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], matches: [suggestion]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"]),
        ])

        // Whatever state it arrives with, a suggestion is stored as one.
        registry.suggest(match("1:B", "Bob", bob, .applied))
        #expect(registry.labels[2].matches == [match("1:B", "Bob", bob)])
        #expect(registry.labels[2].name == "Speaker 2")

        let before = registry.labels
        registry.suggest(match("9:Z", "Alice", alice))
        #expect(registry.labels == before)
    }

    @Test func aLaterMatchForTheSameKeyReplacesTheEarlier() {
        var registry = SpeakerRegistry(labels: [
            user, SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A", "2:A"]),
        ])
        registry.suggest(match("1:A", "Alice", alice, score: 0.55))
        registry.suggest(match("2:A", "Bob", bob))
        registry.suggest(match("1:A", "Carol", carol, score: 0.62))

        #expect(registry.labels[1].matches == [
            match("1:A", "Carol", carol, score: 0.62),
            match("2:A", "Bob", bob),
        ])
    }

    @Test func applyRenamesADefaultNamedSpeaker() {
        var registry = numbered("A")
        registry.suggest(match("1:A", "Bob", bob))
        let sure = match("1:A", "Alice", alice, .applied, score: 0.83)

        #expect(registry.apply(sure, userName: nil) == nil)
        // Named, the suggestion replaced, and not linked: an applied name teaches nothing.
        #expect(registry.labels == [
            user, SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], matches: [sure]),
        ])

        // Stored as applied whatever state it arrives with.
        _ = registry.resolve(session: 1, label: "B")
        #expect(registry.apply(match("1:B", "Bob", bob), userName: nil) == nil)
        #expect(registry.labels[2] == SpeakerLabel(
            id: 2, name: "Bob", providerKeys: ["1:B"], matches: [match("1:B", "Bob", bob, .applied)]
        ))
    }

    @Test func applyOntoAnExistingNameMergesAndKeepsTheMatchOnTheSurvivor() {
        var registry = numbered("A", "B")
        registry.rename(1, to: "Alice")
        let sure = match("1:B", "Alice", alice, .applied, score: 0.8)

        #expect(registry.apply(sure, userName: nil) == SpeakerRegistry.Merge(from: 2, into: 1))
        #expect(registry.labels == [
            user, SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A", "1:B"], matches: [sure]),
        ])
        #expect(registry.id(session: 1, label: "B") == 1)
    }

    @Test func applyOfTheUsersPersonRenamesToTheUserName() {
        var registry = numbered("A")
        // The person's stored name may differ from the meeting's user name.
        let sure = match("1:A", "Alexander", me, .applied, score: 0.9)

        #expect(registry.apply(sure, userName: "Alex") == SpeakerRegistry.Merge(from: 1, into: 0))
        #expect(registry.labels == [
            SpeakerLabel(id: 0, name: "Alex", isUser: true, providerKeys: ["1:A"], matches: [sure]),
        ])
    }

    @Test func applyLeavesANamedALinkedOrTheUserSpeakerAlone() {
        let labels = [
            SpeakerLabel(id: 0, name: "Alex", isUser: true, providerKeys: ["1:C"]),
            SpeakerLabel(id: 1, name: "Marta", providerKeys: ["1:A"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], person: bob),
            SpeakerLabel(id: 3, name: "Speaker 1", providerKeys: ["1:D"]),
        ]
        var registry = SpeakerRegistry(labels: labels)

        for key in ["1:A", "1:B", "1:C", "1:D", "9:Z"] {
            #expect(registry.apply(match(key, "Alice", alice, .applied), userName: nil) == nil)
            #expect(registry.apply(match(key, "Alexander", me, .applied), userName: "Alex") == nil)
        }
        #expect(registry.labels == labels)
    }

    @Test func acceptRenamesLinksAndRemovesTheMatch() throws {
        var registry = numbered("A", "B")
        let other = match("1:B", "Bob", bob)
        registry.suggest(match("1:A", "Alice", alice))
        registry.suggest(other)

        let result = registry.accept(key: "1:A")
        let accepted = try #require(result)
        #expect(accepted.person == alice)
        #expect(accepted.merge == nil)
        #expect(registry.labels == [
            user,
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: alice),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], matches: [other]),
        ])

        // Nothing stands for the key, or the key is unknown.
        #expect(registry.accept(key: "1:A") == nil)
        #expect(registry.accept(key: "9:Z") == nil)

        // An applied name is not a suggestion and cannot be confirmed.
        _ = registry.apply(match("1:B", "Bob", bob, .applied), userName: nil)
        let before = registry.labels
        #expect(registry.accept(key: "1:B") == nil)
        #expect(registry.labels == before)
    }

    @Test func acceptOntoAnExistingNameMerges() throws {
        var registry = numbered("A", "B")
        registry.suggest(match("1:A", "Alice", alice))
        registry.suggest(match("1:B", "Alice", alice))
        _ = registry.accept(key: "1:A")

        // Two speakers accepted as one person merge, as a rename does.
        let secondResult = registry.accept(key: "1:B")
        let second = try #require(secondResult)
        #expect(second.person == alice)
        #expect(second.merge == SpeakerRegistry.Merge(from: 2, into: 1))
        #expect(registry.labels == [
            user, SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A", "1:B"], person: alice),
        ])

        // In the room a suggestion of the user carries the user's name and merges into the user.
        #expect(registry.resolve(session: 1, label: "C") == 2)
        registry.suggest(match("1:C", "Alex", me))
        let mineResult = registry.accept(key: "1:C")
        let mine = try #require(mineResult)
        #expect(mine.person == me)
        #expect(mine.merge == SpeakerRegistry.Merge(from: 2, into: 0))
        #expect(registry.labels[0] == SpeakerLabel(
            id: 0, name: "Alex", isUser: true, providerKeys: ["1:C"], person: me
        ))

        // A match without a person leaves the survivor's link alone.
        #expect(registry.resolve(session: 1, label: "D") == 2)
        registry.suggest(match("1:D", "Alice", nil))
        let unlinkedResult = registry.accept(key: "1:D")
        let unlinked = try #require(unlinkedResult)
        #expect(unlinked.person == nil)
        #expect(unlinked.merge == SpeakerRegistry.Merge(from: 2, into: 1))
        #expect(registry.labels[1] == SpeakerLabel(
            id: 1, name: "Alice", providerKeys: ["1:A", "1:B", "1:D"], person: alice
        ))
    }

    @Test func dismissRemovesTheMatchAndRejectsThePerson() {
        var registry = numbered("A", "B")
        let suggestion = match("1:A", "Alice", alice)
        registry.suggest(suggestion)

        #expect(registry.dismiss(key: "1:A") == suggestion)
        #expect(registry.labels[1] == SpeakerLabel(
            id: 1, name: "Speaker 1", providerKeys: ["1:A"], rejected: [alice]
        ))

        // A person is rejected once.
        registry.suggest(suggestion)
        registry.dismiss(key: "1:A")
        #expect(registry.labels[1].rejected == [alice])

        #expect(registry.dismiss(key: "1:A") == nil)
        #expect(registry.dismiss(key: "9:Z") == nil)

        // An applied name is left to "Not <name>".
        _ = registry.apply(match("1:B", "Bob", bob, .applied), userName: nil)
        let before = registry.labels
        #expect(registry.dismiss(key: "1:B") == nil)
        #expect(registry.labels == before)
    }

    @Test func detachOfASoleUnlinkedKeyReturnsItToSpeakerN() {
        var registry = numbered("A", "B")
        _ = registry.apply(match("1:B", "Alice", alice, .applied), userName: nil)

        #expect(registry.detach(key: "1:B") == nil)
        #expect(registry.labels == [
            user,
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"], rejected: [alice]),
        ])

        // Nothing applied for the key: a suggestion, no match, an unknown key.
        registry.suggest(match("1:A", "Bob", bob))
        let before = registry.labels
        #expect(registry.detach(key: "1:A") == nil)
        #expect(registry.detach(key: "1:B") == nil)
        #expect(registry.detach(key: "9:Z") == nil)
        #expect(registry.labels == before)
    }

    @Test func detachOfOneOfSeveralKeysMovesItToANewSpeaker() {
        var registry = numbered("A", "B", "C")
        registry.rename(1, to: "Alice")
        let applied = match("1:C", "Alice", alice, .applied, score: 0.8)
        #expect(registry.apply(applied, userName: nil) == SpeakerRegistry.Merge(from: 3, into: 1))

        #expect(registry.detach(key: "1:C") == SpeakerRegistry.Detach(key: "1:C", from: 1, to: 3))
        #expect(registry.labels == [
            user,
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"]),
            SpeakerLabel(id: 2, name: "Speaker 2", providerKeys: ["1:B"]),
            SpeakerLabel(id: 3, name: "Speaker 3", providerKeys: ["1:C"], rejected: [alice]),
        ])
        #expect(registry.resolve(session: 1, label: "C") == 3)

        // A linked speaker keeps its name and person even when that was its only key.
        var linked = SpeakerRegistry(labels: [
            user,
            SpeakerLabel(id: 4, name: "Bob", providerKeys: ["2:A"], person: bob,
                         matches: [match("2:A", "Bob", bob, .applied)]),
        ])
        #expect(linked.detach(key: "2:A") == SpeakerRegistry.Detach(key: "2:A", from: 4, to: 5))
        #expect(linked.labels == [
            user,
            SpeakerLabel(id: 4, name: "Bob", person: bob),
            SpeakerLabel(id: 5, name: "Speaker 5", providerKeys: ["2:A"], rejected: [bob]),
        ])

        // The user is never renamed to a default name: the key moves instead.
        var room = numbered("A")
        _ = room.apply(match("1:A", "Alexander", me, .applied), userName: "Alex")
        #expect(room.detach(key: "1:A") == SpeakerRegistry.Detach(key: "1:A", from: 0, to: 1))
        #expect(room.labels == [
            user, SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"], rejected: [me]),
        ])
    }

    @Test func linkSetsThePersonAndRejectsOtherPeoplesMatches() {
        var registry = SpeakerRegistry(labels: [
            user,
            SpeakerLabel(
                id: 1, name: "Alice", providerKeys: ["1:A", "2:A"],
                matches: [match("1:A", "Alice", alice), match("2:A", "Bob", bob, .applied)],
                rejected: [carol]
            ),
        ])

        registry.link(1, person: alice)
        #expect(registry.labels[1] == SpeakerLabel(
            id: 1, name: "Alice", providerKeys: ["1:A", "2:A"], person: alice, rejected: [carol, bob]
        ))

        // Clearing the link rejects every removed match's person.
        registry.suggest(match("1:A", "Dave", dave))
        registry.link(1, person: nil)
        #expect(registry.labels[1] == SpeakerLabel(
            id: 1, name: "Alice", providerKeys: ["1:A", "2:A"], rejected: [carol, bob, dave]
        ))

        let before = registry.labels
        registry.link(9, person: alice)
        #expect(registry.labels == before)
    }

    @Test func bindingAKeyToTheUserDropsItsMatch() {
        var registry = SpeakerRegistry(labels: [
            user,
            SpeakerLabel(
                id: 1, name: "Speaker 1", providerKeys: ["1:A", "1:B"],
                matches: [match("1:A", "Alice", alice), match("1:B", "Bob", bob)]
            ),
        ])

        registry.bindToUser(session: 1, label: "A")

        #expect(registry.labels == [
            SpeakerLabel(id: 0, name: "Alex", isUser: true, providerKeys: ["1:A"]),
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:B"], matches: [match("1:B", "Bob", bob)]),
        ])
    }

    @Test func aRenameMergeCarriesMatchesRejectedAndPerson() {
        var registry = SpeakerRegistry(labels: [
            user,
            SpeakerLabel(id: 1, name: "Alice", providerKeys: ["1:A"], person: alice, rejected: [carol]),
            SpeakerLabel(
                id: 2, name: "Speaker 2", providerKeys: ["1:B"], person: bob,
                matches: [match("1:B", "Bob", bob)], rejected: [carol, dave]
            ),
            SpeakerLabel(id: 3, name: "Dana", providerKeys: ["2:A"], matches: [match("2:A", "Dana", nil)]),
            SpeakerLabel(id: 4, name: "Speaker 4", providerKeys: ["2:B"], person: dave, rejected: [bob]),
        ])

        // The survivor keeps its person; matches and rejections union.
        #expect(registry.rename(2, to: "Alice") == SpeakerRegistry.Merge(from: 2, into: 1))
        #expect(registry.labels[1] == SpeakerLabel(
            id: 1, name: "Alice", providerKeys: ["1:A", "1:B"], person: alice,
            matches: [match("1:B", "Bob", bob)], rejected: [carol, dave]
        ))

        // A survivor without a person takes the absorbed speaker's.
        #expect(registry.rename(4, to: "Dana") == SpeakerRegistry.Merge(from: 4, into: 3))
        #expect(registry.labels[2] == SpeakerLabel(
            id: 3, name: "Dana", providerKeys: ["2:A", "2:B"], person: dave,
            matches: [match("2:A", "Dana", nil)], rejected: [bob]
        ))

        // Into the user, today's rule, with the same carrying.
        #expect(registry.rename(1, to: "Alex") == SpeakerRegistry.Merge(from: 1, into: 0))
        #expect(registry.labels[0] == SpeakerLabel(
            id: 0, name: "Alex", isUser: true, providerKeys: ["1:A", "1:B"], person: alice,
            matches: [match("1:B", "Bob", bob)], rejected: [carol, dave]
        ))
    }
}

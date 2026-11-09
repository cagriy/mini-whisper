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
}

import Foundation
import Testing

import MWVoices

@Suite struct SpeechmaticsEnrolmentTests {
    private static let start = Date(timeIntervalSince1970: 1_793_491_200)  // 2026-11-01T00:00:00Z

    private func day(_ n: Int) -> Date {
        Self.start.addingTimeInterval(Double(n) * 86_400)
    }

    /// A person heard on `heard`, holding an identifier per tier dated as given.
    private func person(_ name: String, heard: Int? = nil, standard: Int? = nil, enhanced: Int? = nil) -> Person {
        var identifiers: [String: SpeechmaticsIdentifier] = [:]
        for (tier, at) in [("standard", standard), ("enhanced", enhanced)] {
            guard let at else { continue }
            identifiers[tier] = SpeechmaticsIdentifier(meeting: UUID(), at: day(at), identifier: "\(tier)-\(name)")
        }
        return Person(name: name, createdAt: Self.start, lastHeard: heard.map { day($0) }, speechmatics: identifiers)
    }

    @Test func onlyPeopleWithAnIdentifierForTheTier() {
        let alice = person("Alice", heard: 4, standard: 1)
        let bob = person("Bob", heard: 3, enhanced: 1)
        let carol = person("Carol", heard: 2)
        let dave = person("Dave", heard: 1, standard: 1, enhanced: 1)
        let people = [alice, bob, carol, dave]

        let standard = SpeechmaticsEnrolment.entries(people: people, tier: "standard")
        #expect(standard.map(\.person.id) == [alice.id, dave.id])
        #expect(standard.map(\.identifier) == ["standard-Alice", "standard-Dave"])

        let enhanced = SpeechmaticsEnrolment.entries(people: people, tier: "enhanced")
        #expect(enhanced.map(\.person.id) == [bob.id, dave.id])
        #expect(enhanced.map(\.identifier) == ["enhanced-Bob", "enhanced-Dave"])

        #expect(SpeechmaticsEnrolment.entries(people: [carol], tier: "standard").isEmpty)
        #expect(SpeechmaticsEnrolment.entries(people: [], tier: "standard").isEmpty)
    }

    @Test func newestHeardFirstFallingBackToTheIdentifiersDate() {
        let alice = person("Alice", heard: 1, standard: 0)
        let bob = person("Bob", standard: 3)
        let carol = person("Carol", heard: 5, standard: 0)
        let dave = person("Dave", heard: 2, standard: 10)

        let entries = SpeechmaticsEnrolment.entries(people: [alice, bob, carol, dave], tier: "standard")

        #expect(entries.map(\.person.name) == ["Carol", "Bob", "Dave", "Alice"])
    }

    @Test func atMostFifty() {
        let people = (0..<60).map { (n: Int) in person("P\(n)", heard: n, standard: 0) }

        let entries = SpeechmaticsEnrolment.entries(people: people, tier: "standard")

        #expect(SpeechmaticsEnrolment.limit == 50)
        #expect(entries.count == 50)
        #expect(entries.map(\.person.name) == (10..<60).reversed().map { "P\($0)" })
    }

    @Test func theLabelIsMwAndTheLowercasePersonUUID() throws {
        let alice = person("Alice", heard: 1, standard: 1)
        let label = SpeechmaticsEnrolment.label(for: alice.id)

        #expect(label == "mw:" + alice.id.uuidString.lowercased())
        #expect(label == label.lowercased())
        #expect(!label.localizedCaseInsensitiveContains("alice"))

        let entry = try #require(SpeechmaticsEnrolment.entries(people: [alice], tier: "standard").first)
        #expect(entry.label == label)
    }

    @Test func aLabelParsesBackToAKnownPersonOnly() {
        let alice = person("Alice", standard: 1)
        let bob = person("Bob", standard: 2)
        let people = [alice, bob]
        let uuid = alice.id.uuidString

        #expect(SpeechmaticsEnrolment.person(forLabel: "mw:" + uuid.lowercased(), among: people)?.id == alice.id)
        #expect(SpeechmaticsEnrolment.person(forLabel: SpeechmaticsEnrolment.label(for: bob.id), among: people) == bob)

        #expect(SpeechmaticsEnrolment.person(forLabel: "mw:" + UUID().uuidString.lowercased(), among: people) == nil)
        #expect(SpeechmaticsEnrolment.person(forLabel: "mw:" + uuid.lowercased(), among: [bob]) == nil)
        for label in ["S1", "", "mw:", "mw:" + uuid.uppercased(), "MW:" + uuid.lowercased(), uuid.lowercased(),
                      "mw:" + uuid.lowercased() + " ", " mw:" + uuid.lowercased(), "mw:{" + uuid.lowercased() + "}"] {
            #expect(SpeechmaticsEnrolment.person(forLabel: label, among: people) == nil, "\(label)")
        }
    }
}

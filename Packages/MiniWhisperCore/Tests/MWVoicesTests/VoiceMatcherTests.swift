import Foundation
import MWConfig
import MWMeetings
import MWTestSupport
import Testing

import MWVoices

private func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

/// The probe is `.unit(0)`; each stored vector's cosine with it is an exact ratio of integers.
@Suite struct VoiceMatcherTests {
    private static let at = Date(timeIntervalSince1970: 1_793_491_200)
    private let probe = VoiceVector.unit(0)
    private let settings = VoiceSettings()  // sure 0.70, suggestion 0.50, margin 0.10

    private static let scores: [Double: VoiceVector] = [
        0.75: .padded([3, 2, 1, 1, 1]),
        0.70: .padded([7, 7, 1, 1]),
        0.60: .padded([3, 4]),
        0.50: .padded([1, 1, 1, 1]),
        0.40: .padded([2, 4, 2, 1]),
    ]

    private func person(_ name: String, _ scores: Double..., isUser: Bool = false) -> Person {
        Person(
            name: name, isUser: isUser, createdAt: Self.at,
            local: scores.map { LocalSample(meeting: UUID(), at: Self.at, seconds: 20, vector: Self.scores[$0]!) }
        )
    }

    private func decide(
        _ people: [Person], settings: VoiceSettings? = nil, excluding: Set<UUID> = [], includeUser: Bool = false
    ) -> VoiceMatcher.Decision {
        VoiceMatcher.decide(
            probe: probe, people: people, settings: settings ?? self.settings, excluding: excluding,
            includeUser: includeUser
        )
    }

    @Test func sureNeedsTheThresholdAndTheMargin() {
        let alice = person("Alice", 0.70)
        let sure = decide([alice, person("Bob", 0.60)])
        #expect(sure.outcome == .sure)
        #expect(sure.person?.id == alice.id)
        #expect(close(sure.score, 0.70))
        #expect(close(sure.runnerUp, 0.60))

        let crowded = decide([person("Alice", 0.75), person("Bob", 0.70)])
        #expect(crowded.outcome == .none)
        #expect(crowded.person == nil)
        #expect(close(crowded.score, 0.75))
        #expect(close(crowded.runnerUp, 0.70))
    }

    @Test func belowSureAboveSuggestionIsASuggestion() {
        let alice = person("Alice", 0.60)
        let decision = decide([alice, person("Bob", 0.40)])
        #expect(decision.outcome == .suggestion)
        #expect(decision.person?.id == alice.id)

        let stricter = settings.setting(.sure, to: 0.80)
        #expect(decide([person("Alice", 0.70)], settings: stricter).outcome == .suggestion)
    }

    @Test func marginExactlyMetPasses() {
        #expect(decide([person("Alice", 0.60), person("Bob", 0.50)]).outcome == .suggestion)
        #expect(decide([person("Alice", 0.70), person("Bob", 0.60)]).outcome == .sure)
    }

    @Test func withOnePersonTheRunnerUpIsZero() {
        let decision = decide([person("Alice", 0.70)])

        #expect(decision.outcome == .sure)
        #expect(decision.runnerUp == 0)
    }

    @Test func aPersonsScoreIsTheirBestSample() {
        let alice = person("Alice", 0.50, 0.75, 0.40)
        let decision = decide([person("Bob", 0.60), alice])

        #expect(decision.outcome == .sure)
        #expect(decision.person?.id == alice.id)
        #expect(close(decision.score, 0.75))
        #expect(close(decision.runnerUp, 0.60))
    }

    @Test func rejectedPeopleAreNotCandidates() {
        let alice = person("Alice", 0.75)
        let bob = person("Bob", 0.70)
        #expect(decide([alice, bob]).outcome == .none)

        let decision = decide([alice, bob], excluding: [alice.id])
        #expect(decision.outcome == .sure)
        #expect(decision.person?.id == bob.id)
        #expect(decision.runnerUp == 0)
    }

    @Test func theUserIsACandidateOnlyWhenAsked() {
        let user = person("Alex", 0.75, isUser: true)
        let bob = person("Bob", 0.60)

        let remote = decide([user, bob], includeUser: false)
        #expect(remote.outcome == .suggestion)
        #expect(remote.person?.id == bob.id)
        #expect(remote.runnerUp == 0)

        let inRoom = decide([user, bob], includeUser: true)
        #expect(inRoom.outcome == .sure)
        #expect(inRoom.person?.id == user.id)
    }

    @Test func aWeakBestIsNothing() {
        let decision = decide([person("Alice", 0.40)])

        #expect(decision.outcome == .none)
        #expect(decision.person == nil)
        #expect(close(decision.score, 0.40))
    }

    @Test func noPeopleIsNothing() {
        let nobody = VoiceMatcher.Decision(outcome: .none, person: nil, score: 0, runnerUp: 0)

        #expect(decide([]) == nobody)
        #expect(decide([person("Alice")]) == nobody)
    }
}

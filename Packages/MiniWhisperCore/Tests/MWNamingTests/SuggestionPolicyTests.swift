import Foundation
import MWMeetings
import MWTranscription
import Testing

import MWNaming

@Suite struct SuggestionPolicyTests {
    private let kate = UUID(uuidString: "0B6F7C1E-2D3A-4B5C-8D9E-0F1A2B3C4D5E")!
    private let siobhan = UUID(uuidString: "6A1D2C3B-4E5F-4A7B-8C9D-0E1F2A3B4C5D")!

    private func open(
        id: Int = 2, name: String = "Speaker 2", isUser: Bool = false, person: UUID? = nil, matches: [NameMatch] = []
    ) -> Bool {
        SuggestionPolicy.isOpen(SpeakerLabel(
            id: id, name: name, isUser: isUser, providerKeys: ["1:A", "1:B"], person: person, matches: matches
        ))
    }

    @Test func isOpen() {
        let heard = NameMatch(key: "1:A", name: "Kate", person: nil, source: "conversation", state: .suggested)
        let voice = NameMatch(key: "1:B", name: "Kate", person: kate, state: .suggested, score: 0.6)

        #expect(open())
        #expect(open(matches: [heard]))

        #expect(!open(id: 0, name: "Speaker 0", isUser: true))
        #expect(!open(name: "Kate"))
        #expect(!open(name: "Speaker 3"))
        #expect(!open(person: kate))
        #expect(!open(matches: [voice]))
        #expect(!open(matches: [heard, voice]))
    }

    // MARK: - decide

    private static func segment(_ speaker: Int, _ start: Double, _ text: String) -> Segment {
        Segment(speaker: speaker, start: start, end: start + 2, text: text, session: 1)
    }

    /// T1 S1, T2 S2, T3 S0 (the user), T4 S3.
    private let meeting = [
        segment(1, 0, "Hi, I'm Kate."),
        segment(2, 5, "Thanks Kate. I'm Dan, and Siobhan is joining."),
        segment(0, 10, "Welcome both."),
        segment(3, 15, "Hello, I'm Neve."),
    ]

    private func label(_ id: Int) -> SpeakerLabel {
        SpeakerLabel(id: id, name: SpeakerLabel.defaultName(id), isUser: id == 0, providerKeys: ["1:S\(id)"])
    }

    private func decide(
        _ raws: [RawSuggestion],
        segments: [Segment]? = nil,
        _ adjust: (inout PolicyContext) -> Void = { _ in }
    ) -> NamingDecision {
        let segments = segments ?? meeting
        var speakers = (0...3).map(label)
        speakers[0].name = "Niamh"
        var context = PolicyContext(
            speakers: speakers,
            people: [],
            userName: "Niamh",
            aliases: ["Neve"],
            mode: .remote,
            autoApply: false,
            segmentSpeakers: Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0.speaker) })
        )
        adjust(&context)
        return SuggestionPolicy.decide(raws, rendered: NamingTranscript.render(segments: segments), context: context)
    }

    private func raw(
        _ speaker: String = "S1",
        _ name: String = "Kate",
        confidence: String = "certain",
        kind: String = "self_introduction",
        turn: Int = 1,
        quote: String = "I'm Kate"
    ) -> RawSuggestion {
        RawSuggestion(speaker: speaker, name: name, confidence: confidence, kind: kind, turn: turn, quote: quote)
    }

    private func match(
        _ name: String,
        speaker: Int,
        _ evidence: NameEvidence,
        kind: String = "self_introduction",
        state: NameMatch.State = .suggested
    ) -> NameMatch {
        NameMatch(
            key: "1:S\(speaker)", name: name, person: nil, source: "conversation", state: state,
            score: nil, evidence: evidence, kind: kind
        )
    }

    private var kateEvidence: NameEvidence {
        NameEvidence(segment: meeting[0].id, time: 0, text: "I'm Kate")
    }

    private var suggestKate: NamingAction {
        .suggest(speaker: 1, match("Kate", speaker: 1, kateEvidence))
    }

    @Test func keepsAVerifiedCertainSuggestion() {
        let decision = decide([raw()])

        #expect(decision.actions == [suggestKate])
        #expect(decision.dropped.isEmpty)
    }

    // Rule 1

    @Test func unknownOrUnparsableSpeakerIsDropped() {
        let decision = decide(["S9", "1", "S", "Speaker 1", "S1x", "s1"].map { raw($0) })

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [1: 6])
    }

    // Rule 2

    @Test func unknownConfidencesAndKindsAreDropped() {
        let decision = decide([raw(confidence: "CERTAIN"), raw(confidence: "possible"), raw(kind: "nickname")])

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [2: 3])
    }

    @Test func likelyIsKept() {
        let decision = decide([raw(confidence: "likely")])

        #expect(decision.actions == [suggestKate])
        #expect(decision.dropped.isEmpty)
    }

    @Test(arguments: ["self_introduction", "addressed", "handoff", "other"])
    func everyKnownKindIsKept(_ kind: String) {
        let decision = decide([raw(kind: kind)])

        #expect(decision.actions == [.suggest(speaker: 1, match("Kate", speaker: 1, kateEvidence, kind: kind))])
    }

    // Rule 3

    @Test func sanitiserRejectsAreDropped() {
        let decision = decide(["Kate!", "K8", "Speaker 4", "", "<b>Kate</b>"].map { raw("S1", $0) })

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [3: 5])
    }

    @Test func sanitisedNameIsTrimmed() {
        #expect(decide([raw("S1", "  Kate ")]).actions == [suggestKate])
    }

    // Rule 4

    @Test func unverifiedQuoteIsDropped() {
        let decision = decide([
            raw(quote: "I am Kate"),
            raw(turn: 2, quote: "I'm Kate"),
            raw(turn: 7, quote: "I'm Kate"),
            raw(quote: "Hi, I'm"),
        ])

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [4: 4])
    }

    // Rule 5

    @Test func closedTargetIsDropped() {
        let voice = NameMatch(key: "1:S1", name: "Kim", person: kate, state: .suggested, score: 0.7)
        let closings: [(inout PolicyContext) -> Void] = [
            { $0.speakers[1].name = "Bob" },
            { $0.speakers[1].person = self.kate },
            { $0.speakers[1].matches = [voice] },
        ]
        for close in closings {
            let decision = decide([raw()], close)
            #expect(decision.actions.isEmpty)
            #expect(decision.dropped == [5: 1])
        }

        let user = decide([raw("S0")])
        #expect(user.actions.isEmpty)
        #expect(user.dropped == [5: 1])
    }

    // Rule 6

    @Test func peopleSpellingIsUsed() {
        let decision = decide([raw("S3", "Siobhan", kind: "handoff", turn: 2, quote: "Siobhan is joining")]) {
            $0.people = [(id: self.siobhan, name: "Siobhán")]
        }

        let evidence = NameEvidence(segment: meeting[1].id, time: 5, text: "Siobhan is joining")
        #expect(decision.actions == [.suggest(speaker: 3, match("Siobhán", speaker: 3, evidence, kind: "handoff"))])
    }

    @Test func usersNameOrAliasIsDroppedInARemoteMeeting() {
        let said = [Self.segment(1, 0, "Niamh here."), Self.segment(3, 4, "Hello, I'm Neve.")]

        let decision = decide([
            raw("S1", "NIAMH", turn: 1, quote: "Niamh here"),
            raw("S3", "Neve", turn: 2, quote: "I'm Neve"),
        ], segments: said)

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [6: 2])
    }

    @Test func usersNameOrAliasBecomesTheUsersNameInARoom() {
        let said = [Self.segment(1, 0, "Niamh here."), Self.segment(3, 4, "Hello, I'm Neve.")]

        for (speaker, raw) in [(1, raw("S1", "NIAMH", turn: 1, quote: "Niamh here")), (3, raw("S3", "Neve", turn: 2, quote: "I'm Neve"))] {
            let decision = decide([raw], segments: said) { $0.mode = .inRoom }
            #expect(decision.actions.map(\.name) == ["Niamh"])
            #expect(decision.actions.map(\.speaker) == [speaker])
        }
    }

    @Test func aliasInARoomWithoutAUserNameIsDropped() {
        let decision = decide([raw("S3", "Neve", turn: 4, quote: "I'm Neve")]) {
            $0.mode = .inRoom
            $0.userName = nil
        }

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [6: 1])
    }

    // Rule 7

    @Test func rejectedNameIsDropped() {
        let decision = decide([raw()]) { $0.speakers[1].rejectedNames = ["KÁTE"] }

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [7: 1])
    }

    @Test func rejectedPersonIsDropped() {
        let handoff = raw("S3", "Siobhan", kind: "handoff", turn: 2, quote: "Siobhan is joining")

        let rejected = decide([handoff]) {
            $0.people = [(id: self.siobhan, name: "Siobhán")]
            $0.speakers[3].rejected = [self.siobhan]
        }
        #expect(rejected.actions.isEmpty)
        #expect(rejected.dropped == [7: 1])

        let other = decide([handoff]) {
            $0.people = [(id: self.siobhan, name: "Siobhán")]
            $0.speakers[3].rejected = [self.kate]
        }
        #expect(other.actions.count == 1)
    }

    // Rule 8

    @Test func oneSpeakerWithTwoNamesDropsBoth() {
        let decision = decide([
            raw("S2", "Kate", kind: "addressed", turn: 2, quote: "Thanks Kate"),
            raw("S2", "Dan", turn: 2, quote: "I'm Dan"),
        ])

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [8: 2])
    }

    @Test func oneSpeakerWithOneNameTwiceKeepsOneAndPrefersTheSelfIntroduction() {
        let decision = decide([
            raw("S1", "Kate", kind: "addressed", turn: 2, quote: "Thanks Kate"),
            raw(),
        ])

        #expect(decision.actions == [suggestKate])
        #expect(decision.dropped.isEmpty)
    }

    @Test func oneNameForTwoSpeakersKeepsTheOnlySelfIntroductionInItsOwnTurn() {
        let decision = decide([
            raw("S3", "Dan", kind: "addressed", turn: 2, quote: "I'm Dan"),
            raw("S2", "Dan", turn: 2, quote: "I'm Dan"),
        ])

        let evidence = NameEvidence(segment: meeting[1].id, time: 5, text: "I'm Dan")
        #expect(decision.actions == [.suggest(speaker: 2, match("Dan", speaker: 2, evidence))])
        #expect(decision.dropped == [8: 1])
    }

    @Test func oneNameForTwoSpeakersWithoutExactlyOneSelfIntroductionDropsAll() {
        let twice = [Self.segment(1, 0, "I'm Dan."), Self.segment(2, 4, "I'm Dan.")]

        let both = decide([raw("S1", "Dan", turn: 1, quote: "I'm Dan"), raw("S2", "Dan", turn: 2, quote: "I'm Dan")], segments: twice)
        #expect(both.actions.isEmpty)
        #expect(both.dropped == [8: 2])

        let neither = decide([
            raw("S1", "Dan", kind: "addressed", turn: 1, quote: "I'm Dan"),
            raw("S2", "Dan", kind: "other", turn: 2, quote: "I'm Dan"),
        ], segments: twice)
        #expect(neither.actions.isEmpty)
        #expect(neither.dropped == [8: 2])

        // A self-introduction quoted from another speaker's turn is not its own.
        let elsewhere = decide([
            raw("S1", "Dan", turn: 2, quote: "I'm Dan"),
            raw("S3", "Dan", turn: 2, quote: "I'm Dan"),
        ])
        #expect(elsewhere.actions.isEmpty)
        #expect(elsewhere.dropped == [8: 2])
    }

    @Test func likelyGivesWayToCertainForTheSameSpeaker() {
        let decision = decide([
            raw("S2", "Kate", confidence: "likely", kind: "addressed", turn: 2, quote: "Thanks Kate"),
            raw("S2", "Dan", turn: 2, quote: "I'm Dan"),
        ])

        let evidence = NameEvidence(segment: meeting[1].id, time: 5, text: "I'm Dan")
        #expect(decision.actions == [.suggest(speaker: 2, match("Dan", speaker: 2, evidence))])
        #expect(decision.dropped == [8: 1])
    }

    @Test func likelyGivesWayToCertainForTheSameName() {
        let decision = decide([
            raw("S3", "Kate", confidence: "likely", kind: "other", turn: 2, quote: "Thanks Kate"),
            raw("S1", "Kate", kind: "addressed", turn: 2, quote: "Thanks Kate"),
        ])

        let evidence = NameEvidence(segment: meeting[1].id, time: 5, text: "Thanks Kate")
        #expect(decision.actions == [.suggest(speaker: 1, match("Kate", speaker: 1, evidence, kind: "addressed"))])
        #expect(decision.dropped == [8: 1])
    }

    // Rule 9

    @Test func sameStandingNameEmitsNothing() {
        let standing = NameMatch(key: "1:S1", name: "KÁTE", person: nil, source: "conversation", state: .suggested)

        let decision = decide([raw()]) { $0.speakers[1].matches = [standing] }

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [9: 1])
    }

    @Test func differentStandingNameIsReplaced() {
        let standing = NameMatch(key: "1:S1", name: "Kim", person: nil, source: "conversation", state: .suggested)

        #expect(decide([raw()]) { $0.speakers[1].matches = [standing] }.actions == [suggestKate])
    }

    // Rule 10

    private var applyKate: NamingAction {
        .apply(speaker: 1, match("Kate", speaker: 1, kateEvidence, state: .applied))
    }

    @Test func selfIntroductionIsAppliedWhenEveryConditionHolds() {
        #expect(decide([raw()]) { $0.autoApply = true }.actions == [applyKate])
    }

    @Test func likelySelfIntroductionIsOnlySuggested() {
        #expect(decide([raw(confidence: "likely")]) { $0.autoApply = true }.actions == [suggestKate])
    }

    @Test func autoApplyOffSuggests() {
        #expect(decide([raw()]) { $0.autoApply = false }.actions == [suggestKate])
    }

    @Test func otherKindsAreOnlySuggested() {
        let decision = decide([raw(kind: "addressed")]) { $0.autoApply = true }

        #expect(decision.actions == [.suggest(speaker: 1, match("Kate", speaker: 1, kateEvidence, kind: "addressed"))])
    }

    @Test func evidenceSegmentNowOfAnotherSpeakerIsOnlySuggested() {
        let relabelled = decide([raw()]) {
            $0.autoApply = true
            $0.segmentSpeakers[self.meeting[0].id] = 2
        }
        #expect(relabelled.actions == [suggestKate])

        let deleted = decide([raw()]) {
            $0.autoApply = true
            $0.segmentSpeakers[self.meeting[0].id] = nil
        }
        #expect(deleted.actions == [suggestKate])
    }

    @Test func nameAnotherSpeakerHoldsIsOnlySuggested() {
        let decision = decide([raw()]) {
            $0.autoApply = true
            $0.speakers[3].name = "kate"
        }

        #expect(decision.actions == [suggestKate])
    }

    @Test func usersNameInARoomIsOnlySuggested() {
        let decision = decide([raw("S3", "Neve", turn: 4, quote: "I'm Neve")]) {
            $0.autoApply = true
            $0.mode = .inRoom
        }

        let evidence = NameEvidence(segment: meeting[3].id, time: 15, text: "I'm Neve")
        #expect(decision.actions == [.suggest(speaker: 3, match("Niamh", speaker: 3, evidence))])
    }

    // Cap

    @Test func atMost50SuggestionsAreProcessed() {
        let decision = decide(Array(repeating: raw("S9"), count: 50) + [raw()])

        #expect(decision.actions.isEmpty)
        #expect(decision.dropped == [1: 50])
    }
}

extension NamingAction {
    fileprivate var name: String {
        switch self {
        case .suggest(_, let match), .apply(_, let match): match.name
        }
    }

    fileprivate var speaker: Int {
        switch self {
        case .suggest(let speaker, _), .apply(let speaker, _): speaker
        }
    }
}

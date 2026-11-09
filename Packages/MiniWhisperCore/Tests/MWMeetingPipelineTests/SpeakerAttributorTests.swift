import Foundation
import MWMeetings
import MWStreaming
import Testing

import MWMeetingPipeline

@Suite struct SpeakerAttributorTests {
    private func segment(_ words: [(String, Double, Double)], label: String? = "S1") -> TranscriptSegment {
        let words = words.map { TranscriptWord(text: $0.0, start: $0.1, end: $0.2) }
        return TranscriptSegment(
            text: words.map(\.text).joined(separator: " "),
            words: words,
            speaker: label,
            turnOrder: 7,
            start: words.first?.start ?? 0,
            end: words.last?.end ?? 0
        )
    }

    private func spans(_ bounds: (Double, Double)...) -> SpeechGate.View {
        SpeechGate.View(spans: bounds.map { SpeechSpan(start: $0.0, end: $0.1) })
    }

    private func attribute(
        _ segment: TranscriptSegment,
        session: Int = 1,
        mode: MeetingMode = .remote,
        spans: SpeechGate.View = SpeechGate.View(),
        registry: SpeakerRegistry = SpeakerRegistry(userName: "Alex"),
        tallies: [String: SpeakerAttributor.Tally] = [:]
    ) -> SpeakerAttributor.Attribution {
        SpeakerAttributor.attribute(
            segment, session: session, mode: mode, spans: spans, registry: registry, tallies: tallies
        )
    }

    private func runs(_ result: SpeakerAttributor.Attribution) -> [(speaker: Int, text: String)] {
        result.segments.map { ($0.speaker, $0.text) }
    }

    @Test func wordWithHalfItsSpanInSpeechIsTheUsers() {
        let result = attribute(
            segment([("one", 0, 0.4), ("two", 1, 2), ("three", 3, 3.4)]), spans: spans((1.5, 2.5))
        )
        #expect(result.segments.map(\.speaker) == [1, 0, 1])
        #expect(result.segments[1].words == [Word(text: "two", start: 1, end: 2)])
    }

    @Test func wordBelowHalfKeepsTheProviderLabel() {
        let result = attribute(segment([("one", 1, 2)]), spans: spans((1.51, 2.5)))
        #expect(result.segments.map(\.speaker) == [1])
        #expect(result.registry.labels.map(\.name) == ["Alex", "Speaker 1"])
        #expect(result.tallies == ["1:S1": SpeakerAttributor.Tally(words: 1, inSpeech: 0)])
    }

    @Test func adjacentWordsWithOneOutcomeFormOneSegment() throws {
        let split = attribute(
            segment([("a", 0, 1), ("b", 1, 2), ("c", 3, 4), ("d", 4, 5), ("e", 6, 7)]),
            spans: spans((0, 2), (6, 7))
        )
        #expect(runs(split).map(\.speaker) == [0, 1, 0])
        #expect(runs(split).map(\.text) == ["a b", "c d", "e"])
        #expect(split.segments.map(\.start) == [0, 3, 6])
        #expect(split.segments.map(\.end) == [2, 5, 7])
        #expect(split.segments.allSatisfy { $0.session == 1 && $0.providerLabel == "S1" && $0.turnOrder == 7 })
        #expect(split.segments.allSatisfy { !$0.edited && !$0.pinned })
        #expect(Set(split.segments.map(\.id)).count == 3)

        // One outcome keeps the provider's own text.
        var whole = segment([("hello", 0, 1), ("there", 1, 2)])
        whole.text = "Hello there."
        let one = try #require(attribute(whole).segments.first)
        #expect(attribute(whole).segments.count == 1)
        #expect((one.speaker, one.text, one.start, one.end) == (1, "Hello there.", 0, 2))
        #expect(one.words == [Word(text: "hello", start: 0, end: 1), Word(text: "there", start: 1, end: 2)])
    }

    @Test func labelWithSeventyPercentGateWordsBindsToTheUser() {
        // 6 of 10 in speech: the words split, the label stays Speaker 1.
        let first = attribute(
            segment((0..<10).map { ("w\($0)", Double($0), Double($0) + 1) }), spans: spans((0, 6))
        )
        #expect(runs(first).map(\.speaker) == [0, 1])
        #expect(first.tallies["1:S1"] == SpeakerAttributor.Tally(words: 10, inSpeech: 6))

        // 8 of 10 more: 14 of 20 reaches 70 %, so every word of the label is the user's.
        let second = attribute(
            segment((10..<20).map { ("w\($0)", Double($0), Double($0) + 1) }),
            spans: spans((10, 18)), registry: first.registry, tallies: first.tallies
        )
        #expect(runs(second).map(\.speaker) == [0])
        #expect(second.segments[0].words.count == 10)
        #expect(second.registry.id(session: 1, label: "S1") == 0)

        // Later words of that label are the user's with no speech at all.
        let third = attribute(
            segment([("late", 30, 31)]), registry: second.registry, tallies: second.tallies
        )
        #expect(runs(third).map(\.speaker) == [0])

        // Another session's S1 is a different label.
        let other = attribute(
            segment([("new", 40, 41)]), session: 2, registry: third.registry, tallies: third.tallies
        )
        #expect(runs(other).map(\.speaker) == [2])
    }

    @Test func labelBoundOnFirstSightGetsNoSpeakerNumber() {
        let result = attribute(segment([("hi", 0, 1), ("all", 1, 2)]), spans: spans((0, 2)))
        #expect(runs(result).map(\.speaker) == [0])
        #expect(result.registry.labels.map(\.id) == [0])
        #expect(result.registry.labels[0].providerKeys == ["1:S1"])
    }

    @Test func inRoomNeverConsultsTheGate() {
        let result = attribute(
            segment([("a", 0, 1), ("b", 1, 2)]), mode: .inRoom, spans: spans((0, 10))
        )
        #expect(runs(result).map(\.speaker) == [1])
        #expect(result.tallies.isEmpty)
        #expect(result.registry.id(session: 1, label: "S1") == 1)
    }

    @Test func nilProviderLabelIsItsOwnSpeakerPerSession() {
        let unlabelled = attribute(segment([("mm", 0, 1)], label: nil), mode: .inRoom)
        #expect(runs(unlabelled).map(\.speaker) == [1])
        #expect(unlabelled.segments[0].providerLabel == nil)

        let labelled = attribute(
            segment([("yes", 2, 3)]), mode: .inRoom, registry: unlabelled.registry
        )
        let again = attribute(
            segment([("ok", 4, 5)], label: nil), mode: .inRoom, registry: labelled.registry
        )
        let nextSession = attribute(
            segment([("so", 6, 7)], label: nil), session: 2, mode: .inRoom, registry: again.registry
        )
        #expect([labelled, again, nextSession].map { $0.segments[0].speaker } == [2, 1, 3])
        #expect(nextSession.registry.labels.map(\.providerKeys) == [[], ["1:"], ["1:S1"], ["2:"]])

        // In a remote meeting the unlabelled key is tallied like any other.
        let remote = attribute(segment([("mm", 0, 1)], label: nil), spans: spans((0, 1)))
        #expect(remote.tallies == ["1:": SpeakerAttributor.Tally(words: 1, inSpeech: 1)])
        #expect(remote.registry.id(session: 1, label: nil) == 0)
    }

    @Test func wordlessSegmentFollowsItsLabel() {
        let empty = attribute(TranscriptSegment(text: "", start: 0, end: 0))
        #expect(empty.segments.isEmpty)

        let bare = attribute(
            TranscriptSegment(text: "Right.", speaker: "S2", start: 3, end: 4), spans: spans((0, 10))
        )
        #expect(runs(bare).map(\.speaker) == [1])
        #expect((bare.segments[0].text, bare.segments[0].start, bare.segments[0].end) == ("Right.", 3, 4))
        #expect(bare.tallies.isEmpty)
    }

    @Test func attributionIsDeterministic() {
        func run() -> SpeakerAttributor.Attribution {
            var counter = 0
            return SpeakerAttributor.attribute(
                segment([("a", 0, 1), ("b", 1, 2), ("c", 3, 4)]),
                session: 1, mode: .remote, spans: spans((0, 2)),
                registry: SpeakerRegistry(userName: "Alex"), tallies: [:],
                newID: {
                    counter += 1
                    return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", counter))!
                }
            )
        }
        #expect(run() == run())
        #expect(run().segments.map(\.speaker) == [0, 1])
    }
}

import Foundation
import MWMeetings
import MWStreaming

/// Splits a provider segment between the user and its provider speaker (design §5.3, R3).
///
/// Remote: a word is the user's when microphone speech covers at least `userWordShare` of it.
/// Once at least `userLabelShare` of a provider label's words so far were the user's, the label is
/// bound to the user and every word it carries from then on is the user's. In the room the gate
/// is not consulted.
public enum SpeakerAttributor {
    public static let userWordShare = 0.5
    public static let userLabelShare = 0.7

    /// One provider label's words so far, and how many of them were in microphone speech.
    public struct Tally: Sendable, Equatable {
        public var words: Int
        public var inSpeech: Int

        public init(words: Int = 0, inSpeech: Int = 0) {
            self.words = words
            self.inSpeech = inSpeech
        }
    }

    public struct Attribution: Sendable, Equatable {
        public var segments: [Segment]
        public var registry: SpeakerRegistry
        /// Keyed by `SpeakerRegistry.key(session:label:)`.
        public var tallies: [String: Tally]
    }

    /// `segment`'s word times must already be in meeting seconds.
    public static func attribute(
        _ segment: TranscriptSegment,
        session: Int,
        mode: MeetingMode,
        spans: SpeechGate.View,
        registry: SpeakerRegistry,
        tallies: [String: Tally],
        newID: () -> UUID = { UUID() }
    ) -> Attribution {
        var registry = registry
        var tallies = tallies
        let label = segment.speaker
        let key = SpeakerRegistry.key(session: session, label: label)

        var isUser = [Bool](repeating: false, count: segment.words.count)
        if mode == .remote, !isUser.isEmpty {
            isUser = segment.words.map { spans.overlap(start: $0.start, end: $0.end) >= userWordShare }
            var tally = tallies[key, default: Tally()]
            tally.words += isUser.count
            tally.inSpeech += isUser.filter { $0 }.count
            tallies[key] = tally
            if Double(tally.inSpeech) / Double(tally.words) >= userLabelShare {
                registry.bindToUser(session: session, label: label)
            }
        }
        if registry.id(session: session, label: label) == SpeakerRegistry.userID {
            isUser = isUser.map { _ in true }
        }

        func make(user: Bool, _ words: ArraySlice<TranscriptWord>, text: String) -> Segment {
            Segment(
                id: newID(),
                speaker: user ? SpeakerRegistry.userID : registry.resolve(session: session, label: label),
                start: words.first?.start ?? segment.start,
                end: words.last?.end ?? segment.end,
                text: text,
                words: words.map { Word(text: $0.text, start: $0.start, end: $0.end) },
                session: session,
                providerLabel: label,
                turnOrder: segment.turnOrder
            )
        }

        guard !segment.words.isEmpty else {
            let segments = segment.text.isEmpty ? [] : [make(user: false, [], text: segment.text)]
            return Attribution(segments: segments, registry: registry, tallies: tallies)
        }
        // Runs of words with one outcome.
        var runs: [Range<Int>] = []
        for index in isUser.indices {
            if let last = runs.last, isUser[last.lowerBound] == isUser[index] {
                runs[runs.count - 1] = last.lowerBound..<(index + 1)
            } else {
                runs.append(index..<(index + 1))
            }
        }
        let segments = runs.map { run in
            let words = segment.words[run]
            let text = runs.count == 1 ? segment.text : words.map(\.text).joined(separator: " ")
            return make(user: isUser[run.lowerBound], words, text: text)
        }
        return Attribution(segments: segments, registry: registry, tallies: tallies)
    }
}

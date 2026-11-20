import Foundation
import MWConfig
import MWMeetings

/// R8: a probe voice against the people's local samples.
public enum VoiceMatcher {
    public struct Decision: Sendable, Equatable {
        public enum Outcome: Sendable, Equatable { case none, suggestion, sure }

        public var outcome: Outcome
        /// Nil when the outcome is `.none`.
        public var person: Person?
        /// The best candidate's score, 0 without candidates.
        public var score: Double
        /// The best other candidate's score, 0 when there is none.
        public var runnerUp: Double

        public init(outcome: Outcome, person: Person?, score: Double, runnerUp: Double) {
            self.outcome = outcome
            self.person = person
            self.score = score
            self.runnerUp = runnerUp
        }
    }

    /// Thresholds and margin are two-decimal settings, and a difference of two-decimal scores
    /// lands a hair either side of them (0.70 − 0.60 = 0.0999…98), so a met boundary counts.
    private static let tolerance = 1e-9

    /// A person's score is their best sample. `excluding` holds the people rejected for this
    /// speaker; the user is a candidate only with `includeUser` (in-room meetings).
    public static func decide(
        probe: VoiceVector, people: [Person], settings: VoiceSettings, excluding: Set<UUID> = [], includeUser: Bool
    ) -> Decision {
        let ranked = people
            .filter { !excluding.contains($0.id) && (includeUser || !$0.isUser) }
            .compactMap { person in
                person.local.map { probe.cosine($0.vector) }.max().map { (person: person, score: $0) }
            }
            .sorted { $0.score > $1.score }
        guard let best = ranked.first else { return Decision(outcome: .none, person: nil, score: 0, runnerUp: 0) }
        let runnerUp = ranked.dropFirst().first?.score ?? 0
        func clears(_ threshold: Double) -> Bool {
            best.score >= threshold - tolerance && best.score - runnerUp >= settings.margin - tolerance
        }
        let outcome: Decision.Outcome =
            clears(settings.sureThreshold) ? .sure : clears(settings.suggestionThreshold) ? .suggestion : .none
        return Decision(
            outcome: outcome, person: outcome == .none ? nil : best.person, score: best.score, runnerUp: runnerUp
        )
    }
}

import Foundation
import MWMeetings
import MWTranscription

/// The speakers and settings a reply is decided against: read when the reply lands, not when
/// the request was sent.
public struct PolicyContext: Sendable {
    public var speakers: [SpeakerLabel]
    public var people: [(id: UUID, name: String)]
    public var userName: String?
    /// The user's name as misheard.
    public var aliases: [String]
    public var mode: MeetingMode
    public var autoApply: Bool
    /// Each segment's current speaker: a revision during the flight may have moved the evidence.
    public var segmentSpeakers: [UUID: Int]

    public init(
        speakers: [SpeakerLabel],
        people: [(id: UUID, name: String)],
        userName: String?,
        aliases: [String],
        mode: MeetingMode,
        autoApply: Bool,
        segmentSpeakers: [UUID: Int]
    ) {
        self.speakers = speakers
        self.people = people
        self.userName = userName
        self.aliases = aliases
        self.mode = mode
        self.autoApply = autoApply
        self.segmentSpeakers = segmentSpeakers
    }
}

/// A conversation match for the registry, with `source: "conversation"`, evidence and kind.
public enum NamingAction: Sendable, Equatable {
    case suggest(speaker: Int, NameMatch)
    case apply(speaker: Int, NameMatch)
}

public struct NamingDecision: Sendable, Equatable {
    public var actions: [NamingAction]
    /// Suggestions dropped, keyed by policy rule number, for the log.
    public var dropped: [Int: Int]
}

public enum SuggestionPolicy {
    private static let source = "conversation"
    private static let selfIntroduction = "self_introduction"
    private static let kinds: Set = [selfIntroduction, "addressed", "handoff", "other"]
    private static let maxSuggestions = 50

    /// A conversation match leaves the speaker open, so a later reply can replace it; a voice
    /// match outranks the conversation (R13, R17).
    public static func isOpen(_ label: SpeakerLabel) -> Bool {
        !label.isUser && label.person == nil && label.name == SpeakerLabel.defaultName(label.id)
            && !label.matches.contains { $0.source == "voice" }
    }

    /// Policy rules 1–10, in order, over the first 50 suggestions.
    public static func decide(_ raws: [RawSuggestion], rendered: Rendered, context: PolicyContext) -> NamingDecision {
        var dropped: [Int: Int] = [:]
        var candidates: [Candidate] = []
        for raw in raws.prefix(maxSuggestions) {
            switch candidate(raw, rendered: rendered, context: context) {
            case .success(let candidate): candidates.append(candidate)
            case .failure(let drop): dropped[drop.rule, default: 0] += 1
            }
        }

        var actions: [NamingAction] = []
        for candidate in resolveConflicts(candidates, dropped: &dropped) {
            let target = candidate.target
            // Rule 9: a standing suggestion of the same name stays as it is.
            if target.matches.contains(where: {
                $0.source == source && $0.state == .suggested && NameFold.key($0.name) == candidate.key
            }) {
                dropped[9, default: 0] += 1
                continue
            }
            // Rule 10. A name another speaker holds is only suggested: Accept merges the two.
            let applies = context.autoApply && candidate.introducesItself && !candidate.isUser
                && !context.speakers.contains { $0.id != candidate.speaker && NameFold.key($0.name) == candidate.key }
            let match = NameMatch(
                key: target.providerKeys.first ?? "", name: candidate.name, person: nil, source: source,
                state: applies ? .applied : .suggested, evidence: candidate.evidence, kind: candidate.kind
            )
            actions.append(applies ? .apply(speaker: candidate.speaker, match) : .suggest(speaker: candidate.speaker, match))
        }
        return NamingDecision(actions: actions, dropped: dropped)
    }

    private struct Candidate {
        var target: SpeakerLabel
        var name: String
        /// `NameFold` key of `name`.
        var key: String
        var kind: String
        var evidence: NameEvidence
        /// The user's name or a misheard spelling of it.
        var isUser: Bool
        /// A self-introduction whose evidence segment is now the target's own.
        var introducesItself: Bool

        var speaker: Int { target.id }
    }

    private struct Drop: Error {
        var rule: Int
    }

    /// Rules 1–7.
    private static func candidate(
        _ raw: RawSuggestion, rendered: Rendered, context: PolicyContext
    ) -> Result<Candidate, Drop> {
        guard let match = raw.speaker.wholeMatch(of: /S(\d+)/), let id = Int(match.1),
              let target = context.speakers.first(where: { $0.id == id })
        else { return .failure(Drop(rule: 1)) }
        guard raw.confidence == "certain", kinds.contains(raw.kind) else { return .failure(Drop(rule: 2)) }
        guard let clean = NameSanitiser.clean(raw.name) else { return .failure(Drop(rule: 3)) }
        var checked = raw
        checked.name = clean
        guard let evidence = EvidenceCheck.verify(checked, in: rendered) else { return .failure(Drop(rule: 4)) }
        guard isOpen(target) else { return .failure(Drop(rule: 5)) }

        let key = NameFold.key(clean)
        let userName = context.userName.flatMap { $0.isEmpty ? nil : $0 }
        let isUser = ([userName].compactMap { $0 } + context.aliases).contains { NameFold.key($0) == key }
        var name = clean
        var person: UUID?
        if isUser {
            // Remote, the microphone is already the user; in a room, Accept merges into the user.
            guard context.mode == .inRoom, let userName else { return .failure(Drop(rule: 6)) }
            name = userName
        } else if let entry = context.people.first(where: { NameFold.key($0.name) == key }) {
            name = entry.name
            person = entry.id
        }
        let canonical = NameFold.key(name)
        guard !target.rejectedNames.contains(where: { NameFold.key($0) == canonical }),
              !(person.map(target.rejected.contains) ?? false)
        else { return .failure(Drop(rule: 7)) }

        return .success(Candidate(
            target: target, name: name, key: canonical, kind: raw.kind, evidence: evidence, isUser: isUser,
            introducesItself: raw.kind == selfIntroduction && context.segmentSpeakers[evidence.segment] == id
        ))
    }

    /// Rule 8, keeping the reply's order.
    private static func resolveConflicts(_ candidates: [Candidate], dropped: inout [Int: Int]) -> [Candidate] {
        // One speaker with two names: neither. One name said twice for a speaker: one.
        var perSpeaker: [Candidate] = []
        for (index, candidate) in candidates.enumerated() {
            let same = candidates.filter { $0.speaker == candidate.speaker }
            if Set(same.map(\.key)).count > 1 {
                dropped[8, default: 0] += 1
            } else if index == candidates.firstIndex(where: { $0.speaker == candidate.speaker }) {
                perSpeaker.append(same.first(where: \.introducesItself) ?? candidate)
            }
        }
        // One name for two speakers: only the one that introduced itself, when exactly one did.
        return perSpeaker.filter { candidate in
            let same = perSpeaker.filter { $0.key == candidate.key }
            guard same.count > 1 else { return true }
            let introduced = same.filter(\.introducesItself)
            if introduced.count == 1, introduced[0].speaker == candidate.speaker { return true }
            dropped[8, default: 0] += 1
            return false
        }
    }
}

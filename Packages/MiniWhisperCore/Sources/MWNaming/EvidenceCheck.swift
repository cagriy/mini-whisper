import Foundation
import MWMeetings
import MWTranscription

/// R12: the quote must be found in the cited turn, and must contain the name, after folding
/// case, diacritics, quote marks and whitespace. The evidence is the turn's own text.
public enum EvidenceCheck {
    private static let evidenceLimit = 300

    public static func verify(_ s: RawSuggestion, in r: Rendered) -> NameEvidence? {
        guard let turn = r.turns.first(where: { $0.number == s.turn }) else { return nil }
        let quote = normalised(s.quote.trimmingCharacters(in: .whitespacesAndNewlines)).characters
        let name = normalised(s.name.trimmingCharacters(in: .whitespacesAndNewlines)).characters
        guard !quote.isEmpty, !name.isEmpty, quote.contains(name) else { return nil }

        let text = normalised(turn.text)
        guard let found = text.characters.firstRange(of: quote) else { return nil }
        let start = text.origins[found.lowerBound].lowerBound
        let range = start..<text.origins[found.upperBound - 1].upperBound
        guard let span = turn.segments.last(where: { $0.range.lowerBound <= start }) else { return nil }
        return NameEvidence(segment: span.id, time: span.start, text: cut(String(turn.text[range])))
    }

    /// Each normalised character with the range of the original character it came from.
    private static func normalised(_ s: String) -> (characters: [Character], origins: [Range<String.Index>]) {
        var characters: [Character] = []
        var origins: [Range<String.Index>] = []
        for index in s.indices {
            let original = s[index]
            let origin = index..<s.index(after: index)
            if original.isWhitespace {
                if characters.last != " " {
                    characters.append(" ")
                    origins.append(origin)
                }
                continue
            }
            let mapped: String = switch original {
            case "‘", "’", "‚", "‛": "'"
            case "“", "”", "„": "\""
            default: String(original).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            }
            for character in mapped {
                characters.append(character)
                origins.append(origin)
            }
        }
        return (characters, origins)
    }

    private static func cut(_ text: String) -> String {
        guard text.count > evidenceLimit else { return text }
        let limit = text.index(text.startIndex, offsetBy: evidenceLimit)
        guard !text[limit].isWhitespace,
              let space = text[..<limit].lastIndex(where: \.isWhitespace)
        else { return String(text[..<limit]).trimmingCharacters(in: .whitespaces) }
        return String(text[..<space]).trimmingCharacters(in: .whitespaces)
    }
}

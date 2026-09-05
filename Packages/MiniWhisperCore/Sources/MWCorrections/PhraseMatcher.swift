import Foundation

/// One compiled whole-phrase pattern for a single normalised variant (R7, design §5.3).
public struct PhraseMatcher {
    public enum Failure: Error, Equatable {
        case emptyVariant
    }

    /// The run a whole-phrase match may not begin or end inside.
    private static let wordCharacter = #"[\p{L}\p{M}\p{N}_]"#

    private let regex: NSRegularExpression

    public init(variant: String) throws {
        let words = variant.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { throw Failure.emptyVariant }
        // Escaped, so a phrase can never become a pattern; `\s+` so the phrase still
        // matches across a doubled space or a line break.
        let body = words
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
        regex = try NSRegularExpression(
            pattern: "(?<!\(Self.wordCharacter))\(body)(?!\(Self.wordCharacter))",
            options: [.caseInsensitive]
        )
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            // A match that would split a grapheme cluster cannot be spliced, so it is
            // not a match here either.
            .compactMap { Range($0.range, in: text) }
    }
}

import Foundation

/// The text shown around a search match.
public enum SearchExcerpt {
    /// About `context` characters either side of the first match, cut at word boundaries, on one
    /// line. Case-insensitive; nil without a match.
    public static func around(_ needle: String, in text: String, context: Int) -> String? {
        guard let match = text.range(of: needle, options: .caseInsensitive) else { return nil }
        var lower = text.index(match.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        var upper = text.index(match.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex
        if lower > text.startIndex, !text[text.index(before: lower)].isWhitespace,
           let space = text[lower..<match.lowerBound].firstIndex(where: \.isWhitespace) {
            lower = text.index(after: space)
        }
        if upper < text.endIndex, !text[upper].isWhitespace,
           let space = text[match.upperBound..<upper].lastIndex(where: \.isWhitespace) {
            upper = space
        }
        let cut = text[lower..<upper].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (lower > text.startIndex ? "…" : "") + cut + (upper < text.endIndex ? "…" : "")
    }
}

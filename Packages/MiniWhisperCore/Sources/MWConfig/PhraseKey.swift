import Foundation

/// The one phrase normalisation shared by validation, matching, hint dedupe and the
/// tally (R6). It lives in `MWConfig` because `Config.validated()` needs it and
/// `MWConfig` cannot import `MWCorrections` without inverting the module edge.
public enum PhraseKey {
    /// NFC-composed, trimmed, internal whitespace runs collapsed to one space.
    public static func normalised(_ phrase: String) -> String {
        phrase.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// `normalised`, lowercased — the identity two phrases share when matching is
    /// case-insensitive.
    public static func key(_ phrase: String) -> String {
        normalised(phrase).lowercased()
    }
}

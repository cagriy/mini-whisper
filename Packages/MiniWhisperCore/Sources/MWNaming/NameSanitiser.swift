import Foundation

/// No digit can pass, so a default `Speaker 4` label needs no check of its own.
public enum NameSanitiser {
    public static func clean(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.wholeMatch(of: /[\p{L}\p{M}][\p{L}\p{M}'’.\- ]{0,59}/) == nil ? nil : trimmed
    }
}

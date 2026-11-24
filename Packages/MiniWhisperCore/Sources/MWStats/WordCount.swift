import Foundation

/// Words as Foundation's word breaking finds them, so unspaced scripts such as Japanese count too.
public enum WordCount {
    public static func count(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            // Breaking beside CJK reports the spaces between runs as words of their own.
            if text[range].contains(where: { $0.isLetter || $0.isNumber }) { count += 1 }
        }
        return count
    }
}

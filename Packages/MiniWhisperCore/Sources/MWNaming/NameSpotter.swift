import Foundation
import NaturalLanguage

public enum NameSpotter {
    public static func containsName(_ text: String, known: [String]) -> Bool {
        // Padding both sides with a space makes a substring match land on whole words only.
        let words = " \(wordKey(text)) "
        return known.contains { name in
            let key = wordKey(name)
            return !key.isEmpty && words.contains(" \(key) ")
        } || taggerFindsName(in: text)
    }

    private static func wordKey(_ s: String) -> String {
        NameFold.key(s)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .joined(separator: " ")
    }

    private static func taggerFindsName(in text: String) -> Bool {
        // NLTagger is not Sendable, so each call makes its own.
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        return tagger.tags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.joinNames])
            .contains { $0.0 == .personalName }
    }
}

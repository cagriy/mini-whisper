/// Why a hint the user configured never reached an engine (R18–R21), surfaced in the
/// Settings report.
public enum SkipReason: Equatable, Sendable {
    case overCap
    case emptyAfterFilter
    case tooManyWords
    case wordTooLong
}

public struct SkippedHint: Equatable, Sendable {
    public var term: String
    public var reason: SkipReason

    public init(term: String, reason: SkipReason) {
        self.term = term
        self.reason = reason
    }
}

/// Each provider's own caps and filters, applied to the resolved hints in resolver
/// order so an app-scoped term is never the one dropped (R18–R21).
public enum HintSerializer {
    public struct Capped: Equatable, Sendable {
        public var sent: [String]
        public var skipped: [SkippedHint]
    }

    public struct VocabEntry: Equatable, Sendable {
        public var content: String
        public var soundsLike: [String]

        public init(content: String, soundsLike: [String]) {
            self.content = content
            self.soundsLike = soundsLike
        }
    }

    public struct CappedEntries: Equatable, Sendable {
        public var sent: [VocabEntry]
        public var skipped: [SkippedHint]
    }

    static let contextualStringsCap = 100
    static let speechmaticsEntryCap = 1_000
    private static let speechmaticsMaxWords = 6
    private static let speechmaticsMaxWordLength = 4_000
    private static let openAIForbidden: Set<Unicode.Scalar> = ["<", ">", "\r", "\n"]

    public static func contextualStrings(_ hints: RecognitionHints) -> Capped {
        Capped(
            sent: Array(hints.terms.prefix(contextualStringsCap)),
            skipped: hints.terms.dropFirst(contextualStringsCap)
                .map { SkippedHint(term: $0, reason: .overCap) }
        )
    }

    public static func openAIKeywords(_ hints: RecognitionHints) -> Capped {
        var sent: [String] = []
        var skipped: [SkippedHint] = []
        for term in hints.terms {
            // Scalars, not characters: CR LF is one Character and would survive a
            // Character-wise filter.
            let filtered = String(
                String.UnicodeScalarView(term.unicodeScalars.filter { !openAIForbidden.contains($0) })
            )
            if filtered.isEmpty {
                skipped.append(SkippedHint(term: term, reason: .emptyAfterFilter))
            } else {
                sent.append(filtered)
            }
        }
        return Capped(sent: sent, skipped: skipped)
    }

    public static func speechmaticsVocab(_ hints: RecognitionHints) -> CappedEntries {
        var entries: [VocabEntry] = []
        var skipped: [SkippedHint] = []
        func append(content: String, soundsLike: [String]) {
            if let reason = skipReason(content) {
                skipped.append(SkippedHint(term: content, reason: reason))
                return
            }
            var kept: [String] = []
            for value in soundsLike {
                if let reason = skipReason(value) {
                    skipped.append(SkippedHint(term: value, reason: reason))
                } else {
                    kept.append(value)
                }
            }
            entries.append(VocabEntry(content: content, soundsLike: kept))
        }

        for rule in hints.rules { append(content: rule.write, soundsLike: rule.soundsLike) }
        for term in hints.vocabulary { append(content: term, soundsLike: []) }
        skipped += entries.dropFirst(speechmaticsEntryCap)
            .map { SkippedHint(term: $0.content, reason: .overCap) }
        return CappedEntries(sent: Array(entries.prefix(speechmaticsEntryCap)), skipped: skipped)
    }

    private static func skipReason(_ content: String) -> SkipReason? {
        let words = content.split(whereSeparator: \.isWhitespace)
        if words.count > speechmaticsMaxWords { return .tooManyWords }
        if words.contains(where: { $0.count > speechmaticsMaxWordLength }) { return .wordTooLong }
        return nil
    }
}

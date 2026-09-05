import Foundation
import MWConfig

/// R31: how many stored dictations a draft rule would have rewritten, with a few
/// examples, so the user sees the reach of a rule before saving it.
public enum ImpactPreview {
    public struct Entry: Equatable, Sendable {
        public var text: String
        public var bundleID: String?

        public init(text: String, bundleID: String?) {
            self.text = text
            self.bundleID = bundleID
        }
    }

    public struct Result: Equatable, Sendable {
        public var matching: Int
        public var total: Int
        public var snippets: [String]
        /// There was nothing to look through: history retention is 0.
        public var historyOff: Bool
    }

    private static let snippetContext = 30
    private static let snippetLimit = 3

    public static func compute(rule: CorrectionRule, over entries: [Entry]?) -> Result {
        guard let entries else {
            return Result(matching: 0, total: 0, snippets: [], historyOff: true)
        }
        let matchers = CorrectionResolver(rules: [rule]).rules(for: rule.bundleID)
            .flatMap(\.variants)
            .compactMap { try? PhraseMatcher(variant: $0) }
        let inScope = entries.filter { rule.bundleID == nil || $0.bundleID == rule.bundleID }

        var matching = 0
        var snippets: [String] = []
        for entry in inScope {
            let text = entry.text.precomposedStringWithCanonicalMapping
            guard
                let first = matchers.compactMap({ $0.matches(in: text).first })
                    .min(by: { $0.lowerBound < $1.lowerBound })
            else { continue }
            matching += 1
            if snippets.count < snippetLimit { snippets.append(snippet(of: text, around: first)) }
        }
        return Result(
            matching: matching, total: inScope.count, snippets: snippets, historyOff: false
        )
    }

    private static func snippet(of text: String, around match: Range<String.Index>) -> String {
        let start = text.index(
            match.lowerBound, offsetBy: -snippetContext, limitedBy: text.startIndex
        ) ?? text.startIndex
        let end = text.index(
            match.upperBound, offsetBy: snippetContext, limitedBy: text.endIndex
        ) ?? text.endIndex
        let lead = start > text.startIndex ? "…" : ""
        let tail = end < text.endIndex ? "…" : ""
        return lead + text[start..<end] + tail
    }
}

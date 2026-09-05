import Foundation
import MWConfig

/// Rewrites a transcript in one pass over the original text, so no rule can cascade
/// into another's output (R8, R9).
public struct CorrectionApplier {
    public struct Application: Equatable, Sendable {
        public var text: String
        public var replacements: Int
        /// Variants whose pattern would not compile — impossible for escaped literals,
        /// counted rather than thrown so a rule can never fail a dictation.
        public var droppedVariants: Int
    }

    private struct Candidate {
        let range: Range<String.Index>
        let length: Int
        let ruleIndex: Int
        let isAppScoped: Bool
    }

    private let rules: [ResolvedRule]
    private let matchers: [(matcher: PhraseMatcher, ruleIndex: Int)]
    private let droppedVariants: Int

    public init(rules: [ResolvedRule]) {
        self.rules = rules
        var matchers: [(PhraseMatcher, Int)] = []
        var dropped = 0
        for (index, resolved) in rules.enumerated() {
            for variant in resolved.variants {
                guard let matcher = try? PhraseMatcher(variant: variant) else {
                    dropped += 1
                    continue
                }
                matchers.append((matcher, index))
            }
        }
        self.matchers = matchers
        droppedVariants = dropped
    }

    public func apply(to text: String) -> Application {
        // Matching and splicing happen on NFC, so the output is NFC too (§5.3).
        let text = text.precomposedStringWithCanonicalMapping
        var candidates: [Candidate] = []
        for (matcher, ruleIndex) in matchers {
            for range in matcher.matches(in: text) {
                candidates.append(
                    Candidate(
                        range: range,
                        length: text.distance(from: range.lowerBound, to: range.upperBound),
                        ruleIndex: ruleIndex,
                        isAppScoped: rules[ruleIndex].isAppScoped
                    )
                )
            }
        }
        // R9: earliest, then longest, then app over global, then stored order.
        candidates.sort { left, right in
            if left.range.lowerBound != right.range.lowerBound {
                return left.range.lowerBound < right.range.lowerBound
            }
            if left.length != right.length { return left.length > right.length }
            if left.isAppScoped != right.isAppScoped { return left.isAppScoped }
            return left.ruleIndex < right.ruleIndex
        }

        var output = ""
        var cursor = text.startIndex
        var replacements = 0
        for candidate in candidates where candidate.range.lowerBound >= cursor {
            output.append(contentsOf: text[cursor..<candidate.range.lowerBound])
            output.append(rules[candidate.ruleIndex].rule.write)
            cursor = candidate.range.upperBound
            replacements += 1
        }
        output.append(contentsOf: text[cursor...])
        return Application(
            text: output, replacements: replacements, droppedVariants: droppedVariants
        )
    }
}

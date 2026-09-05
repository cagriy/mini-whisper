import MWConfig

/// One enabled rule as it applies to one delivery app: the rule itself, the normalised
/// phrases that fire it, and whether it beats a global rule on an overlap (R9, R10).
public struct ResolvedRule: Equatable, Sendable {
    public var rule: CorrectionRule
    public var variants: [String]
    public var isAppScoped: Bool

    public init(rule: CorrectionRule, variants: [String], isAppScoped: Bool) {
        self.rule = rule
        self.variants = variants
        self.isAppScoped = isAppScoped
    }
}

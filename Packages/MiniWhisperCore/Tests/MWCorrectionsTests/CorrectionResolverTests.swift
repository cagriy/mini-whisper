import MWConfig
import Testing

import MWCorrections

/// R10/R11: which rules apply to a delivery app, in which order, with which variants.
@Suite struct CorrectionResolverTests {
    private static let slack = "com.tinyspeck.slackmacgap"

    private func rule(
        _ id: String,
        _ heard: String,
        _ write: String,
        soundsLike: [String] = [],
        bundleID: String? = nil,
        enabled: Bool = true
    ) -> CorrectionRule {
        CorrectionRule(
            id: id, heard: heard, write: write, soundsLike: soundsLike,
            bundleID: bundleID, enabled: enabled
        )
    }

    @Test func keepsOnlyEnabledRulesInScope() {
        let resolver = CorrectionResolver(rules: [
            rule("global", "get hub", "GitHub"),
            rule("slack", "eefa", "Aoife", bundleID: Self.slack),
            rule("terminal", "eefa", "Eva", bundleID: "com.apple.Terminal"),
            rule("off", "speech matics", "Speechmatics", enabled: false),
        ])

        #expect(resolver.rules(for: Self.slack).map(\.rule.id) == ["slack", "global"])
        #expect(resolver.rules(for: nil).map(\.rule.id) == ["global"])
        #expect(resolver.rules(for: "com.apple.Terminal").map(\.rule.id) == ["terminal", "global"])
    }

    @Test func appRulesComeFirstAndStoredOrderIsKeptWithinAScope() {
        let resolver = CorrectionResolver(rules: [
            rule("g1", "one", "One"),
            rule("a1", "two", "Two", bundleID: Self.slack),
            rule("g2", "three", "Three"),
            rule("a2", "four", "Four", bundleID: Self.slack),
        ])

        let resolved = resolver.rules(for: Self.slack)
        #expect(resolved.map(\.rule.id) == ["a1", "a2", "g1", "g2"])
        #expect(resolved.map(\.isAppScoped) == [true, true, false, false])
    }

    @Test func variantsAreTheNormalisedHeardPlusSoundsLikeDeduped() {
        let resolver = CorrectionResolver(rules: [
            rule("g", " get   hub ", "GitHub", soundsLike: ["Get Hub", "git hub"])
        ])

        #expect(resolver.rules(for: nil).first?.variants == ["get hub", "git hub"])
    }

    @Test func anAppRuleSuppressesTheGlobalRulesVariantForTheSameKey() {
        let resolver = CorrectionResolver(rules: [
            rule("global", "eefa", "Eva", soundsLike: ["eeva"]),
            rule("slack", "eefa", "Aoife", bundleID: Self.slack),
        ])

        let resolved = resolver.rules(for: Self.slack)
        #expect(resolved.map(\.rule.id) == ["slack", "global"])
        #expect(resolved[0].variants == ["eefa"])
        #expect(resolved[1].variants == ["eeva"])
    }

    @Test func disabledRulesContributeNothing() {
        let resolver = CorrectionResolver(rules: [
            rule("off", "eefa", "Aoife", bundleID: Self.slack, enabled: false),
            rule("global", "eefa", "Eva"),
        ])

        let resolved = resolver.rules(for: Self.slack)
        #expect(resolved.map(\.rule.id) == ["global"])
        #expect(resolved[0].variants == ["eefa"])
    }
}

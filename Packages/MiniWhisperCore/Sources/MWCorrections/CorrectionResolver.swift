import MWConfig

/// The rules that apply to one delivery app, app-scoped first then global, each in
/// stored order (R9, R10, R11).
public struct CorrectionResolver {
    private let stored: [CorrectionRule]

    public init(rules: [CorrectionRule]) {
        stored = rules
    }

    public func rules(for bundleID: String?) -> [ResolvedRule] {
        let enabled = stored.filter(\.enabled)
        let appScoped = bundleID.map { id in enabled.filter { $0.bundleID == id } } ?? []
        let resolvedApp = appScoped.map {
            ResolvedRule(rule: $0, variants: Self.variants(of: $0), isAppScoped: true)
        }
        // R10: a phrase an app-scoped rule owns is never also rewritten by a global rule.
        let owned = Set(resolvedApp.flatMap(\.variants).map(PhraseKey.key))
        let resolvedGlobal = enabled.filter { $0.bundleID == nil }.map {
            ResolvedRule(
                rule: $0,
                variants: Self.variants(of: $0).filter { !owned.contains(PhraseKey.key($0)) },
                isAppScoped: false
            )
        }
        return resolvedApp + resolvedGlobal
    }

    private static func variants(of rule: CorrectionRule) -> [String] {
        var seen: Set<String> = []
        return ([rule.heard] + rule.soundsLike)
            .map(PhraseKey.normalised)
            .filter { !$0.isEmpty && seen.insert(PhraseKey.key($0)).inserted }
    }
}

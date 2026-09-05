import MWConfig

/// R17: writes, heards and sounds-like of the rules in scope, app-scoped first, then the
/// manual vocabulary, each spelling once.
public enum HintResolver {
    public static func resolve(
        _ snapshot: CorrectionSnapshot,
        bundleID: String?
    ) -> RecognitionHints {
        var seen: Set<String> = []
        var terms: [String] = []
        func add(_ term: String) {
            let term = PhraseKey.normalised(term)
            guard !term.isEmpty, seen.insert(PhraseKey.key(term)).inserted else { return }
            terms.append(term)
        }

        var rules: [RecognitionHints.HintRule] = []
        for resolved in CorrectionResolver(rules: snapshot.rules).rules(for: bundleID) {
            let write = PhraseKey.normalised(resolved.rule.write)
            add(write)
            resolved.variants.forEach(add)
            let writeKey = PhraseKey.key(write)
            rules.append(
                RecognitionHints.HintRule(
                    write: write,
                    soundsLike: resolved.variants.filter { PhraseKey.key($0) != writeKey }
                )
            )
        }
        let vocabulary = snapshot.vocabulary.map(PhraseKey.normalised).filter { !$0.isEmpty }
        vocabulary.forEach(add)
        return RecognitionHints(terms: terms, rules: rules, vocabulary: vocabulary)
    }
}

import MWCorrections

/// What the user's vocabulary and remembered corrections add to the two prompts
/// actually sent (F28, R23, R24).
public struct PromptComposer {
    public static func transcribePrompt(base: String, terms: [String]) -> String {
        let line = PromptSections.vocabularyLine(terms: terms)
        return composed(base: base, blocks: line.map { ["\n\n\($0)"] } ?? [])
    }

    public static func cleanupPrompt(
        base: String,
        hints: RecognitionHints,
        rules: [ResolvedRule]
    ) -> String {
        composed(base: base, blocks: PromptSections.cleanupBlocks(hints: hints, rules: rules))
    }

    private static func composed(base: String, blocks: [String]) -> String {
        let body = blocks.joined()
        // An empty instructions file leaves the sections as the whole prompt (§5.5).
        return base.isEmpty ? String(body.drop(while: \.isNewline)) : base + body
    }
}

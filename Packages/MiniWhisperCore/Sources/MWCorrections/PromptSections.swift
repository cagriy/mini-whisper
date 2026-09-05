/// The exact prompt text the batch request (R23) and the cleanup request (R24) carry.
public enum PromptSections {
    public static func vocabularyLine(terms: [String]) -> String? {
        guard !terms.isEmpty else { return nil }
        return "Vocabulary (spell exactly as written): \(terms.joined(separator: ", "))"
    }

    public static func cleanupBlocks(hints: RecognitionHints, rules: [ResolvedRule]) -> [String] {
        var blocks: [String] = []
        let preserve = hints.rules.map(\.write) + hints.vocabulary
        if !preserve.isEmpty {
            blocks.append(
                "\n\nPreserve these terms exactly as written: \(preserve.joined(separator: ", "))"
            )
        }
        // Quoted as data under a fixed heading, in resolver order so an app rule is read
        // before the global rule it overrides.
        let pairs = rules.flatMap { resolved in
            resolved.variants.map { "\"\($0)\" → \"\(resolved.rule.write)\"" }
        }
        if !pairs.isEmpty {
            blocks.append(
                """
                \n
                Known corrections — replace the exact phrase on the left with the spelling on the right:
                \(pairs.joined(separator: "\n"))
                """
            )
        }
        return blocks
    }
}

/// Appends the user's vocabulary to the prompts actually sent, verbatim (F28, design §5.8).
public struct PromptComposer {
    public static func transcribeInstructions(base: String, vocabulary: [String]) -> String {
        appending(base, "Vocabulary (spell exactly as written)", vocabulary)
    }

    public static func cleanupPrompt(base: String, vocabulary: [String]) -> String {
        appending(base, "Preserve these terms exactly as written", vocabulary)
    }

    private static func appending(
        _ base: String,
        _ heading: String,
        _ vocabulary: [String]
    ) -> String {
        guard !vocabulary.isEmpty else { return base }
        return "\(base)\n\n\(heading): \(vocabulary.joined(separator: ", "))"
    }
}

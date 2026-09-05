import MWConfig

/// R5: what the correction window and the Settings detail form refuse to save.
public enum CorrectionValidator {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyHeard
        case emptyWrite
        case noChange
        case duplicate(heard: String, existingWrite: String, scope: String)

        public var message: String {
            switch self {
            case .emptyHeard: "Select the misheard phrase first."
            case .emptyWrite: "Enter the spelling to write."
            case .noChange: "Nothing to remember — Write is the same as Heard."
            case .duplicate(let heard, let existingWrite, let scope):
                "‘\(heard)’ is already remembered for \(scope) as ‘\(existingWrite)’."
            }
        }
    }

    /// `scopeName` is the app name the message should read; without one the message
    /// names the bundle ID, which is all a rule carries on its own.
    public static func validate(
        _ draft: CorrectionRule,
        against existing: [CorrectionRule],
        excluding id: String?,
        scopeName: String? = nil
    ) -> ValidationError? {
        let heard = PhraseKey.normalised(draft.heard)
        let write = PhraseKey.normalised(draft.write)
        guard !heard.isEmpty else { return .emptyHeard }
        guard !write.isEmpty else { return .emptyWrite }
        // Case-sensitive, so a case-only fix is a change worth remembering.
        guard write != heard else { return .noChange }
        let key = PhraseKey.key(heard)
        guard
            let clash = existing.first(where: {
                $0.id != id && $0.bundleID == draft.bundleID && PhraseKey.key($0.heard) == key
            })
        else { return nil }
        return .duplicate(
            heard: heard,
            existingWrite: clash.write,
            scope: scopeName ?? draft.bundleID ?? "All apps"
        )
    }
}

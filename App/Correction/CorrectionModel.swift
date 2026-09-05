import Foundation
import MWConfig
import MWCorrections
import MWPaste
import MWSupport
import Observation

/// Everything the correction window decides (design §5.4, R5, R29–R32): the snapped
/// phrase, the draft rule, its preview and impact, and the two writes it may make.
/// `CorrectionView` is a projection of this and holds no rules of its own.
@MainActor
@Observable
final class CorrectionModel {
    struct Dependencies {
        var store: ConfigStore
        var pasteboard: any PasteboardAccess
        /// Nil when history retention is 0, which is not the same as an empty history (R31).
        var historyEntries: @Sendable () async -> [ImpactPreview.Entry]?
    }

    enum Scope: Equatable { case thisApp, allApps }

    /// Letters, marks, numbers and underscore — the matcher's own boundary class (§5.5).
    private static let wordCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "_"))

    let source: CorrectionSource

    var heard = "" { didSet { draftChanged() } }
    var write = "" { didSet { draftChanged() } }
    var soundsLike = "" { didSet { draftChanged() } }
    var scope: Scope { didSet { draftChanged() } }
    var remember = true

    private(set) var saved = false
    /// A failed `ConfigStore.update`, cleared by the next draft change (§5.5).
    private(set) var saveError: String?
    private(set) var impact: ImpactPreview.Result?

    private let deps: Dependencies
    private let existing: [CorrectionRule]
    /// Fixed for the window's life, so Save appends one rule however often the draft changed.
    private let ruleID = UUID().uuidString
    private var tallied = false
    private var impactTask: Task<Void, Never>?

    init(source: CorrectionSource, config: Config, deps: Dependencies) {
        self.source = source
        self.deps = deps
        existing = config.corrections
        scope = source.bundleID == nil ? .allApps : .thisApp
        if source.preselectAll {
            select(NSRange(source.text.startIndex..<source.text.endIndex, in: source.text))
        }
    }

    // MARK: - Selection (R29)

    /// R29: a selection snaps outward to whole words and starts a fresh draft, because a
    /// rule built from half a word could never match.
    func select(_ range: NSRange) {
        guard
            let selected = Range(range, in: source.text),
            let phrase = Self.snapped(selected, in: source.text)
        else { return reset(to: "") }
        reset(to: phrase)
    }

    private func reset(to phrase: String) {
        heard = phrase
        write = phrase
        soundsLike = phrase
    }

    private static func snapped(
        _ range: Range<String.Index>, in text: String
    ) -> String? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace { lower = text.index(after: lower) }
        while upper > lower, text[text.index(before: upper)].isWhitespace {
            upper = text.index(before: upper)
        }
        guard lower < upper else { return nil }
        while lower > text.startIndex, isWord(text[text.index(before: lower)]) {
            lower = text.index(before: lower)
        }
        while upper < text.endIndex, isWord(text[upper]) { upper = text.index(after: upper) }
        return String(text[lower..<upper])
    }

    private static func isWord(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(wordCharacters.contains)
    }

    // MARK: - Scope (R30)

    var canScopeToApp: Bool { source.bundleID != nil }

    var thisAppLabel: String {
        source.appName.map { "This app · \($0)" } ?? "This app"
    }

    /// How the scope reads in a message: the app's own name, or "All apps".
    var scopeName: String {
        scope == .thisApp ? (source.appName ?? source.bundleID ?? "This app") : "All apps"
    }

    // MARK: - Draft, preview and validation (R5, R31)

    var draftRule: CorrectionRule {
        CorrectionRule(
            id: ruleID,
            heard: heard,
            write: write,
            soundsLike: soundsLike
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            bundleID: scope == .thisApp ? source.bundleID : nil
        )
    }

    var previewText: String {
        let rules = CorrectionResolver(rules: [draftRule]).rules(for: draftRule.bundleID)
        return CorrectionApplier(rules: rules).apply(to: source.text).text
    }

    var validationError: String? {
        CorrectionValidator.validate(
            draftRule,
            against: existing,
            excluding: nil,
            scopeName: scope == .thisApp ? source.appName : nil
        )?.message
    }

    var impactLine: String? {
        guard let impact else { return nil }
        guard !impact.historyOff else { return "History is off — no preview of past dictations." }
        let scope = scope == .thisApp ? " in \(scopeName)" : ""
        return "Would have changed \(impact.matching) of \(impact.total) past dictations\(scope)"
    }

    // MARK: - Confirmation (R32)

    var canSave: Bool { remember }

    var confirmationTitle: String { "Remembered for \(scopeName)" }

    var confirmationDetail: String {
        let place = scope == .thisApp ? "in future dictations to \(scopeName)" : "in every app"
        return "“\(heard)” will be written as “\(write)” \(place). "
            + "Edit or disable it any time under Settings → Vocabulary."
    }

    // MARK: - Writes (R32)

    /// R32: the corrected text goes to the pasteboard and nowhere else — never a paste,
    /// never a submit key.
    func copy() async {
        _ = deps.pasteboard.write(previewText)
        await tallyOnce()
    }

    func save() async {
        guard canSave, validationError == nil else { return }
        let rule = draftRule
        let phrase = heard
        let counted = tallied
        do {
            try await deps.store.update { @Sendable in
                $0.corrections.append(rule)
                if !counted {
                    $0.correctionTally = CorrectionTally.incremented(
                        $0.correctionTally, heard: phrase, now: Date()
                    )
                }
            }
            tallied = true
            saved = true
        } catch {
            saveError = AnyError(error).description
        }
    }

    /// R32: one tally increment per window, whichever of Copy and Save came first.
    private func tallyOnce() async {
        guard !tallied, !heard.isEmpty else { return }
        let phrase = heard
        do {
            try await deps.store.update { @Sendable in
                $0.correctionTally = CorrectionTally.incremented(
                    $0.correctionTally, heard: phrase, now: Date()
                )
            }
            tallied = true
        } catch {
            Log.config.error("Could not record correction: \(AnyError(error).description)")
        }
    }

    // MARK: - Impact task

    private func draftChanged() {
        saveError = nil
        impactTask?.cancel()
        let rule = draftRule
        guard !rule.heard.isEmpty else {
            impact = nil
            return
        }
        impactTask = Task { [deps] in
            let entries = await deps.historyEntries()
            // The draft may have moved on while the history was read (§5.4).
            guard !Task.isCancelled, self.draftRule == rule else { return }
            self.impact = ImpactPreview.compute(rule: rule, over: entries)
        }
    }

    /// Awaits the impact task the last draft change started.
    func settle() async {
        await impactTask?.value
    }
}

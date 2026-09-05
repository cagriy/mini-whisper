import Foundation
import MWConfig
import MWCorrections
import MWSupport
import Observation

/// The corrections table and its detail form, the often-corrected tally and the
/// per-engine hint report (R33–R36). It mirrors `ProfilesEditorModel`: the table is
/// read-only, the selected row is edited in the form below it, and every accepted
/// change is written through to `config.json` at once.
@MainActor
@Observable
final class CorrectionsEditorModel {
    struct Row: Identifiable, Equatable {
        var id: String
        var heard: String
        var write: String
        var scope: String
        var enabled: Bool
    }

    /// The report row's dot: sent, sent with something dropped, or not sent at all.
    enum HintStatus: Equatable { case ok, warning, off }

    struct HintRow: Identifiable, Equatable {
        var id: String
        var label: String
        var detail: String
        var status: HintStatus
    }

    private let store: ConfigStore
    private let apps: any AppListing
    private let openCorrection: @MainActor (CorrectionSource) -> Void

    private var rules: [CorrectionRule]
    private(set) var error: String?
    private var vocabulary: [String]
    private var tally: [CorrectionTallyEntry]

    var selection: String? {
        didSet { error = nil }
    }

    init(
        config: Config,
        store: ConfigStore,
        apps: any AppListing,
        openCorrection: @escaping @MainActor (CorrectionSource) -> Void
    ) {
        rules = config.corrections
        vocabulary = config.vocabulary
        tally = config.correctionTally
        self.store = store
        self.apps = apps
        self.openCorrection = openCorrection
    }

    /// R36: a rule saved from the correction window reaches the open table through
    /// AppDelegate's config-change consumer, which is the only one there is (N4).
    func refresh(_ config: Config) {
        rules = config.corrections
        vocabulary = config.vocabulary
        tally = config.correctionTally
        if let selection, !rules.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    // MARK: - Table

    var rows: [Row] {
        rules.map {
            Row(
                id: $0.id, heard: $0.heard, write: $0.write,
                scope: scopeLabel($0.bundleID), enabled: $0.enabled
            )
        }
    }

    var selectedRule: CorrectionRule? { rules.first { $0.id == selection } }

    var runningApps: [AppChoice] { apps.sortedRunningApps() }

    func displayName(_ bundleID: String) -> String { apps.name(forBundleID: bundleID) }

    func scopeLabel(_ bundleID: String?) -> String {
        bundleID.map(displayName) ?? "All apps"
    }

    func soundsLikeText(for id: String) -> String {
        rules.first { $0.id == id }?.soundsLike.joined(separator: ", ") ?? ""
    }

    // MARK: - Detail form (R34)

    func setHeard(_ heard: String, for id: String) async {
        await edit(id) { $0.heard = heard }
    }

    func setWrite(_ write: String, for id: String) async {
        await edit(id) { $0.write = write }
    }

    func setSoundsLike(_ text: String, for id: String) async {
        let values = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        await edit(id) { $0.soundsLike = values }
    }

    func setScope(_ bundleID: String?, for id: String) async {
        await edit(id) { $0.bundleID = bundleID }
    }

    func setEnabled(_ enabled: Bool, for id: String) async {
        await edit(id) { $0.enabled = enabled }
    }

    func remove(_ id: String) async {
        guard rules.contains(where: { $0.id == id }) else { return }
        rules.removeAll { $0.id == id }
        if selection == id { selection = nil }
        await persist()
    }

    /// R34: the draft is validated before it replaces the stored rule, so a rejected
    /// edit leaves both the table and `config.json` as they were.
    private func edit(_ id: String, _ mutate: (inout CorrectionRule) -> Void) async {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        var draft = rules[index]
        mutate(&draft)
        if let failure = CorrectionValidator.validate(
            draft, against: rules, excluding: id, scopeName: draft.bundleID.map(displayName)
        ) {
            error = failure.message
            return
        }
        error = nil
        rules[index] = draft
        await persist()
    }

    private func persist() async {
        let rules = rules
        do {
            try await store.update { @Sendable in $0.corrections = rules }
        } catch {
            Log.config.error("Could not save corrections: \(AnyError(error).description)")
        }
    }

    // MARK: - Often corrected (R35)

    var tallyRows: [CorrectionTally.TallyRow] {
        CorrectionTally.top(tally, rules: rules)
    }

    func remember(_ phrase: String) {
        openCorrection(CorrectionSource(phrase: phrase))
    }

    // MARK: - Recognition hints (R33)

    var hintRows: [HintRow] {
        HintReport.report(
            rules: rules, vocabulary: vocabulary, support: HintSupport.speechAnalyzer
        )
        .map {
            HintRow(id: $0.label, label: $0.label, detail: Self.detail($0), status: Self.status($0))
        }
    }

    private static func detail(_ row: HintReport.Row) -> String {
        switch row.state {
        case .supported:
            var parts = ["\(row.sent) \(noun(row.engine)) sent"]
            if let cap = row.cap { parts.append("cap \(cap)") }
            if let clause = skippedClause(row.skipped) { parts.append(clause) }
            return parts.joined(separator: " · ")
        case .unavailable(let reason): return "hints not sent · \(reason)"
        case .notSent(let reason): return "\(reason) · rules still apply"
        case .prompt: return "terms and corrections added to the prompt"
        }
    }

    private static func status(_ row: HintReport.Row) -> HintStatus {
        switch row.state {
        case .supported: row.skipped.isEmpty ? .ok : .warning
        case .prompt: .ok
        case .notSent, .unavailable: .off
        }
    }

    /// Each provider names what it takes differently, and the report reads as its own
    /// wire shape rather than a generic count.
    private static func noun(_ engine: EngineName?) -> String {
        switch engine {
        case .openai: "keywords"
        case .speechmatics: "entries"
        default: "hints"
        }
    }

    private static func skippedClause(_ skipped: [SkippedHint]) -> String? {
        guard let first = skipped.first else { return nil }
        let more = skipped.count > 1 ? ", and \(skipped.count - 1) more" : ""
        return "\(skipped.count) skipped: “\(first.term)” \(sentence(first.reason))\(more)"
    }

    private static func sentence(_ reason: SkipReason) -> String {
        switch reason {
        case .overCap: "is past the cap"
        case .emptyAfterFilter: "is empty once the forbidden characters are removed"
        case .tooManyWords: "is over 6 words"
        case .wordTooLong: "has a word over 4000 characters"
        }
    }
}

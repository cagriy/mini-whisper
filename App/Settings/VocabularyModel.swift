import MWConfig
import MWSupport
import Observation

/// F28's term list. Terms are trimmed, kept unique and in entry order, and every
/// change is written through to `config.json` immediately.
@MainActor
@Observable
final class VocabularyModel {
    private(set) var terms: [String]
    private let store: ConfigStore

    init(terms: [String], store: ConfigStore) {
        self.terms = terms
        self.store = store
    }

    func add(_ term: String) async {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !terms.contains(trimmed) else { return }
        terms.append(trimmed)
        await persist()
    }

    func remove(at index: Int) async {
        guard terms.indices.contains(index) else { return }
        terms.remove(at: index)
        await persist()
    }

    private func persist() async {
        let terms = terms
        do {
            try await store.update { @Sendable in $0.vocabulary = terms }
        } catch {
            Log.config.error("Could not save vocabulary: \(AnyError(error).description)")
        }
    }
}

import SwiftUI

/// F28's term list as chips plus an entry field.
struct VocabularySection: View {
    let model: SettingsModel

    @State private var draft = ""

    var body: some View {
        SettingsPane(title: "Vocabulary") {
            FlowChips(terms: model.vocabulary.terms) { index in
                Task { await model.vocabulary.remove(at: index) }
            }

            TextField("Add a word or name, then press Return", text: $draft)
                .frame(width: 320)
                .onSubmit {
                    let term = draft
                    draft = ""
                    Task { await model.vocabulary.add(term) }
                }

            SettingsFootnote(
                "Terms are passed to the transcription instructions and the cleanup prompt"
                    + " so names and jargon are kept as written."
            )
        }
    }
}

private struct FlowChips: View {
    let terms: [String]
    let remove: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(terms.enumerated()), id: \.element) { index, term in
                HStack(spacing: 4) {
                    Text(term)
                    Button { remove(index) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }
}

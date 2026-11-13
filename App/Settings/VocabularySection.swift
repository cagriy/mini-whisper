import SwiftUI

/// F28's term list as chips plus an entry field, followed by the corrections table,
/// the often-corrected tally and the hint report (R33).
struct VocabularySection: View {
    let model: SettingsModel

    @State private var draft = ""

    var body: some View {
        Card {
            SettingRow.full(spacing: DS.Space.s4) {
                FlowLayout {
                    ForEach(Array(model.vocabulary.terms.enumerated()), id: \.element) { index, term in
                        Chip(term) { Task { await model.vocabulary.remove(at: index) } }
                    }
                }

                TextField("Add a word or name, then press Return", text: $draft, prompt: Text(""))
                    .fieldPlaceholder("Add a word or name, then press Return", shown: draft.isEmpty)
                    .dsField()
                    .frame(width: 320)
                    .onSubmit {
                        let term = draft
                        draft = ""
                        Task { await model.vocabulary.add(term) }
                    }

                SettingsFootnote(
                    "Terms are sent to the recognizer as hints and kept as written by the"
                        + " cleanup prompt."
                )
            }

            CorrectionsEditor(model: model.corrections)
        }
    }
}

import SwiftUI

/// F26's toggle and footnote, the two prompt editors, and the per-app profiles
/// table from the accepted mockup.
struct CleanupSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Card {
            SettingRow(
                "Text cleanup",
                description: model.cleanupToggleEnabled
                    ? nil
                    : "Requires an OpenAI API key — add one under Keys. Without a key, on-device"
                        + " transcripts are pasted as spoken."
            ) {
                Toggle(
                    "Text cleanup",
                    isOn: settingsBinding(model.cleanupShownOn) { await model.setCleanupEnabled($0) }
                )
                .toggleStyle(.ds)
                .disabled(!model.cleanupToggleEnabled)
            }

            promptFileEditor(
                title: "Cleanup prompt",
                text: $model.cleanupPromptDraft,
                url: model.cleanupPromptURL,
                save: model.saveCleanupPrompt
            )
            promptFileEditor(
                title: "Transcription instructions",
                text: $model.transcribeDraft,
                url: model.transcribeInstructionsURL,
                save: model.saveTranscribeInstructions,
                error: model.promptError
            )

            SettingRow.full("Per-app profiles", spacing: DS.Space.s4) {
                ProfilesEditor(model: model.profiles)
            }
        }
        .onAppear(perform: model.loadPrompts)
    }

    /// Both files use the same editor and the source's two buttons.
    private func promptFileEditor(
        title: String,
        text: Binding<String>,
        url: URL,
        save: @escaping () -> Void,
        error: String? = nil
    ) -> some View {
        SettingRow.full(title, spacing: DS.Space.s4) {
            PromptTextEditor(title: title, text: text)
            HStack(spacing: DS.Space.s5) {
                Button("Save Prompt", action: save)
                Button("Open in Editor") {
                    save()
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.pill(size: .small))
            if let error {
                ErrorLine(error)
            }
        }
    }
}

/// A multi-line prompt field; the row it sits in names it on screen.
struct PromptTextEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .dsField(.area())
            .accessibilityLabel(title)
    }
}

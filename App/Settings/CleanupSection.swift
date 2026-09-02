import SwiftUI

/// F26's toggle and footnote, the two prompt editors, and the per-app profiles
/// table from the accepted mockup.
struct CleanupSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        SettingsPane(title: "Cleanup") {
            Toggle(
                "Text cleanup",
                isOn: settingsBinding(model.cleanupShownOn) { await model.setCleanupEnabled($0) }
            )
            .disabled(!model.cleanupToggleEnabled)

            if !model.cleanupToggleEnabled {
                SettingsFootnote(
                    "Requires an OpenAI API key — add one under Keys. Without a key, on-device"
                        + " transcripts are pasted as spoken."
                )
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
                save: model.saveTranscribeInstructions
            )
            if let error = model.promptError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            ProfilesEditor(model: model.profiles)
        }
        .onAppear(perform: model.loadPrompts)
    }

    /// Both files use the same editor and the source's two buttons.
    private func promptFileEditor(
        title: String,
        text: Binding<String>,
        url: URL,
        save: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PromptTextEditor(title: title, text: text)
            HStack {
                Button("Save Prompt", action: save)
                Button("Open in Editor") {
                    save()
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
    }
}

/// A labelled multi-line prompt field.
struct PromptTextEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium))
            TextEditor(text: $text)
                .font(.system(size: 12))
                .frame(height: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
        }
    }
}

import MWConfig
import SwiftUI

/// The profiles table and its detail form (F27). The Default row is synthetic and
/// read-only: it shows what the top-level settings and `prompt.txt` already say.
struct ProfilesEditor: View {
    @Bindable var model: ProfilesEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Table(model.rows, selection: $model.selection) {
                TableColumn("Profile", value: \.name)
                TableColumn("Apps", value: \.apps)
                TableColumn("Cleanup", value: \.cleanup).width(70)
                TableColumn("Submit key", value: \.submitKey).width(90)
            }
            .settingsTable(height: 130)

            HStack(spacing: DS.Space.s3) {
                Button("+") { Task { await model.add() } }
                Button("−") {
                    guard let id = model.selectedProfile?.id else { return }
                    Task { await model.remove(id) }
                }
                .disabled(model.selectedProfile == nil)
            }
            .buttonStyle(.pill(size: .small))

            if let profile = model.selectedProfile {
                ProfileDetail(profile: profile, model: model)
            }

            SettingsFootnote(
                "An app belongs to one profile. “Add…” lists running apps or opens a"
                    + " chooser. The Default profile uses prompt.txt."
            )
        }
    }
}

/// The detail form. Free text is edited locally and committed on Return or Save,
/// so a config write does not happen per keystroke.
private struct ProfileDetail: View {
    let profile: Profile
    let model: ProfilesEditorModel

    @State private var name = ""
    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            DetailRow("Name") {
                TextField("Profile name", text: $name, prompt: Text(""))
                    .fieldPlaceholder("Profile name", shown: name.isEmpty)
                    .dsField()
                    .frame(width: 220)
                    .onSubmit { Task { await model.setName(name, for: profile.id) } }
            }

            DetailRow("Apps", alignment: .top) {
                appChips
            }

            if let error = model.appAssignmentError {
                ErrorLine(error)
            }

            DetailRow("Cleanup") {
                Toggle(
                    "Cleanup",
                    isOn: settingsBinding(profile.cleanupEnabled) {
                        await model.setCleanupEnabled($0, for: profile.id)
                    }
                )
                .toggleStyle(.ds)
            }

            DetailRow("Submit key") {
                SegmentedPill(
                    selection: settingsBinding(profile.submitKey) {
                        await model.setSubmitKey($0, for: profile.id)
                    },
                    options: SubmitKey.allCases.map { ($0, ProfilesEditorModel.label(for: $0)) }
                )
            }

            DetailRow("Prompt", alignment: .top) {
                PromptTextEditor(title: "Prompt", text: $prompt)
            }
            HStack(spacing: DS.Space.s5) {
                Button("Save Prompt") { Task { await model.setPrompt(prompt, for: profile.id) } }
                    .buttonStyle(.pill(size: .small))
                SettingsFootnote("Clear this to fall back to prompt.txt.")
            }
        }
        .padding(.top, DS.Space.s2)
        .task(id: profile.id) {
            name = profile.name
            prompt = model.prompt(for: profile.id)
        }
    }

    private var appChips: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            FlowLayout {
                ForEach(profile.bundleIDs, id: \.self) { bundleID in
                    Chip(model.displayName(bundleID)) {
                        Task { await model.removeBundleID(bundleID, from: profile.id) }
                    }
                }
            }
            PillMenu(title: "Add…") {
                model.runningApps.map { app in
                    PillMenu.Item(title: app.name) {
                        Task { await model.addBundleID(app.bundleID, to: profile.id) }
                    }
                } + [
                    PillMenu.Item(title: "Choose from Applications…", separated: true) {
                        guard let choice = AppChooser.chooseFromApplications() else { return }
                        Task { await model.addBundleID(choice.bundleID, to: profile.id) }
                    },
                ]
            }
        }
    }
}

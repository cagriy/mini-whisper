import MWConfig
import SwiftUI

/// The profiles table and its detail form (F27). The Default row is synthetic and
/// read-only: it shows what the top-level settings and `prompt.txt` already say.
struct ProfilesEditor: View {
    @Bindable var model: ProfilesEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-app profiles").font(.callout.weight(.medium))

            Table(model.rows, selection: $model.selection) {
                TableColumn("Profile", value: \.name)
                TableColumn("Apps", value: \.apps)
                TableColumn("Cleanup", value: \.cleanup).width(70)
                TableColumn("Submit key", value: \.submitKey).width(90)
            }
            .frame(height: 130)

            HStack(spacing: 6) {
                Button("+") { Task { await model.add() } }
                Button("−") {
                    guard let id = model.selectedProfile?.id else { return }
                    Task { await model.remove(id) }
                }
                .disabled(model.selectedProfile == nil)
            }
            .controlSize(.small)

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Name").frame(width: 90, alignment: .leading)
                TextField("Profile name", text: $name)
                    .frame(width: 220)
                    .onSubmit { Task { await model.setName(name, for: profile.id) } }
            }

            HStack(alignment: .top) {
                Text("Apps").frame(width: 90, alignment: .leading)
                appChips
            }

            if let error = model.appAssignmentError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Toggle(
                "Cleanup",
                isOn: settingsBinding(profile.cleanupEnabled) {
                    await model.setCleanupEnabled($0, for: profile.id)
                }
            )

            HStack {
                Text("Submit key").frame(width: 90, alignment: .leading)
                Picker(
                    "",
                    selection: settingsBinding(profile.submitKey) {
                        await model.setSubmitKey($0, for: profile.id)
                    }
                ) {
                    ForEach(SubmitKey.allCases, id: \.self) { key in
                        Text(ProfilesEditorModel.label(for: key)).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            PromptTextEditor(title: "Prompt", text: $prompt)
            HStack {
                Button("Save Prompt") { Task { await model.setPrompt(prompt, for: profile.id) } }
                    .controlSize(.small)
                SettingsFootnote("Clear this to fall back to prompt.txt.")
            }
        }
        .padding(.top, 4)
        .task(id: profile.id) {
            name = profile.name
            prompt = model.prompt(for: profile.id)
        }
    }

    private var appChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ForEach(profile.bundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 4) {
                        Text(model.displayName(bundleID))
                        Button {
                            Task { await model.removeBundleID(bundleID, from: profile.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
            Menu("Add…") {
                ForEach(model.runningApps) { app in
                    Button(app.name) { Task { await model.addBundleID(app.bundleID, to: profile.id) } }
                }
                Divider()
                Button("Choose from Applications…") {
                    guard let choice = AppChooser.chooseFromApplications() else { return }
                    Task { await model.addBundleID(choice.bundleID, to: profile.id) }
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 160, alignment: .leading)
        }
    }
}

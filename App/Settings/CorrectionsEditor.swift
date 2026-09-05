import MWConfig
import SwiftUI

/// The three groups the Vocabulary pane gains (R33), matching the accepted mockup
/// `mockup-v2-vocab-detail-form.html`: a read-only corrections table with a detail
/// form for the selected rule, the often-corrected tally, and the per-engine hint
/// report. Every rule lives in `CorrectionsEditorModel`.
struct CorrectionsEditor: View {
    @Bindable var model: CorrectionsEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            corrections
            tally
            hints
        }
    }

    // MARK: - Corrections (R33, R34)

    private var corrections: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Corrections").font(.callout.weight(.medium))

            Table(model.rows, selection: $model.selection) {
                TableColumn("Heard", value: \.heard)
                TableColumn("Write", value: \.write)
                TableColumn("Scope", value: \.scope).width(120)
                TableColumn("Enabled") { row in
                    Text(row.enabled ? "on" : "off")
                        .foregroundStyle(row.enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
                .width(60)
            }
            .frame(height: 130)

            Button("−") {
                guard let id = model.selectedRule?.id else { return }
                Task { await model.remove(id) }
            }
            .controlSize(.small)
            .disabled(model.selectedRule == nil)

            if let rule = model.selectedRule {
                RuleDetail(rule: rule, model: model)
            }

            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            SettingsFootnote(
                "Free text commits on Return. Rules are created from a dictation:"
                    + " Correct Last Dictation… in the menu bar, or Correct… on a History row."
            )
        }
    }

    // MARK: - Often corrected (R33, R35)

    private var tally: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Often corrected").font(.callout.weight(.medium))

            ForEach(model.tallyRows, id: \.heard) { row in
                HStack(spacing: 10) {
                    Text(row.heard)
                    Spacer()
                    Text("×\(row.count)").monospacedDigit().foregroundStyle(.secondary)
                    if row.hasRule {
                        Text("remembered").foregroundStyle(.green)
                    } else {
                        Button("Remember…") { model.remember(row.heard) }
                            .controlSize(.small)
                    }
                }
                .font(.callout)
                .frame(width: 380, alignment: .leading)
            }

            SettingsFootnote(
                "Phrases you corrected in the correction window, remembered or not."
                    + " Remember… opens that window with the phrase selected."
            )
        }
    }

    // MARK: - Recognition hints (R33)

    private var hints: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recognition hints").font(.callout.weight(.medium))

            ForEach(model.hintRows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(Self.dot(row.status))
                        .frame(width: 8, height: 8)
                    Text(row.label).frame(width: 150, alignment: .leading)
                    Text(row.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
            }

            SettingsFootnote(
                "Counts include every rule regardless of app. A hint makes a spelling more"
                    + " likely; the rule makes it certain."
            )
        }
    }

    private static func dot(_ status: CorrectionsEditorModel.HintStatus) -> Color {
        switch status {
        case .ok: .green
        case .warning: .orange
        case .off: .secondary
        }
    }
}

/// The selected rule's form. Free text is edited locally and committed on Return, so
/// a config write does not happen per keystroke — as the profiles editor does.
private struct RuleDetail: View {
    let rule: CorrectionRule
    let model: CorrectionsEditorModel

    @State private var heard = ""
    @State private var write = ""
    @State private var soundsLike = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Heard", text: $heard) { await model.setHeard($0, for: rule.id) }
            field("Write", text: $write) { await model.setWrite($0, for: rule.id) }
            field("Sounds like", text: $soundsLike) { await model.setSoundsLike($0, for: rule.id) }

            HStack {
                Text("Scope").frame(width: 90, alignment: .leading)
                scope
            }

            HStack {
                Text("Enabled").frame(width: 90, alignment: .leading)
                Toggle(
                    "",
                    isOn: settingsBinding(rule.enabled) {
                        await model.setEnabled($0, for: rule.id)
                    }
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
        .task(id: rule.id) {
            heard = rule.heard
            write = rule.write
            soundsLike = model.soundsLikeText(for: rule.id)
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        commit: @escaping @MainActor (String) async -> Void
    ) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            TextField(label, text: text)
                .labelsHidden()
                .frame(width: 220)
                .onSubmit {
                    let value = text.wrappedValue
                    Task { await commit(value) }
                }
        }
    }

    private var scope: some View {
        Menu(model.scopeLabel(rule.bundleID)) {
            Button("All apps") { Task { await model.setScope(nil, for: rule.id) } }
            if let bundleID = rule.bundleID {
                Button(model.displayName(bundleID)) {
                    Task { await model.setScope(bundleID, for: rule.id) }
                }
            }
            Divider()
            ForEach(model.runningApps) { app in
                Button(app.name) { Task { await model.setScope(app.bundleID, for: rule.id) } }
            }
            Divider()
            Button("Choose from Applications…") {
                guard let choice = AppChooser.chooseFromApplications() else { return }
                Task { await model.setScope(choice.bundleID, for: rule.id) }
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 200, alignment: .leading)
    }
}

import MWConfig
import SwiftUI

/// The three groups the Vocabulary pane gains (R33), matching the accepted mockup
/// `mockup-v2-vocab-detail-form.html`: a read-only corrections table with a detail
/// form for the selected rule, the often-corrected tally, and the per-engine hint
/// report. Every rule lives in `CorrectionsEditorModel`.
struct CorrectionsEditor: View {
    @Bindable var model: CorrectionsEditorModel

    var body: some View {
        SettingRow.full("Corrections", spacing: DS.Space.s4) { corrections }
        SettingRow.full("Often corrected", spacing: DS.Space.s4) { tally }
        SettingRow.full("Recognition hints", spacing: DS.Space.s4) { hints }
    }

    // MARK: - Corrections (R33, R34)

    @ViewBuilder private var corrections: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("Heard", value: \.heard)
            TableColumn("Write", value: \.write)
            TableColumn("Scope", value: \.scope).width(120)
            TableColumn("Enabled") { row in
                Text(row.enabled ? "on" : "off")
                    .foregroundStyle(row.enabled ? DS.Colors.text : DS.Colors.textTertiary)
            }
            .width(60)
        }
        .settingsTable(height: 130)

        Button("−") {
            guard let id = model.selectedRule?.id else { return }
            Task { await model.remove(id) }
        }
        .buttonStyle(.pill(size: .small))
        .disabled(model.selectedRule == nil)

        if let rule = model.selectedRule {
            RuleDetail(rule: rule, model: model)
        }

        if let error = model.error {
            ErrorLine(error)
        }

        SettingsFootnote(
            "Free text commits on Return. Rules are created from a dictation:"
                + " Correct Last Dictation… in the menu bar, or Correct… on a Dictations row."
        )
    }

    // MARK: - Often corrected (R33, R35)

    @ViewBuilder private var tally: some View {
        ForEach(model.tallyRows, id: \.heard) { row in
            HStack(spacing: DS.Space.s5) {
                Text(row.heard).foregroundStyle(DS.Colors.text)
                Spacer()
                Text("×\(row.count)").monospacedDigit().foregroundStyle(DS.Colors.textSecondary)
                if row.hasRule {
                    Text("remembered").foregroundStyle(DS.Colors.ok)
                } else {
                    Button("Remember…") { model.remember(row.heard) }
                        .buttonStyle(.pill(size: .small))
                }
            }
            .textStyle(.body)
            .frame(width: 380, alignment: .leading)
        }

        SettingsFootnote(
            "Phrases you corrected in the correction window, remembered or not."
                + " Remember… opens that window with the phrase selected."
        )
    }

    // MARK: - Recognition hints (R33)

    @ViewBuilder private var hints: some View {
        ForEach(model.hintRows) { row in
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                Circle()
                    .fill(Self.dot(row.status))
                    .frame(width: 8, height: 8)
                Text(row.label)
                    .foregroundStyle(DS.Colors.text)
                    .frame(width: 150, alignment: .leading)
                Text(row.detail)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textStyle(.meta)
        }

        SettingsFootnote(
            "Counts include every rule regardless of app. A hint makes a spelling more"
                + " likely; the rule makes it certain."
        )
    }

    private static func dot(_ status: CorrectionsEditorModel.HintStatus) -> Color {
        switch status {
        case .ok: DS.Colors.ok
        case .warning: DS.Colors.warn
        case .off: DS.Colors.textTertiary
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
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            field("Heard", text: $heard) { await model.setHeard($0, for: rule.id) }
            field("Write", text: $write) { await model.setWrite($0, for: rule.id) }
            field("Sounds like", text: $soundsLike) { await model.setSoundsLike($0, for: rule.id) }

            DetailRow("Scope") {
                scope
            }

            DetailRow("Enabled") {
                Toggle(
                    "Enabled",
                    isOn: settingsBinding(rule.enabled) {
                        await model.setEnabled($0, for: rule.id)
                    }
                )
                .toggleStyle(.ds)
            }
        }
        .padding(.top, DS.Space.s2)
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
        DetailRow(label) {
            TextField(label, text: text, prompt: Text(""))
                .fieldPlaceholder(label, shown: text.wrappedValue.isEmpty)
                .dsField()
                .frame(width: 220)
                .onSubmit {
                    let value = text.wrappedValue
                    Task { await commit(value) }
                }
        }
    }

    private var scope: some View {
        PillMenu(title: model.scopeLabel(rule.bundleID)) {
            var items = [PillMenu.Item(title: "All apps") { Task { await model.setScope(nil, for: rule.id) } }]
            if let bundleID = rule.bundleID {
                items.append(PillMenu.Item(title: model.displayName(bundleID)) {
                    Task { await model.setScope(bundleID, for: rule.id) }
                })
            }
            for (index, app) in model.runningApps.enumerated() {
                items.append(PillMenu.Item(title: app.name, separated: index == 0) {
                    Task { await model.setScope(app.bundleID, for: rule.id) }
                })
            }
            items.append(PillMenu.Item(title: "Choose from Applications…", separated: true) {
                guard let choice = AppChooser.chooseFromApplications() else { return }
                Task { await model.setScope(choice.bundleID, for: rule.id) }
            })
            return items
        }
    }
}

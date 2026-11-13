import MWConfig
import SwiftUI

/// Live transcript, the engine list with its gating (F23, F24), the two engine-lifetime
/// steppers, and updates.
struct GeneralSection: View {
    let model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Card("Dictation") {
                SettingRow("Live transcript", description: "Show the words in the overlay while you speak.") {
                    Toggle(
                        "Live transcript",
                        isOn: settingsBinding(model.config.streamingEnabled) { await model.setStreamingEnabled($0) }
                    )
                    .toggleStyle(.ds)
                }
                SettingRow.full("Engine") {
                    ForEach(model.engineRows) { row in
                        engineRow(row)
                    }
                }
                SettingRow(
                    "Stop microphone after idle",
                    description: "The mic indicator shows only while the engine runs. Lower values save"
                        + " power; higher values keep the next press instant."
                ) {
                    StepperPill(
                        title: "Stop microphone after idle",
                        value: settingsBinding(model.config.idleStopSeconds) { await model.setIdleStopSeconds($0) },
                        range: SettingsModel.idleStopSecondsRange,
                        step: 10,
                        label: model.idleStopLabel
                    )
                }
                SettingRow(
                    "Stop tap-to-talk after",
                    description: "A tap arms toggle mode; recording ends at the next tap or at this limit."
                ) {
                    StepperPill(
                        title: "Stop tap-to-talk after",
                        value: settingsBinding(model.config.toggleMaxSeconds / 60) { await model.setToggleCapMinutes($0) },
                        range: SettingsModel.toggleCapMinutesRange,
                        step: 1,
                        label: model.toggleCapLabel
                    )
                }
            }

            Card("Updates") {
                SettingRow(
                    "Automatically check for updates",
                    description: "Version \(model.appVersion). Checked once a day; an update installs"
                        + " only after you approve it."
                ) {
                    // Not `settingsBinding`: Sparkle owns this preference and rewrites it
                    // on every scheduled check, so config.json never holds a copy.
                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { model.automaticUpdatesEnabled },
                            set: { model.setAutomaticUpdates($0) }
                        )
                    )
                    .toggleStyle(.ds)
                }
                SettingRow("Check for an update now") {
                    Button("Check Now") { model.checkForUpdatesNow() }
                        .buttonStyle(.pill(size: .small))
                }
            }
        }
        .task { await model.refreshSpeechModel() }
    }

    private func engineRow(_ row: SettingsModel.EngineRow) -> some View {
        RadioRow(
            row.title,
            detail: row.disabledReason.map { .warning($0) } ?? row.subtitle.map { .plain($0) },
            selected: model.selectedEngine == row.name,
            select: { Task { await model.selectEngine(row.name) } }
        ) {
            accessory(row.accessory)
        }
        .disabled(!row.isEnabled)
    }

    @ViewBuilder private func accessory(_ accessory: SettingsModel.EngineAccessory?) -> some View {
        switch accessory {
        case .download:
            Button(SettingsModel.EngineAccessory.download.text) {
                Task { await model.installSpeechModel() }
            }
            .buttonStyle(.pill(size: .small))
        case .installing(let fraction):
            // The system reports no fraction until the transfer starts, so the bar
            // only replaces the spinner once there is something to show.
            HStack(spacing: DS.Space.s3) {
                if fraction > 0 {
                    ProgressView(value: fraction).frame(width: 90)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(SettingsModel.EngineAccessory.installing(fraction: fraction).text)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .tint(DS.Colors.accent)
        case .installed:
            Text(SettingsModel.EngineAccessory.installed.text)
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
        case nil:
            EmptyView()
        }
    }
}

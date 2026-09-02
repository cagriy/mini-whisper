import MWConfig
import SwiftUI

/// Live transcript, the engine list with its gating (F23, F24) and the two
/// engine-lifetime steppers.
struct GeneralSection: View {
    let model: SettingsModel

    var body: some View {
        SettingsPane(title: "General") {
            Toggle(
                "Live transcript",
                isOn: settingsBinding(model.config.streamingEnabled) { await model.setStreamingEnabled($0) }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Engine").font(.callout.weight(.medium))
                ForEach(model.engineRows) { row in
                    engineRow(row)
                }
            }

            stepperRow(
                title: "Stop microphone after idle",
                value: model.idleStopLabel,
                binding: settingsBinding(model.config.idleStopSeconds) { await model.setIdleStopSeconds($0) },
                range: SettingsModel.idleStopSecondsRange,
                step: 10,
                footnote: "The mic indicator shows only while the engine runs. Lower values save"
                    + " power; higher values keep the next press instant."
            )

            stepperRow(
                title: "Stop tap-to-talk after",
                value: model.toggleCapLabel,
                binding: settingsBinding(model.config.toggleMaxSeconds / 60) { await model.setToggleCapMinutes($0) },
                range: SettingsModel.toggleCapMinutesRange,
                step: 1,
                footnote: "A tap arms toggle mode; recording ends at the next tap or at this limit."
            )
        }
        .task { await model.refreshSpeechModel() }
    }

    private func engineRow(_ row: SettingsModel.EngineRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                Task { await model.selectEngine(row.name) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: model.config.streamingEngine == row.name
                        ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(model.config.streamingEngine == row.name ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                        if let reason = row.disabledReason {
                            Text(reason).font(.caption).foregroundStyle(.orange)
                        } else if let subtitle = row.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!row.isEnabled)

            accessory(row.accessory)
        }
        .opacity(row.isEnabled ? 1 : 0.55)
    }

    @ViewBuilder private func accessory(_ accessory: SettingsModel.EngineAccessory?) -> some View {
        switch accessory {
        case .download:
            Button(SettingsModel.EngineAccessory.download.text) {
                Task { await model.installSpeechModel() }
            }
            .controlSize(.small)
        case .installing(let fraction):
            ProgressView(value: fraction).frame(width: 90)
        case .installed:
            Text(SettingsModel.EngineAccessory.installed.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func stepperRow(
        title: String,
        value: String,
        binding: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
                Stepper("", value: binding, in: range, step: step).labelsHidden()
            }
            SettingsFootnote(footnote)
        }
    }
}

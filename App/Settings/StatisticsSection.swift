import SwiftUI

/// Settings › Statistics (design v11 R27, R28): the typing speed, Reset, and what the record keeps.
struct StatisticsSection: View {
    let model: SettingsModel

    var body: some View {
        Card {
            SettingRow(
                "Typing speed",
                description: "Used to estimate the time dictation saves you, shown on Timeline."
            ) {
                StepperPill(
                    title: "Typing speed",
                    value: settingsBinding(model.config.typingWPM) { await model.setTypingSpeed($0) },
                    range: SettingsModel.typingSpeedRange,
                    step: SettingsModel.typingSpeedStep,
                    label: model.typingSpeedLabel
                )
            }
            SettingRow(
                "Reset statistics",
                description: "Erases the totals, records and milestones kept for Timeline, then rebuilds them from"
                    + " the meetings and dictations still stored."
            ) {
                Button("Reset Statistics", action: model.requestReset)
                    .buttonStyle(.pill(size: .small, tint: DS.Colors.recording))
            }
            SettingRow.full {
                SettingsFootnote(
                    "Statistics are numbers only: counts, lengths, word counts and estimated costs, plus which app"
                        + " each dictation went to. No text, titles or names of people. They stay on this Mac and"
                        + " are never sent anywhere."
                )
            }
        }
    }
}

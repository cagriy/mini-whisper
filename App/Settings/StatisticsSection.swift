import SwiftUI

/// Settings › Statistics (design v11 R27): Reset, and what the record keeps.
struct StatisticsSection: View {
    let model: SettingsModel

    var body: some View {
        Card {
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

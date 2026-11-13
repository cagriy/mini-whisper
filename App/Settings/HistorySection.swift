import SwiftUI

/// F29's retention control and Clear History. The slider commits when the drag ends,
/// so one adjustment writes the config and prunes once.
struct HistorySection: View {
    let model: SettingsModel
    @Binding var confirmingClear: Bool

    @State private var days = 0.0

    private static let sliderRange = Double(SettingsModel.retentionDaysRange.lowerBound)
        ... Double(SettingsModel.retentionDaysRange.upperBound)

    var body: some View {
        Card {
            SettingRow(
                "Keep dictations for",
                description: "0 days turns history off and writes nothing. Maximum 30 days."
                    + " Stored only on this Mac."
            ) {
                HStack(spacing: DS.Space.s5) {
                    Slider(value: $days, in: Self.sliderRange, step: 1) { editing in
                        guard !editing else { return }
                        Task { await model.setRetentionDays(Int(days)) }
                    }
                    .tint(DS.Colors.accent)
                    .frame(width: 200)
                    Text(SettingsModel.retentionLabel(days: Int(days)))
                        .textStyle(.body)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.textSecondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            // The row is named by the confirmation's own question.
            SettingRow("Delete every stored dictation") {
                Button("Clear History") { confirmingClear = true }
                    .buttonStyle(.pill(size: .small, tint: DS.Colors.recording))
            }
        }
        .onAppear { days = Double(model.config.historyRetentionDays) }
    }
}

import SwiftUI

/// F29's retention control and the two history actions. The slider commits when
/// the drag ends, so one adjustment writes the config and prunes once.
struct HistorySection: View {
    let model: SettingsModel

    @State private var days = 0.0
    @State private var confirmingClear = false

    private static let sliderRange = Double(SettingsModel.retentionDaysRange.lowerBound)
        ... Double(SettingsModel.retentionDaysRange.upperBound)

    var body: some View {
        SettingsPane(title: "History") {
            HStack {
                Text("Keep dictations for")
                Slider(value: $days, in: Self.sliderRange, step: 1) { editing in
                    guard !editing else { return }
                    Task { await model.setRetentionDays(Int(days)) }
                }
                .frame(width: 240)
                Text(SettingsModel.retentionLabel(days: Int(days)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }

            SettingsFootnote(
                "0 days turns history off and writes nothing. Maximum 30 days."
                    + " Stored only on this Mac."
            )

            HStack {
                Button("Open History…") { model.openHistory() }
                Button("Clear History") { confirmingClear = true }
            }
            .confirmationDialog(
                "Delete every stored dictation?",
                isPresented: $confirmingClear
            ) {
                Button("Clear History", role: .destructive) {
                    Task { await model.clearHistory() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear { days = Double(model.config.historyRetentionDays) }
    }
}

import SwiftUI

/// F34's volume slider: it previews the “on” sound when the drag ends.
struct SoundSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Card {
            SettingRow(
                "Volume",
                description: "Plays the start sound on release. A short tick precedes it only when the"
                    + " microphone needs to warm up."
            ) {
                HStack(spacing: DS.Space.s5) {
                    Slider(value: $model.volume, in: 0...1) { editing in
                        guard !editing else { return }
                        Task { await model.commitVolume() }
                    }
                    .tint(DS.Colors.accent)
                    .frame(width: 200)
                    Text("\(Int((model.volume * 100).rounded())) %")
                        .textStyle(.body)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.textSecondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }
}

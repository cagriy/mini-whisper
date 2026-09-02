import SwiftUI

/// F34's volume slider: it previews the “on” sound when the drag ends.
struct SoundSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        SettingsPane(title: "Sound") {
            HStack {
                Text("Volume")
                Slider(value: $model.volume, in: 0...1) { editing in
                    guard !editing else { return }
                    Task { await model.commitVolume() }
                }
                .frame(width: 280)
                Text("\(Int((model.volume * 100).rounded())) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
            SettingsFootnote(
                "Plays the start sound on release. A short tick precedes it only when the"
                    + " microphone needs to warm up."
            )
        }
    }
}

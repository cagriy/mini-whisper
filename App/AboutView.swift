import SwiftUI

/// The About window's content: the mark, the name, the version, what the app does and Credits.
struct AboutView: View {
    let version: String
    let showCredits: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            Tile.app
            Text("Mini Whisper")
                .textStyle(.title)
                .foregroundStyle(DS.Colors.text)
            Text("Version \(version)")
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
            Text("Hold your hotkey to talk, or tap to toggle recording. Transcribed text is pasted into the active app.")
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(maxWidth: 240)
                .fixedSize(horizontal: false, vertical: true)
            Text("Powered by OpenAI gpt-4o-mini-transcribe.")
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textTertiary)
            Button("Credits…", action: showCredits)
                .buttonStyle(.pill(.quietAction, size: .small))
        }
        .multilineTextAlignment(.center)
        .smallWindowBody(.top, top: DS.Space.s1)
    }
}

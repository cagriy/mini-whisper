import SwiftUI

/// The onboarding window's content (design §5.9): each permission's state, today's status line and
/// Continue, which wakes once both are granted.
struct OnboardingView: View {
    let model: OnboardingModel
    let openSettings: (OnboardingPermission) -> Void
    let proceed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text("Mini Whisper needs two permissions")
                .textStyle(.title)
                .foregroundStyle(DS.Colors.text)
            Text(
                "Microphone access is needed to transcribe speech, and Accessibility access allows"
                    + " pasting the transcribed text into other apps."
            )
            .textStyle(.body)
            .foregroundStyle(DS.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Card {
                ForEach(OnboardingModel.steps, id: \.self, content: row)
            }
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.s4) {
                Text(model.statusText)
                    .textStyle(.body)
                    .foregroundStyle(model.allGranted ? DS.Colors.ok : DS.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Continue", action: proceed)
                    .buttonStyle(.pill(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.continueEnabled)
            }
        }
        .smallWindowBody()
    }

    private func row(_ permission: OnboardingPermission) -> some View {
        let granted = model.granted(permission)
        return HStack(spacing: DS.Space.s6) {
            Tile(symbol: permission.symbolName)
            VStack(alignment: .leading, spacing: 0) {
                Text(permission.label)
                    .textStyle(.body.weight(.medium))
                    .foregroundStyle(DS.Colors.text)
                Text(granted ? "Granted" : "Not granted yet")
                    .textStyle(.meta)
                    .foregroundStyle(granted ? DS.Colors.ok : DS.Colors.warn)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if granted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Colors.canvas)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(DS.Colors.ok))
                    .accessibilityHidden(true)
            } else {
                Button("Open Settings") { openSettings(permission) }
                    .buttonStyle(.pill(size: .small))
            }
        }
        .padding(.vertical, DS.Space.s6)
        .padding(.top, DS.Size.hairline)
        .hairline(.top)
    }
}

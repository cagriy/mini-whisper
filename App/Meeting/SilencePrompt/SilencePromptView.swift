import SwiftUI

/// The silence prompt's card (design v7 §5.3, decision 72): the Dialog card with no scrim. It has
/// no close box and no keyboard shortcuts, since its panel never becomes key.
struct SilencePromptView: View {
    let model: SilencePromptModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            HStack(spacing: DS.Space.s4) {
                PulseBars(active: false).foregroundStyle(DS.Colors.recording)
                Text(model.eyebrow)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(model.title)
                .textStyle(.titleDialog)
                .foregroundStyle(DS.Colors.text)
                .accessibilityAddTraits(.isHeader)
            Text("Recording stops in \(countdown) unless you keep it going.")
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            meter
            HStack(spacing: DS.Space.s4) {
                Spacer(minLength: 0)
                Button("Stop now", action: model.stop)
                    .buttonStyle(.pill(tint: DS.Colors.recording))
                Button("Keep recording", action: model.keep)
                    .buttonStyle(.pill(.primary))
            }
            .padding(.top, DS.Space.s3)
        }
        .dialogCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
    }

    private var countdown: Text {
        Text(model.countdownText).fontWeight(.semibold).monospacedDigit().foregroundStyle(DS.Colors.text)
    }

    /// Steps once a second with the countdown, unanimated.
    private var meter: some View {
        Capsule()
            .fill(DS.Colors.hover)
            .frame(height: DS.Space.s2)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(DS.Colors.recording).frame(width: proxy.size.width * model.fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

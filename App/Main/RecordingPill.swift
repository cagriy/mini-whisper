import SwiftUI

/// The sidebar's live meeting, in place of Start Meeting (R3): four bars that pulse while it
/// records, its title and its elapsed time. It returns to the live page.
struct RecordingPill: View {
    let model: MeetingWindowModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s4) {
                PulseBars(active: model.state == .recording).foregroundStyle(DS.Colors.recording)
                Text(model.pillTitle)
                    .textStyle(.body.weight(.medium))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.pillDetail)
                    .textStyle(.body)
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .padding(.horizontal, DS.Space.s6 + DS.Size.hairline)
            .frame(height: 36)
            .background(Capsule().fill(DS.Colors.recordingSoft))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Returns to the live meeting")
        .accessibilityLabel("\(model.pillTitle), \(model.pillDetail)")
    }
}

import SwiftUI

/// A setting's number as it reads, such as `60 s`, beside a pill with − and +. Each press moves
/// the value one step within its range.
struct StepperPill: View {
    /// Names it for assistive technology; the row it sits in names it on screen.
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: String

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            Text(label)
                .textStyle(.body)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textSecondary)
            HStack(spacing: 0) {
                button("minus", by: -step, enabled: value > range.lowerBound)
                Rectangle().fill(DS.Colors.line).frame(width: DS.Size.hairline)
                button("plus", by: step, enabled: value < range.upperBound)
            }
            .frame(height: DS.Size.controlSmall)
            .overlay(Capsule().strokeBorder(DS.Colors.line))
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(by: step)
            case .decrement: change(by: -step)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, by delta: Int, enabled: Bool) -> some View {
        Button { change(by: delta) } label: {
            Image(systemName: symbol)
                .font(DS.TextStyle.label.font)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: 22 + DS.Size.hairline, height: DS.Size.controlSmall)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func change(by delta: Int) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }
}

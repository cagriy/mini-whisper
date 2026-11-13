import SwiftUI

/// The segmented pill switch: one of a few choices, such as a meeting's tabs or the theme.
struct SegmentedPill<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    /// Fills the width on offer, the segments sharing it equally.
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(DS.TextStyle.meta.weight(.medium).font)
                        .lineLimit(1)
                        .foregroundStyle(selected ? DS.Colors.text : DS.Colors.textSecondary)
                        .padding(.horizontal, DS.Space.s6)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .frame(height: DS.Size.controlSmall)
                        .background {
                            if selected {
                                Capsule().fill(DS.Colors.card)
                                Capsule().strokeBorder(DS.Colors.line)
                            }
                        }
                        .contentShape([.interaction, .focusEffect], Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(DS.Space.s1 + DS.Size.hairline)
        .background(Capsule().fill(DS.Colors.sidebar))
        .overlay(Capsule().strokeBorder(DS.Colors.line))
        .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}

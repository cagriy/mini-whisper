import SwiftUI

/// Decision 76: a suggested speaker name in its speaker's colour, with a question mark and a
/// dashed underline, then what the speaker is called until the name is accepted. A click on the
/// name runs `open`.
struct ProvisionalName: View {
    let name: String
    /// "Speaker 2".
    let current: String
    let color: Color
    let open: () -> Void

    private static let underline: CGFloat = 1.5

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            Button(action: open) {
                Text(name + "?")
                    .textStyle(.body.weight(.semibold))
                    .padding(.bottom, DS.Space.s1 / 2)
                    .overlay(alignment: .bottom) {
                        HorizontalRule()
                            .stroke(style: StrokeStyle(lineWidth: Self.underline, dash: [3, 2]))
                            .frame(height: Self.underline)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(color)
            Text(current)
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A line across the middle of its frame, stroked dashed for rules and underlines.
struct HorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

import SwiftUI

/// The settings card: rows on the card surface inside a hairline, under an optional group label.
struct Card<Content: View>: View {
    private let label: String?
    private let content: Content

    init(_ label: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if let label {
                Text(label)
                    .textStyle(.meta.weight(.medium))
                    .foregroundStyle(DS.Colors.textTertiary)
                    .padding(.horizontal, DS.Space.s2)
                    .padding(.top, DS.Space.s4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16 + DS.Size.hairline)
            .padding(.bottom, DS.Size.hairline)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Colors.card))
            // Drawn over the rows, so the first row's hairline lies under the card's top edge.
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.line))
        }
    }
}

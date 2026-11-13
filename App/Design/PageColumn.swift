import SwiftUI

/// A page: a centred, scrolling column that opens with its title in the display serif.
struct PageColumn<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(title)
                    .textStyle(.display)
                    .foregroundStyle(DS.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 40, leading: 32, bottom: 56, trailing: 32))
            .frame(maxWidth: DS.Size.pageColumn)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Colors.canvas)
    }
}

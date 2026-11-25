import SwiftUI

/// A page: a centred, scrolling column that opens with its title in the display serif. A page that
/// keeps its place binds `scrollPosition` to the ids of its scroll targets and names a
/// `coordinateSpace` that spans the visible part of the scroll view, to tell where its parts sit.
struct PageColumn<Content: View, Position: Hashable>: View {
    private let title: String
    private let tracking: (position: Binding<Position?>, space: String)?
    private let content: Content

    init(
        _ title: String, scrollPosition: Binding<Position?>, coordinateSpace: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        tracking = (scrollPosition, coordinateSpace)
        self.content = content()
    }

    var body: some View {
        if let tracking {
            scrollView
                .scrollPosition(id: tracking.position)
                .coordinateSpace(.named(tracking.space))
        } else {
            scrollView
        }
    }

    private var scrollView: some View {
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

extension PageColumn where Position == Never {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        tracking = nil
        self.content = content()
    }
}

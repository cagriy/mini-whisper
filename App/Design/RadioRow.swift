import SwiftUI

/// One choice of a radio list: a ring, filled with the accent when selected, the title with an
/// optional detail line under it, and a figure or an action at the right. The action sits outside
/// the choice, so pressing it never selects the row.
struct RadioRow<Trailing: View>: View {
    enum Detail {
        case plain(String)
        /// What is missing before the choice can be made.
        case warning(String)
    }

    private let title: String
    private let detail: Detail?
    private let selected: Bool
    private let select: () -> Void
    private let trailing: Trailing

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        detail: Detail? = nil,
        selected: Bool,
        select: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.selected = selected
        self.select = select
        self.trailing = trailing()
    }

    init(_ title: String, detail: Detail? = nil, selected: Bool, select: @escaping () -> Void)
        where Trailing == EmptyView {
        self.init(title, detail: detail, selected: selected, select: select) { EmptyView() }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s5) {
            Button(action: select) {
                HStack(alignment: .top, spacing: DS.Space.s5) {
                    Circle()
                        .strokeBorder(selected ? DS.Colors.accent : DS.Colors.textTertiary, lineWidth: selected ? 5 : 1.5)
                        .frame(width: 16, height: 16)
                        .padding(.top, DS.Size.hairline)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(title).textStyle(.body).foregroundStyle(DS.Colors.text)
                        switch detail {
                        case .plain(let text):
                            Text(text).textStyle(.meta).foregroundStyle(DS.Colors.textSecondary)
                        case .warning(let text):
                            Text(text).textStyle(.meta).foregroundStyle(DS.Colors.warn)
                        case nil:
                            EmptyView()
                        }
                    }
                    Spacer(minLength: DS.Space.s6)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            trailing
        }
        .padding(.vertical, DS.Space.s3)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

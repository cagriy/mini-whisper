import SwiftUI

/// A day-grouped row list's group title: `Today`, `Meetings · 2`.
struct DayHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .textStyle(DS.TextStyle.meta.weight(.medium))
            .foregroundStyle(DS.Colors.textTertiary)
            .padding(.horizontal, DS.Space.s6)
            .padding(.top, DS.Space.s5)
            .padding(.bottom, DS.Space.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row of a day-grouped list: a tile, the content and, at the right, a time. It fills while
/// hovered, focused or selected, and tells its content so, which shows its actions then.
struct ListRow<Leading: View, Content: View>: View {
    var time: String?
    var selected = false
    /// A click; Return when the row has focus.
    var activate: (() -> Void)?
    /// A double-click opens; Return too, when the row has no `activate`.
    var open: (() -> Void)?
    @ViewBuilder let tile: () -> Leading
    @ViewBuilder let content: (_ active: Bool) -> Content

    @State private var hovered = false
    @FocusState private var focused: Bool

    private var active: Bool { hovered || focused || selected }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s6) {
            tile()
            content(active).frame(maxWidth: .infinity, alignment: .leading)
            if let time {
                Text(time)
                    .textStyle(.body)
                    .padding(.vertical, DS.Space.s1 / 2)
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        }
        .padding(.vertical, DS.Space.s5)
        .padding(.horizontal, DS.Space.s6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row).fill(active ? DS.Colors.hover : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.row))
        .onHover { hovered = $0 }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard let action = activate ?? open else { return .ignored }
            action()
            return .handled
        }
        .modifier(Taps(activate: activate, open: open))
        .accessibilityElement(children: .contain)
    }
}

/// Only the gestures a row has: a double-click recogniser would delay every single click.
private struct Taps: ViewModifier {
    let activate: (() -> Void)?
    let open: (() -> Void)?

    func body(content: Content) -> some View {
        switch (activate, open) {
        case let (activate?, open?):
            content.onTapGesture(count: 2, perform: open).onTapGesture(perform: activate)
        case let (activate?, nil):
            content.onTapGesture(perform: activate)
        case let (nil, open?):
            content.onTapGesture(count: 2, perform: open)
        case (nil, nil):
            content
        }
    }
}

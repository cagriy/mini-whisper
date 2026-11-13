import SwiftUI

/// The rounded field, for a `TextField`, `SecureField` or `TextEditor`.
struct DSFieldStyle: ViewModifier {
    enum Kind: Equatable {
        /// One line, as tall as a control.
        case line
        /// A text area in the monospaced style, unless the editor sets its own font.
        case area(height: CGFloat = 96)
    }

    var kind = Kind.line

    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        Group {
            switch kind {
            case .line:
                content
                    .font(DS.TextStyle.body.font)
                    .padding(.horizontal, DS.Space.s5 + DS.Size.hairline)
                    .frame(height: DS.Size.control)
            case .area(let height):
                // A text editor already insets its text by 5 points at each side.
                content
                    .font(DS.TextStyle.mono.font)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, DS.Space.s5 + DS.Size.hairline - 5)
                    .padding(.vertical, DS.Space.s4 + DS.Size.hairline)
                    .frame(height: height)
            }
        }
        .textFieldStyle(.plain)
        .foregroundStyle(DS.Colors.text)
        .focused($focused)
        .modifier(FieldChrome(
            shape: RoundedRectangle(cornerRadius: DS.Radius.field), fill: DS.Colors.canvas, focused: focused
        ))
    }
}

extension View {
    func dsField(_ kind: DSFieldStyle.Kind = .line) -> some View {
        modifier(DSFieldStyle(kind: kind))
    }
}

/// The search field: a pill with the magnifier and, at the right, the shortcut that focuses it.
/// Esc empties it.
struct SearchPill: View {
    @Binding var text: String
    /// Its owner focuses it from a shortcut.
    let focused: FocusState<Bool>.Binding
    var prompt = "Search"
    var hint: String?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "magnifyingglass")
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(DS.Colors.textTertiary))
                .textFieldStyle(.plain)
                .foregroundStyle(DS.Colors.text)
                .focused(focused)
                .onExitCommand { text = "" }
            if let hint {
                Text(hint).font(DS.TextStyle.label.weight(.regular).font)
            }
        }
        .font(DS.TextStyle.body.font)
        .foregroundStyle(DS.Colors.textTertiary)
        .padding(.horizontal, DS.Space.s5 + DS.Size.hairline)
        .frame(height: DS.Size.control)
        .modifier(FieldChrome(shape: Capsule(), fill: DS.Colors.card, focused: focused.wrappedValue))
    }
}

/// A field's fill and hairline; focused, an accent border inside a soft ring.
private struct FieldChrome<Outline: InsettableShape>: ViewModifier {
    let shape: Outline
    let fill: Color
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .background {
                // The fill covers the inner half of the stroke, which leaves a 3-point ring.
                if focused {
                    shape.stroke(DS.Colors.accentSoft, lineWidth: 6)
                }
                shape.fill(fill)
            }
            .overlay(shape.strokeBorder(focused ? DS.Colors.accent : DS.Colors.line))
    }
}

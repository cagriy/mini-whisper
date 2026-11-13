import SwiftUI

/// The pill button. A page or dialog has one `primary` button; every other is outlined or quiet.
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        /// Filled with the accent.
        case primary
        /// Outlined.
        case secondary
        /// No outline until hovered.
        case quiet
    }

    enum Size {
        case regular
        case small
    }

    var kind = Kind.secondary
    var size = Size.regular
    /// The label's colour on an accent or destructive row action. A primary button ignores it.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        Pill(style: self, configuration: configuration)
    }

    /// Hover and the enabled state come from the environment, which a style cannot read itself.
    private struct Pill: View {
        let style: PillButtonStyle
        let configuration: Configuration

        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        private var small: Bool { style.size == .small }
        private var lit: Bool { isEnabled && (hovered || configuration.isPressed) }

        private var foreground: Color {
            switch style.kind {
            case .primary: DS.Colors.accentOn
            case .secondary: style.tint ?? DS.Colors.text
            case .quiet: style.tint ?? DS.Colors.textSecondary
            }
        }

        private var font: Font {
            let text = small ? DS.TextStyle.meta : DS.TextStyle.body
            return text.weight(style.kind == .primary ? .semibold : .medium).font
        }

        var body: some View {
            configuration.label
                .labelStyle(PillLabelStyle())
                .font(font)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, (small ? DS.Space.s5 : DS.Space.s7) + DS.Size.hairline)
                .frame(height: small ? DS.Size.controlSmall : DS.Size.control)
                .background {
                    if style.kind == .primary {
                        Capsule().fill(DS.Colors.accent).brightness(lit ? 0.06 : 0)
                    } else if lit {
                        Capsule().fill(DS.Colors.hover)
                    }
                }
                .overlay {
                    if style.kind == .secondary {
                        Capsule().strokeBorder(DS.Colors.line)
                    }
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .contentShape([.interaction, .focusEffect], Capsule())
                .onHover { hovered = $0 }
        }
    }

    private struct PillLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: DS.Space.s3) {
                configuration.icon
                configuration.title
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(
        _ kind: PillButtonStyle.Kind = .secondary, size: PillButtonStyle.Size = .regular, tint: Color? = nil
    ) -> PillButtonStyle {
        PillButtonStyle(kind: kind, size: size, tint: tint)
    }
}

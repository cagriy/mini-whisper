import SwiftUI

/// A small outlined label, with a dot when it reports a state.
struct Chip: View {
    enum Kind {
        case plain
        /// A green dot: capturing.
        case active
        /// A grey dot: paused or ended.
        case inactive
        /// The text and its dot in the warning colour.
        case warning
        /// The filled TEST chip of a test call.
        case test
    }

    private let text: String
    private let kind: Kind

    init(_ text: String, _ kind: Kind = .plain) {
        self.text = text
        self.kind = kind
    }

    private var dot: Color? {
        switch kind {
        case .plain, .test: nil
        case .active: DS.Colors.ok
        case .inactive: DS.Colors.textTertiary
        case .warning: DS.Colors.warn
        }
    }

    private var foreground: Color {
        switch kind {
        case .plain, .active, .inactive: DS.Colors.textSecondary
        case .warning: DS.Colors.warn
        case .test: DS.Colors.testText
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(DS.TextStyle.label.font)
        .lineLimit(1)
        .foregroundStyle(foreground)
        .padding(.horizontal, 9 + DS.Size.hairline)
        .frame(height: 22)
        .background {
            if kind == .test {
                Capsule().fill(DS.Colors.testFill)
            } else {
                Capsule().strokeBorder(DS.Colors.line)
            }
        }
        .fixedSize()
    }
}

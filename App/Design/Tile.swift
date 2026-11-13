import MWMeetings
import SwiftUI

/// A rounded square carrying a symbol or an app's initials.
struct Tile: View {
    private enum Mark {
        case symbol(String)
        case letters(String)
    }

    private let mark: Mark
    private let fill: Color
    private let ink: Color
    private let small: Bool

    /// A symbol in the accent on its soft fill.
    init(symbol: String, small: Bool = false) {
        self.init(.symbol(symbol), DS.Colors.accentSoft, DS.Colors.accent, small)
    }

    /// A meeting: the display for a remote call, people on teal for one in the room.
    init(mode: MeetingMode, small: Bool = false) {
        switch mode {
        case .remote: self.init(symbol: "display", small: small)
        case .inRoom: self.init(.symbol("person.2"), DS.Colors.tealSoft, DS.Colors.teal, small)
        }
    }

    /// An app: its initials on its own colour.
    init(glyph: AppGlyph, small: Bool = false) {
        self.init(.letters(glyph.letters), glyph.color, DS.Colors.white, small)
    }

    private init(_ mark: Mark, _ fill: Color, _ ink: Color, _ small: Bool) {
        self.mark = mark
        self.fill = fill
        self.ink = ink
        self.small = small
    }

    var body: some View {
        let side: CGFloat = small ? 22 : 32
        RoundedRectangle(cornerRadius: small ? DS.Radius.small : DS.Radius.field)
            .fill(fill)
            .frame(width: side, height: side)
            .overlay {
                switch mark {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: small ? 10 : 14, weight: .medium))
                case .letters(let letters):
                    Text(letters).font(small ? .system(size: 10, weight: .semibold) : DS.TextStyle.label.font)
                }
            }
            .foregroundStyle(ink)
            .accessibilityHidden(true)
    }
}

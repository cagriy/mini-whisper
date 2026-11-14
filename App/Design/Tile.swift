import MWMeetings
import SwiftUI

/// A rounded square carrying a symbol, an app's initials or the app's own mark.
struct Tile: View {
    private enum Mark {
        case symbol(String)
        case letters(String)
        case app
    }

    private enum Scale {
        case small, regular, large

        var side: CGFloat {
            switch self {
            case .small: 22
            case .regular: 32
            case .large: 64
            }
        }

        var radius: CGFloat {
            switch self {
            case .small: DS.Radius.small
            case .regular: DS.Radius.field
            case .large: DS.Radius.mark
            }
        }
    }

    private let mark: Mark
    private let fill: Color
    private let ink: Color
    private let scale: Scale

    /// A symbol in the accent on its soft fill.
    init(symbol: String, small: Bool = false) {
        self.init(.symbol(symbol), DS.Colors.accentSoft, DS.Colors.accent, small ? .small : .regular)
    }

    /// A meeting: the display for a remote call, people on teal for one in the room.
    init(mode: MeetingMode, small: Bool = false) {
        switch mode {
        case .remote: self.init(symbol: "display", small: small)
        case .inRoom: self.init(.symbol("person.2"), DS.Colors.tealSoft, DS.Colors.teal, small ? .small : .regular)
        }
    }

    /// An app: its initials on its own colour.
    init(glyph: AppGlyph, small: Bool = false) {
        self.init(.letters(glyph.letters), glyph.color, DS.Colors.white, small ? .small : .regular)
    }

    /// The app's cloud-and-pulse mark, large on the accent, as About shows it.
    static var app: Tile { Tile(.app, DS.Colors.accent, DS.Colors.accentOn, .large) }

    private init(_ mark: Mark, _ fill: Color, _ ink: Color, _ scale: Scale) {
        self.mark = mark
        self.fill = fill
        self.ink = ink
        self.scale = scale
    }

    var body: some View {
        let small = scale == .small
        RoundedRectangle(cornerRadius: scale.radius)
            .fill(fill)
            .frame(width: scale.side, height: scale.side)
            .overlay {
                switch mark {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: small ? 10 : 14, weight: .medium))
                case .letters(let letters):
                    Text(letters).font(small ? .system(size: 10, weight: .semibold) : DS.TextStyle.label.font)
                case .app:
                    CloudPulseMark()
                        .stroke(style: StrokeStyle(lineWidth: 1.47, lineCap: .round, lineJoin: .round))
                        .frame(width: 44, height: 30)
                }
            }
            .foregroundStyle(ink)
            .accessibilityHidden(true)
    }
}

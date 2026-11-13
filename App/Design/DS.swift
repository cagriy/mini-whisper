import AppKit
import SwiftUI

/// The design language recorded in `DESIGN.md`. Its values appear nowhere else in the app.
enum DS {
    /// The palette. Each colour has a light and a dark value and follows the appearance it is drawn in.
    enum Colors {
        static let canvas = Color(light: 0xFBFAF7, dark: 0x262522)
        static let sidebar = Color(light: 0xF2F0EA, dark: 0x1E1D1B)
        static let card = Color(light: 0xFFFFFF, dark: 0x2F2E2A)
        static let hover = Color(light: 0xECE9E2, dark: 0x39372F)
        static let line = Color(light: 0xE1DDD3, dark: 0x46443D)

        static let text = Color(light: 0x23221F, dark: 0xF1EEE7)
        static let textSecondary = Color(light: 0x6B675E, dark: 0xB4AFA4)
        static let textTertiary = Color(light: 0x969084, dark: 0x878278)

        static let accent = Color(light: 0x2A6FC9, dark: 0x7DB8F0)
        static let accentOn = Color(light: 0xFFFFFF, dark: 0x10202F)
        static let accentSoft = Color(light: 0xE3EEFB, dark: 0x2A3948)

        static let recording = Color(light: 0xD2452D, dark: 0xF07A62)
        static let recordingSoft = Color(light: 0xFBE9E5, dark: 0x45261F)
        static let ok = Color(light: 0x2F8A5B, dark: 0x7FC79E)
        static let warn = Color(light: 0xA56A00, dark: 0xE2B45E)
        static let testText = Color(light: 0x7A4FD0, dark: 0xB79CF0)
        static let testFill = Color(light: 0xF1ECFB, dark: 0x3A3150)

        static let teal = Color(light: 0x1A808F, dark: 0x6CC5D1)
        static let tealSoft = Color(light: 0xDDF0F1, dark: 0x1F3B3E)
        static let speaker1 = Color(light: 0x7A4FD0, dark: 0xB79CF0)
        static let speaker2 = Color(light: 0x1A808F, dark: 0x6CC5D1)
        static let speaker3 = Color(light: 0xB3661C, dark: 0xE0A565)

        /// The switch knob and the initials on an app tile, white in both themes.
        static let white = Color(nsColor: NSColor(hex: 0xFFFFFF))
        static let knobShadow = Color(nsColor: NSColor(hex: 0x000000, alpha: 0.25))
        /// Dims the window behind a dialog.
        static let scrim = Color(nsColor: NSColor(hex: 0x141311, alpha: 0.36))
        /// The colour of `shadow.dialog`.
        static let dialogShadow = Color(
            light: NSColor(hex: 0x23221F, alpha: 0.18), dark: NSColor(hex: 0x000000, alpha: 0.45)
        )
    }

    enum Radius {
        /// Small tiles.
        static let small: CGFloat = 6
        /// Fields and tiles.
        static let field: CGFloat = 8
        /// List rows and status lines.
        static let row: CGFloat = 10
        /// Cards and dialogs.
        static let card: CGFloat = 14
    }

    /// `space.1` to `space.10`.
    enum Space {
        static let s1: CGFloat = 2
        static let s2: CGFloat = 4
        static let s3: CGFloat = 6
        static let s4: CGFloat = 8
        static let s5: CGFloat = 10
        static let s6: CGFloat = 12
        static let s7: CGFloat = 14
        static let s8: CGFloat = 18
        static let s9: CGFloat = 24
        static let s10: CGFloat = 28
    }

    enum Size {
        /// A border or divider. The mockups' boxes include it, so padding inside a border adds it.
        static let hairline: CGFloat = 1
        static let control: CGFloat = 30
        static let controlSmall: CGFloat = 24
        /// The widest a page gets, its side padding included.
        static let pageColumn: CGFloat = 736
        /// The widest running text gets.
        static let readingColumn: CGFloat = 640
    }

    /// A type style: its font and the line height `DESIGN.md` gives it.
    struct TextStyle: Hashable, Sendable {
        let size: CGFloat
        let lineHeight: CGFloat
        var weight: Font.Weight = .regular
        var design: Font.Design = .default
        var tracking: CGFloat = 0

        static let display = TextStyle(size: 28, lineHeight: 34, weight: .medium, design: .serif, tracking: -0.28)
        static let title = TextStyle(size: 22, lineHeight: 28, weight: .medium, design: .serif)
        static let titleCompact = TextStyle(size: 20, lineHeight: 26, weight: .medium, design: .serif)
        static let titleDialog = TextStyle(size: 18, lineHeight: 24, weight: .medium, design: .serif)
        static let heading = TextStyle(size: 16, lineHeight: 24, weight: .semibold)
        static let heading2 = TextStyle(size: 15, lineHeight: 22, weight: .semibold)
        static let heading3 = TextStyle(size: 14, lineHeight: 20, weight: .semibold)
        static let reading = TextStyle(size: 15, lineHeight: 24)
        static let rowTitle = TextStyle(size: 14, lineHeight: 20, weight: .medium)
        static let body = TextStyle(size: 13, lineHeight: 18)
        static let meta = TextStyle(size: 12, lineHeight: 16)
        static let mono = TextStyle(size: 12, lineHeight: 18, design: .monospaced)
        /// Chips.
        static let label = TextStyle(size: 11, lineHeight: 14, weight: .semibold)

        var font: Font { .system(size: size, weight: weight, design: design) }

        /// The same font for AppKit text.
        var nsFont: NSFont {
            let weight: NSFont.Weight = switch self.weight {
            case .medium: .medium
            case .semibold: .semibold
            default: .regular
            }
            let design: NSFontDescriptor.SystemDesign = switch self.design {
            case .serif: .serif
            case .monospaced: .monospaced
            default: .default
            }
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            return font.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        }

        /// The style at another weight: a button label is `body` at medium.
        func weight(_ weight: Font.Weight) -> TextStyle {
            var style = self
            style.weight = weight
            return style
        }

        /// What `lineHeight` adds to the height the font gives a line. Kept per style: every
        /// styled text asks for it each time its view is evaluated.
        @MainActor fileprivate var leading: CGFloat {
            if let known = Self.leadings[self] { return known }
            let font = nsFont
            let leading = max(0, lineHeight - (font.ascender - font.descender + font.leading).rounded(.up))
            Self.leadings[self] = leading
            return leading
        }

        @MainActor private static var leadings: [TextStyle: CGFloat] = [:]
    }
}

extension View {
    /// The style's font, each line as tall as the style's line height, as the mockups' CSS lays text out.
    func textStyle(_ style: DS.TextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.leading)
            .padding(.vertical, style.leading / 2)
    }

    /// `shadow.dialog`: dialogs and menus only.
    func dialogShadow() -> some View {
        shadow(color: DS.Colors.dialogShadow, radius: 18, y: 14)
    }
}

extension Color {
    /// The colour for AppKit text. A palette colour keeps both of its values.
    var nsColor: NSColor { NSColor(self) }

    fileprivate init(light: UInt32, dark: UInt32) {
        self.init(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }

    fileprivate init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
            green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

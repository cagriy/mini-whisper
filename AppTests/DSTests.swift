import AppKit
import SwiftUI
import Testing
@testable import MiniWhisper

/// The `DS` tokens against the values `DESIGN.md` records.
@Suite struct DSTests {
    struct Token: Sendable, CustomTestStringConvertible {
        let name: String
        let color: Color
        let light: String
        let dark: String

        var testDescription: String { name }
    }

    static let palette = [
        Token(name: "canvas", color: DS.Colors.canvas, light: "#FBFAF7", dark: "#262522"),
        Token(name: "sidebar", color: DS.Colors.sidebar, light: "#F2F0EA", dark: "#1E1D1B"),
        Token(name: "card", color: DS.Colors.card, light: "#FFFFFF", dark: "#2F2E2A"),
        Token(name: "hover", color: DS.Colors.hover, light: "#ECE9E2", dark: "#39372F"),
        Token(name: "line", color: DS.Colors.line, light: "#E1DDD3", dark: "#46443D"),
        Token(name: "text", color: DS.Colors.text, light: "#23221F", dark: "#F1EEE7"),
        Token(name: "text.secondary", color: DS.Colors.textSecondary, light: "#6B675E", dark: "#B4AFA4"),
        Token(name: "text.tertiary", color: DS.Colors.textTertiary, light: "#969084", dark: "#878278"),
        Token(name: "accent", color: DS.Colors.accent, light: "#2A6FC9", dark: "#7DB8F0"),
        Token(name: "accent.on", color: DS.Colors.accentOn, light: "#FFFFFF", dark: "#10202F"),
        Token(name: "accent.soft", color: DS.Colors.accentSoft, light: "#E3EEFB", dark: "#2A3948"),
        Token(name: "recording", color: DS.Colors.recording, light: "#D2452D", dark: "#F07A62"),
        Token(name: "recording.soft", color: DS.Colors.recordingSoft, light: "#FBE9E5", dark: "#45261F"),
        Token(name: "ok", color: DS.Colors.ok, light: "#2F8A5B", dark: "#7FC79E"),
        Token(name: "warn", color: DS.Colors.warn, light: "#A56A00", dark: "#E2B45E"),
        Token(name: "teal", color: DS.Colors.teal, light: "#1A808F", dark: "#6CC5D1"),
        Token(name: "teal.soft", color: DS.Colors.tealSoft, light: "#DDF0F1", dark: "#1F3B3E"),
        Token(name: "test.text", color: DS.Colors.testText, light: "#7A4FD0", dark: "#B79CF0"),
        Token(name: "test.fill", color: DS.Colors.testFill, light: "#F1ECFB", dark: "#3A3150"),
        Token(name: "speaker.1", color: DS.Colors.speaker1, light: "#7A4FD0", dark: "#B79CF0"),
        Token(name: "speaker.2", color: DS.Colors.speaker2, light: "#1A808F", dark: "#6CC5D1"),
        Token(name: "speaker.3", color: DS.Colors.speaker3, light: "#B3661C", dark: "#E0A565"),
    ]

    @Test(arguments: palette) func colourResolvesToItsLightAndDarkValue(_ token: Token) throws {
        let light = try Self.hex(token.color.nsColor, in: .aqua)
        let dark = try Self.hex(token.color.nsColor, in: .darkAqua)

        #expect(light == token.light)
        #expect(dark == token.dark)
    }

    @Test func radiiMatchDesignMD() {
        #expect(DS.Radius.field == 8)
        #expect(DS.Radius.row == 10)
        #expect(DS.Radius.card == 14)
    }

    @Test func typeScaleMatchesDesignMD() {
        let styles: [DS.TextStyle] = [
            .display, .title, .titleCompact, .titleDialog, .heading, .heading2, .heading3, .reading, .rowTitle, .body,
            .meta, .mono,
        ]

        #expect(styles.map(\.size) == [28, 22, 20, 18, 16, 15, 14, 15, 14, 13, 12, 12])
        #expect(styles.map(\.lineHeight) == [34, 28, 26, 24, 24, 22, 20, 24, 20, 18, 16, 18])
        #expect(styles.map(\.weight) == [
            .medium, .medium, .medium, .medium, .semibold, .semibold, .semibold, .regular, .medium, .regular, .regular,
            .regular,
        ])
        #expect(styles.map(\.design) == [
            .serif, .serif, .serif, .serif, .default, .default, .default, .default, .default, .default, .default,
            .monospaced,
        ])
    }

    @Test func appGlyphPaletteIsUnchanged() {
        #expect(AppGlyph.palette == [
            Color(red: 0.23, green: 0.44, blue: 0.85),
            Color(red: 0.29, green: 0.62, blue: 0.36),
            Color(red: 0.85, green: 0.44, blue: 0.20),
            Color(red: 0.62, green: 0.30, blue: 0.68),
            Color(red: 0.80, green: 0.28, blue: 0.36),
            Color(red: 0.16, green: 0.53, blue: 0.60),
            Color(red: 0.45, green: 0.42, blue: 0.72),
            Color(red: 0.36, green: 0.36, blue: 0.40),
        ])
    }

    /// The colour as `#RRGGBB` in sRGB, as the named appearance draws it.
    private static func hex(_ color: NSColor, in appearance: NSAppearance.Name) throws -> String {
        var resolved: NSColor?
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        let srgb = try #require(resolved)
        let bytes = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

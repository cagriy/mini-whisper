import SwiftUI

/// The rounded app tile of a History row (design §5.4): initials taken from the app
/// name and a colour hashed from the bundle ID, so one app always looks the same.
struct AppGlyph: Equatable, Sendable {
    let letters: String
    let colorIndex: Int

    init(appName: String, bundleID: String?) {
        letters = Self.letters(for: appName)
        colorIndex = Self.index(for: bundleID ?? appName)
    }

    var color: Color { Self.palette[colorIndex] }

    static let palette: [Color] = [
        Color(red: 0.23, green: 0.44, blue: 0.85),
        Color(red: 0.29, green: 0.62, blue: 0.36),
        Color(red: 0.85, green: 0.44, blue: 0.20),
        Color(red: 0.62, green: 0.30, blue: 0.68),
        Color(red: 0.80, green: 0.28, blue: 0.36),
        Color(red: 0.16, green: 0.53, blue: 0.60),
        Color(red: 0.45, green: 0.42, blue: 0.72),
        Color(red: 0.36, green: 0.36, blue: 0.40),
    ]

    /// The capitals of the name, at most two — “VS Code” → `VS`, “Slack” → `S` —
    /// falling back to the first letter or digit of an all-lowercase name.
    private static func letters(for appName: String) -> String {
        let capitals = appName.filter(\.isUppercase)
        if !capitals.isEmpty { return String(capitals.prefix(2)) }
        guard let first = appName.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }

    /// FNV-1a: `hashValue` is seeded per process, and the colour has to survive a relaunch.
    private static func index(for key: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Int(hash % UInt32(palette.count))
    }
}

/// Appearance of the app's windows, stored in `config.json` under `theme`. An absent or
/// unrecognised value resolves to `system`.
public enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// The main window's frame in screen points, stored in `config.json` under
/// `main_window_frame`.
public struct WindowFrame: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The file is user-writable and the numbers end up in AppKit, so a non-finite one
    /// is refused here rather than left to the decoder's settings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Non-finite window frame")
            )
        }
    }
}

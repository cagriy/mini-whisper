import Foundation

public struct CaptionLine: Sendable, Equatable {
    public var text: String
    public var alpha: Double

    public init(text: String, alpha: Double) {
        self.text = text
        self.alpha = alpha
    }
}

/// The caption bar's line composition, a port of `wrap_caption`, `caption_lines` and
/// `with_unavailable` in `overlay.py`. `measure` returns the rendered width of a candidate
/// line, so wrapping is measured rather than estimated without pulling AppKit in here.
public struct CaptionModel {
    public static let usableWidth = Constants.captionWidth - 2 * Constants.captionPaddingH

    /// The rows to draw: the last seven wrapped lines, newest last, older ones dimmer.
    public static func lines(
        text: String,
        dimmed: Bool,
        measure: (String) -> Double
    ) -> [CaptionLine] {
        let currentAlpha = dimmed ? Constants.captionDimmedAlpha : Constants.captionCurrentAlpha
        let olderAlpha = dimmed ? Constants.captionDimmedOlderAlpha : Constants.captionOlderAlpha
        var wrapped = Array(wrap(text, measure: measure).suffix(Constants.captionMaxLines))
        if wrapped.isEmpty { wrapped = [""] }
        return wrapped.enumerated().map { index, line in
            CaptionLine(text: line, alpha: index == wrapped.count - 1 ? currentAlpha : olderAlpha)
        }
    }

    /// F21: the notice joins the transcript already on screen, never twice.
    public static func withUnavailable(_ lines: [CaptionLine]) -> [CaptionLine] {
        let warning = CaptionLine(
            text: Constants.captionUnavailableText, alpha: Constants.captionCurrentAlpha
        )
        if lines.last?.text == Constants.captionUnavailableText { return lines }
        let kept = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array((kept + [warning]).suffix(Constants.captionMaxLines))
    }

    /// Word wrap against the bar's usable width; a word wider than the line stands alone.
    public static func wrap(_ text: String, measure: (String) -> Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            if measure(candidate) <= usableWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

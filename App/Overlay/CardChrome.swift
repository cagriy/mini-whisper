import AppKit
import CoreText
import MWOverlaySim

/// The card every overlay style shares: the rounded background, the bottom-right label and
/// the centred error message (design §5.5). Lifted out of `ConstellationLayer` unchanged,
/// so a new style cannot drift from the shipped chrome. `alpha` is the card's own fade;
/// each piece applies its own weight on top.
enum CardChrome {
    static func drawCard(in context: CGContext, rect: CGRect, alpha: Double) {
        context.setFillColor(gray: 0, alpha: Constants.backgroundAlpha * alpha)
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: Constants.backgroundCornerRadius,
            cornerHeight: Constants.backgroundCornerRadius,
            transform: nil
        ))
        context.fillPath()
    }

    /// Bottom-right, 12 pt in from the edge and 10 pt up, as `overlay.py` draws it.
    static func drawLabel(
        in context: CGContext,
        rect: CGRect,
        text: String,
        alpha: Double,
        font: NSFont
    ) {
        guard !text.isEmpty else { return }
        let line = CTLineCreateWithAttributedString(
            attributed(text, font: font, alpha: Constants.dotAlpha * alpha)
        )
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: rect.maxX - width - 12, y: rect.minY + 10)
        CTLineDraw(line, context)
    }

    static func drawError(
        in context: CGContext,
        rect: CGRect,
        text: String,
        alpha: Double,
        font: NSFont
    ) {
        let margin = 20.0
        let attributed = attributed(text, font: font, alpha: alpha, centred: true)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let width = rect.width - 2 * margin
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: rect.height),
            nil
        )
        // The source's geometry: centred, nudged 30 pt down, with 20 pt of slack.
        let box = CGRect(
            x: rect.minX + margin,
            y: (rect.height - size.height) / 2 - 30,
            width: width,
            height: size.height + 20
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            CGPath(rect: box, transform: nil),
            nil
        )
        CTFrameDraw(frame, context)
    }

    private static func attributed(
        _ string: String,
        font: NSFont,
        alpha: Double,
        centred: Bool = false
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        if centred {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            attributes[.paragraphStyle] = style
        }
        return NSAttributedString(string: string, attributes: attributes)
    }
}

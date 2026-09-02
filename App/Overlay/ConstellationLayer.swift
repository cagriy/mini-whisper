import AppKit
import CoreText
import MWOverlaySim
import QuartzCore

/// Draws one `Frame` with CoreGraphics. The frame's contents are copied into arrays
/// allocated once, so a 60 fps redraw allocates no buffers (design §5.6, N1).
final class ConstellationLayer: CALayer {
    private var dots = [DotState](repeating: DotState(), count: Constants.dotCount)
    private var links = [Link](repeating: Link(), count: Constants.maxLinks)
    private var linkCount = 0
    private var cardAlpha = 0.0
    private var offsetX = 0.0
    private var label = ""
    private var errorText = ""
    private var dotsVisible = true

    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let errorFont = NSFont.systemFont(ofSize: 14, weight: .medium)

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unused")
    }

    /// No implicit animation may run between frames (design §5.6).
    override func action(forKey event: String) -> (any CAAction)? { nil }

    func update(_ frame: Frame) {
        for index in dots.indices { dots[index] = frame.dots[index] }
        linkCount = min(frame.linkCount, links.count)
        for index in 0..<linkCount { links[index] = frame.links[index] }
        cardAlpha = frame.cardAlpha
        offsetX = frame.offsetX
        label = frame.label
        errorText = frame.errorText
        dotsVisible = frame.dotsVisible
        setNeedsDisplay()
    }

    /// The addresses the render test asserts stay put across draws.
    var dotStorageIdentity: UnsafeRawPointer? {
        dots.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    var linkStorageIdentity: UnsafeRawPointer? {
        links.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    override func draw(in context: CGContext) {
        guard cardAlpha > 0 else { return }
        let side = Constants.windowSize
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: offsetX, y: 0)

        let card = CGRect(x: 0, y: 0, width: side, height: side)
        context.setFillColor(gray: 0, alpha: Constants.backgroundAlpha * cardAlpha)
        context.addPath(CGPath(
            roundedRect: card,
            cornerWidth: Constants.backgroundCornerRadius,
            cornerHeight: Constants.backgroundCornerRadius,
            transform: nil
        ))
        context.fillPath()

        if dotsVisible {
            drawLinks(in: context)
            drawDots(in: context)
            drawLabel(in: context, rect: card)
        } else if !errorText.isEmpty {
            drawError(in: context, rect: card)
        }
    }

    private func drawLinks(in context: CGContext) {
        guard linkCount > 0 else { return }
        context.setLineWidth(1)
        for index in 0..<linkCount {
            let link = links[index]
            context.setStrokeColor(gray: 1, alpha: link.alpha * cardAlpha)
            context.move(to: CGPoint(x: dots[link.a].x, y: dots[link.a].y))
            context.addLine(to: CGPoint(x: dots[link.b].x, y: dots[link.b].y))
            context.strokePath()
        }
    }

    private func drawDots(in context: CGContext) {
        context.setFillColor(gray: 1, alpha: Constants.dotAlpha * cardAlpha)
        for dot in dots {
            context.addEllipse(in: CGRect(
                x: dot.x - dot.radius,
                y: dot.y - dot.radius,
                width: dot.radius * 2,
                height: dot.radius * 2
            ))
        }
        context.fillPath()
    }

    /// Bottom-right, 12 pt in from the edge and 10 pt up, as `overlay.py` draws it.
    private func drawLabel(in context: CGContext, rect: CGRect) {
        guard !label.isEmpty else { return }
        let line = CTLineCreateWithAttributedString(
            attributed(label, font: labelFont, alpha: Constants.dotAlpha)
        )
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: rect.maxX - width - 12, y: rect.minY + 10)
        CTLineDraw(line, context)
    }

    private func drawError(in context: CGContext, rect: CGRect) {
        let margin = 20.0
        let text = attributed(errorText, font: errorFont, alpha: 1, centred: true)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
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

    private func attributed(
        _ string: String,
        font: NSFont,
        alpha: Double,
        centred: Bool = false
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha * cardAlpha),
        ]
        if centred {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            attributes[.paragraphStyle] = style
        }
        return NSAttributedString(string: string, attributes: attributes)
    }
}

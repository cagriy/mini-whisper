import AppKit
import MWOverlaySim
import QuartzCore

/// Draws one `StyleFrame` with CoreGraphics, transcribed from the animation-studies
/// mockup's `draw` (design §5.5). The frame's marks are copied into a buffer allocated
/// once and the pearl's gradient is built once, so a redraw allocates nothing (R17).
final class StyleLayer: CALayer {
    /// `style` is taken by `CALayer` itself, so the chosen animation lives here.
    private let overlayStyle: OverlayStyle
    private var points = [StylePoint](repeating: StylePoint(), count: Constants.stylePointCapacity)
    private var count = 0
    private var glowX = 0.0
    private var cardAlpha = 0.0
    private var offsetX = 0.0
    private var label = ""
    private var errorText = ""
    private var contentVisible = true
    private var checkProgress = 0.0
    private var phase = StylePhase.quiet

    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let errorFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    private let pearlGlow: CGGradient

    init(style: OverlayStyle) {
        overlayStyle = style
        pearlGlow = Self.makePearlGlow()
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        let source = layer as? StyleLayer
        overlayStyle = source?.overlayStyle ?? .default
        pearlGlow = source?.pearlGlow ?? Self.makePearlGlow()
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unused")
    }

    /// No implicit animation may run between frames (design §5.6).
    override func action(forKey event: String) -> (any CAAction)? { nil }

    func update(_ frame: StyleFrame) {
        count = min(frame.geometry.count, points.count)
        for index in 0..<count { points[index] = frame.geometry.points[index] }
        glowX = frame.geometry.glowX
        cardAlpha = frame.cardAlpha
        offsetX = frame.offsetX
        label = frame.label
        errorText = frame.errorText
        contentVisible = frame.contentVisible
        checkProgress = frame.checkProgress
        phase = frame.phase
        setNeedsDisplay()
    }

    /// The address the render test asserts stays put across draws.
    var pointStorageIdentity: UnsafeRawPointer? {
        points.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    override func draw(in context: CGContext) {
        guard cardAlpha > 0 else { return }
        let side = Constants.windowSize
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: offsetX, y: 0)

        let card = CGRect(x: 0, y: 0, width: side, height: side)
        CardChrome.drawCard(in: context, rect: card, alpha: cardAlpha)

        if contentVisible {
            // The sampler works in the mockup's y-down card space; the label does not, so
            // the flip is scoped to the marks alone.
            context.saveGState()
            context.translateBy(x: 0, y: side)
            context.scaleBy(x: 1, y: -1)
            drawMarks(in: context)
            context.restoreGState()

            CardChrome.drawLabel(
                in: context, rect: card, text: label, alpha: cardAlpha, font: labelFont
            )
        } else if !errorText.isEmpty {
            CardChrome.drawError(
                in: context, rect: card, text: errorText, alpha: cardAlpha, font: errorFont
            )
        }
    }

    private func drawMarks(in context: CGContext) {
        if phase == .done {
            drawCheck(in: context)
            return
        }
        guard count > 0 else { return }
        switch overlayStyle {
        case .silkRibbon: drawRuns(in: context, run: 120, width: 1.2)
        case .resonantHalo: drawRuns(in: context, run: 180, width: 1)
        case .petalIris: drawRuns(in: context, run: 80, width: 1)
        case .softMeter: drawMeter(in: context)
        case .liquidPearl: drawPearl(in: context)
        case .constellation: break
        }
    }

    /// The mockup's completion tick, drawn in place of the marks.
    private func drawCheck(in context: CGContext) {
        setMarkStroke(in: context, alpha: 0.9 * checkProgress)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 139, y: 140))
        context.addLine(to: CGPoint(x: 147, y: 148))
        context.addLine(to: CGPoint(x: 163, y: 130))
        context.strokePath()
    }

    /// Polylines in fixed-length runs, each segment carrying its end point's alpha.
    private func drawRuns(in context: CGContext, run: Int, width: Double) {
        context.setLineWidth(width)
        context.setLineCap(.round)
        var start = 0
        while start < count {
            let end = min(start + run, count)
            for index in (start + 1)..<end {
                setMarkStroke(in: context, alpha: points[index].alpha)
                context.move(to: CGPoint(x: points[index - 1].x, y: points[index - 1].y))
                context.addLine(to: CGPoint(x: points[index].x, y: points[index].y))
                context.strokePath()
            }
            start = end
        }
    }

    private func drawMeter(in context: CGContext) {
        context.setLineWidth(5)
        context.setLineCap(.round)
        for index in 0..<count {
            let point = points[index]
            setMarkStroke(in: context, alpha: point.alpha)
            context.move(to: CGPoint(x: point.x, y: point.y - point.height / 2))
            context.addLine(to: CGPoint(x: point.x, y: point.y + point.height / 2))
            context.strokePath()
        }
    }

    private func drawPearl(in context: CGContext) {
        context.saveGState()
        context.setAlpha(cardAlpha)
        addPearlOutline(to: context)
        context.clip()
        context.drawRadialGradient(
            pearlGlow,
            startCenter: CGPoint(x: glowX, y: 126),
            startRadius: 3,
            endCenter: CGPoint(x: 150, y: 140),
            endRadius: 76,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()

        addPearlOutline(to: context)
        context.setStrokeColor(gray: 1, alpha: 0.45 * cardAlpha)
        context.setLineWidth(0.8)
        context.strokePath()
    }

    private func addPearlOutline(to context: CGContext) {
        context.beginPath()
        context.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for index in 1..<count {
            context.addLine(to: CGPoint(x: points[index].x, y: points[index].y))
        }
        context.closePath()
    }

    private func setMarkStroke(in context: CGContext, alpha: Double) {
        let white = Constants.styleMarkWhite
        context.setStrokeColor(
            red: white.red, green: white.green, blue: white.blue, alpha: alpha * cardAlpha
        )
    }

    /// The mockup's `createRadialGradient` stops. Only its centres move per frame, and
    /// those are arguments to `drawRadialGradient`, so one gradient lasts the layer.
    private static func makePearlGlow() -> CGGradient {
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
                CGColor(red: 235 / 255, green: 243 / 255, blue: 255 / 255, alpha: 0.65),
                CGColor(red: 205 / 255, green: 225 / 255, blue: 250 / 255, alpha: 0.05),
            ] as CFArray,
            locations: [0, 0.45, 1]
        )!
    }
}

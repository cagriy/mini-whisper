import AppKit
import MWOverlaySim
import QuartzCore

/// The caption bar's layers: a rounded background, seven text rows and the blinking
/// cursor (§5.6). Only a text change touches them — there is no per-frame work.
@MainActor
final class CaptionLayerStack {
    private static let cursorAnimationKey = "blink"

    private let background = CALayer()
    private var rows: [CATextLayer] = []
    private let cursor = CATextLayer()
    private let font = NSFont.systemFont(ofSize: Constants.captionFontSize)
    private var lastLineText = ""

    var layer: CALayer { background }

    init(size: CGSize) {
        background.frame = CGRect(origin: .zero, size: size)
        background.backgroundColor = CGColor(gray: 0, alpha: Constants.captionBackgroundAlpha)
        background.cornerRadius = Constants.captionCornerRadius
        background.masksToBounds = true

        for index in 0..<Constants.captionMaxLines {
            let row = CATextLayer()
            row.frame = Self.rowFrame(index: index, size: size)
            row.font = font
            row.fontSize = Constants.captionFontSize
            row.foregroundColor = CGColor(gray: 1, alpha: 1)
            row.alignmentMode = .left
            row.isWrapped = false
            row.truncationMode = .none
            row.actions = ["contents": NSNull(), "opacity": NSNull(), "position": NSNull()]
            background.addSublayer(row)
            rows.append(row)
        }

        cursor.string = Constants.captionCursor
        cursor.font = font
        cursor.fontSize = Constants.captionFontSize
        cursor.foregroundColor = CGColor(gray: 1, alpha: 1)
        // Without this the caret animates to each new position over CA's default
        // quarter second, lagging visibly behind the text it follows.
        cursor.actions = [
            "position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "hidden": NSNull(),
        ]
        cursor.isHidden = true
        background.addSublayer(cursor)
    }

    func setContentsScale(_ scale: CGFloat) {
        background.contentsScale = scale
        for row in rows { row.contentsScale = scale }
        cursor.contentsScale = scale
    }

    func measure(_ text: String) -> Double {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    func set(_ lines: [CaptionLine], showCursor: Bool) {
        // Rows are bottom-aligned: the newest line is always the last one drawn.
        let offset = Constants.captionMaxLines - lines.count
        for (index, row) in rows.enumerated() {
            let line = index >= offset ? lines[index - offset] : nil
            row.string = line?.text ?? ""
            row.opacity = Float(line?.alpha ?? 0)
        }

        if let last = lines.last {
            // Only a genuinely new bottom line animates in. A live partial extends the
            // current line word by word, and animating each change replayed the fade on
            // every word, which read as flicker.
            if CaptionModel.isNewLine(previous: lastLineText, current: last.text) {
                animateNewLine(rows[Constants.captionMaxLines - 1], alpha: last.alpha)
            }
            lastLineText = last.text
        }
        positionCursor(after: lines.last, visible: showCursor)
    }

    func reset() {
        lastLineText = ""
        for row in rows {
            row.string = ""
            row.opacity = 0
        }
        cursor.isHidden = true
        cursor.removeAnimation(forKey: Self.cursorAnimationKey)
    }

    private func animateNewLine(_ row: CATextLayer, alpha: Double) {
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = -8
        slide.toValue = 0
        slide.duration = Constants.cardFadeSeconds
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = Float(alpha)
        fade.duration = Constants.cardFadeSeconds
        row.add(slide, forKey: "slide")
        row.add(fade, forKey: "fade")
    }

    private func positionCursor(after line: CaptionLine?, visible: Bool) {
        guard visible, let line else {
            cursor.isHidden = true
            cursor.removeAnimation(forKey: Self.cursorAnimationKey)
            return
        }
        let width = measure(Constants.captionCursor)
        cursor.frame = CGRect(
            x: Constants.captionPaddingH + measure(line.text) + 2,
            y: Self.rowFrame(index: Constants.captionMaxLines - 1, size: background.bounds.size).minY,
            width: width,
            height: Constants.captionLineHeight
        )
        cursor.isHidden = false
        guard cursor.animation(forKey: Self.cursorAnimationKey) == nil else { return }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0]
        blink.keyTimes = [0, 0.5]
        blink.calculationMode = .discrete
        blink.duration = Constants.captionBlinkSeconds
        blink.repeatCount = .greatestFiniteMagnitude
        cursor.add(blink, forKey: Self.cursorAnimationKey)
    }

    private static func rowFrame(index: Int, size: CGSize) -> CGRect {
        CGRect(
            x: Constants.captionPaddingH,
            y: size.height - Constants.captionPaddingV - Double(index + 1) * Constants.captionLineHeight,
            width: size.width - 2 * Constants.captionPaddingH,
            height: Constants.captionLineHeight
        )
    }
}

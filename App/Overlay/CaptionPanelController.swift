import AppKit
import MWOverlaySim

/// The caption bar under the card: live partials, the dimmed processing state, the
/// engine notice and F21's unavailable warning (§5.6).
@MainActor
final class CaptionPanelController {
    private let panel: OverlayPanel
    private let stack: CaptionLayerStack

    private var text = ""
    private var partial = false
    private var dimmed = false
    private var unavailable = false
    private var notice: String?

    init() {
        let size = CGSize(width: Constants.captionWidth, height: Constants.captionHeight)
        panel = OverlayPanel(size: size)
        stack = CaptionLayerStack(size: size)
        panel.hostLayer?.addSublayer(stack.layer)
    }

    /// Called with every card placement so the bar is already on the right display
    /// when its first line arrives (F37).
    func prepare(card: CGRect) {
        panel.setFrame(DisplayPlacement.captionFrame(card: card), display: false)
        stack.setContentsScale(panel.screen?.backingScaleFactor ?? 2)
        text = ""
        partial = false
        dimmed = false
        unavailable = false
        notice = nil
        stack.reset()
    }

    func setText(_ text: String, partial: Bool, dimmed: Bool) {
        self.text = text
        self.partial = partial
        self.dimmed = dimmed
        render()
    }

    func showUnavailable() {
        unavailable = true
        render()
    }

    func showNotice(_ message: String) {
        notice = message
        render()
    }

    func hide() {
        panel.orderOut(nil)
        stack.reset()
    }

    private func render() {
        var lines = CaptionModel.lines(text: text, dimmed: dimmed, measure: stack.measure)
        if unavailable {
            lines = CaptionModel.withUnavailable(lines)
        }
        if let notice {
            lines = Self.appending(notice, to: lines)
        }
        stack.set(lines, showCursor: partial && !dimmed)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// F23's one-line engine notice, kept on screen alongside whatever is transcribed.
    private static func appending(_ message: String, to lines: [CaptionLine]) -> [CaptionLine] {
        guard lines.last?.text != message else { return lines }
        let kept = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let notice = CaptionLine(text: message, alpha: Constants.captionCurrentAlpha)
        return Array((kept + [notice]).suffix(Constants.captionMaxLines))
    }
}

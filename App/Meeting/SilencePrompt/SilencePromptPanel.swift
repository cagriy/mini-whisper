import AppKit
import SwiftUI

/// Design v7 R8: the silence prompt's panel. Borderless, non-activating and floating on every
/// Space, full-screen ones included; it never becomes key, so typing stays in the call. Clear
/// and shadowless: the card draws its own `shadow.dialog` inside `shadowPadding`.
class SilencePromptPanel: NSPanel {
    /// Room for `shadow.dialog`'s blur and offset around the card.
    static let shadowPadding: CGFloat = 40

    init(model: SilencePromptModel) {
        let host = FirstMouseHostingView(rootView: SilencePromptView(model: model).padding(Self.shadowPadding))
        super.init(
            contentRect: CGRect(origin: DisplayPlacement.offscreenOrigin, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The card's laid-out size, without the shadow padding.
    var cardSize: CGSize {
        guard let host = contentView else { return .zero }
        // Read before SwiftUI's first layout, the fitting size can be zero.
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        return CGSize(width: fitting.width - 2 * Self.shadowPadding, height: fitting.height - 2 * Self.shadowPadding)
    }
}

/// A panel that is never key would otherwise spend the first click on focusing it, so Keep
/// recording would seem to do nothing.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

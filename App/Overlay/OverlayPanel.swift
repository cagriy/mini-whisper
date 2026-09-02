import AppKit

/// The panel both overlays use (§5.6): borderless, non-activating, floating, clear,
/// shadowless, click-through, on every space, and never hidden when the app deactivates.
final class OverlayPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: DisplayPlacement.offscreenOrigin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.isOpaque = false
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var hostLayer: CALayer? { contentView?.layer }
}

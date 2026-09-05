import CoreGraphics
import MWPipeline

/// Main-actor fan-out of `DictationController.uiEvents` to the menu bar and the two
/// overlay panels (design §5.5, §5.6).
@MainActor
final class UIEventRouter {
    private let statusItem: StatusItemController
    private let overlay: OverlayPanelController
    private let caption: CaptionPanelController
    private let placement: DisplayPlacement
    private let frontmost: any FrontmostAppProviding
    private var task: Task<Void, Never>?

    init(
        statusItem: StatusItemController,
        overlay: OverlayPanelController,
        caption: CaptionPanelController,
        placement: DisplayPlacement,
        frontmost: any FrontmostAppProviding
    ) {
        self.statusItem = statusItem
        self.overlay = overlay
        self.caption = caption
        self.placement = placement
        self.frontmost = frontmost
    }

    func start(_ events: AsyncStream<UIEvent>) {
        task = Task { [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        overlay.hide()
        caption.hide()
    }

    /// F14's error. A card already on screen shakes in place rather than restarting
    /// its show choreography.
    func show(error message: String) {
        if !overlay.isVisible { present() }
        overlay.set(mode: .error(message))
        caption.hide()
    }

    private func apply(_ event: UIEvent) {
        switch event {
        case .starting:
            present()
        case .recording:
            overlay.set(mode: .recording)
        case .level(let rms):
            overlay.setLevel(rms)
        case .caption(let text, let partial, let dimmed):
            caption.setText(text, partial: partial, dimmed: dimmed)
        case .captionUnavailable:
            caption.showUnavailable()
        case .captionNotice(let message):
            caption.showNotice(message)
        case .processing:
            overlay.set(mode: .processing)
        case .result(let dictation):
            statusItem.setLast(dictation)
            overlay.set(mode: .result)
            caption.hide()
        case .error(let message):
            show(error: message)
        case .idle:
            overlay.hide()
            caption.hide()
        case .usage(let today, let month):
            statusItem.setUsage(today: today, month: month)
        }
    }

    /// F37: the display is resolved from the frontmost app at every show.
    private func present() {
        let screen = placement.screenFrame(forPID: frontmost.frontmost()?.pid)
        overlay.show(on: screen)
        caption.prepare(card: DisplayPlacement.cardFrame(on: screen))
    }
}

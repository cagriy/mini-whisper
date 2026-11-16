import AppKit

/// Design v7 §5.3: what the meeting coordinator drives with a meeting's `.silence` events.
@MainActor
protocol SilencePrompting: AnyObject {
    /// Opens the prompt, or updates it in place when it is already open.
    func show(
        meetingTitle: String, minutes: Int, secondsLeft: Int,
        keep: @escaping @MainActor () -> Void, stop: @escaping @MainActor () -> Void
    )
    func hide()
}

/// Places the silence prompt on the display `screen` picks each time it opens, and keeps it
/// there until it is hidden. The panel is made on the first prompt and reused (§5.8).
@MainActor
final class SilencePromptController: SilencePrompting {
    let model = SilencePromptModel()

    private let screen: @MainActor () -> CGRect
    private let announce: @MainActor (String) -> Void
    private let makePanel: @MainActor (SilencePromptModel) -> SilencePromptPanel
    private var panel: SilencePromptPanel?
    private var isShown = false

    init(
        screen: @escaping @MainActor () -> CGRect,
        announce: @escaping @MainActor (String) -> Void = SilencePromptController.postAnnouncement,
        makePanel: @escaping @MainActor (SilencePromptModel) -> SilencePromptPanel = SilencePromptPanel.init(model:)
    ) {
        self.screen = screen
        self.announce = announce
        self.makePanel = makePanel
    }

    func show(
        meetingTitle: String, minutes: Int, secondsLeft: Int,
        keep: @escaping @MainActor () -> Void, stop: @escaping @MainActor () -> Void
    ) {
        model.meetingTitle = meetingTitle
        model.minutes = minutes
        model.secondsLeft = secondsLeft
        model.onKeep = keep
        model.onStop = stop
        // §5.6: an open prompt does not follow focus to another display, nor announce itself again.
        guard !isShown else { return }

        let panel = panel ?? makePanel(model)
        self.panel = panel
        panel.setFrame(Self.frame(size: panel.cardSize, on: screen()), display: true)
        panel.orderFrontRegardless()
        isShown = true
        announce(model.title)
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
    }

    /// The panel's frame: the card centred across `screen`, its top a fifth of the way down,
    /// with the shadow padding around it.
    static func frame(size: CGSize, on screen: CGRect) -> CGRect {
        let padding = SilencePromptPanel.shadowPadding
        let top = screen.maxY - screen.height / 5
        return CGRect(x: screen.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
            .insetBy(dx: -padding, dy: -padding)
    }

    static func postAnnouncement(_ text: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}

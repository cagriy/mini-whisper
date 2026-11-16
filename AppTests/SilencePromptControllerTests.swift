import AppKit
import Testing
@testable import MiniWhisper

/// The panels are built and placed, never ordered on screen.
@MainActor
@Suite struct SilencePromptControllerTests {
    // Primary 1920×1080 at the origin, secondary 1440×900 to its right, as in DisplayPlacementTests.
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let secondary = CGRect(x: 1920, y: 0, width: 1440, height: 900)
    private let card = CGSize(width: 380, height: 180)
    private let padding = SilencePromptPanel.shadowPadding

    /// Records what the controller asks of its panel instead of showing it.
    private final class RecordingPanel: SilencePromptPanel {
        private(set) var frames: [CGRect] = []
        private(set) var ordersFront = 0
        private(set) var ordersOut = 0
        // AppKit may size the window while it is built; only the controller's calls count.
        private var isBuilt = false

        override init(model: SilencePromptModel) {
            super.init(model: model)
            isBuilt = true
        }

        override func setFrame(_ frameRect: NSRect, display flag: Bool) {
            if isBuilt { frames.append(frameRect) }
            super.setFrame(frameRect, display: flag)
        }

        override func orderFrontRegardless() { ordersFront += 1 }
        override func orderOut(_ sender: Any?) { ordersOut += 1 }
    }

    @MainActor
    private final class Recorder {
        var screen: CGRect
        var announcements: [String] = []
        var panels: [RecordingPanel] = []
        var calls: [String] = []

        init(screen: CGRect) { self.screen = screen }

        var panel: RecordingPanel? { panels.first }
    }

    private func controller(_ recorder: Recorder) -> SilencePromptController {
        SilencePromptController(
            screen: { recorder.screen },
            announce: { recorder.announcements.append($0) },
            makePanel: { model in
                let panel = RecordingPanel(model: model)
                recorder.panels.append(panel)
                return panel
            }
        )
    }

    private func show(
        _ controller: SilencePromptController,
        secondsLeft: Int = 60,
        keep: @escaping @MainActor () -> Void = {},
        stop: @escaping @MainActor () -> Void = {}
    ) {
        controller.show(meetingTitle: "Standup", minutes: 1, secondsLeft: secondsLeft, keep: keep, stop: stop)
    }

    // `#expect` does not apply the implicit CGFloat/Double conversion, so the expected
    // coordinates are typed explicitly.
    @Test func frameIsCentredWithTheCardTopAtAFifthOfTheScreen() {
        let frame = SilencePromptController.frame(size: card, on: primary)
        let cardFrame = frame.insetBy(dx: padding, dy: padding)
        let midX: CGFloat = 960
        let top: CGFloat = 1080 - 216

        #expect(cardFrame.size == card)
        #expect(cardFrame.midX == midX)
        #expect(cardFrame.maxY == top)
    }

    @Test func frameFollowsASecondaryDisplay() {
        let frame = SilencePromptController.frame(size: card, on: secondary)
        let cardFrame = frame.insetBy(dx: padding, dy: padding)
        let midX: CGFloat = 1920 + 720
        let top: CGFloat = 900 - 180

        #expect(cardFrame.size == card)
        #expect(cardFrame.midX == midX)
        #expect(cardFrame.maxY == top)
    }

    @Test func panelNeverTakesFocusAndShowsOnEverySpace() {
        let panel = SilencePromptPanel(model: SilencePromptModel())

        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.isOpaque)
        #expect(!panel.hasShadow)
        #expect(panel.contentView?.acceptsFirstMouse(for: nil) == true)
    }

    @Test func firstShowPlacesAnnouncesAndOrdersFront() throws {
        let recorder = Recorder(screen: secondary)
        let controller = controller(recorder)

        show(controller)

        let panel = try #require(recorder.panel)
        // The measured card is the Dialog card, not an unlaid-out zero.
        #expect(panel.cardSize.width == 380)
        #expect(panel.cardSize.height > 0)
        #expect(panel.frames == [SilencePromptController.frame(size: panel.cardSize, on: secondary)])
        #expect(panel.ordersFront == 1)
        #expect(recorder.announcements == ["No one has spoken for 1 minute"])
    }

    @Test func showWhileOpenOnlyUpdatesTheModel() throws {
        let recorder = Recorder(screen: primary)
        let controller = controller(recorder)
        show(controller)

        recorder.screen = secondary
        show(controller, secondsLeft: 41)

        let panel = try #require(recorder.panel)
        #expect(controller.model.secondsLeft == 41)
        #expect(recorder.panels.count == 1)
        #expect(panel.frames.count == 1)
        #expect(panel.ordersFront == 1)
        #expect(recorder.announcements.count == 1)
    }

    @Test func hideOrdersOutAndTheNextShowPlacesAgain() throws {
        let recorder = Recorder(screen: primary)
        let controller = controller(recorder)
        show(controller)

        controller.hide()

        let panel = try #require(recorder.panel)
        #expect(panel.ordersOut == 1)

        recorder.screen = secondary
        show(controller)

        #expect(recorder.panels.count == 1)
        #expect(panel.frames.count == 2)
        #expect(panel.frames.last == SilencePromptController.frame(size: panel.cardSize, on: secondary))
        #expect(panel.ordersFront == 2)
        #expect(recorder.announcements.count == 2)
    }

    @Test func buttonsCallTheLatestClosures() {
        let recorder = Recorder(screen: primary)
        let controller = controller(recorder)
        show(controller, keep: { recorder.calls.append("keep 1") }, stop: { recorder.calls.append("stop 1") })
        show(controller, keep: { recorder.calls.append("keep 2") }, stop: { recorder.calls.append("stop 2") })

        controller.model.keep()
        controller.model.stop()

        #expect(recorder.calls == ["keep 2", "stop 2"])
    }
}

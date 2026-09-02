import MWPipeline

/// Main-actor fan-out of `DictationController.uiEvents` to the app's UI.
@MainActor
final class UIEventRouter {
    private let statusItem: StatusItemController
    private var task: Task<Void, Never>?

    init(statusItem: StatusItemController) {
        self.statusItem = statusItem
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
    }

    private func apply(_ event: UIEvent) {
        switch event {
        case .result(let text):
            statusItem.setLast(text)
        case .usage(let today, let month):
            statusItem.setUsage(today: today, month: month)
        case .starting, .recording, .level, .caption, .captionUnavailable, .captionNotice,
             .processing, .error, .idle:
            // The overlay and caption panels arrive in Stage 25.
            break
        }
    }
}

import Foundation
import MWStreaming

/// The controller's `TranscriptSink`: assembles the compound transcript and turns every
/// engine callback into a caption event. Callbacks arrive on engine threads, so the state
/// is behind a lock rather than an actor — the emit closure must be safe to call from any
/// thread (F21, F22, design §5.5).
public final class StreamSink: TranscriptSink, @unchecked Sendable {
    private struct Storage {
        var assembler = TranscriptAssembler()
        var failed = false
        var unavailableSent = false
    }

    private let lock = NSLock()
    private var storage = Storage()
    private let emit: @Sendable (UIEvent) -> Void

    public init(emit: @escaping @Sendable (UIEvent) -> Void) {
        self.emit = emit
    }

    /// True once the engine reported an error: the streamed transcript is unusable (F12).
    public var failed: Bool { lock.withLock { storage.failed } }

    /// The compound transcript so far, re-emitted dimmed while processing.
    public var text: String { lock.withLock { storage.assembler.text } }

    public func onPartial(_ text: String) {
        caption { $0.addPartial(text) }
    }

    public func onFinal(_ text: String) {
        caption { $0.addFinal(text) }
    }

    public func onEngineError(_ error: any Error) {
        lock.withLock { storage.failed = true }
        markUnavailable()
    }

    /// Emits `captionUnavailable` at most once per dictation (F21).
    public func markUnavailable() {
        let alreadySent = lock.withLock { () -> Bool in
            defer { storage.unavailableSent = true }
            return storage.unavailableSent
        }
        guard !alreadySent else { return }
        emit(.captionUnavailable)
    }

    private func caption(_ update: (inout TranscriptAssembler) -> Void) {
        let text = lock.withLock { () -> String? in
            guard !storage.failed else { return nil }
            update(&storage.assembler)
            return storage.assembler.text
        }
        guard let text else { return }
        emit(.caption(text: text, partial: true, dimmed: false))
    }
}

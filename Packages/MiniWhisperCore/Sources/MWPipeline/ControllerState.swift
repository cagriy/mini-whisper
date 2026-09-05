import Foundation
import MWCorrections
import MWHotkeys
import MWStreaming

/// One live dictation: everything a press creates and a release consumes (design §5.5).
struct RecordingSession {
    let id: Int
    let pressedAt: TimeInterval
    let binding: BindingName
    /// R12: the delivery app and the rules as they stood at the press.
    var startTarget: PasteTarget?
    var snapshot: CorrectionSnapshot?
    var engine: (any StreamingEngine)?
    var sink: StreamSink?
    var toggleArmed = false
    var tick: Task<Void, Never>?
    var cap: Task<Void, Never>?

    func cancelTimers() {
        tick?.cancel()
        cap?.cancel()
    }
}

/// Everything the controller remembers between hotkey events.
struct ControllerState {
    var session: RecordingSession?
    /// F23: each downgrade notice is shown at most once per app run.
    var shownNotices: Set<EngineNotice> = []
}

/// The generation guard of F15. Boxed rather than held on the main actor so the processing
/// job's `isStale` closure can read it from whatever executor the job runs on.
final class GenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var current: Int { lock.withLock { value } }

    func bump() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    func isStale(_ generation: Int) -> Bool { current != generation }
}

/// Holds a long-lived task that has to be cancelled from a nonisolated `deinit`.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func set(_ task: Task<Void, Never>) { lock.withLock { self.task = task } }
    func cancel() { lock.withLock { task }?.cancel() }
}

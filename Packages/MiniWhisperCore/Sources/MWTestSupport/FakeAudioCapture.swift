import AVFAudio
import Foundation
import MWAudio

/// `AudioCapture` without CoreAudio: records the calls the pipeline made, hands back a
/// canned `Recording`, and lets a test drive `AudioEvent`s and tap buffers by hand.
public final class FakeAudioCapture: AudioCapture, @unchecked Sendable {
    public enum Call: Sendable, Equatable {
        case ensureRunning
        case beginCapture
        /// `true` when a listener was attached, `false` when it was cleared.
        case attachListener(Bool)
        case endCapture
        case scheduleIdleStop(Duration)
        case cancelIdleStop
        case stop
        case holdRunning(Bool)
        /// `true` when a meeting listener was attached, `false` when it was cleared.
        case attachMeetingListener(Bool)
        case setVoiceProcessing(Bool)
    }

    private struct Storage {
        var calls: [Call] = []
        var listener: (any BufferListener)?
        var meetingListener: (any BufferListener)?
        var recording: Recording
        var beginFailure: (any Error)?
        var gated = false
        var gate: CheckedContinuation<Void, Never>?
    }

    public nonisolated let events: AsyncStream<AudioEvent>
    public nonisolated let meetingEvents: AsyncStream<MeetingAudioEvent>

    private let continuation: AsyncStream<AudioEvent>.Continuation
    private let meetingContinuation: AsyncStream<MeetingAudioEvent>.Continuation
    private let lock = NSLock()
    private var storage: Storage

    public init(
        recording: Recording = Recording(wav: Data("fake wav".utf8), duration: 1, meanRMS: 0.02)
    ) {
        storage = Storage(recording: recording)
        (events, continuation) = AsyncStream.makeStream()
        (meetingEvents, meetingContinuation) = AsyncStream.makeStream()
    }

    deinit {
        continuation.finish()
        meetingContinuation.finish()
    }

    public var calls: [Call] { lock.withLock { storage.calls } }
    public var listener: (any BufferListener)? { lock.withLock { storage.listener } }
    public var meetingListener: (any BufferListener)? { lock.withLock { storage.meetingListener } }

    public var recording: Recording {
        get { lock.withLock { storage.recording } }
        set { lock.withLock { storage.recording = newValue } }
    }

    public var beginFailure: (any Error)? {
        get { lock.withLock { storage.beginFailure } }
        set { lock.withLock { storage.beginFailure = newValue } }
    }

    /// Delivers an `AudioEvent` as the real engine would.
    public func send(_ event: AudioEvent) {
        continuation.yield(event)
    }

    /// Delivers a `MeetingAudioEvent` as the real engine would.
    public func sendMeeting(_ event: MeetingAudioEvent) {
        meetingContinuation.yield(event)
    }

    /// Hands a tap buffer to whichever listeners are attached, synchronously.
    public func feed(_ buffer: AVAudioPCMBuffer) {
        let (meeting, dictation) = lock.withLock { (storage.meetingListener, storage.listener) }
        meeting?.feed(buffer)
        dictation?.feed(buffer)
    }

    /// Makes `cancelIdleStop()` — the press path's first `await` — suspend until released,
    /// so a test can prove what happened before it.
    public func blockCancelIdleStop() {
        lock.withLock { storage.gated = true }
    }

    public func releaseCancelIdleStop() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            storage.gated = false
            defer { storage.gate = nil }
            return storage.gate
        }
        waiting?.resume()
    }

    // MARK: - AudioCapture

    public func ensureRunning() async throws {
        record(.ensureRunning)
    }

    public func beginCapture() async throws {
        record(.beginCapture)
        if let failure = beginFailure { throw failure }
    }

    public func attachListener(_ listener: (any BufferListener)?) async {
        lock.withLock {
            storage.listener = listener
            storage.calls.append(.attachListener(listener != nil))
        }
    }

    public func endCapture() async -> Recording {
        record(.endCapture)
        return recording
    }

    public func scheduleIdleStop(after duration: Duration) async {
        record(.scheduleIdleStop(duration))
    }

    public func cancelIdleStop() async {
        record(.cancelIdleStop)
        guard lock.withLock({ storage.gated }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                guard storage.gated else { return true }
                storage.gate = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    public func stop() async {
        record(.stop)
    }

    public func holdRunning(_ held: Bool) async {
        record(.holdRunning(held))
    }

    public func attachMeetingListener(_ listener: (any BufferListener)?) async {
        lock.withLock {
            storage.meetingListener = listener
            storage.calls.append(.attachMeetingListener(listener != nil))
        }
    }

    public func setVoiceProcessing(_ on: Bool) async throws {
        record(.setVoiceProcessing(on))
    }

    private func record(_ call: Call) {
        lock.withLock { storage.calls.append(call) }
    }
}

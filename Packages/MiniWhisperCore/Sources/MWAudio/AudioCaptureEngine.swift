import AVFAudio
import Foundation
import MWSupport
import os

/// Capture state shared between the actor and the audio tap thread.
///
/// The tap callback hands the buffer to the listener synchronously, on the tap
/// thread, with no actor hop and no `Task` (design §5.5, §5.9, F18) — so every
/// field it touches is guarded by this lock rather than by the actor.
private final class CaptureState: @unchecked Sendable {
    struct Snapshot {
        var samples: [Float] = []
        var rmsSum: Double = 0
        var bufferCount = 0
        var sampleRate: Double = 0
    }

    private struct Storage {
        var capturing = false
        var live = false
        var listener: (any BufferListener)?
        var snapshot = Snapshot()
    }

    private let storage = OSAllocatedUnfairLock(initialState: Storage())
    private let events: AsyncStream<AudioEvent>.Continuation

    init(events: AsyncStream<AudioEvent>.Continuation) {
        self.events = events
    }

    func begin() {
        storage.withLock { state in
            state.capturing = true
            state.live = false
            state.snapshot = Snapshot()
        }
    }

    func setListener(_ listener: (any BufferListener)?) {
        storage.withLock { $0.listener = listener }
    }

    /// Stops accumulation without discarding what was captured; `true` when a
    /// capture was in progress.
    @discardableResult
    func suspend() -> Bool {
        storage.withLock { state in
            defer { state.capturing = false }
            return state.capturing
        }
    }

    func end() -> Snapshot {
        storage.withLock { state in
            defer {
                state.capturing = false
                state.live = false
                state.listener = nil
                state.snapshot = Snapshot()
            }
            return state.snapshot
        }
    }

    /// Called on the tap thread for every buffer.
    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        let samples = [Float](UnsafeBufferPointer(start: channel, count: count))
        var sumOfSquares = 0.0
        for sample in samples { sumOfSquares += Double(sample) * Double(sample) }
        let rms = (sumOfSquares / Double(count)).squareRoot()
        let rate = buffer.format.sampleRate

        let (accepted, listener, isFirst) = storage.withLock { state -> (Bool, (any BufferListener)?, Bool) in
            guard state.capturing else { return (false, nil, false) }
            state.snapshot.samples.append(contentsOf: samples)
            state.snapshot.rmsSum += rms
            state.snapshot.bufferCount += 1
            state.snapshot.sampleRate = rate
            let isFirst = !state.live
            state.live = true
            return (true, state.listener, isFirst)
        }
        guard accepted else { return }
        if isFirst { events.yield(.live) }
        listener?.feed(buffer)
    }
}

/// Holds the backend-event observation task, which has to be created in a
/// nonisolated `init` and cancelled from `deinit`.
private final class TaskBox: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    func set(_ task: Task<Void, Never>) { storage.withLock { $0 = task } }
    func cancel() { storage.withLock { $0 }?.cancel() }
}

/// Owns the audio backend for the whole idle period rather than per press: the
/// engine starts on the first press, capture is a flag flip while it runs, and it
/// stops `idle_stop_seconds` after the last dictation, on sleep, or on quit
/// (F18, F19, design §5.5).
public actor AudioCaptureEngine: AudioCapture {
    private static let tapFrames: AVAudioFrameCount = 1024

    public nonisolated let events: AsyncStream<AudioEvent>

    private nonisolated let eventContinuation: AsyncStream<AudioEvent>.Continuation
    private nonisolated let capture: CaptureState
    private let backend: any AudioBackend
    private let clock: any Clock
    private var running = false
    private var idleStop: Task<Void, Never>?
    private nonisolated let backendEvents = TaskBox()

    public init(backend: any AudioBackend, clock: any Clock = SystemClock()) {
        self.backend = backend
        self.clock = clock
        let (stream, continuation) = AsyncStream<AudioEvent>.makeStream()
        events = stream
        eventContinuation = continuation
        capture = CaptureState(events: continuation)
        backendEvents.set(Task { [weak self, backend] in
            for await event in backend.events {
                guard let self else { return }
                await self.handle(event)
            }
        })
    }

    deinit {
        backendEvents.cancel()
        idleStop?.cancel()
        eventContinuation.finish()
    }

    public func ensureRunning() throws {
        guard !running else { return }
        // Reinstalled on every start: after a configuration change the input
        // format is new, so the previous tap no longer matches the hardware.
        backend.installTap(bufferSize: Self.tapFrames) { [capture] buffer in
            capture.ingest(buffer)
        }
        try backend.start()
        running = true
        Log.audio.info("engine started")
    }

    public func beginCapture() throws {
        try ensureRunning()
        cancelIdleStop()
        capture.begin()
    }

    public func attachListener(_ listener: (any BufferListener)?) {
        capture.setListener(listener)
    }

    public func endCapture() -> Recording {
        let snapshot = capture.end()
        let rate = snapshot.sampleRate > 0 ? snapshot.sampleRate : backend.inputFormat.sampleRate
        let duration = rate > 0 ? Double(snapshot.samples.count) / rate : 0
        let meanRMS = snapshot.bufferCount > 0
            ? Float(snapshot.rmsSum / Double(snapshot.bufferCount))
            : 0
        return Recording(
            wav: WAVEncoder.encode(samples: snapshot.samples, sampleRate: rate),
            duration: duration,
            meanRMS: meanRMS
        )
    }

    public func scheduleIdleStop(after duration: Duration) {
        idleStop?.cancel()
        idleStop = Task { [weak self, clock] in
            guard (try? await clock.sleep(for: duration)) != nil, !Task.isCancelled else { return }
            await self?.idleStopFired()
        }
    }

    public func cancelIdleStop() {
        idleStop?.cancel()
        idleStop = nil
    }

    public func stop() {
        capture.suspend()
        teardown()
        eventContinuation.yield(.stopped)
    }

    private func idleStopFired() {
        idleStop = nil
        guard running else { return }
        Log.audio.info("idle stop")
        stop()
    }

    private func handle(_ event: AudioBackendEvent) {
        switch event {
        case .configurationChanged:
            // During capture the recording is over (F19); while idle the engine is
            // merely marked stopped so the next press restarts it at the new format.
            let wasCapturing = capture.suspend()
            teardown()
            eventContinuation.yield(wasCapturing ? .deviceChanged : .stopped)
        case .systemWillSleep:
            stop()
        }
    }

    private func teardown() {
        cancelIdleStop()
        guard running else { return }
        backend.stop()
        running = false
    }
}

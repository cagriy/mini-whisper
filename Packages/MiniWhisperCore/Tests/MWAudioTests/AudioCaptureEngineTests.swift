import AVFAudio
import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWAudio

private func currentThreadID() -> UInt64 {
    var id: UInt64 = 0
    pthread_threadid_np(nil, &id)
    return id
}

/// Records the buffers handed to it and the thread each arrived on, so the tests can
/// prove the tap → listener hand-off is synchronous (design §5.5, F18).
private final class RecordingListener: BufferListener, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(frames: Int, thread: UInt64)] = []

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { storage.append((Int(buffer.frameLength), currentThreadID())) }
    }

    var frameCounts: [Int] { lock.withLock { storage.map(\.frames) } }
    var threads: [UInt64] { lock.withLock { storage.map(\.thread) } }
}

@Suite struct AudioCaptureEngineTests {
    private static let rate: Double = 48000

    private func buffer(_ value: Float, count: Int = 1024) -> AVAudioPCMBuffer {
        PCMBufferFactory.make(samples: [Float](repeating: value, count: count), sampleRate: Self.rate)
    }

    @Test func ensureRunningStartsBackendOnce() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())

        try await engine.ensureRunning()
        try await engine.ensureRunning()

        #expect(backend.startCount == 1)
    }

    @Test func beginCaptureFlipsFlagWithoutRestart() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())

        try await engine.ensureRunning()
        try await engine.beginCapture()

        #expect(backend.startCount == 1)
        backend.deliver(buffer(0.1))
        let recording = await engine.endCapture()
        #expect(recording.duration > 0)
    }

    @Test func firstBufferEmitsLiveOnce() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())
        var events = engine.events.makeAsyncIterator()

        try await engine.beginCapture()
        backend.deliver(buffer(0.1))
        backend.deliver(buffer(0.1))
        #expect(await events.next() == .live)

        // A second `.live` would arrive here instead of `.stopped`.
        await engine.stop()
        #expect(await events.next() == .stopped)
    }

    @Test func buffersBeforeBeginCaptureAreDropped() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())

        try await engine.ensureRunning()
        backend.deliver(buffer(0.9))
        try await engine.beginCapture()
        backend.deliver(buffer(0.2))

        let recording = await engine.endCapture()
        #expect(abs(recording.duration - 1024 / Self.rate) < 1e-9)
        #expect(abs(recording.meanRMS - 0.2) < 1e-5)
    }

    @Test func endCaptureReturnsWavDurationAndMeanRMS() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())

        try await engine.beginCapture()
        for value in [Float(0.1), 0.2, 0.3] { backend.deliver(buffer(value)) }
        let recording = await engine.endCapture()

        #expect(abs(recording.duration - 0.064) < 1e-9)
        #expect(abs(recording.meanRMS - 0.2) < 1e-5)
        // 3072 frames at 48 kHz resample to 1024 int16 samples plus the 44-byte header.
        #expect(recording.wav.count == 2048 + 44)
    }

    @Test func listenerReceivesBuffersSynchronously() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())
        let listener = RecordingListener()

        try await engine.beginCapture()
        backend.deliver(buffer(0.1))
        backend.deliver(buffer(0.1))
        await engine.attachListener(listener)
        backend.deliver(buffer(0.3, count: 512))

        // Asserted without an await: the listener must have run before `deliver` returned.
        #expect(listener.frameCounts == [512])
        #expect(listener.threads == [currentThreadID()])
    }

    @Test func idleStopFiresAfterDurationOnVirtualClock() async throws {
        let backend = FakeAudioBackend()
        let clock = VirtualClock()
        let engine = AudioCaptureEngine(backend: backend, clock: clock)
        var events = engine.events.makeAsyncIterator()

        try await engine.ensureRunning()
        await engine.scheduleIdleStop(after: .seconds(60))
        await clock.waitUntilSleeping()

        clock.advance(by: 59)
        #expect(backend.stopCount == 0)

        clock.advance(by: 1)
        #expect(await events.next() == .stopped)
        #expect(backend.stopCount == 1)
    }

    @Test func cancelIdleStopPreventsStop() async throws {
        let backend = FakeAudioBackend()
        let clock = VirtualClock()
        let engine = AudioCaptureEngine(backend: backend, clock: clock)

        try await engine.ensureRunning()
        await engine.scheduleIdleStop(after: .seconds(60))
        await clock.waitUntilSleeping()
        await engine.cancelIdleStop()

        clock.advance(by: 60)
        #expect(backend.stopCount == 0)
    }

    @Test func beginCaptureCancelsPendingIdleStop() async throws {
        let backend = FakeAudioBackend()
        let clock = VirtualClock()
        let engine = AudioCaptureEngine(backend: backend, clock: clock)

        try await engine.ensureRunning()
        await engine.scheduleIdleStop(after: .seconds(60))
        await clock.waitUntilSleeping()
        try await engine.beginCapture()

        clock.advance(by: 60)
        #expect(backend.stopCount == 0)
    }

    @Test func configurationChangeDuringCaptureEmitsDeviceChangedAndEndsCapture() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())
        var events = engine.events.makeAsyncIterator()

        try await engine.beginCapture()
        backend.deliver(buffer(0.1))
        #expect(await events.next() == .live)

        backend.emit(.configurationChanged)
        #expect(await events.next() == .deviceChanged)

        backend.deliver(buffer(0.5))
        let recording = await engine.endCapture()
        #expect(abs(recording.duration - 1024 / Self.rate) < 1e-9)
    }

    @Test func configurationChangeWhileIdleMarksStoppedSoNextEnsureRunningRestarts() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())
        var events = engine.events.makeAsyncIterator()

        try await engine.ensureRunning()
        backend.emit(.configurationChanged)
        #expect(await events.next() == .stopped)

        try await engine.ensureRunning()
        #expect(backend.startCount == 2)
    }

    @Test func sleepStopsImmediately() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())
        var events = engine.events.makeAsyncIterator()

        try await engine.beginCapture()
        backend.emit(.systemWillSleep)

        #expect(await events.next() == .stopped)
        #expect(backend.stopCount == 1)
    }

    @Test func startFailureThrowsBackendError() async {
        let backend = FakeAudioBackend()
        backend.startError = FakeAudioBackend.Failure.startFailed
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())

        await #expect(throws: FakeAudioBackend.Failure.startFailed) {
            try await engine.ensureRunning()
        }
    }

    @Test func tapUses1024FramesAtInputFormat() async throws {
        let backend = FakeAudioBackend()
        let engine = AudioCaptureEngine(backend: backend, clock: VirtualClock())

        try await engine.ensureRunning()

        #expect(backend.tapBufferSize == 1024)
        #expect(backend.tapFormat?.sampleRate == backend.inputFormat.sampleRate)
    }
}

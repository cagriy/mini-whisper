import AVFAudio
import Foundation
import MWAudio
import MWConfig
import MWCorrections
import MWHotkeys
import MWProfiles
import MWStreaming
import MWSupport

/// The press/release state machine (F9–F11, F15–F19, F23): it decides when audio captures,
/// which engine streams, when a recording becomes a dictation and when the microphone may
/// stop. Every side effect goes through `Dependencies`, and every duration through `Clock`
/// as a one-shot — the press path never polls (N1).
@MainActor
public final class DictationController {
    private static let holdThreshold: TimeInterval = 0.3
    private static let tickDelay = Duration.seconds(0.1)
    private static let minRecordingSeconds: TimeInterval = 0.5
    private static let silenceRMSThreshold: Float = 0.005
    /// A stream whose text is unwanted is given far less than F21's 5 s to close.
    private static let discardTimeout = Duration.seconds(0.5)

    public nonisolated let uiEvents: AsyncStream<UIEvent>

    private nonisolated let continuation: AsyncStream<UIEvent>.Continuation
    private nonisolated let emit: @Sendable (UIEvent) -> Void
    private nonisolated let generations = GenerationCounter()
    private nonisolated let audioEvents = TaskBox()

    private let deps: Dependencies
    private let configStore: ConfigStore
    private let clock: any Clock
    private let job: ProcessingJob
    private let billing: StreamBilling
    private let log = Log.pipeline

    private var state = ControllerState()
    private var pressTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    public init(deps: Dependencies, config: ConfigStore, clock: any Clock = SystemClock()) {
        self.deps = deps
        configStore = config
        self.clock = clock
        job = ProcessingJob(deps: deps)
        billing = StreamBilling(usage: deps.usage)
        (uiEvents, continuation) = AsyncStream.makeStream()
        let continuation = self.continuation
        emit = { continuation.yield($0) }
        audioEvents.set(Task { [weak self, events = deps.audio.events] in
            for await event in events {
                guard let self else { return }
                await handle(event)
            }
        })
    }

    deinit {
        audioEvents.cancel()
        continuation.finish()
    }

    // MARK: - Hotkeys

    /// Synchronous up to `.starting` so the overlay is on screen within one frame (N1);
    /// everything that can suspend runs in the task this spawns.
    public func hotkeyPressed(_ name: BindingName) {
        if let session = state.session {
            // F10: the second tap of a toggle stops. F16: any other press is ignored.
            if session.toggleArmed { stopAndProcess(binding: name) }
            return
        }
        // R12: the delivery app is read before `.starting`, so nothing the user does
        // once the overlay appears can change which app the hints were resolved for.
        let startTarget = deps.frontmost.frontmost()
        emit(.starting)
        let id = generations.bump()
        state.session = RecordingSession(
            id: id, pressedAt: clock.now, binding: name, startTarget: startTarget
        )
        startTick(id: id)
        pressTask = Task { await self.beginRecording(id: id) }
    }

    /// F10: a release inside the hold threshold arms the toggle, a longer hold stops.
    public func hotkeyReleased(_ name: BindingName) {
        guard let session = state.session, !session.toggleArmed else { return }
        guard clock.now - session.pressedAt >= Self.holdThreshold else {
            state.session?.toggleArmed = true
            startToggleCap(id: session.id)
            return
        }
        stopAndProcess(binding: name)
    }

    /// Quit path (design §5.7): the live stream is finished, its seconds billed and the
    /// audio engine stopped; nothing is pasted.
    public func abort() async {
        guard let session = state.session else { return await deps.audio.stop() }
        endSession()
        await deps.audio.attachListener(nil)
        await discard(session.engine, overrides: await configStore.load().pricingOverrides)
        await deps.audio.stop()
    }

    // MARK: - Press path

    private func beginRecording(id: Int) async {
        await deps.audio.cancelIdleStop()
        do {
            try await deps.audio.beginCapture()
        } catch {
            // F16 / design §5.7: no stream, and no idle-stop timer to schedule.
            guard state.session?.id == id else { return }
            endSession()
            deps.sounds.playOff()
            emit(.error("Mic error: \(AnyError(error).description)"))
            return
        }
        guard state.session?.id == id else { return }
        await startStream(id: id)
    }

    /// F23: selection and its one-per-run downgrade notice. A failure here never breaks the
    /// dictation — it simply leaves the batch path in place.
    private func startStream(id: Int) async {
        let config = await configStore.load()
        guard state.session?.id == id else { return }
        // R12/R13: one snapshot per recording, and hints for the app that was frontmost
        // at the press — the only app the engine can be steered towards.
        let snapshot = CorrectionSnapshot(config: config)
        state.session?.snapshot = snapshot
        let hints = HintResolver.resolve(
            snapshot, bundleID: state.session?.startTarget?.bundleID
        )
        let selection = await deps.engines.make(
            config: config, secrets: deps.secrets, hints: hints
        )
        guard state.session?.id == id else { return }

        if let notice = selection.notice, state.shownNotices.insert(notice).inserted {
            switch notice {
            case .speechPermissionPointer: emit(.error(notice.message))
            case .cloudKeyMissing: emit(.captionNotice(notice.message))
            }
        }
        if let engine = selection.engine {
            let sink = StreamSink(emit: emit)
            state.session?.engine = engine
            state.session?.sink = sink
            engine.start(sink: sink)
            log.info("streaming with \(engine.name.rawValue)")
        }
        // Buffers captured before this point are recorded but not streamed (design §5.5).
        await deps.audio.attachListener(
            CaptureListener(emit: emit, engine: state.session?.engine)
        )
    }

    // MARK: - Audio events

    private func handle(_ event: AudioEvent) async {
        switch event {
        case .live:
            guard state.session != nil else { return }
            state.session?.tick?.cancel()
            state.session?.tick = nil
            emit(.recording)
            deps.sounds.playOn()
        case .deviceChanged:
            // F19: only a capture in progress is affected; while idle the engine simply
            // restarts on the next press.
            guard let session = state.session else { return }
            await endWithError("Audio device changed", session: session)
        case .stopped:
            break
        }
    }

    private func endWithError(_ message: String, session: RecordingSession) async {
        endSession()
        await deps.audio.attachListener(nil)
        _ = await deps.audio.endCapture()
        await discard(session.engine, overrides: await configStore.load().pricingOverrides)
        deps.sounds.playOff()
        emit(.error(message))
    }

    // MARK: - Stop and process

    private func stopAndProcess(binding: BindingName) {
        stopTask = Task { await self.stop(binding: binding) }
    }

    private func stop(binding: BindingName) async {
        guard let session = state.session else { return }
        // F17: the target is whatever was frontmost at the moment of release.
        let target = deps.frontmost.frontmost() ?? PasteTarget(pid: 0, name: "")
        endSession()
        await deps.audio.attachListener(nil)
        let recording = await deps.audio.endCapture()
        let config = await configStore.load()

        // F11: too short or too quiet is not a dictation; the stream is discarded but its
        // seconds are still billed.
        guard recording.duration >= Self.minRecordingSeconds,
              recording.meanRMS >= Self.silenceRMSThreshold
        else {
            await discard(session.engine, overrides: config.pricingOverrides)
            deps.sounds.playOff()
            emit(.idle)
            await scheduleIdleStop(config)
            return
        }

        emit(.processing)
        if let sink = session.sink, !sink.failed {
            emit(.caption(text: sink.text, partial: false, dimmed: true))
        }

        let profile: ResolvedProfile
        do {
            profile = try ProfileResolver(config: config, defaultPrompt: deps.prompts.cleanupPrompt)
                .resolve(bundleID: target.bundleID)
        } catch {
            deps.sounds.playOff()
            emit(.error(AnyError(error).description))
            await scheduleIdleStop(config)
            return
        }

        let generation = generations.bump()
        let input = ProcessingInput(
            recording: recording,
            engine: session.engine,
            sink: session.sink,
            profile: profile,
            target: target,
            binding: binding,
            config: config,
            snapshot: session.snapshot ?? CorrectionSnapshot(config: config)
        )
        await scheduleIdleStop(config)
        processingTask = Task { [job, generations, emit] in
            await job.run(input, isStale: { generations.isStale(generation) }, emit: emit)
            await self.processingFinished()
        }
    }

    /// F18: the microphone stops `idle_stop_seconds` after the last dictation ended, so the
    /// timer is rearmed at every terminus.
    private func processingFinished() async {
        await scheduleIdleStop(await configStore.load())
    }

    private func scheduleIdleStop(_ config: Config) async {
        await deps.audio.scheduleIdleStop(after: .seconds(Double(config.idleStopSeconds)))
    }

    // MARK: - Timers (one-shots only, N1)

    private func startTick(id: Int) {
        state.session?.tick = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.tickDelay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.tickFired(id: id)
        }
    }

    /// F9: capture was not live within 100 ms of the press.
    private func tickFired(id: Int) {
        guard state.session?.id == id else { return }
        state.session?.tick = nil
        deps.sounds.playTick()
    }

    private func startToggleCap(id: Int) {
        state.session?.cap = Task { [weak self, clock, configStore] in
            let seconds = await configStore.load().toggleMaxSeconds
            do { try await clock.sleep(for: .seconds(Double(seconds))) } catch { return }
            guard !Task.isCancelled else { return }
            self?.toggleCapFired(id: id)
        }
    }

    /// F10: a toggle-armed recording stops itself at `toggle_max_seconds`.
    private func toggleCapFired(id: Int) {
        guard let session = state.session, session.id == id else { return }
        log.info("toggle cap reached")
        stopAndProcess(binding: session.binding)
    }

    // MARK: - Session helpers

    private func endSession() {
        state.session?.cancelTimers()
        state.session = nil
    }

    private func discard(_ engine: (any StreamingEngine)?, overrides: [String: Double]) async {
        guard let engine else { return }
        let result = await engine.finish(timeout: Self.discardTimeout)
        await billing.record(
            engine: engine.name, seconds: result.usage.seconds, overrides: overrides
        )
    }

    // MARK: - Test seams

    var generation: Int { generations.current }

    /// Awaits the work the last press or release spawned.
    func settle() async {
        await pressTask?.value
        await stopTask?.value
        await processingTask?.value
    }
}

/// The one tap listener: it publishes the per-buffer level the overlay animates from and
/// hands the buffer straight to the streaming engine on the same thread (design §5.5, §5.9).
private final class CaptureListener: BufferListener {
    private let emit: @Sendable (UIEvent) -> Void
    private let engine: (any StreamingEngine)?

    init(emit: @escaping @Sendable (UIEvent) -> Void, engine: (any StreamingEngine)?) {
        self.emit = emit
        self.engine = engine
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        emit(.level(rms: Self.rms(buffer)))
        engine?.feed(buffer)
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sumOfSquares = 0.0
        for index in 0..<count {
            let sample = Double(channel[index])
            sumOfSquares += sample * sample
        }
        return Float((sumOfSquares / Double(count)).squareRoot())
    }
}

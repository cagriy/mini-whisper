import AVFAudio
import Foundation
import MWConfig
import MWCorrections
import MWSupport

/// On-device recognition through `SFSpeechRecognizer` (F20), a port of
/// `../mini-whisper-py/src/mini_whisper/streaming/on_device.py`: buffers fed before the
/// session opens are flushed on `start`, the first final result completes the stream,
/// and any recogniser error fails the engine once so the pipeline falls back to batch.
public final class SFSpeechEngine: StreamingEngine, @unchecked Sendable {
    private struct State {
        var sink: (any TranscriptSink)?
        var request: (any RecognitionRequestHandle)?
        var preStart: [AVAudioPCMBuffer] = []
        var assembler = TranscriptAssembler()
        var startedAt: TimeInterval?
        var failed = false
    }

    public let name = EngineName.onDevice

    private let api: any SpeechRecognitionAPI
    private let clock: any Clock
    private let hints: RecognitionHints
    private let lock = NSLock()
    private var state = State()
    private let done = Latch()
    private let log = Log.stream(EngineName.onDevice.rawValue)

    public init(
        api: any SpeechRecognitionAPI,
        clock: any Clock = SystemClock(),
        hints: RecognitionHints = .none
    ) {
        self.api = api
        self.clock = clock
        self.hints = hints
    }

    // MARK: - StreamingEngine

    public func start(sink: any TranscriptSink) {
        lock.withLock {
            state.sink = sink
            state.startedAt = clock.now
        }
        let capped = HintSerializer.contextualStrings(hints)
        let request: any RecognitionRequestHandle
        do {
            request = try api.startTask(
                options: RecognitionOptions(
                    requiresOnDeviceRecognition: true,
                    shouldReportPartialResults: true,
                    contextualStrings: capped.sent
                ),
                onResult: { [weak self] event in self?.handle(event) }
            )
        } catch {
            fail(error)
            return
        }
        log.info("engine started")
        if let line = capped.logLine { log.info("\(line)") }

        // Publish the request only in the same critical section that finds the backlog
        // empty. A tap-thread `feed` racing this loop still enqueues, and is drained on
        // the next pass, so buffers always reach the recogniser in the order they arrived.
        while true {
            let pending = lock.withLock { () -> [AVAudioPCMBuffer] in
                guard !state.preStart.isEmpty else {
                    state.request = request
                    return []
                }
                defer { state.preStart = [] }
                return state.preStart
            }
            guard !pending.isEmpty else { break }
            for buffer in pending { request.append(buffer) }
        }
    }

    /// Called synchronously on the audio tap thread.
    public func feed(_ buffer: AVAudioPCMBuffer) {
        let request = lock.withLock { () -> (any RecognitionRequestHandle)? in
            guard !state.failed else { return nil }
            guard let request = state.request else {
                // The session is not open yet: buffer and flush on start.
                state.preStart.append(buffer)
                return nil
            }
            return request
        }
        request?.append(buffer)
    }

    public func finish(timeout: Duration) async -> StreamResult {
        let (request, startedAt, failedBefore) = lock.withLock {
            (state.request, state.startedAt, state.failed)
        }
        let usage = StreamUsage(seconds: startedAt.map { clock.now - $0 } ?? 0)
        if !failedBefore { request?.endAudio() }

        let finished = await done.raised(within: timeout, on: clock)
        if !finished { log.info("finish timeout after \(timeout.seconds)s") }

        let snapshot = lock.withLock { state }
        guard finished, !snapshot.failed else { return StreamResult(text: "", ok: false, usage: usage) }
        log.info("engine finished")
        return StreamResult(text: snapshot.assembler.text, ok: true, usage: usage)
    }

    // MARK: - Recogniser callbacks

    private func handle(_ event: RecognitionEvent) {
        switch event {
        case .failure(let error):
            fail(error)
        case .transcript(let text, let isFinal):
            let sink = lock.withLock { () -> (any TranscriptSink)? in
                if isFinal {
                    state.assembler.addFinal(text)
                } else {
                    state.assembler.addPartial(text)
                }
                return state.sink
            }
            if isFinal {
                sink?.onFinal(text)
                done.raise()
            } else {
                sink?.onPartial(text)
            }
        }
    }

    /// Single-shot: only the first failure reaches the sink.
    private func fail(_ error: any Error) {
        let (report, sink) = lock.withLock { () -> (Bool, (any TranscriptSink)?) in
            guard !state.failed else { return (false, nil) }
            state.failed = true
            return (true, state.sink)
        }
        guard report else { return }
        log.info("engine failed: \(AnyError(error).description)")
        done.raise()
        sink?.onEngineError(error)
    }
}

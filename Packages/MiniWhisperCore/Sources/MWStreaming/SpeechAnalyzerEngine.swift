import AVFAudio
import Foundation
import MWConfig
import MWCorrections
import MWSupport

/// Live transcription through `SpeechAnalyzer` + `SpeechTranscriber` (F24): volatile
/// results become partials, finalised results become finals, and `finish` finalises
/// through the last input, waiting at most the given timeout (F21). Every failure
/// path returns `ok == false`, so the pipeline falls back to batch.
public final class SpeechAnalyzerEngine: StreamingEngine, @unchecked Sendable {
    private struct State {
        var sink: (any TranscriptSink)?
        var session: (any AnalyzerSession)?
        var format: AVAudioFormat?
        var preStart: [AVAudioPCMBuffer] = []
        var assembler = TranscriptAssembler()
        var startedAt: TimeInterval?
        var failed = false
        var opening: Task<Void, Never>?
        var consuming: Task<Void, Never>?
    }

    public let name = EngineName.speechAnalyzer

    private let api: any SpeechAnalyzerAPI
    private let locale: Locale
    private let clock: any Clock
    private let hints: RecognitionHints
    private let lock = NSLock()
    private var state = State()
    private let done = Latch()
    private let log = Log.stream(EngineName.speechAnalyzer.rawValue)

    public init(
        api: any SpeechAnalyzerAPI,
        locale: Locale = .current,
        clock: any Clock = SystemClock(),
        hints: RecognitionHints = .none
    ) {
        self.api = api
        self.locale = locale
        self.clock = clock
        self.hints = hints
    }

    deinit {
        let tasks = lock.withLock { (state.opening, state.consuming) }
        tasks.0?.cancel()
        tasks.1?.cancel()
    }

    // MARK: - StreamingEngine

    public func start(sink: any TranscriptSink) {
        lock.withLock {
            state.sink = sink
            state.startedAt = clock.now
            state.opening = Task { await self.open() }
        }
    }

    /// Called synchronously on the audio tap thread.
    public func feed(_ buffer: AVAudioPCMBuffer) {
        let ready = lock.withLock { () -> (any AnalyzerSession, AVAudioFormat)? in
            guard !state.failed else { return nil }
            guard let session = state.session, let format = state.format else {
                // The analyzer is not running yet: buffer and flush on open.
                state.preStart.append(buffer)
                return nil
            }
            return (session, format)
        }
        guard let ready else { return }
        send(buffer, to: ready.0, as: ready.1)
    }

    public func finish(timeout: Duration) async -> StreamResult {
        await lock.withLock { state.opening }?.value
        let (session, startedAt, failedBefore) = lock.withLock {
            (state.session, state.startedAt, state.failed)
        }
        let usage = StreamUsage(seconds: startedAt.map { clock.now - $0 } ?? 0)

        var finalizing: Task<Void, Never>?
        if let session, !failedBefore {
            finalizing = Task {
                do {
                    try await session.finish()
                } catch {
                    self.fail(error)
                }
            }
        }
        let finished = await done.raised(within: timeout, on: clock)
        if !finished { log.info("finish timeout after \(timeout.seconds)s") }
        finalizing?.cancel()
        lock.withLock { state.consuming }?.cancel()

        let snapshot = lock.withLock { state }
        guard finished, !snapshot.failed else { return StreamResult(text: "", ok: false, usage: usage) }
        log.info("engine finished")
        return StreamResult(text: snapshot.assembler.text, ok: true, usage: usage)
    }

    // MARK: - Session

    private func open() async {
        let capped = HintSerializer.contextualStrings(hints)
        let session: any AnalyzerSession
        let format: AVAudioFormat
        do {
            session = try await api.makeSession(locale: locale, contextualStrings: capped.sent)
            guard let best = await api.bestAudioFormat(locale: locale) else {
                throw SpeechAnalyzerError.noCompatibleAudioFormat
            }
            format = best
        } catch {
            fail(error)
            return
        }
        log.info("engine started")
        if let line = capped.logLine { log.info("\(line)") }

        // Publishing and flushing under one acquisition: a tap-thread `feed` cannot
        // slip a later buffer in ahead of the ones waiting to be flushed.
        lock.withLock {
            state.session = session
            state.format = format
            state.consuming = Task { await self.consume(session) }
            for buffer in state.preStart { send(buffer, to: session, as: format) }
            state.preStart = []
        }
    }

    private func send(_ buffer: AVAudioPCMBuffer, to session: any AnalyzerSession, as format: AVAudioFormat) {
        guard let converted = api.convert(buffer, to: format) else { return }
        session.feed(converted)
    }

    /// Drains results until the analyzer finishes, then releases `finish`.
    private func consume(_ session: any AnalyzerSession) async {
        for await transcript in session.results {
            let sink = lock.withLock { () -> (any TranscriptSink)? in
                if transcript.isFinal {
                    state.assembler.addFinal(transcript.text)
                } else {
                    state.assembler.addPartial(transcript.text)
                }
                return state.sink
            }
            if transcript.isFinal {
                sink?.onFinal(transcript.text)
            } else {
                sink?.onPartial(transcript.text)
            }
        }
        done.raise()
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

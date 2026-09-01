import AVFAudio
import Foundation
import MWAudio
import MWConfig
import MWSupport
import os

public enum WebSocketEngineError: Error, CustomStringConvertible {
    case preconnectCapExceeded(engine: EngineName, seconds: TimeInterval)

    public var description: String {
        switch self {
        case .preconnectCapExceeded(let engine, let seconds):
            "\(engine.rawValue): connection not open after \(Int(seconds))s of buffered audio"
        }
    }
}

/// A latch that many tasks can await and one can raise, cancellation-safe so the
/// racing task group in `finish` can always unwind.
private final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    private var waiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<UInt64> = []
    private var nextID: UInt64 = 0

    func raise() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            raised = true
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        let id = lock.withLock { () -> UInt64 in
            nextID += 1
            return nextID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    if raised || cancelled.remove(id) != nil { return true }
                    waiters[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                guard let waiter = waiters.removeValue(forKey: id) else {
                    cancelled.insert(id)
                    return nil
                }
                return waiter
            }
            waiter?.resume()
        }
    }
}

/// The shared cloud streaming skeleton (F20, F21), a port of
/// `../mini-whisper/src/mini_whisper/streaming/websocket_engine.py`: buffer-until-open
/// with a 60 s cap, send and receive loops, the end-of-audio gate before a terminal
/// event counts, the drain window, single-shot failure and the 5 s finish handshake.
public final class WebSocketEngine<Adapter: EngineAdapter>: StreamingEngine, @unchecked Sendable {
    public static var maxPreconnectSeconds: TimeInterval { 60 }

    private enum QueueItem: Sendable {
        case chunk([Float], Double)
        case end
    }

    private enum FeedOutcome {
        case drop
        case enqueue
        case overflow
    }

    private struct State {
        var adapter: Adapter
        var sink: (any TranscriptSink)?
        var connection: (any WebSocketConnection)?
        var tasks: [Task<Void, Never>] = []
        var open = false
        var finishing = false
        var endSent = false
        var failed = false
        var bufferedSeconds = 0.0
        var fedSeconds = 0.0
        var inputTokens = 0
        var outputTokens = 0
        var assembler = TranscriptAssembler()
    }

    public let name: EngineName

    private let state: OSAllocatedUnfairLock<State>
    private let clock: any Clock
    private let connect: @Sendable () async throws -> any WebSocketConnection
    private let queue: AsyncStream<QueueItem>
    private let queueContinuation: AsyncStream<QueueItem>.Continuation
    private let done = Latch()
    private let log: LogCategory

    public init(
        adapter: Adapter,
        clock: any Clock = SystemClock(),
        connect: @escaping @Sendable () async throws -> any WebSocketConnection
    ) {
        name = adapter.name
        state = OSAllocatedUnfairLock(initialState: State(adapter: adapter))
        self.clock = clock
        self.connect = connect
        (queue, queueContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        log = Log.stream(adapter.name.rawValue)
    }

    public convenience init(adapter: Adapter, clock: any Clock = SystemClock()) {
        self.init(adapter: adapter, clock: clock) {
            URLSessionWebSocketConnection(url: adapter.url, headers: adapter.headers)
        }
    }

    deinit {
        for task in state.withLock({ $0.tasks }) { task.cancel() }
        queueContinuation.finish()
    }

    // MARK: - StreamingEngine

    public func start(sink: any TranscriptSink) {
        state.withLock { $0.sink = sink }
        let task = Task { await self.run() }
        state.withLock { $0.tasks.append(task) }
    }

    /// Called synchronously on the audio tap thread: copy the samples out and enqueue.
    public func feed(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        let rate = buffer.format.sampleRate
        guard count > 0, rate > 0 else { return }
        let samples = [Float](UnsafeBufferPointer(start: channel, count: count))
        let seconds = Double(count) / rate

        let outcome = state.withLock { state -> FeedOutcome in
            guard !state.failed, !state.finishing else { return .drop }
            state.fedSeconds += seconds
            guard !state.open else { return .enqueue }
            state.bufferedSeconds += seconds
            return state.bufferedSeconds > Self.maxPreconnectSeconds ? .overflow : .enqueue
        }
        switch outcome {
        case .drop:
            return
        case .enqueue:
            queueContinuation.yield(.chunk(samples, rate))
        case .overflow:
            fail(WebSocketEngineError.preconnectCapExceeded(
                engine: name, seconds: Self.maxPreconnectSeconds
            ))
        }
    }

    public func finish(timeout: Duration) async -> StreamResult {
        state.withLock { $0.finishing = true }
        queueContinuation.yield(.end)
        queueContinuation.finish()

        if await !completedBefore(timeout) {
            log.info("finish timeout after \(timeout.seconds)s")
            state.withLock { $0.failed = true }
        }

        let (tasks, connection) = state.withLock { state -> ([Task<Void, Never>], (any WebSocketConnection)?) in
            defer {
                state.tasks = []
                state.connection = nil
            }
            return (state.tasks, state.connection)
        }
        for task in tasks { task.cancel() }
        connection?.close()

        let snapshot = state.withLock { $0 }
        let usage = StreamUsage(
            inputTokens: snapshot.inputTokens,
            outputTokens: snapshot.outputTokens,
            seconds: snapshot.fedSeconds
        )
        guard !snapshot.failed else { return StreamResult(text: "", ok: false, usage: usage) }
        log.info("session finished")
        return StreamResult(text: snapshot.assembler.text, ok: true, usage: usage)
    }

    // MARK: - Session

    private func run() async {
        let connection: any WebSocketConnection
        do {
            connection = try await connect()
        } catch {
            fail(error)
            return
        }
        let openMessages = state.withLock { state -> [WebSocketMessage] in
            state.connection = connection
            state.open = true
            return state.adapter.openMessages()
        }
        log.info("websocket open")

        do {
            for message in openMessages { try await connection.send(message) }
        } catch {
            fail(error)
            connection.close()
            return
        }

        let receiving = Task { await self.receiveLoop(connection) }
        state.withLock { $0.tasks.append(receiving) }
        await sendLoop(connection)
        if state.withLock({ $0.failed }) { receiving.cancel() }
        await receiving.value
        connection.close()
    }

    private func sendLoop(_ connection: any WebSocketConnection) async {
        var converter: PCMConverter?
        var converterRate: Double?

        for await item in queue {
            guard !state.withLock({ $0.failed }) else { return }
            switch item {
            case .end:
                // Flagged before the send, not after: the receive loop runs
                // concurrently, and a server cannot answer a message it has not
                // received yet — so this cannot let an early terminal through.
                let messages = state.withLock { state -> [WebSocketMessage] in
                    state.endSent = true
                    return state.adapter.endMessages()
                }
                do {
                    for message in messages { try await connection.send(message) }
                } catch {
                    fail(error)
                }
                return
            case .chunk(let samples, let rate):
                if converterRate != rate {
                    converter = PCMConverter(from: rate, to: state.withLock { $0.adapter.targetRate })
                    converterRate = rate
                }
                let pcm = converter?.convert(samples) ?? Data()
                guard !pcm.isEmpty else { continue }
                do {
                    try await connection.send(state.withLock { $0.adapter.encodeChunk(pcm) })
                } catch {
                    fail(error)
                    return
                }
            }
        }
    }

    private func receiveLoop(_ connection: any WebSocketConnection) async {
        while !Task.isCancelled {
            let message: WebSocketMessage
            do {
                message = try await connection.receive()
            } catch is CancellationError {
                return
            } catch {
                fail(error)
                return
            }

            let complete: Bool
            do {
                complete = try apply(message)
            } catch {
                fail(error)
                return
            }

            // Terminal only once our end-of-audio message is on the wire; a
            // server-VAD completion processed earlier must not end the loop.
            guard complete, state.withLock({ $0.endSent }) else { continue }
            let window = state.withLock { $0.adapter.drainAfterComplete }
            if window > .zero { await drain(connection, within: window) }
            done.raise()
            return
        }
    }

    /// Scoops events still in flight for up to `window` after the terminal event
    /// (design §5.4).
    private func drain(_ connection: any WebSocketConnection, within window: Duration) async {
        let deadline = clock.now + window.seconds
        while true {
            let remaining = deadline - clock.now
            guard remaining > 0 else { return }
            let received = await withTaskGroup(of: WebSocketMessage?.self) { group in
                group.addTask { try? await connection.receive() }
                group.addTask {
                    try? await self.clock.sleep(for: .seconds(remaining))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            guard let received, (try? apply(received)) != nil else { return }
        }
    }

    private func completedBefore(_ timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.done.wait()
                return true
            }
            group.addTask {
                try? await self.clock.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Hands one server message to the adapter, then applies its emissions to the
    /// compound transcript and the sink in order.
    private func apply(_ message: WebSocketMessage) throws -> Bool {
        typealias Applied = (complete: Bool, sink: (any TranscriptSink)?, emissions: [AdapterEmitter.Emission])
        let applied = try state.withLock { state -> Applied in
            var emitter = AdapterEmitter()
            let complete = try state.adapter.handle(message, emit: &emitter)
            state.inputTokens += emitter.inputTokens
            state.outputTokens += emitter.outputTokens
            for emission in emitter.emissions {
                switch emission {
                case .partial(let text): state.assembler.addPartial(text)
                case .final(let text): state.assembler.addFinal(text)
                }
            }
            return (complete, state.sink, emitter.emissions)
        }
        for emission in applied.emissions {
            switch emission {
            case .partial(let text): applied.sink?.onPartial(text)
            case .final(let text): applied.sink?.onFinal(text)
            }
        }
        return applied.complete
    }

    /// Single-shot: only the first failure reaches the sink, and the sink hears about
    /// it before `finish` is released.
    private func fail(_ error: any Error) {
        let (report, sink) = state.withLock { state -> (Bool, (any TranscriptSink)?) in
            guard !state.failed else { return (false, nil) }
            state.failed = true
            return (true, state.sink)
        }
        guard report else { return }
        log.info("engine failed: \(AnyError(error).description)")
        sink?.onEngineError(error)
        done.raise()
    }
}

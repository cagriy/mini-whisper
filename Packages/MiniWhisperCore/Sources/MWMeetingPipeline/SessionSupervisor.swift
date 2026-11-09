import AVFAudio
import Foundation
import MWConfig
import MWCorrections
import MWMeetings
import MWStreaming
import MWSupport
import os

/// The meeting window's connection chip (design §5.3).
public enum ConnectionState: Sendable, Equatable {
    /// The current session has delivered.
    case connected
    /// The session was lost; `attempt` counts reopens since a session last delivered.
    case reconnecting(attempt: Int)
    /// The next session took over ahead of the provider's session limit.
    case rolledOver
}

public enum SupervisorEvent: Sendable, Equatable {
    /// The current session's in-progress text.
    case partial(String)
    /// `origin` is the meeting time of the session's audio zero; sessions count from 1.
    case segment(TranscriptSegment, session: Int, origin: Double)
    case revision([SpeakerRevision], session: Int)
    case connection(ConnectionState)
    /// Transcript lost to a reconnect, emitted just before the first segment after it.
    case gap(Marker)
}

/// Keeps one provider session open for a meeting (design §5.3, R10, R11).
///
/// - A lost session reopens after 1, 2, 4, 8, 15, then 30 s for as long as it takes. The
///   count resets once a session delivers a partial, a segment or a session limit.
/// - A session limit rolls over: AssemblyAI's `expires_at` 60 s early, a Speechmatics
///   warning at once. The next session takes the audio before the old one finishes.
/// - Audio fed while no session is open is dropped; the recorder still has it.
///
/// `feed` runs on the capture thread and engines call back on their own, so the state sits
/// behind a lock.
public final class SessionSupervisor: Sendable {
    private static let backoff: [Duration] = [1, 2, 4, 8, 15, 30].map { .seconds($0) }
    private static let rolloverLead: Duration = .seconds(60)
    private static let finishTimeout: Duration = .seconds(5)
    private static let gapReason = "connection lost"

    private struct Session {
        let index: Int
        let engine: any StreamingEngine
        var delivered = false
    }

    private struct State {
        var running = false
        /// The session audio goes to; nil while closed or waiting to reconnect.
        var current: Session?
        var nextIndex = 1
        var attempt = 0
        var gapPending = false
        /// Meeting time of the last `open(at:)`; no gap starts before it.
        var openedAt = 0.0
        var lastSegmentEnd: Double?
        /// Meeting time of each session's first fed buffer.
        var origins: [Int: Double] = [:]
        var timer: Task<Void, Never>?
        var timerToken: UInt64 = 0
        /// Retired sessions still finishing, by index.
        var finishing: [Int: Task<Void, Never>] = [:]
    }

    public let events: AsyncStream<SupervisorEvent>
    private let continuation: AsyncStream<SupervisorEvent>.Continuation
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let provider: any MeetingEngineProviding
    private let meetingEngine: MeetingEngine
    private let key: String
    private let hints: RecognitionHints
    private let clock: any Clock
    private let now: @Sendable () -> Date

    /// `now` is the wall clock that AssemblyAI's `expires_at` is compared with.
    public init(
        provider: any MeetingEngineProviding,
        engine: MeetingEngine,
        key: String,
        hints: RecognitionHints,
        clock: any Clock,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        meetingEngine = engine
        self.key = key
        self.hints = hints
        self.clock = clock
        self.now = now
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    deinit {
        state.withLock { $0.timer?.cancel() }
        continuation.finish()
    }

    /// Opens a new session at meeting time `time`; ignored while already open.
    public func open(at time: Double) {
        let session = state.withLock { state -> Session? in
            guard !state.running else { return nil }
            state.running = true
            state.attempt = 0
            state.gapPending = false
            state.openedAt = time
            return install(&state)
        }
        if let session { begin(session) }
    }

    /// Called on the capture thread with the meeting time of the buffer's first sample.
    /// Returns false when no session took the buffer, so it is not billed.
    @discardableResult
    public func feed(_ buffer: AVAudioPCMBuffer, at time: Double) -> Bool {
        let engine = state.withLock { state -> (any StreamingEngine)? in
            guard let current = state.current else { return nil }
            if state.origins[current.index] == nil { state.origins[current.index] = time }
            return current.engine
        }
        engine?.feed(buffer)
        return engine != nil
    }

    /// Stops reconnecting and finishes the open session, and any still draining after a
    /// rollover, allowing each 5 s. Segments they drain are still emitted.
    public func close() async {
        let (current, draining) = state.withLock { state -> (Session?, [Task<Void, Never>]) in
            let current = state.current
            state.current = nil
            state.running = false
            state.gapPending = false
            cancelTimer(&state)
            return (current, Array(state.finishing.values))
        }
        if let current {
            _ = await current.engine.finish(timeout: Self.finishTimeout)
            Log.meeting.info("session \(current.index) closed")
        }
        for task in draining { await task.value }
    }

    // MARK: - Session callbacks

    fileprivate func received(partial text: String, from index: Int) {
        state.withLock { state in
            guard state.current?.index == index else { return }
            markDelivered(&state)
            continuation.yield(.partial(text))
        }
    }

    fileprivate func received(_ segment: TranscriptSegment, from index: Int) {
        state.withLock { state in
            let origin = state.origins[index] ?? state.openedAt
            if state.current?.index == index {
                markDelivered(&state)
                if state.gapPending {
                    state.gapPending = false
                    let start = max(state.lastSegmentEnd ?? state.openedAt, state.openedAt)
                    let end = origin + segment.start
                    if end > start {
                        continuation.yield(.gap(Marker(kind: .gap, start: start, end: end, reason: Self.gapReason)))
                    }
                }
            }
            state.lastSegmentEnd = max(state.lastSegmentEnd ?? 0, origin + segment.end)
            continuation.yield(.segment(segment, session: index, origin: origin))
        }
    }

    fileprivate func received(_ revisions: [SpeakerRevision], from index: Int) {
        continuation.yield(.revision(revisions, session: index))
    }

    fileprivate func received(_ limit: SessionLimit, from index: Int) {
        let lead: Duration? = {
            guard case .expiresAt(let date) = limit else { return nil }
            let remaining = date.timeIntervalSince(now()) - Self.rolloverLead.seconds
            return remaining > 0 ? .seconds(remaining) : nil
        }()
        let rolled = state.withLock { state -> (old: Int, new: Session)? in
            guard state.current?.index == index else { return nil }
            markDelivered(&state)
            guard let lead else { return replaceCurrent(&state) }
            schedule(&state, after: lead) { supervisor, token in
                supervisor.rollOver(from: index, token: token)
            }
            return nil
        }
        if let rolled { beginRollover(rolled, cause: limit == .warning ? "warning" : "expires_at") }
    }

    fileprivate func failed(_ error: any Error, from index: Int) {
        let cause = Self.cause(of: error)
        let note = state.withLock { state -> String? in
            guard let current = state.current, current.index == index else { return nil }
            cancelTimer(&state)
            state.current = nil
            retire(current, &state)
            state.attempt += 1
            state.gapPending = true
            let delay = Self.backoff[min(state.attempt, Self.backoff.count) - 1]
            schedule(&state, after: delay) { supervisor, token in supervisor.reopen(token: token) }
            continuation.yield(.connection(.reconnecting(attempt: state.attempt)))
            return "session \(index) lost (\(cause)); reconnect attempt \(state.attempt) in \(Int(delay.seconds)) s"
        }
        if let note { Log.meeting.info(note) }
    }

    // MARK: - Under the lock

    private func install(_ state: inout State) -> Session {
        let session = Session(
            index: state.nextIndex,
            engine: provider.makeMeeting(meetingEngine, key: key, hints: hints)
        )
        state.nextIndex += 1
        state.current = session
        return session
    }

    /// Installs the next session in the current one's place and retires the old one.
    private func replaceCurrent(_ state: inout State) -> (old: Int, new: Session)? {
        guard let old = state.current else { return nil }
        cancelTimer(&state)
        let new = install(&state)
        retire(old, &state)
        continuation.yield(.connection(.rolledOver))
        return (old.index, new)
    }

    private func retire(_ session: Session, _ state: inout State) {
        // Registered under the lock, so the removal below cannot run first.
        state.finishing[session.index] = Task { [weak self] in
            _ = await session.engine.finish(timeout: Self.finishTimeout)
            self?.state.withLock { _ = $0.finishing.removeValue(forKey: session.index) }
        }
    }

    private func markDelivered(_ state: inout State) {
        guard state.current?.delivered == false else { return }
        state.current?.delivered = true
        state.attempt = 0
        continuation.yield(.connection(.connected))
    }

    private func schedule(
        _ state: inout State,
        after delay: Duration,
        _ fire: @escaping @Sendable (SessionSupervisor, UInt64) -> Void
    ) {
        cancelTimer(&state)
        let token = state.timerToken
        state.timer = Task { [weak self, clock] in
            guard (try? await clock.sleep(for: delay)) != nil, let self else { return }
            fire(self, token)
        }
    }

    private func cancelTimer(_ state: inout State) {
        state.timer?.cancel()
        state.timer = nil
        state.timerToken &+= 1
    }

    // MARK: - Outside the lock

    /// Starts an installed session; an engine may call its sink back at once.
    private func begin(_ session: Session, note: String = "") {
        Log.meeting.info("session \(session.index) open\(note)")
        session.engine.start(sink: SessionSink(index: session.index, supervisor: self))
    }

    private func beginRollover(_ rolled: (old: Int, new: Session), cause: String) {
        Log.meeting.info("session \(rolled.old) rolled over to session \(rolled.new.index) (\(cause))")
        begin(rolled.new)
    }

    private func reopen(token: UInt64) {
        let opened = state.withLock { state -> (Session, Int)? in
            guard state.running, state.timerToken == token, state.current == nil else { return nil }
            state.timer = nil
            return (install(&state), state.attempt)
        }
        guard let (session, attempt) = opened else { return }
        begin(session, note: " (reconnect attempt \(attempt))")
    }

    private func rollOver(from index: Int, token: UInt64) {
        let rolled = state.withLock { state -> (old: Int, new: Session)? in
            guard state.timerToken == token, state.current?.index == index else { return nil }
            state.timer = nil
            return replaceCurrent(&state)
        }
        if let rolled { beginRollover(rolled, cause: "expires_at") }
    }

    /// A failure as a log may state it: a close code, or an error's domain and code — never
    /// a message, which could carry provider or transcript text (R27).
    private static func cause(of error: any Error) -> String {
        if case .closed(let code, _)? = error as? WebSocketConnectionError { return "close code \(code)" }
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

/// One session's sink: tags each callback with the session's index, so a session already
/// rolled over or lost still lands its late segments under the right index.
private final class SessionSink: TranscriptSink {
    let index: Int
    weak let supervisor: SessionSupervisor?

    init(index: Int, supervisor: SessionSupervisor) {
        self.index = index
        self.supervisor = supervisor
    }

    func onPartial(_ text: String) { supervisor?.received(partial: text, from: index) }
    /// Meetings take their text from `onSegment`, which arrives beside every final.
    func onFinal(_ text: String) {}
    func onEngineError(_ error: any Error) { supervisor?.failed(error, from: index) }
    func onSegment(_ segment: TranscriptSegment) { supervisor?.received(segment, from: index) }
    func onSpeakerRevision(_ revisions: [SpeakerRevision]) { supervisor?.received(revisions, from: index) }
    func onSessionLimit(_ limit: SessionLimit) { supervisor?.received(limit, from: index) }
}

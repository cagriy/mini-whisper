import Foundation
import MWAudio
import MWConfig
import MWCorrections
import MWMeetings
import MWStreaming
import MWSupport
import MWUsage

/// One meeting from Start to its summary (design §5.3, §5.6): capture held open with voice
/// processing, the system-audio tap in a remote call, one supervised provider session, and
/// every segment attributed, stored and emitted as it arrives. One controller per window.
@MainActor
public final class MeetingController {
    static let noSummaryKey = "No summary: add an Anthropic key under Keys."
    static let nothingTranscribed = "Nothing was transcribed."
    private static let tick = Duration.seconds(1)
    /// Lost audio longer than this is marked as a transcript gap (design §5.6 Device change).
    private static let gapThreshold = 2.0
    private static let silenceHintAfter = 60.0
    /// −60 dBFS.
    private static let audibleSystemPeak: Float = 0.001

    public nonisolated let events: AsyncStream<MeetingEvent>
    public private(set) var state: MeetingState = .idle
    /// The meeting as last written to `meeting.json`, plus markers since.
    public private(set) var meeting: Meeting?
    public var isActive: Bool { state.isActive }

    private nonisolated let continuation: AsyncStream<MeetingEvent>.Continuation
    private let deps: MeetingDependencies
    private let configStore: ConfigStore
    private let log = Log.meeting

    private var segments: [Segment] = []
    /// `segments[..<savedCount]` are in `segments.jsonl` as they stand.
    private var savedCount = 0
    /// An earlier segment changed, so the whole file is rewritten.
    private var needsRewrite = false
    private var writingSegments = false
    private var writeFailed = false
    private var notes: [Note] = []
    private var registry = SpeakerRegistry(labels: [])
    private var tallies: [String: SpeakerAttributor.Tally] = [:]
    /// Input device changes the open session did not hear: its audio from `at` on belongs `by`
    /// seconds later.
    private var shifts: [(at: Double, by: Double)] = []
    /// Index in `meeting.markers` of the pause not yet resumed.
    private var openPause: Int?
    /// The tap was heard, or the silence hint shown.
    private var systemAudioSettled = false
    private var supervisor: SessionSupervisor?
    private var audioPath: MeetingAudioPath?
    private var tap: (any SystemAudioTapping)?
    /// `deps.clock` reading at meeting second 0.
    private var clockOrigin: TimeInterval = 0
    private var sessionEvents: Task<Void, Never>?
    private var captureEvents: Task<Void, Never>?
    private var tapEvents: Task<Void, Never>?
    /// The pause's session close; Resume waits for it so the new session is not closed with it.
    private var closing: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var summarising = false

    public init(deps: MeetingDependencies, config: ConfigStore) {
        self.deps = deps
        configStore = config
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Start

    /// Design §5.6 Start. Throws `MeetingError.noEngineKey` without a Speechmatics or
    /// AssemblyAI key, or the capture or storage error that kept the meeting from starting.
    public func start(mode: MeetingMode, title: String) async throws {
        guard state == .idle else { return }
        let config = await configStore.load()
        guard let engine = MeetingEngine.resolve(stored: config.meetingEngine, hasKey: { self.secret($0) != nil }),
              let key = secret(engine.keyAccount)
        else { throw MeetingError.noEngineKey }
        setState(.starting)

        let userName = config.meetingUserName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? deps.userName()
        registry = SpeakerRegistry(userName: userName)
        let meeting = Meeting(
            title: title, startedAt: deps.now(), mode: mode, app: deps.frontAppName(), engine: engine,
            userName: userName, speakers: registry.labels
        )
        let supervisor = SessionSupervisor(
            provider: deps.engines,
            engine: engine,
            key: key,
            hints: HintResolver.resolve(CorrectionSnapshot(config: config), bundleID: nil),
            clock: deps.clock,
            now: deps.now
        )
        var created = false
        var held = false
        do {
            try await deps.store.create(meeting)
            created = true
            let recorder = try config.meetingKeepAudio
                ? MeetingRecorder(writer: deps.makeAudioWriter(deps.store.audioURL(meeting.id)))
                : nil
            let audioPath = MeetingAudioPath(
                mode: mode,
                recorder: recorder,
                billing: MeetingBilling(engine: engine, overrides: config.pricingOverrides),
                supervisor: supervisor
            )
            await deps.audio.holdRunning(true)
            held = true
            do {
                try await deps.audio.setVoiceProcessing(true)
            } catch {
                log.warning("voice processing unavailable: \(AnyError(error).description)")
            }
            try await deps.audio.ensureRunning()
            supervisor.open(at: 0)
            clockOrigin = deps.clock.now
            await deps.audio.attachMeetingListener(audioPath)
            self.audioPath = audioPath
        } catch {
            if held { await releaseCapture(idleStopSeconds: config.idleStopSeconds) }
            if created { try? await deps.store.delete(meeting.id) }
            setState(.idle)
            throw error
        }

        self.meeting = meeting
        self.supervisor = supervisor
        sessionEvents = Task { [weak self, events = supervisor.events] in
            for await event in events { await self?.handle(event) }
        }
        captureEvents = Task { [weak self, events = deps.audio.meetingEvents] in
            for await event in events { await self?.handle(event) }
        }
        if mode == .remote { startTap() }
        emit(.speakers(registry.labels))
        log.info("meeting started: \(mode.rawValue), \(engine.rawValue)")
        setState(.recording)
        startTicker()
        if mode == .remote, !config.meetingSystemAudioExplained {
            do {
                try await configStore.update { @Sendable config in config.meetingSystemAudioExplained = true }
            } catch {
                log.warning("meeting_system_audio_explained not saved: \(AnyError(error).description)")
            }
        }
    }

    /// Microphone-only when the system cannot tap (below 14.2) or the tap fails to start.
    private func startTap() {
        guard let tap = deps.tapFactory.make(excluding: ProcessInfo.processInfo.processIdentifier) else {
            emit(.systemAudio(.unavailable("needs macOS 14.2")))
            return
        }
        do {
            try tap.start { [audioPath, clock = deps.clock, origin = clockOrigin] buffer in
                audioPath?.pushSystem(buffer, at: clock.now - origin)
            }
            self.tap = tap
            tapEvents = Task { [weak self, events = tap.events] in
                for await event in events { self?.handle(event) }
            }
            emit(.systemAudio(.on))
        } catch {
            let reason = AnyError(error).description
            log.warning("system audio unavailable: \(reason)")
            emit(.systemAudio(.unavailable(reason)))
        }
    }

    // MARK: - Session events

    private func handle(_ event: SupervisorEvent) async {
        switch event {
        case .partial(let text):
            emit(.partial(text, speaker: audioPath?.isSpeakingNow == true ? SpeakerRegistry.userID : nil))
        case .segment(let segment, let session, let origin):
            await add(segment, session: session, origin: origin)
        case .revision(let revisions, let session):
            await revise(revisions, session: session)
        case .connection(let connection):
            emit(.connection(connection))
        case .gap(let marker):
            addMarker(marker)
        }
    }

    /// Design §5.6 Segment arrives: into meeting time, split between the user and the provider
    /// speaker, appended to `segments.jsonl`, emitted.
    private func add(_ segment: TranscriptSegment, session: Int, origin: Double) async {
        guard let meeting else { return }
        var shifted = segment
        shifted.start = meetingTime(segment.start, origin: origin)
        shifted.end = meetingTime(segment.end, origin: origin)
        shifted.words = segment.words.map {
            TranscriptWord(text: $0.text, start: meetingTime($0.start, origin: origin), end: meetingTime($0.end, origin: origin))
        }
        let attribution = SpeakerAttributor.attribute(
            shifted, session: session, mode: meeting.mode, spans: audioPath?.gateView ?? SpeechGate.View(),
            registry: registry, tallies: tallies
        )
        let speakersChanged = attribution.registry.labels != registry.labels
        registry = attribution.registry
        tallies = attribution.tallies
        if speakersChanged { emit(.speakers(registry.labels)) }
        segments += attribution.segments
        await persistSegments()
        for segment in attribution.segments { emit(.segmentAdded(segment)) }
    }

    /// A session's time in meeting seconds: its origin, plus every input device change it did
    /// not hear.
    private func meetingTime(_ offset: Double, origin: Double) -> Double {
        var time = origin + offset
        for shift in shifts where origin < shift.at && time >= shift.at {
            time += shift.by
        }
        return time
    }

    private func revise(_ revisions: [SpeakerRevision], session: Int) async {
        let labels = registry.labels
        let changed = Self.revise(&segments, with: revisions, session: session, registry: &registry)
        guard !changed.isEmpty else { return }
        if registry.labels != labels { emit(.speakers(registry.labels)) }
        needsRewrite = true
        await persistSegments()
        for index in changed { emit(.segmentUpdated(segments[index])) }
    }

    /// Design §3 R11: a revision re-labels one turn of one session. Pinned segments, and words
    /// the gate gave the user out of another speaker's turn, keep their speaker. Returns the
    /// indices changed.
    nonisolated static func revise(
        _ segments: inout [Segment],
        with revisions: [SpeakerRevision],
        session: Int,
        registry: inout SpeakerRegistry
    ) -> [Int] {
        var changed: [Int] = []
        for revision in revisions {
            for index in segments.indices {
                let segment = segments[index]
                guard segment.session == session, segment.turnOrder == revision.turnOrder, !segment.pinned,
                      segment.providerLabel != revision.speaker,
                      segment.speaker == registry.id(session: session, label: segment.providerLabel)
                else { continue }
                segments[index].providerLabel = revision.speaker
                segments[index].speaker = registry.resolve(session: session, label: revision.speaker)
                changed.append(index)
            }
        }
        return changed
    }

    // MARK: - Capture and tap events

    private func handle(_ event: MeetingAudioEvent) async {
        switch event {
        case .systemWillSleep:
            await pause(.sleep)
        case .deviceChanged:
            await inputDeviceChanged()
        }
    }

    /// Design §5.6 Device change: the engine restarted on the new input; the buffers it missed
    /// are lost meeting time.
    private func inputDeviceChanged() async {
        guard state == .recording || state.isPaused, let audioPath else { return }
        do {
            try await deps.audio.ensureRunning()
        } catch {
            log.error("capture not restarted: \(AnyError(error).description)")
        }
        do {
            try await deps.audio.setVoiceProcessing(true)
        } catch {
            log.warning("voice processing unavailable: \(AnyError(error).description)")
        }
        let now = meetingTime
        let from = audioPath.catchUp(to: now)
        guard state == .recording, now > from else { return }
        shifts.append((at: from, by: now - from))
        log.info("input device changed: \(String(format: "%.1f", now - from)) s lost")
        if now - from > Self.gapThreshold {
            addMarker(Marker(kind: .gap, start: from, end: now, reason: "input device changed"))
        }
    }

    private func handle(_ event: SystemAudioTapEvent) {
        switch event {
        case .defaultOutputChanged:
            guard state == .recording, let from = audioPath?.lastSystemAudio else { return }
            let now = meetingTime
            if now - from > Self.gapThreshold {
                addMarker(Marker(kind: .gap, start: from, end: now, reason: "output device changed"))
            }
        case .stopped(let error):
            tap?.stop()
            tap = nil
            let reason = AnyError(error).description
            log.warning("system audio stopped: \(reason)")
            emit(.systemAudio(.unavailable(reason)))
        }
    }

    // MARK: - Ticker

    /// Meeting seconds now, paused spans included.
    private var meetingTime: Double { deps.clock.now - clockOrigin }

    private func startTicker() {
        ticker = Task { [weak self, clock = deps.clock] in
            while true {
                do { try await clock.sleep(for: Self.tick) } catch { return }
                guard let self else { return }
                checkSystemAudio()
                emit(.elapsed(meetingTime))
                emit(.cost(audioPath?.billing.liveCost ?? 0))
            }
        }
    }

    /// Design §5.6 Silence hint: a tap that stays silent through a minute in which the user
    /// spoke most likely lacks the System Audio Recording permission.
    private func checkSystemAudio() {
        guard !systemAudioSettled, tap != nil, let audioPath else { return }
        if audioPath.systemPeakSinceLastCall() > Self.audibleSystemPeak {
            systemAudioSettled = true
        } else if meetingTime >= Self.silenceHintAfter, !audioPath.gateView.spans.isEmpty {
            systemAudioSettled = true
            emit(.systemAudio(.silentHint))
        }
    }

    // MARK: - Pause

    public func pause() async {
        await pause(.user)
    }

    /// Design §5.6 Pause: the session closes; capture and the tap keep running.
    private func pause(_ reason: PauseReason) async {
        guard state == .recording, let audioPath else { return }
        let time = audioPath.pause()
        setState(.paused(reason))
        openPause = meeting?.markers.count
        addMarker(Marker(kind: reason == .sleep ? .sleep : .paused, start: time, end: time))
        let supervisor = supervisor
        closing = Task { await supervisor?.close() }
        log.info("meeting paused (\(reason == .sleep ? "sleep" : "user"))")
        await saveMeeting()
        await closing?.value
    }

    /// Design §5.6 Resume: silence fills the paused span of the audio file and a new session opens.
    public func resume() async {
        await closing?.value
        guard state.isPaused, let audioPath, let supervisor else { return }
        audioPath.catchUp(to: meetingTime)
        let time = audioPath.resume()
        closePause(at: time)
        supervisor.open(at: time)
        setState(.recording)
        log.info("meeting resumed")
        await saveMeeting()
    }

    private func closePause(at time: Double) {
        guard let index = openPause, var marker = meeting?.markers[index] else { return }
        openPause = nil
        marker.end = time
        meeting?.markers[index] = marker
        emit(.marker(marker))
    }

    private func addMarker(_ marker: Marker) {
        meeting?.markers.append(marker)
        emit(.marker(marker))
    }

    // MARK: - Stop

    /// Design §5.6 Stop. `summarise: false` is the quit path; the summary can be asked for later.
    public func stop(summarise: Bool = true) async {
        guard state == .recording || state.isPaused, let audioPath else { return }
        setState(.stopping)
        for task in [ticker, captureEvents, tapEvents] { task?.cancel() }
        ticker = nil
        captureEvents = nil
        tapEvents = nil
        let endedAt = deps.now()
        let duration = meetingTime
        if openPause != nil {
            audioPath.catchUp(to: duration)
            closePause(at: audioPath.time)
        }
        let config = await configStore.load()

        await supervisor?.close()
        tap?.stop()
        tap = nil
        await releaseCapture(idleStopSeconds: config.idleStopSeconds)
        // Its event stream finishes once it is released, after every drained segment.
        supervisor = nil
        closing = nil
        await sessionEvents?.value
        sessionEvents = nil
        let billing = audioPath.billing
        audioPath.finish()
        self.audioPath = nil
        await persistSegments()

        meeting?.endedAt = endedAt
        meeting?.durationSeconds = duration
        meeting?.billing = billing.totals
        meeting?.speakers = registry.labels
        await saveMeeting()
        if billing.engineSeconds > 0 { await addUsage(billing.finalUsage()) }
        log.info("meeting stopped after \(Int(duration)) s")
        setState(.stopped)
        if summarise { await self.summarise() }
    }

    /// Releasing the hold schedules nothing, so the idle stop is armed here or the
    /// microphone would stay open.
    private func releaseCapture(idleStopSeconds: Int) async {
        await deps.audio.attachMeetingListener(nil)
        await deps.audio.holdRunning(false)
        do {
            try await deps.audio.setVoiceProcessing(false)
        } catch {
            log.warning("voice processing not turned off: \(AnyError(error).description)")
        }
        await deps.audio.scheduleIdleStop(after: .seconds(Double(idleStopSeconds)))
    }

    // MARK: - Speakers, notes and edits

    /// Design §5.6 Rename: onto another speaker's name the two merge.
    public func rename(speaker id: Int, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard meeting != nil, !name.isEmpty else { return }
        let labels = registry.labels
        let merge = registry.rename(id, to: name)
        guard registry.labels != labels else { return }
        var changed: [Int] = []
        if let merge {
            for index in segments.indices where segments[index].speaker == merge.from {
                segments[index].speaker = merge.into
                changed.append(index)
            }
        }
        if !changed.isEmpty {
            needsRewrite = true
            await persistSegments()
        }
        meeting?.speakers = registry.labels
        await saveMeeting()
        for index in changed { emit(.segmentUpdated(segments[index])) }
        emit(.speakers(registry.labels))
    }

    /// `time` is the meeting second of the note's first keystroke.
    public func addNote(_ text: String, firstKeystrokeAt time: Double) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = meeting?.id, !text.isEmpty else { return }
        let note = Note(time: time, text: text, createdAt: deps.now())
        notes.append(note)
        do {
            try await deps.store.append(note, to: id)
        } catch {
            log.error("note not written: \(AnyError(error).description)")
        }
        emit(.note(note))
    }

    /// After Stop only.
    public func edit(segment id: UUID, text: String) async {
        await change(segment: id) {
            $0.text = text
            $0.edited = true
        }
    }

    /// After Stop only; a pinned segment keeps its speaker through later revisions.
    public func reassign(segment id: UUID, to speaker: Int) async {
        guard registry.labels.contains(where: { $0.id == speaker }) else { return }
        await change(segment: id) {
            $0.speaker = speaker
            $0.pinned = true
        }
    }

    private func change(segment id: UUID, _ apply: (inout Segment) -> Void) async {
        guard state == .stopped, let index = segments.firstIndex(where: { $0.id == id }) else { return }
        var segment = segments[index]
        apply(&segment)
        guard segment != segments[index] else { return }
        segments[index] = segment
        needsRewrite = true
        await persistSegments()
        emit(.segmentUpdated(segment))
    }

    /// Design §3 R15: the header rename, while recording or after.
    public func retitle(_ title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, meeting != nil, meeting?.title != title else { return }
        meeting?.title = title
        await saveMeeting()
    }

    // MARK: - Stored meetings

    /// A stored meeting, into `.stopped` for reading, editing and a later summary
    /// (*Planning decisions taken* #22).
    public func open(_ id: UUID) async throws {
        guard state == .idle else { return }
        let loaded = try deps.store.load(id)
        meeting = loaded.meeting
        segments = loaded.segments
        savedCount = segments.count
        notes = loaded.notes
        registry = SpeakerRegistry(labels: loaded.meeting.speakers)
        emit(.speakers(registry.labels))
        loaded.meeting.markers.forEach { emit(.marker($0)) }
        segments.forEach { emit(.segmentAdded($0)) }
        notes.forEach { emit(.note($0)) }
        if let summary = loaded.meeting.summary { emit(.summary(.ready(summary))) }
        setState(.stopped)
    }

    // MARK: - Summary

    /// Design §5.6 Summarise; does nothing once the meeting has a summary.
    public func summarise() async {
        guard state == .stopped, !summarising, let meeting, meeting.summary == nil else { return }
        guard !segments.isEmpty else { return emit(.summary(.none(Self.nothingTranscribed))) }
        guard secret(.anthropic) != nil else { return emit(.summary(.none(Self.noSummaryKey))) }
        summarising = true
        defer { summarising = false }
        emit(.summary(.writing))
        let summariser = Summariser(
            prompts: deps.prompts,
            client: deps.summarizer,
            overrides: await configStore.load().pricingOverrides,
            now: deps.now
        )
        do {
            switch try await summariser.run(LoadedMeeting(meeting: meeting, segments: segments, notes: notes)) {
            case .ready(let summary):
                self.meeting?.summary = summary
                await saveMeeting()
                await addUsage(ProviderUsage(
                    inputTokens: summary.inputTokens, outputTokens: summary.outputTokens, costUSD: summary.costUSD
                ))
                emit(.summary(.ready(summary)))
            case .declined(let category):
                emit(.summary(.failed("Summary declined (\(category))")))
            case .empty:
                emit(.summary(.none(Self.nothingTranscribed)))
            }
        } catch {
            let reason = AnyError(error).description
            log.warning("summary failed: \(reason)")
            emit(.summary(.failed(reason)))
        }
    }

    // MARK: - Persistence

    /// Brings `segments.jsonl` up to date: a rewrite after a change, else appends of the
    /// segments not yet in it. A failure keeps them in memory for the next try (design §5.7).
    private func persistSegments() async {
        guard let id = meeting?.id, !writingSegments else { return }
        writingSegments = true
        defer { writingSegments = false }
        while needsRewrite || savedCount < segments.count {
            do {
                if needsRewrite {
                    needsRewrite = false
                    let all = segments
                    do {
                        try await deps.store.rewriteSegments(all, of: id)
                    } catch {
                        needsRewrite = true
                        throw error
                    }
                    savedCount = all.count
                } else {
                    try await deps.store.append(segments[savedCount], to: id)
                    savedCount += 1
                }
            } catch {
                let reason = AnyError(error).description
                log.error("segments not written: \(reason)")
                if !writeFailed {
                    writeFailed = true
                    let detail = isActive ? "; recording continues in memory" : ""
                    emit(.error("Could not write the transcript (\(reason))\(detail)"))
                }
                return
            }
        }
        writeFailed = false
    }

    private func saveMeeting() async {
        guard let meeting else { return }
        do {
            try await deps.store.update(meeting)
        } catch {
            log.error("meeting.json not written: \(AnyError(error).description)")
        }
    }

    private func addUsage(_ usage: ProviderUsage) async {
        do {
            try await deps.usage.add(usage)
        } catch {
            log.warning("usage not recorded: \(AnyError(error).description)")
        }
    }

    /// The stored key, when there is a non-empty one.
    private func secret(_ account: KeyAccount) -> String? {
        guard let secret = try? deps.secrets.secret(for: account), !secret.isEmpty else { return nil }
        return secret
    }

    private func setState(_ state: MeetingState) {
        self.state = state
        emit(.state(state))
    }

    private func emit(_ event: MeetingEvent) {
        continuation.yield(event)
    }
}

extension MeetingState {
    /// A meeting holds the microphone: dictation stays locked out and Quit asks first.
    public var isActive: Bool {
        switch self {
        case .starting, .recording, .paused, .stopping: true
        case .idle, .stopped: false
        }
    }

    var isPaused: Bool {
        if case .paused = self { true } else { false }
    }
}

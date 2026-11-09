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

    public nonisolated let events: AsyncStream<MeetingEvent>
    public private(set) var state: MeetingState = .idle
    /// The meeting as last written to `meeting.json`, plus markers since.
    public private(set) var meeting: Meeting?

    private nonisolated let continuation: AsyncStream<MeetingEvent>.Continuation
    private let deps: MeetingDependencies
    private let configStore: ConfigStore
    private let log = Log.meeting

    private var segments: [Segment] = []
    private var notes: [Note] = []
    private var registry = SpeakerRegistry(labels: [])
    private var tallies: [String: SpeakerAttributor.Tally] = [:]
    private var supervisor: SessionSupervisor?
    private var audioPath: MeetingAudioPath?
    private var tap: (any SystemAudioTapping)?
    /// `deps.clock` reading at meeting second 0.
    private var clockOrigin: TimeInterval = 0
    private var sessionEvents: Task<Void, Never>?
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
            try tap.start { [audioPath] buffer in audioPath?.pushSystem(buffer) }
            self.tap = tap
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
        case .revision:
            break
        case .connection(let connection):
            emit(.connection(connection))
        case .gap(let marker):
            meeting?.markers.append(marker)
            emit(.marker(marker))
        }
    }

    /// Design §5.6 Segment arrives: into meeting time, split between the user and the provider
    /// speaker, appended to `segments.jsonl`, emitted.
    private func add(_ segment: TranscriptSegment, session: Int, origin: Double) async {
        guard let meeting else { return }
        var shifted = segment
        shifted.start += origin
        shifted.end += origin
        shifted.words = segment.words.map { TranscriptWord(text: $0.text, start: $0.start + origin, end: $0.end + origin) }
        let attribution = SpeakerAttributor.attribute(
            shifted, session: session, mode: meeting.mode, spans: audioPath?.gateView ?? SpeechGate.View(),
            registry: registry, tallies: tallies
        )
        let speakersChanged = attribution.registry.labels != registry.labels
        registry = attribution.registry
        tallies = attribution.tallies
        if speakersChanged { emit(.speakers(registry.labels)) }
        for segment in attribution.segments {
            segments.append(segment)
            do {
                try await deps.store.append(segment, to: meeting.id)
            } catch {
                log.error("segment not written: \(AnyError(error).description)")
            }
            emit(.segmentAdded(segment))
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
                emit(.elapsed(meetingTime))
                emit(.cost(audioPath?.billing.liveCost ?? 0))
            }
        }
    }

    // MARK: - Stop

    /// Design §5.6 Stop. `summarise: false` is the quit path; the summary can be asked for later.
    public func stop(summarise: Bool = true) async {
        guard state == .recording || state.isPaused, let audioPath else { return }
        setState(.stopping)
        ticker?.cancel()
        ticker = nil
        let endedAt = deps.now()
        let duration = meetingTime
        let config = await configStore.load()

        await supervisor?.close()
        tap?.stop()
        tap = nil
        await releaseCapture(idleStopSeconds: config.idleStopSeconds)
        // Its event stream finishes once it is released, after every drained segment.
        supervisor = nil
        await sessionEvents?.value
        sessionEvents = nil
        let billing = audioPath.billing
        audioPath.finish()
        self.audioPath = nil

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

    // MARK: - Helpers

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
    var isPaused: Bool {
        if case .paused = self { true } else { false }
    }
}

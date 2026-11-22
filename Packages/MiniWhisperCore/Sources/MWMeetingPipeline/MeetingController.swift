import Foundation
import MWAudio
import MWConfig
import MWCorrections
import MWMeetings
import MWNaming
import MWStreaming
import MWSupport
import MWTestCall
import MWUsage
import MWVoices

/// One meeting from Start to its summary (design §5.3, §5.6): capture held open with voice
/// processing, the system-audio tap in a remote call, one supervised provider session, and
/// every segment attributed, stored and emitted as it arrives. One controller per window.
@MainActor
public final class MeetingController {
    static let noSummaryKey = "No summary: add an Anthropic key under Keys."
    public static let nothingTranscribed = "Nothing was transcribed."
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
    /// The time each segment of a test meeting was appended, in meeting seconds (design R17).
    public private(set) var segmentArrivals: [UUID: Double] = [:]
    /// The meeting time of the latest one-second tick whose system audio was audible.
    public private(set) var lastAudibleSystemAudio: Double?

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
    /// Nil for a test call: its conductor stops it.
    private var silence: SilenceWatch?
    /// A `.silence(.open)` was emitted since the last close or expiry.
    private var promptShown = false
    /// Nil unless the meeting's voice route is active (design v8 R2).
    private var voice: MeetingVoiceRoute?

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
    /// A test call gives its `engine`, used in place of the configured one, and its `test` tag.
    public func start(
        mode: MeetingMode, title: String, engine given: MeetingEngine? = nil, test: TestCallTag? = nil
    ) async throws {
        guard state == .idle else { return }
        let config = await configStore.load()
        guard let engine = given ?? MeetingEngine.resolve(stored: config.meetingEngine, hasKey: { self.secret($0) != nil }),
              let key = secret(engine.keyAccount)
        else { throw MeetingError.noEngineKey }
        setState(.starting)

        let userName = config.meetingUserName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? deps.userName()
        registry = SpeakerRegistry(userName: userName)
        let meeting = Meeting(
            title: title, startedAt: deps.now(), mode: mode, app: deps.frontAppName(), engine: engine,
            userName: userName, speakers: registry.labels, test: test, titleByUser: false
        )
        let voice = await MeetingVoiceRoute.live(
            deps.voices, engine: engine, mode: mode, meeting: meeting.id, isTest: test != nil, settings: config.voice,
            now: deps.now
        ) { [configStore] in await configStore.load().voice }
        // Typed apart: a closure literal beside `??` here crashes the type checker.
        let noEnrolment: @Sendable () -> VoiceSessionConfig? = { nil }
        let enrolment = voice?.sessionVoices ?? noEnrolment
        let supervisor = SessionSupervisor(
            provider: deps.engines,
            engine: engine,
            key: key,
            hints: HintResolver.resolve(CorrectionSnapshot(config: config), bundleID: nil),
            clock: deps.clock,
            now: deps.now,
            voices: enrolment
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
                supervisor: supervisor,
                voices: voice?.buffers
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
        self.voice = voice
        silence = test == nil ? SilenceWatch(threshold: config.meetingSilenceStopSeconds) : nil
        sessionEvents = Task { [weak self, events = supervisor.events] in
            for await event in events { await self?.handle(event) }
        }
        captureEvents = Task { [weak self, events = deps.audio.meetingEvents] in
            for await event in events { await self?.handle(event) }
        }
        if mode == .remote { startTap() }
        emit(.speakers(registry.labels))
        if let voice {
            emit(.voiceData(active: true, keys: []))
            voice.begin(
                matched: { [weak self] in await self?.matched($0) },
                failed: { [weak self] in self?.voiceModelFailed() }
            )
        }
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
            report(silence?.partial(text, at: meetingTime), reason: "speech")
        case .segment(let segment, let session, let origin):
            await add(segment, session: session, origin: origin)
            report(silence?.segment(segment.text, at: meetingTime), reason: "speech")
        case .revision(let revisions, let session):
            await revise(revisions, session: session)
        case .connection(let connection):
            emit(.connection(connection))
            switch connection {
            case .reconnecting:
                report(silence?.suspend(), reason: "reconnecting")
            // A session draining after Pause or Stop may deliver for the first time.
            case .connected where silence?.isSuspended == true && state == .recording:
                silence?.restart(at: meetingTime)
            case .connected, .rolledOver:
                break
            }
        case .gap(let marker):
            addMarker(marker)
        case .speakers(let speakers, let session):
            await identified(speakers, session: session)
        case .identifierIgnored(_, let identifier):
            if await voice?.ignored(identifier: identifier) == true {
                emit(.notice("Speechmatics ignored some remembered voices. Rename those speakers to learn them again."))
            }
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
        if meeting.test != nil {
            for segment in attribution.segments { segmentArrivals[segment.id] = meetingTime }
        }
        await persistSegments()
        for segment in attribution.segments { emit(.segmentAdded(segment)) }
        for match in voice?.heard(attribution.segments, speakers: registry.labels) ?? [] { await matched(match) }
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
        // Copied only for the route: the revision below would otherwise copy every segment.
        let before = voice == nil ? [] : segments
        let changed = Self.revise(&segments, with: revisions, session: session, registry: &registry)
        guard !changed.isEmpty else { return }
        voice?.revised(changed.map { (before[$0], segments[$0]) }, speakers: registry.labels)
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
    public var meetingTime: Double { deps.clock.now - clockOrigin }

    /// The user's microphone speech, as the gate holds it.
    public var userSpeech: SpeechGate.View { audioPath?.gateView ?? SpeechGate.View() }

    private func startTicker() {
        ticker = Task { [weak self, clock = deps.clock] in
            while true {
                do { try await clock.sleep(for: Self.tick) } catch { return }
                guard let self else { return }
                checkSystemAudio()
                emit(.elapsed(meetingTime))
                emit(.cost(audioPath?.billing.liveCost ?? 0))
                let config = await configStore.load()
                checkSilence(config)
                refreshVoice(config.voice)
            }
        }
    }

    /// Design §5.6 Silence hint: a tap that stays silent through a minute in which the user
    /// spoke most likely lacks the System Audio Recording permission. The peak's one reader, it
    /// reads it every tick, so `lastAudibleSystemAudio` keeps moving after the hint has settled.
    private func checkSystemAudio() {
        guard tap != nil, let audioPath else { return }
        let audible = audioPath.systemPeakSinceLastCall() > Self.audibleSystemPeak
        if audible { lastAudibleSystemAudio = meetingTime }
        guard !systemAudioSettled else { return }
        if audible {
            systemAudioSettled = true
        } else if meetingTime >= Self.silenceHintAfter, !audioPath.gateView.spans.isEmpty {
            systemAudioSettled = true
            emit(.systemAudio(.silentHint))
        }
    }

    // MARK: - Silence

    /// Design v7 R7: the threshold is read every tick, so Off closes an open prompt.
    private func checkSilence(_ config: Config) {
        // A partial, Pause or Stop may have run during the ticker's load.
        guard state == .recording, silence != nil else { return }
        report(silence?.setThreshold(config.meetingSilenceStopSeconds), reason: "setting")
        report(silence?.tick(at: meetingTime), reason: "setting")
    }

    /// Keep recording: closes the prompt; silence counts from now.
    public func keepRecording() {
        report(silence?.keep(at: meetingTime), reason: "kept")
    }

    /// Design v7 R4: stops with a summary and records the threshold, only after the countdown
    /// expired. The coordinator calls it so the stop goes through its own bookkeeping.
    public func stopAfterSilence() async {
        guard let silence, silence.isExpired, state == .recording else { return }
        let seconds = silence.promptMinutes * 60
        meeting?.silenceStopSeconds = seconds
        log.info("meeting stopped after silence (\(seconds) s)")
        await stop(summarise: true)
    }

    /// Emits a prompt change. The log carries times and the close `reason`, never transcript text.
    private func report(_ change: SilencePrompt?, reason: String) {
        guard let change, let silence else { return }
        switch change {
        case .open where !promptShown:
            promptShown = true
            log.info("silence prompt shown after \(Int(meetingTime - silence.lastSpeech)) s")
        case .open:
            break
        case .closed:
            promptShown = false
            log.info("silence prompt closed (\(reason))")
        case .expired:
            promptShown = false
        }
        emit(.silence(change))
    }

    // MARK: - Pause

    /// A test meeting cannot pause (R11); a sleep still pauses it.
    public func pause() async {
        guard meeting?.test == nil else { return }
        await pause(.user)
    }

    /// Design §5.6 Pause: the session closes; capture and the tap keep running.
    private func pause(_ reason: PauseReason) async {
        guard state == .recording, let audioPath else { return }
        report(silence?.suspend(), reason: "paused")
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
        guard meeting?.test == nil else { return }
        await closing?.value
        guard state.isPaused, let audioPath, let supervisor else { return }
        audioPath.catchUp(to: meetingTime)
        let time = audioPath.resume()
        silence?.restart(at: time)
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
        report(silence?.suspend(), reason: "stopped")
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
        await finishVoices()

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

    // MARK: - Voices

    /// Design v8 §5 Segment arrives: a sure match names the speaker, a suggestion is offered. Either
    /// is dropped when the switch is now off, or the speaker is no longer open to recognition, has
    /// rejected the person or holds the same match already (R3, R8, R9, R16).
    private func matched(_ match: MeetingVoiceRoute.Match) async {
        guard let voice, await voiceSettings() != nil, let userName = meeting?.userName,
              let label = MeetingVoiceRoute.speaker(owning: match.key, in: registry.labels),
              MeetingVoiceRoute.isOpen(label), !label.rejected.contains(match.person.id),
              !label.matches.contains(where: { $0.key == match.key && $0.person == match.person.id && !match.sure })
        else { return }
        let named = NameMatch(
            key: match.key, name: match.person.isUser ? userName : match.person.name, person: match.person.id,
            state: match.sure ? .applied : .suggested, score: match.score
        )
        if match.sure {
            await applyMerge(registry.apply(named, userName: match.person.isUser ? userName : nil))
        } else {
            registry.suggest(named)
            await applyMerge(nil)
        }
        await voice.logMatch(match)
    }

    /// The voice settings while the meeting's route switch is on, else nil (R3).
    private func voiceSettings() async -> VoiceSettings? {
        guard let voice, voice.isActive else { return nil }
        let settings = await configStore.load().voice
        refreshVoice(settings)
        return voice.isActive && settings.isEnabled(voice.route) ? settings : nil
    }

    /// Hands the route the latest settings; a live route the switch turned off stays off (R3).
    private func refreshVoice(_ settings: VoiceSettings) {
        guard let voice, voice.isActive else { return }
        voice.refresh(settings)
        if !voice.isActive { emit(.voiceData(active: false, keys: [])) }
    }

    private func voiceModelFailed() {
        emit(.error("Voice recognition is off for this meeting: the voice model could not be loaded."))
        emit(.voiceData(active: false, keys: []))
    }

    /// Design v8 §5 Stop: with the switch still on, the recogniser's voices become the sidecar, the
    /// user's speaker is linked to the user's entry when it has a voice of its own (R19), every
    /// linked person relearns this meeting's voice and the people heard are marked.
    private func finishVoices() async {
        guard let voice, let meeting else { return }
        let sidecar = await voice.finish()
        guard let settings = await voiceSettings() else {
            self.voice = nil
            return emit(.voiceData(active: false, keys: []))
        }
        if !sidecar.keys.isEmpty { await saveSidecar(sidecar, of: meeting.id) }
        let before = registry.labels
        if await voice.hasUserVoice(before, minimum: settings.minimumSpeechSeconds),
           let user = await voice.user(named: meeting.userName) {
            registry.link(SpeakerRegistry.userID, person: user.id)
        }
        await voice.relearn(from: before, to: registry.labels, everyone: true)
        await voice.markHeard(registry.labels)
        if registry.labels != before { emit(.speakers(registry.labels)) }
        emit(.voiceData(active: true, keys: voice.keys))
    }

    /// Writes the meeting's sidecar, or deletes it when there is none; a failure is shown.
    private func saveSidecar(_ sidecar: MeetingVoices?, of id: UUID) async {
        do {
            if let sidecar {
                try await deps.store.writeVoices(sidecar, of: id)
                Log.voice.info("sidecar written: \(sidecar.keys.count) key\(sidecar.keys.count == 1 ? "" : "s")")
            } else {
                try await deps.store.deleteVoices(id)
            }
        } catch {
            let reason = AnyError(error).description
            Log.voice.error("sidecar not written: \(reason)")
            emit(.error("Could not save this meeting's voice data (\(reason))"))
        }
    }

    /// Design v8 §5 People actions, Forget (R24): the stopped meeting this session holds loses the
    /// links, matches and rejections naming `people` (nil for everyone) and those speakers' voice
    /// data; names stay. The sidecar is saved first, so a failed meeting write leaves the links to
    /// scrub again.
    public func scrubVoices(people: Set<UUID>?) async {
        guard state == .stopped, var meeting else { return }
        meeting.speakers = registry.labels
        let original = meeting.speakers
        var scrubbed = false
        if let voice {
            scrubbed = voice.scrub(&meeting, people: people)
            if scrubbed { await saveSidecar(voice.sidecar, of: meeting.id) }
        } else {
            _ = VoiceScrubber.scrub(&meeting, voices: nil, people: people)
            // Without a route the sidecar is absent or unreadable: no use here, and it may hold theirs.
            let linked = original.contains { $0.person.map { people?.contains($0) ?? true } ?? false }
            if deps.voices != nil, people == nil || linked { await saveSidecar(nil, of: meeting.id) }
        }
        if meeting.speakers != original {
            registry = SpeakerRegistry(labels: meeting.speakers)
            await applyMerge(nil)
        }
        if scrubbed, let voice { emit(.voiceData(active: false, keys: voice.keys)) }
    }

    /// Design v8 §5 Accept (R15): the speaker takes the suggested person's name, merging into a
    /// speaker already of that name without asking, and is linked to them. A conversation
    /// suggestion is accepted as if its name were typed (v9 R19).
    public func acceptSuggestion(key: String) async {
        let before = registry.labels
        guard meeting != nil, let suggestion = standing(key, .suggested),
              let accepted = registry.accept(key: key)
        else { return }
        await applyMerge(accepted.merge)
        guard suggestion.match.source == Self.conversation else {
            return await learn(.accepted, key: key, person: accepted.person, since: before)
        }
        Log.naming.info("user action: accepted")
        await link(accepted.merge?.into ?? suggestion.speaker, renamedFrom: before)
    }

    /// Dismiss (R15): the suggestion goes and its person, or a conversation suggestion's name
    /// (v9 R20), is not offered to that speaker again.
    public func dismissSuggestion(key: String) async {
        guard meeting != nil, let dismissed = registry.dismiss(key: key) else { return }
        await applyMerge(nil)
        guard dismissed.source == Self.conversation else {
            return await learn(.dismissed, key: key, person: dismissed.person)
        }
        Log.naming.info("user action: dismissed")
    }

    /// "Not <name>" on an applied name (R15): a speaker of that key alone returns to `Speaker N`;
    /// otherwise the key moves to a new speaker with its unpinned segments. A name the
    /// conversation applied reverts the whole speaker (v9 R23).
    public func rejectMatch(key: String) async {
        let before = registry.labels
        guard meeting != nil, let applied = standing(key, .applied)?.match else { return }
        if applied.source == Self.conversation {
            guard registry.revertConversation(key: key) else { return }
            await applyMerge(nil)
            return Log.naming.info("user action: not")
        }
        if let detach = registry.detach(key: key) {
            await commitSpeakers(to: detach.to) { segment in
                segment.speaker == detach.from && !segment.pinned
                    && SpeakerRegistry.key(session: segment.session, label: segment.providerLabel) == key
            }
        } else {
            await applyMerge(nil)
        }
        await learn(.rejected, key: key, person: applied.person, since: before)
    }

    /// With the switch on, a user's action on a match is logged, and the people whose links it
    /// changed since `before` relearn this meeting's voice (R17, R23). "Not <name>" on a
    /// Speechmatics match costs the person their trust.
    private func learn(_ event: MatchLog.Event, key: String, person: UUID?, since before: [SpeakerLabel]? = nil) async {
        guard let voice, await voiceSettings() != nil else { return }
        await voice.logAction(event, key: key, person: person)
        if event == .rejected, voice.route == .speechmatics, let person { await voice.distrust(person) }
        if let before { await relearn(voice, since: before, linked: event == .accepted && person != nil) }
    }

    /// Design v8 §5 Link: live on Speechmatics a new link first asks the session for its speakers,
    /// whose identifiers teach again when they arrive (R12).
    private func relearn(_ voice: MeetingVoiceRoute, since before: [SpeakerLabel], linked: Bool) async {
        if linked, voice.route == .speechmatics { supervisor?.requestSpeakers() }
        await voice.relearn(from: before, to: registry.labels)
    }

    /// Design v8 §5 SpeakersResult (R12): the identifiers are kept per key, and with the switch on
    /// every linked person relearns theirs.
    private func identified(_ speakers: [ProviderSpeaker], session: Int) async {
        guard let voice else { return }
        voice.identified(speakers, session: session)
        guard await voiceSettings() != nil else { return }
        await voice.relearn(from: registry.labels, to: registry.labels, everyone: true)
    }

    /// Design v8 §5 Rename: with the switch on, the speaker the user named is that person, found or
    /// created by name, or the user's own entry for the user (R17–R19); a default name, or the
    /// switch off, clears the link. Matches standing on the speaker are logged as renamed.
    private func link(_ id: Int, renamedFrom before: [SpeakerLabel]) async {
        guard let voice, let userName = meeting?.userName,
              let renamed = registry.labels.first(where: { $0.id == id })
        else { return }
        let learning = await voiceSettings() != nil
        let person = learning ? await voice.person(for: renamed, userName: userName) : nil
        let labels = registry.labels
        // Read again: the speaker may have changed while the store was asked.
        guard let standing = labels.first(where: { $0.id == id })?.matches else { return }
        registry.link(id, person: person?.id)
        if registry.labels != labels { await applyMerge(nil) }
        guard learning else { return }
        for match in standing { await voice.logAction(.renamed, key: match.key, person: match.person) }
        await relearn(voice, since: before, linked: person != nil)
    }

    // MARK: - Naming

    private static let conversation = "conversation"

    /// Design v9 §5 That's me (R21): the suggested name is the user's, misheard. It is kept once
    /// as a spelling of the user's name, and no speaker of this meeting is offered it any more.
    public func thatsMe(key: String) async {
        guard let userName = meeting?.userName, let match = standing(key, .suggested)?.match,
              match.source == Self.conversation
        else { return }
        let (name, fold) = (match.name, NameFold.key(match.name))
        guard fold != NameFold.key(userName) else { return }
        do {
            try await configStore.update { @Sendable config in
                guard !config.meetingUserNameAliases.contains(where: { NameFold.key($0) == fold }) else { return }
                config.meetingUserNameAliases.append(name)
            }
        } catch {
            log.warning("meeting_user_name_aliases not saved: \(AnyError(error).description)")
        }
        let withdrawn = registry.withdrawConversation(named: fold)
        await applyMerge(nil)
        Log.naming.info("user action: that's me, \(withdrawn) withdrawn")
    }

    /// The match in `state` standing for `key`, and the speaker holding it.
    private func standing(_ key: String, _ state: NameMatch.State) -> (speaker: Int, match: NameMatch)? {
        guard let label = MeetingVoiceRoute.speaker(owning: key, in: registry.labels),
              let match = label.matches.first(where: { $0.key == key && $0.state == state })
        else { return nil }
        return (label.id, match)
    }

    // MARK: - Speakers, notes and edits

    /// Design §5.6 Rename: onto another speaker's name the two merge.
    public func rename(speaker id: Int, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard meeting != nil, !name.isEmpty else { return }
        let labels = registry.labels
        let merge = registry.rename(id, to: name)
        guard registry.labels != labels else { return }
        await applyMerge(merge)
        await link(merge?.into ?? id, renamedFrom: labels)
    }

    /// After a registry change: a merge's segments follow it into the surviving speaker, then
    /// segments and `meeting.json` are saved and the speakers emitted.
    private func applyMerge(_ merge: SpeakerRegistry.Merge?) async {
        let from = merge?.from
        await commitSpeakers(to: merge?.into) { $0.speaker == from }
    }

    /// Moves the segments `moving` picks to `speaker`, when one is given, then saves segments and
    /// `meeting.json` and emits.
    private func commitSpeakers(to speaker: Int?, moving: (Segment) -> Bool) async {
        var changed: [Int] = []
        if let speaker {
            for index in segments.indices where moving(segments[index]) {
                segments[index].speaker = speaker
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
        meeting?.rename(title)
        await saveMeeting()
    }

    // MARK: - Test call

    /// Design §5.3: after `stop(summarise: false)`, scores a test meeting from its segments as
    /// they stand after the drain, stores the score and caches its WER on the tag. A failed
    /// write still shows the score for this session (§5.6).
    public func finishTest(_ run: TestCallRun, scenario: TestScenario) async {
        guard state == .stopped, let meeting, meeting.test != nil else { return }
        let record = TestCallScorer().score(
            run: run, scenario: scenario, segments: segments, arrivals: segmentArrivals,
            speakers: registry.labels, userSpeaker: SpeakerRegistry.userID, engine: meeting.engine,
            scoredAt: deps.now()
        )
        do {
            try await deps.store.writeTestCall(record, of: meeting.id)
        } catch {
            let reason = AnyError(error).description
            log.error("testcall.json not written: \(reason)")
            emit(.error("Could not write the test score (\(reason))"))
        }
        self.meeting?.test?.wer = record.overall.wer
        await saveMeeting()
        emit(.testScore(.scored(record)))
        let wer = record.overall.wer.map { String(format: "%.3f", $0) } ?? "none"
        let scored = record.lines.filter { $0.counts != nil }.count
        let latency = record.latency.map { String(format: "%.1f", $0.median) } ?? "none"
        log.info("test call: scored wer=\(wer) lines=\(scored)/\(record.lines.count) latency_med=\(latency)")
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
        if let voices = deps.voices, let sidecar = storedVoices(id) {
            voice = MeetingVoiceRoute(
                stored: voices, sidecar: sidecar, meeting: id, mode: loaded.meeting.mode, now: deps.now
            )
        }
        emit(.speakers(registry.labels))
        if let voice { emit(.voiceData(active: false, keys: voice.keys)) }
        loaded.meeting.markers.forEach { emit(.marker($0)) }
        segments.forEach { emit(.segmentAdded($0)) }
        notes.forEach { emit(.note($0)) }
        if let summary = loaded.meeting.summary { emit(.summary(.ready(summary))) }
        if let tag = loaded.meeting.test { emit(.testScore(storedScore(id, tag: tag))) }
        setState(.stopped)
    }

    /// The meeting's sidecar; nil when it has none or it cannot be read.
    private func storedVoices(_ id: UUID) -> MeetingVoices? {
        do {
            return try deps.store.readVoices(id)
        } catch {
            // No error text: a decoding error can quote the file, and the file holds voices.
            Log.voice.warning("voices.json of a stored meeting is unreadable; its links learn nothing")
            return nil
        }
    }

    /// Design §3 R20: a tag without a score file is an unfinished test call, unless it carries
    /// the WER the file was scored with.
    private func storedScore(_ id: UUID, tag: TestCallTag) -> TestScoreState {
        do {
            if let record = try deps.store.readTestCall(id) { return .scored(record) }
            return tag.wer == nil ? .missing : .unreadable
        } catch {
            log.warning("test call score unreadable: \(AnyError(error).description)")
            return .unreadable
        }
    }

    // MARK: - Summary

    /// Design §5.6 Summarise; does nothing once the meeting has a summary.
    public func summarise() async {
        guard state == .stopped, !summarising, let meeting, meeting.summary == nil else { return }
        if let reason = summaryBlocker { return emit(.summary(.none(reason))) }
        summarising = true
        defer { summarising = false }
        emit(.summary(.writing))
        switch await requestSummary(of: meeting) {
        case .ready(let summary, let subject):
            await adopt(summary, subject: subject)
            emit(.summary(.ready(summary)))
        case .failed(let reason):
            emit(.summary(.failed(reason)))
        case .empty:
            emit(.summary(.none(Self.nothingTranscribed)))
        }
    }

    /// Design §5.6 Regenerate: the current summary stays until a new one has arrived, and is
    /// kept, with nothing saved, when none does.
    public func regenerateSummary() async {
        guard state == .stopped, !summarising, let meeting, let current = meeting.summary else { return }
        if let reason = summaryBlocker { return keep(current, reason) }
        summarising = true
        defer { summarising = false }
        log.info("summary regenerate started")
        emit(.summary(.rewriting(current)))
        switch await requestSummary(of: meeting) {
        case .ready(let summary, let subject):
            self.meeting?.billing.replacedSummaryCostUSD += current.costUSD
            await adopt(summary, subject: subject)
            log.info("summary regenerate: ready")
            emit(.summary(.ready(summary)))
        case .failed(let reason):
            keep(current, reason)
        case .empty:
            keep(current, Self.nothingTranscribed)
        }
    }

    private enum SummaryAttempt {
        case ready(Summary, subject: String?)
        /// Declined, or the request's error.
        case failed(String)
        case empty
    }

    /// Why no request is made: nothing to summarise, or no Anthropic key.
    private var summaryBlocker: String? {
        if segments.isEmpty { return Self.nothingTranscribed }
        return secret(.anthropic) == nil ? Self.noSummaryKey : nil
    }

    /// One summary request over the meeting as it stands; saves nothing.
    private func requestSummary(of meeting: Meeting) async -> SummaryAttempt {
        let summariser = Summariser(
            prompts: deps.prompts,
            client: deps.summarizer,
            overrides: await configStore.load().pricingOverrides,
            now: deps.now
        )
        do {
            switch try await summariser.run(LoadedMeeting(meeting: meeting, segments: segments, notes: notes)) {
            case .ready(let summary, let subject): return .ready(summary, subject: subject)
            case .declined(let category): return .failed("Summary declined (\(category))")
            case .empty: return .empty
            }
        } catch {
            let reason = AnyError(error).description
            log.warning("summary failed: \(reason)")
            return .failed(reason)
        }
    }

    /// Stores the summary, names the meeting after its subject where the title is the app's, and
    /// bills its tokens.
    private func adopt(_ summary: Summary, subject: String?) async {
        meeting?.summary = summary
        if let subject, meeting?.name(after: subject) == true, let title = meeting?.title { emit(.title(title)) }
        await saveMeeting()
        await addUsage(ProviderUsage(
            inputTokens: summary.inputTokens, outputTokens: summary.outputTokens, costUSD: summary.costUSD
        ))
    }

    private func keep(_ current: Summary, _ reason: String) {
        log.info("summary regenerate: kept (\(reason))")
        emit(.summary(.kept(current, reason: reason)))
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

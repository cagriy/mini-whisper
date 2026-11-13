import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestCall
import MWUsage
import Observation

/// The meeting window's state (design §5.3, mockup States 1–3): the chooser before Start, the
/// live transcript reduced from `MeetingEvent`s, then the stopped meeting with its summary. A
/// segment that arrives in time order only extends or follows the last row, so a long meeting
/// never re-merges its paragraphs (R26).
@MainActor
@Observable
final class MeetingWindowModel {
    /// Mockup State 1: what Start would use, and whether it can.
    struct Chooser: Equatable {
        static let systemAudioNote = "macOS will ask to allow System Audio Recording when the meeting starts."
            + " Mini Whisper captures only the sound other apps play; it never records your screen. If you"
            + " decline, the meeting continues with the microphone alone."

        /// The tier Start would use; nil without a Speechmatics or AssemblyAI key.
        let engine: MeetingEngine?
        let supportsSystemAudio: Bool
        let systemAudioExplained: Bool
        let pricingOverrides: [String: Double]
        let userName: String
        /// The engines with a key, for the test-call setup page.
        let keyedEngines: Set<MeetingEngine>

        /// `accountName` stands in for a blank `meeting_user_name`, as in `MeetingController`.
        init(config: Config, platform: PlatformInfo, accountName: String, hasKey: (KeyAccount) -> Bool) {
            engine = MeetingEngine.resolve(stored: config.meetingEngine, hasKey: hasKey)
            keyedEngines = Set(MeetingEngine.allCases.filter { hasKey($0.keyAccount) })
            supportsSystemAudio = platform.supportsSystemAudio
            systemAudioExplained = config.meetingSystemAudioExplained
            pricingOverrides = config.pricingOverrides
            userName = config.meetingUserName.flatMap {
                $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0
            } ?? accountName
        }

        var priceLabel: String? {
            engine.map { "About \(Pricing.dollars(Pricing.perHour($0, overrides: pricingOverrides))) per hour" }
        }

        var engineLine: String? {
            engine.map { "Engine: \($0.title)" }
        }

        var remoteUnavailableReason: String? {
            supportsSystemAudio ? nil : "needs macOS 14.2"
        }

        var startBlockedReason: String? {
            engine == nil ? MeetingError.noEngineKey.errorDescription : nil
        }

        var defaultMode: MeetingMode {
            supportsSystemAudio ? .remote : .inRoom
        }

        func canStart(_ mode: MeetingMode) -> Bool {
            engine != nil && (mode == .inRoom || supportsSystemAudio)
        }

        /// Ahead of the macOS prompt, before the first remote meeting only (R2).
        func showsSystemAudioNote(for mode: MeetingMode) -> Bool {
            mode == .remote && supportsSystemAudio && !systemAudioExplained
        }

        func description(of mode: MeetingMode) -> String {
            switch mode {
            case .remote:
                "Microphone plus the audio other apps play (Zoom, Teams, Meet). Your microphone is"
                    + " labelled \(userName); other voices become Speaker 1, 2…"
            case .inRoom:
                "Microphone only. Every voice is diarized into Speaker 1, 2…; rename yourself once the"
                    + " first words appear."
            }
        }
    }

    /// Consecutive segments of one speaker, headed by the time of the first (R7).
    struct Paragraph: Equatable, Identifiable {
        /// The first segment's.
        let id: UUID
        let speaker: Int
        let start: Double
        private(set) var segmentIDs: [UUID]
        private(set) var text: String

        init(_ segment: Segment) {
            id = segment.id
            speaker = segment.speaker
            start = segment.start
            segmentIDs = [segment.id]
            text = segment.text
        }

        var time: String { MeetingTime.format(start) }

        mutating func append(_ segment: Segment) {
            segmentIDs.append(segment.id)
            text += " " + segment.text
        }
    }

    enum TranscriptRow: Equatable, Identifiable {
        enum ID: Hashable {
            case paragraph(UUID)
            case note(UUID)
            case marker(Marker.Kind, Double)
        }

        case paragraph(Paragraph)
        case note(Note)
        case marker(Marker)

        var id: ID {
            switch self {
            case .paragraph(let paragraph): .paragraph(paragraph.id)
            case .note(let note): .note(note.id)
            case .marker(let marker): .marker(marker.kind, marker.start)
            }
        }

        var paragraph: Paragraph? {
            if case .paragraph(let paragraph) = self { paragraph } else { nil }
        }

        var text: String {
            switch self {
            case .paragraph(let paragraph): paragraph.text
            case .note(let note): "\(MeetingWindowModel.time(of: note)) · \(note.text)"
            case .marker(let marker): MeetingWindowModel.text(of: marker)
            }
        }
    }

    /// Grey text after the last paragraph; `header` names the speaker when it is not the last
    /// paragraph's.
    struct Partial: Equatable {
        var text: String
        var header: String?
    }

    struct DraftNote: Equatable {
        var text: String
        /// Meeting seconds of the first keystroke (R8).
        var time: Double
    }

    /// The Summary tab of a stopped meeting (R12, R16).
    enum SummaryPanel: Equatable {
        case writing
        /// No summary: why, and whether *Summarise* is offered.
        case message(String, canSummarise: Bool)
        /// The summary on screen; a notice says a new one is being written or was not.
        case ready(blocks: [SummaryDocument.Block], meta: String, notice: Notice?)

        enum Notice: Equatable {
            case rewriting
            case failed(String)
        }
    }

    enum Tab: Hashable {
        case summary, transcript, notes
    }

    /// Copy summary's three forms (R17).
    struct CopyPayload: Equatable {
        let markdown: String
        let html: String
        let rtf: Data
    }

    /// R13: a segment's text as edited, or as it stands.
    struct SegmentEdit: Equatable {
        var segment: UUID
        var text: String
    }

    /// R13: one entry of *Move this segment to*.
    struct ReassignChoice: Equatable, Identifiable {
        let id: Int
        let name: String
        let isCurrent: Bool
    }

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
    )!
    static let silenceHintText = "No audio from other apps yet. Check System Settings → Privacy & Security"
        + " → Screen & System Audio Recording."
    static let noSummaryYet = "No summary yet."

    static func title(of mode: MeetingMode) -> String {
        switch mode {
        case .remote: "Remote call"
        case .inRoom: "In the room"
        }
    }

    nonisolated static func time(of note: Note) -> String {
        MeetingTime.format(note.time)
    }

    /// R9, R10. A pause still open has no end yet.
    nonisolated static func text(of marker: Marker) -> String {
        let span = marker.end > marker.start
            ? "\(MeetingTime.format(marker.start))–\(MeetingTime.format(marker.end))"
            : "from \(MeetingTime.format(marker.start))"
        return switch marker.kind {
        case .gap: "Transcript gap \(span) (\(marker.reason ?? "connection lost"))"
        case .paused: "Paused \(span)"
        case .sleep: "Paused \(span) (Mac slept)"
        }
    }

    let chooser: Chooser
    /// The chooser's test-call setup page.
    let setup: TestCallSetupModel
    /// The chooser shows the setup page in place of its cards (R1).
    private(set) var showsTestCallSetup = false
    /// For the end and summary times.
    let timeZone: TimeZone
    var mode: MeetingMode
    private(set) var state: MeetingState = .idle
    private(set) var title = ""
    private(set) var engine: MeetingEngine?
    private(set) var speakers: [SpeakerLabel] = []
    /// Sorted by time: the Notes pane.
    private(set) var notes: [Note] = []
    private(set) var connectionChip: String?
    private(set) var elapsed: Double = 0
    private(set) var cost: Double = 0
    private(set) var systemAudio: SystemAudioState?
    private(set) var summary: SummaryState?
    /// The summary on screen, parsed once per summary event.
    private var document: SummaryDocument?
    private(set) var errorMessage: String?
    private(set) var endedAt: Date?
    /// A test meeting's score, once the controller has read or computed it.
    private(set) var testScore: TestScoreState?
    /// A test meeting's script and score pane.
    private(set) var testCall: TestCallPaneModel?

    var noteDraft = "" {
        didSet {
            if noteDraft.isEmpty {
                noteStartedAt = nil
            } else if noteStartedAt == nil {
                noteStartedAt = elapsed
            }
        }
    }

    @ObservationIgnored private var noteStartedAt: Double?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let clock: any MWSupport.Clock
    /// The tab is chosen once, when the meeting first stops on this model.
    @ObservationIgnored private var hasStopped = false
    @ObservationIgnored private let loadRuns: @MainActor (TestCallTag) async -> [TestRunHistory.Run]
    /// As last shown; the summary's "partial" note needs it.
    @ObservationIgnored private var meeting: Meeting?
    /// Whether the ready summary read a truncated transcript (*Planning decisions taken* #26).
    private var summaryTruncated = false
    private var partialText: String?
    private var partialSpeaker: Int?

    // The transcript's sources, each sorted by time. Views observe them through `version`.
    @ObservationIgnored private var segments: [Segment] = []
    @ObservationIgnored private var positions: [UUID: Int] = [:]
    @ObservationIgnored private var markers: [Marker] = []
    /// Nil after a change that is not at the end; `rows` rebuilds it on the next read.
    @ObservationIgnored private var cachedRows: [TranscriptRow]? = []
    /// Full re-merges so far; the in-order path never needs one.
    @ObservationIgnored private(set) var rebuilds = 0
    private var version = 0

    init(
        chooser: Chooser,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        clock: any MWSupport.Clock = SystemClock(),
        /// Earlier runs of a test call's scenario revision, newest first.
        loadRuns: @escaping @MainActor (TestCallTag) async -> [TestRunHistory.Run] = { _ in [] }
    ) {
        self.chooser = chooser
        setup = TestCallSetupModel(keyedEngines: chooser.keyedEngines, defaultEngine: chooser.engine)
        self.timeZone = timeZone
        self.now = now
        self.clock = clock
        self.loadRuns = loadRuns
        mode = chooser.defaultMode
    }

    // MARK: - Outputs

    var canStart: Bool { chooser.canStart(mode) }

    /// The chooser's Test Call… link, once this Mac's voices allow a test call.
    func openTestCallSetup() {
        if setup.canOpen { showsTestCallSetup = true }
    }

    /// The setup page's ‹ Back.
    func closeTestCallSetup() {
        showsTestCallSetup = false
    }

    var rows: [TranscriptRow] {
        _ = version
        if let cachedRows { return cachedRows }
        var rows: [TranscriptRow] = []
        for item in mergedItems() { Self.append(item, to: &rows) }
        cachedRows = rows
        rebuilds += 1
        return rows
    }

    var partial: Partial? {
        guard let partialText else { return nil }
        guard let speaker = partialSpeaker, rows.last?.paragraph?.speaker != speaker else {
            return Partial(text: partialText, header: nil)
        }
        return Partial(text: partialText, header: name(of: speaker))
    }

    var sourceLine: String? {
        guard let engine else { return nil }
        let source = "\(engine.title) · English"
        guard isTest else {
            return state == .stopped
                ? source + " · double-click a paragraph to edit it, click a name to rename the speaker"
                : source
        }
        return source + (state == .stopped
            ? " · speaker names stay as the engine labelled them"
            : " · speaker names stay as the engine labels them; the score checks them")
    }

    var captureChip: String {
        guard mode == .remote else { return "Mic" }
        return switch systemAudio {
        case .on, .silentHint: "Mic · System audio"
        case .unavailable: "System audio off"
        case nil: "Mic"
        }
    }

    var silenceHint: String? { systemAudio == .silentHint ? Self.silenceHintText : nil }

    var elapsedText: String { MeetingTime.format(elapsed) }

    /// Live: the engine so far. Stopped: the engine, the replaced summaries and the current one (R18).
    var costText: String {
        Pricing.dollars(cost + (shownSummary?.costUSD ?? 0))
    }

    var endedChip: String? {
        guard state == .stopped, let endedAt else { return nil }
        return "Ended \(timeOfDay(endedAt))"
    }

    var summaryPanel: SummaryPanel? {
        guard state == .stopped else { return nil }
        _ = version
        let transcribed = !segments.isEmpty
        guard let summary else {
            return .message(transcribed ? Self.noSummaryYet : MeetingController.nothingTranscribed, canSummarise: transcribed)
        }
        return switch summary {
        case .ready(let current): .ready(blocks: document?.blocks ?? [], meta: meta(of: current), notice: nil)
        case .rewriting(let current):
            .ready(blocks: document?.blocks ?? [], meta: meta(of: current), notice: .rewriting)
        case .kept(let current, let reason):
            .ready(blocks: document?.blocks ?? [], meta: meta(of: current), notice: .failed(reason))
        case .writing: .writing
        case .none(let reason), .failed(let reason): .message(reason, canSummarise: transcribed)
        }
    }

    var canSummarise: Bool {
        if case .message(_, true)? = summaryPanel { true } else { false }
    }

    /// Summary, or Transcript for a test call, once the meeting first stops; the pill switch after.
    var selectedTab: Tab = .summary

    var notesTabTitle: String {
        notes.isEmpty ? "Notes" : "Notes · \(notes.count)"
    }

    /// The finished page's chips: "Mon 9 Nov · 14:30–15:19", "48 min", the mode, up to three
    /// speakers then "+N", and the total cost.
    var chips: [String] {
        guard state == .stopped, let meeting else { return [] }
        let start = formatted(meeting.startedAt, "EEE d MMM · HH:mm")
        var chips = [
            endedAt.map { "\(start)–\(timeOfDay($0))" } ?? start,
            MeetingsListModel.duration(elapsed),
            Self.title(of: mode),
        ]
        if !speakers.isEmpty {
            let names = speakers.prefix(3).map(\.name).joined(separator: ", ")
            chips.append(speakers.count > 3 ? "\(names) +\(speakers.count - 3)" : names)
        }
        chips.append("\(costText) total")
        return chips
    }

    /// The sidebar's recording pill (R3).
    var pillTitle: String {
        title.isEmpty ? "Starting…" : title
    }

    /// `mm:ss` under an hour, `h:mm:ss` from one, or `Paused`.
    var pillDetail: String {
        if case .paused = state { return "Paused" }
        let seconds = Int(max(0, elapsed))
        let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%02d:%02d", minutes, seconds % 60)
    }

    var canCopySummary: Bool {
        state == .stopped && shownSummary != nil
    }

    /// Not while a summary is being written (R16).
    var canRegenerate: Bool {
        guard state == .stopped else { return false }
        return switch summary {
        case .ready?, .kept?: true
        default: false
        }
    }

    /// The confirmation's message, naming what the current summary cost.
    var regeneratePrompt: String? {
        guard canRegenerate, let current = shownSummary else { return nil }
        return "The current summary cost \(Pricing.dollars(current.costUSD)). It stays until the new one"
            + " arrives, and stays if the request fails."
    }

    var copyPayload: CopyPayload? {
        guard canCopySummary, let current = shownSummary, let document else { return nil }
        return CopyPayload(
            markdown: SummaryDocument.markdown(title: title, summary: current.text),
            html: document.html(title: title),
            rtf: SummaryRichText.rtf(title: title, blocks: document.blocks)
        )
    }

    /// Copy summary reads `Copied` for 1.5 seconds after a copy.
    private(set) var justCopied = false
    @ObservationIgnored private(set) var copyReset: Task<Void, Never>?

    func didCopySummary() {
        justCopied = true
        copyReset?.cancel()
        copyReset = Task { [weak self, clock] in
            try? await clock.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.justCopied = false
        }
    }

    /// R13: edit and reassign after Stop only.
    var canEdit: Bool { state == .stopped }

    var isTest: Bool { testCall != nil }

    /// Recording or paused.
    var canStop: Bool {
        if case .paused = state { return true }
        return state == .recording
    }

    /// R11: a test call never pauses.
    var canPause: Bool { canStop && !isTest }

    var pauseHelp: String? { isTest ? "Not available in a test call" : nil }

    var pauseTitle: String {
        if case .paused = state { "Resume" } else { "Pause" }
    }

    func name(of speaker: Int) -> String {
        speakers.first { $0.id == speaker }?.name ?? "Speaker \(speaker)"
    }

    func renameTitle(of speaker: Int) -> String {
        "Rename \(name(of: speaker)) (every segment)"
    }

    /// Renaming onto another speaker's name merges the two, so the window asks first (§5.7).
    func mergePrompt(renaming speaker: Int, to name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speakers.contains(where: { $0.id != speaker && $0.name == name }) else { return nil }
        return "Merge \(self.name(of: speaker)) into \(name)?"
    }

    func segments(in paragraph: Paragraph) -> [Segment] {
        paragraph.segmentIDs.compactMap { positions[$0].map { segments[$0] } }
    }

    /// The drafts that change a segment, trimmed; a blank draft changes nothing.
    func edits(_ drafts: [SegmentEdit]) -> [SegmentEdit] {
        guard canEdit else { return [] }
        return drafts.compactMap { draft in
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let position = positions[draft.segment], segments[position].text != text
            else { return nil }
            return SegmentEdit(segment: draft.segment, text: text)
        }
    }

    func reassignChoices(for segment: UUID) -> [ReassignChoice] {
        guard canEdit, let position = positions[segment] else { return [] }
        let current = segments[position].speaker
        return speakers.map { ReassignChoice(id: $0.id, name: $0.name, isCurrent: $0.id == current) }
    }

    // MARK: - Inputs

    /// The header once the controller has the meeting; an ended one also sets its duration
    /// and engine cost.
    func show(_ meeting: Meeting) {
        self.meeting = meeting
        title = meeting.title
        mode = meeting.mode
        engine = meeting.engine
        if let tag = meeting.test, testCall == nil {
            let testCall = TestCallPaneModel(scenario: Self.scenario(of: tag), casting: [:])
            testCall.score = testScore
            self.testCall = testCall
        }
        if let endedAt = meeting.endedAt {
            self.endedAt = endedAt
            elapsed = meeting.durationSeconds
            cost = meeting.billing.costUSD + meeting.billing.replacedSummaryCostUSD
        }
    }

    /// Segments intersecting the expanded score line's scoring window (*Planning decisions taken* #28).
    var highlightedSegments: Set<UUID> {
        _ = version
        guard let window = testCall?.highlight else { return [] }
        return Set(segments.filter { $0.start <= window.upperBound && $0.end >= window.lowerBound }.map(\.id))
    }

    /// The paragraphs holding a highlighted segment.
    var highlightedParagraphs: Set<UUID> {
        let segments = highlightedSegments
        guard !segments.isEmpty else { return [] }
        return Set(rows.compactMap(\.paragraph).filter { !segments.isDisjoint(with: $0.segmentIDs) }.map(\.id))
    }

    /// Earlier runs of a test meeting's scenario revision, for its score pane.
    func loadEarlierRuns() async {
        guard let meeting, let tag = meeting.test, let testCall else { return }
        let runs = await loadRuns(tag)
        testCall.showRuns(runs, this: meeting.id, now: now(), timeZone: timeZone)
    }

    /// A running test call's pane, which follows its conductor.
    func attach(_ testCall: TestCallPaneModel) {
        self.testCall = testCall
    }

    /// The bundled script the tag names; an id this version does not know has no lines.
    private static func scenario(of tag: TestCallTag) -> TestScenario {
        ScenarioLibrary.scenario(id: tag.scenarioID)
            ?? TestScenario(id: tag.scenarioID, revision: tag.revision, title: tag.scenarioTitle, voices: [], lines: [])
    }

    /// The header rename (R15): the trimmed title to store, or nil when blank or unchanged.
    func commitTitle(_ draft: String) -> String? {
        let draft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty, draft != title else { return nil }
        title = draft
        return draft
    }

    /// A failure outside the event stream, such as Start throwing.
    func showError(_ message: String) {
        errorMessage = message
    }

    /// Enter in the composer: the trimmed draft and the time of its first keystroke.
    func commitNote() -> DraftNote? {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let time = noteStartedAt else { return nil }
        noteDraft = ""
        return DraftNote(text: text, time: time)
    }

    func apply(_ event: MeetingEvent) {
        switch event {
        case .state(let state):
            self.state = state
            if state == .stopped, !hasStopped {
                hasStopped = true
                selectedTab = isTest ? .transcript : .summary
            }
            if state != .recording {
                partialText = nil
                connectionChip = nil
            }
        case .segmentAdded(let segment):
            partialText = nil
            add(segment)
        case .segmentUpdated(let segment):
            update(segment)
        case .partial(let text, let speaker):
            partialText = text.isEmpty ? nil : text
            partialSpeaker = speaker
        case .speakers(let labels):
            speakers = labels
        case .marker(let marker):
            add(marker)
        case .note(let note):
            add(note)
        case .connection(let connection):
            if case .reconnecting(let attempt) = connection {
                connectionChip = "Reconnecting (\(attempt))"
            } else {
                connectionChip = nil
            }
        case .elapsed(let seconds):
            elapsed = seconds
        case .cost(let dollars):
            cost = dollars
        case .summary(let summary):
            // The summary a regenerate replaced stays in the total.
            if case .rewriting(let replaced)? = self.summary, case .ready = summary { cost += replaced.costUSD }
            self.summary = summary
            document = shownSummary.map { SummaryDocument(markdown: $0.text) }
            if case .ready = summary { summaryTruncated = isTruncated }
        case .systemAudio(let state):
            systemAudio = state
        case .testScore(let score):
            testScore = score
            testCall?.score = score
        case .error(let message):
            errorMessage = message
        }
    }

    // MARK: - Summary

    /// "Claude Sonnet 5.5 · 15:19 · 12.5k in / 610 out tokens · $0.03", plus "partial" (§5.5).
    private func meta(of summary: Summary) -> String {
        var parts = [
            MeetingMarkdown.modelName(summary.model),
            timeOfDay(summary.createdAt),
            "\(Self.tokens(summary.inputTokens)) in / \(Self.tokens(summary.outputTokens)) out tokens",
            Pricing.dollars(summary.costUSD),
        ]
        if summaryTruncated { parts.append("partial") }
        return parts.joined(separator: " · ")
    }

    private static func tokens(_ count: Int) -> String {
        count < 1000 ? "\(count)" : String(format: "%.1fk", Double(count) / 1000)
    }

    /// The transcript the summary was written from, as `Summariser` measures it.
    private var isTruncated: Bool {
        guard var meeting else { return false }
        meeting.speakers = speakers
        meeting.markers = markers
        return Summariser.isTruncated(LoadedMeeting(meeting: meeting, segments: segments, notes: notes))
    }

    /// The current summary of `.ready`, `.rewriting` or `.kept`.
    private var shownSummary: Summary? {
        switch summary {
        case .ready(let current)?, .rewriting(let current)?, .kept(let current, _)?: current
        default: nil
        }
    }

    private func timeOfDay(_ date: Date) -> String {
        formatted(date, "HH:mm")
    }

    private func formatted(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Transcript reduction

    /// Order within one time: markers, notes, then segments, as in the transcript export.
    private enum Item {
        case marker(Marker)
        case note(Note)
        case segment(Segment)

        var key: Key {
            switch self {
            case .marker(let marker): Key(time: marker.start, rank: 0)
            case .note(let note): Key(time: note.time, rank: 1)
            case .segment(let segment): Key(time: segment.start, rank: 2)
            }
        }
    }

    private struct Key: Comparable {
        var time: Double
        var rank: Int

        static func < (lhs: Key, rhs: Key) -> Bool {
            (lhs.time, lhs.rank) < (rhs.time, rhs.rank)
        }
    }

    private static func append(_ item: Item, to rows: inout [TranscriptRow]) {
        switch item {
        case .segment(let segment):
            if case .paragraph(var paragraph)? = rows.last, paragraph.speaker == segment.speaker {
                paragraph.append(segment)
                rows[rows.count - 1] = .paragraph(paragraph)
            } else {
                rows.append(.paragraph(Paragraph(segment)))
            }
        case .note(let note):
            rows.append(.note(note))
        case .marker(let marker):
            rows.append(.marker(marker))
        }
    }

    /// The three sorted sources merged by `Key`, stably.
    private func mergedItems() -> [Item] {
        var items: [Item] = []
        items.reserveCapacity(markers.count + notes.count + segments.count)
        var m = 0, n = 0, s = 0
        while true {
            var next: Item?
            func consider(_ item: Item) {
                if next.map({ item.key < $0.key }) ?? true { next = item }
            }
            if m < markers.count { consider(.marker(markers[m])) }
            if n < notes.count { consider(.note(notes[n])) }
            if s < segments.count { consider(.segment(segments[s])) }
            guard let next else { return items }
            switch next {
            case .marker: m += 1
            case .note: n += 1
            case .segment: s += 1
            }
            items.append(next)
        }
    }

    /// The last item in transcript order.
    private var tail: Key? {
        [
            markers.last.map { Item.marker($0).key },
            notes.last.map { Item.note($0).key },
            segments.last.map { Item.segment($0).key },
        ].compactMap { $0 }.max()
    }

    /// Appends to the rows when `item` sorts last; otherwise they are rebuilt on the next read.
    /// Call before adding `item` to its source.
    @discardableResult
    private func place(_ item: Item) -> Bool {
        let atEnd = tail.map { !(item.key < $0) } ?? true
        if !atEnd {
            cachedRows = nil
        } else if cachedRows != nil {
            Self.append(item, to: &cachedRows!)
        }
        version += 1
        return atEnd
    }

    private func add(_ segment: Segment) {
        guard positions[segment.id] == nil else { return update(segment) }
        if place(.segment(segment)) {
            positions[segment.id] = segments.count
            segments.append(segment)
        } else {
            let index = segments.firstIndex { $0.start > segment.start } ?? segments.count
            segments.insert(segment, at: index)
            for position in index..<segments.count { positions[segments[position].id] = position }
        }
    }

    /// A revision, a rename merge or an edit: grouping may change, so the rows are rebuilt.
    private func update(_ segment: Segment) {
        guard let position = positions[segment.id] else { return }
        segments[position] = segment
        cachedRows = nil
        version += 1
    }

    private func add(_ note: Note) {
        place(.note(note))
        notes.insert(note, at: notes.firstIndex { $0.time > note.time } ?? notes.count)
    }

    /// A pause marker comes again with its end once the meeting resumes.
    private func add(_ marker: Marker) {
        if let index = markers.lastIndex(where: { $0.kind == marker.kind && $0.start == marker.start }) {
            markers[index] = marker
            let id = TranscriptRow.marker(marker).id
            if let row = cachedRows?.lastIndex(where: { $0.id == id }) {
                cachedRows?[row] = .marker(marker)
            } else {
                cachedRows = nil
            }
            version += 1
            return
        }
        place(.marker(marker))
        markers.insert(marker, at: markers.firstIndex { $0.start > marker.start } ?? markers.count)
    }
}

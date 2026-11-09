import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWUsage
import Observation

/// The meeting window's state (design §5.3, mockup States 1–2): the chooser before Start, then
/// the live transcript reduced from `MeetingEvent`s. A segment that arrives in time order only
/// extends or follows the last row, so a long meeting never re-merges its paragraphs (R26).
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

        /// `accountName` stands in for a blank `meeting_user_name`, as in `MeetingController`.
        init(config: Config, platform: PlatformInfo, accountName: String, hasKey: (KeyAccount) -> Bool) {
            engine = MeetingEngine.resolve(stored: config.meetingEngine, hasKey: hasKey)
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

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
    )!
    static let silenceHintText = "No audio from other apps yet. Check System Settings → Privacy & Security"
        + " → Screen & System Audio Recording."

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
    private(set) var errorMessage: String?

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

    init(chooser: Chooser) {
        self.chooser = chooser
        mode = chooser.defaultMode
    }

    // MARK: - Outputs

    var canStart: Bool { chooser.canStart(mode) }

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

    var sourceLine: String? { engine.map { "\($0.title) · English" } }

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

    var costText: String { Pricing.dollars(cost) }

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

    // MARK: - Inputs

    /// The header's title, mode and engine once the controller has the meeting.
    func show(_ meeting: Meeting) {
        title = meeting.title
        mode = meeting.mode
        engine = meeting.engine
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
            self.summary = summary
        case .systemAudio(let state):
            systemAudio = state
        case .error(let message):
            errorMessage = message
        }
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

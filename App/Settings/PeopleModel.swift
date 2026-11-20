import Foundation
import MWConfig
import MWMeetings
import MWSupport
import MWVoices
import Observation

/// Settings › People (design v8 R24, §5 UI surfaces): everyone remembered, newest heard first,
/// renamed and merged here for future meetings, and locked while a meeting records.
@MainActor
@Observable
final class PeopleModel {
    /// The people store's operations; the default is inert, with no one remembered.
    struct Dependencies {
        var load: @Sendable () async -> [Person] = { [] }
        /// Every person after each change to the store; this model is its one consumer.
        var changes: AsyncStream<[Person]> = AsyncStream { $0.finish() }
        var rename: @Sendable (_ id: UUID, _ name: String) async throws -> Void = { _, _ in }
        var merge: @Sendable (_ source: UUID, _ target: UUID) async throws -> Void = { _, _ in }
        var openMeetingsSettings: @MainActor () -> Void = {}
        var now: @Sendable () -> Date = Date.init
        var calendar = Calendar.current
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        let isUser: Bool
        /// "Local model · Speechmatics Standard · last heard 18 Nov": the routes holding data.
        let detail: String

        /// The user's own entry is never renamed or merged into another.
        var offersRename: Bool { !isUser }
        var offersMerge: Bool { !isUser }
    }

    /// A Dialog the window shows over everything.
    struct Confirmation: Equatable {
        enum Action: Equatable {
            case merge(UUID, into: UUID)
        }

        let action: Action
        let title: String
        let message: String
        let confirmTitle: String
    }

    static let lead = "People you named in meetings while a Remember voices switch was on. Mini Whisper keeps a"
        + " voiceprint or a Speechmatics identifier for each, never audio."
    static let renameNote = "Past meetings keep the old name."
    static let emptyTitle = "No one yet"
    static let emptyMessage = "Turn on Remember voices under Meetings, then name a speaker in a meeting. The people"
        + " you name appear here."
    static let openMeetingsTitle = "Open Meetings Settings"
    private static let recordingNote = "A meeting is recording. Rename, merge and forget are available when it stops."

    private(set) var rows: [Row] = []
    /// Set from the meeting coordinator on every meeting change.
    var isRecording = false {
        didSet { if isRecording { pending = nil } }
    }
    private(set) var pending: Confirmation?

    @ObservationIgnored private let deps: Dependencies
    @ObservationIgnored private let dayFormat: DateFormatter
    @ObservationIgnored private let datedFormat: DateFormatter

    init(deps: Dependencies = Dependencies()) {
        self.deps = deps
        dayFormat = MeetingsListModel.formatter("d MMM", deps.calendar)
        datedFormat = MeetingsListModel.formatter("d MMM yyyy", deps.calendar)
        Task { [weak self, load = deps.load, changes = deps.changes] in
            let people = await load()
            self?.show(people)
            for await people in changes {
                guard let self else { return }
                show(people)
            }
        }
    }

    var groupTitle: String { "Remembered voices · \(rows.count)" }
    var recordingLine: String? { isRecording ? Self.recordingNote : nil }
    var canAct: Bool { !isRecording }

    /// A name a person can take: not blank, and not a default `Speaker N` (R17).
    static func acceptsName(_ draft: String) -> Bool {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.wholeMatch(of: /Speaker \d+/) == nil
    }

    func renameTitle(of row: Row) -> String { "Rename \(row.name)" }

    /// Future meetings only (R24). Returns the refusal to show under the field, or nil once there
    /// is nothing more to do; a name another person has is refused.
    func rename(_ row: Row, to draft: String) async -> String? {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAct, row.offersRename, Self.acceptsName(name), name != row.name else { return nil }
        guard !rows.contains(where: { $0.id != row.id && $0.name == name }) else { return Self.taken(name) }
        do {
            try await deps.rename(row.id, name)
        } catch VoiceStoreError.nameTaken {
            return Self.taken(name)
        } catch {
            Log.voice.error("person not renamed: \(AnyError(error).description)")
        }
        return nil
    }

    private static func taken(_ name: String) -> String {
        "\(name) already exists. Use Merge into… instead."
    }

    /// Everyone else, the user's entry included.
    func mergeTargets(for row: Row) -> [Row] {
        row.offersMerge ? rows.filter { $0.id != row.id } : []
    }

    func mergeMenuTitle(of row: Row) -> String { "Merge \(row.name) into" }

    func mergeTitle(of target: Row) -> String {
        target.isUser ? "\(target.name) (you)" : target.name
    }

    func requestMerge(_ row: Row, into target: Row) {
        guard canAct, row.offersMerge, row.id != target.id else { return }
        pending = Confirmation(
            action: .merge(row.id, into: target.id),
            title: "Merge \(row.name) into \(target.name)?",
            message: "\(target.name) keeps the name and gets both voices. Past meetings are not changed.",
            confirmTitle: "Merge"
        )
    }

    func cancelConfirmation() {
        pending = nil
    }

    func confirm() async {
        guard let pending, canAct else { return }
        self.pending = nil
        switch pending.action {
        case .merge(let source, let target):
            do {
                try await deps.merge(source, target)
            } catch {
                Log.voice.error("people not merged: \(AnyError(error).description)")
            }
        }
    }

    func openMeetingsSettings() {
        deps.openMeetingsSettings()
    }

    // MARK: - Rows

    private func show(_ people: [Person]) {
        let now = deps.now()
        rows = people
            .sorted { ($0.lastHeard ?? $0.createdAt, $1.name) > ($1.lastHeard ?? $1.createdAt, $0.name) }
            .map { Row(id: $0.id, name: $0.name, isUser: $0.isUser, detail: detail(of: $0, now: now)) }
    }

    private func detail(of person: Person, now: Date) -> String {
        var parts = person.local.isEmpty ? [] : ["Local model"]
        parts += MeetingEngine.allCases
            .filter { $0.voiceRoute == .speechmatics && person.speechmatics[$0.providerModel] != nil }
            .map(\.title)
        if let heard = person.lastHeard { parts.append("last heard \(day(heard, now: now))") }
        return parts.joined(separator: " · ")
    }

    private func day(_ date: Date, now: Date) -> String {
        let calendar = deps.calendar
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return (sameYear ? dayFormat : datedFormat).string(from: date)
    }
}

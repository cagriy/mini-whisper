import AppKit
import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestCall
import MWUsage
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct MeetingWindowModelTests {
    private static let current = PlatformInfo(osMajor: 26, osMinor: 0)
    private static let created = Date(timeIntervalSince1970: 1_794_000_000)
    private static let alex = SpeakerLabel(id: 0, name: "Alex", isUser: true)
    private static let utc = TimeZone(identifier: "UTC")!

    private func chooser(
        keys: Set<KeyAccount> = [.speechmatics],
        engine: MeetingEngine? = nil,
        explained: Bool = false,
        overrides: [String: Double] = [:],
        platform: PlatformInfo = current
    ) -> MeetingWindowModel.Chooser {
        var config = Config()
        config.meetingEngine = engine
        config.meetingSystemAudioExplained = explained
        config.pricingOverrides = overrides
        return MeetingWindowModel.Chooser(
            config: config, platform: platform, accountName: "Alex", hasKey: { keys.contains($0) }
        )
    }

    private func model(_ chooser: MeetingWindowModel.Chooser? = nil, clock: ManualClock = ManualClock()) -> MeetingWindowModel {
        MeetingWindowModel(chooser: chooser ?? self.chooser(), timeZone: Self.utc, clock: clock)
    }

    private func segment(_ speaker: Int, _ start: Double, _ text: String) -> Segment {
        Segment(speaker: speaker, start: start, end: start + 2, text: text, session: 1)
    }

    private func note(_ time: Double, _ text: String) -> Note {
        Note(time: time, text: text, createdAt: Self.created)
    }

    // MARK: - Chooser

    @Test func chooserShowsAboutPricePerHourForTheResolvedEngine() {
        #expect(chooser().priceLabel == "About $0.45 per hour")
        #expect(chooser().engineLine == "Engine: Speechmatics Standard")
        #expect(chooser(keys: [.speechmatics], engine: .speechmaticsEnhanced).priceLabel == "About $0.80 per hour")
        #expect(chooser(keys: [.assemblyai], engine: .speechmaticsEnhanced).priceLabel == "About $0.27 per hour")
        #expect(chooser(overrides: ["speechmatics": 0.01]).priceLabel == "About $0.60 per hour")
    }

    @Test func remoteCardIsDisabledBelow142() {
        let old = chooser(platform: PlatformInfo(osMajor: 14, osMinor: 1))
        #expect(old.remoteUnavailableReason == "needs macOS 14.2")
        #expect(old.canStart(.remote) == false)
        #expect(old.canStart(.inRoom))
        #expect(model(old).mode == .inRoom)

        let supported = chooser(platform: PlatformInfo(osMajor: 14, osMinor: 2))
        #expect(supported.remoteUnavailableReason == nil)
        #expect(model(supported).mode == .remote)
    }

    @Test func startIsDisabledWithoutAnyKey() {
        let none = chooser(keys: [])
        #expect(none.canStart(.remote) == false)
        #expect(none.canStart(.inRoom) == false)
        #expect(none.startBlockedReason == "Add a Speechmatics or AssemblyAI key under Keys.")
        #expect(none.priceLabel == nil)
        #expect(chooser().startBlockedReason == nil)
        #expect(model().canStart)
    }

    @Test func systemAudioNoteShowsOnlyBeforeTheFirstRemoteMeeting() {
        #expect(chooser().showsSystemAudioNote(for: .remote))
        #expect(chooser().showsSystemAudioNote(for: .inRoom) == false)
        #expect(chooser(explained: true).showsSystemAudioNote(for: .remote) == false)
        #expect(chooser(platform: PlatformInfo(osMajor: 14, osMinor: 1)).showsSystemAudioNote(for: .remote) == false)
    }

    @Test func remoteDescriptionNamesTheUser() {
        #expect(chooser().description(of: .remote) == "Microphone plus the audio other apps play (Zoom, Teams, Meet)."
            + " Your microphone is labelled Alex; other voices become Speaker 1, 2…")
        #expect(MeetingWindowModel.title(of: .inRoom) == "In the room")
    }

    // MARK: - Transcript

    @Test func consecutiveSegmentsOfOneSpeakerMergeIntoOneParagraph() {
        let model = model()
        model.apply(.segmentAdded(segment(1, 10, "So the rollout")))
        model.apply(.segmentAdded(segment(1, 13, "slips a week.")))
        model.apply(.segmentAdded(segment(0, 16, "Yes.")))

        let paragraphs = model.rows.compactMap(\.paragraph)
        #expect(paragraphs.map(\.text) == ["So the rollout slips a week.", "Yes."])
        #expect(paragraphs.map(\.speaker) == [1, 0])
    }

    @Test func paragraphHeaderIsNameAndFirstWordTime() throws {
        let model = model()
        model.apply(.speakers([Self.alex, SpeakerLabel(id: 1, name: "Speaker 1")]))
        model.apply(.segmentAdded(segment(1, 2342, "So the Northwind rollout")))
        model.apply(.segmentAdded(segment(1, 2350, "slips a week")))

        let paragraph = try #require(model.rows.first?.paragraph)
        #expect(model.name(of: paragraph.speaker) == "Speaker 1")
        #expect(paragraph.time == "00:39:02")

        model.apply(.speakers([Self.alex, SpeakerLabel(id: 1, name: "Marta")]))
        #expect(model.name(of: 1) == "Marta")
        #expect(model.name(of: 7) == "Speaker 7")
    }

    @Test func appendingASegmentTouchesOnlyTheLastParagraph() {
        let model = model()
        for index in 0..<20_000 {
            model.apply(.segmentAdded(segment(index / 4 % 3, Double(index), "w\(index)")))
        }
        let before = model.rows
        #expect(before.count == 5_000)

        model.apply(.segmentAdded(segment(1, 20_000, "last")))

        let after = model.rows
        #expect(after.count == 5_000)
        #expect(after.dropLast() == before.dropLast())
        #expect(after.last?.paragraph?.text == "w19996 w19997 w19998 w19999 last")
        #expect(model.rebuilds == 0)
    }

    @Test func lateOrRevisedSegmentsRegroupParagraphs() {
        let model = model()
        let middle = segment(1, 12, "b")
        model.apply(.segmentAdded(segment(1, 10, "a")))
        model.apply(.segmentAdded(middle))
        model.apply(.segmentAdded(segment(1, 14, "c")))
        model.apply(.segmentAdded(segment(2, 11, "late")))
        #expect(model.rows.map(\.text) == ["a", "late", "b c"])

        var revised = middle
        revised.speaker = 2
        model.apply(.segmentUpdated(revised))
        #expect(model.rows.map(\.text) == ["a", "late b", "c"])
    }

    @Test func partialRendersAfterTheLastParagraph() {
        let model = model()
        model.apply(.speakers([Self.alex, SpeakerLabel(id: 1, name: "Speaker 1")]))
        model.apply(.segmentAdded(segment(1, 10, "Agreed.")))

        model.apply(.partial("I think the cap", speaker: 0))
        #expect(model.partial == MeetingWindowModel.Partial(text: "I think the cap", header: "Alex"))
        model.apply(.partial("and the demo", speaker: 1))
        #expect(model.partial == MeetingWindowModel.Partial(text: "and the demo", header: nil))
        model.apply(.partial("unattributed", speaker: nil))
        #expect(model.partial?.header == nil)

        model.apply(.segmentAdded(segment(0, 14, "I think the cap should default to 25.")))
        #expect(model.partial == nil)
        #expect(model.rows.count == 2)
        model.apply(.partial("", speaker: 0))
        #expect(model.partial == nil)
    }

    @Test func gapMarkerReadsTranscriptGapConnectionLost() {
        let model = model()
        model.apply(.segmentAdded(segment(1, 2500, "Agreed.")))
        model.apply(.marker(Marker(kind: .gap, start: 2508, end: 2523, reason: "connection lost")))
        model.apply(.marker(Marker(kind: .gap, start: 2600, end: 2610, reason: "input device changed")))

        #expect(model.rows.map(\.text) == [
            "Agreed.",
            "Transcript gap 00:41:48–00:42:03 (connection lost)",
            "Transcript gap 00:43:20–00:43:30 (input device changed)",
        ])
    }

    @Test func pausedMarkersReadPausedAndMacSlept() {
        let model = model()
        model.apply(.marker(Marker(kind: .paused, start: 2650, end: 2650)))
        #expect(model.rows.map(\.text) == ["Paused from 00:44:10"])

        model.apply(.marker(Marker(kind: .paused, start: 2650, end: 2790)))
        #expect(model.rows.map(\.text) == ["Paused 00:44:10–00:46:30"])

        model.apply(.marker(Marker(kind: .sleep, start: 3000, end: 3600)))
        #expect(model.rows.last?.text == "Paused 00:50:00–01:00:00 (Mac slept)")
    }

    @Test func notesAppearInlineAtTheirTimeAndInThePane() {
        let model = model()
        model.apply(.segmentAdded(segment(2, 2380, "I can do the refresh tonight.")))
        model.apply(.segmentAdded(segment(2, 2410, "Wednesday instead.")))
        model.apply(.note(note(2405, "Ask ops for a Wednesday maintenance window")))
        model.apply(.note(note(760, "Marta owns the migration script")))

        #expect(model.rows.map(\.text) == [
            "00:12:40 · Marta owns the migration script",
            "I can do the refresh tonight.",
            "00:40:05 · Ask ops for a Wednesday maintenance window",
            "Wednesday instead.",
        ])
        #expect(model.notes.map(\.time) == [760, 2405])
        #expect(model.notes.first.map(MeetingWindowModel.time(of:)) == "00:12:40")
    }

    @Test func noteTimeIsTheFirstKeystroke() throws {
        let model = model()
        model.apply(.elapsed(2405))
        model.noteDraft = "A"
        model.apply(.elapsed(2410))
        model.noteDraft = "Ask ops\nfor a window "

        let committed = try #require(model.commitNote())
        #expect(committed == MeetingWindowModel.DraftNote(text: "Ask ops\nfor a window", time: 2405))
        #expect(model.noteDraft == "")

        model.noteDraft = "  "
        #expect(model.commitNote() == nil)
        model.noteDraft = ""
        model.apply(.elapsed(2420))
        model.noteDraft = "Next"
        #expect(model.commitNote()?.time == 2420)
    }

    // MARK: - Header

    @Test func connectionChipReadsReconnectingWithAttempt() {
        let model = model()
        #expect(model.connectionChip == nil)
        model.apply(.connection(.reconnecting(attempt: 2)))
        #expect(model.connectionChip == "Reconnecting (2)")
        model.apply(.connection(.connected))
        #expect(model.connectionChip == nil)
        model.apply(.connection(.reconnecting(attempt: 1)))
        model.apply(.state(.paused(.user)))
        #expect(model.connectionChip == nil)
    }

    @Test func captureChipReadsSystemAudioOff() {
        let remote = model()
        #expect(remote.captureChip == "Mic")
        remote.apply(.systemAudio(.on))
        #expect(remote.captureChip == "Mic · System audio")
        remote.apply(.systemAudio(.unavailable("needs macOS 14.2")))
        #expect(remote.captureChip == "System audio off")

        let inRoom = model()
        inRoom.mode = .inRoom
        #expect(inRoom.captureChip == "Mic")
    }

    @Test func elapsedAndCostFormat() {
        let model = model()
        #expect(model.elapsedText == "00:00:00")
        #expect(model.costText == "$0.00")
        model.apply(.elapsed(2537))
        model.apply(.cost(0.3166))
        #expect(model.elapsedText == "00:42:17")
        #expect(model.costText == "$0.32")
    }

    @Test func headerShowsTheMeetingTitleModeAndEngine() {
        let model = model()
        model.show(Meeting(
            title: "Zoom · 9 Nov 2026 14:30", startedAt: Self.created, mode: .remote,
            engine: .speechmaticsStandard, userName: "Alex"
        ))
        #expect(model.title == "Zoom · 9 Nov 2026 14:30")
        #expect(MeetingWindowModel.title(of: model.mode) == "Remote call")
        #expect(model.sourceLine == "Speechmatics Standard · English")
        #expect(model.pauseTitle == "Pause")
        model.apply(.state(.paused(.sleep)))
        #expect(model.pauseTitle == "Resume")
    }

    @Test func silenceHintTextAndPaneURL() {
        let model = model()
        #expect(model.silenceHint == nil)
        model.apply(.systemAudio(.silentHint))
        #expect(model.silenceHint == "No audio from other apps yet. Check System Settings → Privacy & Security"
            + " → Screen & System Audio Recording.")
        #expect(MeetingWindowModel.privacySettingsURL.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }

    @Test func renameToAnExistingNameAsksToMerge() {
        let model = model()
        model.apply(.speakers([Self.alex, SpeakerLabel(id: 1, name: "Marta"), SpeakerLabel(id: 3, name: "Speaker 3")]))

        #expect(model.renameTitle(of: 3) == "Rename Speaker 3 (every segment)")
        #expect(model.mergePrompt(renaming: 3, to: " Marta ") == "Merge Speaker 3 into Marta?")
        #expect(model.mergePrompt(renaming: 3, to: "Priya") == nil)
        #expect(model.mergePrompt(renaming: 1, to: "Marta") == nil)
    }

    // MARK: - Stopped

    private static let startedAt = Date(timeIntervalSince1970: 1_794_234_600)
    private static let summary = Summary(
        text: """
        ## Summary
        The Northwind rollout stays on schedule.

        ## Decisions
        - Sign-off moves to Wednesday (**Priya**).

        ## Action items
        - **Priya**: refresh staging data tonight.
        - **Marta**: migration script by Wednesday.

        ## Open questions
        - Whether the cap applies to trial accounts.
        """,
        model: "claude-sonnet-5-5",
        createdAt: Date(timeIntervalSince1970: 1_794_237_580),
        inputTokens: 12_480,
        outputTokens: 610,
        costUSD: 0.03106
    )

    private static func meeting(title: String = "Zoom · 9 Nov 2026 14:30", ended: Bool = false) -> Meeting {
        Meeting(
            title: title, startedAt: startedAt,
            endedAt: ended ? Date(timeIntervalSince1970: 1_794_237_560) : nil,
            durationSeconds: ended ? 2932 : 0, mode: .remote, engine: .speechmaticsStandard, userName: "Alex",
            billing: Billing(engineSeconds: 2932, costUSD: ended ? 0.3665 : 0)
        )
    }

    /// A stopped meeting with one segment unless `transcribed` is false.
    private func stopped(
        _ summary: SummaryState?, transcribed: Bool = true, clock: ManualClock = ManualClock()
    ) -> MeetingWindowModel {
        let model = model(clock: clock)
        model.show(Self.meeting())
        if transcribed { model.apply(.segmentAdded(segment(1, 10, "Agreed."))) }
        model.apply(.state(.stopped))
        if let summary { model.apply(.summary(summary)) }
        return model
    }

    @Test func noKeyPanelReadsAddAnAnthropicKey() {
        let model = stopped(.none("No summary: add an Anthropic key under Keys."))
        #expect(model.summaryPanel == .message("No summary: add an Anthropic key under Keys.", canSummarise: true))
    }

    @Test func failedPanelShowsTheReasonAndSummarise() {
        let model = stopped(.failed("HTTP 529"))
        #expect(model.summaryPanel == .message("HTTP 529", canSummarise: true))
        #expect(model.canSummarise)
    }

    @Test func declinedPanelReadsSummaryDeclinedCategory() {
        let model = stopped(.failed("Summary declined (cyber)"))
        #expect(model.summaryPanel == .message("Summary declined (cyber)", canSummarise: true))
    }

    @Test func emptyPanelReadsNothingWasTranscribed() {
        let declined = stopped(.none("Nothing was transcribed."), transcribed: false)
        #expect(declined.summaryPanel == .message("Nothing was transcribed.", canSummarise: false))
        // An empty meeting opened from the list has no summary event at all.
        #expect(stopped(nil, transcribed: false).summaryPanel == .message("Nothing was transcribed.", canSummarise: false))
    }

    private static let meta = "Claude Sonnet 5.5 · 15:19 · 12.5k in / 610 out tokens · $0.03"

    @Test func summaryPanelForEachOfTheSixStates() {
        let blocks = SummaryDocument(markdown: Self.summary.text).blocks
        #expect(stopped(.none("No summary: add an Anthropic key under Keys.")).summaryPanel
            == .message("No summary: add an Anthropic key under Keys.", canSummarise: true))
        #expect(stopped(.writing).summaryPanel == .writing)
        #expect(stopped(.ready(Self.summary)).summaryPanel == .ready(blocks: blocks, meta: Self.meta, notice: nil))
        #expect(stopped(.failed("HTTP 529")).summaryPanel == .message("HTTP 529", canSummarise: true))

        let rewriting = stopped(.ready(Self.summary))
        rewriting.apply(.summary(.rewriting(Self.summary)))
        #expect(rewriting.summaryPanel == .ready(blocks: blocks, meta: Self.meta, notice: .rewriting))
        #expect(rewriting.canSummarise == false)

        let kept = stopped(.ready(Self.summary))
        kept.apply(.summary(.rewriting(Self.summary)))
        kept.apply(.summary(.kept(Self.summary, reason: "API error (503).")))
        #expect(kept.summaryPanel == .ready(blocks: blocks, meta: Self.meta, notice: .failed("API error (503).")))
        #expect(kept.canSummarise == false)
    }

    @Test func fourSectionSummaryRendersAsHeadedBlocks() {
        #expect(stopped(.ready(Self.summary)).summaryPanel == .ready(blocks: [
            .heading(level: 2, text: "Summary"),
            .paragraph("The Northwind rollout stays on schedule."),
            .heading(level: 2, text: "Decisions"),
            .item(depth: 0, ordinal: nil, text: "Sign-off moves to Wednesday (**Priya**)."),
            .heading(level: 2, text: "Action items"),
            .item(depth: 0, ordinal: nil, text: "**Priya**: refresh staging data tonight."),
            .item(depth: 0, ordinal: nil, text: "**Marta**: migration script by Wednesday."),
            .heading(level: 2, text: "Open questions"),
            .item(depth: 0, ordinal: nil, text: "Whether the cap applies to trial accounts."),
        ], meta: Self.meta, notice: nil))
    }

    @Test func partialMarkStaysInTheMeta() {
        let long = model()
        long.show(Self.meeting())
        long.apply(.segmentAdded(segment(1, 0, String(repeating: "a", count: 600_000))))
        long.apply(.state(.stopped))
        let partial = Self.meta + " · partial"

        long.apply(.summary(.ready(Self.summary)))
        #expect(Self.meta(of: long.summaryPanel) == partial)
        long.apply(.summary(.rewriting(Self.summary)))
        #expect(Self.meta(of: long.summaryPanel) == partial)
        long.apply(.summary(.kept(Self.summary, reason: "API error (503).")))
        #expect(Self.meta(of: long.summaryPanel) == partial)
        #expect(Self.meta(of: stopped(.ready(Self.summary)).summaryPanel) == Self.meta)
    }

    private static func meta(of panel: MeetingWindowModel.SummaryPanel?) -> String? {
        if case .ready(_, let meta, _)? = panel { meta } else { nil }
    }

    @Test func summariseButtonExistsOnlyWithoutASummary() {
        let model = model()
        model.show(Self.meeting())
        model.apply(.segmentAdded(segment(1, 10, "Agreed.")))
        model.apply(.state(.recording))
        #expect(model.summaryPanel == nil)
        #expect(model.canSummarise == false)

        model.apply(.state(.stopped))
        #expect(model.summaryPanel == .message("No summary yet.", canSummarise: true))
        model.apply(.summary(.writing))
        #expect(model.summaryPanel == .writing)
        #expect(model.canSummarise == false)
        model.apply(.summary(.ready(Self.summary)))
        #expect(model.canSummarise == false)
    }

    @Test func editAndReassignAreOfferedOnlyWhenStopped() throws {
        let model = model()
        let first = segment(1, 10, "So the rollout")
        let second = segment(1, 13, "slips a week.")
        model.apply(.speakers([Self.alex, SpeakerLabel(id: 1, name: "Marta")]))
        model.apply(.segmentAdded(first))
        model.apply(.segmentAdded(second))
        model.apply(.state(.recording))
        let drafts = [
            MeetingWindowModel.SegmentEdit(segment: first.id, text: " So the Northwind rollout "),
            MeetingWindowModel.SegmentEdit(segment: second.id, text: "slips a week."),
        ]
        #expect(model.canEdit == false)
        #expect(model.edits(drafts).isEmpty)
        #expect(model.reassignChoices(for: first.id).isEmpty)

        model.apply(.state(.stopped))
        let paragraph = try #require(model.rows.first?.paragraph)
        #expect(model.canEdit)
        #expect(model.segments(in: paragraph).map(\.text) == ["So the rollout", "slips a week."])
        #expect(model.edits(drafts) == [.init(segment: first.id, text: "So the Northwind rollout")])
        #expect(model.edits([.init(segment: second.id, text: "  ")]).isEmpty)
        #expect(model.reassignChoices(for: first.id).count == 2)
    }

    @Test func reassignMenuListsEverySpeaker() {
        let model = model()
        let marta = segment(1, 10, "Agreed.")
        model.apply(.speakers([Self.alex, SpeakerLabel(id: 1, name: "Marta"), SpeakerLabel(id: 2, name: "Priya")]))
        model.apply(.segmentAdded(marta))
        model.apply(.state(.stopped))

        #expect(model.reassignChoices(for: marta.id) == [
            .init(id: 0, name: "Alex", isCurrent: false),
            .init(id: 1, name: "Marta", isCurrent: true),
            .init(id: 2, name: "Priya", isCurrent: false),
        ])
        #expect(model.reassignChoices(for: UUID()).isEmpty)
    }

    @Test func titleEditCallsRetitle() {
        let model = model()
        model.show(Self.meeting())

        #expect(model.commitTitle("  Northwind rollout sync ") == "Northwind rollout sync")
        #expect(model.title == "Northwind rollout sync")
        #expect(model.commitTitle("Northwind rollout sync") == nil)
        #expect(model.commitTitle("   ") == nil)
        #expect(model.title == "Northwind rollout sync")
    }

    @Test func stoppedHeaderShowsDurationTotalAndEndTime() {
        let model = model()
        model.show(Self.meeting())
        model.apply(.elapsed(2930))
        model.apply(.cost(0.36))
        #expect(model.endedChip == nil)

        model.apply(.state(.stopped))
        model.show(Self.meeting(ended: true))
        #expect(model.elapsedText == "00:48:52")
        #expect(model.endedChip == "Ended 15:19")
        #expect(model.costText == "$0.37")
        model.apply(.summary(.ready(Self.summary)))
        #expect(model.costText == "$0.40")
    }

    // MARK: - Regenerate

    private static let regenerated = Summary(
        text: "## Rollout\n- On schedule.", model: "claude-sonnet-5-5",
        createdAt: Date(timeIntervalSince1970: 1_794_240_000), inputTokens: 13_000, outputTokens: 480, costUSD: 0.05
    )

    @Test func costAfterARegenerateIncludesTheReplacedSummary() {
        let model = stopped(.ready(Self.summary))
        model.show(Self.meeting(ended: true))

        model.apply(.summary(.rewriting(Self.summary)))
        #expect(model.costText == Pricing.dollars(0.3665 + 0.03106))
        model.apply(.summary(.ready(Self.regenerated)))
        #expect(model.costText == Pricing.dollars(0.3665 + 0.03106 + 0.05))
        #expect(model.costText == "$0.45")

        // Nothing is replaced when the summary is kept.
        model.apply(.summary(.rewriting(Self.regenerated)))
        model.apply(.summary(.kept(Self.regenerated, reason: "API error (503).")))
        #expect(model.costText == "$0.45")
    }

    @Test func showReadsTheReplacedCostFromBilling() {
        var meeting = Self.meeting(ended: true)
        meeting.billing.replacedSummaryCostUSD = 0.03106
        let model = stopped(.ready(Self.regenerated))

        model.show(meeting)

        #expect(model.costText == Pricing.dollars(0.3665 + 0.03106 + 0.05))
    }

    @Test func copyAndRegenerateAvailability() {
        let live = model()
        live.apply(.state(.recording))
        #expect(live.canCopySummary == false)
        #expect(live.canRegenerate == false)

        let cases: [(SummaryState?, copy: Bool, regenerate: Bool)] = [
            (nil, false, false),
            (.none("No summary: add an Anthropic key under Keys."), false, false),
            (.failed("HTTP 529"), false, false),
            (.writing, false, false),
            (.ready(Self.summary), true, true),
            (.rewriting(Self.summary), true, false),
            (.kept(Self.summary, reason: "API error (503)."), true, true),
        ]
        for (state, copy, regenerate) in cases {
            let model = stopped(state)
            #expect(model.canCopySummary == copy, "\(String(describing: state))")
            #expect(model.canRegenerate == regenerate, "\(String(describing: state))")
        }
    }

    @Test func regeneratePromptNamesTheCurrentCost() {
        let model = stopped(.ready(Self.summary))
        #expect(model.regeneratePrompt
            == "The current summary cost $0.03. It stays until the new one arrives, and stays if the request fails.")
        model.apply(.summary(.rewriting(Self.summary)))
        #expect(model.regeneratePrompt == nil)
        model.apply(.summary(.ready(Self.regenerated)))
        #expect(model.regeneratePrompt
            == "The current summary cost $0.05. It stays until the new one arrives, and stays if the request fails.")
        #expect(stopped(nil).regeneratePrompt == nil)
    }

    // MARK: - Finished page

    private static let topics = Summary(
        text: """
        ## Catalog entries
        - Existing entries were reviewed in the shared sheet
          - Harbour billing
        ## Next Steps
        1. **Tomas** adds the two projects by Friday
        2. See [the index](https://example.com/index)

        """,
        model: "claude-sonnet-5-5",
        createdAt: Date(timeIntervalSince1970: 1_794_237_580),
        inputTokens: 12_480,
        outputTokens: 610,
        costUSD: 0.03106
    )

    @Test func copyPayloadCarriesTitleAndSummaryInThreeForms() throws {
        let model = stopped(.ready(Self.topics))
        let payload = try #require(model.copyPayload)
        let document = SummaryDocument(markdown: Self.topics.text)

        #expect(payload.markdown == SummaryDocument.markdown(title: "Zoom · 9 Nov 2026 14:30", summary: Self.topics.text))
        #expect(payload.markdown.hasPrefix("# Zoom · 9 Nov 2026 14:30\n\n## Catalog entries\n"))
        #expect(payload.html == document.html(title: "Zoom · 9 Nov 2026 14:30"))
        let rtf = try NSAttributedString(
            data: payload.rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
        )
        #expect(rtf.string == SummaryRichText.attributed(title: "Zoom · 9 Nov 2026 14:30", blocks: document.blocks).string)
        #expect(rtf.string.hasPrefix("Zoom · 9 Nov 2026 14:30\nCatalog entries\n"))

        _ = model.commitTitle("Catalog review")
        #expect(model.copyPayload?.markdown.hasPrefix("# Catalog review\n\n") == true)
        #expect(stopped(nil).copyPayload == nil)
        #expect(stopped(.writing).copyPayload == nil)
    }

    @Test func justCopiedClearsAfter1point5Seconds() async throws {
        let clock = ManualClock()
        let model = stopped(.ready(Self.summary), clock: clock)
        var sleeps = clock.sleeps.makeAsyncIterator()
        #expect(model.justCopied == false)

        model.didCopySummary()

        #expect(model.justCopied)
        // Without a reset under way the clock is never asked to sleep, and the wait below would not end.
        try #require(model.copyReset != nil)
        #expect(await sleeps.next() == .milliseconds(1500))
        #expect(model.justCopied)
        clock.wake()
        await model.copyReset?.value
        #expect(model.justCopied == false)
    }

    @Test func opensOnSummaryOrOnTranscriptForATestCall() {
        let meeting = model()
        meeting.show(Self.meeting())
        meeting.selectedTab = .notes
        meeting.apply(.state(.stopped))
        #expect(meeting.selectedTab == .summary)

        let test = model()
        test.show(Self.testMeeting())
        test.apply(.state(.stopped))
        #expect(test.selectedTab == .transcript)
    }

    @Test func tabIsSetOnlyWhenTheMeetingFirstStops() {
        let model = model()
        model.show(Self.meeting())
        model.apply(.state(.recording))
        model.apply(.state(.stopped))
        model.selectedTab = .notes

        model.apply(.state(.stopped))
        model.apply(.summary(.writing))
        model.apply(.summary(.ready(Self.summary)))

        #expect(model.selectedTab == .notes)
    }

    @Test func notesTabCountsOnlyAboveZero() {
        let model = model()
        #expect(model.notesTabTitle == "Notes")
        model.apply(.note(note(760, "Marta owns the migration script")))
        model.apply(.note(note(2405, "Ask ops for a window")))
        #expect(model.notesTabTitle == "Notes · 2")
    }

    @Test func chipsReadDateRangeDurationModeSpeakersAndCost() {
        let model = model()
        model.show(Self.meeting())
        model.apply(.speakers([Self.alex, SpeakerLabel(id: 1, name: "Marta"), SpeakerLabel(id: 2, name: "Priya")]))
        #expect(model.chips.isEmpty)

        model.apply(.state(.stopped))
        model.show(Self.meeting(ended: true))
        #expect(model.chips == ["Mon 9 Nov · 14:30–15:19", "48 min", "Remote call", "Alex, Marta, Priya", "$0.37 total"])

        model.apply(.speakers([
            Self.alex, SpeakerLabel(id: 1, name: "Marta"), SpeakerLabel(id: 2, name: "Priya"),
            SpeakerLabel(id: 3, name: "Speaker 3"), SpeakerLabel(id: 4, name: "Speaker 4"),
        ]))
        model.apply(.summary(.ready(Self.summary)))
        #expect(model.chips == ["Mon 9 Nov · 14:30–15:19", "48 min", "Remote call", "Alex, Marta, Priya +2", "$0.40 total"])

        model.apply(.speakers([]))
        #expect(model.chips == ["Mon 9 Nov · 14:30–15:19", "48 min", "Remote call", "$0.40 total"])
    }

    @Test func pillTextIsMinutesSecondsUnderAnHourThenHours() {
        let model = model()
        model.show(Self.meeting())
        model.apply(.state(.recording))
        #expect(model.pillTitle == "Zoom · 9 Nov 2026 14:30")
        #expect(model.pillDetail == "00:00")
        for (seconds, text) in [(768.4, "12:48"), (3599, "59:59"), (3600, "1:00:00"), (4380, "1:13:00"), (36_061, "10:01:01")] {
            model.apply(.elapsed(seconds))
            #expect(model.pillDetail == text)
        }
    }

    @Test func pillReadsPausedAndStarting() {
        let model = model()
        model.apply(.state(.starting))
        #expect(model.pillTitle == "Starting…")
        model.show(Self.meeting())
        model.apply(.state(.recording))
        model.apply(.elapsed(768))
        model.apply(.state(.paused(.user)))
        #expect(model.pillDetail == "Paused")
        model.apply(.state(.paused(.sleep)))
        #expect(model.pillDetail == "Paused")
        model.apply(.state(.recording))
        #expect(model.pillDetail == "12:48")
    }

    @Test func sourceLineInvitesEditingOnlyOutsideATestCall() {
        let model = model()
        model.show(Self.meeting())
        model.apply(.state(.recording))
        #expect(model.sourceLine == "Speechmatics Standard · English")
        model.apply(.state(.stopped))
        #expect(model.sourceLine == "Speechmatics Standard · English · double-click a paragraph to edit it,"
            + " click a name to rename the speaker")

        let test = self.model()
        test.show(Self.testMeeting())
        test.apply(.state(.stopped))
        #expect(test.sourceLine == "AssemblyAI Universal-Streaming · English · speaker names stay as the engine"
            + " labelled them")
    }

    // MARK: - Test calls

    private static let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

    private static func testMeeting() -> Meeting {
        Meeting(
            title: "Test call · Sprint planning", startedAt: startedAt, mode: .remote, engine: .assemblyaiStreaming,
            userName: "Alex", test: tag
        )
    }

    @Test func testMeetingCannotPauseAndSaysWhy() {
        let model = model()
        model.show(Self.testMeeting())
        model.apply(.state(.recording))

        #expect(model.isTest)
        #expect(model.canPause == false)
        #expect(model.canStop)
        #expect(model.pauseHelp == "Not available in a test call")

        model.apply(.state(.paused(.sleep)))
        #expect(model.canPause == false)
        #expect(model.canStop)
    }

    @Test func testSourceLineCarriesTheLabellingNote() {
        let model = model()
        model.show(Self.testMeeting())
        model.apply(.state(.recording))
        #expect(model.sourceLine == "AssemblyAI Universal-Streaming · English · speaker names stay as the engine"
            + " labels them; the score checks them")

        model.apply(.state(.stopped))
        #expect(model.sourceLine == "AssemblyAI Universal-Streaming · English · speaker names stay as the engine"
            + " labelled them")
    }

    @Test func ordinaryMeetingsUnchanged() {
        let model = model()
        #expect(model.canPause == false)
        #expect(model.canStop == false)

        model.show(Self.meeting())
        model.apply(.state(.recording))

        #expect(model.isTest == false)
        #expect(model.testCall == nil)
        #expect(model.canPause)
        #expect(model.canStop)
        #expect(model.pauseHelp == nil)
        #expect(model.sourceLine == "Speechmatics Standard · English")
        model.apply(.state(.paused(.user)))
        #expect(model.canPause)
        model.apply(.state(.stopped))
        #expect(model.canPause == false)
        #expect(model.canStop == false)
        #expect(model.sourceLine?.hasPrefix("Speechmatics Standard · English · double-click") == true)
    }

    @Test func testMeetingShowsItsScenariosScriptUntilTheSessionsPaneArrives() throws {
        let model = model()
        model.show(Self.testMeeting())
        let shown = try #require(model.testCall)
        #expect(shown.title == "Script · Sprint planning")

        let session = TestCallPaneModel(scenario: shown.scenario, casting: [:])
        model.attach(session)
        model.show(Self.testMeeting())

        #expect(model.testCall === session)
    }

    @Test func testScoreEventIsKept() {
        let model = model()
        #expect(model.testScore == nil)

        model.apply(.testScore(.missing))
        #expect(model.testScore == .missing)
        model.apply(.testScore(.unreadable))
        #expect(model.testScore == .unreadable)
    }
}

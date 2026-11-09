import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct MeetingWindowModelTests {
    private static let current = PlatformInfo(osMajor: 26, osMinor: 0)
    private static let created = Date(timeIntervalSince1970: 1_794_000_000)
    private static let alex = SpeakerLabel(id: 0, name: "Alex", isUser: true)

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

    private func model(_ chooser: MeetingWindowModel.Chooser? = nil) -> MeetingWindowModel {
        MeetingWindowModel(chooser: chooser ?? self.chooser())
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
}

import Foundation
import MWMeetings
import MWTestCall
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct TestCallPaneModelTests {
    private static let scenario = ScenarioLibrary.scenario(id: "sprint-planning")!
    private static let casting: [TestCallRole: CastVoice] = [
        .a: CastVoice(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
        .b: CastVoice(role: .b, character: "Priya", requested: "Karen", voice: "Karen"),
    ]

    /// The conductor's events up to `last`, the sprint-planning script's turns in order.
    private static func reaching(_ last: Int) -> [ConductorEvent] {
        scenario.lines.prefix(last).enumerated().map { offset, line in
            .line(offset + 1, line.role == .you ? .yourTurn : .voiceSpeaking(line.role))
        }
    }

    private func pane(
        _ events: [ConductorEvent] = [], casting: [TestCallRole: CastVoice] = casting
    ) -> TestCallPaneModel {
        let pane = TestCallPaneModel(scenario: Self.scenario, casting: casting)
        events.forEach(pane.apply)
        return pane
    }

    // MARK: - Script

    @Test func voiceTurnRingsTheLineAndTagsIt() {
        let pane = pane(Self.reaching(1))

        #expect(pane.current?.number == 1)
        #expect(pane.current?.speaker == "Tom")
        #expect(pane.turnTag?.text == "Tom · Daniel voice · speaking")
        #expect(pane.turnTag?.isVoice == true)
        #expect(pane.hint == "Waits for the voice to finish")
        #expect(pane.canSkip)

        var substituted = Self.casting
        substituted[.b]?.voice = "Moira"
        #expect(self.pane(Self.reaching(2), casting: substituted).turnTag?.text == "Priya · Moira voice · speaking")
    }

    @Test func userTurnPromptsAndHints() {
        let pane = pane(Self.reaching(3))

        #expect(pane.current?.number == 3)
        #expect(pane.current?.role == .you)
        #expect(pane.current?.speaker == "You")
        #expect(pane.turnTag?.text == "Your turn · read this line aloud")
        #expect(pane.turnTag?.isVoice == false)
        #expect(pane.hint == "Hands over after a 1.2 s pause")
    }

    @Test func showsUpToThreeEarlierLinesDimmedWithSkipped() {
        #expect(pane(Self.reaching(2)).earlier.map(\.number) == [1])

        let pane = pane(Self.reaching(5) + [.skipped(5, .skipped)])
        // The skipped line leaves the ring before the next line starts.
        #expect(pane.current == nil)
        #expect(pane.canSkip == false)
        #expect(pane.earlier.map(\.number) == [3, 4, 5])
        #expect(pane.earlier.map(\.skipped) == [false, false, true])

        pane.apply(.line(6, .voiceSpeaking(.b)))
        #expect(pane.current?.number == 6)
        #expect(pane.earlier.map(\.number) == [3, 4, 5])
        #expect(pane.earlier.last?.skipped == true)
    }

    @Test func showsTheNextThreeAndTheRestCount() {
        let sixth = pane(Self.reaching(6))
        #expect(sixth.upcoming.map(\.number) == [7, 8, 9])
        #expect(sixth.upcoming.map(\.speaker) == ["Tom", "You", "Priya"])
        #expect(sixth.moreLines == "+ 3 more lines")

        #expect(pane(Self.reaching(8)).moreLines == "+ 1 more line")
        #expect(pane(Self.reaching(10)).upcoming.map(\.number) == [11, 12])
        #expect(pane(Self.reaching(10)).moreLines == nil)

        let before = pane()
        #expect(before.current == nil)
        #expect(before.upcoming.map(\.number) == [1, 2, 3])
        #expect(before.moreLines == "+ 9 more lines")
        #expect(before.hint == nil)
    }

    @Test func headerCountsTheLine() {
        #expect(pane().title == "Script · Sprint planning")
        #expect(pane().progress == nil)
        #expect(pane(Self.reaching(6)).progress == "6 of 12")
    }

    @Test func finishedReadsPressStop() {
        let pane = pane(Self.reaching(12) + [.finished])

        #expect(pane.hint == "Script finished · press Stop for the score")
        #expect(pane.current == nil)
        #expect(pane.canSkip == false)
        #expect(pane.earlier.map(\.number) == [10, 11, 12])
        #expect(pane.upcoming.isEmpty)
        #expect(pane.progress == "12 of 12")
    }

    @Test func sleepShowsTheR12Message() {
        let pane = pane(Self.reaching(6))

        pane.macSlept()

        #expect(pane.hint == "The test call ended when the Mac slept. Press Stop for the score.")
        #expect(pane.current == nil)
        #expect(pane.canSkip == false)
        // A line the conductor announced just before the sleep changes nothing.
        pane.apply(.line(7, .voiceSpeaking(.a)))
        #expect(pane.current == nil)
        #expect(pane.progress == "6 of 12")
    }

    @Test func captureMissingShowsTheCaptureWarning() {
        let pane = pane(Self.reaching(1))
        #expect(pane.notices.isEmpty)

        pane.apply(.captureMissing(1))
        pane.apply(.line(2, .voiceSpeaking(.b)))
        pane.apply(.captureMissing(2))

        #expect(pane.notices == [
            "The test voices are not being captured; the score will count their lines as missed.",
        ])
        #expect(pane.current?.number == 2)
    }

    @Test func voicesFailedShowsTheMessage() {
        let pane = pane(Self.reaching(1) + [
            .skipped(1, .voiceFailed), .line(2, .voiceSpeaking(.b)), .skipped(2, .voiceFailed), .voicesFailed, .finished,
        ])

        #expect(pane.notices == ["The test voices could not play."])
        #expect(pane.hint == "Script finished · press Stop for the score")
        #expect(pane.earlier.map(\.skipped) == [true, true])
    }
}

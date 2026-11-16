import Testing
@testable import MiniWhisper

@MainActor
@Suite struct SilencePromptModelTests {
    @Test func titleFollowsTheMinutes() {
        let model = SilencePromptModel()

        model.minutes = 1
        #expect(model.title == "No one has spoken for 1 minute")
        model.minutes = 2
        #expect(model.title == "No one has spoken for 2 minutes")
        model.minutes = 5
        #expect(model.title == "No one has spoken for 5 minutes")
    }

    @Test(arguments: [(60, "1:00"), (42, "0:42"), (5, "0:05"), (0, "0:00")])
    func countdownTextIsMinutesAndSeconds(secondsLeft: Int, text: String) {
        let model = SilencePromptModel()
        model.secondsLeft = secondsLeft
        #expect(model.countdownText == text)
    }

    @Test(arguments: [(60, 1.0), (42, 0.7), (0, 0.0)])
    func fractionIsTheShareOfTheMinuteLeft(secondsLeft: Int, fraction: Double) {
        let model = SilencePromptModel()
        model.secondsLeft = secondsLeft
        #expect(model.fraction == fraction)
    }

    @Test func eyebrowNamesTheMeetingUnlessItHasNoTitle() {
        let model = SilencePromptModel()

        model.meetingTitle = "Standup"
        #expect(model.eyebrow == "Recording · Standup")
        model.meetingTitle = ""
        #expect(model.eyebrow == "Recording")
        model.meetingTitle = "   "
        #expect(model.eyebrow == "Recording")
    }
}

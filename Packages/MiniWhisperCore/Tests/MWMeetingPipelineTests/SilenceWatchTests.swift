import Foundation
import Testing

@testable import MWMeetingPipeline

@Suite struct SilenceWatchTests {
    private static let oneMinute = SilencePrompt.open(minutes: 1, secondsLeft: 60)

    /// A one-minute watch whose prompt opened at 180 with no speech.
    private func openAtTheGrace() throws -> SilenceWatch {
        var watch = SilenceWatch(threshold: 60)
        try #require(watch.tick(at: 180) == Self.oneMinute)
        return watch
    }

    // MARK: - Opening

    @Test func noPromptBeforeTheGraceHoweverLongTheSilence() {
        var watch = SilenceWatch(threshold: 60)
        #expect(watch.tick(at: 61) == nil)
        #expect(watch.tick(at: 120) == nil)
        #expect(watch.tick(at: 179.9) == nil)
    }

    @Test func promptAtTheGraceWithNoSpeech() {
        var watch = SilenceWatch(threshold: 60)
        #expect(watch.tick(at: 180) == .open(minutes: 1, secondsLeft: 60))
    }

    @Test func promptAtLastSpeechPlusThresholdAfterTheGrace() {
        var watch = SilenceWatch(threshold: 60)
        #expect(watch.segment("Thanks, everyone.", at: 170) == nil)
        #expect(watch.tick(at: 180) == nil)
        #expect(watch.tick(at: 229) == nil)
        #expect(watch.tick(at: 230) == Self.oneMinute)
    }

    @Test func thresholdsOfTwoAndFiveMinutesOpenAtTheirThresholds() {
        var two = SilenceWatch(threshold: 120)
        _ = two.segment("so", at: 100)
        #expect(two.tick(at: 219) == nil)
        #expect(two.tick(at: 220) == .open(minutes: 2, secondsLeft: 60))
        #expect(two.promptMinutes == 2)

        var five = SilenceWatch(threshold: 300)
        _ = five.segment("so", at: 100)
        #expect(five.tick(at: 399) == nil)
        #expect(five.tick(at: 400) == .open(minutes: 5, secondsLeft: 60))
        #expect(five.promptMinutes == 5)

        var twoWithoutSpeech = SilenceWatch(threshold: 120)
        #expect(twoWithoutSpeech.tick(at: 180) == .open(minutes: 2, secondsLeft: 60))

        var fiveWithoutSpeech = SilenceWatch(threshold: 300)
        #expect(fiveWithoutSpeech.tick(at: 299) == nil)
        #expect(fiveWithoutSpeech.tick(at: 300) == .open(minutes: 5, secondsLeft: 60))
    }

    // MARK: - What counts as speech

    @Test func repeatedEmptyAndWhitespacePartialsAreNotSpeech() {
        var watch = SilenceWatch(threshold: 60)
        #expect(watch.partial("so", at: 150) == nil)
        #expect(watch.partial("so", at: 180) == nil)
        #expect(watch.partial("", at: 190) == nil)
        #expect(watch.partial("  ", at: 200) == nil)
        #expect(watch.lastSpeech == 150)
        #expect(watch.tick(at: 209) == nil)
        #expect(watch.tick(at: 210) == Self.oneMinute)
    }

    @Test func anEmptyPartialBetweenTwoEqualTextsLetsTheSecondCount() {
        var watch = SilenceWatch(threshold: 60)
        _ = watch.partial("so", at: 100)
        _ = watch.partial("", at: 110)
        _ = watch.partial("so", at: 150)
        #expect(watch.tick(at: 209) == nil)
        #expect(watch.tick(at: 210) == Self.oneMinute)
    }

    @Test func aNonEmptySegmentIsSpeechAnEmptyOneIsNot() throws {
        var empty = SilenceWatch(threshold: 60)
        #expect(empty.segment("", at: 160) == nil)
        #expect(empty.segment(" \n", at: 170) == nil)
        #expect(empty.lastSpeech == 0)
        #expect(empty.tick(at: 180) == Self.oneMinute)
        #expect(empty.segment("  ", at: 185) == nil)
        #expect(empty.tick(at: 186) == .open(minutes: 1, secondsLeft: 54))

        var spoken = SilenceWatch(threshold: 60)
        #expect(spoken.segment("Let's start.", at: 170) == nil)
        #expect(spoken.lastSpeech == 170)
        #expect(spoken.tick(at: 229) == nil)

        var open = try openAtTheGrace()
        #expect(open.segment("One more thing.", at: 190) == .closed)
        #expect(open.tick(at: 191) == nil)
        #expect(open.tick(at: 250) == Self.oneMinute)
    }

    @Test func speechWhileOpenCloses() throws {
        var watch = try openAtTheGrace()
        #expect(watch.partial("back", at: 190) == .closed)
        #expect(watch.tick(at: 191) == nil)
        #expect(watch.partial("back again", at: 192) == nil)
    }

    @Test func lastSpeechTracksTheLatestSpeech() {
        var watch = SilenceWatch(threshold: 60)
        #expect(watch.lastSpeech == 0)
        _ = watch.partial("a", at: 10)
        #expect(watch.lastSpeech == 10)
        _ = watch.partial("a", at: 15)
        #expect(watch.lastSpeech == 10)
        _ = watch.segment("a b", at: 20)
        #expect(watch.lastSpeech == 20)
        _ = watch.segment("", at: 25)
        #expect(watch.lastSpeech == 20)
        _ = watch.keep(at: 30)
        #expect(watch.lastSpeech == 30)
        _ = watch.suspend()
        watch.restart(at: 40)
        #expect(watch.lastSpeech == 40)
    }

    // MARK: - Countdown

    @Test func countdownRunsSixtyToOneThenExpiresOnce() {
        var watch = SilenceWatch(threshold: 60)
        for (offset, time) in (180...239).enumerated() {
            #expect(watch.tick(at: Double(time)) == .open(minutes: 1, secondsLeft: 60 - offset), "at \(time)")
        }
        #expect(!watch.isExpired)
        #expect(watch.tick(at: 240) == .expired)
        #expect(watch.isExpired)
        #expect(watch.promptMinutes == 1)

        #expect(watch.tick(at: 241) == nil)
        #expect(watch.partial("hello", at: 242) == nil)
        #expect(watch.segment("hello there", at: 243) == nil)
        #expect(watch.keep(at: 244) == nil)
        #expect(watch.suspend() == nil)
        #expect(watch.setThreshold(0) == nil)
        watch.restart(at: 245)
        #expect(watch.tick(at: 600) == nil)
        #expect(watch.isExpired)
        #expect(watch.promptMinutes == 1)
    }

    @Test func fractionalTicksRoundSecondsLeftUp() throws {
        var watch = try openAtTheGrace()
        #expect(watch.tick(at: 180.4) == .open(minutes: 1, secondsLeft: 60))
        #expect(watch.tick(at: 181.2) == .open(minutes: 1, secondsLeft: 59))
        #expect(watch.tick(at: 239.9) == .open(minutes: 1, secondsLeft: 1))
        #expect(watch.tick(at: 240.3) == .expired)
    }

    // MARK: - Closing and restarting

    @Test func keepClosesAndRestartsTheClock() throws {
        var watch = try openAtTheGrace()
        #expect(watch.keep(at: 200) == .closed)
        #expect(watch.tick(at: 201) == nil)
        #expect(watch.tick(at: 259) == nil)
        #expect(watch.tick(at: 260) == Self.oneMinute)

        var closed = SilenceWatch(threshold: 60)
        #expect(closed.keep(at: 150) == nil)
        #expect(closed.tick(at: 180) == nil)
        #expect(closed.tick(at: 209) == nil)
        #expect(closed.tick(at: 210) == Self.oneMinute)
    }

    @Test func suspendClosesIgnoresTicksAndRestartRestartsTheClock() throws {
        var watch = try openAtTheGrace()
        #expect(watch.suspend() == .closed)
        #expect(watch.isSuspended)
        #expect(watch.tick(at: 200) == nil)
        #expect(watch.tick(at: 299) == nil)
        watch.restart(at: 300)
        #expect(!watch.isSuspended)
        #expect(watch.tick(at: 359) == nil)
        #expect(watch.tick(at: 360) == Self.oneMinute)

        var closed = SilenceWatch(threshold: 60)
        #expect(closed.suspend() == nil)
        #expect(closed.isSuspended)
        #expect(closed.tick(at: 600) == nil)
    }

    // MARK: - Threshold changes

    @Test func thresholdZeroClosesAnOpenPromptAndNeverOpens() throws {
        var watch = try openAtTheGrace()
        #expect(watch.setThreshold(0) == .closed)
        #expect(watch.threshold == 0)
        #expect(watch.tick(at: 181) == nil)
        #expect(watch.tick(at: 600) == nil)
        #expect(watch.setThreshold(0) == nil)

        var off = SilenceWatch(threshold: 0)
        #expect(off.tick(at: 180) == nil)
        #expect(off.tick(at: 3600) == nil)
    }

    @Test func anotherThresholdKeepsTheOpenCountdownAndMinutes() throws {
        var watch = try openAtTheGrace()
        #expect(watch.setThreshold(300) == nil)
        #expect(watch.threshold == 300)
        #expect(watch.tick(at: 200) == .open(minutes: 1, secondsLeft: 40))
        #expect(watch.tick(at: 239) == .open(minutes: 1, secondsLeft: 1))
        #expect(watch.tick(at: 240) == .expired)
        #expect(watch.promptMinutes == 1)
    }
}

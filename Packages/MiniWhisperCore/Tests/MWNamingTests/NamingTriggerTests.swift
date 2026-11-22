import Testing

import MWNaming

@Suite struct NamingTriggerTests {
    private let armed = 12.3

    @Test func noFireWithoutArming() {
        var trigger = NamingTrigger()
        let fired = [
            trigger.segment(speaker: 1, hasName: false, at: 1),
            trigger.segment(speaker: 2, hasName: false, at: 2),
            trigger.tick(at: 100),
        ]
        #expect(fired == [false, false, false])
    }

    @Test func sameSpeakerDoesNotFireAndAnotherSpeakerDoes() {
        var trigger = NamingTrigger()
        let fired = [
            trigger.segment(speaker: 1, hasName: true, at: armed),
            trigger.segment(speaker: 1, hasName: false, at: armed + 5),
            trigger.segment(speaker: 2, hasName: false, at: armed + 6),
            trigger.segment(speaker: 1, hasName: false, at: armed + 7),
        ]
        #expect(fired == [false, false, true, false])
    }

    @Test func firesTwentySecondsAfterArming() {
        var trigger = NamingTrigger()
        let fired = [
            trigger.segment(speaker: 1, hasName: true, at: armed),
            trigger.tick(at: armed + 19.9),
            trigger.tick(at: armed + 20),
            trigger.tick(at: armed + 40),
        ]
        #expect(fired == [false, false, true, false])
    }

    @Test func furtherNamesFromTheArmedSpeakerKeepTheFirstDeadline() {
        var trigger = NamingTrigger()
        let fired = [
            trigger.segment(speaker: 1, hasName: true, at: armed),
            trigger.segment(speaker: 1, hasName: true, at: armed + 15),
            trigger.tick(at: armed + 20),
        ]
        #expect(fired == [false, false, true])
    }

    @Test func delayIsConfigurable() {
        var trigger = NamingTrigger(delay: 5)
        let fired = [
            trigger.segment(speaker: 1, hasName: true, at: armed),
            trigger.tick(at: armed + 4.9),
            trigger.tick(at: armed + 5),
        ]
        #expect(fired == [false, false, true])
    }

    @Test func firesDuringFlightCoalesceIntoOneFollowUp() {
        var trigger = NamingTrigger()
        trigger.begin()
        #expect(trigger.inFlight)
        var fired: [Bool] = []
        for start in [armed, armed + 10, armed + 20] {
            fired.append(trigger.segment(speaker: 1, hasName: true, at: start))
            fired.append(trigger.segment(speaker: 2, hasName: false, at: start + 1))
        }
        #expect(fired == Array(repeating: false, count: 6))

        let followUp = trigger.end()
        #expect(followUp)
        #expect(!trigger.inFlight)
        trigger.begin()
        let second = trigger.end()
        #expect(!second)
    }

    @Test func disarmDropsArmedState() {
        var trigger = NamingTrigger()
        _ = trigger.segment(speaker: 1, hasName: true, at: armed)
        trigger.disarm()
        let fired = [
            trigger.segment(speaker: 2, hasName: false, at: armed + 1),
            trigger.tick(at: armed + 20),
        ]
        #expect(fired == [false, false])
    }

    @Test func disarmDropsPendingFollowUp() {
        var trigger = NamingTrigger()
        trigger.begin()
        _ = trigger.segment(speaker: 1, hasName: true, at: armed)
        _ = trigger.segment(speaker: 2, hasName: false, at: armed + 1)
        trigger.disarm()
        let followUp = trigger.end()
        #expect(!followUp)
    }

    @Test func nameBearingSegmentThatFiresRearmsForItsSpeaker() {
        var trigger = NamingTrigger()
        let fired = [
            trigger.segment(speaker: 1, hasName: true, at: armed),
            trigger.segment(speaker: 2, hasName: true, at: armed + 4),
            trigger.segment(speaker: 2, hasName: false, at: armed + 5),
            trigger.segment(speaker: 1, hasName: false, at: armed + 6),
        ]
        #expect(fired == [false, true, false, true])
    }

    @Test func rearmedTriggerTimesOutFromItsOwnSegment() {
        var trigger = NamingTrigger()
        let rearmed = armed + 4
        let fired = [
            trigger.segment(speaker: 1, hasName: true, at: armed),
            trigger.segment(speaker: 2, hasName: true, at: rearmed),
            trigger.tick(at: rearmed + 19.9),
            trigger.tick(at: rearmed + 20),
        ]
        #expect(fired == [false, true, false, true])
    }
}

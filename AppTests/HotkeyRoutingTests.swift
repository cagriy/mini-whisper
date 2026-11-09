import MWHotkeys
import Testing
@testable import MiniWhisper

@Suite struct HotkeyRoutingTests {
    @Test func meetingPressTogglesTheMeeting() {
        #expect(HotkeyRouting.route(.pressed(.meeting), meetingActive: false) == .meeting)
        #expect(HotkeyRouting.route(.pressed(.meeting), meetingActive: true) == .meeting)
        #expect(HotkeyRouting.route(.released(.meeting), meetingActive: true) == .ignore)
    }

    @Test func dictationPressWhileAMeetingIsActiveShowsTheNotice() {
        let notice = HotkeyRouting.Route.notice("Dictation is off while a meeting is recording")
        #expect(HotkeyRouting.route(.pressed(.paste), meetingActive: true) == notice)
        #expect(HotkeyRouting.route(.pressed(.pasteSubmit), meetingActive: true) == notice)
    }

    @Test func dictationReleaseWhileActiveIsIgnored() {
        #expect(HotkeyRouting.route(.released(.paste), meetingActive: true) == .ignore)
        #expect(HotkeyRouting.route(.released(.pasteSubmit), meetingActive: true) == .ignore)
    }

    @Test func dictationPressWhenIdleGoesToDictation() {
        #expect(HotkeyRouting.route(.pressed(.paste), meetingActive: false) == .dictation(.pressed(.paste)))
        #expect(HotkeyRouting.route(.released(.pasteSubmit), meetingActive: false) == .dictation(.released(.pasteSubmit)))
    }

    @Test func captureActionsStillReachSettings() throws {
        let combo = try HotkeyCombo.parse("ctrl+alt+cmd+j")
        for active in [false, true] {
            #expect(HotkeyRouting.route(.captured(combo), meetingActive: active) == .settings(.captured(combo)))
            #expect(HotkeyRouting.route(.captureRejected, meetingActive: active) == .settings(.captureRejected))
        }
    }
}

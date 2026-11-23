import Testing

@testable import MiniWhisper

@Suite struct QuitPolicyTests {
    @Test func aQuitTheMenuPreparedTerminatesNowWithoutAsking() {
        var asked = false

        let reply = QuitPolicy.reply(prepared: true, recording: true, hasMainWindow: true) {
            asked = true
            return false
        }

        #expect(reply == .now)
        #expect(!asked)
    }

    @Test func nothingToStopOrSaveTerminatesNow() {
        #expect(QuitPolicy.reply(prepared: false, recording: false, hasMainWindow: false) { true } == .now)
    }

    @Test func aMainWindowIsSavedFirst() {
        #expect(QuitPolicy.reply(prepared: false, recording: false, hasMainWindow: true) { true } == .afterCleanup)
    }

    @Test func aRecordingMeetingAsksFirst() {
        #expect(QuitPolicy.reply(prepared: false, recording: true, hasMainWindow: false) { false } == .cancel)
        #expect(QuitPolicy.reply(prepared: false, recording: true, hasMainWindow: false) { true } == .afterCleanup)
    }
}

import Testing

import MWStats

@Suite struct StatsRecordingTests {
    @Test func theTenOutcomesKeepTheirStoredNames() {
        #expect(DictationAttempt.Outcome.allCases.map(\.rawValue) == [
            "delivered", "too_short", "silent", "superseded", "no_key",
            "empty", "failed", "mic_error", "device_changed", "aborted",
        ])
    }
}

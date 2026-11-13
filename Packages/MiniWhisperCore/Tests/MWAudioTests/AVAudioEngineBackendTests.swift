import AVFAudio
import Testing

@testable import MWAudio

@Suite struct AVAudioEngineBackendTests {
    /// Measured: advanced ducking leaves other apps 30 dB down at every level; plain `.min` 8 dB.
    @Test func otherAudioDuckingIsPlainAndMinimal() {
        let ducking = AVAudioEngineBackend.otherAudioDucking
        #expect(!ducking.enableAdvancedDucking.boolValue)
        #expect(ducking.duckingLevel == .min)
    }
}

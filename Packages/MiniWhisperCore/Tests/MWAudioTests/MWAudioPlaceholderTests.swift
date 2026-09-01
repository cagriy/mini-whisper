import Testing
@testable import MWAudio

@Suite struct MWAudioPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWAudioModule.self) == "MWAudioModule")
    }
}

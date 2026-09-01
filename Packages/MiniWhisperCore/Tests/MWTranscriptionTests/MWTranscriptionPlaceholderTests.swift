import Testing
@testable import MWTranscription

@Suite struct MWTranscriptionPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWTranscriptionModule.self) == "MWTranscriptionModule")
    }
}

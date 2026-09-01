import Testing
@testable import MWStreaming

@Suite struct MWStreamingPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWStreamingModule.self) == "MWStreamingModule")
    }
}

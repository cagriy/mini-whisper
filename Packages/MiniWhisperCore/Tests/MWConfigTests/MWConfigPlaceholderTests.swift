import Testing
@testable import MWConfig

@Suite struct MWConfigPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWConfigModule.self) == "MWConfigModule")
    }
}

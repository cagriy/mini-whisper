import Testing
@testable import MWHotkeys

@Suite struct MWHotkeysPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWHotkeysModule.self) == "MWHotkeysModule")
    }
}

import Testing
@testable import MWPaste

@Suite struct MWPastePlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWPasteModule.self) == "MWPasteModule")
    }
}

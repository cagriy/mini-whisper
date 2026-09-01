import Testing
@testable import MWHistory

@Suite struct MWHistoryPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWHistoryModule.self) == "MWHistoryModule")
    }
}

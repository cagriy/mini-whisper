import Testing
@testable import MWUsage

@Suite struct MWUsagePlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWUsageModule.self) == "MWUsageModule")
    }
}

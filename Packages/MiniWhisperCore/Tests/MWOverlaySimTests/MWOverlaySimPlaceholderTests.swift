import Testing
@testable import MWOverlaySim

@Suite struct MWOverlaySimPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWOverlaySimModule.self) == "MWOverlaySimModule")
    }
}

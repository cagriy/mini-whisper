import Testing
@testable import MWSupport

@Suite struct MWSupportPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWSupportModule.self) == "MWSupportModule")
    }
}

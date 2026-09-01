import Testing
@testable import MWProfiles

@Suite struct MWProfilesPlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWProfilesModule.self) == "MWProfilesModule")
    }
}

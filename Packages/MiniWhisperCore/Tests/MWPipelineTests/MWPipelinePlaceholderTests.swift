import Testing
@testable import MWPipeline

@Suite struct MWPipelinePlaceholderTests {
    @Test func moduleMarkerExists() {
        #expect(String(describing: MWPipelineModule.self) == "MWPipelineModule")
    }
}

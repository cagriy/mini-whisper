import Testing
@testable import MWConfig

@Suite struct MeetingEngineTests {
    @Test func fourTiersWithDesignRawValues() {
        #expect(
            MeetingEngine.allCases.map(\.rawValue) == [
                "speechmatics_standard", "speechmatics_enhanced",
                "assemblyai_streaming", "assemblyai_pro",
            ]
        )
    }

    @Test func keyAccountsPricingKeysAndDiarizationKeys() {
        #expect(MeetingEngine.allCases.map(\.keyAccount) == [.speechmatics, .speechmatics, .assemblyai, .assemblyai])
        #expect(
            MeetingEngine.allCases.map(\.pricingKey)
                == ["speechmatics", "speechmatics_enhanced", "assemblyai", "assemblyai_pro"]
        )
        #expect(
            MeetingEngine.allCases.map(\.diarizationPricingKey)
                == [nil, nil, "assemblyai_diarization", "assemblyai_diarization"]
        )
    }

    @Test func titlesAndProviderModels() {
        #expect(
            MeetingEngine.allCases.map(\.title) == [
                "Speechmatics Standard", "Speechmatics Enhanced",
                "AssemblyAI Universal-Streaming", "AssemblyAI Universal 3.6 Pro",
            ]
        )
        #expect(
            MeetingEngine.allCases.map(\.providerModel)
                == ["standard", "enhanced", "universal-streaming-english", "universal-3-6-pro"]
        )
    }

    @Test func resolveKeepsTheStoredTierWhenItsKeyExists() {
        let resolved = MeetingEngine.resolve(stored: .assemblyaiPro) { _ in true }

        #expect(resolved == .assemblyaiPro)
    }

    @Test func resolveFallsBackToTheFirstTierWithAKey() {
        let assemblyAIOnly: (KeyAccount) -> Bool = { $0 == .assemblyai }

        #expect(MeetingEngine.resolve(stored: nil, hasKey: assemblyAIOnly) == .assemblyaiStreaming)
        #expect(MeetingEngine.resolve(stored: .speechmaticsEnhanced, hasKey: assemblyAIOnly) == .assemblyaiStreaming)
        #expect(MeetingEngine.resolve(stored: nil) { _ in true } == .speechmaticsStandard)
    }

    @Test func resolveIsNilWithoutAnyKey() {
        #expect(MeetingEngine.resolve(stored: nil) { _ in false } == nil)
        #expect(MeetingEngine.resolve(stored: .speechmaticsStandard) { _ in false } == nil)
    }
}

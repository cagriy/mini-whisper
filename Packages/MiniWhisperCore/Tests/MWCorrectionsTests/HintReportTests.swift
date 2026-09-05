import MWConfig
import Testing

import MWCorrections

/// R22/R33/R38: the rows Settings → Vocabulary renders.
@Suite struct HintReportTests {
    private static let rules = [
        CorrectionRule(
            heard: "eefa", write: "Aoife", soundsLike: ["eva"],
            bundleID: "com.tinyspeck.slackmacgap"
        ),
        CorrectionRule(heard: "get hub", write: "GitHub"),
        CorrectionRule(heard: "speech matics", write: "Speechmatics", enabled: false),
    ]

    private func report(
        _ rules: [CorrectionRule] = HintReportTests.rules,
        vocabulary: [String] = ["xcodegen"],
        support: HintSupport = .unavailable(reason: "effect not yet measured")
    ) -> [HintReport.Row] {
        HintReport.report(rules: rules, vocabulary: vocabulary, support: support)
    }

    private func row(_ engine: EngineName?) throws -> HintReport.Row {
        try #require(report().first { $0.engine == engine })
    }

    @Test func oneRowPerEngineThenTheBatchRow() {
        #expect(report().map(\.engine) == EngineName.allCases + [nil])
        #expect(report().map(\.label) == [
            "SpeechAnalyzer", "On-device", "OpenAI Realtime", "ElevenLabs", "Speechmatics",
            "Batch transcription",
        ])
    }

    @Test func countsCoverEveryEnabledRuleWhateverItsScope() throws {
        // Aoife, eefa, eva, GitHub, get hub, xcodegen — the disabled rule adds nothing.
        #expect(try row(.onDevice).sent == 6)
        #expect(try row(.onDevice).cap == 100)
        #expect(try row(.openai).sent == 6)
        #expect(try row(.openai).cap == nil)
        // Two rule entries plus one vocabulary entry.
        #expect(try row(.speechmatics).sent == 3)
        #expect(try row(.speechmatics).cap == 1_000)
        #expect(try row(nil).sent == 6)
    }

    @Test func disabledRulesAreExcludedFromTheCounts() throws {
        var enabled = Self.rules
        enabled[2].enabled = true

        let sent = try #require(
            report(enabled).first { $0.engine == .onDevice }?.sent
        )
        #expect(sent == 8)
    }

    @Test func elevenLabsReceivesNothing() throws {
        #expect(try row(.elevenlabs).state == .notSent("not sent in this version"))
        #expect(try row(.elevenlabs).sent == 0)
    }

    @Test func theBatchRowIsThePromptField() throws {
        #expect(try row(nil).state == .prompt)
        #expect(try row(nil).cap == nil)
    }

    @Test func speechAnalyzerReflectsItsSupportConstant() {
        let unavailable = report(support: .unavailable(reason: "effect not yet measured"))
        let speechAnalyzer = unavailable.first { $0.engine == .speechAnalyzer }
        #expect(speechAnalyzer?.state == .unavailable("effect not yet measured"))
        #expect(speechAnalyzer?.sent == 0)
        #expect(speechAnalyzer?.cap == nil)

        let supported = report(support: .supported).first { $0.engine == .speechAnalyzer }
        #expect(supported?.state == .supported)
        #expect(supported?.sent == 6)
        #expect(supported?.cap == 100)
    }

    @Test func theSpeechAnalyzerConstantIsUnmeasuredBeforeTheMeasurementStage() {
        #expect(HintSupport.speechAnalyzer == .unavailable(reason: "effect not yet measured"))
    }

    @Test func skippedTermsAreReportedWithTheirReason() throws {
        let many = (0..<40).map {
            CorrectionRule(heard: "heard\($0)", write: "Write\($0)", soundsLike: ["alias\($0)"])
        }

        let row = try #require(report(many).first { $0.engine == .onDevice })
        #expect(row.sent == 100)
        #expect(row.skipped.count == 21)
        #expect(row.skipped.allSatisfy { $0.reason == .overCap })
    }
}

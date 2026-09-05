import MWConfig

/// R33: what each engine would be sent right now, counted over every enabled rule
/// whatever its scope — the worst case for the caps.
public enum HintReport {
    public enum State: Equatable, Sendable {
        case supported
        case unavailable(String)
        case notSent(String)
        case prompt
    }

    public struct Row: Equatable, Sendable {
        public var engine: EngineName?
        public var label: String
        public var sent: Int
        public var cap: Int?
        public var skipped: [SkippedHint]
        public var state: State
    }

    public static func report(
        rules: [CorrectionRule],
        vocabulary: [String],
        support: HintSupport
    ) -> [Row] {
        // Scope is flattened away so every enabled rule counts, whichever app it is for.
        let everywhere = rules.map { rule -> CorrectionRule in
            var rule = rule
            rule.bundleID = nil
            return rule
        }
        let hints = HintResolver.resolve(
            CorrectionSnapshot(rules: everywhere, vocabulary: vocabulary), bundleID: nil
        )
        let contextual = HintSerializer.contextualStrings(hints)
        let keywords = HintSerializer.openAIKeywords(hints)
        let vocab = HintSerializer.speechmaticsVocab(hints)

        return [
            speechAnalyzerRow(contextual, support: support),
            Row(
                engine: .onDevice, label: "On-device", sent: contextual.sent.count,
                cap: HintSerializer.contextualStringsCap, skipped: contextual.skipped,
                state: .supported
            ),
            Row(
                engine: .openai, label: "OpenAI Realtime", sent: keywords.sent.count, cap: nil,
                skipped: keywords.skipped, state: .supported
            ),
            Row(
                engine: .elevenlabs, label: "ElevenLabs", sent: 0, cap: nil, skipped: [],
                state: .notSent("not sent in this version")
            ),
            Row(
                engine: .speechmatics, label: "Speechmatics", sent: vocab.sent.count,
                cap: HintSerializer.speechmaticsEntryCap, skipped: vocab.skipped, state: .supported
            ),
            Row(
                engine: nil, label: "Batch transcription", sent: hints.terms.count, cap: nil,
                skipped: [], state: .prompt
            ),
        ]
    }

    private static func speechAnalyzerRow(
        _ contextual: HintSerializer.Capped,
        support: HintSupport
    ) -> Row {
        switch support {
        case .supported:
            Row(
                engine: .speechAnalyzer, label: "SpeechAnalyzer", sent: contextual.sent.count,
                cap: HintSerializer.contextualStringsCap, skipped: contextual.skipped,
                state: .supported
            )
        case .unavailable(let reason):
            Row(
                engine: .speechAnalyzer, label: "SpeechAnalyzer", sent: 0, cap: nil, skipped: [],
                state: .unavailable(reason)
            )
        }
    }
}

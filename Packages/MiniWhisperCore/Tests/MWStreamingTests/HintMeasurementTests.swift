import Foundation
import MWConfig
import MWCorrections
import MWProfiles
import MWTestSupport
import MWTranscription
import Testing

import MWStreaming

/// R37's measurement: every clip in a user-provided set transcribed hints-off and
/// hints-on per engine, written as a markdown report under the feature folder. It needs
/// a clip set and the user's own provider credentials, so it is opt-in and never part of
/// a plain `swift test`.
///
///     MW_INTEGRATION=1 MW_HINT_AUDIO_DIR=<dir> swift test --filter HintMeasurementTests
///
/// Cloud runs spend the user's own credits. No audio is written anywhere, and no key is
/// written or logged.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"
        && ProcessInfo.processInfo.environment["MW_HINT_AUDIO_DIR"] != nil)
)
struct HintMeasurementTests {
    private enum SetupError: Error, CustomStringConvertible {
        case noAudioDirectory
        case noReportDirectory

        var description: String {
            switch self {
            case .noAudioDirectory: "MW_HINT_AUDIO_DIR names no directory"
            case .noReportDirectory: "the measurements directory could not be derived"
            }
        }
    }

    private struct ClipSet {
        let directory: URL
        let manifest: HintMeasurementManifest

        var hints: RecognitionHints { HintResolver.resolve(manifest.snapshot, bundleID: nil) }

        var rules: [ResolvedRule] {
            CorrectionResolver(rules: manifest.snapshot.rules).rules(for: nil)
        }
    }

    // MARK: - Engines

    @Test func measuresOnDeviceRecognizer() async throws {
        let api = SFSpeechRecognitionBridge()
        try #require(SpeechPermission.ensureAuthorized(api: api) == .authorized)

        let report = try await Self.measure(engine: "On-device") { clip, hints in
            try await Self.transcribe(clip, with: SFSpeechEngine(api: api, hints: hints))
        }
        #expect(!report.rows.isEmpty)
    }

    /// R38: the run whose verdict decides `HintSupport.speechAnalyzer`.
    @Test(
        .enabled(if: ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ))
    )
    func measuresSpeechAnalyzer() async throws {
        let api = SpeechAnalyzerBridge()
        try #require(api.isAvailable)
        guard await SpeechModelAssets.status(api: api, locale: .current) == .installed else {
            Issue.record("the on-device speech model is not installed — install it from Settings")
            return
        }

        let report = try await Self.measure(
            engine: "SpeechAnalyzer", decidesHintSupport: true
        ) { clip, hints in
            try await Self.transcribe(clip, with: SpeechAnalyzerEngine(api: api, hints: hints))
        }
        #expect(!report.rows.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil))
    func measuresOpenAIRealtime() async throws {
        let report = try await Self.measureCloud(.openai, label: "OpenAI Realtime")
        #expect(!report.rows.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPEECHMATICS_API_KEY"] != nil))
    func measuresSpeechmatics() async throws {
        let report = try await Self.measureCloud(.speechmatics, label: "Speechmatics")
        #expect(!report.rows.isEmpty)
    }

    /// R23's path: the terms reach the model through the multipart `prompt` field rather
    /// than a streaming hint field.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil))
    func measuresBatchTranscription() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["OPENAI_API_KEY"])
        let client = OpenAIClient(apiKey: key)

        let report = try await Self.measure(engine: "Batch transcription") { clip, hints in
            let prompt = PromptComposer.transcribePrompt(base: "", terms: hints.terms)
            return try await client.transcribe(wav: try Data(contentsOf: clip), prompt: prompt).0
        }
        #expect(!report.rows.isEmpty)
    }

    // MARK: - The run

    private static func measure(
        engine label: String,
        decidesHintSupport: Bool = false,
        transcribe: (URL, RecognitionHints) async throws -> String
    ) async throws -> HintMeasurementReport {
        let set = try clipSet()
        var rows: [HintMeasurementReport.Row] = []
        for clip in set.manifest.clips {
            let url = set.directory.appendingPathComponent(clip.file)
            let off = try await transcribe(url, .none)
            let on = try await transcribe(url, set.hints)
            rows.append(
                HintMeasurement.row(clip: clip, hintsOff: off, hintsOn: on, rules: set.rules)
            )
        }
        let report = HintMeasurementReport(
            engine: label, date: Date(), decidesHintSupport: decidesHintSupport, rows: rows
        )
        try write(report)
        return report
    }

    /// The cloud engines are built through `EngineFactory`, so the measurement runs the
    /// same construction path a dictation does.
    private static func measureCloud(
        _ name: EngineName,
        label: String
    ) async throws -> HintMeasurementReport {
        let provider = try #require(name.measurementKey)
        let key = try #require(ProcessInfo.processInfo.environment[provider.variable])
        let secrets = FakeSecretStore([provider.account: key])
        var config = Config()
        config.streamingEnabled = true
        config.streamingEngine = name

        return try await measure(engine: label) { clip, hints in
            let selection = await EngineFactory().make(
                config: config, secrets: secrets, hints: hints
            )
            return try await transcribe(clip, with: try #require(selection.engine))
        }
    }

    private static func transcribe(_ clip: URL, with engine: any StreamingEngine) async throws
        -> String
    {
        let sink = RecordingSink()
        let result = try await ClipPlayback.play(
            clip, through: engine, sink: sink, timeout: .seconds(30)
        )
        for error in sink.errors {
            Issue.record("\(clip.lastPathComponent): \(error)")
        }
        return result.text
    }

    private static func clipSet() throws -> ClipSet {
        guard let path = ProcessInfo.processInfo.environment["MW_HINT_AUDIO_DIR"] else {
            throw SetupError.noAudioDirectory
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        return ClipSet(
            directory: directory,
            manifest: try HintMeasurementManifest.decode(
                Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            )
        )
    }

    private static func write(_ report: HintMeasurementReport) throws {
        guard let directory = HintMeasurement.reportDirectory() else {
            throw SetupError.noReportDirectory
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(HintMeasurement.render(report).utf8)
            .write(to: directory.appendingPathComponent(HintMeasurement.fileName(report)))
    }
}

extension EngineName {
    /// Where the measurement reads a provider key from: the environment, exactly as the
    /// other integration suites do, never the user's Keychain.
    fileprivate var measurementKey: (account: KeyAccount, variable: String)? {
        switch self {
        case .openai: (.openai, "OPENAI_API_KEY")
        case .elevenlabs: (.elevenlabs, "ELEVENLABS_API_KEY")
        case .speechmatics: (.speechmatics, "SPEECHMATICS_API_KEY")
        case .onDevice, .speechAnalyzer: nil
        }
    }
}

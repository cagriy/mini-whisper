import Foundation
import MWConfig
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

private enum TestConnectError: Error { case refused }

/// Records what the factory would dial without opening a socket.
private final class ConnectRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(url: URL, headers: [String: String])] = []

    var urls: [URL] { lock.withLock { calls.map(\.url) } }
    var headers: [[String: String]] { lock.withLock { calls.map(\.headers) } }

    var connect: @Sendable (URL, [String: String]) async throws -> any WebSocketConnection {
        { url, headers in
            self.lock.withLock { self.calls.append((url, headers)) }
            throw TestConnectError.refused
        }
    }
}

/// Engine selection and the downgrade rules (F23) plus the default-engine rule (F32),
/// ported from `../mini-whisper/tests/test_factory.py` and extended for the two
/// on-device engines the Python app does not have.
@Suite struct EngineFactoryTests {
    private static let keys: [KeyAccount: String] = [
        .openai: "sk-test-not-a-real-key",
        .elevenlabs: "el-test-not-a-real-key",
        .speechmatics: "sm-test-not-a-real-key",
    ]

    private static let cloudEngines: [EngineName] = [.openai, .elevenlabs, .speechmatics]

    private func config(enabled: Bool = true, engine: EngineName? = .onDevice) -> Config {
        var config = Config()
        config.streamingEnabled = enabled
        config.streamingEngine = engine
        return config
    }

    private func factory(
        osMajor: Int = 15,
        locale: Locale = Locale(identifier: "en_US"),
        speech: FakeSpeechRecognitionAPI = FakeSpeechRecognitionAPI(),
        analyzer: FakeSpeechAnalyzerAPI = FakeSpeechAnalyzerAPI(),
        clock: any Clock = VirtualClock(),
        connect: @escaping @Sendable (URL, [String: String]) async throws -> any WebSocketConnection
            = { _, _ in throw TestConnectError.refused }
    ) -> EngineFactory {
        EngineFactory(
            platform: PlatformInfo(osMajor: osMajor, locale: locale),
            speech: speech,
            analyzer: analyzer,
            clock: clock,
            connect: connect
        )
    }

    /// Assets present for the analyzer: `installationRequest` returns nothing to install.
    private func installedAnalyzer() -> FakeSpeechAnalyzerAPI {
        FakeSpeechAnalyzerAPI(installation: nil)
    }

    // MARK: - Streaming toggle

    @Test(arguments: EngineName.allCases)
    func disabledReturnsNoEngineForEveryName(_ name: EngineName) async {
        let selection = await factory().make(
            config: config(enabled: false, engine: name),
            secrets: FakeSecretStore(Self.keys)
        )

        #expect(selection.engine == nil)
        #expect(selection.notice == nil)
    }

    // MARK: - On-device: the Speech authorization gate

    @Test func onDeviceAuthorizedReturnsSFEngine() async {
        let selection = await factory().make(config: config(), secrets: FakeSecretStore())

        #expect(selection.engine is SFSpeechEngine)
        #expect(selection.engine?.name == .onDevice)
        #expect(selection.notice == nil)
    }

    @Test func onDeviceDeniedReturnsNoneWithPointerNoticeOncePerRun() async {
        let speech = FakeSpeechRecognitionAPI(status: .denied)
        let factory = factory(speech: speech)

        let first = await factory.make(config: config(), secrets: FakeSecretStore())
        let second = await factory.make(config: config(), secrets: FakeSecretStore())

        #expect(first.engine == nil)
        #expect(first.notice == .speechPermissionPointer)
        #expect(first.notice?.message
            == "Live transcript off: enable Speech Recognition in System Settings → Privacy & Security.")
        #expect(second.engine == nil)
        #expect(second.notice == nil)
        #expect(speech.requestAuthorizationCalls == 0)
    }

    @Test func onDeviceUndeterminedRequestsOnceAndBatchesThisTime() async {
        let speech = FakeSpeechRecognitionAPI(status: .notDetermined)

        let selection = await factory(speech: speech).make(config: config(), secrets: FakeSecretStore())

        #expect(selection.engine == nil)
        #expect(selection.notice == nil)
        #expect(speech.requestAuthorizationCalls == 1)
    }

    // MARK: - Cloud engines: the key gate

    @Test(arguments: EngineFactoryTests.cloudEngines)
    func cloudEngineWithKeyReturnsWebSocketEngine(_ name: EngineName) async {
        let selection = await factory().make(
            config: config(engine: name),
            secrets: FakeSecretStore(Self.keys)
        )

        #expect(selection.engine?.name == name)
        #expect(selection.notice == nil)
    }

    @Test(arguments: zip(
        EngineFactoryTests.cloudEngines,
        ["OpenAI", "ElevenLabs", "Speechmatics"]
    ))
    func cloudEngineWithoutKeyDowngradesToOnDeviceDefaultWithNoticeOncePerRun(
        _ name: EngineName,
        _ label: String
    ) async {
        let factory = factory()

        let first = await factory.make(config: config(engine: name), secrets: FakeSecretStore())
        let second = await factory.make(config: config(engine: name), secrets: FakeSecretStore())

        #expect(first.engine is SFSpeechEngine)
        #expect(first.notice == .cloudKeyMissing(name))
        #expect(first.notice?.message == "Live transcript: \(label) key missing — using on-device")
        #expect(second.engine is SFSpeechEngine)
        #expect(second.notice == nil)
    }

    @Test func cloudDowngradeUsesTheAnalyzerWhenItIsThePlatformDefault() async {
        let selection = await factory(osMajor: 26, analyzer: installedAnalyzer()).make(
            config: config(engine: .elevenlabs),
            secrets: FakeSecretStore()
        )

        #expect(selection.engine is SpeechAnalyzerEngine)
        #expect(selection.notice == .cloudKeyMissing(.elevenlabs))
    }

    @Test func openAIUsesOpenAIKeyAccount() async {
        let recorder = ConnectRecorder()
        let selection = await factory(connect: recorder.connect).make(
            config: config(engine: .openai),
            secrets: FakeSecretStore([.openai: "sk-test-not-a-real-key"])
        )
        let engine = try? #require(selection.engine)
        engine?.start(sink: RecordingSink())
        _ = await engine?.finish(timeout: .seconds(5))

        #expect(recorder.urls == [URL(string: "wss://api.openai.com/v1/realtime")!])
        #expect(recorder.headers == [["Authorization": "Bearer sk-test-not-a-real-key"]])
    }

    // MARK: - SpeechAnalyzer gating

    @Test func speechAnalyzerBelow26UsesSF() async {
        let analyzer = installedAnalyzer()

        let selection = await factory(osMajor: 25, analyzer: analyzer).make(
            config: config(engine: .speechAnalyzer),
            secrets: FakeSecretStore()
        )

        #expect(selection.engine is SFSpeechEngine)
        #expect(selection.notice == nil)
    }

    @Test func speechAnalyzerAssetsNotInstalledUsesSF() async {
        let analyzer = FakeSpeechAnalyzerAPI(installation: FakeAssetInstallation(fractionCompleted: 0))

        let selection = await factory(osMajor: 26, analyzer: analyzer).make(
            config: config(engine: .speechAnalyzer),
            secrets: FakeSecretStore()
        )

        #expect(selection.engine is SFSpeechEngine)
        #expect(selection.notice == nil)
    }

    @Test func speechAnalyzerUnsupportedLocaleUsesSF() async {
        let analyzer = FakeSpeechAnalyzerAPI(supportedLocale: nil, installation: nil)

        let selection = await factory(osMajor: 26, analyzer: analyzer).make(
            config: config(engine: .speechAnalyzer),
            secrets: FakeSecretStore()
        )

        #expect(selection.engine is SFSpeechEngine)
    }

    @Test func speechAnalyzerInstalledUsesAnalyzer() async {
        let selection = await factory(osMajor: 26, analyzer: installedAnalyzer()).make(
            config: config(engine: .speechAnalyzer),
            secrets: FakeSecretStore()
        )

        #expect(selection.engine is SpeechAnalyzerEngine)
        #expect(selection.engine?.name == .speechAnalyzer)
        #expect(selection.notice == nil)
    }

    // MARK: - The default-engine rule (F32)

    @Test func absentEngineDefaultsToAnalyzerOn26WhenInstalledElseOnDevice() async {
        let installed = await factory(osMajor: 26, analyzer: installedAnalyzer()).make(
            config: config(engine: nil),
            secrets: FakeSecretStore()
        )
        let notInstalled = await factory(osMajor: 26).make(
            config: config(engine: nil),
            secrets: FakeSecretStore()
        )
        let old = await factory(osMajor: 15, analyzer: installedAnalyzer()).make(
            config: config(engine: nil),
            secrets: FakeSecretStore()
        )

        #expect(installed.engine is SpeechAnalyzerEngine)
        #expect(notInstalled.engine is SFSpeechEngine)
        #expect(old.engine is SFSpeechEngine)
    }

    @Test func defaultEngineRuleIsIndependentOfConfig() {
        let modern = PlatformInfo(osMajor: 26, locale: Locale(identifier: "en_US"))
        let legacy = PlatformInfo(osMajor: 15, locale: Locale(identifier: "en_US"))

        #expect(EngineFactory.defaultEngine(platform: modern, assetsInstalled: true) == .speechAnalyzer)
        #expect(EngineFactory.defaultEngine(platform: modern, assetsInstalled: false) == .onDevice)
        #expect(EngineFactory.defaultEngine(platform: legacy, assetsInstalled: true) == .onDevice)
    }

    @Test func presentEngineValueIsHonoured() async {
        let selection = await factory(osMajor: 26, analyzer: installedAnalyzer()).make(
            config: config(engine: .elevenlabs),
            secrets: FakeSecretStore(Self.keys)
        )

        #expect(selection.engine?.name == .elevenlabs)
    }

    /// An unrecognised `streaming_engine` string decodes to no engine choice (Stage 3),
    /// so it takes the same platform default as an absent key rather than the Python
    /// app's `unknown_engine` batch fallback.
    @Test func unknownEngineNameFallsBackToPlatformDefault() async throws {
        let json = Data(#"{"streaming_engine": "bogus"}"#.utf8)
        let config = try JSONDecoder().decode(Config.self, from: json)

        let selection = await factory(osMajor: 26, analyzer: installedAnalyzer()).make(
            config: config,
            secrets: FakeSecretStore()
        )

        #expect(config.streamingEngine == nil)
        #expect(selection.engine is SpeechAnalyzerEngine)
    }
}

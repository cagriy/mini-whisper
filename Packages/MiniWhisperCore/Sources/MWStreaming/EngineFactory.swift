import Foundation
import MWConfig
import MWSupport
import os

/// Picks the streaming engine for one dictation and applies every downgrade rule of
/// F23, plus the F32 default when `config.json` names no engine. A port of
/// `../mini-whisper/src/mini_whisper/streaming/factory.py`, extended for the two
/// on-device engines and the notices the Python app has no overlay for.
///
/// The only I/O is through the injected seams, so `swift test` needs neither TCC,
/// the speech model nor the network.
public struct EngineFactory: EngineProvider {
    private let platform: PlatformInfo
    private let speech: any SpeechRecognitionAPI
    private let analyzer: any SpeechAnalyzerAPI
    private let clock: any Clock
    private let connect: @Sendable (URL, [String: String]) async throws -> any WebSocketConnection
    /// Notices already shown this run; each fires at most once (F23).
    private let shown = OSAllocatedUnfairLock(initialState: Set<EngineNotice>())

    public init(
        platform: PlatformInfo = PlatformInfo(),
        speech: any SpeechRecognitionAPI = SFSpeechRecognitionBridge(),
        analyzer: any SpeechAnalyzerAPI = SpeechAnalyzerBridge(),
        clock: any Clock = SystemClock(),
        connect: @escaping @Sendable (URL, [String: String]) async throws -> any WebSocketConnection
            = { url, headers in URLSessionWebSocketConnection(url: url, headers: headers) }
    ) {
        self.platform = platform
        self.speech = speech
        self.analyzer = analyzer
        self.clock = clock
        self.connect = connect
    }

    public func make(config: Config, secrets: any SecretStore) async -> EngineSelection {
        guard config.streamingEnabled else { return EngineSelection() }
        // An absent (or unrecognised) `streaming_engine` takes the platform default (F32).
        guard let name = config.streamingEngine else { return await onDeviceSelection() }
        switch name {
        case .speechAnalyzer: return await onDeviceSelection()
        case .onDevice: return onDevice()
        case .openai, .elevenlabs, .speechmatics: return await cloud(name, secrets: secrets)
        }
    }

    /// F32: `speech_analyzer` once macOS 26 has the model installed, `on_device` otherwise.
    public static func defaultEngine(platform: PlatformInfo, assetsInstalled: Bool) -> EngineName {
        platform.osMajor >= 26 && assetsInstalled ? .speechAnalyzer : .onDevice
    }

    // MARK: - Selection

    /// The on-device pair under one rule: the analyzer once macOS 26 has the model for
    /// this locale, silently SFSpeechRecognizer otherwise (F23, design §5.7). Serves the
    /// explicit `speech_analyzer` value, the absent-value default and the cloud downgrade.
    private func onDeviceSelection() async -> EngineSelection {
        switch Self.defaultEngine(platform: platform, assetsInstalled: await assetsInstalled()) {
        case .speechAnalyzer:
            return EngineSelection(
                engine: SpeechAnalyzerEngine(api: analyzer, locale: platform.locale, clock: clock)
            )
        default:
            return onDevice()
        }
    }

    private func onDevice() -> EngineSelection {
        switch SpeechPermission.ensureAuthorized(api: speech) {
        case .authorized:
            return EngineSelection(engine: SFSpeechEngine(api: speech, clock: clock))
        case .denied:
            return EngineSelection(notice: noticeOnce(.speechPermissionPointer))
        case .undetermined:
            // The grant applies from the next dictation; this one goes to batch.
            return EngineSelection()
        }
    }

    private func cloud(_ name: EngineName, secrets: any SecretStore) async -> EngineSelection {
        guard let key = key(for: name, secrets: secrets), !key.isEmpty else {
            Log.stream(name.rawValue).info("no key configured; using the on-device default")
            let notice = noticeOnce(.cloudKeyMissing(name))
            var selection = await onDeviceSelection()
            selection.notice = notice ?? selection.notice
            return selection
        }
        return EngineSelection(engine: cloudEngine(name, key: key))
    }

    private func cloudEngine(_ name: EngineName, key: String) -> (any StreamingEngine)? {
        switch name {
        case .openai: webSocketEngine(OpenAIRealtimeAdapter(apiKey: key))
        case .elevenlabs: webSocketEngine(ElevenLabsAdapter(apiKey: key))
        case .speechmatics: webSocketEngine(SpeechmaticsAdapter(apiKey: key))
        case .onDevice, .speechAnalyzer: nil
        }
    }

    private func webSocketEngine<Adapter: EngineAdapter>(_ adapter: Adapter) -> WebSocketEngine<Adapter> {
        let url = adapter.url
        let headers = adapter.headers
        let connect = connect
        return WebSocketEngine(adapter: adapter, clock: clock) { try await connect(url, headers) }
    }

    // MARK: - Seams

    private func assetsInstalled() async -> Bool {
        guard platform.osMajor >= 26 else { return false }
        return await SpeechModelAssets.status(api: analyzer, locale: platform.locale) == .installed
    }

    private func key(for name: EngineName, secrets: any SecretStore) -> String? {
        guard let account = KeyAccount(engine: name) else { return nil }
        do {
            return try secrets.secret(for: account)
        } catch {
            Log.stream(name.rawValue).warning("keychain read failed: \(AnyError(error).description)")
            return nil
        }
    }

    /// Nil once the notice has already been shown in this process.
    private func noticeOnce(_ notice: EngineNotice) -> EngineNotice? {
        shown.withLock { $0.insert(notice).inserted } ? notice : nil
    }
}

extension KeyAccount {
    /// The Keychain account a cloud engine's key lives under; nil for the on-device engines.
    init?(engine: EngineName) {
        switch engine {
        case .openai: self = .openai
        case .elevenlabs: self = .elevenlabs
        case .speechmatics: self = .speechmatics
        case .onDevice, .speechAnalyzer: return nil
        }
    }
}

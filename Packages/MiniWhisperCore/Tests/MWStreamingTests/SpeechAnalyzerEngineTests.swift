import AVFAudio
import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

private struct AnalyzerFailure: Error, CustomStringConvertible {
    let description = "analyzer refused the session"
}

/// SpeechAnalyzer behind the `SpeechAnalyzerAPI` seam (design N5, F24): volatile
/// results are partials, finalised results are finals, and every failure path returns
/// `ok == false` so the pipeline falls back to batch.
@Suite struct SpeechAnalyzerEngineTests {
    @Test func volatileResultIsPartial() async {
        let api = FakeSpeechAnalyzerAPI()
        let session = started(api)

        api.session.emit(AnalyzerTranscript(text: "hel", isFinal: false))
        let result = await session.engine.finish(timeout: .seconds(5))

        #expect(session.sink.partials == ["hel"])
        #expect(session.sink.finals.isEmpty)
        #expect(result.ok)
        #expect(result.text == "hel")
    }

    @Test func finalResultIsFinal() async {
        let api = FakeSpeechAnalyzerAPI()
        let session = started(api)

        api.session.emit(AnalyzerTranscript(text: "hello", isFinal: false))
        api.session.emit(AnalyzerTranscript(text: "hello world.", isFinal: true))
        let result = await session.engine.finish(timeout: .seconds(5))

        #expect(session.sink.partials == ["hello"])
        #expect(session.sink.finals == ["hello world."])
        #expect(result.text == "hello world.")
    }

    @Test func feedConvertsToAnalyzerFormatAndYields() async throws {
        let api = FakeSpeechAnalyzerAPI(bestFormat: format(16000))
        let session = started(api)

        session.engine.feed(PCMBufferFactory.make(samples: [0.1, 0.2, 0.3], sampleRate: 48000))
        _ = await session.engine.finish(timeout: .seconds(5))

        #expect(api.conversions == [FakeSpeechAnalyzerAPI.Conversion(from: 48000, to: 16000)])
        #expect(api.session.fed.count == 1)
        #expect(try #require(api.session.fed.first).format.sampleRate == 16000)
    }

    @Test func finishFinalizesThroughLastInputAndReturnsText() async {
        let api = FakeSpeechAnalyzerAPI()
        let session = started(api)
        api.session.emit(AnalyzerTranscript(text: "hello", isFinal: true))
        api.session.emit(AnalyzerTranscript(text: "world", isFinal: true))

        let result = await session.engine.finish(timeout: .seconds(5))

        #expect(api.session.finishCalls == 1)
        #expect(result.ok)
        #expect(result.text == "hello world")
    }

    @Test func finishTimeoutReturnsNotOk() async {
        let clock = VirtualClock()
        let api = FakeSpeechAnalyzerAPI(endsResultsOnFinish: false)
        let session = started(api, clock: clock)
        api.session.emit(AnalyzerTranscript(text: "half a sentence", isFinal: false))

        let finishing = Task { await session.engine.finish(timeout: .seconds(5)) }
        await clock.waitUntilSleeping()
        clock.advance(by: 5)
        let result = await finishing.value

        #expect(result.ok == false)
        #expect(result.text == "")
    }

    @Test func analyzerErrorFailsOnce() async {
        let api = FakeSpeechAnalyzerAPI(sessionError: AnalyzerFailure())
        let session = started(api)

        let result = await session.engine.finish(timeout: .seconds(5))

        #expect(session.sink.errors.count == 1)
        #expect(result.ok == false)
    }

    @Test func usageSeconds() async {
        let clock = VirtualClock()
        let api = FakeSpeechAnalyzerAPI()
        let session = started(api, clock: clock)

        clock.advance(by: 2.5)
        api.session.emit(AnalyzerTranscript(text: "done", isFinal: true))

        #expect(await session.engine.finish(timeout: .seconds(5)).usage
            == StreamUsage(inputTokens: 0, outputTokens: 0, seconds: 2.5))
    }

    // MARK: - Harness

    private func format(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    }

    private func started(
        _ api: FakeSpeechAnalyzerAPI,
        clock: VirtualClock = VirtualClock()
    ) -> (engine: SpeechAnalyzerEngine, sink: RecordingSink) {
        let engine = SpeechAnalyzerEngine(api: api, locale: Locale(identifier: "en_US"), clock: clock)
        let sink = RecordingSink()
        engine.start(sink: sink)
        return (engine, sink)
    }
}

/// Asset availability and installation for the on-device speech model (F24, F32).
@Suite struct SpeechModelAssetsTests {
    private let locale = Locale(identifier: "en_US")

    @Test func unavailableBelow26OrWhenTranscriberUnavailable() async {
        let api = FakeSpeechAnalyzerAPI(isAvailable: false)

        #expect(await SpeechModelAssets.status(api: api, locale: locale) == .unavailable)
    }

    @Test func unsupportedLocaleIsUnavailable() async {
        let api = FakeSpeechAnalyzerAPI(supportedLocale: nil)

        #expect(await SpeechModelAssets.status(api: api, locale: locale) == .unavailable)
    }

    @Test func notInstalledWhenRequestNonNil() async {
        let api = FakeSpeechAnalyzerAPI(installation: FakeAssetInstallation(fractionCompleted: 0))

        #expect(await SpeechModelAssets.status(api: api, locale: locale) == .notInstalled)
    }

    @Test func installedWhenRequestNil() async {
        let api = FakeSpeechAnalyzerAPI(installation: nil)

        #expect(await SpeechModelAssets.status(api: api, locale: locale) == .installed)
    }

    @Test func installingReportsProgress() async {
        let api = FakeSpeechAnalyzerAPI(installation: FakeAssetInstallation(fractionCompleted: 0.3))

        #expect(await SpeechModelAssets.status(api: api, locale: locale)
            == .installing(fractionCompleted: 0.3))
    }

    /// macOS 26.6 hands back an installation request for a locale whose model is
    /// already installed (en_GB: request non-nil, progress 0 of 0), so the request
    /// alone cannot answer "installed" — `installedLocales` does. Without this the
    /// row never left "Download model…" and `EngineFactory` downgraded every
    /// dictation to SFSpeechRecognizer.
    @Test func installedWhenTheLocaleIsInstalledDespiteAPendingRequest() async {
        let api = FakeSpeechAnalyzerAPI(
            installation: FakeAssetInstallation(fractionCompleted: 0),
            installedLocales: [locale]
        )

        #expect(await SpeechModelAssets.status(api: api, locale: locale) == .installed)
    }

    @Test func installDownloadsTheRequest() async throws {
        let installation = FakeAssetInstallation(fractionCompleted: 0)
        let api = FakeSpeechAnalyzerAPI(installation: installation)

        try await SpeechModelAssets.install(api: api, locale: locale)

        #expect(installation.downloadCalls == 1)
    }
}

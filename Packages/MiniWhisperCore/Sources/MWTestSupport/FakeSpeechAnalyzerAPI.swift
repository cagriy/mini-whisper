import AVFAudio
import Foundation
import MWStreaming

/// A scripted `AnalyzerSession`: results are pushed by the test, and `finish()` ends
/// the stream unless the test asked it not to.
public final class FakeAnalyzerSession: AnalyzerSession, @unchecked Sendable {
    public let results: AsyncStream<AnalyzerTranscript>

    private let continuation: AsyncStream<AnalyzerTranscript>.Continuation
    private let endsResultsOnFinish: Bool
    private let finishError: (any Error)?
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var finishes = 0

    public init(endsResultsOnFinish: Bool = true, finishError: (any Error)? = nil) {
        (results, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        self.endsResultsOnFinish = endsResultsOnFinish
        self.finishError = finishError
    }

    public var fed: [AVAudioPCMBuffer] { lock.withLock { buffers } }
    public var finishCalls: Int { lock.withLock { finishes } }

    /// Plays one analyzer result into the engine.
    public func emit(_ transcript: AnalyzerTranscript) { continuation.yield(transcript) }

    public func feed(_ buffer: AVAudioPCMBuffer) { lock.withLock { buffers.append(buffer) } }

    public func finish() async throws {
        lock.withLock { finishes += 1 }
        if let finishError { throw finishError }
        if endsResultsOnFinish { continuation.finish() }
    }
}

public final class FakeAssetInstallation: AssetInstallation, @unchecked Sendable {
    public let fractionCompleted: Double

    private let lock = NSLock()
    private var downloads = 0

    public init(fractionCompleted: Double) {
        self.fractionCompleted = fractionCompleted
    }

    public var downloadCalls: Int { lock.withLock { downloads } }

    public func downloadAndInstall() async throws { lock.withLock { downloads += 1 } }
}

/// Stands in for `SpeechAnalyzerBridge`: no Speech framework, no model download.
public final class FakeSpeechAnalyzerAPI: SpeechAnalyzerAPI, @unchecked Sendable {
    public struct Conversion: Sendable, Equatable {
        public var from: Double
        public var to: Double

        public init(from: Double, to: Double) {
            self.from = from
            self.to = to
        }
    }

    public let isAvailable: Bool
    public let session: FakeAnalyzerSession
    public let installation: FakeAssetInstallation?
    /// What `SpeechTranscriber.installedLocales` reports; the installation request
    /// stays non-nil regardless, as the real API does.
    public var installedLocales: [Locale]

    private let locale: Locale?
    private let bestFormat: AVAudioFormat
    private let sessionError: (any Error)?
    private let lock = NSLock()
    private var records: [Conversion] = []

    public init(
        isAvailable: Bool = true,
        supportedLocale: Locale? = Locale(identifier: "en_US"),
        installation: FakeAssetInstallation? = FakeAssetInstallation(fractionCompleted: 0),
        installedLocales: [Locale] = [],
        bestFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!,
        sessionError: (any Error)? = nil,
        endsResultsOnFinish: Bool = true
    ) {
        self.isAvailable = isAvailable
        locale = supportedLocale
        self.installation = installation
        self.installedLocales = installedLocales
        self.bestFormat = bestFormat
        self.sessionError = sessionError
        session = FakeAnalyzerSession(endsResultsOnFinish: endsResultsOnFinish)
    }

    public var conversions: [Conversion] { lock.withLock { records } }

    public func supportedLocale(equivalentTo locale: Locale) async -> Locale? { self.locale }

    public func isInstalled(locale: Locale) async -> Bool {
        installedLocales.contains { $0.identifier == locale.identifier }
    }

    public func installationRequest(for locale: Locale) async throws -> (any AssetInstallation)? {
        installation
    }

    public func bestAudioFormat(locale: Locale) async -> AVAudioFormat? { bestFormat }

    public func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        lock.withLock {
            records.append(Conversion(from: buffer.format.sampleRate, to: format.sampleRate))
        }
        return PCMBufferFactory.make(
            samples: [Float](repeating: 0, count: Int(buffer.frameLength)),
            sampleRate: format.sampleRate
        )
    }

    public func makeSession(locale: Locale) async throws -> any AnalyzerSession {
        if let sessionError { throw sessionError }
        return session
    }
}

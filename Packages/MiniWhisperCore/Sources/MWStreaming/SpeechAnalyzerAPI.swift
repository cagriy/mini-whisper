import AVFAudio
import Foundation

/// One `SpeechTranscriber.Result`, reduced to what the pipeline needs: volatile
/// results are partials, finalised ones are finals (F24).
public struct AnalyzerTranscript: Sendable, Equatable {
    public var text: String
    public var isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// A running `SpeechAnalyzer` with one `SpeechTranscriber` module.
public protocol AnalyzerSession: Sendable {
    /// Ends when the analyzer has finalised and finished.
    var results: AsyncStream<AnalyzerTranscript> { get }
    /// Called on the audio tap thread, already in the analyzer's format.
    func feed(_ buffer: AVAudioPCMBuffer)
    /// Finalises through the last input and ends `results`.
    func finish() async throws
}

/// A pending speech-model download (`AssetInstallationRequest`).
public protocol AssetInstallation: Sendable {
    var fractionCompleted: Double { get }
    func downloadAndInstall() async throws
}

public enum AssetStatus: Sendable, Equatable {
    /// Below macOS 26, transcriber unavailable, or the locale is unsupported.
    case unavailable
    case notInstalled
    case installing(fractionCompleted: Double)
    case installed
}

public enum SpeechAnalyzerError: Error, Equatable, CustomStringConvertible {
    case unavailable
    case noCompatibleAudioFormat

    public var description: String {
        switch self {
        case .unavailable: "the on-device speech model is unavailable"
        case .noCompatibleAudioFormat: "no audio format compatible with the speech transcriber"
        }
    }
}

/// The SpeechAnalyzer seam (design N5): the real calls live only in
/// `SpeechAnalyzerBridge`, so `swift test` needs neither macOS 26 nor the model.
public protocol SpeechAnalyzerAPI: Sendable {
    /// False below macOS 26 and when `SpeechTranscriber` is unavailable.
    var isAvailable: Bool { get }
    func supportedLocale(equivalentTo locale: Locale) async -> Locale?
    /// `SpeechTranscriber.installedLocales` — the only reliable "is the model here"
    /// answer; the installation request is non-nil either way.
    func isInstalled(locale: Locale) async -> Bool
    /// The pending download for `locale`. Present even once the model is installed,
    /// so it answers "how far along", never "is it needed".
    func installationRequest(for locale: Locale) async throws -> (any AssetInstallation)?
    /// `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`.
    func bestAudioFormat(locale: Locale) async -> AVAudioFormat?
    /// Tap buffer → analyzer format; nil when the buffer cannot be converted.
    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer?
    func makeSession(
        locale: Locale,
        contextualStrings: [String]
    ) async throws -> any AnalyzerSession
}

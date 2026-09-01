import AVFAudio
import CoreMedia
import Foundation
import Speech

/// The only file in MWStreaming that talks to `SpeechAnalyzer` (design N5). Everything
/// macOS 26 sits behind `#available`, so the type is constructible on macOS 14 and
/// simply reports itself unavailable there.
public final class SpeechAnalyzerBridge: SpeechAnalyzerAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterFormats: (input: AVAudioFormat, output: AVAudioFormat)?

    public init() {}

    public var isAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return SpeechTranscriber.isAvailable
    }

    public func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        guard #available(macOS 26, *) else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    public func installationRequest(for locale: Locale) async throws -> (any AssetInstallation)? {
        guard #available(macOS 26, *) else { throw SpeechAnalyzerError.unavailable }
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [Self.transcriber(locale: locale)]
        ) else { return nil }
        return Installation(request: request)
    }

    public func bestAudioFormat(locale: Locale) async -> AVAudioFormat? {
        guard #available(macOS 26, *) else { return nil }
        return await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [Self.transcriber(locale: locale)]
        )
    }

    /// Called on the audio tap thread; the converter is built once per format pair.
    public func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let input = buffer.format
        guard input != format else { return buffer }
        let converter = lock.withLock { () -> AVAudioConverter? in
            if let converterFormats, converterFormats.input == input, converterFormats.output == format {
                return self.converter
            }
            let made = AVAudioConverter(from: input, to: format)
            self.converter = made
            converterFormats = made == nil ? nil : (input, format)
            return made
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        let source = InputSource(buffer: buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !source.consumed else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            source.consumed = true
            inputStatus.pointee = .haveData
            return source.buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    public func makeSession(locale: Locale) async throws -> any AnalyzerSession {
        guard #available(macOS 26, *) else { throw SpeechAnalyzerError.unavailable }
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        return Session(locale: resolved)
    }

    @available(macOS 26, *)
    private static func transcriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    @available(macOS 26, *)
    private struct Installation: AssetInstallation {
        let request: AssetInstallationRequest

        var fractionCompleted: Double { request.progress.fractionCompleted }

        func downloadAndInstall() async throws { try await request.downloadAndInstall() }
    }

    /// One `SpeechAnalyzer` run: buffers go in as `AnalyzerInput`, transcriber results
    /// come out as `AnalyzerTranscript`, and `finish` finalises through the last input.
    @available(macOS 26, *)
    private final class Session: AnalyzerSession, @unchecked Sendable {
        let results: AsyncStream<AnalyzerTranscript>

        private let analyzer: SpeechAnalyzer
        private let input: AsyncStream<AnalyzerInput>.Continuation
        private let analysis: Task<CMTime?, any Error>
        private let forwarding: Task<Void, Never>
        private let forwardingFailure = ErrorBox()

        init(locale: Locale) {
            let transcriber = SpeechAnalyzerBridge.transcriber(locale: locale)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (inputSequence, input) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
            let (results, output) = AsyncStream<AnalyzerTranscript>.makeStream(bufferingPolicy: .unbounded)

            self.analyzer = analyzer
            self.input = input
            self.results = results
            analysis = Task { try await analyzer.analyzeSequence(inputSequence) }

            let failure = forwardingFailure
            forwarding = Task {
                do {
                    for try await result in transcriber.results {
                        output.yield(AnalyzerTranscript(
                            text: String(result.text.characters),
                            isFinal: result.isFinal
                        ))
                    }
                } catch {
                    failure.store(error)
                }
                output.finish()
            }
        }

        deinit {
            input.finish()
            analysis.cancel()
            forwarding.cancel()
        }

        func feed(_ buffer: AVAudioPCMBuffer) {
            input.yield(AnalyzerInput(buffer: buffer))
        }

        func finish() async throws {
            input.finish()
            let last = try await analysis.value
            if let last {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            await forwarding.value
            if let error = forwardingFailure.stored { throw error }
        }
    }

    /// The one buffer an `AVAudioConverterInputBlock` may hand over. `@unchecked`:
    /// the block is a `@Sendable` type but runs synchronously on this thread, inside
    /// `convert(to:error:withInputFrom:)`, before that call returns.
    private final class InputSource: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var consumed = false

        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    /// Carries a transcriber-stream error out of the forwarding task.
    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var error: (any Error)?

        var stored: (any Error)? { lock.withLock { error } }

        func store(_ error: any Error) { lock.withLock { self.error = error } }
    }
}

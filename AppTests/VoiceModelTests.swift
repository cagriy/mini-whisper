import AVFoundation
import Foundation
import MWMeetings
import MWVoices
import Testing

/// The fixture clips live in this test bundle, not in the app's.
private final class FixtureAnchor {}

/// R6, R26: the bundled model ships as one folder and separates two synthetic voices.
@Suite struct VoiceModelTests {
    private static func modelURL() throws -> URL {
        try #require(Bundle.main.url(forResource: "wespeaker_v2", withExtension: "mlmodelc"))
    }

    /// The clip's one window: 16 kHz mono speech looped to 10 s.
    private static func window(_ clip: String) throws -> [Float] {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: clip, withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        #expect(file.processingFormat.sampleRate == VoiceWindow.sampleRate)
        #expect(file.processingFormat.channelCount == 1)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        )
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let windows = VoiceWindow.windows(from: samples)
        try #require(windows.count == 1)
        return windows[0].samples
    }

    @Test func theModelIsInTheAppBundleAsOneFolder() throws {
        let model = try Self.modelURL()
        for file in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
            #expect(FileManager.default.fileExists(atPath: model.appendingPathComponent(file).path), "\(file)")
        }
    }

    @Test func prepareLoadsTheBundledModel() async throws {
        try await CoreMLVoiceEmbedder(modelURL: Self.modelURL()).prepare()
    }

    @Test func sameVoiceScoresAboveSeventyAndOtherVoicesBelow() async throws {
        let embedder = try CoreMLVoiceEmbedder(modelURL: Self.modelURL())
        var voices: [String: VoiceVector] = [:]
        for clip in ["daniel-1", "daniel-2", "karen-1", "karen-2"] {
            voices[clip] = try await embedder.embed(Self.window(clip))
        }
        func score(_ lhs: String, _ rhs: String) throws -> Double {
            try #require(voices[lhs]).cosine(#require(voices[rhs]))
        }

        #expect(try score("daniel-1", "daniel-2") > 0.7)
        #expect(try score("karen-1", "karen-2") > 0.7)
        for daniel in ["daniel-1", "daniel-2"] {
            for karen in ["karen-1", "karen-2"] {
                #expect(try score(daniel, karen) < 0.7, "\(daniel) · \(karen)")
            }
        }
    }
}

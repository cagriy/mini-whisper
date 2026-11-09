import AVFAudio
import Foundation
import Testing
@testable import MWAudio
import MWTestSupport

@Suite struct AACFileWriterTests {

    /// One second of a ramp as 16 kHz int16 LE PCM.
    private func oneSecondOfRamp() -> Data {
        var converter = PCMConverter(from: 16000, to: 16000)
        return converter.convert(SignalFixtures.ramp(count: 16000, from: -0.5, to: 0.5))
    }

    private func duration(_ file: AVAudioFile) -> Double {
        Double(file.length) / file.fileFormat.sampleRate
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @Test func writesADecodable16kMonoAACFile() throws {
        let dir = try TempDirectory()
        let url = dir.file("audio.m4a")
        let writer = try AACFileWriter(url: url)
        try writer.write(oneSecondOfRamp())
        try writer.finish()

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
        #expect(file.fileFormat.sampleRate == 16000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(abs(duration(file) - 1.0) <= 0.1)
    }

    @Test func writeSilencePadsTheDuration() throws {
        let dir = try TempDirectory()
        let url = dir.file("audio.m4a")
        let writer = try AACFileWriter(url: url)
        try writer.write(oneSecondOfRamp())
        try writer.writeSilence(seconds: 0.5)
        try writer.finish()

        let file = try AVAudioFile(forReading: url)
        #expect(abs(duration(file) - 1.5) <= 0.1)
    }

    @Test func fileIsOwnerReadWriteOnly() throws {
        let dir = try TempDirectory()
        let url = dir.file("audio.m4a")
        let writer = try AACFileWriter(url: url)
        #expect(try permissions(url) == 0o600)

        try writer.write(oneSecondOfRamp())
        try writer.finish()
        #expect(try permissions(url) == 0o600)
    }

    @Test func writeAfterFinishThrows() throws {
        let dir = try TempDirectory()
        let writer = try AACFileWriter(url: dir.file("audio.m4a"))
        try writer.finish()

        #expect(throws: AACFileWriterError.finished) { try writer.write(oneSecondOfRamp()) }
        #expect(throws: AACFileWriterError.finished) { try writer.writeSilence(seconds: 1) }
    }
}

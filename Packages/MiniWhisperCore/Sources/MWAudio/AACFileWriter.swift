import AVFAudio
import Foundation

/// Where a meeting's audio goes: int16 LE mono PCM in, a finished file out (design §5.3).
public protocol AudioFileWriting: AnyObject, Sendable {
    func write(_ pcm16: Data) throws
    func writeSilence(seconds: Double) throws
    func finish() throws
}

public enum AACFileWriterError: Error, Equatable {
    case finished
}

/// Encodes int16 LE mono PCM into an owner-only AAC `.m4a` (design §3 R14).
public final class AACFileWriter: AudioFileWriting, @unchecked Sendable {
    private let lock = NSLock()
    private let sampleRate: Double
    private var file: AVAudioFile?

    public init(url: URL, sampleRate: Double = 16000) throws {
        self.sampleRate = sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func write(_ pcm16: Data) throws {
        try lock.withLock {
            let file = try openFile()
            let frames = pcm16.count / 2
            guard frames > 0 else { return }
            let buffer = makeBuffer(file, frames: frames)
            let bytes = frames * 2
            _ = pcm16.copyBytes(
                to: UnsafeMutableRawBufferPointer(start: buffer.int16ChannelData![0], count: bytes),
                count: bytes
            )
            buffer.frameLength = AVAudioFrameCount(frames)
            try file.write(from: buffer)
        }
    }

    public func writeSilence(seconds: Double) throws {
        try lock.withLock {
            let file = try openFile()
            var remaining = Int((seconds * sampleRate).rounded())
            guard remaining > 0 else { return }
            // One second at a time, so an hour-long pause never allocates an hour of zeros.
            let chunk = min(remaining, Int(sampleRate))
            let buffer = makeBuffer(file, frames: chunk)
            buffer.int16ChannelData![0].update(repeating: 0, count: chunk)
            while remaining > 0 {
                buffer.frameLength = AVAudioFrameCount(min(remaining, chunk))
                try file.write(from: buffer)
                remaining -= chunk
            }
        }
    }

    public func finish() throws {
        lock.withLock {
            // Before macOS 15 the encoder flushes and the header is written when the file is released.
            if #available(macOS 15, *) { file?.close() }
            file = nil
        }
    }

    private func openFile() throws -> AVAudioFile {
        guard let file else { throw AACFileWriterError.finished }
        return file
    }

    /// `frames` is always positive and the format is the file's own, so allocation cannot fail.
    private func makeBuffer(_ file: AVAudioFile, frames: Int) -> AVAudioPCMBuffer {
        AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
    }
}

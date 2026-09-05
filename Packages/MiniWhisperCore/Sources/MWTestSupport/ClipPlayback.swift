import AVFAudio
import Foundation
import MWStreaming

/// Feeds a WAV file through a streaming engine the way the audio tap does, so the suites
/// that drive a real engine against real audio share one loop.
public enum ClipPlayback {
    public enum PlaybackError: Error, CustomStringConvertible {
        case noBuffer(String)

        public var description: String {
            switch self {
            case .noBuffer(let clip): "could not allocate a read buffer for \(clip)"
            }
        }
    }

    private static let frameCapacity: AVAudioFrameCount = 4_096

    public static func play(
        _ clip: URL,
        through engine: any StreamingEngine,
        sink: any TranscriptSink,
        timeout: Duration
    ) async throws -> StreamResult {
        engine.start(sink: sink)

        let file = try AVAudioFile(forReading: clip)
        // Bounded by framePosition: on macOS 26 a read at end-of-file throws
        // _GenericObjCError.nilError instead of returning zero frames.
        while file.framePosition < file.length {
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat, frameCapacity: frameCapacity
                )
            else { throw PlaybackError.noBuffer(clip.lastPathComponent) }
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            try file.read(into: buffer, frameCount: min(frameCapacity, remaining))
            guard buffer.frameLength > 0 else { break }
            engine.feed(buffer)
        }

        return await engine.finish(timeout: timeout)
    }
}

import AVFAudio
import Foundation
import MWConfig
import MWStreaming

/// A `StreamingEngine` with a canned result: records the sink it was started with, the
/// buffers it was fed and the timeout it was finished with, and never sleeps — so the
/// pipeline's timeout rules can be asserted without any real time passing.
public final class FakeStreamingEngine: StreamingEngine, @unchecked Sendable {
    private struct Storage {
        var sink: (any TranscriptSink)?
        var finishTimeout: Duration?
        var fedBuffers = 0
    }

    public let name: EngineName

    private let lock = NSLock()
    private var storage = Storage()
    private let result: StreamResult

    public init(
        name: EngineName = .onDevice,
        result: StreamResult = StreamResult(
            text: "streamed text", ok: true, usage: StreamUsage(seconds: 3)
        )
    ) {
        self.name = name
        self.result = result
    }

    public var sink: (any TranscriptSink)? { lock.withLock { storage.sink } }
    public var finishTimeout: Duration? { lock.withLock { storage.finishTimeout } }
    public var fedBuffers: Int { lock.withLock { storage.fedBuffers } }

    public func start(sink: any TranscriptSink) {
        lock.withLock { storage.sink = sink }
    }

    public func feed(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { storage.fedBuffers += 1 }
    }

    public func finish(timeout: Duration) async -> StreamResult {
        lock.withLock { storage.finishTimeout = timeout }
        return result
    }
}

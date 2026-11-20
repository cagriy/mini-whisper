import os

/// The last `seconds` of 16 kHz audio by meeting time, for voice recognition (design v8 R5, R28).
///
/// The capture tick appends and the recogniser reads, so the chunks sit behind a lock. Appends
/// arrive in time order, possibly with gaps (pause, device switch), so each chunk keeps its own
/// start; audio more than `seconds` before the newest sample is dropped.
final class VoiceAudioBuffer: Sendable {
    private struct Chunk {
        /// Meeting seconds of `samples[0]`.
        let start: Double
        let samples: [Float]
        /// Samples before this index are evicted.
        var first = 0

        var end: Double { start + Double(samples.count) / MeetingAudioPath.sampleRate }

        /// The sample index at meeting time `time`, clamped to the live samples.
        func index(at time: Double) -> Int {
            let index = ((time - start) * MeetingAudioPath.sampleRate).rounded()
            return Int(min(max(index, Double(first)), Double(samples.count)))
        }
    }

    private struct Storage {
        var chunks: [Chunk] = []
        /// Index of the oldest live chunk; the dead prefix is compacted in bulk, not per append.
        var head = 0
    }

    private let seconds: Double
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    init(seconds: Double) {
        self.seconds = seconds
    }

    func append(_ samples: [Float], at time: Double) {
        guard !samples.isEmpty else { return }
        let chunk = Chunk(start: time, samples: samples)
        let cutoff = chunk.end - seconds
        storage.withLock { storage in
            storage.chunks.append(chunk)
            while storage.head < storage.chunks.count {
                let cut = storage.chunks[storage.head].index(at: cutoff)
                guard cut == storage.chunks[storage.head].samples.count else {
                    storage.chunks[storage.head].first = cut
                    break
                }
                storage.head += 1
            }
            if storage.head * 2 > storage.chunks.count {
                storage.chunks.removeFirst(storage.head)
                storage.head = 0
            }
        }
    }

    /// The held samples from `start` to `end`, gaps left out.
    func samples(from start: Double, to end: Double) -> [Float] {
        guard end > start else { return [] }
        return storage.withLock { storage in
            var out: [Float] = []
            for chunk in storage.chunks[storage.head...] where chunk.end > start {
                guard chunk.start < end else { break }
                out += chunk.samples[chunk.index(at: start)..<chunk.index(at: end)]
            }
            return out
        }
    }
}

/// The buffers the audio tick fills: the microphone always, the system audio in a remote meeting.
struct VoiceBuffers: Sendable {
    let microphone: VoiceAudioBuffer
    let system: VoiceAudioBuffer?
}

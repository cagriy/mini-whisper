import AVFAudio
import MWAudio
import MWMeetings
import MWSupport
import os

/// The meeting's audio tick (design §5.6), run on the capture thread for every microphone
/// buffer: resample to 16 kHz, then in a remote meeting gate the microphone and mix in the
/// system audio, then record, stream and bill. The tap threads call in, so the state is
/// lock-guarded; only segments, partials and one-second ticks reach the main actor.
final class MeetingAudioPath: BufferListener, Sendable {
    static let sampleRate = 16_000.0

    private struct State {
        var inputRate = 0.0
        var converter = PCMConverter(from: 16_000, to: 16_000)
        var gate = SpeechGate()
        var recorder: MeetingRecorder?
        var billing: MeetingBilling
        /// Meeting seconds of the 16 kHz sample count's zero.
        var anchor = 0.0
        var samples = 0

        /// Meeting seconds of the next microphone sample.
        var time: Double { anchor + Double(samples) / MeetingAudioPath.sampleRate }
    }

    private let mode: MeetingMode
    private let state: OSAllocatedUnfairLock<State>
    private let ring = SystemAudioRing()
    /// Weak: the supervisor's events end only when it is released (Stop drains them).
    private weak let supervisor: SessionSupervisor?

    init(mode: MeetingMode, recorder: MeetingRecorder?, billing: MeetingBilling, supervisor: SessionSupervisor) {
        self.mode = mode
        self.supervisor = supervisor
        state = OSAllocatedUnfairLock(initialState: State(recorder: recorder, billing: billing))
    }

    var gateView: SpeechGate.View { state.withLock { $0.gate.view } }
    var isSpeakingNow: Bool { state.withLock { $0.gate.isSpeakingNow } }
    var billing: MeetingBilling { state.withLock { $0.billing } }

    /// A microphone buffer, on the capture thread.
    func feed(_ buffer: AVAudioPCMBuffer) {
        let input = Self.samples(of: buffer)
        let rate = buffer.format.sampleRate
        guard !input.isEmpty, rate > 0 else { return }
        state.withLock { state in
            if state.inputRate != rate {
                state.inputRate = rate
                state.converter = PCMConverter(from: rate, to: Self.sampleRate)
            }
            let mic = state.converter.resample(input)
            guard !mic.isEmpty else { return }
            let time = state.time
            var mixed = mic
            if mode == .remote {
                state.gate.push(mic, at: time)
                mixed = AudioMixer.mix(mic: mic, system: ring.take(mic.count))
            }
            state.samples += mic.count
            Self.record(mixed, &state)
            if supervisor?.feed(Self.buffer(mixed), at: time) == true {
                state.billing.add(seconds: Double(mixed.count) / Self.sampleRate)
            }
        }
    }

    /// A 16 kHz mono system-audio buffer, on the tap's thread.
    func pushSystem(_ buffer: AVAudioPCMBuffer) {
        ring.push(Self.samples(of: buffer))
    }

    /// Closes the audio file; nothing is recorded after.
    func finish() {
        state.withLock { state in
            guard let recorder = state.recorder else { return }
            state.recorder = nil
            do {
                try recorder.finish()
            } catch {
                Log.meeting.error("audio file not finished: \(AnyError(error).description)")
            }
        }
    }

    /// A write error ends the audio file rather than failing every later buffer.
    private static func record(_ samples: [Float], _ state: inout State) {
        guard state.recorder != nil else { return }
        do {
            try state.recorder?.write(samples)
        } catch {
            Log.meeting.error("audio recording stopped: \(AnyError(error).description)")
            try? state.recorder?.finish()
            state.recorder = nil
        }
    }

    private static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return [Float](UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}

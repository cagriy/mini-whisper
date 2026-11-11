import AVFAudio
import MWAudio
import MWMeetings
import MWSupport
import os

/// The meeting's audio tick (design §5.6), run on the capture thread for every microphone
/// buffer: resample to 16 kHz, then in a remote meeting gate the microphone, level the system
/// audio and mix it in, then record, stream and bill. The tap threads call in, so the state is
/// lock-guarded; only segments, partials and one-second ticks reach the main actor.
final class MeetingAudioPath: BufferListener, Sendable {
    static let sampleRate = 16_000.0

    private struct State {
        var inputRate = 0.0
        var converter = PCMConverter(from: 16_000, to: 16_000)
        var gate = SpeechGate()
        var leveller = SystemAudioLeveller()
        var recorder: MeetingRecorder?
        var billing: MeetingBilling
        /// False while paused: buffers only move the time on.
        var streaming = true
        /// Meeting seconds of the 16 kHz sample count's zero.
        var anchor = 0.0
        var samples = 0
        /// Meeting seconds of the latest system-audio buffer.
        var lastSystemAudio = 0.0

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
    var time: Double { state.withLock { $0.time } }
    var lastSystemAudio: Double { state.withLock { $0.lastSystemAudio } }

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
            state.samples += mic.count
            // Taken while paused too, so the ring stays in step with the microphone.
            let system = mode == .remote ? ring.take(mic.count) : []
            guard state.streaming else { return }
            var mixed = mic
            if mode == .remote {
                state.gate.push(mic, at: time)
                mixed = AudioMixer.mix(mic: mic, system: state.leveller.process(system))
            }
            Self.withRecorder(&state) { try $0.write(mixed) }
            if supervisor?.feed(Self.buffer(mixed), at: time) == true {
                state.billing.add(seconds: Double(mixed.count) / Self.sampleRate)
            }
        }
    }

    /// A 16 kHz mono system-audio buffer, on the tap's thread, with the meeting time it arrived.
    func pushSystem(_ buffer: AVAudioPCMBuffer, at time: Double) {
        ring.push(Self.samples(of: buffer))
        state.withLock { $0.lastSystemAudio = time }
    }

    func systemPeakSinceLastCall() -> Float {
        ring.peakSinceLastCall()
    }

    /// Stops streaming and recording; returns the meeting time it stopped at.
    func pause() -> Double {
        state.withLock { state in
            let time = state.time
            state.streaming = false
            state.recorder?.pause(at: time)
            return time
        }
    }

    /// Streams and records again; the audio file gets silence for the paused span.
    func resume() -> Double {
        state.withLock { state in
            state.streaming = true
            let time = state.time
            Self.withRecorder(&state) { try $0.resume(at: time) }
            return time
        }
    }

    /// Moves the next sample's time up to `time` when the microphone fell behind it: no
    /// buffers arrive while the input device switches or the Mac sleeps. While streaming,
    /// the audio file gets silence for the jump. Returns the time before.
    @discardableResult
    func catchUp(to time: Double) -> Double {
        state.withLock { state in
            let from = state.time
            guard time > from else { return from }
            state.anchor = time
            state.samples = 0
            if state.streaming {
                state.recorder?.pause(at: from)
                Self.withRecorder(&state) { try $0.resume(at: time) }
            }
            return from
        }
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
    private static func withRecorder(_ state: inout State, _ write: (inout MeetingRecorder) throws -> Void) {
        guard var recorder = state.recorder else { return }
        do {
            try write(&recorder)
            state.recorder = recorder
        } catch {
            Log.meeting.error("audio recording stopped: \(AnyError(error).description)")
            try? recorder.finish()
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

import AVFAudio
import Testing

import MWConfig
import MWCorrections
@testable import MWMeetingPipeline
import MWMeetings
import MWTestSupport

/// The audio tick filling the voice buffers (design v8 §5 Control flow, Audio tick; R5).
@Suite struct MeetingAudioPathVoiceTests {
    private static let tick = 1_600

    @Test func remoteAppendsMicrophoneAndSystemAtTheTickTime() {
        let rig = Rig(mode: .remote, voices: .both)
        rig.path.pushSystem(Self.audio(0.2, count: 8_000), at: 0)
        rig.feed(0.1, ticks: 5)

        #expect(rig.microphone.samples(from: 0, to: 0.5) == [Float](repeating: 0.1, count: 8_000))
        #expect(rig.system?.samples(from: 0, to: 0.5) == [Float](repeating: 0.2, count: 8_000))

        // After a jump the next tick lands at its own time.
        rig.path.catchUp(to: 2)
        rig.feed(0.3, ticks: 1)
        #expect(rig.microphone.samples(from: 0.5, to: 2).isEmpty)
        #expect(rig.microphone.samples(from: 2, to: 2.1) == [Float](repeating: 0.3, count: Self.tick))
        #expect(rig.system?.samples(from: 2, to: 2.1) == [Float](repeating: 0, count: Self.tick))
    }

    @Test func inRoomAppendsTheMicrophoneOnly() {
        let rig = Rig(mode: .inRoom, voices: .both)
        rig.path.pushSystem(Self.audio(0.2, count: 8_000), at: 0)
        rig.feed(0.1, ticks: 5)

        #expect(rig.microphone.samples(from: 0, to: 0.5) == [Float](repeating: 0.1, count: 8_000))
        #expect(rig.system?.samples(from: 0, to: 10).isEmpty == true)
    }

    @Test func pausedAppendsNothing() {
        let rig = Rig(mode: .remote, voices: .both)
        rig.feed(0.1, ticks: 1)
        _ = rig.path.pause()
        rig.feed(0.2, ticks: 2)
        _ = rig.path.resume()
        rig.feed(0.3, ticks: 1)

        #expect(rig.microphone.samples(from: 0, to: 1).count == 2 * Self.tick)
        #expect(rig.microphone.samples(from: 0.1, to: 0.3).isEmpty)
        #expect(rig.microphone.samples(from: 0.3, to: 0.4) == [Float](repeating: 0.3, count: Self.tick))
        #expect(rig.system?.samples(from: 0, to: 1).count == 2 * Self.tick)
    }

    @Test(arguments: [MeetingMode.remote, .inRoom])
    func withoutBuffersTheTickIsUnchanged(_ mode: MeetingMode) {
        let runs = [Rig.Voices.absent, .passedNil, .both].map { voices in
            let rig = Rig(mode: mode, voices: voices)
            rig.path.pushSystem(Self.audio(0.6, count: 4_000), at: 0)
            rig.feed(0.5, ticks: 3)
            _ = rig.path.pause()
            rig.feed(0.5, ticks: 1)
            _ = rig.path.resume()
            rig.feed(0.4, ticks: 2)
            return Run(
                fed: rig.provider.engines.map(\.fedBuffers),
                billed: rig.path.billing.engineSeconds,
                written: rig.writer.events
            )
        }

        #expect(runs[0].fed == [5])
        #expect(runs[1] == runs[0])
        #expect(runs[2] == runs[0])
    }

    private static func audio(_ value: Float, count: Int) -> AVAudioPCMBuffer {
        PCMBufferFactory.make(samples: [Float](repeating: value, count: count), sampleRate: 16_000)
    }

    private struct Run: Equatable {
        var fed: [Int]
        var billed: Double
        var written: [FakeAudioFileWriter.Event]
    }

    /// A path over a supervisor opened at 0 on a fake provider, recording to a fake writer.
    private struct Rig {
        enum Voices {
            /// The init parameter left out.
            case absent
            /// `voices: nil` passed.
            case passedNil
            case both
        }

        let provider = FakeMeetingEngineProvider()
        let writer = FakeAudioFileWriter()
        let supervisor: SessionSupervisor
        let path: MeetingAudioPath
        let microphone = VoiceAudioBuffer(seconds: 120)
        let system: VoiceAudioBuffer? = VoiceAudioBuffer(seconds: 120)

        init(mode: MeetingMode, voices: Voices) {
            supervisor = SessionSupervisor(
                provider: provider, engine: .assemblyaiStreaming, key: "placeholder-not-a-real-key",
                hints: .none, clock: VirtualClock()
            )
            let recorder = MeetingRecorder(writer: writer)
            let billing = MeetingBilling(engine: .assemblyaiStreaming, overrides: [:])
            switch voices {
            case .absent:
                path = MeetingAudioPath(mode: mode, recorder: recorder, billing: billing, supervisor: supervisor)
            case .passedNil:
                path = MeetingAudioPath(
                    mode: mode, recorder: recorder, billing: billing, supervisor: supervisor, voices: nil
                )
            case .both:
                path = MeetingAudioPath(
                    mode: mode, recorder: recorder, billing: billing, supervisor: supervisor,
                    voices: VoiceBuffers(microphone: microphone, system: system)
                )
            }
            supervisor.open(at: 0)
        }

        /// `ticks` microphone buffers of 0.1 s at 16 kHz, each sample `value`.
        func feed(_ value: Float, ticks: Int) {
            for _ in 0..<ticks {
                path.feed(MeetingAudioPathVoiceTests.audio(value, count: MeetingAudioPathVoiceTests.tick))
            }
        }
    }
}

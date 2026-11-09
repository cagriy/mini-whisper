import Foundation
import Testing

import MWMeetingPipeline
import MWTestSupport

@Suite struct MeetingRecorderTests {
    private func pcm16(_ values: [Int16]) -> Data {
        values.reduce(into: Data()) { data, value in
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
    }

    @Test func writesInt16PCM() throws {
        let writer = FakeAudioFileWriter()
        var recorder = MeetingRecorder(writer: writer)
        try recorder.write([0, 0.5, -0.5, 1, -1, 2])
        try recorder.write([0.25])
        #expect(writer.events == [
            .write(pcm16([0, 16383, -16383, 32767, -32767, 32767])),
            .write(pcm16([8191])),
        ])
    }

    @Test func resumePadsThePausedSpanWithSilence() throws {
        let writer = FakeAudioFileWriter()
        var recorder = MeetingRecorder(writer: writer)
        try recorder.write([0.5])
        recorder.pause(at: 12.5)
        recorder.pause(at: 20)
        // Audio still arriving while paused is not written: the silence stands for it.
        try recorder.write([0.5])
        try recorder.resume(at: 152.5)
        try recorder.resume(at: 160)
        try recorder.write([1])
        #expect(writer.events == [
            .write(pcm16([16383])),
            .silence(seconds: 140),
            .write(pcm16([32767])),
        ])
    }

    @Test func finishClosesTheWriter() throws {
        let writer = FakeAudioFileWriter()
        var recorder = MeetingRecorder(writer: writer)
        try recorder.write([0])
        try recorder.finish()
        #expect(writer.events == [.write(pcm16([0])), .finish])
    }
}

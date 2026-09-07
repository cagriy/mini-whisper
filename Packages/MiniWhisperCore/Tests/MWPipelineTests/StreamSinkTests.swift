import Foundation
import MWStreaming
import MWTestSupport
import Testing

import MWPipeline

/// The controller's `TranscriptSink`: compound assembly into caption events, the failed
/// flag, and the once-per-dictation `captionUnavailable` (F21, F22).
/// A port of `_StreamSink` in `../mini-whisper-py/src/mini_whisper/controller.py`.
@Suite struct StreamSinkTests {
    private struct EngineFailure: Error {}

    private func makeSink() -> (StreamSink, UIEventRecorder) {
        let recorder = UIEventRecorder()
        return (StreamSink(emit: recorder.emit), recorder)
    }

    @Test func partialEmitsCaptionWithFullCompoundText() {
        let (sink, recorder) = makeSink()

        sink.onPartial("hello")
        sink.onFinal("hello world.")
        sink.onPartial("and more")

        #expect(recorder.events == [
            .caption(text: "hello", partial: true, dimmed: false),
            .caption(text: "hello world.", partial: true, dimmed: false),
            .caption(text: "hello world. and more", partial: true, dimmed: false),
        ])
        #expect(sink.text == "hello world. and more")
    }

    @Test func finalEmitsCaption() {
        let (sink, recorder) = makeSink()

        sink.onFinal("hello world.")

        #expect(recorder.events == [.caption(text: "hello world.", partial: true, dimmed: false)])
    }

    @Test func engineErrorSetsFailedAndEmitsUnavailableOnce() {
        let (sink, recorder) = makeSink()

        sink.onEngineError(EngineFailure())
        sink.onEngineError(EngineFailure())

        #expect(sink.failed)
        #expect(recorder.events == [.captionUnavailable])
    }

    @Test func markUnavailableIsIdempotent() {
        let (sink, recorder) = makeSink()

        sink.markUnavailable()
        sink.markUnavailable()

        #expect(recorder.events == [.captionUnavailable])
        #expect(!sink.failed)
    }

    @Test func eventsAfterFailureAreIgnored() {
        let (sink, recorder) = makeSink()
        sink.onPartial("hel")

        sink.onEngineError(EngineFailure())
        sink.onPartial("hello")
        sink.onFinal("hello world.")

        #expect(recorder.events == [
            .caption(text: "hel", partial: true, dimmed: false),
            .captionUnavailable,
        ])
        #expect(sink.text == "hel")
    }
}

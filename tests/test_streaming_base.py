"""Tests for mini_whisper/streaming/base.py."""

from mini_whisper.streaming.base import (
    CompoundTranscript,
    StreamingEngine,
    StreamResult,
    TranscriptSink,
)


# ---------------------------------------------------------------------------
# CompoundTranscript
# ---------------------------------------------------------------------------

def test_partial_replaces_previous_partial():
    ct = CompoundTranscript()
    ct.add_partial("hel")
    ct.add_partial("hello wor")
    assert ct.text == "hello wor"


def test_final_appends_and_clears_partial():
    ct = CompoundTranscript()
    ct.add_partial("hello wor")
    ct.add_final("hello world.")
    assert ct.text == "hello world."
    ct.add_partial("next bit")
    assert ct.text == "hello world. next bit"


def test_multiple_finals_joined():
    ct = CompoundTranscript()
    ct.add_final("First segment.")
    ct.add_final("Second segment.")
    ct.add_partial("third")
    assert ct.text == "First segment. Second segment. third"


def test_empty_compound():
    ct = CompoundTranscript()
    assert ct.text == ""


def test_whitespace_segments_skipped():
    ct = CompoundTranscript()
    ct.add_final("  Hello.  ")
    ct.add_final("   ")
    ct.add_partial("  ")
    assert ct.text == "Hello."


# ---------------------------------------------------------------------------
# StreamResult
# ---------------------------------------------------------------------------

def test_stream_result_defaults():
    result = StreamResult()
    assert result.text == ""
    assert result.ok is False
    assert result.usage == {"input_tokens": 0, "output_tokens": 0, "seconds": 0.0}


def test_stream_result_usage_not_shared():
    a = StreamResult()
    b = StreamResult()
    a.usage["seconds"] = 5.0
    assert b.usage["seconds"] == 0.0


def test_stream_result_explicit_values():
    result = StreamResult(text="hi", ok=True,
                          usage={"input_tokens": 1, "output_tokens": 2, "seconds": 3.0})
    assert result.ok is True
    assert result.text == "hi"


# ---------------------------------------------------------------------------
# Protocols
# ---------------------------------------------------------------------------

def test_protocols_are_satisfiable():
    class FakeSink:
        def on_partial(self, text: str) -> None: ...
        def on_final(self, text: str) -> None: ...
        def on_engine_error(self, exc: Exception) -> None: ...

    class FakeEngine:
        name = "fake"
        def start(self, sink) -> None: ...
        def feed(self, pcm_buffer) -> None: ...
        def finish(self, timeout: float = 5.0) -> StreamResult:
            return StreamResult(text="", ok=False)

    assert isinstance(FakeSink(), TranscriptSink)
    assert isinstance(FakeEngine(), StreamingEngine)

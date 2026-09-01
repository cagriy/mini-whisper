"""Tests for mini_whisper/streaming/on_device.py (Speech framework faked)."""

from unittest.mock import MagicMock

import pytest

from mini_whisper.streaming.on_device import OnDeviceEngine, ensure_authorized

from .conftest import FakeSink


class FakeSpeechAPI:
    """Stands in for _SpeechAPI: plain-Python boundary, no pyobjc."""

    def __init__(self, status=3):
        self.status = status
        self.request_auth_calls = 0
        self.request = MagicMock()
        self.on_result = None
        self.raise_on_start = None

    def authorization_status(self):
        return self.status

    def request_authorization(self):
        self.request_auth_calls += 1

    def start_task(self, on_result):
        if self.raise_on_start is not None:
            raise self.raise_on_start
        self.on_result = on_result
        return self.request


@pytest.fixture()
def engine_and_parts():
    api = FakeSpeechAPI()
    sink = FakeSink()
    engine = OnDeviceEngine(api=api)
    engine.start(sink)
    return engine, api, sink


# ---------------------------------------------------------------------------
# ensure_authorized
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "status,expected",
    [(0, "undetermined"), (1, "denied"), (2, "denied"), (3, "authorized")],
)
def test_ensure_authorized_maps_status(status, expected):
    api = FakeSpeechAPI(status=status)
    assert ensure_authorized(api=api) == expected


def test_ensure_authorized_requests_only_when_undetermined():
    api = FakeSpeechAPI(status=0)
    ensure_authorized(api=api)
    assert api.request_auth_calls == 1

    for status in (1, 2, 3):
        api = FakeSpeechAPI(status=status)
        ensure_authorized(api=api)
        assert api.request_auth_calls == 0


# ---------------------------------------------------------------------------
# feed
# ---------------------------------------------------------------------------

def test_feed_forwards_buffers_to_request(engine_and_parts):
    engine, api, _ = engine_and_parts
    buf = object()
    engine.feed(buf)
    api.request.appendAudioPCMBuffer_.assert_called_once_with(buf)


def test_feed_before_start_buffers_and_flushes_on_start():
    api = FakeSpeechAPI()
    engine = OnDeviceEngine(api=api)
    first, second = object(), object()
    engine.feed(first)
    engine.feed(second)
    api.request.appendAudioPCMBuffer_.assert_not_called()

    engine.start(FakeSink())
    assert [c.args[0] for c in api.request.appendAudioPCMBuffer_.call_args_list] == [first, second]


# ---------------------------------------------------------------------------
# recogniser callbacks → sink
# ---------------------------------------------------------------------------

def test_partial_and_final_callbacks_drive_sink(engine_and_parts):
    _, api, sink = engine_and_parts
    api.on_result("hello", False, None)
    api.on_result("hello world", False, None)
    api.on_result("hello world.", True, None)

    assert sink.partials == ["hello", "hello world"]
    assert sink.finals == ["hello world."]


# ---------------------------------------------------------------------------
# finish
# ---------------------------------------------------------------------------

def test_finish_ends_audio_and_returns_compound_text(engine_and_parts):
    engine, api, _ = engine_and_parts
    api.on_result("hello world.", True, None)

    result = engine.finish(timeout=1.0)
    api.request.endAudio.assert_called_once()
    assert result.ok is True
    assert result.text == "hello world."


def test_finish_times_out_without_final(engine_and_parts):
    engine, _, _ = engine_and_parts
    result = engine.finish(timeout=0.05)
    assert result.ok is False
    assert result.text == ""


def test_recogniser_error_fails_engine(engine_and_parts):
    engine, api, sink = engine_and_parts
    api.on_result("", False, "kAFAssistantErrorDomain error 1101")

    assert len(sink.errors) == 1
    result = engine.finish(timeout=1.0)
    assert result.ok is False


def test_recogniser_unavailable_at_start_fails_engine():
    api = FakeSpeechAPI()
    api.raise_on_start = RuntimeError("recogniser unavailable")
    sink = FakeSink()
    engine = OnDeviceEngine(api=api)
    engine.start(sink)

    assert len(sink.errors) == 1
    result = engine.finish(timeout=1.0)
    assert result.ok is False


# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------

def test_usage_reports_seconds_and_zero_tokens(engine_and_parts, monkeypatch):
    engine, api, _ = engine_and_parts
    monkeypatch.setattr(
        "mini_whisper.streaming.on_device.time.monotonic",
        lambda: engine._started_at + 2.5,
    )
    api.on_result("done", True, None)
    result = engine.finish(timeout=1.0)

    assert result.usage == {"input_tokens": 0, "output_tokens": 0, "seconds": 2.5}

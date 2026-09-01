"""Tests for mini_whisper/controller.py."""

import io
import queue
from unittest.mock import MagicMock, patch

import httpx
import pytest

from mini_whisper.controller import Controller, UIEvent


def _fake_audio() -> io.BytesIO:
    buf = io.BytesIO(b"fake wav")
    buf.name = "audio.wav"
    return buf


def _make_error_response(status_code: int) -> httpx.HTTPStatusError:
    request = httpx.Request("POST", "https://api.openai.com/test")
    response = httpx.Response(status_code, request=request)
    return httpx.HTTPStatusError(str(status_code), request=request, response=response)


@pytest.fixture()
def ctrl(monkeypatch):
    """Controller with all macOS-dependent components mocked out."""
    mock_recorder = MagicMock()
    mock_recorder.is_recording = False
    mock_recorder.duration_seconds.return_value = 1.0
    mock_recorder.average_rms = 0.02
    mock_recorder.stop.return_value = _fake_audio()

    monkeypatch.setattr("mini_whisper.controller.Recorder", MagicMock(return_value=mock_recorder))
    monkeypatch.setattr("mini_whisper.controller.play_sound", MagicMock())
    monkeypatch.setattr("mini_whisper.controller.transcribe",
                        MagicMock(return_value=("hello world", {"input_tokens": 10, "output_tokens": 0})))
    monkeypatch.setattr("mini_whisper.controller.clean",
                        MagicMock(return_value=("Hello world.", {"input_tokens": 5, "output_tokens": 8})))
    monkeypatch.setattr("mini_whisper.controller.paste", MagicMock())
    monkeypatch.setattr("mini_whisper.controller.config.get_api_key", MagicMock(return_value="sk-test"))
    monkeypatch.setattr("mini_whisper.controller.config.get_transcribe_prompt", MagicMock(return_value=""))
    monkeypatch.setattr("mini_whisper.controller.config.load",
                        MagicMock(return_value={"cleanup_enabled": True}))
    monkeypatch.setattr("mini_whisper.controller.config.get_prompt", MagicMock(return_value="Clean up."))
    monkeypatch.setattr("mini_whisper.controller.config.add_usage",
                        MagicMock(return_value={"input_tokens": 15, "output_tokens": 8,
                                                "streamed_seconds": {}, "cost_usd": 0.0}))
    return Controller()


def _drain(q: queue.Queue) -> list[UIEvent]:
    events = []
    while True:
        try:
            events.append(q.get_nowait())
        except queue.Empty:
            break
    return events


# ---------------------------------------------------------------------------
# _process: happy path
# ---------------------------------------------------------------------------

def test_process_success(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    kinds = [e.kind for e in events]
    assert "result" in kinds
    assert "usage" in kinds
    result_event = next(e for e in events if e.kind == "result")
    assert result_event.text == "Hello world."
    mod.paste.assert_called_once()


def test_process_no_api_key(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    mod.config.get_api_key.return_value = None
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "error" and "API key" in e.text for e in events)
    mod.paste.assert_not_called()


def test_process_empty_transcript(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    mod.transcribe.return_value = ("   ", {"input_tokens": 0, "output_tokens": 0})
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "idle" for e in events)
    mod.paste.assert_not_called()


def test_process_cleanup_disabled(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    mod.config.load.return_value = {"cleanup_enabled": False}
    mod.transcribe.return_value = ("raw text", {"input_tokens": 5, "output_tokens": 0})
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    mod.clean.assert_not_called()
    mod.paste.assert_called_once_with("raw text", submit=False)


def test_process_submit_flag(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=True, generation=1)

    mod.paste.assert_called_once_with("Hello world.", submit=True)


# ---------------------------------------------------------------------------
# _process: error handling
# ---------------------------------------------------------------------------

def test_process_http_401(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    mod.transcribe.side_effect = _make_error_response(401)
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "error" and "Invalid API key" in e.text for e in events)


def test_process_http_429(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    mod.transcribe.side_effect = _make_error_response(429)
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "error" and "Rate limited" in e.text for e in events)


def test_process_generic_exception(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    mod.transcribe.side_effect = RuntimeError("network blip")
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "error" for e in events)


# ---------------------------------------------------------------------------
# Generation guard: stale worker discards result
# ---------------------------------------------------------------------------

def test_generation_guard_discards_paste(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    # Generation 2 is "current"; worker was started with gen=1
    ctrl._generation = 2
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "idle" for e in events)
    assert not any(e.kind == "result" for e in events)
    mod.paste.assert_not_called()


def test_generation_guard_allows_current(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "result" for e in events)
    mod.paste.assert_called_once()

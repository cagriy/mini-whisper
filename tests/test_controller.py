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
    monkeypatch.setattr("mini_whisper.controller.config.get_streaming_api_key",
                        MagicMock(return_value=None))
    monkeypatch.setattr("mini_whisper.controller.make_engine",
                        MagicMock(return_value=(None, "disabled")))
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


# ---------------------------------------------------------------------------
# Streaming pipeline (Stage 8)
# ---------------------------------------------------------------------------

from mini_whisper.streaming import StreamResult  # noqa: E402


class FakeEngine:
    """Implements the StreamingEngine protocol with a canned result."""

    name = "fake"

    def __init__(self, result=None):
        self.sink = None
        self.finish_timeout = None
        self.result = result if result is not None else StreamResult(
            text="streamed text",
            ok=True,
            usage={"input_tokens": 0, "output_tokens": 0, "seconds": 3.0},
        )

    def start(self, sink):
        self.sink = sink

    def feed(self, pcm_buffer):
        pass

    def finish(self, timeout=5.0):
        self.finish_timeout = timeout
        return self.result


def _press_streaming(ctrl, engine, hotkey="paste"):
    """Press with make_engine returning the fake engine; return its sink."""
    import mini_whisper.controller as mod
    mod.make_engine.return_value = (engine, None)
    ctrl.on_hotkey_press(hotkey)
    ctrl.recorder.is_recording = True
    return engine.sink


def _release_held(ctrl, hotkey="paste"):
    """Release after a >HOLD_THRESHOLD hold; join the worker if one started."""
    ctrl._press_time -= 1.0
    ctrl.on_hotkey_release(hotkey)
    if ctrl._worker is not None:
        ctrl._worker.join(timeout=5)


def test_streamed_press_installs_listener_and_starts_engine(ctrl):
    engine = FakeEngine()
    sink = _press_streaming(ctrl, engine)

    assert sink is not None  # engine.start received the controller's sink
    ctrl.recorder.set_buffer_listener.assert_called_once_with(engine.feed)


def test_streamed_happy_path_skips_batch(ctrl):
    import mini_whisper.controller as mod
    engine = FakeEngine()
    _press_streaming(ctrl, engine)
    _release_held(ctrl)

    mod.transcribe.assert_not_called()
    mod.clean.assert_called_once_with("streamed text", "sk-test", "Clean up.")
    mod.paste.assert_called_once_with("Hello world.", submit=False)
    # Listener cleared at stop, engine finished with the default timeout
    ctrl.recorder.set_buffer_listener.assert_called_with(None)
    assert engine.finish_timeout == 5.0
    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "result" and e.text == "Hello world." for e in events)


def test_caption_events_flow_through_queue(ctrl):
    engine = FakeEngine()
    sink = _press_streaming(ctrl, engine)

    sink.on_partial("hello")
    sink.on_final("hello world.")
    sink.on_partial("and more")

    captions = [e for e in _drain(ctrl.ui_queue) if e.kind == "caption"]
    assert [(c.text, c.partial, c.dimmed) for c in captions] == [
        ("hello", True, False),
        ("hello world.", True, False),
        ("hello world. and more", True, False),
    ]


def test_release_emits_dimmed_caption(ctrl):
    engine = FakeEngine()
    sink = _press_streaming(ctrl, engine)
    sink.on_partial("hello world")
    _release_held(ctrl)

    events = _drain(ctrl.ui_queue)
    dimmed = [e for e in events if e.kind == "caption" and e.dimmed]
    assert [(c.text, c.partial) for c in dimmed] == [("hello world", False)]
    # Dimmed re-emit arrives with/after processing, before result
    kinds = [e.kind for e in events]
    assert kinds.index("processing") < kinds.index("result")


def test_engine_none_reproduces_batch_flow_with_no_captions(ctrl):
    import mini_whisper.controller as mod
    mod.make_engine.return_value = (None, "disabled")
    ctrl.on_hotkey_press("paste")
    ctrl.recorder.is_recording = True
    _release_held(ctrl)

    mod.transcribe.assert_called_once()
    mod.paste.assert_called_once_with("Hello world.", submit=False)
    events = _drain(ctrl.ui_queue)
    assert not any(e.kind in ("caption", "caption_unavailable") for e in events)


def test_mid_stream_error_falls_back_to_batch(ctrl):
    import mini_whisper.controller as mod
    engine = FakeEngine(result=StreamResult(text="", ok=False,
                                            usage={"input_tokens": 0, "output_tokens": 0, "seconds": 2.0}))
    sink = _press_streaming(ctrl, engine)
    sink.on_partial("hel")
    sink.on_engine_error(RuntimeError("socket dropped"))
    _release_held(ctrl)

    mod.transcribe.assert_called_once()
    mod.paste.assert_called_once_with("Hello world.", submit=False)
    events = _drain(ctrl.ui_queue)
    assert [e.kind for e in events].count("caption_unavailable") == 1


def test_finish_not_ok_falls_back_to_batch(ctrl):
    import mini_whisper.controller as mod
    engine = FakeEngine(result=StreamResult(text="", ok=False,
                                            usage={"input_tokens": 0, "output_tokens": 0, "seconds": 2.0}))
    _press_streaming(ctrl, engine)
    _release_held(ctrl)

    mod.transcribe.assert_called_once()
    mod.paste.assert_called_once_with("Hello world.", submit=False)
    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "caption_unavailable" for e in events)


def test_empty_compound_falls_back_to_batch(ctrl):
    import mini_whisper.controller as mod
    engine = FakeEngine(result=StreamResult(text="   ", ok=True,
                                            usage={"input_tokens": 0, "output_tokens": 0, "seconds": 2.0}))
    _press_streaming(ctrl, engine)
    _release_held(ctrl)

    mod.transcribe.assert_called_once()
    mod.paste.assert_called_once_with("Hello world.", submit=False)
    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "caption_unavailable" for e in events)


def test_cleanup_failure_after_streamed_pastes_nothing(ctrl):
    import mini_whisper.controller as mod
    mod.clean.side_effect = RuntimeError("network unreachable")
    engine = FakeEngine()
    _press_streaming(ctrl, engine)
    _release_held(ctrl)

    mod.paste.assert_not_called()
    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "error" for e in events)


def test_gated_recording_discards_stream_and_records_seconds(ctrl):
    import mini_whisper.controller as mod
    ctrl.recorder.duration_seconds.return_value = 0.1  # below MIN_RECORDING_SECONDS
    engine = FakeEngine()
    _press_streaming(ctrl, engine)
    _release_held(ctrl)

    assert engine.finish_timeout == 0.5
    mod.transcribe.assert_not_called()
    mod.paste.assert_not_called()
    usage_call = mod.config.add_usage.call_args.args[0]
    assert usage_call["streamed_seconds"] == {"fake": 3.0}
    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "idle" for e in events)


def test_stale_generation_discards_streamed_result(ctrl):
    import mini_whisper.controller as mod
    engine = FakeEngine()
    sink = mod._StreamSink(ctrl.ui_queue)
    ctrl._generation = 2
    ctrl._process(_fake_audio(), submit=False, generation=1, engine=engine, sink=sink)

    assert engine.finish_timeout is not None  # engine was finished, result discarded
    mod.paste.assert_not_called()
    events = _drain(ctrl.ui_queue)
    assert any(e.kind == "idle" for e in events)
    assert not any(e.kind == "result" for e in events)


def test_toggle_mode_streams_identically(ctrl):
    import mini_whisper.controller as mod
    engine = FakeEngine()
    _press_streaming(ctrl, engine)
    ctrl.on_hotkey_release("paste")  # quick tap → toggle armed
    assert ctrl._toggle_active

    ctrl.on_hotkey_press("paste")  # second tap → stop
    if ctrl._worker is not None:
        ctrl._worker.join(timeout=5)

    mod.transcribe.assert_not_called()
    mod.paste.assert_called_once_with("Hello world.", submit=False)


def test_abort_stream_finishes_and_discards(ctrl):
    import mini_whisper.controller as mod
    engine = FakeEngine()
    _press_streaming(ctrl, engine)
    ctrl.abort_stream()

    assert engine.finish_timeout == 0.5
    ctrl.recorder.set_buffer_listener.assert_called_with(None)
    mod.paste.assert_not_called()
    events = _drain(ctrl.ui_queue)
    assert not any(e.kind == "result" for e in events)


def test_usage_recorded_with_cost(ctrl, monkeypatch):
    import mini_whisper.controller as mod
    cost_mock = MagicMock(return_value=0.42)
    monkeypatch.setattr("mini_whisper.controller.pricing.dictation_cost", cost_mock)
    engine = FakeEngine()
    _press_streaming(ctrl, engine)
    _release_held(ctrl)

    cost_mock.assert_called_once_with(
        "fake", 3.0, {"gpt-4o-mini": {"input_tokens": 5, "output_tokens": 8}}, None
    )
    usage_call = mod.config.add_usage.call_args.args[0]
    assert usage_call["cost_usd"] == 0.42
    assert usage_call["streamed_seconds"] == {"fake": 3.0}
    assert usage_call["input_tokens"] == 5
    assert usage_call["output_tokens"] == 8


def test_usage_event_carries_formatted_rows(ctrl, monkeypatch):
    """Stage 10: the usage event carries the two pre-formatted menu rows."""
    monkeypatch.setattr(
        "mini_whisper.controller.config.usage_totals",
        MagicMock(return_value={
            "today": {"input_tokens": 1200, "output_tokens": 3400,
                      "streamed_seconds": {"on_device": 720}, "cost_usd": 0.08},
            "month_cost_usd": 1.42,
        }),
    )
    ctrl._generation = 1
    ctrl._process(_fake_audio(), submit=False, generation=1)

    usage_events = [e for e in _drain(ctrl.ui_queue) if e.kind == "usage"]
    assert len(usage_events) == 1
    assert usage_events[0].text == "Today: 1.2k/3.4k tok · 12m · $0.08"
    assert usage_events[0].text2 == "Month: $1.42"


def test_permission_denied_pointer_once_per_run(ctrl):
    import mini_whisper.controller as mod
    mod.make_engine.return_value = (None, "permission_denied")
    ctrl.on_hotkey_press("paste")
    ctrl.on_hotkey_press("paste")

    events = _drain(ctrl.ui_queue)
    pointers = [e for e in events if e.kind == "error" and "Speech" in e.text]
    assert len(pointers) == 1

"""Tests for Recorder.set_buffer_listener (AVFoundation stubbed, no real tap)."""

from unittest.mock import MagicMock

import numpy as np
import pytest


@pytest.fixture()
def recorder(monkeypatch):
    """Recorder with AVFoundation mocked out and _tap_block drivable directly."""
    import mini_whisper.recorder as rec_mod

    monkeypatch.setattr(rec_mod, "AVFoundation", MagicMock())
    monkeypatch.setattr(
        rec_mod, "_buffer_to_numpy", lambda buf: np.full(160, 0.1, dtype=np.float32)
    )
    rec = rec_mod.Recorder()
    rec._recording = True
    return rec


def test_listener_called_with_buffer_after_append(recorder):
    seen = []
    recorder.set_buffer_listener(lambda buf: seen.append((buf, len(recorder._frames))))

    marker = object()
    recorder._tap_block(marker, None)

    # Listener received the raw tap buffer, after the frame was appended.
    assert seen == [(marker, 1)]


def test_raising_listener_is_swallowed_and_accumulation_unaffected(recorder):
    def bad_listener(buf):
        raise RuntimeError("engine blew up")

    recorder.set_buffer_listener(bad_listener)
    recorder._tap_block(object(), None)
    recorder._tap_block(object(), None)

    assert len(recorder._frames) == 2
    assert recorder._rms_count == 2


def test_set_buffer_listener_none_clears(recorder):
    calls = []
    recorder.set_buffer_listener(calls.append)
    recorder._tap_block(object(), None)

    recorder.set_buffer_listener(None)
    recorder._tap_block(object(), None)

    assert len(calls) == 1
    assert len(recorder._frames) == 2


def test_listener_not_called_when_not_recording(recorder):
    calls = []
    recorder.set_buffer_listener(calls.append)
    recorder._recording = False

    recorder._tap_block(object(), None)

    assert calls == []
    assert recorder._frames == []

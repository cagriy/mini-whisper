"""Tests for mini_whisper/streaming/factory.py (selection/gate matrix)."""

import pytest

from mini_whisper.streaming.factory import make_engine
from mini_whisper.streaming.on_device import OnDeviceEngine
from mini_whisper.streaming.websocket_engine import (
    ElevenLabsEngine,
    OpenAIRealtimeEngine,
    SpeechmaticsEngine,
)

from .test_on_device import FakeSpeechAPI

KEYS = {"openai": "sk-openai", "elevenlabs": "el-key", "speechmatics": "sm-key"}
NO_KEYS = {"openai": None, "elevenlabs": None, "speechmatics": None}

CLOUD_ENGINES = [
    ("openai", OpenAIRealtimeEngine),
    ("elevenlabs", ElevenLabsEngine),
    ("speechmatics", SpeechmaticsEngine),
]


def _cfg(enabled=True, engine="on_device"):
    return {"streaming_enabled": enabled, "streaming_engine": engine}


@pytest.fixture()
def speech_api(monkeypatch):
    """Route all _SpeechAPI construction (factory + engine) to one fake."""
    api = FakeSpeechAPI(status=3)
    monkeypatch.setattr(
        "mini_whisper.streaming.on_device._SpeechAPI", lambda: api
    )
    return api


# ---------------------------------------------------------------------------
# streaming toggle
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("engine_name", ["on_device", "openai", "elevenlabs", "speechmatics"])
def test_disabled_returns_none_for_every_engine(engine_name, speech_api):
    assert make_engine(_cfg(enabled=False, engine=engine_name), KEYS) == (None, "disabled")


# ---------------------------------------------------------------------------
# on-device: Speech authorization gate
# ---------------------------------------------------------------------------

def test_on_device_authorized_returns_engine(speech_api):
    engine, reason = make_engine(_cfg(engine="on_device"), NO_KEYS)
    assert isinstance(engine, OnDeviceEngine)
    assert reason is None


def test_on_device_denied_returns_none(speech_api):
    speech_api.status = 1
    assert make_engine(_cfg(engine="on_device"), KEYS) == (None, "permission_denied")
    assert speech_api.request_auth_calls == 0


def test_on_device_undetermined_requests_authorization_once(speech_api):
    speech_api.status = 0
    assert make_engine(_cfg(engine="on_device"), KEYS) == (None, "permission_undetermined")
    assert speech_api.request_auth_calls == 1


# ---------------------------------------------------------------------------
# cloud engines: key gate
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("engine_name,engine_cls", CLOUD_ENGINES)
def test_cloud_engine_with_key(engine_name, engine_cls):
    engine, reason = make_engine(_cfg(engine=engine_name), KEYS)
    assert isinstance(engine, engine_cls)
    assert reason is None
    assert engine._api_key == KEYS[engine_name]


@pytest.mark.parametrize("engine_name,engine_cls", CLOUD_ENGINES)
def test_cloud_engine_without_key(engine_name, engine_cls):
    assert make_engine(_cfg(engine=engine_name), NO_KEYS) == (None, "no_key")


def test_openai_uses_existing_openai_key():
    engine, _ = make_engine(_cfg(engine="openai"), {"openai": "sk-batch-key"})
    assert engine._api_key == "sk-batch-key"


# ---------------------------------------------------------------------------
# defensive: unknown engine name in config
# ---------------------------------------------------------------------------

def test_unknown_engine_returns_none():
    assert make_engine(_cfg(engine="bogus"), KEYS) == (None, "unknown_engine")

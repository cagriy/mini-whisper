"""Tests for mini_whisper/transcriber.py."""

import io

import httpx
import pytest

import mini_whisper.transcriber as transcriber_module
from mini_whisper.transcriber import transcribe
from tests.conftest import make_httpx_response


def _fake_audio(content: bytes = b"RIFF....fake wav data") -> io.BytesIO:
    buf = io.BytesIO(content)
    buf.name = "audio.wav"
    return buf


def test_transcribe_success(monkeypatch):
    response = make_httpx_response(200, {
        "text": "hello world",
        "usage": {"input_tokens": 42, "output_tokens": 7},
    })
    monkeypatch.setattr(transcriber_module._client, "post", lambda *a, **kw: response)

    text, usage = transcribe(_fake_audio(), "sk-key")
    assert text == "hello world"
    assert usage == {"input_tokens": 42, "output_tokens": 7}


def test_transcribe_empty_buffer_raises():
    with pytest.raises(ValueError, match="empty"):
        transcribe(io.BytesIO(b""), "sk-key")


def test_transcribe_with_instructions(monkeypatch):
    captured = {}

    def fake_post(url, **kwargs):
        captured["data"] = kwargs.get("data", {})
        return make_httpx_response(200, {"text": "hi", "usage": {}})

    monkeypatch.setattr(transcriber_module._client, "post", fake_post)
    transcribe(_fake_audio(), "sk-key", instructions="Be precise.")
    assert captured["data"].get("instructions") == "Be precise."


def test_transcribe_no_instructions_omitted(monkeypatch):
    captured = {}

    def fake_post(url, **kwargs):
        captured["data"] = kwargs.get("data", {})
        return make_httpx_response(200, {"text": "hi", "usage": {}})

    monkeypatch.setattr(transcriber_module._client, "post", fake_post)
    transcribe(_fake_audio(), "sk-key")
    assert "instructions" not in captured["data"]


def test_transcribe_http_error(monkeypatch):
    request = httpx.Request("POST", transcriber_module.TRANSCRIPTIONS_URL)
    error_response = httpx.Response(401, request=request)

    def fake_post(*a, **kw):
        raise httpx.HTTPStatusError("401", request=request, response=error_response)

    monkeypatch.setattr(transcriber_module._client, "post", fake_post)
    with pytest.raises(httpx.HTTPStatusError):
        transcribe(_fake_audio(), "sk-bad-key")


def test_transcribe_missing_usage_returns_zeros(monkeypatch):
    response = make_httpx_response(200, {"text": "hello"})
    monkeypatch.setattr(transcriber_module._client, "post", lambda *a, **kw: response)

    _, usage = transcribe(_fake_audio(), "sk-key")
    assert usage == {"input_tokens": 0, "output_tokens": 0}

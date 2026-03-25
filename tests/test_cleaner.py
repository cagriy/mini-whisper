"""Tests for mini_whisper/cleaner.py."""

import httpx
import pytest

import mini_whisper.cleaner as cleaner_module
from mini_whisper.cleaner import clean
from tests.conftest import make_httpx_response


def _chat_response(content: str, prompt_tokens: int = 10, completion_tokens: int = 5) -> httpx.Response:
    return make_httpx_response(200, {
        "choices": [{"message": {"content": content}}],
        "usage": {"prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens},
    })


def test_clean_success(monkeypatch):
    monkeypatch.setattr(cleaner_module._client, "post", lambda *a, **kw: _chat_response("Cleaned text."))
    text, usage = clean("raw transcript", "sk-key", "Fix grammar.")
    assert text == "Cleaned text."
    assert usage == {"input_tokens": 10, "output_tokens": 5}


def test_clean_strips_whitespace(monkeypatch):
    monkeypatch.setattr(cleaner_module._client, "post", lambda *a, **kw: _chat_response("  trimmed  "))
    text, _ = clean("input", "sk-key", "prompt")
    assert text == "trimmed"


def test_clean_http_error(monkeypatch):
    request = httpx.Request("POST", cleaner_module.CHAT_URL)
    error_response = httpx.Response(500, request=request)

    def fake_post(*a, **kw):
        raise httpx.HTTPStatusError("500", request=request, response=error_response)

    monkeypatch.setattr(cleaner_module._client, "post", fake_post)
    with pytest.raises(httpx.HTTPStatusError):
        clean("text", "sk-key", "prompt")


def test_clean_missing_usage_returns_zeros(monkeypatch):
    response = make_httpx_response(200, {
        "choices": [{"message": {"content": "ok"}}],
    })
    monkeypatch.setattr(cleaner_module._client, "post", lambda *a, **kw: response)
    _, usage = clean("text", "sk-key", "prompt")
    assert usage == {"input_tokens": 0, "output_tokens": 0}


def test_clean_sends_system_prompt(monkeypatch):
    captured = {}

    def fake_post(url, **kwargs):
        captured["json"] = kwargs.get("json", {})
        return _chat_response("ok")

    monkeypatch.setattr(cleaner_module._client, "post", fake_post)
    clean("raw", "sk-key", "My system prompt.")
    messages = captured["json"]["messages"]
    assert messages[0]["role"] == "system"
    assert messages[0]["content"] == "My system prompt."
    assert messages[1]["role"] == "user"
    assert messages[1]["content"] == "raw"

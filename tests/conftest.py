"""Shared fixtures for the mini-whisper test suite."""

import pytest
import httpx

import mini_whisper.config as config_module


@pytest.fixture()
def tmp_config_dir(tmp_path, monkeypatch):
    """Redirect all config path constants to a temp directory."""
    cfg_dir = tmp_path / "mini-whisper"
    cfg_dir.mkdir()

    monkeypatch.setattr(config_module, "CONFIG_DIR", cfg_dir)
    monkeypatch.setattr(config_module, "CONFIG_FILE", cfg_dir / "config.json")
    monkeypatch.setattr(config_module, "PROMPT_FILE", cfg_dir / "prompt.txt")
    monkeypatch.setattr(config_module, "TRANSCRIBE_PROMPT_FILE", cfg_dir / "transcribe_prompt.txt")

    yield cfg_dir


def make_httpx_response(status_code: int, json_body: dict) -> httpx.Response:
    """Build a real httpx.Response with the given status and JSON body."""
    request = httpx.Request("POST", "https://api.openai.com/test")
    return httpx.Response(status_code, json=json_body, request=request)


class FakeSink:
    """Recording TranscriptSink for streaming-engine tests."""

    def __init__(self):
        self.partials: list[str] = []
        self.finals: list[str] = []
        self.errors: list[Exception] = []

    def on_partial(self, text):
        self.partials.append(text)

    def on_final(self, text):
        self.finals.append(text)

    def on_engine_error(self, exc):
        self.errors.append(exc)

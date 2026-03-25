"""Tests for mini_whisper/config.py."""

import json
import threading
from datetime import date, timedelta
from unittest.mock import MagicMock

import pytest

import mini_whisper.config as config_module
from mini_whisper.config import (
    DEFAULT_CONFIG,
    add_daily_usage,
    get_api_key,
    get_prompt,
    load,
    save,
)


def test_load_creates_defaults(tmp_config_dir):
    result = load()
    assert result == DEFAULT_CONFIG
    assert config_module.CONFIG_FILE.exists()


def test_save_and_load_roundtrip(tmp_config_dir):
    cfg = {**DEFAULT_CONFIG, "cleanup_enabled": False, "sound_volume": 0.5}
    save(cfg)
    assert load() == cfg


def test_load_corrupt_json_backs_up(tmp_config_dir):
    config_module.CONFIG_FILE.write_text("not valid json{{{", encoding="utf-8")
    result = load()
    assert result == DEFAULT_CONFIG
    bak = config_module.CONFIG_FILE.with_suffix(".json.bak")
    assert bak.exists()
    assert bak.read_text() == "not valid json{{{"


def test_load_missing_file_creates_defaults(tmp_config_dir):
    assert not config_module.CONFIG_FILE.exists()
    result = load()
    assert result == DEFAULT_CONFIG
    assert config_module.CONFIG_FILE.exists()


def test_add_daily_usage_accumulates(tmp_config_dir):
    totals = add_daily_usage(10, 5)
    assert totals == {"input_tokens": 10, "output_tokens": 5}
    totals = add_daily_usage(3, 2)
    assert totals == {"input_tokens": 13, "output_tokens": 7}


def test_add_daily_usage_prunes_old_dates(tmp_config_dir):
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    cfg = {**DEFAULT_CONFIG, "daily_usage": {yesterday: {"input_tokens": 99, "output_tokens": 99}}}
    save(cfg)
    totals = add_daily_usage(1, 1)
    # Today's usage starts fresh (yesterday's is pruned)
    assert totals == {"input_tokens": 1, "output_tokens": 1}
    saved = load()
    assert yesterday not in saved.get("daily_usage", {})


def test_add_daily_usage_thread_safety(tmp_config_dir):
    n = 20
    threads = [threading.Thread(target=add_daily_usage, args=(1, 1)) for _ in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    totals = add_daily_usage(0, 0)
    assert totals["input_tokens"] == n
    assert totals["output_tokens"] == n


def test_get_prompt_returns_bundled_default(tmp_config_dir):
    text = get_prompt()
    assert isinstance(text, str)
    assert len(text) > 0


def test_get_api_key_returns_value(monkeypatch):
    monkeypatch.setattr("mini_whisper.config.keyring.get_password", MagicMock(return_value="sk-test-key"))
    assert get_api_key() == "sk-test-key"


def test_get_api_key_returns_none_when_missing(monkeypatch):
    monkeypatch.setattr("mini_whisper.config.keyring.get_password", MagicMock(return_value=None))
    assert get_api_key() is None

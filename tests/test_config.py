"""Tests for mini_whisper/config.py."""

import json
import threading
from datetime import date, timedelta
from unittest.mock import MagicMock

import pytest

import mini_whisper.config as config_module
from mini_whisper.config import (
    DEFAULT_CONFIG,
    add_usage,
    get_api_key,
    get_prompt,
    get_streaming_api_key,
    load,
    save,
    set_streaming_api_key,
    usage_totals,
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


def test_default_config_streaming_keys():
    assert DEFAULT_CONFIG["streaming_enabled"] is True
    assert DEFAULT_CONFIG["streaming_engine"] == "on_device"
    assert DEFAULT_CONFIG["pricing_overrides"] == {}


def test_add_usage_accumulates(tmp_config_dir):
    entry = add_usage({"input_tokens": 10, "output_tokens": 5,
                       "streamed_seconds": {"on_device": 30.0}, "cost_usd": 0.02})
    assert entry == {"input_tokens": 10, "output_tokens": 5,
                     "streamed_seconds": {"on_device": 30.0}, "cost_usd": 0.02}
    entry = add_usage({"input_tokens": 3, "output_tokens": 2,
                       "streamed_seconds": {"on_device": 10.0, "elevenlabs": 5.0},
                       "cost_usd": 0.01})
    assert entry["input_tokens"] == 13
    assert entry["output_tokens"] == 7
    assert entry["streamed_seconds"] == {"on_device": 40.0, "elevenlabs": 5.0}
    assert entry["cost_usd"] == pytest.approx(0.03)


def test_add_usage_defaults_missing_fields(tmp_config_dir):
    entry = add_usage({"input_tokens": 4, "output_tokens": 6})
    assert entry == {"input_tokens": 4, "output_tokens": 6,
                     "streamed_seconds": {}, "cost_usd": 0.0}


def _fixed_today(monkeypatch, fixed: date):
    class _FixedDate:
        @staticmethod
        def today():
            return fixed
    monkeypatch.setattr(config_module, "date", _FixedDate)


def test_add_usage_prunes_previous_month_keeps_current(tmp_config_dir, monkeypatch):
    _fixed_today(monkeypatch, date(2026, 9, 15))
    earlier_this_month = {"input_tokens": 5, "output_tokens": 5,
                          "streamed_seconds": {}, "cost_usd": 0.10}
    last_month = {"input_tokens": 99, "output_tokens": 99,
                  "streamed_seconds": {}, "cost_usd": 9.99}
    save({**DEFAULT_CONFIG, "usage": {"2026-09-10": earlier_this_month,
                                      "2026-08-31": last_month}})
    add_usage({"input_tokens": 1, "output_tokens": 1})
    saved = load()
    assert "2026-08-31" not in saved["usage"]
    assert saved["usage"]["2026-09-10"] == earlier_this_month
    assert saved["usage"]["2026-09-15"]["input_tokens"] == 1


def test_load_migrates_daily_usage(tmp_config_dir):
    today = date.today().isoformat()
    cfg = {**DEFAULT_CONFIG, "daily_usage": {today: {"input_tokens": 7, "output_tokens": 9}}}
    save(cfg)
    loaded = load()
    assert "daily_usage" not in loaded
    assert loaded["usage"][today] == {"input_tokens": 7, "output_tokens": 9,
                                      "streamed_seconds": {}, "cost_usd": 0.0}
    # Migration is persisted, not just in-memory
    on_disk = json.loads(config_module.CONFIG_FILE.read_text(encoding="utf-8"))
    assert "daily_usage" not in on_disk
    assert on_disk["usage"][today]["input_tokens"] == 7


def test_load_migration_drops_stale_daily_usage(tmp_config_dir):
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    save({**DEFAULT_CONFIG, "daily_usage": {yesterday: {"input_tokens": 99, "output_tokens": 99}}})
    loaded = load()
    assert "daily_usage" not in loaded
    assert loaded.get("usage", {}) == {}


def test_usage_totals(tmp_config_dir, monkeypatch):
    _fixed_today(monkeypatch, date(2026, 9, 15))
    save({**DEFAULT_CONFIG, "usage": {
        "2026-09-10": {"input_tokens": 5, "output_tokens": 5,
                       "streamed_seconds": {}, "cost_usd": 0.10},
        "2026-09-15": {"input_tokens": 20, "output_tokens": 30,
                       "streamed_seconds": {"on_device": 60.0}, "cost_usd": 0.05},
    }})
    totals = usage_totals()
    assert totals["today"] == {"input_tokens": 20, "output_tokens": 30,
                               "streamed_seconds": {"on_device": 60.0}, "cost_usd": 0.05}
    assert totals["month_cost_usd"] == pytest.approx(0.15)


def test_usage_totals_empty(tmp_config_dir):
    totals = usage_totals()
    assert totals["today"] == {"input_tokens": 0, "output_tokens": 0,
                               "streamed_seconds": {}, "cost_usd": 0.0}
    assert totals["month_cost_usd"] == 0.0


def test_add_usage_thread_safety(tmp_config_dir):
    n = 20
    threads = [threading.Thread(target=add_usage,
                                args=({"input_tokens": 1, "output_tokens": 1},))
               for _ in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    entry = add_usage({"input_tokens": 0, "output_tokens": 0})
    assert entry["input_tokens"] == n
    assert entry["output_tokens"] == n


def test_streaming_api_key_roundtrip(monkeypatch):
    store = {}
    monkeypatch.setattr("mini_whisper.config.keyring.set_password",
                        lambda svc, user, key: store.__setitem__((svc, user), key))
    monkeypatch.setattr("mini_whisper.config.keyring.get_password",
                        lambda svc, user: store.get((svc, user)))
    set_streaming_api_key("elevenlabs", "el-key")
    set_streaming_api_key("speechmatics", "sm-key")
    assert store[("mini-whisper", "elevenlabs-api-key")] == "el-key"
    assert store[("mini-whisper", "speechmatics-api-key")] == "sm-key"
    assert get_streaming_api_key("elevenlabs") == "el-key"
    assert get_streaming_api_key("speechmatics") == "sm-key"


def test_streaming_api_key_unknown_engine(monkeypatch):
    monkeypatch.setattr("mini_whisper.config.keyring.get_password", MagicMock())
    with pytest.raises(KeyError):
        get_streaming_api_key("openai")


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

"""Configuration management for Mini Whisper.

Settings stored in ~/.config/mini-whisper/:
- config.json: hotkey, cleanup toggle
- prompt.txt: LLM cleanup prompt (editable by user)
- transcribe_prompt.txt: transcription instructions (editable by user)
- API key: macOS Keychain via keyring (never on disk)
"""

import json
import logging
import shutil
import threading
from datetime import date
from pathlib import Path

import keyring

logger = logging.getLogger(__name__)

CONFIG_DIR = Path.home() / ".config" / "mini-whisper"
CONFIG_FILE = CONFIG_DIR / "config.json"
PROMPT_FILE = CONFIG_DIR / "prompt.txt"
TRANSCRIBE_PROMPT_FILE = CONFIG_DIR / "transcribe_prompt.txt"
BUNDLED_PROMPT = Path(__file__).parent / "resources" / "default_prompt.txt"
BUNDLED_TRANSCRIBE_PROMPT = Path(__file__).parent / "resources" / "default_transcribe_prompt.txt"

KEYRING_SERVICE = "mini-whisper"
KEYRING_USERNAME = "openai-api-key"
STREAMING_KEY_USERNAMES = {
    "elevenlabs": "elevenlabs-api-key",
    "speechmatics": "speechmatics-api-key",
}

_lock = threading.Lock()

DEFAULT_CONFIG = {
    "hotkey": "shift+cmd_r",
    "submit_hotkey": "cmd_r",
    "cleanup_enabled": True,
    "sound_volume": 1.0,
    "streaming_enabled": True,
    "streaming_engine": "on_device",
    "pricing_overrides": {},
}


def ensure_config_dir():
    """Create config directory and default files if they don't exist."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        save(DEFAULT_CONFIG)
    if not PROMPT_FILE.exists():
        shutil.copy(BUNDLED_PROMPT, PROMPT_FILE)
    if not TRANSCRIBE_PROMPT_FILE.exists():
        shutil.copy(BUNDLED_TRANSCRIBE_PROMPT, TRANSCRIBE_PROMPT_FILE)


def load() -> dict:
    """Load config from disk, creating defaults if needed."""
    ensure_config_dir()
    try:
        return _migrate_daily_usage(json.loads(CONFIG_FILE.read_text(encoding="utf-8")))
    except json.JSONDecodeError:
        # Back up the corrupt file before overwriting with defaults
        try:
            CONFIG_FILE.rename(CONFIG_FILE.with_suffix(".json.bak"))
        except OSError:
            pass
        logger.warning("config.json was corrupt; defaults restored (backup: config.json.bak)")
        save(DEFAULT_CONFIG)
        return DEFAULT_CONFIG.copy()
    except FileNotFoundError:
        save(DEFAULT_CONFIG)
        return DEFAULT_CONFIG.copy()


def save(config: dict):
    """Save config to disk."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def get_api_key() -> str | None:
    """Get OpenAI API key from macOS Keychain."""
    key = keyring.get_password(KEYRING_SERVICE, KEYRING_USERNAME)
    if key:
        logger.debug("API key loaded from Keychain")
    else:
        logger.debug("No API key found in Keychain")
    return key


def set_api_key(key: str):
    """Store OpenAI API key in macOS Keychain."""
    keyring.set_password(KEYRING_SERVICE, KEYRING_USERNAME, key)
    logger.info("API key saved to Keychain")


def get_streaming_api_key(engine: str) -> str | None:
    """Get a cloud streaming engine's API key from the macOS Keychain."""
    return keyring.get_password(KEYRING_SERVICE, STREAMING_KEY_USERNAMES[engine])


def set_streaming_api_key(engine: str, key: str):
    """Store a cloud streaming engine's API key in the macOS Keychain."""
    keyring.set_password(KEYRING_SERVICE, STREAMING_KEY_USERNAMES[engine], key)
    logger.info("%s API key saved to Keychain", engine)


def get_prompt() -> str:
    """Read the cleanup prompt, re-reading from disk each time."""
    ensure_config_dir()
    return PROMPT_FILE.read_text(encoding="utf-8").strip()


def get_transcribe_prompt() -> str:
    """Read the transcription instructions, re-reading from disk each time."""
    ensure_config_dir()
    return TRANSCRIBE_PROMPT_FILE.read_text(encoding="utf-8").strip()


def _new_day_entry() -> dict:
    return {"input_tokens": 0, "output_tokens": 0, "streamed_seconds": {}, "cost_usd": 0.0}


def _migrate_daily_usage(cfg: dict) -> dict:
    """One-shot migration of the legacy today-only `daily_usage` store into `usage`."""
    if "daily_usage" not in cfg:
        return cfg
    today = date.today().isoformat()
    old_today = cfg.pop("daily_usage").get(today)
    if old_today:
        entry = _new_day_entry()
        entry["input_tokens"] = int(old_today.get("input_tokens", 0))
        entry["output_tokens"] = int(old_today.get("output_tokens", 0))
        cfg.setdefault("usage", {})[today] = entry
    save(cfg)
    logger.info("Migrated daily_usage to usage store")
    return cfg


def add_usage(provider_usage: dict) -> dict:
    """Accumulate one dictation's provider-attributed usage into today's entry.

    provider_usage keys (all optional): input_tokens, output_tokens,
    streamed_seconds ({engine: seconds}), cost_usd. Entries outside the
    current calendar month are pruned on write. Returns today's entry.
    """
    with _lock:
        cfg = load()
        today = date.today().isoformat()
        usage = cfg.get("usage", {})
        entry = usage.get(today, _new_day_entry())
        entry["input_tokens"] += int(provider_usage.get("input_tokens", 0))
        entry["output_tokens"] += int(provider_usage.get("output_tokens", 0))
        entry["cost_usd"] += float(provider_usage.get("cost_usd", 0.0))
        seconds_by_engine = entry.setdefault("streamed_seconds", {})
        for engine, seconds in provider_usage.get("streamed_seconds", {}).items():
            seconds_by_engine[engine] = seconds_by_engine.get(engine, 0.0) + float(seconds)
        usage[today] = entry
        month = today[:7]
        cfg["usage"] = {day: e for day, e in usage.items() if day[:7] == month}
        save(cfg)
        return entry


def usage_totals() -> dict:
    """Return {"today": today's usage entry, "month_cost_usd": month-to-date cost}."""
    cfg = load()
    usage = cfg.get("usage", {})
    today = date.today().isoformat()
    month = today[:7]
    month_cost = sum(
        float(e.get("cost_usd", 0.0)) for day, e in usage.items() if day[:7] == month
    )
    return {"today": usage.get(today, _new_day_entry()), "month_cost_usd": month_cost}

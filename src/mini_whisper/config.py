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

DEFAULT_CONFIG = {
    "hotkey": "shift+cmd_r",
    "submit_hotkey": "cmd_r",
    "cleanup_enabled": True,
    "sound_volume": 1.0,
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
        return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, FileNotFoundError):
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
        masked = key[:3] + "..." + key[-4:] if len(key) > 7 else "***"
        logger.info("API key loaded from Keychain: %s", masked)
    else:
        logger.debug("No API key found in Keychain")
    return key


def set_api_key(key: str):
    """Store OpenAI API key in macOS Keychain."""
    keyring.set_password(KEYRING_SERVICE, KEYRING_USERNAME, key)
    logger.info("API key saved to Keychain")


def get_prompt() -> str:
    """Read the cleanup prompt, re-reading from disk each time."""
    ensure_config_dir()
    return PROMPT_FILE.read_text(encoding="utf-8").strip()


def get_transcribe_prompt() -> str:
    """Read the transcription instructions, re-reading from disk each time."""
    ensure_config_dir()
    return TRANSCRIBE_PROMPT_FILE.read_text(encoding="utf-8").strip()


def get_daily_usage() -> dict:
    """Return today's cumulative token usage from config."""
    cfg = load()
    today = date.today().isoformat()
    return cfg.get("daily_usage", {}).get(today, {"input_tokens": 0, "output_tokens": 0})


def add_daily_usage(input_tokens: int, output_tokens: int) -> dict:
    """Add tokens to today's usage, prune old dates, save, and return updated totals."""
    cfg = load()
    today = date.today().isoformat()
    today_usage = cfg.get("daily_usage", {}).get(today, {"input_tokens": 0, "output_tokens": 0})
    today_usage["input_tokens"] += input_tokens
    today_usage["output_tokens"] += output_tokens
    cfg["daily_usage"] = {today: today_usage}  # prune old dates
    save(cfg)
    return today_usage

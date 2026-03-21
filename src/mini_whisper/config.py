"""Configuration management for Mini Whisper.

Settings stored in ~/.config/mini-whisper/:
- config.json: hotkey, cleanup toggle
- prompt.txt: LLM cleanup prompt (editable by user)
- API key: macOS Keychain via keyring (never on disk)
"""

import json
import shutil
from pathlib import Path

import keyring

CONFIG_DIR = Path.home() / ".config" / "mini-whisper"
CONFIG_FILE = CONFIG_DIR / "config.json"
PROMPT_FILE = CONFIG_DIR / "prompt.txt"
BUNDLED_PROMPT = Path(__file__).parent / "resources" / "default_prompt.txt"

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
    return keyring.get_password(KEYRING_SERVICE, KEYRING_USERNAME)


def set_api_key(key: str):
    """Store OpenAI API key in macOS Keychain."""
    keyring.set_password(KEYRING_SERVICE, KEYRING_USERNAME, key)


def get_prompt() -> str:
    """Read the cleanup prompt, re-reading from disk each time."""
    ensure_config_dir()
    return PROMPT_FILE.read_text(encoding="utf-8").strip()

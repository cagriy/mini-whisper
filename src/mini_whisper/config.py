"""Configuration management for Mini Whisper.

Settings stored in ~/.config/mini-whisper/:
- config.json: hotkey, cleanup toggle
- prompt.txt: LLM cleanup prompt (editable by user)
- API key: macOS Keychain via legacy Keychain Services (prompts on signature change)
"""

import ctypes
import ctypes.util
import json
import shutil
from ctypes import byref, c_char_p, c_uint32, c_void_p
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "mini-whisper"
CONFIG_FILE = CONFIG_DIR / "config.json"
PROMPT_FILE = CONFIG_DIR / "prompt.txt"
BUNDLED_PROMPT = Path(__file__).parent / "resources" / "default_prompt.txt"

KEYCHAIN_SERVICE = "mini-whisper"
KEYCHAIN_ACCOUNT = "openai-api-key"

# Legacy Keychain Services API — uses login.keychain-db, prompts on signature change
_security = ctypes.CDLL(ctypes.util.find_library("Security"))

_security.SecKeychainAddGenericPassword.restype = ctypes.c_int32
_security.SecKeychainAddGenericPassword.argtypes = [
    c_void_p, c_uint32, c_char_p, c_uint32, c_char_p, c_uint32, c_char_p, c_void_p,
]

_security.SecKeychainFindGenericPassword.restype = ctypes.c_int32
_security.SecKeychainFindGenericPassword.argtypes = [
    c_void_p, c_uint32, c_char_p, c_uint32, c_char_p,
    ctypes.POINTER(c_uint32), ctypes.POINTER(c_void_p), c_void_p,
]

_security.SecKeychainItemModifyAttributesAndData.restype = ctypes.c_int32
_security.SecKeychainItemModifyAttributesAndData.argtypes = [
    c_void_p, c_void_p, c_uint32, c_char_p,
]

_security.SecKeychainItemFreeContent.restype = ctypes.c_int32
_security.SecKeychainItemFreeContent.argtypes = [c_void_p, c_void_p]

_ERR_ITEM_NOT_FOUND = -25300

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
    """Get OpenAI API key from macOS Keychain (legacy API, prompts on signature change)."""
    service = KEYCHAIN_SERVICE.encode("utf-8")
    account = KEYCHAIN_ACCOUNT.encode("utf-8")
    length = c_uint32(0)
    data = c_void_p(0)
    item_ref = c_void_p(0)

    status = _security.SecKeychainFindGenericPassword(
        None,
        len(service), service,
        len(account), account,
        byref(length), byref(data),
        byref(item_ref),
    )

    if status == _ERR_ITEM_NOT_FOUND:
        return None
    if status != 0:
        return None

    password = ctypes.string_at(data, length.value).decode("utf-8")
    _security.SecKeychainItemFreeContent(None, data)
    return password


def set_api_key(key: str):
    """Store OpenAI API key in macOS Keychain (legacy API, prompts on signature change)."""
    service = KEYCHAIN_SERVICE.encode("utf-8")
    account = KEYCHAIN_ACCOUNT.encode("utf-8")
    password = key.encode("utf-8")

    # Try to find existing item and update it
    length = c_uint32(0)
    data = c_void_p(0)
    item_ref = c_void_p(0)

    status = _security.SecKeychainFindGenericPassword(
        None,
        len(service), service,
        len(account), account,
        byref(length), byref(data),
        byref(item_ref),
    )

    if status == 0:
        # Update existing item
        _security.SecKeychainItemFreeContent(None, data)
        _security.SecKeychainItemModifyAttributesAndData(
            item_ref, None, len(password), password,
        )
    else:
        # Add new item
        _security.SecKeychainAddGenericPassword(
            None,
            len(service), service,
            len(account), account,
            len(password), password,
            None,
        )


def get_prompt() -> str:
    """Read the cleanup prompt, re-reading from disk each time."""
    ensure_config_dir()
    return PROMPT_FILE.read_text(encoding="utf-8").strip()

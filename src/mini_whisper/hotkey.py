"""Global hotkey listener using pynput.

Supports push-to-talk (hold to record, release to process) and
key capture mode for changing the hotkey from the menu.
"""

import threading
from typing import Callable

from pynput.keyboard import Key, KeyCode, Listener

# Map config string names to pynput keys
_MODIFIER_MAP = {
    "cmd": Key.cmd,
    "shift": Key.shift,
    "ctrl": Key.ctrl,
    "alt": Key.alt,
}

_KEY_MAP = {
    "space": Key.space,
    "tab": Key.tab,
    "enter": Key.enter,
}


def parse_hotkey(combo: str) -> tuple[set, Key | KeyCode]:
    """Parse a hotkey string like 'cmd+shift+space' into modifiers and key.

    Returns:
        Tuple of (modifier_keys_set, trigger_key).
    """
    parts = [p.strip().lower() for p in combo.split("+")]
    modifiers = set()
    trigger = None

    for part in parts:
        if part in _MODIFIER_MAP:
            modifiers.add(_MODIFIER_MAP[part])
        elif part in _KEY_MAP:
            trigger = _KEY_MAP[part]
        elif len(part) == 1:
            trigger = KeyCode.from_char(part)
        else:
            raise ValueError(f"Unknown key: {part}")

    if trigger is None:
        raise ValueError(f"No trigger key found in combo: {combo}")

    return modifiers, trigger


def format_hotkey(modifiers: set, trigger: Key | KeyCode) -> str:
    """Format a hotkey for display (e.g. '⌘⇧Space')."""
    symbols = {
        Key.cmd: "⌘",
        Key.shift: "⇧",
        Key.ctrl: "⌃",
        Key.alt: "⌥",
    }
    key_names = {
        Key.space: "Space",
        Key.tab: "Tab",
        Key.enter: "Enter",
    }

    parts = [symbols.get(m, str(m)) for m in sorted(modifiers, key=str)]
    if isinstance(trigger, Key):
        parts.append(key_names.get(trigger, trigger.name.title()))
    else:
        parts.append(trigger.char.upper() if trigger.char else str(trigger))
    return "".join(parts)


class HotkeyListener:
    def __init__(
        self,
        combo: str,
        on_press: Callable[[], None],
        on_release: Callable[[], None],
    ):
        self._modifiers, self._trigger = parse_hotkey(combo)
        self._on_press = on_press
        self._on_release = on_release
        self._pressed_modifiers: set = set()
        self._hotkey_active = False
        self._listener: Listener | None = None
        self._capture_callback: Callable | None = None
        self._capture_modifiers: set = set()

    def _on_key_press(self, key):
        # Key capture mode
        if self._capture_callback is not None:
            canonical = self._to_canonical(key)
            if canonical in _MODIFIER_MAP.values():
                self._capture_modifiers.add(canonical)
            else:
                # Non-modifier key pressed — capture complete
                cb = self._capture_callback
                mods = self._capture_modifiers.copy()
                self._capture_callback = None
                self._capture_modifiers = set()
                cb(mods, key)
            return

        # Normal hotkey detection
        canonical = self._to_canonical(key)
        if canonical in self._modifiers:
            self._pressed_modifiers.add(canonical)

        if (
            not self._hotkey_active
            and self._pressed_modifiers >= self._modifiers
            and canonical == self._trigger
        ):
            self._hotkey_active = True
            self._on_press()

    def _on_key_release(self, key):
        if self._capture_callback is not None:
            return

        canonical = self._to_canonical(key)

        # Release hotkey when trigger or any modifier is released
        if self._hotkey_active and (
            canonical == self._trigger or canonical in self._modifiers
        ):
            self._hotkey_active = False
            self._on_release()

        self._pressed_modifiers.discard(canonical)

    def _to_canonical(self, key) -> Key | KeyCode:
        """Normalize key variants (e.g. cmd_l/cmd_r → cmd)."""
        if isinstance(key, Key):
            name = key.name
            for base in ("cmd", "shift", "ctrl", "alt"):
                if name.startswith(base):
                    return _MODIFIER_MAP[base]
        return key

    def start(self):
        """Start the hotkey listener in a daemon thread."""
        self._listener = Listener(
            on_press=self._on_key_press,
            on_release=self._on_key_release,
        )
        self._listener.daemon = True
        self._listener.start()

    def stop(self):
        """Stop the listener."""
        if self._listener is not None:
            self._listener.stop()
            self._listener = None

    def update_hotkey(self, combo: str):
        """Change the hotkey combo."""
        self._modifiers, self._trigger = parse_hotkey(combo)
        self._hotkey_active = False
        self._pressed_modifiers.clear()

    def enter_capture_mode(self, callback: Callable[[set, Key | KeyCode], None]):
        """Enter key capture mode. Next key combo pressed will be passed to callback.

        Args:
            callback: Called with (modifiers_set, trigger_key) when a combo is captured.
        """
        self._capture_modifiers = set()
        self._capture_callback = callback

    def cancel_capture(self):
        """Cancel key capture mode."""
        self._capture_callback = None
        self._capture_modifiers = set()

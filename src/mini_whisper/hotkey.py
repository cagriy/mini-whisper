"""Global hotkey listener using pynput.

Supports push-to-talk (hold to record, release to process) and
key capture mode for changing the hotkey from the menu.
Multiple named bindings share a single pynput Listener.
"""

from dataclasses import dataclass, field
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

# Sided modifier keys that can serve as trigger keys
_MODIFIER_TRIGGER_MAP = {
    "cmd_r": Key.cmd_r,
    "shift_r": Key.shift_r,
    "ctrl_r": Key.ctrl_r,
    "alt_r": Key.alt_r,
}

# Canonical forms for modifier triggers (for pressed_modifiers matching)
_TRIGGER_TO_CANONICAL = {
    Key.cmd_r: Key.cmd,
    Key.shift_r: Key.shift,
    Key.ctrl_r: Key.ctrl,
    Key.alt_r: Key.alt,
}


def parse_hotkey(combo: str) -> tuple[set, Key | KeyCode, bool]:
    """Parse a hotkey string like 'cmd+shift+space' or 'shift+cmd_r'.

    Returns:
        Tuple of (modifier_keys_set, trigger_key, is_modifier_trigger).
        For modifier triggers like 'cmd_r', is_modifier_trigger is True
        and the trigger is the raw Key (e.g. Key.cmd_r).
    """
    parts = [p.strip().lower() for p in combo.split("+")]
    modifiers = set()
    trigger = None
    is_modifier_trigger = False

    for part in parts:
        if part in _MODIFIER_TRIGGER_MAP:
            if trigger is not None:
                raise ValueError(f"Multiple trigger keys in combo: {combo}")
            trigger = _MODIFIER_TRIGGER_MAP[part]
            is_modifier_trigger = True
        elif part in _MODIFIER_MAP:
            modifiers.add(_MODIFIER_MAP[part])
        elif part in _KEY_MAP:
            trigger = _KEY_MAP[part]
        elif len(part) == 1:
            trigger = KeyCode.from_char(part)
        else:
            raise ValueError(f"Unknown key: {part}")

    if trigger is None:
        raise ValueError(f"No trigger key found in combo: {combo}")

    return modifiers, trigger, is_modifier_trigger


def format_hotkey(modifiers: set, trigger: Key | KeyCode) -> str:
    """Format a hotkey for display (e.g. '⌘⇧Space' or '⇧Right ⌘')."""
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
    modifier_trigger_names = {
        Key.cmd_r: "Right ⌘",
        Key.shift_r: "Right ⇧",
        Key.ctrl_r: "Right ⌃",
        Key.alt_r: "Right ⌥",
    }

    parts = [symbols.get(m, str(m)) for m in sorted(modifiers, key=str)]
    if trigger in modifier_trigger_names:
        parts.append(modifier_trigger_names[trigger])
    elif isinstance(trigger, Key):
        parts.append(key_names.get(trigger, trigger.name.title()))
    else:
        parts.append(trigger.char.upper() if trigger.char else str(trigger))
    return "".join(parts)


@dataclass
class _HotkeyBinding:
    """State for a single named hotkey binding."""

    modifiers: set
    trigger: Key | KeyCode
    on_press: Callable[[], None]
    on_release: Callable[[], None]
    is_modifier_trigger: bool = False
    trigger_canonical: Key | None = None
    active: bool = field(default=False, init=False)


class HotkeyListener:
    def __init__(self):
        self._bindings: dict[str, _HotkeyBinding] = {}
        self._pressed_modifiers: set = set()
        self._listener: Listener | None = None
        self._capture_callback: Callable | None = None
        self._capture_modifiers: set = set()
        self._capture_non_modifier_pressed: bool = False

    def register(
        self,
        name: str,
        combo: str,
        on_press: Callable[[], None],
        on_release: Callable[[], None],
    ):
        """Register a named hotkey binding.

        Args:
            name: Unique name for this binding (e.g. "paste", "paste_submit").
            combo: Hotkey string like 'cmd+shift+space'.
            on_press: Called when the hotkey is pressed.
            on_release: Called when the hotkey is released.
        """
        modifiers, trigger, is_modifier_trigger = parse_hotkey(combo)
        trigger_canonical = (
            _TRIGGER_TO_CANONICAL.get(trigger) if is_modifier_trigger else None
        )
        self._bindings[name] = _HotkeyBinding(
            modifiers=modifiers,
            trigger=trigger,
            on_press=on_press,
            on_release=on_release,
            is_modifier_trigger=is_modifier_trigger,
            trigger_canonical=trigger_canonical,
        )

    def _on_key_press(self, key):
        # Key capture mode
        if self._capture_callback is not None:
            self._handle_capture_press(key)
            return

        # Normal hotkey detection
        canonical = self._to_canonical(key)
        if canonical in _MODIFIER_MAP.values():
            self._pressed_modifiers.add(canonical)

        for binding in self._bindings.values():
            if binding.active:
                continue

            if binding.is_modifier_trigger:
                # Modifier-as-trigger: exact modifier set match + raw key match
                if (
                    key == binding.trigger
                    and self._pressed_modifiers
                    == binding.modifiers | {binding.trigger_canonical}
                ):
                    binding.active = True
                    binding.on_press()
            else:
                # Regular binding: superset match + canonical trigger match
                if (
                    self._pressed_modifiers >= binding.modifiers
                    and canonical == binding.trigger
                ):
                    binding.active = True
                    binding.on_press()

    def _on_key_release(self, key):
        if self._capture_callback is not None:
            self._handle_capture_release(key)
            return

        canonical = self._to_canonical(key)

        for binding in self._bindings.values():
            if not binding.active:
                continue

            if binding.is_modifier_trigger:
                # Deactivate when the raw trigger modifier or a required modifier is released
                if key == binding.trigger or canonical in binding.modifiers:
                    binding.active = False
                    binding.on_release()
            else:
                if canonical == binding.trigger or canonical in binding.modifiers:
                    binding.active = False
                    binding.on_release()

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

    def update_hotkey(self, name: str, combo: str):
        """Change the hotkey combo for a named binding."""
        binding = self._bindings.get(name)
        if binding is None:
            raise KeyError(f"No binding named '{name}'")
        modifiers, trigger, is_modifier_trigger = parse_hotkey(combo)
        binding.modifiers = modifiers
        binding.trigger = trigger
        binding.is_modifier_trigger = is_modifier_trigger
        binding.trigger_canonical = (
            _TRIGGER_TO_CANONICAL.get(trigger) if is_modifier_trigger else None
        )
        binding.active = False
        self._pressed_modifiers.clear()

    def _handle_capture_press(self, key):
        """Handle a key press during capture mode."""
        canonical = self._to_canonical(key)
        if canonical in _MODIFIER_MAP.values():
            self._capture_modifiers.add(canonical)
        else:
            # Non-modifier key pressed — capture complete (existing behavior)
            self._capture_non_modifier_pressed = True
            cb = self._capture_callback
            mods = self._capture_modifiers.copy()
            self._capture_callback = None
            self._capture_modifiers = set()
            self._capture_non_modifier_pressed = False
            cb(mods, key)

    def _handle_capture_release(self, key):
        """Handle a key release during capture mode.

        If a modifier is released without any non-modifier key having been
        pressed, treat the released modifier as the trigger and remaining
        held modifiers as the modifier set (modifier-as-trigger capture).
        """
        if self._capture_non_modifier_pressed:
            return

        canonical = self._to_canonical(key)
        if canonical not in _MODIFIER_MAP.values():
            return

        if not self._capture_modifiers:
            return

        # The released modifier becomes the trigger; others are the modifier set
        remaining_mods = self._capture_modifiers - {canonical}
        cb = self._capture_callback
        self._capture_callback = None
        self._capture_modifiers = set()
        self._capture_non_modifier_pressed = False
        cb(remaining_mods, key)

    def enter_capture_mode(self, callback: Callable[[set, Key | KeyCode], None]):
        """Enter key capture mode. Next key combo pressed will be passed to callback.

        Args:
            callback: Called with (modifiers_set, trigger_key) when a combo is captured.
        """
        self._capture_modifiers = set()
        self._capture_non_modifier_pressed = False
        self._capture_callback = callback

    def cancel_capture(self):
        """Cancel key capture mode."""
        self._capture_callback = None
        self._capture_modifiers = set()
        self._capture_non_modifier_pressed = False

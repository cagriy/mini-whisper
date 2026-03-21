"""Global hotkey listener using pynput.

Supports push-to-talk (hold to record, release to process) and
key capture mode for changing the hotkey from the menu.
Multiple named bindings share a single pynput Listener.
"""

import logging
import threading
from dataclasses import dataclass, field
from typing import Callable

from pynput.keyboard import Key, KeyCode, Listener
from Quartz import CGEventSourceFlagsState, kCGEventSourceStateCombinedSessionState

logger = logging.getLogger(__name__)

# macOS virtual key code <-> character mappings for reliable KeyCode matching.
# Stable across all macOS versions (unchanged since Carbon API).
_VK_TO_CHAR: dict[int, str] = {
    0: 'a', 1: 's', 2: 'd', 3: 'f', 4: 'h', 5: 'g', 6: 'z', 7: 'x',
    8: 'c', 9: 'v', 11: 'b', 12: 'q', 13: 'w', 14: 'e', 15: 'r',
    16: 'y', 17: 't', 18: '1', 19: '2', 20: '3', 21: '4', 22: '6',
    23: '5', 24: '=', 25: '9', 26: '7', 27: '-', 28: '8', 29: '0',
    30: ']', 31: 'o', 32: 'u', 33: '[', 34: 'i', 35: 'p', 37: 'l',
    38: 'j', 39: "'", 40: 'k', 41: ';', 42: '\\', 43: ',', 44: '/',
    45: 'n', 46: 'm', 47: '.', 50: '`',
}
_CHAR_TO_VK: dict[str, int] = {c: vk for vk, c in _VK_TO_CHAR.items()}

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

# macOS modifier flag bitmasks for CGEventSourceFlagsState
_MODIFIER_FLAGS = {
    Key.shift: 0x20000,   # kCGEventFlagMaskShift
    Key.ctrl:  0x40000,   # kCGEventFlagMaskControl
    Key.cmd:   0x100000,  # kCGEventFlagMaskCommand
    Key.alt:   0x80000,   # kCGEventFlagMaskAlternate
}

_WATCHDOG_INTERVAL = 0.1  # seconds


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
            vk = _CHAR_TO_VK.get(part)
            trigger = KeyCode.from_char(part, vk=vk) if vk is not None else KeyCode.from_char(part)
        else:
            raise ValueError(f"Unknown key: {part}")

    if trigger is None:
        raise ValueError(f"No trigger key found in combo: {combo}")

    return modifiers, trigger, is_modifier_trigger


def build_combo_string(modifiers: set, trigger) -> str:
    """Convert captured modifiers + trigger into a config combo string like 'shift+cmd_r'."""
    reverse_mod = {Key.cmd: "cmd", Key.shift: "shift", Key.ctrl: "ctrl", Key.alt: "alt"}
    reverse_mod_trigger = {
        Key.cmd_r: "cmd_r",
        Key.shift_r: "shift_r",
        Key.ctrl_r: "ctrl_r",
        Key.alt_r: "alt_r",
    }

    parts = [reverse_mod.get(m, str(m)) for m in modifiers]
    if trigger in reverse_mod_trigger:
        parts.append(reverse_mod_trigger[trigger])
    elif isinstance(trigger, Key):
        parts.append(trigger.name)
    elif isinstance(trigger, KeyCode):
        if trigger.char:
            parts.append(trigger.char)
        elif trigger.vk is not None and trigger.vk in _VK_TO_CHAR:
            parts.append(_VK_TO_CHAR[trigger.vk])
        else:
            parts.append(str(trigger))

    return "+".join(parts)


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
        if trigger.char:
            parts.append(trigger.char.upper())
        elif trigger.vk is not None and trigger.vk in _VK_TO_CHAR:
            parts.append(_VK_TO_CHAR[trigger.vk].upper())
        else:
            parts.append(str(trigger))
    return "".join(parts)


def _get_os_modifiers() -> set:
    """Query macOS for the current modifier key state via Quartz."""
    flags = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState)
    held = set()
    for mod_key, mask in _MODIFIER_FLAGS.items():
        if flags & mask:
            held.add(mod_key)
    return held


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
        self._watchdog_timer: threading.Timer | None = None
        self._event_count: int = 0

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

    def has_received_events(self) -> bool:
        """Return True if the listener has received any key events."""
        return self._event_count > 0

    def _on_key_press(self, key):
        self._event_count += 1
        try:
            self._handle_press(key)
        except Exception:
            logger.exception("Error in _on_key_press")

    def _on_key_release(self, key):
        try:
            self._handle_release(key)
        except Exception:
            logger.exception("Error in _on_key_release")

    def _handle_press(self, key):
        # Key capture mode
        if self._capture_callback is not None:
            self._handle_capture_press(key)
            return

        # Normal hotkey detection
        canonical = self._to_canonical(key)
        logger.debug("key_press: raw=%r canonical=%r modifiers=%s", key, canonical, self._pressed_modifiers)
        if canonical in _MODIFIER_MAP.values():
            self._pressed_modifiers.add(canonical)

        for name, binding in self._bindings.items():
            if binding.active:
                continue

            if binding.is_modifier_trigger:
                # Modifier-as-trigger: exact modifier set match + raw key match
                if (
                    key == binding.trigger
                    and self._pressed_modifiers
                    == binding.modifiers | {binding.trigger_canonical}
                ):
                    logger.debug("activate '%s': modifier_trigger match", name)
                    binding.active = True
                    binding.on_press()
            else:
                # Regular binding: superset match + canonical trigger match
                if (
                    self._pressed_modifiers >= binding.modifiers
                    and canonical == binding.trigger
                ):
                    logger.debug("activate '%s': trigger match", name)
                    binding.active = True
                    binding.on_press()
                    self._start_watchdog()

    def _handle_release(self, key):
        if self._capture_callback is not None:
            self._handle_capture_release(key)
            return

        canonical = self._to_canonical(key)
        logger.debug("key_release: raw=%r canonical=%r modifiers=%s", key, canonical, self._pressed_modifiers)

        for name, binding in self._bindings.items():
            if not binding.active:
                continue

            if binding.is_modifier_trigger:
                # Deactivate when the raw trigger modifier or a required modifier is released
                if key == binding.trigger or canonical in binding.modifiers:
                    logger.debug("deactivate '%s': modifier_trigger release", name)
                    binding.active = False
                    binding.on_release()
            else:
                if canonical == binding.trigger or canonical in binding.modifiers:
                    logger.debug("deactivate '%s': trigger/modifier release", name)
                    binding.active = False
                    binding.on_release()

        self._pressed_modifiers.discard(canonical)

        # Safety net: deactivate any active binding whose modifiers are no longer held
        for name, binding in self._bindings.items():
            if not binding.active or binding.is_modifier_trigger:
                continue
            if binding.modifiers and not (self._pressed_modifiers >= binding.modifiers):
                logger.debug("deactivate '%s': modifiers no longer held (safety net)", name)
                binding.active = False
                binding.on_release()

        if not any(b.active for b in self._bindings.values()):
            self._stop_watchdog()

    # -- Modifier watchdog (polls macOS for actual modifier state) ----------

    def _start_watchdog(self):
        """Start polling macOS modifier flags to detect missed key-up events."""
        self._stop_watchdog()
        self._tick_watchdog()

    def _stop_watchdog(self):
        if self._watchdog_timer is not None:
            self._watchdog_timer.cancel()
            self._watchdog_timer = None

    def _tick_watchdog(self):
        """Check OS modifier state; deactivate bindings whose modifiers dropped."""
        try:
            held = _get_os_modifiers()
            for name, binding in self._bindings.items():
                if not binding.active or binding.is_modifier_trigger:
                    continue
                if binding.modifiers and not (held >= binding.modifiers):
                    logger.debug("deactivate '%s': OS reports modifiers released (watchdog)", name)
                    binding.active = False
                    binding.on_release()
        except Exception:
            logger.exception("Error in watchdog tick")

        # Reschedule if any binding is still active
        if any(b.active and not b.is_modifier_trigger for b in self._bindings.values()):
            self._watchdog_timer = threading.Timer(_WATCHDOG_INTERVAL, self._tick_watchdog)
            self._watchdog_timer.daemon = True
            self._watchdog_timer.start()
        else:
            self._watchdog_timer = None

    def _to_canonical(self, key) -> Key | KeyCode:
        """Normalize key variants (e.g. cmd_l/cmd_r → cmd, KeyCode vk↔char)."""
        if isinstance(key, Key):
            name = key.name
            for base in ("cmd", "shift", "ctrl", "alt"):
                if name.startswith(base):
                    return _MODIFIER_MAP[base]
            return key

        if isinstance(key, KeyCode):
            vk = key.vk
            char = key.char
            # Have vk in our mapping → always normalize to canonical char + vk
            if vk is not None and vk in _VK_TO_CHAR:
                return KeyCode.from_char(_VK_TO_CHAR[vk], vk=vk)
            # Have char but no vk → resolve vk and lowercase
            if vk is None and char is not None:
                char_lower = char.lower()
                looked_up_vk = _CHAR_TO_VK.get(char_lower)
                if looked_up_vk is not None:
                    return KeyCode.from_char(char_lower, vk=looked_up_vk)
                return KeyCode.from_char(char_lower)

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
        self._stop_watchdog()
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
            cb(mods, self._to_canonical(key))

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

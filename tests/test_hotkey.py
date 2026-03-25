"""Tests for pure functions in mini_whisper/hotkey.py."""

import pytest
from pynput.keyboard import Key, KeyCode

from mini_whisper.hotkey import build_combo_string, format_hotkey, parse_hotkey


# ---------------------------------------------------------------------------
# parse_hotkey
# ---------------------------------------------------------------------------

def test_parse_modifier_plus_key():
    mods, trigger, is_mod_trigger = parse_hotkey("cmd+shift+space")
    assert mods == {Key.cmd, Key.shift}
    assert trigger == Key.space
    assert is_mod_trigger is False


def test_parse_modifier_trigger():
    mods, trigger, is_mod_trigger = parse_hotkey("shift+cmd_r")
    assert mods == {Key.shift}
    assert trigger == Key.cmd_r
    assert is_mod_trigger is True


def test_parse_single_modifier_trigger():
    mods, trigger, is_mod_trigger = parse_hotkey("cmd_r")
    assert mods == set()
    assert trigger == Key.cmd_r
    assert is_mod_trigger is True


def test_parse_single_char_key():
    mods, trigger, is_mod_trigger = parse_hotkey("cmd+a")
    assert mods == {Key.cmd}
    assert isinstance(trigger, KeyCode)
    assert trigger.char == "a"
    assert is_mod_trigger is False


def test_parse_tab_key():
    mods, trigger, is_mod_trigger = parse_hotkey("ctrl+tab")
    assert mods == {Key.ctrl}
    assert trigger == Key.tab
    assert is_mod_trigger is False


def test_parse_no_trigger_raises():
    with pytest.raises(ValueError, match="No trigger key"):
        parse_hotkey("cmd+shift")


def test_parse_unknown_key_raises():
    with pytest.raises(ValueError, match="Unknown key"):
        parse_hotkey("cmd+foobar")


def test_parse_empty_raises():
    with pytest.raises(ValueError):
        parse_hotkey("")


# ---------------------------------------------------------------------------
# build_combo_string (+ roundtrip via re-parse)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("combo", [
    "shift+cmd_r",
    "cmd_r",
    "cmd+space",
    "cmd+shift+space",
    "ctrl+tab",
])
def test_build_combo_roundtrip(combo):
    mods, trigger, is_mod_trigger = parse_hotkey(combo)
    rebuilt = build_combo_string(mods, trigger)
    # Re-parse should give equivalent result
    mods2, trigger2, is_mod_trigger2 = parse_hotkey(rebuilt)
    assert mods == mods2
    assert trigger == trigger2
    assert is_mod_trigger == is_mod_trigger2


# ---------------------------------------------------------------------------
# format_hotkey
# ---------------------------------------------------------------------------

def test_format_hotkey_contains_symbols():
    text = format_hotkey({Key.cmd, Key.shift}, Key.space)
    assert "⌘" in text
    assert "⇧" in text
    assert "Space" in text


def test_format_modifier_trigger():
    text = format_hotkey({Key.shift}, Key.cmd_r)
    assert "⇧" in text
    assert "Right ⌘" in text


def test_format_single_modifier_trigger():
    text = format_hotkey(set(), Key.cmd_r)
    assert "Right ⌘" in text


def test_format_char_key():
    mods, trigger, _ = parse_hotkey("cmd+a")
    text = format_hotkey(mods, trigger)
    assert "⌘" in text
    assert "A" in text

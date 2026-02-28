"""Paste text into the active application via clipboard + Cmd+V."""

import subprocess
import time

from pynput.keyboard import Controller, Key

_keyboard = Controller()


def paste(text: str, submit: bool = False):
    """Copy text to clipboard and simulate Cmd+V in the active app.

    Args:
        text: The text to paste.
        submit: If True, press Enter after pasting to submit the text.
    """
    # Copy to clipboard via pbcopy
    subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)

    # Small delay to ensure clipboard is ready
    time.sleep(0.05)

    # Simulate Cmd+V
    _keyboard.press(Key.cmd)
    _keyboard.press("v")
    _keyboard.release("v")
    _keyboard.release(Key.cmd)

    if submit:
        time.sleep(0.15)
        subprocess.run([
            "osascript", "-e",
            "tell application \"System Events\" to key code 36",
        ], check=True)

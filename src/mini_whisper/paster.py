"""Paste text into the active application via clipboard + Cmd+V."""

import subprocess
import time

from pynput.keyboard import Controller, Key

_keyboard = Controller()


def paste(text: str):
    """Copy text to clipboard and simulate Cmd+V in the active app.

    Args:
        text: The text to paste.
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

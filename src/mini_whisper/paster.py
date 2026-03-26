"""Paste text into the active application via clipboard + Cmd+V."""

import subprocess
import time

import Quartz
from AppKit import NSWorkspace

# Key codes
_KEY_V = 9
_KEY_ENTER = 36


def _post_key(key_code: int, flags: int = 0):
    """Post a key down+up event directly to the frontmost application's PID."""
    pid = NSWorkspace.sharedWorkspace().frontmostApplication().processIdentifier()
    src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    for key_down in (True, False):
        event = Quartz.CGEventCreateKeyboardEvent(src, key_code, key_down)
        if flags:
            Quartz.CGEventSetFlags(event, flags)
        Quartz.CGEventPostToPid(pid, event)


def paste(text: str, submit: bool = False):
    """Copy text to clipboard and simulate Cmd+V in the active app.

    Args:
        text: The text to paste.
        submit: If True, press Enter after pasting to submit the text.
    """
    subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
    time.sleep(0.05)

    _post_key(_KEY_V, Quartz.kCGEventFlagMaskCommand)

    if submit:
        time.sleep(0.15)
        _post_key(_KEY_ENTER)

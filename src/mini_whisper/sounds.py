"""Sound effects using NSSound (AppKit/pyobjc — no extra deps)."""

import logging
from pathlib import Path

from AppKit import NSSound

logger = logging.getLogger(__name__)

_ASSETS = Path(__file__).parent / "assets"
_cache: dict[str, NSSound] = {}
_volume: float = 1.0


def set_volume(v: float) -> None:
    global _volume
    _volume = max(0.0, min(1.0, v))


def _load(name: str) -> NSSound | None:
    if name not in _cache:
        path = str(_ASSETS / f"{name}.mp3")
        sound = NSSound.alloc().initWithContentsOfFile_byReference_(path, True)
        if sound is None:
            logger.warning("Could not load sound: %s", path)
            return None
        _cache[name] = sound
    return _cache[name]


def play(name: str) -> None:
    """Play a sound asynchronously. name is 'on' or 'off'."""
    from AppKit import NSThread
    sound = _load(name)
    if not sound:
        return
    sound.stop()
    sound.setVolume_(_volume)
    if NSThread.isMainThread():
        sound.play()
    else:
        # NSSound should be used on the main thread; dispatch without blocking.
        sound.performSelectorOnMainThread_withObject_waitUntilDone_(b"play", None, False)

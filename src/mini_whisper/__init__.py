"""Mini Whisper — macOS menu bar dictation app."""

from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("mini-whisper")
except PackageNotFoundError:
    try:
        from Foundation import NSBundle
        info = NSBundle.mainBundle().infoDictionary()
        __version__ = info.get("CFBundleShortVersionString", "unknown")
    except Exception:
        __version__ = "unknown"

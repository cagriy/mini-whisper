"""Mini Whisper — macOS menu bar dictation app."""

from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("mini-whisper")
except PackageNotFoundError:
    __version__ = "unknown"

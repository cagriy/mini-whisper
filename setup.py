"""py2app build configuration for Mini Whisper."""

import os

from setuptools import setup

_version = os.environ.get("APP_VERSION", "0.1.3")

APP = ["src/mini_whisper/app.py"]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,
    "iconfile": "src/mini_whisper/assets/AppIcon.icns",
    "plist": {
        "CFBundleName": "Mini Whisper",
        "CFBundleIdentifier": "com.cagri.mini-whisper",
        "CFBundleVersion": _version,
        "CFBundleShortVersionString": _version,
        "LSUIElement": True,
        "NSMicrophoneUsageDescription": (
            "Mini Whisper needs microphone access to record your dictation."
        ),
        "NSAccessibilityUsageDescription": (
            "Mini Whisper needs accessibility access to detect hotkeys "
            "and paste text."
        ),
    },
    "packages": ["mini_whisper", "_soundfile_data"],
    "includes": [
        "rumps",
        "pynput",
        "AVFoundation",
        "soundfile",
        "httpx",
        "keyring",
        "numpy",
    ],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    install_requires=[],  # Override pyproject.toml deps; py2app 0.28.9+ rejects non-empty
)

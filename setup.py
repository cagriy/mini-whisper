"""py2app build configuration for Mini Whisper."""

import os

from setuptools import setup

_version = os.environ.get("APP_VERSION", "0.1.3")

APP = ["src/mini_whisper/app.py"]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,
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
    "packages": ["mini_whisper"],
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
    setup_requires=["py2app"],
)

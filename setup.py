"""py2app build configuration for Mini Whisper."""

import os
import re

from setuptools import setup


def _read_pyproject_version():
    with open("pyproject.toml") as f:
        m = re.search(r'^version\s*=\s*"(.+?)"', f.read(), re.MULTILINE)
    return m.group(1) if m else "0.0.0"


_version = os.environ.get("APP_VERSION") or _read_pyproject_version()

APP = ["src/mini_whisper/app.py"]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,
    "iconfile": "src/mini_whisper/assets/AppIcon.icns",
    "plist": {
        "CFBundleName": "Mini Whisper",
        "CFBundleIdentifier": "com.ips.mini-whisper",
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
        "NSInputMonitoringUsageDescription": (
            "Mini Whisper needs Input Monitoring access to detect "
            "global hotkeys."
        ),
        "NSSpeechRecognitionUsageDescription": (
            "Mini Whisper uses on-device speech recognition to show a "
            "live transcript while you dictate."
        ),
    },
    "packages": ["mini_whisper", "_soundfile_data", "keyring.backends"],
    "includes": [
        "rumps",
        "pynput",
        "pynput.keyboard._darwin",
        "pynput.mouse._darwin",
        "pynput._util.darwin",
        "pynput._util.darwin_vks",
        "AVFoundation",
        "soundfile",
        "httpx",
        "numpy",
        "Quartz",
        "ApplicationServices",
        "Speech",
        "websockets",
    ],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    install_requires=[],  # Override pyproject.toml deps; py2app 0.28.9+ rejects non-empty
)

"""py2app build configuration for Mini Whisper."""

from setuptools import setup

APP = ["src/mini_whisper/app.py"]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,
    "plist": {
        "CFBundleName": "Mini Whisper",
        "CFBundleIdentifier": "com.cagri.mini-whisper",
        "CFBundleVersion": "0.1.0",
        "CFBundleShortVersionString": "0.1.0",
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

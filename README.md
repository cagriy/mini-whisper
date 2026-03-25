# Mini Whisper

**Speak. Release. Done.**

Mini Whisper is a lightweight macOS menu bar app that turns your voice into text — instantly, anywhere. Hold a hotkey, say what you want, release, and your words appear in whatever app is in focus. No copy-paste, no switching windows, no friction.

Powered by OpenAI's `gpt-4o-mini-transcribe` for fast, accurate transcription and GPT-4o-mini for optional AI cleanup that silently strips filler words and fixes grammar before pasting.

---

## Features

### Speak into any app
Mini Whisper pastes transcribed text directly into the active app via clipboard simulation — works in browsers, editors, terminals, chat apps, IDEs, and anywhere else you type.

### Push-to-talk and toggle modes
- **Push-to-talk**: Hold the hotkey while speaking, release to transcribe and paste
- **Toggle mode**: Tap the hotkey to start recording, tap again to stop — ideal for longer dictations

### Auto-submit mode
A second configurable hotkey transcribes, pastes, **and** presses Enter. Perfect for chat apps, Claude Code, shell terminals, and anywhere you'd hit Enter right after typing.

### AI text cleanup
An optional GPT-4o-mini pass runs after transcription to silently remove filler words ("um", "uh", "you know"), fix grammar, and clean up false starts — so what gets pasted reads like you meant to write it. Fully customizable via your own system prompt.

### Animated recording overlay
A floating constellation of dots appears when you're recording — physics-driven, audio-reactive, 60 FPS. The dots pulse and react to your voice in real time so you always know the app is listening. Switches to a rotating animation while processing.

### Privacy-first
- API key stored in the **macOS Keychain** — never written to disk
- Audio goes only to OpenAI's API; nothing is stored locally after processing
- No telemetry, no analytics, no phoning home

### Native macOS, no Electron
Built with PyObjC, AVFoundation, and AppKit. Near-instant recording start thanks to a preallocated audio engine. Lightweight enough to forget it's running.

### Fully customizable
- Remap any hotkey (supports modifier keys like Right Cmd as standalone triggers)
- Edit the transcription instructions and cleanup prompt from the Settings window
- Adjust feedback sound volume
- View daily token usage from the menu bar

---

## Installation

### Download (recommended)

Download the latest `MiniWhisper-{version}-arm64.dmg` from the [GitHub Releases](../../releases) page. Open the DMG, drag **Mini Whisper.app** to your Applications folder, and launch it.

> Requires macOS 13 or later on Apple Silicon.

### From source

```bash
# Prerequisites: Python 3.12+, uv (https://docs.astral.sh/uv/)
git clone https://github.com/cagriy/mini-whisper.git
cd mini-whisper
uv sync
uv run mini-whisper
```

---

## Setup

### 1. Grant permissions

On first launch, Mini Whisper walks you through the two permissions it needs:

- **Microphone** — to capture your voice
- **Accessibility** — to paste text into other apps

The onboarding window guides you to the right macOS System Settings pane for each and waits until both are granted before continuing.

### 2. Add your OpenAI API key

Open **Settings** from the menu bar icon and paste your OpenAI API key into the API Key field. The key is saved directly to the macOS Keychain.

Don't have an API key? Get one at [platform.openai.com](https://platform.openai.com).

---

## Usage

| Action | Default hotkey |
|---|---|
| Record and paste | `Shift + Right Cmd` |
| Record, paste, and submit | `Right Cmd` |

Both hotkeys support push-to-talk (hold) and toggle (tap) modes automatically based on how long you press.

The menu bar icon shows a dropdown with your last transcription (click to copy it again), today's token usage, and links to Settings and About.

---

## Configuration

| Location | Purpose |
|---|---|
| `~/.config/mini-whisper/config.json` | Hotkeys, cleanup toggle, volume, token usage |
| `~/.config/mini-whisper/prompt.txt` | AI cleanup system prompt |
| `~/.config/mini-whisper/transcribe_prompt.txt` | Transcription instructions |
| macOS Keychain | OpenAI API key |

All of these are editable from the **Settings** window inside the app.

---

## Building a .app bundle

```bash
# pyproject.toml must be temporarily hidden due to a py2app conflict
mv pyproject.toml pyproject.toml.bak && python setup.py py2app && mv pyproject.toml.bak pyproject.toml
```

The resulting `Mini Whisper.app` will be in the `dist/` folder.

---

## Requirements

- macOS 13+, Apple Silicon
- OpenAI API key (`gpt-4o-mini-transcribe` and `gpt-4o-mini` access)
- Python 3.12+ (if running from source)

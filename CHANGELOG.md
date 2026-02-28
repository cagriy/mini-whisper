# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.2] - 2026-02-28

### Changed
- Replace sounddevice (PortAudio) with AVAudioEngine for near-instant recording start
- Audio engine pre-warms hardware at init via `prepare()`, eliminating ~200-500ms startup latency
- Hardware captures at native rate (48kHz) and resamples to 16kHz at stop time

## [0.1.1] - 2026-02-28

### Added
- Dual hotkey support: paste-only (`cmd+shift+space`) and paste+submit (`cmd+shift+enter`)
- "Change Submit Hotkey..." menu item for configuring the submit hotkey
- `submit_hotkey` config option with default `cmd+shift+enter`
- HotkeyListener now supports multiple named bindings on a single listener

## [0.1.0] - 2026-02-28

### Added
- macOS menu bar app with rumps (MW icon, full settings menu)
- Push-to-talk hotkey (default: Cmd+Shift+Space)
- Audio recording via sounddevice (16kHz mono WAV)
- OpenAI Whisper API transcription
- GPT-4o-mini text cleanup (remove filler words, fix grammar)
- Paste into active app via pbcopy + Cmd+V simulation
- API key storage in macOS Keychain via keyring
- Configurable hotkey with live key capture dialog
- Editable cleanup prompt (~/.config/mini-whisper/prompt.txt)
- Toggle to enable/disable text cleanup
- First-run welcome dialog with setup instructions
- py2app bundling configuration (setup.py + entitlements.plist)

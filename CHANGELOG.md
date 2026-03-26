# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.6] - 2026-03-26

### Fixed
- Keychain access broken in app bundle — `keyring.backends` was missing from py2app packages, causing `NoKeyringError` and preventing startup
- Settings window opens automatically on first launch when no API key is set, instead of showing an alert that could cause the window to appear behind other apps
- Settings window failure is now logged instead of silently swallowed

## [0.1.5] - 2026-03-26

### Changed
- File logging to `/tmp/mini-whisper.log` now only happens when `--debug` flag is passed

## [0.1.3] - 2026-03-06

### Added
- Sound effects on recording start/stop (`on.mp3` / `off.mp3`) via AppKit NSSound
- Volume slider in Settings → Sound section (0–100%)
- Volume preference persisted in config (`sound_volume`)
- Preview sound plays on slider release so user can hear the chosen volume

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

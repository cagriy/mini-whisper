# Mini Whisper

Hold a hotkey, speak, release — the transcript is pasted into whatever app you were using.
A macOS menu-bar app with a live transcript overlay, on-device or cloud speech engines, and
optional AI cleanup.

## Install

```sh
brew tap cagriy/tap
brew install --cask mini-whisper
```

## Permissions

On first launch Mini Whisper asks for:

- **Microphone** — to record your dictation.
- **Accessibility** — to paste the transcript into the frontmost app.
- **Input Monitoring** — to detect the global hotkey.
- **Speech Recognition** — only when you choose the on-device live transcript engine.

## Privacy

- API keys are stored in the macOS login Keychain (service `mini-whisper`), never on disk.
- Cloud engines send audio to the provider you select (OpenAI, ElevenLabs or Speechmatics).
  On-device engines send nothing off the machine.
- Dictation history is stored **locally only**, in `~/.config/mini-whisper/history.jsonl`
  (file mode 0600), for `history_retention_days` days — default 7, maximum 30. Set it to
  **0** to disable history entirely: the file is deleted and nothing further is written.
- There is no telemetry or analytics of any kind.

## Development

See [CLAUDE.md](./CLAUDE.md) for layout, dev commands, the module map and test conventions.

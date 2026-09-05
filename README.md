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

## Corrections and vocabulary

Correct a misheard phrase once and Mini Whisper remembers it: **Correct Last Dictation…**
in the menu bar, or **Correct…** on a History row, opens a window where you select the
phrase, type the spelling you want, and save it. A rule scoped to **This app** only changes
dictations delivered to that app; **All apps** changes them everywhere. Rules and the plain
vocabulary list are edited under Settings → Vocabulary, where a rule can be disabled or
deleted at any time — it stops firing from the next recording.

A rule is **deterministic**: every whole-phrase match in its scope is rewritten, on every
engine and every path. A hint is **probabilistic**: the correct spelling, the misheard
phrase and any sounds-like variants are also sent to the recognizer, so it is likelier to
produce the right words in the first place. What each engine is sent:

- **On-device (Apple Speech)** — the first 100 terms as contextual strings.
- **SpeechAnalyzer (macOS 26)** — the terms are set on the analyzer's context, but Apple
  documents that property as read by a different transcriber, and the effect has not been
  measured on this engine, so Settings reports it as “hints not sent · effect not yet
  measured”. The rule itself still applies.
- **OpenAI Realtime** — every term as `keywords`.
- **Speechmatics** — one `additional_vocab` entry per rule, carrying the variants as
  `sounds_like`, up to 1000 entries.
- **ElevenLabs** — no hints in this version; the rule still rewrites the transcript.
- **Batch transcription** — the terms are appended to the request's documented `prompt`
  field, which replaces the undocumented `instructions` field earlier versions sent. Your
  `transcribe_prompt.txt` now reaches the model.
- **Cleanup** — the prompt lists the terms to keep as written and the corrections to make.

Settings → Vocabulary shows, per engine, how many hints were sent and anything that was
skipped.

## Privacy

- API keys are stored in the macOS login Keychain (service `mini-whisper`), never on disk.
- Cloud engines send audio to the provider you select (OpenAI, ElevenLabs or Speechmatics).
  On-device engines send nothing off the machine.
- Dictation history is stored **locally only**, in `~/.config/mini-whisper/history.jsonl`
  (file mode 0600), for `history_retention_days` days — default 7, maximum 30. Set it to
  **0** to disable history entirely: the file is deleted and nothing further is written.
- Correction rules and the tally of phrases you have corrected are stored **locally only**,
  in `~/.config/mini-whisper/config.json`. They leave the machine only as recognition hints,
  to the engine you selected.
- There is no telemetry or analytics of any kind.

## Development

See [CLAUDE.md](./CLAUDE.md) for layout, dev commands, the module map and test conventions.

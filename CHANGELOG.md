# Changelog

## [Unreleased]

### Added

- Remembered corrections. Correct a misheard phrase from the menu bar's last dictation or
  from a History row, and save it as a rule scoped to that app or to all apps. The rule
  rewrites every later dictation in its scope, and its spellings are sent to the recognizer
  as hints where the engine takes them — Apple Speech, SpeechAnalyzer, OpenAI Realtime and
  Speechmatics; ElevenLabs receives none. Rules and a tally of corrected phrases are stored
  locally in `config.json` under two new keys, `corrections` and `correction_tally`.
- Settings → Vocabulary: a corrections table with a detail form for the selected rule, an
  "Often corrected" list, and a per-engine report of the hints sent and skipped.

### Changed

- The batch transcription request sends the documented `prompt` field instead of the
  undocumented `instructions` field. A customised `transcribe_prompt.txt` therefore reaches
  the model for the first time; the shipped default only asks for accurate punctuation and
  capitalisation.

## [0.2.0] - 2026-09-05

Native Swift rewrite.

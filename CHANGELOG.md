# Changelog

## [Unreleased]

## [0.5.0] - 2026-09-07

### Added

- Six overlay animation styles for the recording card: Soft meter, Silk ribbon, Resonant halo,
  Liquid pearl, Petal iris and the original Constellation. **Soft meter is now the default for
  every install** — Settings → Overlay picks any of the six beside a live preview that loops a
  simulated dictation, and Constellation is one click away.

### Changed

- The release pipeline signs the DMG itself, not just the app inside it, and refuses to submit an
  image `hdiutil` cannot verify. Gatekeeper can now assess the download on its own signature;
  0.4.0 and earlier shipped an unsigned image.

## [0.4.0] - 2026-09-07

### Added

- Automatic updates, via Sparkle. Mini Whisper checks for a new version once a day, shows the
  changelog entry for it, and installs and relaunches once you approve. `Check for Updates…` in
  the menu bar checks on demand; Settings → General turns the daily check off. Homebrew no longer
  needs to upgrade the app, and no longer tries to.
- **This release has to be installed the old way.** 0.3.1 and earlier have no updater, and the
  cask is now `auto_updates true`, so plain `brew upgrade` skips it. Run
  `brew upgrade --cask --greedy mini-whisper` (or install the DMG) once to get here; updates are
  automatic from then on.

## [0.3.1] - 2026-09-07

### Fixed

- The release pipeline signs the app with a Developer ID, notarizes and staples the
  DMG, and publishes it. 0.3.0 was tagged but produced no downloadable build, and an
  unsigned one would not have opened.

## [0.3.0] - 2026-09-06

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

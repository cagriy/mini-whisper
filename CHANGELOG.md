# Changelog

## [Unreleased]

## [0.9.0b5] - 2026-11-25

### Added

- Timeline: lifetime totals, the year, weekly rhythm, talk share, spend, dictation, records and
  milestones, from the statistics record. Open it from the sidebar, ⌘3 or the menu-bar menu.
  Costs are estimates; everything stays on the Mac.
- The sidebar shows the last 30 days above the usage table; click it for Timeline, or fold it
  with the handle on the table's top edge.
- Settings → Statistics → Typing speed sets the speed "saved typing" is measured against.

### Changed

- While Settings is open the sidebar hides the usage table, so every section fits in the
  smallest window.

## [0.9.0b4] - 2026-11-24

### Added

- A numbers-only record of meetings, dictations and estimated spend, kept for life under
  `~/.config/mini-whisper/stats/`: counts, lengths, word counts, costs and which app each
  dictation went to. No text, titles or names; nothing leaves the Mac. It starts from the
  dictations and meetings already stored, and survives clearing history and deleting meetings.
- Settings → Statistics → Reset Statistics rebuilds the record from what is still stored.

## [0.9.0b3] - 2026-11-23

### Fixed

- Quit from the menu bar hung once the main window had been opened that session.

## [0.9.0b2] - 2026-11-23

### Changed

- Speaker names Claude is less sure of are suggested too, instead of dropped; only a certain
  self-introduction is applied without asking.

## [0.9.0b1] - 2026-11-22

### Added

- Speaker names suggested from the conversation by Claude Haiku 5.5, each with the line it came
  from; stopped meetings offer Suggest names. The transcript goes to Anthropic during the
  meeting, about 3 cents a meeting. Needs an Anthropic key; turn off under Settings → Meetings.

## [0.8.2] - 2026-11-22

### Added

- Settings → General → Updates: choose Release or Beta versions. Beta gets new versions first;
  switching back to Release keeps an installed beta until the next release.

## [0.8.1] - 2026-11-20

### Fixed

- Turning a Remember voices switch off and on again during a meeting resumed recognising and
  learning in that meeting; it now stays off until the next one.
- `voices.json` was written through a temporary file that other users on the Mac could briefly
  read; it is now owner-only from the start.

## [0.8.0] - 2026-11-20

### Added

- Remember voices. A speaker you name is named, or offered as a provisional name to Accept,
  Edit or Dismiss, in later meetings; only names you confirm are learned. Two switches under
  Settings → Meetings, both off by default:
  - **Remember voices on this Mac** (AssemblyAI engines) keeps a voiceprint per person from a
    bundled voice model (WeSpeaker, Core ML). Nothing leaves the Mac. Unverified on macOS 14.
  - **Remember voices with Speechmatics** (Speechmatics engines) keeps the voice identifier
    Speechmatics returns and sends it back in later meetings, labelled by an opaque id, never a
    name. With this switch on, Speechmatics may split speakers differently.
  Voiceprints and identifiers, never audio, are kept in `~/.config/mini-whisper/voices.json`,
  each meeting's `voices.json` and `voice-matches.jsonl` (all 0600). A slider sets how readily
  names are applied; `config.json` gains `voice_local_enabled`, `voice_speechmatics_enabled` and
  six `voice_*` tuning keys.
- Settings → People lists everyone remembered, with Rename, Merge into…, Forget and Forget
  everyone. Forget removes their voice data from every meeting; names in transcripts stay.
- About → **Credits…** credits the WeSpeaker voice model (CC BY 4.0) and Sparkle.

## [0.7.3] - 2026-11-19

### Added

- A meeting is named after its summary's subject: `Meeting · 19 Nov 2026 10:01` becomes
  `API Platform Options · 19 Nov 2026 10:01`. Regenerate names it again. A title you gave is
  kept, as is a test call's.

## [0.7.2] - 2026-11-17

### Fixed

- Renaming a meeting, while it records or after, could crash the app.

## [0.7.1] - 2026-11-16

### Added

- Meetings stop after silence: with no speech for a minute (never in the first 3), a prompt
  offers to keep recording and stops the meeting a minute later. Settings → Meetings →
  Stop after silence takes Off, 1, 2 or 5 min (`meeting_silence_stop_seconds` in `config.json`).
  On by default; Off records until you stop, as before. A meeting stopped this way says so on
  its finished page.

## [0.7.0] - 2026-11-14

### Added

- One main window. Its sidebar holds search, Start Meeting, Meetings, Dictations, Settings and
  a usage table of today's and this month's tokens, audio time and cost. ⌘1, ⌘2, ⌘, and ⌘N go
  to a page, ⌘F searches, ⌘[ leaves a finished meeting, ⌘W hides the window. Closing it never
  stops a recording; its size and place are kept in `config.json` (`main_window_frame`).
- One search over meeting titles, transcripts, notes and summaries and stored dictations.
- Theme: Settings → General → Appearance → System, Light or Dark (`theme` in `config.json`).
  The dictation overlay is unchanged.
- **Regenerate** on a finished meeting, after confirming the current summary's cost. That
  summary stays until the new one arrives, and stays if the request fails; its cost stays in
  the meeting's total (`replacedSummaryCostUSD` in `meeting.json`).
- **Copy summary**: the title and summary as Markdown, HTML and RTF.

### Changed

- A new look for every window but the overlay, light and dark, recorded in `DESIGN.md`.
- Meetings, Dictations (formerly History) and Settings are pages of the main window; the menu's
  *History...* is *Dictations…*. A meeting is a page too: the chooser, the live meeting, then
  the finished meeting with Summary, Transcript and Notes tabs. While a meeting runs, a
  recording pill in the sidebar leads back to it.
- Summaries are written by topic and end with Next Steps; they display as headings and lists.
  A `summary_prompt.txt` still holding the previous default is replaced at launch; an edited
  one is kept. Four-section summaries still display.
- A Meetings row shows the summary's topics under its title, else its first sentence, else the
  transcript's first line.
- The menu's Month row shows tokens and audio time, as Today does. Audio time of an hour or
  more reads `2h 14m`.
- The Dock icon stays while any Mini Whisper window is open.
- Correction, Onboarding and About follow the new look; About is a window, not an alert.

### Removed

- The Meetings, History, Settings and Meeting windows.
- The search fields of the meetings and history lists.
- Settings' *Open History…* and *Open Meetings…* buttons.
- The finished meeting's **Meetings** button; its back button (⌘[) returns to the page it was
  opened from.

## [0.6.2] - 2026-11-13

### Added

- Settings → Meetings shows how to add the MCP server to the ChatGPT app for Mac, with the
  command to paste.
- A finished meeting's window has a **Meetings** button that closes it and opens the list.

## [0.6.1] - 2026-11-13

### Fixed

- The 0.6.0 fix for quiet remote calls did not take effect: other apps still dropped about
  30 dB while a remote meeting recorded, and the call still reached the transcription engine
  too quiet. Other apps now drop about 8 dB and the call reaches the engine at speech level,
  both measured.

## [0.6.0] - 2026-11-11

### Added

- Test calls. **Test Call…** in the New Meeting window runs a scripted two-minute remote call:
  two macOS voices speak through the speakers and you read your lines. Stop scores the
  transcript against the script — word error rate per speaker and overall, speaker-label
  consistency and latency — and keeps the score with the meeting for comparison with earlier
  runs. Eight scenarios, about $0.02 a run. Test calls are marked TEST in *Meetings…* and hidden
  from the `mini-whisper` tool and MCP server.

### Fixed

- A remote meeting turned other apps' audio down by about 30 dB, the call included, and the
  call reached the transcription engine too quiet to transcribe well. Other apps now drop about
  7 dB, and the call is raised to speech level before it is mixed with the microphone.

## [0.5.1] - 2026-11-10

### Added

- Meeting mode. **⌃⌥⌘M** or *Start Meeting…* records a remote call (microphone plus the audio
  other apps play) or an in-room meeting (microphone only) with a live, speaker-labelled
  transcript and timestamped notes; Stop writes a Claude Sonnet 5.5 summary. Four engines:
  Speechmatics Standard ($0.45/h) and Enhanced ($0.80/h), AssemblyAI Universal-Streaming
  ($0.27/h) and Universal 3.6 Pro ($0.57/h), the AssemblyAI prices including $0.12/h for speaker
  labels. Meetings are stored locally in `~/.config/mini-whisper/meetings/`, listed and searched
  in *Meetings…*, exported as Markdown, and billed into the Today/Month rows. Settings → Meetings
  holds the engine, your name, Keep meeting audio and the summary prompt; `config.json` gains
  `meeting_hotkey`, `meeting_engine`, `meeting_keep_audio`, `meeting_user_name` and
  `meeting_system_audio_explained`.
- The System Audio Recording permission (macOS 14.2+), asked at the first remote call.
- AssemblyAI and Anthropic keys under Settings → Keys.
- AssemblyAI Universal-Streaming as a dictation engine ($0.15/h), with vocabulary sent as key
  terms.
- The `mini-whisper` command-line tool, installed from Settings → Meetings:
  `meetings transcript|summary <id>` print the exported Markdown, `meetings list|search` one line
  per meeting or hit, or JSON with `--json`. `mini-whisper mcp` is a stdio MCP server with four
  read-only tools for Claude Code and other agents. Neither records nor changes a meeting.

### Changed

- The Speechmatics rate is now $0.0075 per minute (was $0.0067): new usage costs more; past
  Today/Month totals are unchanged.
- Dictation hotkeys are off while a meeting records or is paused, and starting a meeting cancels
  a dictation in progress.

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

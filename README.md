# Mini Whisper

Hold a hotkey, speak, release — the transcript is pasted into whatever app you were using.
A macOS menu-bar app with a live transcript overlay, on-device or cloud speech engines, and
optional AI cleanup.

## Install

```sh
brew tap cagriy/tap
brew trust cagriy/tap
brew install --cask mini-whisper
```

Homebrew refuses to load casks from a third-party tap until you trust it, so the
`brew trust` line is required, not optional.

Requires macOS 14 (Sonoma) or newer, on Apple silicon.

Mini Whisper updates itself: it checks once a day, shows what changed, and installs only
after you approve. `Check for Updates…` in the menu bar checks on demand, and the General
tab of Settings turns the daily check off. Homebrew leaves the app alone once installed, so
there is no need to `brew upgrade` it.

## Permissions

On first launch Mini Whisper asks for:

- **Microphone** — to record your dictation and meetings.
- **Accessibility** — to paste the transcript into the frontmost app.
- **Input Monitoring** — to detect the global hotkey.
- **Speech Recognition** — only when you choose the on-device live transcript engine.
- **System Audio Recording** — macOS 14.2 or newer, at the first remote-call meeting, to hear
  the other participants. Without it a remote call transcribes only you; Settings → Meetings →
  **Open Privacy Settings…** opens the pane.

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
- **AssemblyAI** — up to 100 terms as `keyterms_prompt`; a term over 50 characters is
  skipped.
- **ElevenLabs** — no hints in this version; the rule still rewrites the transcript.
- **Batch transcription** — the terms are appended to the request's documented `prompt`
  field, which replaces the undocumented `instructions` field earlier versions sent. Your
  `transcribe_prompt.txt` now reaches the model.
- **Cleanup** — the prompt lists the terms to keep as written and the corrections to make.

Settings → Vocabulary shows, per engine, how many hints were sent and anything that was
skipped.

## Meetings

Press **⌃⌥⌘M** (Settings → Hotkeys → Meeting) or choose **Start Meeting…** in the menu bar,
then pick:

- **Remote call** — the microphone plus the audio other apps play (Zoom, Teams, Meet), mixed
  into one stream. Words spoken while your microphone hears you are labelled with your name
  (Settings → Meetings → Your name, by default your macOS account's full name); other voices
  become Speaker 1, 2…. Needs macOS 14.2 or newer.
- **In the room** — the microphone only. Every voice becomes Speaker 1, 2…; rename yourself
  once your first words appear.

The window shows the live transcript, your notes, the elapsed time and the running cost.
Click a speaker's name to rename them everywhere; a name already in use merges the two. Enter
adds a note stamped with the meeting time, Shift+Enter a new line. **Pause** stops streaming
until **Resume**; the Mac going to sleep pauses too. A dropped connection never ends a
meeting: audio keeps recording, the session reconnects, and the transcript marks the gap.
Dictation hotkeys are off while a meeting records or is paused, and starting a meeting cancels
a dictation in progress. Your **All apps** correction rules and vocabulary reach the engine as
hints; rules do not rewrite meeting transcripts.

**Stop** sends the transcript and notes to Claude Sonnet 5.5 for a summary — Summary,
Decisions, Action items, Open questions — under the prompt in Settings → Meetings
(`summary_prompt.txt`). Without an Anthropic key (Settings → Keys), after a failed request, or
when quitting stopped the meeting, **Summarise** writes it later; a meeting holds one summary.
After Stop, double-click a paragraph to edit it, or right-click to move a segment to another
speaker. **Export** writes `<title> - transcript.md` and `<title> - summary.md`.

**Meetings…** in the menu bar lists meetings by day with their cost and searches titles,
transcripts, notes and summaries.

### Engines and prices

Pick the engine under Settings → Meetings. Without a pick, or without its key, the first
engine below whose key is under Settings → Keys is used. Meetings are English only.

| Engine | Key | Per hour |
|---|---|---|
| Speechmatics Standard | Speechmatics | $0.45 |
| Speechmatics Enhanced | Speechmatics | $0.80 |
| AssemblyAI Universal-Streaming | AssemblyAI | $0.27, including $0.12 for speaker labels |
| AssemblyAI Universal 3.6 Pro | AssemblyAI | $0.57, including $0.12 for speaker labels |

The summary costs $2.00 per million input tokens and $10.00 per million output tokens — a few
cents for an hour's meeting. Costs join the menu bar's Today/Month rows when a meeting stops;
every rate can be overridden in `config.json`'s `pricing_overrides`.

### Storage and consent

```
~/.config/mini-whisper/meetings/
  index.json
  <meeting id>/
    meeting.json      title, speakers, gaps and pauses, summary, cost
    segments.jsonl    transcript
    notes.jsonl       notes
    audio.m4a         AAC, 16 kHz mono, about 14 MB per hour
    testcall.json     a test call's score
```

Folders are 0700, files 0600, and nothing is deleted automatically. Turn off **Keep meeting
audio** (Settings → Meetings) to record no audio file. **Meetings…** deletes a meeting, or
only its audio with **Export → Delete audio**.

**You are responsible for getting consent to record.** Mini Whisper does not tell the other
participants.

### Limitations

- A remote call is one mixed stream: overlapping voices can garble words, and words said over
  you may be labelled as yours.
- While a remote call records, other apps play a little quieter (about 8 dB): macOS lowers them
  while echo cancellation keeps your speakers out of the microphone.
- If the provider merges two voices into one speaker, renaming cannot split them; move their
  segments one at a time after Stop.
- After a reconnect, voices get new Speaker numbers; rename one to an existing name to merge.
- English only.
- Form ⌃⌥⌘M with the **left** ⌘. Right ⌘ alone is the default **Record and submit** hotkey,
  so pressing it first starts a dictation.

### Command line and agents

Settings → Meetings → **Install…** writes `/usr/local/bin/mini-whisper`, a script that runs the
app; it asks for an administrator password only when you cannot write to `/usr/local/bin`. The
tool and its MCP server only read meetings: they never record or change one.

```sh
mini-whisper meetings list [--json]
mini-whisper meetings transcript <id>    # the Markdown Export writes
mini-whisper meetings summary <id>
mini-whisper meetings search <text> [--json]
```

`<id>` is a meeting's UUID or at least its first 8 hex characters. A bad or unknown id, or a
summary that does not exist, exits 2.

`mini-whisper mcp` is a stdio MCP server (MCP 2025-06-18, 2025-11-25 and 2026-07-28) with the
read-only tools `list_meetings`, `search_meetings`, `get_transcript` and `get_summary`. Add it
to Claude Code:

```sh
claude mcp add --transport stdio mini-whisper -- mini-whisper mcp
```

Settings → Meetings → Claude Code copies this command, naming the app's binary by its full
path until the tool is installed.

### Test call

**Test Call…**, at the bottom left of the New Meeting window, runs a scripted remote call that
measures how well meetings transcribe on this Mac. Pick a scenario (Random, or one of eight), an
engine and Overlap, then **Start Test Call**. Two macOS voices speak their lines through the
speakers; you read yours from the script pane, which hands over after a 1.2 s pause. **Skip
line** leaves a line out of the score. Pause is off during a test call.

Stop scores the transcript against the script: word error rate per speaker and overall, which
speaker label each voice got and how consistently, and how late the final text arrived. The
score is kept with the meeting (`testcall.json`), and **Earlier runs…** compares runs of the
same scenario on this Mac. A run takes about 2 minutes and costs about $0.02; it is billed and
summarised like any meeting and marked TEST in **Meetings…**.

- The score is a relative benchmark across engines, settings and builds: synthetic voices
  diarise differently from people.
- The `mini-whisper` tool and its MCP server never list, search or return a test call.
- Test calls need two English voices. Add one in System Settings → Accessibility → Spoken
  Content → System voice → Manage Voices….

## Privacy

- API keys are stored in the macOS login Keychain (service `mini-whisper`), never on disk.
- Cloud engines send audio to the provider you select (OpenAI, ElevenLabs, Speechmatics or
  AssemblyAI); a meeting summary sends the transcript and notes to Anthropic. On-device
  engines send nothing off the machine.
- Dictation history is stored **locally only**, in `~/.config/mini-whisper/history.jsonl`
  (file mode 0600), for `history_retention_days` days — default 7, maximum 30. Set it to
  **0** to disable history entirely: the file is deleted and nothing further is written.
- Correction rules and the tally of phrases you have corrected are stored **locally only**,
  in `~/.config/mini-whisper/config.json`. They leave the machine only as recognition hints,
  to the engine you selected.
- Meetings, with their audio unless **Keep meeting audio** is off, are stored **locally
  only**, in `~/.config/mini-whisper/meetings/` (folders 0700, files 0600), until you delete
  them. They are not part of dictation history. An agent connected to the MCP server can
  read every meeting except test calls.
- There is no telemetry or analytics of any kind.

## Development

See [CLAUDE.md](./CLAUDE.md) for layout, dev commands, the module map and test conventions.

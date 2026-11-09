# Meeting transcripts — Brainstorm v4

**Status:** Draft
**Date:** 2026-11-09

## 1. Summary
Mini Whisper records short dictations from the microphone and pastes the result into the front app. Users also sit in remote calls (Zoom, Teams, Meet) and in-room meetings where nobody is keeping a reliable record, and the app already has the pieces a meeting recorder needs: audio capture, three cloud streaming adapters, Keychain-held keys, editable prompt files, a History window and per-day cost tracking. This feature adds a meeting mode: a hotkey or menu item starts capturing the microphone and the Mac's own system audio, a window shows the live transcript with the user's own voice labelled as them and other voices labelled Speaker 1..N by real-time diarization, speaker names can be changed at any point, the user can type timestamped notes alongside, and on Stop the transcript and notes are sent to Claude Sonnet 5.5 for a summary under an editable prompt. Transcript and summary export as Markdown, past meetings live in an in-app list, and a read-only command-line entry point and MCP server let Claude Code and other agents fetch them. It is the "meeting" work the 2026-09 application review deferred, now sized to the app's own strengths rather than to meeting bots or team workspaces, and it is the first feature to introduce a second audio source and a second LLM provider.

## 2. Goals
- A meeting started from the hotkey or the menu produces, on Stop, a transcript in which every segment carries a speaker label and a time, the user's own speech is labelled as the user, and other participants are labelled consistently for the whole meeting.
- Renaming a speaker at any moment, during or after the meeting, changes every segment of that speaker in the window and in every later export, and survives relaunch.
- Stopping a meeting yields a summary written by Claude Sonnet 5.5 from the transcript and the user's typed notes, using the shipped default prompt unless the user has edited it; editing the prompt and choosing Re-summarise produces a new summary from the stored transcript without re-recording.
- Transcript and summary each export as a Markdown file through the save panel, with speaker names, times and notes as shown in the window.
- A dropped provider connection never ends a meeting: audio keeps recording, the engine reconnects, and the transcript shows where the gap was.
- Every finished meeting appears in the Meetings list with its cost, and `mini-whisper`-style command-line and MCP calls return the same transcript and summary Markdown an export would.

## 3. Scope (in / out)
- **In scope:**
  - A third configurable hotkey and menu items to start and stop a meeting recording, plus a `Meetings…` menu item opening the list.
  - Capturing the microphone and the Mac's system audio together, for remote calls and in-room meetings. System audio requires macOS 14.2+; on 14.0 and 14.1 meeting mode records the microphone only and says so.
  - The onboarding and Settings surface for the new System Audio Recording permission.
  - A live meeting window: transcript with speaker labels and times, the user's own microphone labelled as the user, other voices as Speaker 1..N from real-time diarization, rename at any point, Pause/Resume, elapsed time and running cost.
  - A timestamped notes pane in the meeting window; each note carries the meeting time it was typed, appears at that point in the exported transcript, and is passed to the summariser as the user's notes.
  - Two meeting engines, selectable in Settings: Speechmatics real-time diarization through the existing adapter, and AssemblyAI streaming with speaker labels through a new adapter and a new Keychain account.
  - Summary on Stop by Claude Sonnet 5.5 through a new Anthropic Keychain account and a Settings → Keys field; a shipped default summary prompt, editable the same way as the cleanup and transcribe prompts; a Re-summarise action.
  - After Stop: editing transcript text and reassigning a segment to another speaker, with edits saved.
  - An in-app Meetings list: open, rename, re-summarise, export, delete. Meetings are kept until the user deletes them and are not subject to the history retention window.
  - Each meeting keeps its audio recording, deletable per meeting, with a Settings toggle to stop keeping audio.
  - Export of transcript and of summary as Markdown via the save panel.
  - Reconnect on a dropped provider connection, with a marked gap in the transcript while audio keeps recording.
  - The dictation hotkey is locked while a meeting is recording, with a short notice.
  - Default meeting title from date, time and the front app at start, renamable.
  - Meeting costs (engine minutes and Sonnet tokens) counted in the existing Today/Month usage rows and overridable through `pricing_overrides`.
  - Read-only agent access: a command-line entry point and a stdio MCP server (hand-written JSON-RPC, no dependency) that list meetings, fetch a transcript or summary as Markdown, and search transcripts.
  - README and CHANGELOG describing the new permission, the engines that can diarize, the costs per hour and where meetings are stored.
- **Out of scope / deferred:**
  - Calendar integration: naming meetings from the current event and prompting to start when an event begins.
  - Re-transcribing a meeting from its saved audio through a provider's batch endpoint.
  - Retroactive start from a rolling audio buffer.
  - A live running summary during the meeting.
  - On-device diarization through a bundled CoreML package, which would break the no-new-dependency rule.
  - A question box over the whole meeting archive ("ask your meetings").
  - Agent control of recording (start, pause, stop) through the CLI or MCP server.
  - An auto-export folder written on every Stop.
  - A mark-moment hotkey dropping a timestamped marker without typing.
  - Claude Haiku 5.5 or an OpenAI model as a selectable summariser.
  - Soniox, Deepgram, OpenAI, ElevenLabs or Apple's engine as meeting engines (the last three cannot diarize live).
  - Automatic speaker recognition across meetings from stored voice samples.
  - Dictation while a meeting is recording.
  - Editing transcript text while the meeting is still recording.
  - Meeting languages beyond what the existing adapter configuration already supports.
  - Meeting bots that join calls, cloud sync, sharing links and team workspaces.

## 4. High-level technical direction
- Bundle ID `com.ips.mini-whisper`, Team `XPRCQRLN7Y`, macOS 14 deployment target, arm64, Swift 6 with complete strict concurrency, as for every feature.
- No new third-party dependency: Sparkle stays the only one, in the app target. The AssemblyAI adapter, the Anthropic client and the MCP server are written against Foundation networking, following the existing adapter and `OpenAIClient` patterns.
- System audio capture must use a native Apple API available on macOS 14.2+, with graceful microphone-only behaviour on 14.0 and 14.1 and a clear permission flow; it must not require Screen Recording permission if an audio-only route exists.
- Secrets live only in the Keychain under the existing service, as new accounts beside the three present ones. No key is ever written to disk, a log, a fixture or a comment.
- `config.json` stays round-trippable by this app and the Python app: new top-level keys for the meeting hotkey, meeting engine, audio retention and summariser settings; unknown keys preserved.
- Meeting data (segments with speaker and times, notes, summary, audio, metadata) lives under `~/.config/mini-whisper/`, is never auto-deleted, and is the single source both the window and the agent access read.
- The user's own speech is labelled from the microphone source; other voices are labelled by the provider's diarization. Whether this means two provider streams, one mixed stream with correlation, or a provider channel feature is a design decision with a direct cost consequence that must be surfaced in Settings and the README.
- Speaker labels and renames are applied to stored segments, never baked into provider output; a rename is a local mapping so it can be changed again.
- Meeting duration is not bounded by the dictation toggle cap or idle stop; provider session limits (AssemblyAI closes after 3 h) must be handled without ending the meeting.
- Pricing constants for the new engine and model are added to the existing rate tables and remain overridable; costs are recorded against the day as dictations are.
- Every duration (reconnect backoff, pause, keepalive, timer) is tested on the virtual clock; provider request contracts are covered by request-contract tests; TDD throughout.
- Agent access is read-only by construction: the CLI and MCP server expose no operation that starts capture or changes stored data.

## 5. Alternatives considered
- Diarize every voice equally in one mixed stream, with the user's own voice as just another Speaker N — rejected because the microphone already tells the app which speech is the user's, and renaming yourself in every meeting is friction the audio source can remove.
- Files only: write each meeting as Markdown into a chosen folder with no in-app list — rejected because re-summarising after a prompt edit, renaming speakers after the fact and agent access all need a stored meeting the app can reopen.
- A single cheapest vendor (Soniox at $0.12/hr) as the only meeting engine — rejected in favour of Speechmatics plus AssemblyAI: one adapter already exists and the other is the strongest diarizer found, and two engines let the user compare label quality before settling.
- Keep dictation available during a meeting by sharing the microphone feed — rejected for this version as design complexity without a settled need; the hotkey shows a notice instead.

## 6. Risks
- Real-time diarization merges or splits speakers, especially in rooms with several voices. Impact: wrong attribution in the transcript and summary. Mitigated by renames, post-meeting reassignment and the AssemblyAI label revisions; residual error is documented.
- Streaming two sources may double the per-hour engine cost ($0.90–1.60 on Speechmatics, $0.54–1.14 on AssemblyAI per meeting hour). Impact: a cost surprise after a long call. Mitigated by the running cost in the window and the stated rates in Settings and README.
- The system audio permission adds a second TCC prompt and a 14.2+ API; macOS may re-prompt or revoke after updates. Impact: a meeting that silently captures the microphone only. Must be detected and shown before recording starts.
- Recording other people's speech is regulated differently by jurisdiction and the app cannot know who consented. Impact: legal exposure for the user. The README states that the user is responsible for consent; no consent feature is built.
- Audio and transcripts of other people sit unencrypted under the config directory, and agent access makes them readable to any local process that can run the CLI. Impact: sensitive data exposure on a shared or compromised Mac. Documented; audio retention can be turned off.
- Provider churn: OpenAI deprecated its diarizing model within a year, and AssemblyAI is a new contract for this app. Impact: an adapter that stops working between releases. Mitigated by request-contract tests and two engines.
- Long sessions hit limits the dictation path never saw: AssemblyAI closes after 3 h, devices change mid-meeting (AirPods connecting), the Mac may sleep. Impact: lost minutes. Covered by the reconnect-and-mark-gap goal and explicit tests on the virtual clock.
- The summary may invent decisions or action items not in the transcript. Impact: a wrong record that reads as authoritative. Mitigated by a prompt that quotes the transcript's speakers and by the user's notes being passed as a separate, labelled input.

## 7. Open questions for design
- How the user's own label is derived: two provider streams (one per source), one mixed stream with microphone-activity correlation, or a provider multichannel feature; and how the chosen approach's cost is shown.
- Which native API captures system audio (Core Audio process taps versus ScreenCaptureKit), which permission it triggers, how 14.0/14.1 fall back to microphone only, and what the onboarding step looks like.
- The meeting storage format and layout under the config directory: segment schema with speaker, times and revisions, notes, summary versions, audio container and compression, and what the Meetings list indexes.
- Speechmatics operating point (Standard versus Enhanced) and AssemblyAI tier (Universal-Streaming versus U-3.6 Pro): fixed per engine or a Settings choice, and the matching pricing keys (user leaned toward keeping Settings simple, but did not commit).
- How AssemblyAI's mid-session and end-of-session speaker label revisions are applied to segments already shown and already renamed.
- Reconnect and keepalive policy per provider, gap marker semantics, and how a meeting longer than AssemblyAI's 3 h session cap continues.
- Pause semantics: whether provider sessions stay open while paused, and how pause affects billed minutes and the gap marker.
- The default summary prompt's content and structure (summary, decisions, action items, open questions), how notes and speaker names are passed, and how Re-summarise versions are kept.
- Transcript Markdown layout: timestamp granularity, speaker paragraphs versus per-utterance lines, where notes and gap markers appear, and the summary file's front matter.
- How the command-line entry point is shipped (the app binary with arguments versus a helper inside the bundle), how the stdio MCP server is launched and registered with Claude Code, and the tool and search surface it exposes.
- How the dictation lock is communicated (overlay notice versus menu state) and how the meeting hotkey interacts with the two existing hotkeys and profiles.
- How the running cost is estimated live for a two-source meeting before provider usage is confirmed, and how it is reconciled into the day's usage on Stop.

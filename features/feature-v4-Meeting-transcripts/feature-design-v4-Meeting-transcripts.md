# Meeting transcripts — Design v4

**Status:** Draft
**Date:** 2026-11-09
**Storm:** [feature-storm-v4-Meeting-transcripts.md](./feature-storm-v4-Meeting-transcripts.md)

## 1. Summary

Mini Whisper gains a **meeting mode**. A third hotkey (⌃⌥⌘M) or the menu item *Start Meeting…*
opens a chooser between a **remote call** (microphone plus the Mac's own system audio) and an
**in-room meeting** (microphone only). While the meeting records, a 920×620 window shows a live,
speaker-labelled transcript with the user's own speech labelled by name and other voices as
Speaker 1..N, a notes pane where each typed note carries the meeting time, elapsed time and the
running cost. Stop sends transcript and notes to Claude Sonnet 5.5 for a summary under an
editable prompt. Every meeting is stored under `~/.config/mini-whisper/meetings/`, listed in a
Meetings window with search, and exportable as two Markdown files. A read-only command-line entry
point and a stdio MCP server give Claude Code and other agents the same transcript and summary
text. It is for the single user of this menu-bar app who sits in calls nobody records; it reuses
the capture, streaming-adapter, Keychain, prompt-file, usage and list machinery that dictation
already has, and introduces the app's first second audio source and first second LLM provider.

## 2. Goals and non-goals

- **Goals**
  - A meeting started from the hotkey or menu yields, on Stop, a transcript in which every segment
    has a speaker and a meeting time, the user's speech is labelled with the user's name, and other
    participants keep one label each for the whole meeting.
  - Renaming a speaker at any time changes every segment of that speaker in the window and every
    later export, and survives relaunch.
  - Stop produces a Claude Sonnet 5.5 summary from transcript and notes under the shipped default
    prompt or the user's edit of it; a meeting without a summary can be summarised later by one
    button.
  - Transcript and summary each export as Markdown through the save panel in the accepted layout.
  - A dropped provider connection never ends a meeting: audio keeps recording, the session
    reconnects, the transcript marks the gap.
  - Every finished meeting appears in the Meetings list with its cost, is searchable, and the CLI
    and MCP server return the same Markdown an export would.
  - Meeting costs land in the existing Today/Month usage rows and stay overridable through
    `pricing_overrides`.
- **Non-goals** (deferred as in the storm §3, with the reasons there)
  - Two provider sessions per remote call (one per source). Deferred as a future improvement if
    the mixed-stream attribution in §5.6 proves insufficient; see §6.
  - Re-summarise after a prompt edit, and summary versions. The user dropped this in the interview;
    a meeting holds at most one summary.
  - Calendar integration, batch re-transcription from saved audio, retroactive start, live
    running summary, on-device diarization, archive-wide question box, agent control of
    recording, auto-export folder, mark-moment hotkey, other summarisers, other meeting engines,
    cross-meeting voice recognition, dictation during a meeting, editing text while recording,
    non-English meetings, meeting bots, sync and sharing.
  - A consent feature. The README states the user is responsible for consent to record.
  - This feature is single-project: no briefs under `./briefs/`.

## 3. Requirements

Functional

1. `BindingName.meeting` with config key `meeting_hotkey` (default `ctrl+alt+cmd+m`) opens the
   meeting chooser when no meeting is active, stops the meeting when one records, and is a no-op
   while the chooser is open. The menu bar shows *Start Meeting…* and *Meetings…* when idle, and
   *Stop Meeting* and *Show Meeting…* while a meeting records or is paused.
2. The chooser offers **Remote call** and **In the room**; both show "About $0.45 per hour" for
   Speechmatics Standard (the price follows the configured engine). On macOS 14.0 and 14.1 the
   Remote card is disabled with "needs macOS 14.2". Before the first remote meeting on a Mac the
   chooser shows the System Audio Recording note; afterwards it does not.
3. In a remote call the microphone and the system-audio tap are mixed into **one** 16 kHz mono
   stream sent to **one** provider session. Words whose time span overlaps microphone speech
   activity are attributed to the user; all other words take the provider's diarization label.
   In an in-room meeting the microphone alone is sent, diarized, and no speaker is auto-labelled
   as the user.
4. `meeting_engine` selects one of `speechmatics_standard`, `speechmatics_enhanced`,
   `assemblyai_streaming`, `assemblyai_pro`. Absent, the first row whose key exists is used; when
   no key exists the chooser's Start button is disabled with "Add a Speechmatics or AssemblyAI key
   under Keys." Meetings are English only.
5. `EngineName.assemblyai` is added as a **dictation** engine too (`universal-streaming-english`,
   no speaker labels), gated on the new AssemblyAI key like the other cloud engines.
6. `KeyAccount.assemblyai` (`assemblyai-api-key`) and `KeyAccount.anthropic` (`anthropic-api-key`)
   are added; Settings → Keys shows both rows; the Anthropic mask check accepts keys starting
   `sk-ant-`.
7. The transcript view merges consecutive segments of one speaker into one paragraph headed by the
   speaker's name and the time of its first word; partial text is grey with a cursor; clicking a
   name opens a rename popover whose result applies to every segment of that speaker.
8. Notes: Enter commits a note stamped with the meeting time of its first keystroke; Shift+Enter
   inserts a newline; notes appear inline in the transcript at their time, in the Notes pane, in
   the transcript export as block quotes, in the summary export as a list, and are passed to the
   summariser as labelled input.
9. Pause closes the provider session and stops streaming; audio files are padded with silence for
   the paused span; the transcript shows "Paused hh:mm:ss–hh:mm:ss"; Resume opens a fresh session.
   System sleep auto-pauses and the meeting stays paused until Resume ("Paused (Mac slept)").
10. A provider disconnect or close code keeps audio recording, reconnects with backoff 1, 2, 4, 8,
    15, 30 s (30 s repeated indefinitely), and writes "Transcript gap hh:mm:ss–hh:mm:ss (connection
    lost)" when the new session delivers its first word. AssemblyAI sessions roll over at
    `expires_at − 60 s`; a Speechmatics session-timeout warning triggers the same rollover.
11. After a reconnect, provider labels start fresh; new remote speakers get the next free
    Speaker N; the user merges by renaming. AssemblyAI `SpeakerRevision` messages re-map words by
    `turn_order` within their session; a manual per-segment reassignment after Stop is final and
    is not overwritten by a revision.
12. Stop: the window shows the final transcript, bills the meeting into `UsageStore`, writes the
    meeting to disk, and requests the summary. The summary panel sits above the transcript with
    Summary, Decisions, Action items, Open questions and a meta line (model, time, tokens, cost).
    Without an Anthropic key the panel reads "No summary: add an Anthropic key under Keys." with a
    *Summarise* button; a failed call shows its reason and the same button; a refusal shows
    "Summary declined (category)". The button exists only while the meeting has no summary.
13. After Stop, double-click edits a paragraph's text and right-click → *Move this segment to*
    reassigns it; both persist.
14. Meeting storage: `meetings/<uuid>/meeting.json`, `segments.jsonl`, `notes.jsonl`, `audio.m4a`
    (AAC, 16 kHz mono, present when `meeting_keep_audio` is true), plus `meetings/index.json`;
    directory 0700, files 0600; meetings are never auto-deleted and are not in dictation history.
15. Default title "<front app name> · <d MMM yyyy HH:mm>" at start (the front app before the
    chooser opened; "Meeting" when none), renamable from the window header and the list.
16. Meetings window 680×480: day-grouped rows (mode glyph, title, summary excerpt or italic first
    transcript line, meta line), hover actions Open / Export ▾ / Delete, footer with count, audio
    size, *Show in Finder* and *Start Meeting…*; title-bar search over titles, transcript text,
    notes and summaries showing up to two labelled snippets per matching row; an empty state that
    names the hotkey.
17. Export writes "<title> - transcript.md" and "<title> - summary.md" (title sanitised: `/` and
    `:` → `-`) in the accepted layout (§5.5); *Export both* writes both into one chosen folder;
    exporting a summary of a meeting without one is refused with a message.
18. Billing: live estimate = fed audio seconds × engine rate (+ diarization add-on for AssemblyAI)
    while recording; on Stop the meeting's seconds are recorded under the engine's pricing key in
    `ProviderUsage.streamedSeconds` with the cost computed from the rates, and the summary's input
    and output tokens are added with their cost at the `claude-sonnet-5-5_in`/`_out` rates; pricing
    keys `speechmatics` (0.0075), `speechmatics_enhanced` (0.013333), `assemblyai` (0.0025),
    `assemblyai_pro` (0.0075), `assemblyai_diarization` (0.002) per minute and
    `claude-sonnet-5-5_in` 2.00 / `_out` 10.00 per MTok are added, all overridable.
19. Dictation hotkeys are locked while a meeting records or is paused: a press shows the overlay
    notice "Dictation is off while a meeting is recording" and does nothing else.
20. Settings → Meetings (one section after History) holds: engine rows with prices and key gating,
    Your name (default: macOS account full name), Keep meeting audio (default on), Open Privacy
    Settings…, Summary prompt editor (Save Prompt / Open in Editor / Restore Default), Storage row
    (count, audio size, Show in Finder, Open Meetings…), and under "Command line and agents" the
    rows Command-line tool (Install…) and Claude Code (MCP command + Copy).
21. `mini-whisper meetings list|transcript <id>|summary <id>|search <text>` prints Markdown or
    JSON to stdout and exits 0; unknown id → exit 2 with one stderr line; `mini-whisper mcp` runs a
    stdio JSON-RPC server with tools `list_meetings`, `get_transcript`, `get_summary`,
    `search_meetings`, all `readOnlyHint: true`, speaking both the legacy `initialize` handshake
    and the 2026-07-28 stateless shape. Neither entry point starts capture or changes stored data.
22. *Install…* writes `/usr/local/bin/mini-whisper`, a shell wrapper that execs the app binary at
    its baked path and falls back to resolving the bundle by id; it is a regular file, never a
    symlink, created through `osascript … with administrator privileges`.
23. README and CHANGELOG describe the permission, the engines, the per-hour prices, the storage
    location, the consent responsibility, and the CLI/MCP usage.

Non-functional

24. No new third-party dependency; `MiniWhisperCore` stays dependency-free; Swift 6 strict
    concurrency; macOS 14 deployment target with `@available(macOS 14.2, *)` around the tap.
25. Every duration (backoff, rollover margin, pause, VAD hysteresis, summary timeout, 60 s silence
    hint) is tested on `VirtualClock`; provider wire shapes are covered by request-contract tests
    against fixtures; no network in unit tests.
26. A two-hour meeting holds at most the last ~2 s of audio in memory; segments stream to disk on
    arrival; the transcript view renders from an in-memory model of ≤ 20 000 segments without
    stutter.
27. No secret is written to disk, log, fixture or comment; the Anthropic request logs sizes and
    status only.
28. `config.json` stays round-trippable by this app and the Python app: new keys are
    `meeting_hotkey`, `meeting_engine`, `meeting_keep_audio`, `meeting_user_name`,
    `meeting_system_audio_explained`; all optional.

## 4. Background and context

- **Capture.** `AudioCaptureEngine` (`Packages/MiniWhisperCore/Sources/MWAudio/AudioCaptureEngine.swift:108`)
  is an actor that owns one `AudioBackend` for the idle period, installs a tap on every
  `ensureRunning()` (`:142`), accumulates every sample of a capture into `snapshot.samples` (`:81`)
  and encodes a WAV on stop (`:172`). It hands buffers to one `BufferListener` set through
  `attachListener` (`:160`). It stops `idle_stop_seconds` after a dictation, tears down on
  `.configurationChanged` (`:206`) and stops on `.systemWillSleep` (`:212`). None of this fits a
  two-hour meeting: accumulation is unbounded and the idle stop and sleep handling end capture.
- **Streaming.** `StreamingEngine` (`MWStreaming/StreamingEngine.swift:5`) is `start(sink:)`,
  `feed(_:)`, `finish(timeout:)`. `WebSocketEngine<Adapter>` (`MWStreaming/WebSocketEngine.swift:23`)
  buffers audio until open with a 60 s cap (`:24`), is single-shot on failure, and dispatches
  `AdapterEmitter.Emission` (`MWStreaming/EngineAdapter.swift:7`, cases `.partial`/`.final`) at two
  switch sites (`WebSocketEngine.swift:287-288` into the assembler, `:295-296` into the sink).
  `TranscriptSink` (`MWStreaming/TranscriptSink.swift:1`) has `onPartial`, `onFinal`,
  `onEngineError`. `SpeechmaticsAdapter` (`MWStreaming/Adapters/SpeechmaticsAdapter.swift:6`) builds
  `transcription_config` (`:39`) with `additional_vocab` (`:30`) and handles `AddPartialTranscript`,
  `AddTranscript`, `EndOfTranscript` (`:60-64`); it reads only the `transcript` text, never the
  per-word `speaker` or times. `EngineFactory.make` (`MWStreaming/EngineFactory.swift:38`) switches
  over `EngineName` at `:47-49`, `:110-114` and `KeyAccount(engine:)` at `:152-155`;
  `EngineNotice.label` at `MWStreaming/EngineSelection.swift:20-23`.
- **Config and secrets.** `EngineName` (`MWConfig/EngineName.swift:1`) has five cases. `Config`
  (`MWConfig/Config.swift:91`) round-trips unknown keys through `extra` (`:122`) and lists known keys
  in `Key.all` (`:186`). `KeyAccount` (`MWConfig/SecretStore.swift:3`) has three accounts under
  service `mini-whisper` (`MWConfig/KeychainStore.swift:9`). `PromptFiles`
  (`MWConfig/PromptFiles.swift:5`) copies bundled defaults (`App/Resources/default_prompt.txt`,
  `default_transcribe_prompt.txt`) into `prompt.txt` and `transcribe_prompt.txt` on first read.
- **Usage.** `Pricing.perMinute` (`MWUsage/Pricing.swift:9`) has `speechmatics: 0.0067`; engines map
  to rate keys through `engineRateKeys` (`:25`, only `.openai → openai_realtime`, others use
  `rawValue`, so `EngineName.assemblyai` bills under `assemblyai` with no table change);
  `UsageRecording.add(_: ProviderUsage)` (`MWUsage/UsageStore.swift:5-7`) takes `inputTokens`,
  `outputTokens`, `streamedSeconds: [String: Double]` and a caller-computed `costUSD`
  (`MWUsage/ProviderUsage.swift:2-7`); `UsageStore` (`:14`) sums `streamedSeconds` by key (`:32-33`). `MWUsageTests/PricingTests.swift:20` and `:94` pin 0.0067.
- **History.** `HistoryStore` (`MWHistory/HistoryStore.swift:13`) is the jsonl, 0600-file (`:129`),
  load-once, append pattern that the meeting store follows.
- **Hotkeys.** `BindingName` (`MWHotkeys/HotkeyAction.swift:2`) has `paste` and `pasteSubmit`;
  `HotkeyCombo.configString` (`MWHotkeys/HotkeyCombo.swift:59`). Switch sites over `BindingName`:
  `App/Settings/SettingsModel.swift:447-448` and `:458-459`, `App/AppDelegate.swift:327-338`
  (`bindings(from:)` table) and the `onAction` closure at `:155`;
  `DictationController.hotkeyPressed/Released` (`MWPipeline/DictationController.swift:69`, `:88`).
- **HTTP.** `OpenAIClient` (`MWTranscription/OpenAIClient.swift:15`) sends through `HTTPTransport`
  (`MWTranscription/HTTPTransport.swift:6`) and maps failures to `APIError`
  (`MWTranscription/APIError.swift:6`: `httpStatus`, `transport`, `emptyAudio`).
- **App shell.** `App/main.swift:3` creates `NSApplication.shared` unconditionally;
  `LaunchArguments` (`App/LaunchArguments.swift:4`) knows only `--debug`; `SingleInstanceGuard`
  (`App/SingleInstanceGuard.swift:5`) exits a second GUI instance. `MenuModel`
  (`App/MenuModel.swift:7-15`) has actions copyLast, correctLast, history, settings,
  checkForUpdates, about, quit, dispatched by the switch at `App/StatusItemController.swift:81-82`;
  `SettingsView` switches over `Section` at `App/Settings/SettingsView.swift:30-31`.
  `UIEventRouter.show(error:)` (`App/UIEventRouter.swift:46`) shows an
  overlay notice. `SettingsModel.Section` (`App/Settings/SettingsModel.swift:58`) has eight cases;
  `cloudEngines` (`:256`) is the gated engine table; `KeysSection.rows`
  (`App/Settings/KeysSection.swift:11`); `HotkeysSection` has two `HotkeyCaptureField`s;
  `HistoryListModel.engineLabel` (`App/History/HistoryListModel.swift:200`);
  `CorrectionsEditorModel.noun` (`App/Settings/CorrectionsEditorModel.swift:196`);
  `HintSerializer` (`MWCorrections/HintSerializer.swift:22`) has `openAIKeywords` and
  `speechmaticsVocab`. `OnboardingPermission` (`App/Onboarding/OnboardingModel.swift:5`) covers
  microphone and accessibility; `PermissionMonitor` (`App/PermissionMonitor.swift`) the same two.
  `App/Info.plist` has `NSMicrophoneUsageDescription` and no `NSAudioCaptureUsageDescription`; the
  entitlements hold only `com.apple.security.device.audio-input`.
- **Platform facts (verified against the macOS SDK headers and vendor docs during Step 3).**
  `AudioHardwareCreateProcessTap` and `CATapDescription` are `API_AVAILABLE(macos(14.2))`;
  `CATapDescription(monoGlobalTapButExcludeProcesses:)` captures every process's output except the
  listed ones; a tap is read through an aggregate device (`kAudioAggregateDeviceTapListKey`,
  `kAudioSubTapUIDKey`, `kAudioAggregateDeviceIsPrivateKey`) with `AudioDeviceCreateIOProcIDWithBlock`;
  the TCC prompt (`NSAudioCaptureUsageDescription`) appears at the first IO start, there is no API
  to query or request it, and denial yields silence; the pane anchor is
  `x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`.
  `AVAudioInputNode.setVoiceProcessingEnabled(_:)` provides echo cancellation. Speechmatics RT v2:
  `transcription_config.diarization: "speaker"`, `speaker_diarization_config.max_speakers`,
  `model: "standard"|"enhanced"`, `AddTranscript.results[].alternatives[].speaker` = `S1..Sn`/`UU`,
  per-result `start_time`/`end_time`; idle timeouts 1 h without audio and 3 min connection idle;
  48 h cap with warnings; closes 1003/1008/1011/4001-4013. AssemblyAI v3:
  `wss://streaming.assemblyai.com/v3/ws`, header `Authorization: <key>`, params `speech_model`,
  `encoding=pcm_s16le`, `sample_rate=16000`, `speaker_labels=true` (+$0.12/h), `max_speakers`,
  `speaker_labels_revision_interval_ms` (≥120000), `format_turns`, `keyterms_prompt` (≤100 terms,
  ≤50 chars), `inactivity_timeout`; messages `Begin{id,expires_at}`,
  `Turn{turn_order,end_of_turn,turn_is_formatted,transcript,words[{text,start,end,confidence,word_is_final,speaker}],speaker_label}`,
  `SpeakerRevision{revisions[{turn_order,speaker_label,words[]}]}`, `Terminate`, `Termination`;
  sessions close after 3 h; billed by connection time. Anthropic Messages API: `POST
  /v1/messages`, `x-api-key`, `anthropic-version: 2026-10-21`, `claude-sonnet-5-5` at $2/$10 per
  MTok, `output_config.effort`, `stop_reason: "refusal"` with `stop_details.category`,
  `fallbacks: "default"` under `anthropic-beta: server-side-fallback-2026-07-01`. MCP: stdio is
  newline-delimited JSON-RPC on stdout, stderr for logs, exit on stdin EOF; Claude Code 2.x sends
  `initialize` with protocol 2025-11-25; spec 2026-07-28 is stateless with `server/discover`.
- **Mockups.** Accepted in Step 5: [Meeting Window](./mockups/mockup-v4-meeting-window.html)
  ([artifact](https://claude.ai/artifact/TyA8BvbmphpAxbZeDpfuFf)),
  [Meetings List](./mockups/mockup-v4-meetings-list.html)
  ([artifact](https://claude.ai/artifact/8hLv1fbYG3YLQJQamkuKHg)),
  [Settings — One Meetings section](./mockups/mockup-v4-settings-one-pane.html)
  ([artifact](https://claude.ai/artifact/HAkM4WyxrSd7bUk1fdExeZ)),
  [Export Files](./mockups/mockup-v4-export-markdown.html)
  ([artifact](https://claude.ai/artifact/Ko7nAzDNRVU7CT1tFduP51)). Rejected:
  [Settings — Meetings and Agents sections](./mockups/mockup-v4-settings-two-panes.html).

## 5. Design

### 5.1 Architecture / components

New SwiftPM targets (all registered in `Package.swift` `targets:` and `products:`):

| Target | Responsibility | Depends on |
|---|---|---|
| `MWMeetings` | Meeting model (`Meeting`, `Segment`, `Note`, `Summary`, `SpeakerLabel`), `MeetingStore` (folder layout, jsonl, index), `MeetingMarkdown` (transcript/summary export text), `MeetingSearch`, `TitleSanitizer` | MWConfig, MWSupport |
| `MWMeetingPipeline` | `MeetingController` (state machine), `AudioMixer`, `SpeechGate` (mic VAD), `SpeakerAttributor`, `SpeakerRegistry`, `SessionSupervisor` (reconnect/rollover), `MeetingRecorder` (AAC writer), `MeetingBilling`, `Summariser` | MWMeetings, MWStreaming, MWAudio, MWConfig, MWUsage, MWTranscription, MWSupport |
| `MWAgentAccess` | `MeetingsCLI` (argument parsing, output), `MCPServer` (JSON-RPC framing, handshake, tools) | MWMeetings, MWSupport |

`MWMeetingPipeline` sits beside `MWPipeline` at the top of the dependency graph; nothing depends on
either. `MWAgentAccess` depends only on `MWMeetings` so the CLI never links audio or networking
(`MWMeetings` needs `MWConfig` for `MeetingEngine`; `MWConfig` links neither).

Extended targets:

| Target | Change |
|---|---|
| `MWAudio` | `AudioCaptureEngine.attachMeetingListener(_:)` + `holdRunning(_:)`; `SystemAudioTap` (`@available(macOS 14.2, *)`); `AACFileWriter`; `AudioBackend` gains `setVoiceProcessing(_:)` |
| `MWStreaming` | `Emission.segment`/`.speakerRevision`; `TranscriptSink.onSegment`/`onSpeakerRevision` (default no-op); `SpeechmaticsAdapter(diarization:model:)`; new `AssemblyAIAdapter`; `WebSocketEngine` closes/codes surfaced through `onEngineError`; `EngineFactory` handles `.assemblyai` and a new `makeMeeting(_:)`; `PlatformInfo` gains `osMinor` and `supportsSystemAudio` |
| `MWSupport` | `Log.meeting` category beside the six existing ones (`MWSupport/Log.swift:85-90`) |
| `MWConfig` | `EngineName.assemblyai`; `MeetingEngine` enum; `Config` keys `meeting_*`; `KeyAccount.assemblyai/.anthropic`; `PromptFiles.summaryPrompt()` + `summary_prompt.txt` |
| `MWCorrections` | `HintSerializer.assemblyAIKeyterms(_:)`; `HintReport` gains an AssemblyAI row (its test enumerates `EngineName.allCases`) |
| `MWUsage` | new pricing keys; `Pricing.meetingCost(engine:seconds:tokens:overrides:)` |
| `MWTranscription` | `AnthropicClient` (`Summarizing` protocol) reusing `HTTPTransport`/`APIError` |
| App | `MeetingWindowController` + SwiftUI `MeetingView`, `MeetingsWindowController` + `MeetingsListView`, `MeetingsSection` in Settings, Keys/Hotkeys/General rows, menu items, `main.swift` branch for `meetings`/`mcp`, `CommandLineToolInstaller`, `Info.plist` `NSAudioCaptureUsageDescription`, `App/Resources/default_summary_prompt.txt` |

Each component has one responsibility and a protocol seam where it touches the outside world
(`AudioBackend`, `WebSocketConnection`, `HTTPTransport`, `Clock`, `SecretStore`, `FileManager`
paths), so every one is unit-tested with the fakes in `MWTestSupport`.

### 5.2 Data model

**Config (`MWConfig/Config.swift`)** — new optional keys, all in `Key.all`, encoded only when set
except the defaults noted:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `meeting_hotkey` | string | `"ctrl+alt+cmd+m"` | `HotkeyCombo` config string |
| `meeting_engine` | string | absent | one of the four `MeetingEngine` raw values |
| `meeting_keep_audio` | bool | `true` | write `audio.m4a` |
| `meeting_user_name` | string | absent → `NSFullUserName()` at use | label for the user's speech |
| `meeting_system_audio_explained` | bool | `false` | first-remote-start note shown |

`MeetingEngine: String, Codable, CaseIterable` = `speechmatics_standard`, `speechmatics_enhanced`,
`assemblyai_streaming`, `assemblyai_pro`, with `keyAccount` (`.speechmatics` / `.assemblyai`),
`pricingKey` (`speechmatics`, `speechmatics_enhanced`, `assemblyai`, `assemblyai_pro`),
`diarizationPricingKey` (`assemblyai_diarization` for the two AssemblyAI tiers, nil otherwise),
`title` ("Speechmatics Standard" …), `providerModel` (`standard`/`enhanced`;
`universal-streaming-english`/`universal-3-6-pro`).

**Meeting store (`~/.config/mini-whisper/meetings/`)**

```
meetings/
  index.json                     [{id, title, startedAt, endedAt, duration, mode, app, engine,
                                   speakerCount, costUSD, hasSummary, audioBytes, excerpt}]
  <uuid>/
    meeting.json                 Meeting metadata (below)
    segments.jsonl               one Segment per line, append-only while recording
    notes.jsonl                  one Note per line
    audio.m4a                    AAC 16 kHz mono, optional
```

`Meeting` (`meeting.json`): `id: UUID`, `title`, `startedAt: Date`, `endedAt: Date?`,
`durationSeconds: Double` (excludes paused spans), `mode: "remote"|"in-room"`, `app: String?`,
`engine: MeetingEngine`, `userName: String`, `speakers: [SpeakerLabel]`, `markers: [Marker]`,
`summary: Summary?`, `billing: {engineSeconds, diarizationSeconds, costUSD}`, `schema: 1`.

`SpeakerLabel`: `id: Int` (1-based, stable), `name: String` ("Speaker 3" until renamed),
`isUser: Bool`, `providerKeys: [String]` (e.g. `"2:S1"` = session index 2, provider label S1).

`Segment` (one jsonl line): `id: UUID`, `speaker: Int` (SpeakerLabel.id), `start: Double`,
`end: Double` (meeting seconds), `text: String`, `words: [{t: String, s: Double, e: Double}]`,
`session: Int`, `providerLabel: String?`, `turnOrder: Int?`, `edited: Bool`, `pinned: Bool`
(manual reassignment; wins over revisions). Text edits and reassignments rewrite the whole
`segments.jsonl` atomically (write temp, rename), which is bounded by one meeting's size.

`Note`: `id`, `time: Double` (meeting seconds of first keystroke), `text`, `createdAt`.
`Marker`: `kind: "gap"|"paused"|"sleep"`, `start`, `end`, `reason: String?`.
`Summary`: `text: String` (the model's Markdown, four sections), `model`, `createdAt`,
`inputTokens`, `outputTokens`, `costUSD`.

Writes: `MeetingStore` creates `<uuid>/` with 0700 and each file with 0600, appends segments and
notes as they arrive (one `FileHandle` per file, flushed per line), rewrites `meeting.json` on
rename, pause, stop, summary and reassignment, and rebuilds the `index.json` entry from
`meeting.json` plus the first segment line on every `meeting.json` write. On load the store
tolerates a malformed jsonl line by skipping it (as `HistoryStore` does) and rebuilds a missing
`index.json` by scanning folders.

**Pricing (`MWUsage/Pricing.swift`)** — `perMinute` gains `speechmatics_enhanced: 0.013333`,
`assemblyai: 0.0025`, `assemblyai_pro: 0.0075`, `assemblyai_diarization: 0.002`, and `speechmatics`
moves from 0.0067 to 0.0075 (the current Speechmatics list price, $0.45/h; `PricingTests.swift:20`
and `:94` change accordingly — this is a deliberate correction of a stale constant, not a no-op).
`perMTok` gains `claude-sonnet-5-5_in: 2.00`, `claude-sonnet-5-5_out: 10.00`.

**Keychain** — two new generic-password accounts under service `mini-whisper`:
`assemblyai-api-key`, `anthropic-api-key`.

**Prompt file** — `summary_prompt.txt` beside `prompt.txt`, seeded from
`App/Resources/default_summary_prompt.txt`.

### 5.3 Interfaces

**MWStreaming**

```swift
public struct AdapterEmitter {
    public enum Emission: Sendable, Equatable {
        case partial(String)
        case final(String)
        case segment(TranscriptSegment)                 // new
        case speakerRevision([SpeakerRevision])         // new
        case sessionLimit(SessionLimit)                 // new
    }
}
public enum SessionLimit: Sendable, Equatable { case expiresAt(Date), warning }
public struct TranscriptSegment: Sendable, Equatable {
    public var text: String
    public var words: [TranscriptWord]                  // text, start, end (seconds from session audio origin)
    public var speaker: String?                         // provider label, nil when diarization is off
    public var turnOrder: Int?                          // AssemblyAI only
    public var start: Double; public var end: Double
}
public struct SpeakerRevision: Sendable, Equatable { public var turnOrder: Int; public var speaker: String; public var words: [TranscriptWord] }

public protocol TranscriptSink: AnyObject, Sendable {
    func onPartial(_ text: String)
    func onFinal(_ text: String)
    func onEngineError(_ error: any Error)
    func onSegment(_ segment: TranscriptSegment)        // default: no-op
    func onSpeakerRevision(_ revisions: [SpeakerRevision]) // default: no-op
    func onSessionLimit(_ limit: SessionLimit)          // default: no-op
}
```

`WebSocketEngine.apply` (`WebSocketEngine.swift:287-296`) handles the three new cases at both
switch sites: a `.segment` calls `sink.onSegment` only — every adapter emits the matching `.final`
beside it, so the assembler's text comes from `.final` alone and `StreamSink` and dictation callers
keep working unchanged; `.speakerRevision` calls `sink.onSpeakerRevision`; `.sessionLimit` calls
`sink.onSessionLimit`.

`SpeechmaticsAdapter.init(apiKey:hints:diarization: Bool = false, model: String = "standard")`
adds `"diarization": "speaker"`, `"speaker_diarization_config": {"max_speakers": 10}` and
`"model": model` (the adapter sends no `operating_point` today; `model` is the current field and
`operating_point` its deprecated alias) to `transcription_config` when `diarization` is
true, and on `AddTranscript` emits one `.segment` per run of consecutive `results` sharing
`alternatives[0].speaker` (`UU` → `nil`), with `start_time`/`end_time` per word, in addition to the
existing `.final`. A `Warning` with `type: "session_timeout"` emits `.sessionLimit(.warning)`. With
`diarization == false` behaviour is byte-identical to today.

`AssemblyAIAdapter(apiKey:hints:model:speakerLabels:formatTurns:)`: url
`wss://streaming.assemblyai.com/v3/ws?speech_model=…&encoding=pcm_s16le&sample_rate=16000[&speaker_labels=true&max_speakers=10&speaker_labels_revision_interval_ms=300000][&format_turns=true][&keyterms_prompt=<JSON array>]`,
header `Authorization: <key>`, `targetRate` 16000, binary PCM chunks of 100 ms, `endMessages` =
`{"type":"Terminate"}`, `drainAfterComplete` true. `handle`: `Begin` → stores `expires_at` (Unix
seconds) and emits `.sessionLimit(.expiresAt(date))`; word `start`/`end` arrive in milliseconds and
are converted to seconds; `Turn` with `end_of_turn == false` → `.partial(transcript)`; `Turn` with
`end_of_turn == true` and (`turn_is_formatted` or `formatTurns == false`) → `.final(transcript)`
plus `.segment` (words with `speaker`, `turnOrder = turn_order`); `SpeakerRevision` →
`.speakerRevision`; `Termination` → complete. The expiry reaches `SessionSupervisor` through
`TranscriptSink.onSessionLimit`: the supervisor holds only `any StreamingEngine`, so it cannot read
the adapter. For dictation (`EngineName.assemblyai`) the factory builds it with
`model: "universal-streaming-english"`, `speakerLabels: false`, `formatTurns: true` and
`HintSerializer.assemblyAIKeyterms(hints)` (≤100 terms, ≤50 chars each, longer ones skipped and
reported like the Speechmatics cap).

`EngineFactory`: `make` gains `.assemblyai` at `:49` and `:110-114`; `KeyAccount(engine:)` at
`:152-155` maps `.assemblyai → .assemblyai`; `EngineNotice.label` gains `"AssemblyAI"`. New
`public func makeMeeting(_ engine: MeetingEngine, key: String, hints: RecognitionHints) -> any StreamingEngine`
returns a `WebSocketEngine` over `SpeechmaticsAdapter(diarization: true, model:)` or
`AssemblyAIAdapter(speakerLabels: true, formatTurns: engine == .assemblyaiStreaming)`.

**MWAudio**

```swift
public actor AudioCaptureEngine {
    public func holdRunning(_ held: Bool)                      // suppresses idle stop and sleep stop while true
    public func attachMeetingListener(_ l: (any BufferListener)?) // continuous, never accumulates into snapshot
    public func setVoiceProcessing(_ on: Bool) throws           // forwards to backend; reapplied after reinstall
}
// AudioBackend gains `func setVoiceProcessing(_ on: Bool) throws`; AVAudioEngineBackend stops the
// engine, calls AVAudioInputNode.setVoiceProcessingEnabled, restarts and reinstalls the tap, because
// the flag can only change while the engine is stopped. FakeAudioBackend records the calls.
@available(macOS 14.2, *)
public final class SystemAudioTap: @unchecked Sendable {
    public init(excluding pid: pid_t, clock: any Clock)
    public func start(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws   // creates tap + private aggregate, IOProc
    public func stop()
    public var events: AsyncStream<SystemAudioTapEvent>          // .defaultOutputChanged, .stopped(Error)
}
public final class AACFileWriter { init(url: URL, sampleRate: 16000) throws; func write(_ pcm16: Data) throws; func writeSilence(seconds: Double) throws; func finish() throws }
```

`SystemAudioTap` builds `CATapDescription(monoGlobalTapButExcludeProcesses: [ownProcessObject])`
with `isPrivate = true`, `muteBehavior = .unmuted`, creates a private aggregate device whose
`kAudioAggregateDeviceTapListKey` holds the tap UID with drift compensation, installs an IOProc
converting to 16 kHz mono float, and on `kAudioHardwarePropertyDefaultOutputDevice` change
tears down and rebuilds (emitting `.defaultOutputChanged`, which the controller turns into a gap
marker only if the rebuild takes longer than 2 s).

**MWMeetingPipeline**

```swift
public final class MeetingController {
    public init(deps: MeetingDependencies, config: ConfigStore, clock: any Clock)
    public var events: AsyncStream<MeetingEvent>
    public func start(mode: MeetingMode, title: String) async throws   // .remote / .inRoom
    public func pause() async; public func resume() async throws; public func stop() async
    public func rename(speaker: Int, to: String) async
    public func addNote(_ text: String, firstKeystrokeAt: Double) async
    public func edit(segment: UUID, text: String) async               // stopped only
    public func reassign(segment: UUID, to speaker: Int) async        // stopped only
    public func summarise() async                                      // only when summary == nil
}
public enum MeetingEvent: Sendable, Equatable {
    case state(MeetingState)                 // idle, starting, recording, paused(reason), stopping, stopped
    case segmentAdded(Segment), segmentUpdated(Segment), partial(String, speaker: Int?)
    case speakers([SpeakerLabel]), marker(Marker), note(Note)
    case connection(ConnectionState)         // connected, reconnecting(attempt), rolledOver
    case elapsed(Double), cost(Double), captureHint(String?)
    case summary(SummaryState)               // none(reason), writing, ready(Summary), failed(String)
    case systemAudio(SystemAudioState)       // on, unavailable(reason), silentHint
}
```

`MeetingDependencies` carries the `AudioCapture`, a `SystemAudioTapFactory` (protocol: `make(excluding:) -> any SystemAudioTapping`, nil below 14.2), the `EngineProvider`,
`SecretStore`, `MeetingStore`, `Summarizing`, `UsageRecording`, a `SummaryPromptProviding`
(`func summaryPrompt() throws -> String`, implemented by `PromptFiles`; defined here because
`MWPipeline.PromptProviding` is not visible to this target), `frontAppName: @Sendable () -> String?`
(the app reads `NSWorkspace.shared.frontmostApplication` when the chooser opens), `userName:
@Sendable () -> String` (`meeting_user_name` or `NSFullUserName()`), `platform: PlatformInfo` and
the `Clock`. `PlatformInfo` (`MWStreaming/PlatformInfo.swift:4`) today carries only `osMajor`; it
gains `osMinor` (from `operatingSystemVersion.minorVersion`) and
`supportsSystemAudio: Bool { osMajor > 14 || (osMajor == 14 && osMinor >= 2) }`.

`SpeechGate` (mic VAD): frames of 20 ms; speech when RMS > noise floor × 4 and > −45 dBFS for 3
consecutive frames; silence after 300 ms below threshold; the noise floor is the running 5th
percentile over the last 10 s. It records `[SpeechSpan]` with meeting-time bounds in a ring buffer
covering the last 10 minutes. Pure function on sample arrays, no clock dependency except span
stamping.

`SpeakerAttributor.attribute(_ segment: TranscriptSegment, spans: SpeechGate.View, registry: SpeakerRegistry) -> [Segment]`:
for each word, `isUser = span overlap ≥ 50 % of the word's duration`; adjacent words with the same
outcome and provider label form one `Segment`. Then per provider label in the segment's session,
if ≥ 70 % of that label's words so far fell inside speech spans, the label is bound to the user and
all its words become the user's (this absorbs words the gate missed). In an in-room meeting the
gate is not consulted. Deterministic given its inputs.

`SpeakerRegistry`: maps `(session, providerLabel)` → `SpeakerLabel.id`, allocating the next free
number on first sight; `user` is id 0 with `isUser = true`; renames change `name` only;
`merge(a, b)` on rename-to-existing-name re-points `providerKeys` and rewrites segments.

`SessionSupervisor`: owns one `StreamingEngine` at a time, exposes `feed(_:)`; on
`onEngineError` or a terminal close before `stop` it schedules a reopen after backoff
`[1, 2, 4, 8, 15, 30]` s (then 30 s forever), increments `session`, records `sessionAudioOrigin`
(meeting seconds at first fed buffer of the new session) and emits `.connection(.reconnecting(n))`;
the first `.segment` after a reconnect emits a `gap` marker from the last segment's end to that
segment's start. Rollover: a timer at `expiresAt − 60 s` (AssemblyAI) or a Speechmatics `Warning`
message announcing the session limit (`type: "session_timeout"`, the 45/30/15-minute warnings
before its 48 h cap), both delivered as `onSessionLimit`, opens the next session first, then finishes the old one with
`finish(timeout: 5 s)`; segments from the old session drain into the same registry. Audio fed while
no session is open is dropped from streaming (the recorder still writes it). All timing via `Clock`.

`AudioMixer.mix(mic: [Float], system: [Float]) -> [Float]`: sum with a soft limiter (`tanh` above
0.9), both inputs already at 16 kHz mono; when one source has no buffer for a tick it contributes
zeros. The mixer runs on the mic callback cadence and pulls the latest system ring buffer.

`MeetingRecorder`: receives the mixed PCM (remote) or the mic PCM (in-room), writes AAC through
`AACFileWriter`, pads paused spans with `writeSilence` on resume, and is absent when
`meeting_keep_audio` is false.

`MeetingBilling`: `engineSeconds` accumulates fed audio seconds (Speechmatics bills audio
seconds; AssemblyAI bills connection-open seconds, which coincide here because the session is open
only while audio flows), live `cost = Pricing.meetingCost(engine:, seconds:, tokens: .init(),
overrides:)` = `s/60 × rate(pricingKey) + s/60 × rate(diarizationKey)`. On stop it calls
`UsageRecording.add(ProviderUsage(inputTokens: 0, outputTokens: 0, streamedSeconds: [pricingKey: s],
costUSD: cost))` (`MWUsage/UsageStore.swift:5-7`, `MWUsage/ProviderUsage.swift:2`) — the
diarization add-on is inside `cost`, because recording its seconds under a second key would double
the Today minutes (R18) — so `UsageStore` sums by key unchanged; after a summary it calls `add` again with the summary's
`inputTokens`/`outputTokens` and `costUSD = in/1e6 × rate("claude-sonnet-5-5_in") + out/1e6 ×
rate("claude-sonnet-5-5_out")`. `Pricing.meetingCost` lives in `MWUsage`, which already depends on
`MWConfig` where `MeetingEngine` is defined.

`Summariser`: builds the Messages request from the prompt file, the speaker names, the transcript
as `MeetingMarkdown.transcriptBody` and the notes list, both inside delimited data blocks
(`<transcript>…</transcript>`, `<notes>…</notes>`), calls `Summarizing.summarise(system:user:)`,
stores `Summary`, records tokens. Parameters: `model: "claude-sonnet-5-5"`, `max_tokens: 16000`,
`output_config: {"effort": "low"}`, `fallbacks: "default"` with header
`anthropic-beta: server-side-fallback-2026-07-01`, timeout 180 s, no automatic retry.

**MWTranscription**

```swift
public protocol Summarizing: Sendable { func summarise(system: String, user: String) async throws -> SummaryResult }
public struct AnthropicClient: Summarizing { public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) }
public struct SummaryResult: Sendable, Equatable { public var text: String; public var usage: TokenUsage; public var refusalCategory: String? }
```

`AnthropicClient` reads `content[]` blocks of `type == "text"` and joins them; `stop_reason ==
"refusal"` → `refusalCategory = stop_details.category`; HTTP ≠ 2xx → `APIError.httpStatus`.

**MWMeetings**

```swift
public actor MeetingStore {
    public init(directory: URL)                                    // …/meetings
    public func create(_ meeting: Meeting) throws
    public func append(_ segment: Segment, to id: UUID) throws
    public func append(_ note: Note, to id: UUID) throws
    public func update(_ meeting: Meeting) throws                  // rewrites meeting.json + index entry
    public func rewriteSegments(_ segments: [Segment], of id: UUID) throws
    public func load(_ id: UUID) throws -> LoadedMeeting           // meeting + segments + notes
    public func index() throws -> [IndexEntry]
    public func delete(_ id: UUID) throws; public func deleteAudio(_ id: UUID) throws
    public func audioURL(_ id: UUID) -> URL
}
public protocol MeetingReading: Sendable { func index() throws -> [IndexEntry]; func load(_ id: UUID) throws -> LoadedMeeting }
extension MeetingStore: MeetingReading {}
public enum MeetingMarkdown { static func transcript(_ m: LoadedMeeting, generator: String) -> String; static func summary(_ m: LoadedMeeting, generator: String) throws -> String }
public struct MeetingSearch { func search(_ query: String, in: [LoadedMeeting]) -> [SearchHit] }  // case-insensitive substring over title, segment text, notes, summary; up to 2 hits per meeting ordered transcript→note→summary by time
public enum TitleSanitizer { static func fileStem(_ title: String) -> String }               // "/" and ":" → "-", trim, collapse spaces, ≤ 120 chars
```

**MWAgentAccess**

`mini-whisper meetings list [--json]` → one line per meeting `id  date  time  duration  title`
(or the index JSON); `transcript <id>` and `summary <id>` → the exact Markdown of
`MeetingMarkdown`; `search <text> [--json]` → `id  time  source  snippet` lines. `<id>` accepts a
full UUID or an unambiguous prefix of ≥ 8 hex characters; invalid or ambiguous → exit 2.
`mini-whisper mcp` → `MCPServer(store:)` loop: read stdin line by line, each a JSON-RPC request;
respond to `initialize` (echo the client's protocol version when it is `2025-11-25` or
`2025-06-18`, capabilities `{tools: {}}`, `serverInfo {name: "mini-whisper", version}`),
`notifications/initialized` (no reply), `ping` (`{}`), `server/discover` (returns
`{resultType: "complete", capabilities: {tools: {}}, serverInfo, tools: [...]}`), `tools/list`,
`tools/call`; unknown method → `-32601`; a request carrying
`_meta["io.modelcontextprotocol/protocolVersion"]` other than `2026-07-28` → `-32022`. Tool
schemas: `list_meetings {}`; `get_transcript {id: string}`; `get_summary {id: string}`;
`search_meetings {query: string, limit?: integer ≤ 50}`; every result is
`{content: [{type: "text", text}], isError}`. Output is one JSON object per line with no embedded
newlines; logs go to stderr; EOF on stdin exits 0.

**App**

`main.swift`: before `NSApplication.shared`, `if let command = AgentCommand(arguments: CommandLine.arguments) { exit(command.run()) }`
where `AgentCommand` recognises first argument `meetings` or `mcp`, builds `MeetingStore` on the
same config directory, and runs `MeetingsCLI`/`MCPServer`. `SingleInstanceGuard` is not consulted
on this path (several CLI processes may coexist with the GUI).

`AppDelegate`: `bindings(from:)` adds `(.meeting, config.meeting_hotkey, "ctrl+alt+cmd+m")`;
`onAction` routes `.meeting` presses to `MeetingCoordinator.toggle()` and, while
`meetingCoordinator.isActive`, routes `.paste`/`.pasteSubmit` presses to
`router.show(error: "Dictation is off while a meeting is recording")` instead of the controller.
`MenuModel` gains actions `startMeeting`, `stopMeeting`, `showMeeting`, `meetings`, rendered as
*Start Meeting…* / *Meetings…* when idle and *Stop Meeting* / *Show Meeting…* / *Meetings…* when
active, above *History...*; `StatusItemController`'s action switch (`App/StatusItemController.swift:81-82`)
gains the four cases, each calling a new closure wired by `AppDelegate` to the
`MeetingCoordinator`. `SettingsModel.Section` gains `.meetings` with its `title` and `symbolName` cases
(`App/Settings/SettingsModel.swift:63-85`) and `SettingsView`'s section switch
(`App/Settings/SettingsView.swift:30-31`) gains `case .meetings: MeetingsSection(model: model)`.

`MeetingWindowController` (920×620, non-modal, one per active or opened meeting) hosts
`MeetingView` with the three states of the accepted mockup. Closing the window hides it; recording
continues; *Show Meeting…* reopens it. `MeetingsWindowController` (680×480) hosts
`MeetingsListView` as in the accepted list mockup; double-click or *Open* opens a
`MeetingWindowController` in the stopped state. `SettingsModel.Section.meetings` (title
"Meetings", symbolName `person.2.wave.2`) renders `MeetingsSection` as in the accepted settings mockup;
`KeysSection.rows` gains `(.assemblyai, "AssemblyAI")`, `(.anthropic, "Anthropic")`;
`SettingsModel.saveKey(_:value:)` validates the `sk-ant-` prefix for `.anthropic` (beside the
existing `sk-` check for `.openai`);
`HotkeysSection` adds `HotkeyCaptureField(title: "Meeting", binding: .meeting, model:)`;
`SettingsModel.handle(.captured)` and `stored(_:)` switch over `.meeting` → `config.meetingHotkey`;
`cloudEngines` gains `(.assemblyai, .assemblyai, "AssemblyAI", "Add an AssemblyAI key under Keys to enable")`;
`HistoryListModel.engineLabel` and `CorrectionsEditorModel.noun` gain `.assemblyai` ("AssemblyAI",
"terms"). `CommandLineToolInstaller.install()` writes the wrapper below through
`NSAppleScript("do shell script … with administrator privileges")` and reports success or the
error text in the row:

```sh
#!/bin/sh
APP="/Applications/Mini Whisper.app"            # baked at install time from Bundle.main.bundleURL
if [ ! -x "$APP/Contents/MacOS/Mini Whisper" ]; then
  APP=$(osascript -e 'POSIX path of (path to application id "com.ips.mini-whisper")' 2>/dev/null | sed 's:/$::')
fi
exec "$APP/Contents/MacOS/Mini Whisper" "$@"
```

The Claude Code row shows `claude mcp add --transport stdio mini-whisper -- mini-whisper mcp` when
the tool is installed, otherwise the same command with the full binary path in place of the
second `mini-whisper`; *Copy* puts it on the pasteboard.

`Info.plist` gains `NSAudioCaptureUsageDescription` ("Mini Whisper records the audio other apps
play during a remote meeting so it can transcribe the other participants."). No entitlement
change: process taps need none in a non-sandboxed app.

### 5.4 Export layout

Exactly as the accepted [Export Files](./mockups/mockup-v4-export-markdown.html) mockup.

Transcript file: front matter `title`, `id`, `date` (ISO), `start`, `end`, `duration` (quoted
`hh:mm:ss`), `mode` (`remote`/`in-room`), `app`, `engine` (title), `speakers` (names in order of
first appearance), `generator` (`Mini Whisper <version>`); then `# <title>`; a meta line
`<d MMMM yyyy> · <start>–<end> · <mode title> · <names>`; `## Transcript`; one paragraph per
speaker segment as `**<name>** · hh:mm:ss` on the first line and the text on the next; notes as
`> **Note** · hh:mm:ss · <text>`, gaps as `> **Gap** · hh:mm:ss–hh:mm:ss · connection lost, audio kept`,
pauses as `> **Paused** · hh:mm:ss–hh:mm:ss` (sleep pauses add ` · Mac slept`), all in time order.

Summary file: the same front matter minus `engine`, plus `summary_model`, `summary_at` (ISO 8601
UTC) and `transcript` (the sibling file name); `# <title>`; the meta line; the model's four
sections verbatim; `## Notes` as `- hh:mm:ss · <text>`; `---`; one footer line
`Summary by Claude Sonnet 5.5 at <HH:mm> from <n> minutes of transcript and <k> notes · transcript: <file>`.

The CLI prints exactly these strings; the save panel uses `NSSavePanel` with the suggested file
name and `.md` content type; *Export both* uses `NSOpenPanel` in folder mode.

### 5.5 Summary prompt

`default_summary_prompt.txt` (bundled, copied to `summary_prompt.txt` on first read):

> You summarise a meeting for the person who attended it. Write four sections with these exact
> headings: `## Summary`, `## Decisions`, `## Action items`, `## Open questions`. Summary is one
> short paragraph. Decisions, Action items and Open questions are bullet lists; an action item
> starts with the owner's name in bold when the transcript names one. Use the speaker names
> exactly as given. Do not invent names, decisions, owners or dates; when something was discussed
> but not settled, list it under Open questions. The attendee's own notes are provided separately
> and may be used as hints about what mattered, never as transcript. Answer in the language of the
> transcript.

The user message is `Speakers: <names>\n\n<notes>\n- hh:mm:ss · …\n</notes>\n\n<transcript>\n<transcript body>\n</transcript>`.
The system message is the prompt file's text. Transcript text longer than 600 000 characters
(≈150 k tokens) is truncated from the start with a leading line "[earlier part of the meeting
omitted]" so the request stays under the model's context; the UI meta line then notes "partial".

### 5.6 Control flow

**Start (remote).** Hotkey or menu → `MeetingCoordinator.toggle()` → chooser window
(`MeetingState.idle`) → *Start* → `MeetingController.start(mode: .remote, title:)`:
1. Resolve engine (`meeting_engine` or first with key) and key from `SecretStore`; no key →
   `start` throws `MeetingError.noEngineKey` (defensive: the chooser has already disabled Start).
2. `audioCapture.holdRunning(true)`, `setVoiceProcessing(true)`, `ensureRunning()`,
   `attachMeetingListener(controller.micListener)`.
3. If `PlatformInfo` ≥ 14.2: `SystemAudioTap(excluding: own pid).start { buffer in systemRing.push }`.
   The first IO start raises the TCC prompt; the controller cannot see the answer and proceeds.
   If `start()` throws, emit `.systemAudio(.unavailable(error))` and continue microphone-only.
4. `SessionSupervisor.open(engine: factory.makeMeeting(...))`, `sessionAudioOrigin = 0`.
5. `MeetingRecorder` opens `audio.m4a` when `meeting_keep_audio`.
6. `MeetingStore.create(meeting)`; emit `.state(.recording)`; the elapsed ticker (1 s on `Clock`)
   emits `.elapsed` and `.cost`.
7. Config: set `meeting_system_audio_explained = true` after the first remote start.

**Audio tick (remote).** Mic buffer arrives → `PCMConverter` to 16 kHz mono float → `SpeechGate.push`
(stamps spans in meeting time) → `AudioMixer.mix(mic, systemRing.take())` → `MeetingRecorder.write`
and `SessionSupervisor.feed` (as a 16 kHz mono float `AVAudioPCMBuffer`; `WebSocketEngine` converts
it to int16 and the adapter's `encodeChunk` frames it) → `MeetingBilling.add(seconds)`.
In-room: mic → recorder and supervisor directly; the gate is not run.

**Segment arrives.** `onSegment(seg)` → shift word times by `sessionAudioOrigin[seg.session]` →
`SpeakerAttributor.attribute` → `SpeakerRegistry` resolves labels → `MeetingStore.append` each
`Segment` → emit `.segmentAdded`; a first segment after a reconnect first emits a `gap` marker.
`onPartial(text)` → emit `.partial(text, speaker: gate.isSpeakingNow ? 0 : nil)`.

**Silence hint.** If, in a remote meeting, 60 s pass with speech spans on the mic but no system-
audio sample above −60 dBFS, emit `.systemAudio(.silentHint)` once; the view shows "No audio from
other apps yet. Check System Settings → Privacy & Security → Screen & System Audio Recording." with
a button to the pane.

**Pause / Resume.** `pause()` → `supervisor.close()` (finish 5 s, bill seconds), recorder notes the
pause start, tap keeps running, emit `.state(.paused(.user))` and a `paused` marker opened.
`resume()` → recorder `writeSilence(pausedSeconds)`, marker closed, `supervisor.open(...)` with a
new session index, `.state(.recording)`. `.systemWillSleep` from the backend → `pause()` with
`.paused(.sleep)`; wake does nothing.

**Device change.** `.configurationChanged` → `ensureRunning()` again (the capture engine already
reinstalls its tap) and `setVoiceProcessing(true)` reapplied; if more than 2 s of mic audio are
lost a `gap` marker with reason "input device changed" is written. `SystemAudioTap`
`.defaultOutputChanged` → rebuild; same 2 s rule.

**Stop.** `stop()` → `.state(.stopping)`; `supervisor.close()` drains finals (5 s); `holdRunning(false)`,
`setVoiceProcessing(false)`, `attachMeetingListener(nil)`, tap stopped, recorder finished;
`meeting.endedAt`, `durationSeconds`, `billing` written; `UsageRecording.add(_:)`;
`.state(.stopped)`; then `summarise()` if an Anthropic key exists, else `.summary(.none("No summary:
add an Anthropic key under Keys."))`.

**Summarise.** `.summary(.writing)` → `Summariser.run` → `.summary(.ready(summary))` and
`MeetingStore.update`; `APIError`/timeout → `.summary(.failed(message))`; refusal →
`.summary(.failed("Summary declined (<category>)"))` and no `Summary` stored, so the button stays.

**Second hotkey press.** While `.recording` or `.paused` → `stop()`; while the chooser is shown →
ignored; while `.stopping` → ignored.

**Rename.** `rename(speaker:to:)` → registry rename (merge if the name already exists) →
`rewriteSegments` when merged → `.speakers(labels)`; the view re-renders names from the registry.

**Agent read.** `mini-whisper meetings transcript <id>` → `MeetingStore.load` → `MeetingMarkdown.transcript`
→ stdout. The GUI's `MeetingStore` and the CLI's are separate processes reading the same files;
writes are atomic per file so a reader sees either the old or the new `meeting.json`.

### 5.7 Failure and edge cases

| Case | Behaviour |
|---|---|
| No Speechmatics or AssemblyAI key | Chooser Start disabled with the message; menu item still opens the chooser |
| Key revoked mid-meeting (4001/401-style close) | Supervisor retries with backoff forever; chip shows "Reconnecting (n)"; audio keeps recording; user may Stop; the stored audio stays for later use |
| System Audio Recording denied | Tap delivers silence; after 60 s of one-sided speech the hint appears; transcript shows only the user; summary still runs |
| macOS 14.0/14.1 | Remote card disabled "needs macOS 14.2"; in-room works |
| Tap creation fails (14.2+, e.g. no output device) | `.systemAudio(.unavailable)`; chip reads "System audio off"; meeting continues mic-only |
| AssemblyAI 3 h limit | Rollover at `expires_at − 60 s`; no gap marker when the overlap succeeded; labels continue via registry |
| Speechmatics 1 h without audio / 3 min idle | Cannot occur while recording (audio flows); while paused the session is closed anyway |
| Speechmatics 48 h cap warning | Treated as rollover trigger |
| Provider close 1008/1011/4005 etc. | All routed to reconnect path; the close reason is logged |
| Overlapping speech (remote) | One stream: the recogniser may garble; attribution follows the gate; accepted limitation (§6, §7) |
| Keyboard noise, loud room | Gate false positives limited by hysteresis and the 70 % label rule; residual errors fixed by reassignment |
| Diarizer merges two remote speakers | One Speaker N; user cannot split in this version; noted in README |
| Diarizer splits one speaker | Two numbers; user renames both to one name → merge |
| Rename to an existing name | Merge with confirmation sheet "Merge Speaker 3 into Marta?" |
| Reassignment then a `SpeakerRevision` arrives | Revisions never arrive after Stop (the session is closed); mid-meeting revisions re-map by `turnOrder`; `pinned` segments are never changed |
| Mac sleeps | Auto-pause with `.sleep` reason; marker "Paused (Mac slept)"; stays paused until Resume |
| Input device changes | Reinstall; gap marker if > 2 s lost |
| Window closed while recording | Hidden; menu shows *Show Meeting…*; Stop still works from hotkey/menu |
| Quit while recording | `applicationShouldTerminate` asks "A meeting is recording. Stop and quit?"; Stop runs without summary when the user confirms (summary can be requested later) |
| Disk full / write error | Segment append throws → `.error` event shows "Could not write the transcript (<reason>); recording continues in memory" and the controller keeps the last 10 000 segments in memory, retrying the append on the next segment |
| Anthropic 429/5xx/timeout | `.summary(.failed(APIError.description))` with the Summarise button |
| Anthropic refusal | "Summary declined (<category>)" with the button |
| Transcript empty at Stop | No summary request; panel "Nothing was transcribed." |
| Export summary with none | Save panel not shown; alert "This meeting has no summary yet." |
| Title with `/` or `:` | Sanitised stem; duplicate names handled by the save panel |
| Audio deleted | Row meta "Audio deleted"; nothing else changes |
| Corrupt `segments.jsonl` line | Skipped on load, counted in the log |
| Missing `index.json` | Rebuilt by folder scan on first list |
| Config `meeting_engine` names a tier without a key | Falls back to the first with a key; Settings shows the stored row disabled with its hint |
| Config `meeting_hotkey` unparsable | Falls back to the default combo (as `bindings(from:)` does today) |
| Meeting hotkey equals a dictation hotkey | New rule in `SettingsModel.handle(.captured)`: a combo equal to another binding's stored combo is refused with "Already used by Record" (no check exists today); a duplicate already stored in `config.json` is resolved by `bindings(from:)` dropping the meeting binding to its default |
| CLI bad id | exit 2, stderr "no meeting <id>" |
| MCP unknown method | JSON-RPC -32601; malformed JSON line → -32700 and the loop continues |
| MCP modern client (2026-07-28) | `server/discover` served; `initialize` also answered for older clients |
| Two CLI processes while GUI writes | Readers see complete files thanks to temp-and-rename writes |

### 5.8 Security

- Keys stay in the Keychain under the existing service; the AssemblyAI key travels only in the
  `Authorization` header to `streaming.assemblyai.com`, the Anthropic key only in `x-api-key` to
  `api.anthropic.com`, both over TLS; no key is logged, and `Log` records request sizes, status codes
  and close codes only.
- The transcript and notes enter the summary request as delimited data; the system prompt tells
  the model to treat them as content, not instructions. The summary is rendered as Markdown text,
  never executed or pasted anywhere automatically.
- Meeting files are 0600 inside a 0700 folder. Audio of other people is retained only when
  `meeting_keep_audio` is on, deletable per meeting, and the README states the retention and the
  consent responsibility.
- The CLI and MCP server are read-only by construction: `MeetingsCLI` and `MCPServer` are handed
  an `any MeetingReading` (index and load only), never the `MeetingStore`, so no write method is
  reachable from their code; `MWAgentAccess` links only `MWMeetings`, never audio, streaming or
  the pipeline, so no capture can start from an agent process. Ids are validated as UUID or hex prefix before any path is built, so no path traversal.
  MCP input is parsed with `JSONDecoder` into typed structs; unknown fields ignored; strings capped
  at 10 000 characters.
- The installer runs one `osascript` with administrator privileges that writes a fixed-content
  file to `/usr/local/bin/mini-whisper` and `chmod 755`s it; the content is built from
  `Bundle.main.bundleURL.path` with shell quoting via single quotes and `'\''` escaping; no user
  input reaches the script.
- `NSAudioCaptureUsageDescription` and the first-remote-start note make the second TCC prompt
  intelligible; the app never records the screen.
- Exports are written only where the save panel points.

### 5.9 Performance

- Audio: the mixer and gate run on the capture callback at 16 kHz mono (20 ms frames = 320
  samples); per-frame cost is a few microseconds. The system ring buffer holds 2 s. No sample
  accumulates beyond that: segments and audio go to disk as they arrive.
- Network: one WebSocket session; 100 ms chunks of int16 PCM (3.2 kB) → 32 kB/s upstream.
- Disk: AAC at 16 kHz mono ≈ 29 MB/h; `segments.jsonl` ≈ 1 MB/h; appends are line-sized.
- UI: the transcript view keeps segments in an array and renders merged paragraphs with a
  `LazyVStack`; partial text updates only the last paragraph. 20 000 segments (≈ 8 h) render
  without stutter in the mockup's layout.
- Search: `MeetingSearch` loads meetings lazily and searches on a background task with a 150 ms
  debounce; 200 meetings × 1 MB scan completes well under a second; no index is built.
- Summary: a 1 h meeting is ≈ 10–15 k input tokens; `effort: low` keeps latency to a few seconds.

### 5.10 Observability

- `Log.meeting` (new category) at info: start/stop with mode and engine, session open/close with
  close code and attempt number, rollover, pause/resume with reason, tap start/stop and default-
  output change, summary request size/status/tokens, export destination (path only), CLI/MCP
  command names. Debug adds gate state changes per second and attribution decisions per segment.
- The meeting window shows the live state that matters: connection chip, capture chip, elapsed,
  cost, summary state and reason.
- `UsageStore` rows (Today/Month) reflect meeting costs the moment a meeting stops.
- No metrics or remote telemetry exist in this app and none is added.

### 5.11 Compatibility / migration

- `config.json`: new keys are optional and preserved by the Python app through its unknown-key
  handling; this app preserves them through `extra` until it knows them.
- Dictation behaviour is unchanged: adapters emit a `.final` beside every `.segment` and `.segment`
  never reaches the assembler, so `StreamSink`, the assembler and the caption path need no change; `SpeechmaticsAdapter` with `diarization: false`
  is byte-identical on the wire.
- `Pricing.perMinute["speechmatics"]` changes 0.0067 → 0.0075; `UsageStore` stores each record's
  `costUSD` at write time, so only usage recorded after the update bills at the new rate and past
  Today/Month totals are unchanged.
- Keychain: two new accounts; existing items untouched.
- Meetings folder is new; nothing migrates. Deleting the app leaves the folder as it leaves
  `history.jsonl`.
- Homebrew cask: no stanza change; the CLI is installed from inside the app on request.
- macOS 14.0/14.1 keep the whole feature except remote mode; the tap class is guarded by
  `@available` and `PlatformInfo`.

### 5.12 Testing strategy

Unit (Swift Testing, fakes from `MWTestSupport`, every duration on `VirtualClock`):

- `MWConfigTests`: `meeting_*` keys round-trip and default; `MeetingEngine` raw values and
  pricing keys; `KeyAccount` raw values; `PromptFiles.summaryPrompt` seeds from the bundle.
- `MWUsageTests`: new pricing keys; `speechmatics` 0.0075 (update `PricingTests.swift:20`, `:94`);
  override of each new key; a meeting's seconds land once under its pricing key, so the Today
  minutes are not doubled.
- `MWHotkeysTests`: `BindingName.meeting` raw value; default combo parses; matcher distinguishes
  `ctrl+alt+cmd+m` from the two dictation combos.
- `MWStreamingTests`: `SpeechmaticsAdapter` with `diarization: true` emits `.segment`s split by
  speaker with word times (fixture from the vendor's documented `AddTranscript`), and without
  diarization is byte-identical to the current fixtures; `AssemblyAIAdapter` request URL and
  header, `Begin`/`Turn`/`SpeakerRevision`/`Termination` handling, `format_turns` gating,
  `keyterms_prompt` cap (≤100, ≤50 chars); `WebSocketEngine` routes `.segment` to `onSegment`
  only (the assembler's text comes from the accompanying `.final`), `.speakerRevision` to
  `onSpeakerRevision`, `.sessionLimit` to `onSessionLimit`; `EngineFactory.make`
  with `.assemblyai`, `makeMeeting` per tier; `EngineNotice.label` for `.assemblyai`.
- `MWAudioTests`: `holdRunning` suppresses idle stop and sleep stop on the virtual clock;
  `attachMeetingListener` receives buffers without growing the snapshot; `AACFileWriter` writes a
  decodable file and pads silence; `SystemAudioTap` is covered by a protocol fake
  (`SystemAudioTapFactory`) in the pipeline tests and by an opt-in integration test
  (`MW_INTEGRATION=1`) that starts a real tap for 2 s on 14.2+.
- `MWMeetingsTests`: store creates 0700/0600 files, appends, rewrites atomically, skips corrupt
  lines, rebuilds the index; `MeetingMarkdown` output equals golden files matching the accepted
  export mockup (transcript with note, gap, paused markers; summary with Notes and footer);
  `TitleSanitizer`; `MeetingSearch` hit ordering and 2-per-meeting cap.
- `MWMeetingPipelineTests`: `SpeechGate` on synthetic frames (speech onset after 3 frames,
  release after 300 ms, noise-floor adaptation); `SpeakerAttributor` (50 % word rule, 70 % label
  rule, in-room bypass); `SpeakerRegistry` (allocation, rename, merge, session reset);
  `SessionSupervisor` backoff sequence 1,2,4,8,15,30,30… on `VirtualClock`, gap marker on first
  segment after reconnect, AssemblyAI rollover at `expires_at − 60 s`, Speechmatics warning
  rollover, drop-while-closed; `AudioMixer` sum and limiter; `MeetingBilling` live and final
  figures for each tier; `Summariser` request body (model, max_tokens, effort, fallbacks header,
  delimiters, truncation at 600 000 chars) via `FakeHTTPTransport`, refusal and error mapping;
  `MeetingController` end-to-end on fakes: start→segments→pause→resume→stop→summary, sleep
  auto-pause, device change gap, quit prompt flag, second-press semantics, silence hint after 60 s,
  dictation lock flag.
- `MWTranscriptionTests`: `AnthropicClient` headers, body, text-block joining, refusal category,
  `httpStatus` mapping.
- `MWAgentAccessTests`: CLI argument parsing and exit codes; outputs equal `MeetingMarkdown`;
  `MCPServer` legacy handshake, `server/discover`, `tools/list` schema, each `tools/call`,
  -32601/-32700/-32022, no-newline guarantee, EOF exit, read-only (no write API reachable: compile-
  time via `MeetingReading`).
- `AppTests`: `MenuModel` items per meeting state; `SettingsModel.handle(.captured)` for
  `.meeting` including the duplicate-combo refusal; `PlatformInfo.supportsSystemAudio` for 14.1,
  14.2 and 15.0; `AgentCommand` recognises `meetings`/`mcp` and ignores `--debug`; wrapper script
  content and quoting; `TitleSanitizer` use in save panel names.

Integration (opt-in, `MW_INTEGRATION=1` plus provider keys in the environment): one 20 s
Speechmatics and one 20 s AssemblyAI diarized session against recorded two-speaker audio; one
Anthropic summary of a fixture transcript; the real tap smoke test.

Acceptance: a remote Zoom call of a few minutes produces a transcript with the user's name and
Speaker 1..N, a note at its time, a summary on Stop, two exported files matching the mockup, a
Meetings row with cost, a Today row increment, and `mini-whisper meetings transcript <id>`
printing the same Markdown.

## 6. Alternatives considered

- **Two provider sessions per remote call (mic and system audio separately).** Cleaner
  attribution and intact overlapping speech, at double the per-hour cost ($0.90/h). Rejected for
  this version after the interview: local mic-activity attribution recovers the user's label at
  $0.45/h; kept as a future improvement if attribution or overlap quality disappoints.
- **One mixed stream with the user as just another diarized speaker.** Rejected: the microphone
  already tells the app which words are the user's.
- **Provider multichannel input.** Neither Speechmatics RT nor AssemblyAI streaming accepts two
  channels; not available.
- **ScreenCaptureKit for system audio.** Requires Screen Recording permission and a capture
  session built for video; rejected in favour of Core Audio process taps, which need only the
  audio-capture permission.
- **Re-summarise and summary versions.** Dropped by the user; one summary per meeting.
- **Starting the meeting directly on hotkey press with the last mode.** Rejected for a chooser so
  the mode (and its permission note) is explicit every time.
- **App-path-only CLI (no installer).** Rejected for an *Install…* button writing a wrapper script,
  so `mini-whisper` works from any terminal and the MCP command is short.
- **A symlink in `/usr/local/bin`.** Not allowed by the house rules; a wrapper script also survives
  the app moving.
- **Fixed Speechmatics operating point and fixed AssemblyAI tier.** Rejected for four explicit
  rows with prices; the user wanted the choice visible.
- **Two Settings sections (Meetings + Agents).** Mocked up and rejected by the user for one
  Meetings section with a sub-heading.
- **Keeping provider sessions open while paused.** Rejected: it bills idle minutes and risks the
  idle timeouts; sessions close on pause and reopen on resume.
- **Keeping the transcript view in a monolithic controller.** Rejected for the gate / attributor /
  registry / supervisor split so each timing and attribution rule is a pure, separately tested
  unit.

## 7. Risks and issues

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Mixed-stream recognition garbles overlapping speech | Medium / medium | Known limitation stated in README; two-session mode kept as the fallback design (§6) |
| Mic gate false positives attribute remote words to the user | Medium / low | Hysteresis, 70 % label rule, voice processing on, per-segment reassignment; gate thresholds tuned on fixtures |
| Diarizer merges or splits speakers | Medium / medium | Rename-to-merge; reassignment; AssemblyAI revisions; documented |
| System Audio Recording denied or revoked silently | Medium / high | First-start note, 60 s silence hint with pane button, Settings shortcut, transcript still has the user |
| Process-tap API behaviour differs across 14.2–26 | Low / high | Integration smoke test; rebuild on output-device change; mic-only fallback on any tap error |
| Voice processing ducks or alters other apps' audio | Low / medium | Verified in the integration test that the tap still receives call audio; if ducking is observed, set the input node's other-audio ducking configuration to minimum |
| Provider contract drift (AssemblyAI is new to the app) | Medium / medium | Request-contract tests on fixtures; two engines; close codes all route to reconnect |
| Long meetings hit session limits or sleep | High / medium | Rollover 60 s early, backoff reconnect, auto-pause on sleep, gap markers, audio always kept |
| Cost surprise on long calls | Low / low | Running cost in the header; prices in Settings and README |
| Summary invents content | Medium / medium | Prompt forbids invention, notes passed separately, `effort: low`; the transcript sits below for checking |
| Sensitive recordings readable by any local process via the CLI | Medium / medium | 0600/0700 files; retention toggle; README statement; no network exposure |
| Speechmatics price constant change raises the cost of new dictations (past totals are stored and unchanged) | Certain / low | Called out in CHANGELOG; override available |
| Admin-privileged installer fails or is declined | Medium / low | Row shows the error; MCP command falls back to the full binary path |
| `index.json` and folders drift (manual deletion) | Low / low | Rebuild from folders when inconsistent |
| Legal exposure from recording others | Unknown / high for the user | README states the user's responsibility; no recording without an explicit Start |

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

- Ships as one release, 0.6.0, with CHANGELOG entries for the feature, the new permission, the two
  new keys, the AssemblyAI dictation engine, the Speechmatics price correction and the CLI/MCP
  surface. No feature flag: meeting mode is inert until the user presses the hotkey or picks the
  menu item, and remote mode is inert until a key exists.
- Implementation order for `/feature-plan`: config/keys/pricing → streaming extensions
  (Speechmatics diarization, AssemblyAI adapter, factory, dictation wiring) → audio
  (hold/listener, AAC writer, tap) → `MWMeetings` store and Markdown → pipeline components (gate,
  attributor, registry, supervisor, mixer, billing, summariser, controller) → `MWAgentAccess` and
  `main.swift` → App windows, Settings, menu, installer → README/CHANGELOG.
- Rollback: the release before it keeps working; config keys are ignored by older builds; the
  meetings folder is left in place.
- Communication: README section "Meetings" with prices per hour, permission steps, storage path,
  consent note and agent usage; the first remote start shows the permission note in-app.

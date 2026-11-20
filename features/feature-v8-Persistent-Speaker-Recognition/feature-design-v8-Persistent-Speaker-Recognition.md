# Persistent Speaker Recognition — Design v8

**Status:** Draft
**Date:** 2026-11-20
**Storm:** [feature-storm-v8-Persistent-Speaker-Recognition.md](./feature-storm-v8-Persistent-Speaker-Recognition.md)

## 1. Summary

Mini Whisper numbers meeting speakers afresh in every meeting and forgets a name given to "Speaker 2" when the meeting ends. This feature remembers the people the user names and names them in later meetings. It has two opt-in routes chosen by the meeting engine: Speechmatics voice identifiers under the two Speechmatics engines, and a bundled local voice model (WeSpeaker, Core ML) under the two AssemblyAI engines. A sure match is applied as a normal name; a weaker one is shown as a provisional name the user accepts, edits or dismisses. Only what the user confirms is learned. A People section in Settings lists who is remembered and forgets one person or everyone. It is for anyone who meets the same people repeatedly.

## 2. Goals and non-goals

- **Goals:**
  - A person named in one meeting is named, or suggested by name, in a later meeting on the same route, without retyping.
  - No name reaches a summary, an export, a chip, a search result or an MCP result unless it was applied as a sure match, accepted, or typed by the user.
  - Both routes are off by default. With both off the app sends, stores and shows what it does today.
  - The user sees everyone remembered in one place and can rename, merge and forget there.
  - On the local route no voice data leaves the Mac. On the Speechmatics route no person's name is sent.
  - The app credits WeSpeaker and Sparkle in a Credits window.
- **Non-goals:**
  - Naming speakers from what is said (v9; this design's `NameMatch.source` is the hook).
  - Enrolling voices from existing `audio.m4a`, back-filling earlier meetings, carrying people between routes, cross-checking Speechmatics with the local model.
  - Agents naming speakers; the MCP server and CLI stay read-only and never see voice data.
  - A "Who is this?" review of unnamed voices; thresholds that tune themselves (the match log is recorded only).
  - Recognition in test calls.
  - Verification on macOS 14: no hosted runner or local machine exists for it (§7).

## 3. Requirements

Routes and switches

1. `config.json` gains `voice_local_enabled` and `voice_speechmatics_enabled`, both `false` by default. The local route serves `assemblyai_streaming` and `assemblyai_pro`; the Speechmatics route serves `speechmatics_standard` and `speechmatics_enhanced`.
2. A meeting's route is active when its engine's switch is on at Start, the meeting is not a test call, and (local) the model loaded. With a route inactive: no buffer is allocated, no Speechmatics field is added to `StartRecognition`, no `voices.json` is written, and `meeting.json` gains no key.
3. Switching a route off takes effect at once for a running meeting: no further match is applied, nothing is learned or logged, and no sidecar is written at Stop. Switching it on applies from the next meeting. Thresholds are read at each evaluation; Speechmatics sensitivity at each session open.
4. A switch is disabled with the engine rows' key hint when its provider has no key. The local switch is disabled with "The voice model could not be loaded on this Mac." when the model fails to load.

Local route

5. Audio for voices comes from rolling in-memory buffers of `voice_buffer_seconds` (default 120): the system audio (other speakers) and the microphone (the user) in a remote meeting; the microphone in an in-room meeting.
6. A final segment with a provider label and at least 1.5 s of word audio yields turn vectors: its word spans (merged when gaps are 0.3 s or less, padded 0.05 s each side) are cut from the buffer, split into windows of at most 10 s, each window of at least 1.5 s looped to fill 160,000 samples and embedded with an all-ones mask. Output row 0, L2-normalised, 256 floats.
7. A provider key's voice is the normalised, seconds-weighted sum of its turn vectors. An AssemblyAI speaker revision moves a turn's vectors to its new key; nothing is re-embedded.
8. A key is evaluated after each new vector once it holds `voice_min_speech_seconds` (15) of speech, while its speaker is still named `Speaker <id>`, is not linked to a person, and is not the user. A person's score is the highest cosine between the key's voice and that person's stored local samples. Sure: best ≥ `voice_sure_threshold` (0.70) and best − runner-up ≥ `voice_margin` (0.10). Suggestion: best ≥ `voice_suggest_threshold` (0.50) with the same margin. Otherwise nothing. The runner-up is the best other person, or 0 when there is none. People the user rejected for that speaker are excluded. The user's own entry is a candidate only in in-room meetings.
9. A suggestion may be replaced by a later sure or suggested decision; a later "nothing" leaves it standing. An applied name is never withdrawn by the app.

Speechmatics route

10. With the route active each session's `speaker_diarization_config` adds `get_speakers: true`, `speaker_sensitivity` (default 0.80) and, when anyone is known for this tier, `speakers`: one entry per person, label `mw:<lowercase person UUID>`, one identifier (the person's newest for this tier), most recently heard people first, at most 50 entries. The list is rebuilt at every session open.
11. A segment whose provider label is `mw:<id>` of a known person makes a match for its key on first sight: a suggestion when that person has never been confirmed under Speechmatics, applied otherwise. An unknown id is an ordinary speaker.
12. Every `SpeakersResult` updates the meeting's identifiers per provider key. `GetSpeakers` with `final: false` is sent when the user links a speaker during a live meeting.
13. A `Warning` of type `speaker_id` removes the identifier it names from the store. The first one in a meeting shows "Speechmatics ignored some remembered voices. Rename those speakers to learn them again." once.

Names and learning

14. A suggestion never changes the speaker's `name`. Applying, accepting or renaming does.
15. Accept names the speaker after the suggested person. Edit, or a click on the provisional name, opens the rename popover with the suggested name selected. Dismiss returns the speaker to `Speaker N`. "Not <name>" on an applied name returns that voice to a `Speaker N`. After Dismiss, "Not <name>", or a rename to another name, that person is not offered for that speaker again in the meeting. Accepting asks no merge confirmation.
16. Recognition never changes a speaker the user named, a linked speaker, or the user.
17. Learning happens only on a confirmed link: an accepted suggestion or a manual rename, during the meeting or after Stop, while the meeting's route switch is on. A name the app applied by itself teaches nothing. A name matching `^Speaker \d+$` never creates a person.
18. A rename onto a name the People list holds (exact match after trimming) is that person. A new name creates a person.
19. The user's own voice is learned without a click while the route switch is on: from microphone turns in remote meetings (local), from the label the microphone gate bound to the user in remote meetings (Speechmatics), and from a speaker renamed to the user's name in the room (both).
20. A person holds at most 8 local samples, one per meeting. A new sample whose cosine with a stored one is 0.85 or more replaces the closest; otherwise it is added, and beyond 8 the oldest is dropped. A person holds one Speechmatics identifier per tier, the newest.
21. Each meeting keeps its speakers' voice data (vectors or identifiers, never audio) in `voices.json` in its folder, written at Stop, deleted with the meeting or by Forget.
22. After Stop, Accept, Edit, Dismiss and "Not <name>" work on a stored meeting; learning there uses the meeting's `voices.json`.

People, storage, credits

23. People live in `~/.config/mini-whisper/voices.json` (0600, atomic writes). Each match and each user action on a match appends a line to `~/.config/mini-whisper/voice-matches.jsonl`.
24. Settings gains a People section: list, Rename (future meetings only; a name another person has is refused), Merge into…, Forget, Forget everyone. Forget removes the person, their samples, their voice data in every past meeting and their match-log lines; names in transcripts stay as text. Forget everyone also removes every meeting's `voices.json` and the match log. All four actions are unavailable while a meeting is recording. The user's own entry has no Rename and cannot be merged into another.
25. A test call neither recognises nor learns, and shows no recognition control.
26. The model `wespeaker_v2.mlmodelc` is committed under `App/Resources/` and bundled. A Credits window, opened from About, credits it (CC BY 4.0) and Sparkle.

Non-functional

27. No log line carries a name, a vector, an identifier or transcript text. Speechmatics receives only opaque `mw:` labels.
28. Embedding runs off the capture thread and off the main actor. The capture tick does only a locked buffer append.
29. Swift 6 strict concurrency, macOS 14 target, no new third-party dependency; `MiniWhisperCore` imports only system frameworks.

## 4. Background and context

- Speakers are numbered per meeting by `SpeakerRegistry`, keyed `"<session>:<label>"` (`Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SpeakerRegistry.swift:41`); `rename` merges two speakers that share a name, into the user when either is the user (`:73`). Names live only in `Meeting.speakers` (`MWMeetings/MeetingModel.swift:130`, `:189`).
- The user is recognised only in remote meetings, by the microphone gate (`MWMeetingPipeline/SpeakerAttributor.swift:34`); in the room the gate is not consulted.
- The audio tick `MeetingAudioPath.feed` (`MWMeetingPipeline/MeetingAudioPath.swift:52`) takes the system audio at `:66` and mixes at `:71`; the mix is what the provider hears, sample for sample, so provider word times index both streams.
- `MeetingController` attributes and stores each segment in `add` (`MWMeetingPipeline/MeetingController.swift:222`), applies revisions in `revise` (`:256`), renames in `rename(speaker:to:)` (`:536`), stops in `stop` (`:479`) and opens stored meetings in `open` (`:641`).
- `SessionSupervisor.install` builds each session through `MeetingEngineProviding.makeMeeting` (`MWMeetingPipeline/SessionSupervisor.swift:218`, `MWStreaming/EngineFactory.swift:155`). `SpeechmaticsAdapter.openMessages` sends only `max_speakers` today (`MWStreaming/Adapters/SpeechmaticsAdapter.swift:35`) and handles only the `session_timeout` warning (`:85`).
- `WebSocketEngine` can send only audio and the end message (`MWStreaming/WebSocketEngine.swift:26`); its `apply` switches over every emission twice (`:291`).
- Summaries, exports, the CLI, MCP and search read `SpeakerLabel.name` (`MWMeetings/MeetingMarkdown.swift:179`, `MWMeetingPipeline/Summariser.swift:126`, `App/Search/SearchModel.swift:186`), so a suggestion that leaves `name` alone stays out of all of them.
- Config keys are declared, decoded and encoded in three places (`MWConfig/Config.swift:192`, `:228`, `:286`).
- UI: the Engine card (`App/Settings/MeetingsSection.swift:30`), the Settings sections (`App/Settings/SettingsModel.swift:69`, `App/Settings/SettingsPage.swift:11`), the transcript header and rename popover (`App/Meeting/TranscriptView.swift:99`, `:213`), About (`App/AboutView.swift:4`).
- Research: [`speaker-persistence.md`](../../speaker-persistence.md). Its claim of three clips per call is wrong; the model reads one clip and three masks.

Measured during this design (2026-11-20, macOS 26.6.1):

| Finding | Value |
|---|---|
| Model load, inference | 0.2 s, 21 ms per call |
| Waveform rows 1–2 | Not read: one 10 s clip per call |
| Silence-padded clip | Does not separate voices; a clip looped with the speaker's own speech does |
| Speech needed (synthetic voices) | 3 s: same voice ≥ 0.82, others ≤ 0.59 |
| Gain | Embedding unchanged at ×0.1 and ×0.01 |
| Real meetings (18 meetings, 57 speakers) | Same name across meetings 0.79–0.94; different named speakers in a meeting ≤ 0.41; different names across meetings p95 0.42 |
| Per-turn vectors vs pooled 10 s windows | Same (median 0.94 both) |
| At 20 s with 0.70 / 0.50 / 0.10 | 77% of known speakers named outright, 5% suggested, 0% wrong |
| Speechmatics tiers | Standard identifiers are refused by Enhanced: `Warning` `speaker_id`, "identifier '1', speaker '1' - reason: identifier from an incompatible model" |
| Speechmatics `SpeakersResult` | Arrives before `EndOfTranscript`; a mid-session `GetSpeakers` is answered at once; identifiers are 1,564 characters and differ on every request |
| Speechmatics labels | `mw:<uuid>` accepted and returned in `speaker` and in `SpeakersResult` |
| Speechmatics sensitivity | At default, 0.2 and 0.5 an unknown voice was named as a similar enrolled one; at 0.8 and 1.0 it stayed `S1` |
| Hosted macOS 14 runners | Retired 2 Nov 2026; `macos-15` is the oldest |

## 5. Design

### Architecture / components

A new core module `MWVoices` holds everything about people and matching. The meeting pipeline gains an audio buffer and a recogniser; the streaming layer gains the Speechmatics identification wire. Dependencies stay downward: `MWVoices` → `MWMeetings`, `MWConfig`, `MWSupport`; `MWMeetingPipeline` → `MWVoices`.

| Component | Module | Responsibility | Depends on |
|---|---|---|---|
| `VoiceRoute`, `VoiceSettings` | MWConfig | Route of an engine; the eight settings; slider mapping | — |
| `VoiceVector`, `NameMatch`, `MeetingVoices` | MWMeetings | Stored shapes; `SpeakerLabel` additions | — |
| `MeetingStore` (extended) | MWMeetings | Reads, writes, deletes a meeting's `voices.json` | — |
| `VoiceStore` | MWVoices | Owns `voices.json`: people, samples, rename, merge, forget | `SampleSet` |
| `SampleSet` | MWVoices | Pure: the 8-sample, 0.85 rule | — |
| `VoiceMatcher` | MWVoices | Pure: probe + people + settings → none, suggestion, sure | — |
| `VoiceWindow` | MWVoices | Pure: word spans → speech samples → 10 s windows | — |
| `VoiceEmbedding`, `CoreMLVoiceEmbedder` | MWVoices | One window → `VoiceVector`; lazy model load | Core ML |
| `SpeechmaticsEnrolment` | MWVoices | Pure: people + tier → the `speakers` list | — |
| `MatchLog` | MWVoices | Appends and trims `voice-matches.jsonl` | — |
| `VoiceScrubber` | MWVoices | Removes a person's (or all) voice data from meetings on disk | `MeetingStore` |
| `VoiceSessionConfig`, adapter and engine additions | MWStreaming | Speechmatics `speakers`, `GetSpeakers`, `SpeakersResult`, `speaker_id` warning | — |
| `VoiceAudioBuffer` | MWMeetingPipeline | Lock-guarded rolling audio by meeting time | — |
| `VoiceRecogniser` | MWMeetingPipeline | Actor: turn vectors per key, evaluation | `VoiceWindow`, `VoiceEmbedding`, `VoiceMatcher` |
| `SpeakerRegistry` (extended) | MWMeetingPipeline | suggest, apply, accept, dismiss, detach, link | — |
| `MeetingController` (extended) | MWMeetingPipeline | Wires the route into Start, segments, rename, Stop, open | all above |
| Settings, People, transcript, Credits | App | The four accepted surfaces | models below |

`MWVoices` is one module, not several, because its parts share the `Person` type and are each a small pure type or one actor; splitting further would add targets without adding a test seam.

### Data model

**Config** (`MWConfig/Config.swift`; each key added to `Key`, `Key.all`, `init(from:)` with `try?`, and `encode`):

| Key | Default | Range (clamped in `validated()`) |
|---|---|---|
| `voice_local_enabled`, `voice_speechmatics_enabled` | `false` | — |
| `voice_sure_threshold` | 0.70 | 0.50–0.95 |
| `voice_suggest_threshold` | 0.50 | 0.30–0.90, and never above the sure threshold |
| `voice_margin` | 0.10 | 0.00–0.30 |
| `voice_min_speech_seconds` | 15 | 5–60 |
| `voice_buffer_seconds` | 120 | 60–300 |
| `voice_speechmatics_sensitivity` | 0.80 | 0.00–1.00 |

`Config.voice: VoiceSettings` exposes them. The slider has steps 0 (Cautious) to 10 (Eager), `p = step / 10`: sure `0.80 − 0.20p`, suggestion `0.60 − 0.20p`, margin `0.15 − 0.10p`, minimum speech `25 − 20p` s, sensitivity `0.95 − 0.30p`. Step 5 is the default. `VoiceSettings.step` is the step whose five values all equal the stored ones (±0.005, ±0.5 s), else `nil` (Custom). Buffer length is not on the slider.

**`meeting.json`** — `SpeakerLabel` gains three fields with a hand-written `Codable`: decoded with `decodeIfPresent`, encoded only when set or non-empty, so a meeting without recognition is written as today. `Meeting.schema` stays 1.

```swift
public struct NameMatch: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case suggested, applied }
    public var key: String        // provider key, "<session>:<label>"
    public var name: String       // the person's name when matched
    public var person: UUID?      // nil only for a future non-voice source
    public var source: String     // "voice"
    public var state: State
    public var score: Double?     // nil on the Speechmatics route
}
// SpeakerLabel
public var person: UUID?          // confirmed identity
public var matches: [NameMatch]   // at most one per provider key the speaker owns
public var rejected: [UUID]       // people never offered for this speaker again
```

**Meeting sidecar** `meetings/<id>/voices.json` (`MeetingVoices`, 0600):

```json
{"schema":1,"route":"local","model":"wespeaker_v2",
 "keys":{"1:A":{"seconds":212.4,"vector":"<base64 of 256 little-endian float32>"},
         "user":{"seconds":640.0,"vector":"…"}}}
{"schema":1,"route":"speechmatics","model":"standard",
 "keys":{"1:S2":{"seconds":88.1,"identifier":"…"}}}
```

`seconds` is the speech behind the entry. `"user"` is the user's microphone voice in a remote local-route meeting.

**People** `~/.config/mini-whisper/voices.json` (`VoiceStore`, 0600, temp file renamed into place; an unreadable file is moved to `voices.json.bak` and an empty store used):

```json
{"schema":1,"people":[{
  "id":"…","name":"Alice","isUser":false,"createdAt":"…","lastHeard":"…","aliases":[],
  "local":[{"meeting":"…","at":"…","seconds":212.4,"vector":"…"}],
  "speechmatics":{"standard":{"meeting":"…","at":"…","identifier":"…"}},
  "speechmaticsTrusted":true}]}
```

`aliases` holds the ids of people merged into this one, so Forget still finds their links in old meetings.

**Match log** `~/.config/mini-whisper/voice-matches.jsonl` (0600), one object per line: `at`, `meeting`, `key`, `route`, `event` (`suggested`, `applied`, `accepted`, `dismissed`, `rejected`, `renamed`), `person`, `score`, `runnerUp`, `seconds`. After an append that takes the file past 2 MB the oldest half of the lines is dropped.

### Interfaces

**Streaming** (`MWStreaming`):

```swift
public struct VoiceSessionConfig: Sendable, Equatable {
    public struct Speaker: Sendable, Equatable { public var label: String; public var identifier: String }
    public var speakers: [Speaker]
    public var sensitivity: Double
}
public struct ProviderSpeaker: Sendable, Equatable { public var label: String; public var identifiers: [String] }
public enum EngineCommand: Sendable { case requestSpeakers }

// AdapterEmitter.Emission adds
case speakers([ProviderSpeaker])
case identifierIgnored(label: String?, identifier: String?)   // nil when the warning cannot be parsed

// EngineAdapter adds (default nil)
func encode(_ command: EngineCommand) -> WebSocketMessage?
// StreamingEngine adds (default no-op)
func send(_ command: EngineCommand)
// TranscriptSink adds (default no-ops)
func onSpeakers(_ speakers: [ProviderSpeaker])
func onIdentifierIgnored(label: String?, identifier: String?)
// MeetingEngineProviding becomes
func makeMeeting(_ engine: MeetingEngine, key: String, hints: RecognitionHints, voices: VoiceSessionConfig?) -> any StreamingEngine
```

`SpeechmaticsAdapter(…, voices: VoiceSessionConfig? = nil)`:
- `openMessages`: with `voices`, `speaker_diarization_config` becomes `{"max_speakers":10,"get_speakers":true,"speaker_sensitivity":<s>,"speakers":[{"label":"mw:…","speaker_identifiers":["…"]}]}`; `speakers` is omitted when empty. With `nil` the message is byte-identical to today's.
- `encode(.requestSpeakers)` → `{"message":"GetSpeakers","final":false}`.
- `handle`: `SpeakersResult` → `.speakers`; `Warning` with `type == "speaker_id"` → the regex `identifier '(\d+)', speaker '(\d+)'` on `reason` gives 1-based indices into the adapter's own `speakers`, emitted as `.identifierIgnored(label:identifier:)`; no match emits it with `nil`s. `drainAfterComplete` stays zero: the result precedes `EndOfTranscript`.

`WebSocketEngine`: `QueueItem.command(EngineCommand)` is sent between audio chunks when the adapter encodes it and dropped otherwise or once finishing; both switches in `apply` gain the two cases (no transcript effect, forwarded to the sink).

**Pipeline** (`MWMeetingPipeline`):

```swift
public struct VoiceDependencies: Sendable {           // MeetingDependencies.voices, nil = feature absent
    public var store: VoiceStore
    public var embedder: any VoiceEmbedding
    public var log: MatchLog
}
// SessionSupervisor
init(…, voices: @escaping @Sendable () -> VoiceSessionConfig? = { nil })   // read in install(), under the lock
public func requestSpeakers()                                             // current session only
// SupervisorEvent adds
case speakers([ProviderSpeaker], session: Int)
case identifierIgnored(label: String?, identifier: String?)
// MeetingController adds
public func acceptSuggestion(key: String) async
public func dismissSuggestion(key: String) async
public func rejectMatch(key: String) async            // "Not <name>"
public func scrubVoices(people: Set<UUID>?) async     // nil = everyone; for a meeting a session holds
// MeetingEvent adds
case notice(String)                                   // an info line, once
case voiceData(active: Bool, keys: Set<String>)       // which keys have stored voice data
```

`SpeakerRegistry` additions, all pure:

| Method | Effect |
|---|---|
| `suggest(_ match)` | Stores the match on the key's speaker, replacing one with the same key. Name unchanged. |
| `apply(_ match, userName:)` | Only when the key's speaker is named `Speaker <id>`, unlinked and not the user. Renames it to `match.name` (to `userName` when the person is the user) through `rename`, so an existing speaker of that name absorbs it. The match is stored on the surviving speaker. Returns the `Merge`. |
| `accept(key:)` | Renames the speaker to the suggestion's name through `rename`, sets `person` on the surviving speaker, removes the match. Returns the person and the `Merge`. |
| `dismiss(key:)` | Removes the match; adds its person to `rejected`. |
| `detach(key:)` | "Not <name>". If the speaker owns only that key and has no `person`: its name returns to `Speaker <id>`, the match is removed, the person joins `rejected`. Otherwise the key leaves the speaker and a new speaker `Speaker <max id + 1>` owns it with the person in `rejected`; returns that move so the controller re-points segments. |
| `link(_ id, person:)` | Sets `person`; removes the speaker's matches; a removed match naming another person adds that person to `rejected`. |

**App**:

- `MeetingControlling` and `MeetingActions` gain `acceptSuggestion`, `dismissSuggestion`, `rejectMatch`; `MeetingCoordinator` gains `scrubVoices(people:) async -> Set<UUID>` (the meeting ids its sessions handled), modelled on `retitle` (`App/Meeting/MeetingCoordinator.swift:233`).
- `MeetingWindowModel.nameState(of paragraph) -> .plain | .suggested(NameMatch) | .applied(NameMatch)`, from the match stored for the paragraph's first segment's key; `.plain` in a test call. `learnsVoice(speaker:) -> Bool` is true when the meeting's route switch is on now (a closure the coordinator injects, reading the current config) and the meeting is live or `voiceData.keys` holds one of the speaker's keys.
- `SettingsModel`: `voice`, `voiceModelStatus` (`.ready` / `.failed`, from `CoreMLVoiceEmbedder.prepare()`, run once when the Meetings section first appears), `setVoiceEnabled(_:for:)`, `setVoiceStep(_:)`, `setVoice(_:for:)`, `resetVoiceTuning()`. `SettingsModel.Section` gains `.people` after `.meetings` (title "People", symbol `person.crop.circle`), handled in `title`, `symbolName` and `SettingsPage`'s switch.
- `PeopleModel` (`@Observable`): rows from `VoiceStore.changes`; `rename`, `merge(from:into:)`, `forget`, `forgetEveryone`; `isRecording`.
- `Credits.entries` (static data), `CreditsView`, `CreditsWindowController`.

**UI surfaces** (accepted mockups):

- Settings › Meetings › Engine: [mockup-v8-recognition-settings.html#in-engine-card](./mockups/mockup-v8-recognition-settings.html#in-engine-card) · https://claude.ai/artifact/DreQJ5XL5H9uoW1Ba5x7nE#in-engine-card
  - Each switch sits in an inset box under its two engine rows, a hairline between the providers: "Remember voices with Speechmatics", "Remember voices on this Mac".
  - The description under each switch is the disclosure, shown always: local — "Learns the voice of each speaker you name and names them in later meetings. Keeps a voiceprint per person, never audio, in ~/.config/mini-whisper/voices.json and in each meeting's folder. Nothing leaves this Mac."; Speechmatics — "Speechmatics returns a voice identifier for each speaker you name, and later meetings send those identifiers back so it can name them. Kept in ~/.config/mini-whisper/voices.json, never audio. Names are not sent."
  - A switch that is on while its provider is not the active engine adds a grey line: "Used when a Speechmatics engine is selected." (or AssemblyAI).
  - While any switch is on, a row closes the card: "How readily names are applied", the stock slider (accent tint) between "Cautious" and "Eager", a caption ("Balanced · applies a name at 0.70, suggests from 0.50"; step names Most cautious 0–1, Cautious 2–4, Balanced 5, Eager 6–8, Most eager 9–10), and a closed "Advanced" disclosure of six sliders with value read-outs: Sure match, Suggestion, Margin, Minimum speech, Audio buffer, Speechmatics sensitivity. A hand-set value gives the caption "Custom · set in Advanced", a hollow thumb and "Reset to Balanced". A value whose route is off is dimmed.
- Transcript: [mockup-v8-provisional-name.html](./mockups/mockup-v8-provisional-name.html) · https://claude.ai/artifact/5DFRtWDN6j4xJHCzdJgnrr
  - Suggestion: the suggested name with a question mark in the name's place (speaker colour, 13 px semibold, 1.5 px dashed underline), `Speaker N` in grey 12 px beside it, then the time. Three quiet small pills, right-aligned, on every paragraph of that speaker: Accept, Edit, Dismiss; grey label, no outline, label turning accent on hover or focus. Under 470 px of transcript width they move to their own line under the name.
  - Edit and a click on the provisional name open the rename popover titled "Name Speaker N (every segment)" with the suggested name selected.
  - Applied: a plain name; on hover or keyboard focus a quiet "Not <name>" appears after the time in reserved space.
  - Rename popover: one added line with a waveform mark, "This voice will be remembered as <name>.", shown when `learnsVoice` is true.
  - The Speechmatics notice is an info `StatusLine` under the live header.
  - In the room, a suggestion that is the user carries the user's name; Accept merges that speaker into the user.
- People: [mockup-v8-people.html](./mockups/mockup-v8-people.html) · https://claude.ai/artifact/QJMnNUJAimpTXG87RZY5fj
  - A tenth Settings section after Meetings. Lead line: "People you named in meetings while a Remember voices switch was on. Mini Whisper keeps a voiceprint or a Speechmatics identifier for each, never audio."
  - A card of rows sorted by last heard, newest first, under "Remembered voices · N". Row: name (14 px medium), a "You" chip on the user's entry, then "Local model · Speechmatics Standard · Speechmatics Enhanced · last heard <date>" for the routes that hold data.
  - Hover or focus shows quiet small pills in reserved space: Rename, Merge into…, Forget (red on hover). The user's entry has only Forget.
  - Rename: a popover with the name selected and "Past meetings keep the old name."; a taken name shows "<name> already exists. Use Merge into… instead." Merge into…: a menu of the other people, then the Dialog "Merge A into B?" — "B keeps the name and gets both voices. Past meetings are not changed." Forget: Dialog "Forget <name>?". Forget everyone: its own card row with an outlined red-label button and the Dialog "Forget everyone?".
  - Empty: the app mark, "No one yet", "Turn on Remember voices under Meetings, then name a speaker in a meeting. The people you name appear here.", and "Open Meetings Settings".
  - While a meeting records: an info line "A meeting is recording. Rename, merge and forget are available when it stops." and every action disabled.
- Credits: [mockup-v8-credits.html](./mockups/mockup-v8-credits.html) · https://claude.ai/artifact/EM2d3E1BrecQtS4QvdZ9Lc
  - About grows to 300 × 330 with a quiet small pill "Credits…" under the "Powered by" line.
  - Credits is a small window (standard title bar "Credits", fixed 460 × 440, scrolling content): the lead line "Mini Whisper includes the work of others." and one card with a row per component — name, what it does, who made it, licence line with a quiet button.
  - WeSpeaker voice model: "WeSpeaker ResNet34-LM by the WeSpeaker authors, as published by pyannote and converted to Core ML by Fluid Inference. Bundled as a modified Core ML conversion." CC BY 4.0, the address `creativecommons.org/licenses/by/4.0` as selectable text, "Open Licence…" opening it in the browser.
  - Sparkle: its copyright line and included parts; "Show Licence" unfolds the bundled licence text in a monospaced scrolling box.

### Design language

Follows [`DESIGN.md`](../../DESIGN.md) and its specimen ([`design/specimen.html`](../../design/specimen.html); the recorded artifact https://claude.ai/artifact/3iQhWG4jNhvrqA4EXTwHGh could not be read from this account, so the specimen was re-rendered locally only). Deltas recorded for this feature:

- Quiet pill used as a name or row action: `color.text.secondary` label turning `color.accent` on hover or focus, `color.recording` when destructive — pending v8 (decision 74).
- Small windows now include Credits — pending v8 (decision 75).
- Provisional name component — pending v8 (decision 76).

Everything else uses recorded tokens and components: Settings card, Setting row, Radio row, Switch, Status line, Dialog, Chip, Pill button, Pill menu, the stock slider as Sound › Volume uses it. The existing drift (the test call's Earlier runs sheet) does not touch these surfaces.

### Control flow

**Start** (`MeetingController.start`). After the config load: the route is active per requirement 2. Local: two `VoiceAudioBuffer`s (remote) or one (in-room) are created and handed to `MeetingAudioPath`; a `VoiceRecogniser` is created; the model is prepared in a task that does not delay Start. Speechmatics: the controller builds the enrolment from `VoiceStore` for the engine's tier into a lock-guarded box that the supervisor's `voices` closure reads at every `install`. `SpeechmaticsEnrolment` takes the people holding an identifier for the tier, orders them by `lastHeard` (the identifier's date when that is absent), newest first, and keeps the first 50. `.voiceData(active: true, keys: [])` is emitted. If the model's preparation fails, the local route becomes inactive for the meeting and the error in the table below is emitted.

**Audio tick** (`MeetingAudioPath.feed`, capture thread). While streaming and buffers exist: remote appends `system` and `mic` at `time`; in-room appends `mic`. Nothing else changes.

**Segment arrives, local** (`add`). After the segments are stored and emitted, each attributed segment with a provider label goes to `recogniser.ingest`. The recogniser picks the buffer (microphone for a user segment in a remote meeting or any segment in the room; system audio otherwise), builds windows, embeds them, files the vectors under the segment id and key, and evaluates the key (requirement 8) with the `VoiceSettings` and people read at that moment. A user segment in a remote meeting feeds the `"user"` key and is never evaluated. Decisions return to the main actor: a sure decision runs `registry.apply`, moves segments on a merge through the same code `rename(speaker:to:)` uses (extracted as `applyMerge`, behaviour unchanged), saves and emits; a suggestion runs `registry.suggest`, saves and emits `.speakers`. Each is logged. A decision is dropped when the switch is now off, the speaker is no longer default-named, or the same match already stands.

**Segment arrives, Speechmatics.** A new key whose label starts `mw:` is looked up in the session's enrolment; requirement 11 decides suggest or apply, through the same two registry calls.

**Revision.** `revise` tells the recogniser which segment ids changed key; it moves their vectors and re-evaluates both keys.

**Accept / Dismiss / Not <name>** (live or stopped). The controller runs the registry call, re-points segments when it returns a merge or a detach, persists segments and `meeting.json`, emits, logs, and updates the store. A detach moves the segments whose session and provider label form that key, whose speaker is the old speaker and which are not pinned. Then: Accept links (below); "Not <name>" on a Speechmatics match sets that person's `speechmaticsTrusted` to false.

**Rename, including Edit.** `rename(speaker:to:)` keeps today's behaviour, then: if the route switch is on and the name does not match `^Speaker \d+$`, the person is `store` find-or-create by name (the user's person when the surviving speaker is the user) and `registry.link` runs; otherwise `person` is cleared and matches removed. A rename over a suggested or applied match logs `renamed`.

**Link (Accept or rename).** For each affected person, the previous and the new one, the meeting's sample is recomputed: local — the seconds-weighted voice of every key owned by speakers linked to that person (the `"user"` key for the user in a remote meeting), stored through `SampleSet` when at least one vector exists, removed otherwise; Speechmatics — the identifier of the linked key with the most speech, stored as that tier's identifier, and `speechmaticsTrusted` set. Live on Speechmatics the controller first calls `supervisor.requestSpeakers()`; the sample is recomputed again when the `SpeakersResult` arrives. The enrolment box is rebuilt after every store change.

**SpeakersResult.** Identifiers are stored per `"<session>:<label>"`; samples of linked people are recomputed.

**Identifier ignored.** The named identifier is removed from its person through `VoiceStore.dropIdentifier`, the enrolment box is rebuilt, the count is logged, and `.notice` with requirement 13's text is emitted the first time in a meeting. An event without a label and identifier only emits the notice.

**Stop.** After the session events drain and before the last `saveMeeting`: if the switch is still on, the recogniser finishes its queue, the sidecar is written, the user's label is linked to the user's person (created on first use, named after the meeting's user name, `isUser: true`) when it has voice data — the `"user"` key with at least `voice_min_speech_seconds` of speech on the local route in a remote meeting, a provider key it owns otherwise — every linked person's sample is recomputed, and `lastHeard` is set for people linked or applied in the meeting. `.voiceData(active:keys:)` is emitted with the sidecar's keys.

**Open a stored meeting.** `open` reads the sidecar and emits `.voiceData`. Links made there recompute samples from it.

**People actions.** Rename and Merge change only `VoiceStore`. Merge feeds both people's local samples, oldest first, through `SampleSet` into the target, keeps the newer identifier per tier, ORs `speechmaticsTrusted`, and appends the source id and its aliases to the target's `aliases`. Forget: `VoiceStore.forget` returns the id and aliases; `MeetingCoordinator.scrubVoices` handles meetings its sessions hold; `VoiceScrubber` handles the rest on disk; `MatchLog.remove(people:)` rewrites the log. For each meeting a scrub removes the sidecar entries of provider keys owned by speakers linked to those ids, clears `person`, drops matches and `rejected` entries naming them, and deletes an emptied sidecar. Forget everyone deletes `voices.json`, every sidecar, every `person`, `matches` and `rejected`, and the log.

### Failure and edge cases

| Case | Behaviour |
|---|---|
| Model missing or fails to load | Local route inactive for the meeting; `.error("Voice recognition is off for this meeting: the voice model could not be loaded.")`; Settings disables the switch with the reason. |
| Embedding throws | That segment yields no vector; logged once per meeting at warning level. |
| Segment's audio older than the buffer, or in a gap | The available part is used; under 1.5 s yields no vector. |
| Segment without a provider label | Never embedded, matched or learned. |
| Rename to the name a speaker already has | A no-op, as today (`rename` returns before any link). An applied name therefore cannot be confirmed and teaches nothing. |
| Rename before enough speech exists | The link is recorded; the sample appears at the next recompute that finds a vector or identifier, at the latest at Stop. |
| App quits or crashes mid-meeting | No sidecar; links made live already updated the store; later renames in that meeting learn nothing. |
| Speechmatics session lost before a `SpeakersResult` | Its keys have no identifier; renaming those speakers learns nothing, and the popover line is absent after Stop. |
| `speaker_id` warning that cannot be parsed | Nothing is removed; the notice is still shown. |
| `voices.json` unreadable | Moved to `voices.json.bak`; empty store; logged. |
| A store, sidecar or log write fails | Logged; the meeting continues; the next write retries. A failed sidecar write emits `.error("Could not save this meeting's voice data (<reason>)")`. |
| Forget while a stored meeting is open | Its controller scrubs its own state and file. |
| Person renamed in People, old name typed later in a meeting | A new person is created; Merge into… joins them. |
| Two speakers accepted as one person | The registry merges them, as a rename does. |
| Switch turned off mid-meeting | Requirement 3. Speechmatics keeps sending `mw:` labels until the session ends; they are shown as `Speaker N`. |
| The user's entry forgotten | Learned again at the next remote meeting with the switch on. |

### Security

- Trust boundary: Speechmatics messages. `SpeakersResult` labels and identifiers are stored as opaque strings and only ever sent back to Speechmatics; a `mw:` label is acted on only when it parses to the UUID of a known person. Warning text is parsed with one anchored pattern and never logged or shown.
- Voice vectors and identifiers are biometric data about other people. They are stored 0600 beside meeting audio that already sits unencrypted there (the storm's decision), never leave the Mac on the local route, are never logged, and are removable in one place.
- Names are never sent to Speechmatics. The CLI and MCP server reach meetings through `MeetingReading`, which does not expose the sidecar or the store.
- No key handling changes. The model is loaded only from the app bundle.
- People names are user input shown as plain text; no name is interpolated into a path, a query or a prompt beyond the existing speaker-name use in summaries.

### Performance

- Capture tick: one locked append of the tick's samples per buffer. Memory: 120 s × 16 kHz × 4 bytes = 7.7 MB per buffer, two in a remote meeting.
- Embedding: about 21 ms per window, one to a few windows per final segment, on the recogniser actor.
- Matching: one cosine per stored sample (at most 8 per person).
- `StartRecognition` grows by about 1.6 KB per enrolled person, 80 KB at 50.
- Store and sidecar writes happen on user actions and at Stop, never per segment.
- Forget scans every meeting's `meeting.json` once, off the main actor.

### Observability

A new `Log.voice` category. Lines carry keys, scores, seconds and the first 8 characters of a person id; never names, vectors, identifiers or text: `match 1:A sure 0.83 (next 0.31) after 22 s`, `model loaded in 0.21 s`, `speechmatics dropped 2 identifiers (standard)`, `sidecar written: 6 keys`. The match log is the durable record. Nothing is alertable.

### Compatibility / migration

- No migration. New config keys take defaults; `meeting.json` files without the new fields decode as before; an older build ignores the new fields and files.
- `MeetingEngineProviding.makeMeeting` gains a parameter: its implementation (`EngineFactory`), its fakes (`FakeMeetingEngineProvider` and `AnnouncingProvider` in `SessionSupervisorTests.swift`) and its test callers (`EngineFactoryTests`, `MeetingEngineLiveTests`) are updated together. `SupervisorEvent`, `MeetingEvent` and `AdapterEmitter.Emission` gain cases: every `switch` over them is updated — `MeetingController.handle`, `MeetingWindowModel.apply`, both switches in `WebSocketEngine.apply`.
- `project.yml` adds the model as a folder reference in the resources phase (`type: folder`), excluded from the `App` source glob, so its internal files are copied as one directory.
- `THIRD_PARTY_NOTICES.md` at the repo root and `App/Resources/Sparkle-LICENSE.txt` (Sparkle 2.9.6's `LICENSE`, verbatim) are added.

### Testing strategy

Swift Testing; every type below is tested without the rest of the feature running. No real sleep.

| Component | Tests |
|---|---|
| `VoiceSettings`, `Config` | Defaults; clamps; suggestion never above sure; wrong-typed value reads as default; round-trip; each step's five values; `step` nil off-step. |
| `SpeakerLabel` coding | Old file decodes; a label without the new fields encodes to today's bytes; round-trip with all three. |
| `VoiceVector` | Base64 round-trip; cosine; weighted combine is unit length. |
| `SampleSet` | ≥ 0.85 replaces the closest; below adds; ninth drops the oldest; one per meeting. |
| `VoiceMatcher` | Each tier boundary; margin against the runner-up; single person; rejected excluded; user only when asked. |
| `VoiceWindow` | Span merging and padding; 10 s split; loop fill; under 1.5 s dropped; partial buffer. |
| `SpeechmaticsEnrolment` | Tier filter; order by last heard; cap at 50; label format; label → person. |
| `VoiceStore` | Find-or-create by name; rename refusal; merge (samples, identifiers, aliases, trust); forget returns ids; corrupt file backup; 0600. |
| `MatchLog`, `VoiceScrubber` | Append, trim past 2 MB, remove people; scrub one person and everyone over fixture meeting folders. |
| `SpeechmaticsAdapter` | `StartRecognition` unchanged with `nil`; fields with a config; `GetSpeakers` encoding; `SpeakersResult` and both warning forms from fixtures captured in this design's probe. |
| `WebSocketEngine`, `SessionSupervisor` | A command is sent between chunks; the two emissions reach the sink; `voices` is read at every install; `requestSpeakers` reaches only the current session. |
| `VoiceAudioBuffer` | Lookup across a gap; eviction at capacity; concurrent append and read. |
| `VoiceRecogniser` | With a fake embedder: vectors per segment; a revision moves them; evaluation waits for minimum speech; the user key is never evaluated. |
| `SpeakerRegistry` | suggest, apply (rename and merge), accept, dismiss, detach (both branches), link. |
| `MeetingController` | With fakes: sure applies and merges; suggestion leaves `name`; Accept, Dismiss, "Not"; rename links and learns; switch off mid-meeting; test call inert; sidecar at Stop; stored-meeting rename learns; inactive route leaves the Speechmatics wire and `meeting.json` unchanged. |
| App models | `MeetingWindowModel.nameState` and `learnsVoice`; `SettingsModel` voice setters and disabled reasons; `PeopleModel` actions and the recording lock; `Credits.entries`. |
| Model in the bundle (`AppTests`) | `Bundle.main` holds `wespeaker_v2.mlmodelc`; `CoreMLVoiceEmbedder` embeds four synthetic `say` clips from `AppTests/Fixtures`; same voice scores above 0.7, different below 0.7. |
| Integration (`MW_INTEGRATION=1`) | Speechmatics enrol-then-recognise with synthetic clips. |

Acceptance (manual): name a speaker in an AssemblyAI meeting with the local switch on; in a second meeting that person is named or offered within the first minute of their speech; a summary written while a suggestion is pending says `Speaker N`; Forget removes them from People and from both meetings' `voices.json`.

## 6. Alternatives considered

- The local model under all four engines — rejected in the storm: the brief wants Speechmatics' own route.
- Pooled 10 s windows per speaker instead of per-turn vectors — rejected: same scores on real audio, and pooled windows cannot follow an AssemblyAI revision without re-embedding.
- Raw 10 s windows with per-speaker masks (the model's native use) — rejected: needs pauses and overlaps handled; looped own-speech windows are measured and simpler.
- A running average per person instead of up to 8 samples — rejected: a headset and a room average into a voice that matches neither.
- Learning from names the app applied — rejected by the user: one unnoticed wrong match would teach the app the wrong voice.
- People's names as Speechmatics labels — rejected: sends third-party names off the Mac and collides on shared names.
- Two or three identifiers per person within the 50 — rejected by the user in favour of one each for 50 people.
- Sharing identifiers across Speechmatics tiers — rejected: observed to be refused.
- Downloading the model in CI — rejected by the user: builds would depend on the download.
- The model as a SwiftPM resource of `MWVoices` — rejected: adds a resource bundle to sign; the app bundle and an `AppTests` test cover it.
- Settings: a separate Speaker recognition card ([`recognition-card`](./mockups/mockup-v8-recognition-settings.html#recognition-card) · https://claude.ai/artifact/DreQJ5XL5H9uoW1Ba5x7nE#recognition-card) — not chosen: each switch would have to name its engines.
- Transcript: buttons beside a "Bob?" chip ([`inline-controls`](./mockups/mockup-v8-transcript-names.html#inline-controls) · https://claude.ai/artifact/KV5W5mdhULxgSAiNov6ehd#inline-controls) and one status line above the transcript ([`suggestion-line`](./mockups/mockup-v8-transcript-names.html#suggestion-line) · https://claude.ai/artifact/KV5W5mdhULxgSAiNov6ehd#suggestion-line) — not chosen in favour of the provisional name.

## 7. Risks and issues

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Defaults are calibrated on 18 of one user's remote meetings; in-room data is two speakers | Medium / wrong or missing names for other voices and rooms | Strict sure tier with a margin; suggestions never leave the transcript; the slider and Advanced; the match log for later calibration. |
| A wrongly applied name reaches a summary before the user notices | Low / a misattributed record | Sure needs ≥ 0.70 and a 0.10 lead where different people measured ≤ 0.62; "Not <name>" then Regenerate. |
| macOS 14 is not verified | Medium / the local route may not load there | The model declares macOS 13; a load failure disables the switch with a reason and leaves the app otherwise unchanged; a `macos-15` CI job is the oldest check available. |
| Speechmatics names an unknown voice as a similar enrolled one, with no score | Medium / a wrong suggestion or, for a trusted person, a wrong applied name | Sensitivity 0.80 by default; first match per person is a suggestion; "Not <name>" resets trust. |
| Sending `speaker_sensitivity` changes Speechmatics diarization | Medium / more or fewer speaker splits when the switch is on | Sent only with the switch on; adjustable; stated in the release notes. |
| Speechmatics changes its model or the warning wording | Low / remembered voices stop matching; unparsed warnings remove nothing | Identifiers are dropped when named; the notice is shown either way; a rename re-learns. |
| Diarization errors: two people under one label, or one person split | Medium / a blurred voice matches nobody or teaches a mixed voice | Only confirmed links learn; the 0.85 rule keeps a mixed sample from replacing a clean one unless it is close; Forget and Merge. |
| xcodegen flattens the `.mlmodelc` folder | Low / the model does not load from the bundle | Folder reference in `project.yml`; the `AppTests` bundle test fails the build. |
| Biometric data in a plain file | Inherent / privacy exposure | 0600; disclosed on the switch; one place to forget; nothing leaves the Mac on the local route. |
| The recorded specimen artifact is unreadable from this account | Low / the published specimen lacks the three v8 deltas | `DESIGN.md` and the local specimen are current; re-run `/design-language-update` from the owning account. |
| Existing drift: the Earlier runs sheet | None for this feature | Untouched. |

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

- One release. Both switches ship off; nothing changes until the user turns one on. No flag beyond the switches, no migration.
- CI gains a `macos-15` job that compiles and runs `scripts/voice_model_check.swift` against the committed model and the four fixture clips.
- Release notes: the two switches and what each stores; that Speechmatics diarization may split speakers differently with its switch on; that macOS 14 is unverified for the local route; the Credits window.
- Rollback: turn the switches off (takes effect at once). `voices.json`, the sidecars and the match log are inert without them and removable with Forget everyone. Reverting the release leaves files an older build ignores.
- Single project; no brief.

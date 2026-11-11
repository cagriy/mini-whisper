# Meeting Test Call — Design v5

**Status:** Draft
**Date:** 2026-11-11

## 1. Summary

A **test call** is a scripted remote meeting that measures how well the meeting pipeline transcribes, on this Mac, with the engine of the user's choice.

How a test call runs:
- Two synthetic voices, played by macOS `say` in separate processes, speak their lines through the speakers. The system-audio tap captures them as it would the far side of a real call.
- The user reads their own lines from a script pane in the meeting window.
- At Stop the transcript is scored against the known script:
  - word error rate (WER) per speaker and overall;
  - which engine label each speaker got, and how consistently;
  - how late final text arrives.
- The score shows in the meeting window. It is kept with the meeting and compared with earlier runs of the same scenario.

It is for the user tuning Mini Whisper. Today a bad real meeting leaves no way to tell whether the engine, the audio path or the speakers are at fault. A test call gives a repeatable measurement for about $0.02.

## 2. Goals and non-goals

**Goals**
- Start a test call in two clicks from the New Meeting window. Pick a scenario (or Random), an engine and Overlap.
- Exercise the real remote-call path end to end:
  - voice processing (AEC) and ducking;
  - the process tap;
  - the leveller;
  - the mixer;
  - the streaming engine;
  - speaker attribution.
- Score objectively: normalised WER per speaker and overall, label majority and purity, cross-credited words, and latency median and max.
- Keep every run as an ordinary meeting, marked Test, with its score. Compare it against earlier runs of the same scenario revision.
- Keep test calls away from agents: the CLI and MCP server never see them.

**Non-goals**
- In-room test calls. Remote only, because the voices must reach the transcript through the system-audio tap.
- Generated or random content. Scripts are bundled and fixed per revision, so runs stay comparable.
- Rescoring after transcript edits. The score is computed once, from what the engine produced. Later edits, renames and reassignments do not change it.
- Automated, unattended runs. The user reads their lines, and nothing runs headless.
- Exporting scores or charts across runs. The Earlier runs sheet is the comparison surface.
- Changing Pause/Resume, billing or summary behaviour for ordinary meetings.

## 3. Requirements

**Starting a test call**
1. **Chooser.** The New Meeting chooser keeps its two mode cards and Engine line. A **Test Call…** link button sits at the bottom left, beside Cancel / Start. Clicking it swaps the card to the test-call setup page, and **‹ Back** returns to the chooser.
2. **Setup page.** It has three controls:
   - **Scenario** (default Random). The menu shows Random, a divider, then the 8 scenarios. Each shows its latest WER on this Mac for the current revision, or "not run".
   - **Engine.** All four engines are listed. One without a key is disabled with "no key". The engine Settings would use is labelled "default" and preselected.
   - **Overlap** (default off).

   **Start Test Call** is disabled when no engine has a key, and the page then shows the existing no-key message.
3. **Random.** Random picks uniformly among the 8 scenarios. Picking is reproducible under an injected random-number generator.
4. **Remote meeting.** A test call starts a remote meeting titled `Test call · <Scenario title>`, using the selected engine, tagged with the scenario id and revision.
5. **Voices.** Each scenario names two voices. If a named voice is not installed, another installed English voice is substituted and the substitution is recorded. If fewer than two distinct English voices are installed, **Test Call…** is disabled with the message "Test calls need two English voices. Add one in System Settings → Accessibility → Spoken Content."

**Running the script**
6. **Voice lines.** Each is played by `/usr/bin/say -v <voice> <text>`, run as a separate process with no shell. The next line starts when that process exits.
7. **User lines: hand-over.** On the user's line, the conductor waits for speech. It hands over after a 1.2 s pause that follows speech.
8. **User lines: silence and long lines.**
   - If no speech starts within 20 s of the prompt, the line is skipped.
   - If speech has run for 30 s, the line hands over and is still scored.
9. **Skip line.** Skip ends the current line at once, whether a voice or the user is speaking (a running `say` is terminated). The line is excluded from the score.
10. **Overlap.** With Overlap on, about one in three of the user's lines that are followed by a voice line (⌈n/3⌉ of them, chosen by the injected RNG) are overlapped. On those, the voice line starts 1.5 s after the user's speech onset. The overlapped lines are recorded.
11. **Pause.** Pause is disabled in a test call, with the tooltip "Not available in a test call". `MeetingController.pause()` and `resume()` do nothing for a test meeting.
12. **Stop and sleep.**
    - Stop ends the script. The running line is recorded `stopped` and excluded, and lines never reached are recorded `notReached`.
    - A sleep during a test call ends the script the same way. The meeting is paused for sleep as any meeting is, and the window shows "The test call ended when the Mac slept. Press Stop for the score."

**Scoring**
13. **When and what.** At Stop (and on the quit path) the score is computed from the engine's segments as they stand after the session drains. Only lines recorded `done` are scored.
14. **Normalisation.** Script and transcript are normalised by the same function:
    - lowercase;
    - strip punctuation, keeping apostrophes inside words;
    - split on hyphens;
    - spell out numbers, decimals, percentages, ordinals, times, currency and years identically.
15. **WER.** WER is (S + D + I) / N, from a word-level Levenshtein alignment per line:
    - S = substitutions, D = deletions (missed words), I = insertions (extra words);
    - N = the number of reference words.

    It is summed per speaker role (You, Voice A, Voice B) and overall. A role with N = 0 shows "—".
16. **Labels.** For each role:
    - **Majority label:** the engine speaker label carried by most of its words.
    - **Purity:** that label's share of the role's words.
    - **Clean:** purity ≥ 95%, and no other role has the same majority label.

    Also reported: the count of voice words labelled as the user, and of the user's words labelled as anyone else.
17. **Latency.** For each scored line, latency runs from the end of the line to the arrival of the final segment holding the line's last matched word:
    - a voice line ends when `say` exits;
    - a user line ends at the end of the user's last speech before the hand-over.

    Median and max are reported, with the line number of the max.

**Results**
18. **Score pane.** After Stop, and whenever a test meeting is reopened, the right-hand pane shows the Score as in the accepted mockup (§5.4). The left side is the ordinary finished-meeting view, unchanged.
19. **Earlier runs.** **Earlier runs…** lists every test meeting on this Mac with the same scenario id and revision, newest first, at most 50. This run is shown in bold.
20. **Missing score.** A test meeting with no score shows the reason in the pane, from these cases:
    - **Interrupted** (no score file and no WER on the tag): "No score: the test call did not finish."
    - **File missing or unreadable after scoring** (no file but a WER on the tag, or a file that fails to decode): "Score unavailable: the score file could not be read."
    - **No lines scored:** "No lines were scored."

**Storage and visibility**
21. **Files.**
    - The score is stored as `testcall.json` (mode 0600) in the meeting's folder.
    - `meeting.json` and the `index.json` row carry an optional `test` tag: scenario id, revision, scenario title, overall WER.
    - Meetings without the tag decode unchanged.
22. **Agents.**
    - `mini-whisper meetings list|search|show|…` and the MCP tools never list, search or return a test meeting.
    - A lookup by a test meeting's id or prefix fails exactly as for a missing meeting.
23. **Meetings list.**
    - Test meetings appear in the Meetings list and its search, with a TEST chip after the title.
    - Their meta line reads `HH:MM · N min · Remote call · WER x.x% · <Engine> · $x.xx`. The WER segment is omitted while no score exists.
24. **Billing and summary.** A test call bills its minutes into Today/Month and writes a summary at Stop, exactly like any meeting.

**Engineering constraints**
25. Every duration (1.2 s, 20 s, 30 s, 1.5 s, the 100 ms poll) is tested on `VirtualClock`, with no real sleep in a test.
26. No new third-party dependency.
27. Neither script text nor transcript text is logged.

## 4. Background and context

**The remote-call path being measured**
- `MeetingController.start(mode:title:)` at `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift:79`. It resolves the engine from config with `MeetingEngine.resolve(stored:hasKey:)`, creates the `Meeting`, and starts the session.
- `MeetingAudioPath` (`MeetingAudioPath.swift:52`) handles each microphone buffer:
  - pushes the mic into `SpeechGate`;
  - levels the system audio (`SystemAudioLeveller`, uncommitted fix in the working tree);
  - mixes the two (`AudioMixer`) and streams the mix.

  `isSpeakingNow` and `gateView` (`:45-46`) expose the user's speech spans. `SpeechGate` releases after 0.3 s of quiet (`SpeechGate.swift:24`).
- The system-audio tap is a global process tap that excludes Mini Whisper's own process: `CATapDescription(monoGlobalTapButExcludeProcesses:)` at `Packages/MiniWhisperCore/Sources/MWAudio/SystemAudioTap.swift:85`. Audio from a separate `say` process is captured. The audio diagnostic run in this session confirmed it, with AEC keeping the voices out of the mic gate (about −92 dBFS).
- Timing:
  - Meeting time is `deps.clock.now - clockOrigin` (`MeetingController.swift:319`), currently private.
  - Segments carry meeting-time words (`Segment.words`, `MeetingModel.swift:29`; `Word`, `:10`).
  - Finals arrive in `handle(_ event: SupervisorEvent)` (`MeetingController.swift:181`) and are emitted as `.segmentAdded` (`:216`).

**Stopping, pausing and summarising**
- `stop(summarise:)` (`:394`) drains, then calls `summarise()` (`:431`, `:546`).
- `pause()` (`:347`) is the user pause.
- Sleep pauses via `pause(.sleep)` (`:269`). `PauseReason` is `.user | .sleep` (`MeetingEvent.swift:4`).

**Data model and storage**
- `Meeting` (`MeetingModel.swift:158`) and `IndexEntry` (`:223`) use synthesized `Codable`, so a new optional property decodes absent keys as nil.
- `MeetingStore` (`MeetingStore.swift:15`) keeps the folder files (`meeting.json`, `segments.jsonl`, `notes.jsonl`, `audio.m4a`, `:16-21`). It builds index rows in `entry(for:)` (`:210`) and rescans when `index.json` fails to decode (`readIndexOrScan`, `:186`).
- `MeetingReading` (`:6`) is the read protocol the agents use.

**Agents**
- `App/AgentCommand.swift:38-44` builds `MeetingsCLI(reader: store, …)` and `MCPServer(reader: store, …)` over the store directly.
- Both resolve ids against `reader.index()` through `MeetingID`, which already fails with `.notFound` (`MeetingID.swift:6`).
- Both search with `MeetingSearch` over `index()`-listed meetings (`MeetingsCLI.swift:96-98`, `MCPServer.swift:209-211`).

**App**
- The chooser is `MeetingChooserView` (`App/Meeting/MeetingView.swift:26`). The live view is `MeetingRecordingView` (`:114`), with `NotesPane` 280 pt (`:140`) and `SummaryPanelView` (`:220`).
- `MeetingCoordinator.start()` (`App/Meeting/MeetingCoordinator.swift:191`) calls `controller.start(mode:title:)`. Pause/Resume is wired only through `pauseOrResume` (`:233`).
- `MeetingEvent` is switched over at `MeetingWindowModel.swift:429` and `MeetingCoordinator.swift:290` (with `default:`).
- Meetings list rows are built in `MeetingsListModel.swift:298`, with the meta line at `:312`.

**Prior designs**
- v4 Meeting transcripts design and mockups (`features/feature-v4-Meeting-transcripts/`).
- The v4 Stage 28 README note on consent and agent access.

No brainstorm document exists for v5.

## 5. Design

### 5.1 Architecture / components

A new core module, **`MWTestCall`**, holds everything that is test-call logic. It depends on `MWMeetings`, `MWConfig` (for `MeetingEngine` in the scorer's signature, already reached through `MWMeetings`) and `MWSupport`. `MWMeetingPipeline` gains a dependency on it, which is allowed because nothing depends on `MWMeetingPipeline`.

| Component | Module | Responsibility | Public interface | Depends on |
|---|---|---|---|---|
| `TestScenario`, `ScenarioLibrary` | MWTestCall | The 8 bundled scripts as Swift values: id, revision, title, two voice roles, ordered lines | `ScenarioLibrary.all: [TestScenario]`, `scenario(id:)`, `pick(_: ScenarioChoice, using: inout some RandomNumberGenerator) -> TestScenario` | — |
| `VoiceCatalog` | MWTestCall | Parses `say -v ?` output and casts the scenario's voices, substituting where needed | `static func parse(_ listing: String) -> [SystemVoice]`, `func cast(_: TestScenario) -> VoiceCasting` (`.ready([Role: CastVoice])` / `.unavailable`) | — |
| `TranscriptNormalizer` | MWTestCall | Text → comparable tokens, identical on both sides | `func tokens(_ text: String) -> [String]` | — |
| `WordAligner` | MWTestCall | Word-level Levenshtein with operations | `func align(reference: [String], hypothesis: [String]) -> Alignment` (ops, S, D, I) | — |
| `TestCallConductor` | MWTestCall | Drives the script: plays voice lines, waits for the user, skips, overlap, stop | `init(scenario:casting:overlap:player:sensor:clock:rng:)`, `run() async`, `skip()`, `end(_: EndReason)`, `events: AsyncStream<ConductorEvent>`, `result: TestCallRun` | `SpeechPlaying`, `UserSpeechSensing`, `Clock` |
| `TestCallScorer` | MWTestCall | Assigns transcript words to lines, aligns, aggregates WER, labels and latency | `func score(run:scenario:segments:arrivals:speakers:userSpeaker:engine:) -> TestCallRecord` | Normalizer, Aligner |
| `TestRunHistory` | MWTestCall | Earlier runs and per-scenario latest WER | `latestWER(in: [IndexEntry]) -> [String: Double]`, `runs(of: TestCallTag, in: [IndexEntry], load:) -> [TestCallRecord]` | — |
| `TestCallTag`, `TestCallRecord` | MWMeetings | Codable model of the tag and the score file | value types (§5.2) | — |
| `MeetingStore` (modified) | MWMeetings | Reads and writes `testcall.json`; copies the tag into index rows | `writeTestCall(_:of:)`, `readTestCall(_:) throws -> TestCallRecord?` | — |
| `MeetingController` (modified) | MWMeetingPipeline | Starts with an engine and tag, exposes timing, records arrivals, scores, blocks Pause | §5.3 | MWTestCall |
| `AgentMeetings` | MWAgentAccess | `MeetingReading` decorator hiding test meetings | `init(_ base: any MeetingReading)` | MWMeetings |
| `SayProcessPlayer` | App | `SpeechPlaying` over `/usr/bin/say` | `play(_ line: VoiceLine) async -> Playback`, `stop()` | Foundation `Process` |
| `SystemVoices` | App | Runs `say -v ?` once per chooser open, off the main actor | `load() async -> String` | Foundation `Process` |
| `TestCallSession` | App | Owns the conductor and player for one meeting, bridges controller → sensor, runs the Stop order | `start()`, `skip()`, `finish(summarise:) async` | conductor, controller |
| Views, `MeetingWindowModel`, `MeetingsListModel` (modified) | App | Setup page, Script pane, Score pane, Earlier runs sheet, TEST chip and list meta | SwiftUI views and model state (§5.4) | coordinator, store index |

The seams are protocols:
- `SpeechPlaying`: `func play(_ line: VoiceLine) async -> Playback`, returning launch and exit meeting times and whether `say` exited normally; plus `func stop()`.
- `UserSpeechSensing`: `var meetingTime: Double`, `var isSpeaking: Bool`, `var speechSpans: [ClosedRange<Double>]`, `var lastAudibleSystemAudio: Double?`.

The conductor and scorer are pure, clock-driven logic and are tested without audio, `say` or the controller.

### 5.2 Data model

**Scenario catalogue** (revision 1 of each)
- Every scenario has 12 lines (±2), 4 of them the user's, and 120–200 reference tokens: about 2 minutes.
- Every scenario carries at least three numbers, dates or times and at least two proper nouns or terms of art.
- Lines never name or address the user. Character names are the scenario's own.
- Voices are macOS's default English voices.

| id | Title | Voice A | Voice B | Emphasis |
|---|---|---|---|---|
| `sprint-planning` | Sprint planning | Daniel | Karen | jargon, sprint numbers |
| `budget-review` | Budget review | Samantha | Rishi | currency, percentages |
| `incident-review` | Incident review | Moira | Daniel | jargon, times |
| `hiring-debrief` | Hiring debrief | Karen | Tessa | names, plain speech |
| `product-launch` | Product launch | Samantha | Daniel | product names, dates |
| `customer-escalation` | Customer escalation | Rishi | Moira | names, order numbers |
| `office-move` | Office move | Tessa | Karen | addresses, dates |
| `quarterly-sales` | Quarterly sales | Daniel | Samantha | figures, ordinals |


```swift
// MWMeetings/TestCallModel.swift
public struct TestCallTag: Codable, Sendable, Equatable {
    public var scenarioID: String      // "sprint-planning"
    public var revision: Int           // 1
    public var scenarioTitle: String   // "Sprint planning"
    public var wer: Double?            // overall, 0…; nil until scored
}
// Meeting:     public var test: TestCallTag?   (init parameter `test: TestCallTag? = nil`)
// IndexEntry:  public var test: TestCallTag?   (set by MeetingStore.entry(for:) from meeting.test)
```

`testcall.json`, `TestCallRecord`, schema 1:

```json
{
  "schema": 1,
  "scenario": { "id": "sprint-planning", "revision": 1, "title": "Sprint planning" },
  "engine": "assemblyai_streaming",
  "overlap": false,
  "scoredAt": "2026-11-11T11:16:02Z",
  "voices": [
    { "role": "a", "character": "Tom",   "requested": "Daniel", "voice": "Daniel" },
    { "role": "b", "character": "Priya", "requested": "Karen",  "voice": "Karen" }
  ],
  "lines": [
    { "index": 6, "role": "b", "status": "done", "start": 41.0, "end": 47.6, "overlapped": false,
      "reference": "Then the remaining risk is the Kubernetes upgrade. …",
      "counts": { "words": 17, "substitutions": 1, "deletions": 0, "insertions": 1 },
      "heard": [ { "text": "Then", "op": "match" },
                 { "text": "Cooper Netties", "op": "error", "script": "Kubernetes" }, … ],
      "labels": { "2": 17 }, "segmentStart": 41.2, "latency": 2.9 },
    { "index": 11, "role": "you", "status": "skipped", "reference": "Agreed. I'll move the export ticket to the backlog …" }
  ],
  "roles": [
    { "role": "you", "words": 48, "substitutions": 1, "deletions": 1, "insertions": 0,
      "majorityLabel": 0, "majorityLabelName": "Alex", "purity": 1.0 }, …
  ],
  "overall": { "words": 157, "substitutions": 6, "deletions": 1, "insertions": 3 },
  "crossCredited": { "voiceWordsAsYou": 0, "yourWordsAsVoices": 0 },
  "latency": { "median": 1.3, "max": 2.9, "maxLine": 6 }
}
```

**Line `status`**
- Values: `done | skipped | stopped | notReached`.
- `skipped` covers the Skip button, 20 s of silence and a `say` failure. A sleep ends the script with `stopped` and `notReached`, like Stop.
- Only `done` lines carry counts.
- Rates are not stored. WER is derived from the counts, so a record never disagrees with itself. `TestCallTag.wer` caches the overall WER for the list and the scenario menu.

**`heard`**
- Lists the line's transcript words in time order, in the engine's original spelling.
- A word whose tokens were substituted or inserted carries `"op": "error"` and the script words it replaced, in the script's spelling (`script`, empty for a pure insertion).
- A missed script word is an entry `{ "op": "missed", "script": "a" }`.

**Lifetime and compatibility**
- The record is written once at scoring and lives and dies with the meeting folder. `delete(_:)` already removes the whole folder.
- Old `meeting.json` and `index.json` files decode with `test == nil`. Rewritten files keep their shape, because synthesized `encodeIfPresent` omits nil.
- `Meeting.schema` stays 1.

### 5.3 Interfaces

**`MeetingController`** (`MWMeetingPipeline`)
- `start(mode:title:engine: MeetingEngine? = nil, test: TestCallTag? = nil)`. A given engine replaces the config resolution, and its key must exist, else `MeetingError.noEngineKey`. The tag is stored on the `Meeting` before `store.create`.
- `public var meetingTime: Double` (read-only; today private at `:319`).
- `public var userSpeech: SpeechGate.View` (the audio path's `gateView`).
- `public private(set) var lastAudibleSystemAudio: Double?`: the meeting time of the latest one-second tick whose system peak exceeded `audibleSystemPeak` (`MeetingController.swift:22`).
  - Today `checkSystemAudio()` (`:335`) stops reading the peak once `systemAudioSettled` is set.
  - The change: read `systemPeakSinceLastCall()` on every tick while a tap exists, record `lastAudibleSystemAudio` from that reading, then run the existing settle-and-hint logic on the same reading, unchanged.
  - The peak keeps a single consumer, and the silence hint behaves as before. A test pins this.
- For a test meeting, `segmentArrivals: [UUID: Double]` records meeting time in `handle(_ event: SupervisorEvent)` at the point each new segment is appended, before `.segmentAdded` is emitted.
- `pause()` and `resume()` return immediately when `meeting?.test != nil`. The sleep path (`pause(.sleep)`) is unchanged.
- `finishTest(_ run: TestCallRun, scenario: TestScenario) async`, called after `stop(summarise: false)`. It:
  1. scores with `TestCallScorer`, using its segments, arrivals, speakers and `SpeakerRegistry.userID`;
  2. calls `store.writeTestCall`;
  3. sets `meeting.test.wer` and calls `store.update` (which refreshes the index row);
  4. emits `.testScore(.scored(record))`.

  On a write error it emits `.error` and still emits the score.
- `open(_:)` on a test meeting reads `testcall.json` and emits `.testScore`, with one of three payloads:
  - `.scored(record)`;
  - `.missing`, when there is no file and the tag has no WER;
  - `.unreadable`, when decoding fails, or when there is no file but the tag has a WER.
- **New `MeetingEvent` case** `testScore(TestScoreState)`. Its switch sites:
  - `MeetingWindowModel.swift:429` handles it explicitly;
  - `MeetingCoordinator.swift:290` falls to its existing `default:`;
  - test fakes that switch exhaustively add the case.

**`MeetingControlling`** (`App/Meeting/MeetingCoordinator.swift:8`)
- The protocol mirrors the controller, so it gains:
  - `start(mode:title:engine:test:)` (replacing `start(mode:title:)`);
  - `meetingTime`, `userSpeech` and `lastAudibleSystemAudio`;
  - `finishTest(_:scenario:)`.
- The AppTests fake controllers implement the same members.

**`MeetingCoordinator`**
- `Session` gains `test: TestCallSession?`.
- `stop(summarise:)` (`:207`) is the path both the Stop button and the quit path (`AppDelegate.swift:506`, `:527`) take. For a test session it delegates to `TestCallSession.finish(summarise:)`.
- The event loop (`:290`) forwards `.state(.paused)` to the test session, which ends the script for a sleep.
- `pauseOrResume` (`:233`) is not reached from a test meeting, because the button is disabled. The controller guard covers it anyway.

**`MeetingsListModel`**
- `Row` (`:55`) gains `isTest`, set at `:298` from `entry.test != nil`.
- `meta(of:)` (`:312`) emits the test form of the meta line (R23).

**`MeetingStore`**
- `File.testCall = "testcall.json"`.
- `writeTestCall(_:of:)` uses the existing temp-file-and-rename whole-file write with 0600.
- `readTestCall(_:) throws -> TestCallRecord?` returns nil when the file is absent.
- `entry(for:)` copies `meeting.test`.
- `IndexEntry.init` gains `test: TestCallTag? = nil`, so existing call sites are unchanged.
- `update(_:)` already rewrites the index row via `updateIndexEntry` (`MeetingStore.swift:55-58`).

**`AgentMeetings: MeetingReading`** (`MWAgentAccess`)
- `index()` returns `base.index().filter { $0.test == nil }`.
- `load(id)` throws `CocoaError(.fileReadNoSuchFile)`, the error a missing folder produces, when the loaded meeting has a tag.
- `App/AgentCommand.swift:41` and `:44` pass `AgentMeetings(store)` instead of `store`. Because ids resolve against the filtered index, `show`, `search` and every MCP tool behave as for a missing meeting.

**Conductor contract**
- Inputs:
  - `VoiceLine(text, voice)`;
  - the sensor's `isSpeaking` and `speechSpans` (in meeting seconds);
  - `skip()`;
  - `end(.stop | .sleep)`.
- Events: `.line(index, .voiceSpeaking(role) | .yourTurn)`, `.skipped(index, reason)`, `.captureMissing(index)` (§5.6 no system audio), `.voicesFailed` (§5.6 two consecutive `say` failures, followed by `.finished`), `.finished`.
- `result` holds each line's status, start, end and overlap flag, plus the casting.
- It polls the sensor every 100 ms on `Clock.sleep`.

### 5.4 UI surfaces

Every surface follows the accepted mockups, in the v4 design language plus the TEST tag colours (`--test #7a4fd0`, tag fill `#f1ecfb`, border `#ddd0f5`).

**Chooser and setup**: [Test Call link](./mockups/mockup-v5-chooser-options.html#test-link) · https://claude.ai/artifact/D41uFfFcyJE7igLXAU2DCJ#test-link
- `MeetingChooserView` keeps its cards and Engine line. A `.link` button **Test Call…** sits bottom-left, and Cancel / Start stay bottom-right.
- Clicking it swaps the chooser's content, in the same 920 × 620 chooser window, to `TestCallSetupView`:
  - **‹ Back**;
  - the heading "Test call" with the TEST tag;
  - the description "Two simulated voices talk with you from a script, as on a remote call. You read your lines from the screen. At Stop the transcript is scored against the script. About 2 minutes, about $0.02.";
  - a two-column grid: **Scenario** popup, **Engine** popup, and an **Overlap** checkbox with the sub-text "A voice sometimes starts while you are still speaking.";
  - Cancel and **Start Test Call** (default button).
- Menu rows:
  - Scenario: `Random · one of 8`, divider, `<Title> — WER 6.4%` or `<Title> — not run`;
  - Engine: `<Engine> — default` or `<Engine> — no key` (disabled).
- With fewer than two English voices, the link is disabled with the voice message (R5) as its help text.

**During the call**: [Script pane](./mockups/mockup-v5-script-pane.html) · https://claude.ai/artifact/97JRTvPtzPMsiPHJdFvS2M
- Header:
  - title `Test call · <Scenario>`;
  - TEST chip;
  - the live `Mic · System audio` chip;
  - elapsed time and cost ("$0.01 so far");
  - **Pause** disabled with the help text "Not available in a test call";
  - **Stop**.
- The transcript is unchanged. Its source line reads "<Engine> · <Language> · speaker names stay as the engine labels them; the score checks them".
- `ScriptPane`, 310 pt, replaces `NotesPane` for the meeting's life.
  - Header: "Script · <Scenario>" and "N of 12".
  - Up to three earlier lines, dimmed. A skipped line shows "Skipped".
  - The current line:
    - is ringed in its speaker's colour (`--s1` / `--s2`, or blue for the user, on a `#f2f7ff` fill);
    - is tagged "<Name> · <Voice> voice · speaking" with a three-bar level animation (static under Reduce Motion), or "Your turn · read this line aloud".
  - The next three lines follow, then "+ N more lines".
  - Footer: the hint "Hands over after a 1.2 s pause" on the user's turn, or "Waits for the voice to finish", and **Skip line**.
- After a sleep, the pane footer shows the R12 message.

**After Stop and on reopen**: [Score in the script pane](./mockups/mockup-v5-pane-score.html) · https://claude.ai/artifact/VV8kAwi7aSnp7PRgP4TSDR
- The left side is the v4 finished view unchanged: summary panel above a plain transcript, Export buttons in the title bar.
- `ScorePane`, 310 pt, replaces the script pane. Its header is "Score · <Scenario>", then:
  - **Head block** on the `#faf8fe` fill:
    - overall WER at 30 pt, with "word error rate · N errors in M words";
    - three rows, You · read aloud / <A> · <voice> voice / <B> · <voice> voice, each with WER, majority label name and purity (purity in amber when the role is not clean);
    - "Latency X s median, Y s max · N of M lines · cross-credited words: K".
  - **Line list:** one row per script line (number, speaker, text truncated to one line), with one of these badges:
    - ✓ (green) when it has no errors;
    - "N errors" (red);
    - "Skipped", "Stopped" or "Not reached" (grey);
    - an extra amber "label" badge when any of its words carries a label other than its role's majority label.
  - **Clicking a row** expands it in place and highlights the transcript segment(s) holding its words. The expanded row shows:
    - "Script · <Name>" with the line text;
    - "Heard · <Label> · <time>" with `heard` rendered: error words on a red tint with the script word above in small type, missed words struck through;
    - "N errors (breakdown) · final text X s after the voice ended".
  - **Footer:** **Earlier runs…** and "N runs of this scenario". The button opens a sheet "Earlier runs · <Scenario>" with:
    - the note "Revision R of the scenario, runs on this Mac, newest first." and the definition of clean;
    - a table with the columns Run, Engine, WER, You, <A>, <B>, Clean, Latency (median / max), with this run in bold;
    - **Done**.
- When no score exists, the head block shows the R20 message and the line list shows the script without badges.

**Meetings list**: [inset on the same page](./mockups/mockup-v5-pane-score.html#pane-score)
- Rows with `entry.test != nil` get a TEST chip after the title.
- Their meta reads `11:14 · 2 min · Remote call · WER 6.4% · AssemblyAI Streaming · $0.02`, replacing the speakers and audio-size segments.
- Search is unchanged and finds them.

### 5.5 Control flow

**Happy path**
1. The chooser opens. `SystemVoices.load()` runs once, off the main actor, and `VoiceCatalog.parse` + `cast` decide whether **Test Call…** is enabled. The scenario menu's WERs come from `TestRunHistory.latestWER(in: store.index())`.
2. The user clicks **Start Test Call**. The coordinator then:
   1. resolves the scenario (`pick`, with the system RNG);
   2. casts the voices;
   3. calls `controller.start(mode: .remote, title: "Test call · \(title)", engine: chosen, test: TestCallTag(…, wer: nil))`.
3. When the controller reports `.recording`, `TestCallSession` creates the conductor with:
   - `SayProcessPlayer`;
   - a sensor that reads `controller.meetingTime` and `controller.userSpeech` on the main actor;
   - `SystemClock`.

   Then it calls `run()`.
4. **Voice line.** The player launches `say`. Its `Playback` reports the launch and exit times; the conductor records them as start and end, and moves on.
5. **User line.** The conductor emits `.yourTurn` at time p.
   - The first speech span starting after p sets the line's start.
   - Hand-over happens when the last span's end is at least 1.2 s in the past and `isSpeaking` is false. That end becomes the line's end.
   - If no span starts by p + 20 s, the line is skipped. If start + 30 s passes, the line hands over.
6. **Overlap line.** At start + 1.5 s the conductor launches the next voice line while still tracking the user. It advances once both the voice's `say` has exited and the user hand-over condition holds.
7. After the last line the conductor emits `.finished`. The pane then reads "Script finished · press Stop for the score", and nothing ends automatically.
8. **Stop.**
   1. `TestCallSession.finish(summarise: true)` calls `conductor.end(.stop)`: `say` is terminated, the running line becomes `stopped`, the rest `notReached`.
   2. `controller.stop(summarise: false)`: the session drains, so late finals still get arrival times.
   3. `controller.finishTest(run, scenario)`: score, write, emit.
   4. `controller.summarise()`.

**Alternative flows**
- **Quit:** the same order with `summarise: false`. Scoring is local and well under 100 ms.
- **Window closed during a test call:** recording continues, as for any meeting. The conductor keeps running, and reopening the window shows the pane.
- **Sleep:** the controller emits `.state(.paused)` with reason `.sleep`. `TestCallSession` calls `conductor.end(.sleep)` and the pane shows the R12 message. Stop then proceeds from step 8.2.
- **Reopen from the Meetings list:** `controller.open(id)` emits `.testScore(…)` and the window shows the Score pane.

**Scoring algorithm** (`TestCallScorer`)
1. Scored lines are those with status `done`. Reference tokens = `normalizer.tokens(line.text)`, each keeping its source script word for display.
2. Hypothesis tokens are built per transcript word, from `segment.words` in meeting time. A segment without word timings spreads its tokens evenly over [start, end]. Each token keeps its source word, its segment id and the segment's speaker.
3. Each line's window is [start − 0.5 s, end + 1.5 s]. A token is a candidate for every scored line whose window contains its midpoint.
   - **One candidate:** the token is assigned to it.
   - **Several:** it goes to the earliest candidate whose reference still holds an unconsumed equal token. Failing that, it goes to the candidate whose unpadded span is nearest in time.
   - **None:** the token is ignored, which also covers words spoken during skipped or stopped lines.
4. Per line, `WordAligner.align` runs on the reference against the assigned tokens in time order. It gives S/D/I and the ops, from which `heard` is built by source word.
5. Roles sum their lines. Labels count tokens per speaker id per role, giving majority, purity, clean and cross-credited counts (R16).
6. Latency per line = `arrivals[segment of last matched token] − line.end`. A line with no matched token has no latency. The score reports median and max with the max's line.

### 5.6 Failure and edge cases

- **`say` fails to launch or exits non-zero:** the line is `skipped` with reason "voice failed", and the conductor continues. If two consecutive voice lines fail, it ends the script, and the pane says "The test voices could not play."
- **No system audio during a voice line** (the tap is unavailable or permission is denied): the existing `.systemAudio(.unavailable)` banner applies. The conductor also checks the sensor's `lastAudibleSystemAudio` after each voice line. If it is nil or earlier than the line's start, it shows "The test voices are not being captured; the score will count their lines as missed," and the line is still scored, so the failure shows in the numbers.
- **The user never speaks:** each user line skips after 20 s, and the voices continue.
- **Engine disconnects mid-call:** the existing reconnect and gap markers apply. Words lost in the gap count as deletions.
- **Scenario voice missing:** cast a substitute. The candidates are installed voices whose locale starts with `en_` and that are not the other role's voice, taken in catalogue order. The substitution is recorded in `voices[].voice` and shown in the setup page's Scenario menu as "<Title> — uses <Voice> for <Character>".
- **`testcall.json` write fails:** emit `.error`. `wer` is still set on the tag, and the pane still shows the score for this session. On reopen, the meeting shows "Score unavailable: the score file could not be read." (R20).
- **Crash or force-quit during a test call:** `meeting.json` carries the tag with `wer == nil` and there is no score file. On reopen the pane reads "No score: the test call did not finish."
- **Old app version after a downgrade:** it ignores the `test` key. Accepted in §7.
- **A scenario revision changes in a later version:** stored records stay self-contained (line text included). Comparisons only group equal id and revision.
- **The user renames speakers or edits the transcript afterwards:** the score is unchanged (non-goal). The label names shown are those recorded at scoring.
- **Every line skipped:** the score is written with zero scored lines. The head shows "No lines were scored." and `wer` stays nil.

### 5.7 Security

- **Process launch:** `say` is launched by absolute path `/usr/bin/say` with an argument array. There is no shell, so no command injection.
  - Script text is bundled, never user input. `ScenarioLibrary` tests assert that no line starts with `-`, so a line cannot be read as an option.
  - Voice names come from parsing `say -v ?` and must match `^[A-Za-z0-9 ()._'-]+$` before use.
- **Files:** `testcall.json` is 0600 inside the 0700 meeting folder, written by the same rename-into-place path as the other meeting files. It holds transcript words, so it is as sensitive as `segments.jsonl`.
- **Agents:** they cannot reach test meetings through any CLI command or MCP tool. The decorator sits at the single construction point, `AgentCommand.swift`, so every current and future tool inherits it.
- **Secrets and logs:** no secret is touched beyond the existing engine key lookup. Logs carry scenario id, revision, engine, line index and outcomes only, never script or transcript text.

### 5.8 Performance

- The conductor polls every 100 ms on the main actor, with negligible work per tick.
- Alignment is O(n·m) per line on about 15 tokens, which is trivial.
- The scenario menu reads only `index.json`.
- The Earlier runs sheet loads at most 50 `testcall.json` files on a background task when it opens, at a few KB each.
- `say` runs out of process. Playback adds no load to the capture thread.

### 5.9 Observability

`Log.meeting` gains these lines:
- `test call: start scenario=<id> rev=<n> engine=<raw> overlap=<bool>`;
- `test call: line <i> skipped (<reason>)`;
- `test call: voice substituted <requested>-><actual>`;
- `test call: scored wer=<x> lines=<k>/<n> latency_med=<s>`.

Nothing is alertable; this is a local diagnostic feature.

### 5.10 Compatibility / migration

- **No migration.** Optional fields decode as nil, and the index rescan path (`readIndexOrScan`) rebuilds rows with `test` from `meeting.json`.
- **`Package.swift`:**
  - add the `MWTestCall` target, product and `MWTestCallTests` test target;
  - add `MWTestCall` to `MWMeetingPipeline`'s dependencies;
  - list it in `CLAUDE.md`'s module map.
- **`project.yml`:** add the `MWTestCall` product to the `MiniWhisper` target, which links core products explicitly.
- **README:** a "Test call" section covering what it measures, its cost, that agents never see test calls, and how to add voices.
- **CHANGELOG:** an `[Unreleased] ### Added` entry.

### 5.11 Testing strategy

| Component | Unit tests (isolated) |
|---|---|
| `ScenarioLibrary` | 8 scenarios with unique ids; revision ≥ 1; two distinct voice roles each; 10–14 lines with 4 user lines; 120–200 reference tokens; no line starting with `-`; no line naming the user; `pick(.random)` uniform and reproducible with a seeded RNG; `pick(.named)` |
| `VoiceCatalog` | parses a fixture `say -v ?` listing (names with spaces and parentheses, locales); English filter; casting with both voices present, with one or both missing (substitution order, never the other role's voice), and with fewer than two English voices → `.unavailable`; rejects names failing the allow-list |
| `TranscriptNormalizer` | table tests: case, punctuation, apostrophes, hyphens, integers, decimals (`3.2`), percentages (`80%`), ordinals (`14th`), times (`10:30`), currency (`$40`), years (`2026`), mixed; script and transcript forms of the same sentence give equal tokens |
| `WordAligner` | empty sides, all-match, single S/D/I, `webhook` vs `web hook` = 1 S + 1 I, tie-breaking stability |
| `TestCallConductor` | on `VirtualClock` with fake player and sensor: voice → voice ordering; user hand-over at exactly 1.2 s after the span end and not before; 20 s skip; 30 s cap; Skip during voice (player stopped) and during the user's turn; overlap start at +1.5 s and ⌈n/3⌉ selection with a seeded RNG; `end(.stop)` and `end(.sleep)` statuses; two consecutive `say` failures end the script |
| `TestCallScorer` | fixtures: perfect transcript → 0%; the mockup's sprint-planning case → 10 errors / 157 words (R14 splits the mockup's "one-line"; the mockup shows 156), You 4.2%, Priya purity 87%, 2 of 3 clean, latency median 1.3 s / max 2.9 s at line 6; overlapping windows resolved by token match; words outside windows ignored; segments without word timings; skipped lines excluded; zero scored lines |
| `TestRunHistory` | latest WER per scenario ignores other revisions and nil WER; runs sorted newest first and capped at 50 |
| `TestCallTag` / `TestCallRecord` / `IndexEntry` | old `meeting.json` / `index.json` fixtures decode with `test == nil`; round-trip keeps the bytes free of a `test` key when nil |
| `MeetingStore` | `writeTestCall` / `readTestCall` round-trip; 0600 mode; absent file → nil; `entry(for:)` copies the tag |
| `MeetingController` | `start(engine:)` uses the given engine and fails `noEngineKey` without its key; tag stored; `pause()` / `resume()` no-op for test meetings; arrivals recorded at segment append; `finishTest` writes the file, updates `wer` and the index, emits `.testScore`; `open` emits `.scored` / `.missing` / `.unreadable`; `lastAudibleSystemAudio` updates on every audible tick after the meeting has settled, and the silence hint still fires once, as today |
| `AgentMeetings` | index filtered; load of a test id throws; `MeetingsCLI` and `MCPServer` built over a fake store with one test and one normal meeting never return the test one from list, search or show by id or prefix |
| App (`AppTests`) | `TestCallSession` Stop order against fakes (conductor end → stop(false) → finishTest → summarise; quit path skips summarise); window model maps conductor events and `.testScore` to pane state; meetings-list meta and TEST chip for tagged rows |

Integration tests run only with `MW_INTEGRATION=1`:
- `SayProcessPlayer` plays one short line and returns a normal exit;
- with TCC granted, the tap's peak rises during playback.

**Acceptance.** Run a test call per engine on this Mac, then check:
- the Score pane, list row, search hit and Earlier runs sheet all appear;
- `mini-whisper meetings list` and `search` show no test call;
- a prefix lookup of a test id reports "no meeting".

## 6. Alternatives considered

**Chooser entry**
- **Third mode card** (`third-card`, [mockup](./mockups/mockup-v5-chooser-options.html#third-card)). Rejected: it puts a diagnostic on equal footing with real meetings in a chooser used daily.
- **Checkbox under Remote call** (`remote-checkbox`, [mockup](./mockups/mockup-v5-chooser-options.html#remote-checkbox)). Rejected: test options would crowd the card, and the setting would be easy to leave on.

**Teleprompter**
- **Prompt strip** (`prompt-strip`, [mockup](./mockups/mockup-v5-prompt-strip.html), https://claude.ai/artifact/Y5a4eH41NAbfBHqtTUx4AN). Rejected in favour of the script pane, which shows where the call is going and what was skipped.
- **Prompt card** (`prompt-card`, [mockup](./mockups/mockup-v5-prompt-card.html), https://claude.ai/artifact/KwJmykJU7xVTsShTfM5oy2). Rejected: it shows only the current line.

**Results**
- **Score above the summary** (`score-panel`, [mockup](./mockups/mockup-v5-score-panel.html), https://claude.ai/artifact/HZgtaiLUEeAMsuTeutGiBM). Rejected: it pushes the summary and transcript down.
- **Score tab** (`score-tab`, [mockup](./mockups/mockup-v5-score-tab.html), https://claude.ai/artifact/1Gypf44rhfaqhJQKX1gTVJ). Rejected: it adds a test-only mode switch, and the meeting view would no longer match ordinary meetings.

**Implementation**
- **`AVSpeechSynthesizer` in process.** Rejected: the tap excludes Mini Whisper's own process (`SystemAudioTap.swift:85`), so in-process speech would never reach the transcript.
- **Injecting the voices straight into the mix.** Rejected: it would bypass AEC, ducking, the tap and the leveller, the parts most likely to fail on a real call.
- **Pre-recorded audio files.** Rejected: they add megabytes to the app and fix one voice per line. `say` keeps voices swappable at no size cost.
- **Generated content (Claude writing the dialogue).** Rejected by the user in favour of bundled scripts, because runs must be comparable and free of per-run LLM cost.
- **One global alignment of the whole transcript.** Rejected: per-line windows attribute errors, labels and latency to lines, which the line badges and latency need.
- **Scenarios as JSON resources.** Rejected for Swift values. There is no package resource bundle to ship and sign, and the library tests read the same values the app uses.
- **Scoring in the App target.** Rejected: the controller already owns segments, arrivals and the store, and core placement keeps scoring testable with `swift test`.

## 7. Risks and issues

- **TTS mispronunciation counted as engine error** (likely, medium impact). `say` may mangle jargon, and the error is then blamed on the engine.
  - Mitigation: scenario authoring includes a listening pass. A word `say` mispronounces is replaced in the script, which bumps the revision.
  - Comparisons across engines stay fair because every run hears the same audio.
- **Default voices differ across macOS versions or locales** (medium likelihood, low impact). Mitigation: substitution with recording (R5), the disabled state with instructions, and tests over a fixture listing.
- **Voices not captured** (low likelihood, high impact on that run). Causes: TCC "System Audio Recording" denied, or audio routed through software the tap misses.
  - Mitigation: the existing unavailable banner, plus the per-line capture check (§5.6), so the user sees it during the call, not only in the score.
- **Synthetic voices diarise differently from people** (likely, low impact). The score is a relative benchmark across engines, settings and builds, not an absolute promise. The README says so.
- **User reading variance between runs** (likely, low impact). Mitigation: the You row is reported apart from the voice rows, so voice-only comparisons are unaffected.
- **Downgrade exposes test meetings to agents** (unlikely, low impact). An older build ignores the tag. Accepted: test content is scripted placeholder dialogue.
- **This design measures the uncommitted ducking and leveller fix** (certain, low impact). Mitigation: that fix ships first or with this feature. The plan sequences it before the conductor work.
- **`say` locale versus engine language** (low likelihood). Scripts are English, and every engine config in use is English. A non-English engine language would show a high WER, which is a true measurement.

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

- Ship in the next minor release (0.6.0) with no feature flag. The entry point is a link inside an existing window, and test calls are tagged and hidden from agents.
- Order of work:
  1. the ducking and leveller fix already in the tree;
  2. the core model, store and agent filter;
  3. the normaliser, aligner, scorer and scenarios;
  4. the conductor;
  5. the controller changes;
  6. the App surfaces.
- **Rollback:** a release without the feature leaves test meetings as ordinary meetings, readable and deletable. `testcall.json` files are ignored.
- **Communication:** a README "Test call" section, a CHANGELOG `Added` entry, and the help text on the setup page.

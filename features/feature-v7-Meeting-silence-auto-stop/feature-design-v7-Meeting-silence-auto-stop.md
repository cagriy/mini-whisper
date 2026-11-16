# Meeting Silence Auto-Stop — Design v7

**Status:** Draft
**Date:** 2026-11-16

## 1. Summary

A meeting left recording after the call ends keeps transcribing whatever follows: on 2026-11-16 two later
calls folded into one forgotten recording. This feature watches a recording meeting for transcribed speech.
After a set stretch with none (default 1 min, never in the first 3 min), a floating prompt asks whether to
keep recording and counts down one minute; unanswered, the meeting stops and is summarised as usual, and its
finished page says it stopped after silence. It is for the person running Mini Whisper meetings, who should
not have to remember Stop for the recording to end.

## 2. Goals and non-goals

- **Goals:**
  - A forgotten recording ends about two minutes after the last words (1 min silence + 1 min countdown).
  - A real quiet stretch costs one click: Keep recording.
  - The prompt is seen over any app, full-screen calls included, without taking keyboard focus.
  - The threshold is a setting: Off, 1, 2 or 5 min.
  - A meeting stopped by silence says so on its finished page.
- **Non-goals:**
  - Audio-level silence detection (room noise and music keep levels up; §6).
  - Detecting that a new call started (calendar, app focus): out of scope.
  - Splitting an already-merged recording.
  - Showing the silence stop in exports, the CLI or MCP output: the field is app-only (R10).
  - Test calls: their conductor stops them (R3).

## 3. Requirements

1. **R1 Setting.** `meeting_silence_stop_seconds` in `config.json` takes 0, 60, 120 or 300; default 60; any
   other value reads as 60. 0 is Off.
2. **R2 Speech.** Speech is a partial whose trimmed text is non-empty and differs from the previous partial,
   or a final segment with non-empty trimmed text. Empty partials, repeated partials and speaker revisions are
   not speech.
3. **R3 When the prompt opens.** All of: the meeting is `.recording`; it is not a test call; the threshold is
   above 0; meeting time ≥ 180 s; meeting time − last speech ≥ threshold; the session is not reconnecting.
   Last speech starts at 0 (Start).
4. **R4 Countdown.** 60 s, whatever the threshold. At 0 the meeting stops with a summary, and
   `Meeting.silenceStopSeconds` records the threshold.
5. **R5 Closing.** The prompt closes on: Keep recording (silence counted again from the click); Stop now
   (a manual stop, no field set); speech; Pause, or the Mac sleeping; any stop; the setting turned Off;
   the session reconnecting.
6. **R6 Restarts.** After Resume, silence counts from Resume, with no new grace. After a reconnect, from the
   session's next `.connected`.
7. **R7 Threshold changes.** Read every tick. Off closes an open prompt. Another value applies to the next
   prompt; an open prompt keeps its countdown and title.
8. **R8 Prompt surface.** Non-activating, above every window and full-screen Space, on every Space, never key,
   no keyboard shortcuts, no close box, on the display `DisplayPlacement` picks; content as the accepted
   mockup (§5.3).
9. **R9 Settings row.** "Stop after silence" in Settings → Meetings → Recording, after Keep meeting audio.
10. **R10 Finished page.** A Flag chip "Stopped after N min without speech" after the duration chip, only
    when `silenceStopSeconds` is set. `meeting.json` gains the optional field; older versions ignore it;
    `index.json`, Markdown exports, CLI and MCP output are unchanged.
11. **R11 Timing tests.** Every duration (grace, threshold, countdown) is tested on `VirtualClock` (core) or
    `ManualClock` (app); no real sleeps.

## 4. Background and context

- `MeetingController` (`Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`) owns a
  meeting from Start to summary on the main actor.
  - Constants at lines 18–21: `tick` 1 s, `gapThreshold`, `silenceHintAfter` (60 s, the system-audio hint,
    unrelated to this feature).
  - `start` (line 85) loads config once and builds `Meeting`, `SessionSupervisor`, `MeetingAudioPath`.
  - `handle(_: SupervisorEvent)` (line 189) switches over `.partial`, `.segment`, `.revision`, `.connection`,
    `.gap`.
  - `startTicker` (line 335) runs every second on `deps.clock`: `checkSystemAudio`, `.elapsed`, `.cost`.
  - `pause(_:)` (372), `resume()` (386), `stop(summarise:)` (415). `meetingTime` (330) is clock time since
    Start, paused spans included.
- `SessionSupervisor` yields `.partial(text)` for every partial, empty ones included (line 150), and
  `.connection(.connected)` once per session, when it first delivers (`markDelivered`, line 246).
  `.reconnecting(attempt:)` follows a lost session; `.rolledOver` a planned handover.
- Engines send empty partials during silence (Speechmatics `AddPartialTranscript`, AssemblyAI `Turn`).
- `MeetingCoordinator` (`App/Meeting/MeetingCoordinator.swift`) holds sessions.
  - `stop(summarise:)` (line 303) sets `isStopping`, routes a test call through `TestCallSession.finish`,
    then drops a finished session with no summary under way.
  - `release` (345) keeps a stopped session in `finishing` only while its summary is written or its Stop has
    not returned. A stop the coordinator did not start would drop the session before `.summary(.writing)`
    arrives, losing the summary's events.
  - `forwardEvents` (428) applies each event to the window model and reacts to `.state` and `.summary`.
- `MeetingControlling` (line 10) is the coordinator's view of the controller; `MeetingController` conforms at
  line 32. `AppTests/MeetingCoordinatorTests.swift:34` and `AppTests/TestCallSessionTests.swift:73` stub it.
- `MeetingWindowModel.apply` (`App/Meeting/MeetingWindowModel.swift:605`) is an exhaustive switch over
  `MeetingEvent`. `chips` (line 401) is `[String]`, drawn by `FinishedPage.head`
  (`App/Meeting/FinishedPage.swift:62`) as plain `Chip`s.
- `Chip` (`App/Design/Chip.swift`) has kinds plain, active, inactive, warning, test.
- `OverlayPanel` (`App/Overlay/OverlayPanel.swift`) is the non-activating floating panel precedent:
  `.borderless, .nonactivatingPanel`, `.floating`, all Spaces and full-screen auxiliary, `canBecomeKey`
  false. `DisplayPlacement.screenFrame(forPID:)` (`App/Overlay/DisplayPlacement.swift:29`) picks the display.
- `Config` (`Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`): meeting fields at lines 121–130,
  `validated()` at 146, keys at ~208. `ConfigStore.load()` returns a cached value
  (`ConfigStore.swift:56`).
- `Meeting` (`Packages/MiniWhisperCore/Sources/MWMeetings/MeetingModel.swift:176`) is synthesized Codable, so
  an optional field decodes as nil when absent, and older decoders ignore it.
- `Settings → Meetings → Recording` (`App/Settings/MeetingsSection.swift:62`) holds Your name, Keep meeting
  audio (75) and System Audio Recording (86). `SegmentedPill<Value: Hashable>` is the Theme row's control
  (`App/Settings/GeneralSection.swift:56`).
- Evidence from local meetings (timestamps and speaker ids only): no real meeting had a gap over 45 s; the
  forgotten one would have prompted at ~14:44 and stopped at ~14:45.

## 5. Design

### 5.1 Architecture / components

| Component | Where | Responsibility | Depends on |
|---|---|---|---|
| `SilenceWatch` (new) | `MWMeetingPipeline/SilenceWatch.swift` | Pure value type: the R2–R7 rules, fed times and texts, returns prompt changes | — |
| `SilencePrompt` (new) | `MWMeetingPipeline/MeetingEvent.swift` | The event payload: open, closed, expired | — |
| `MeetingController` | modified | Feeds the watch, emits `.silence`, `keepRecording()`, `stopAfterSilence()` | `SilenceWatch`, `ConfigStore` |
| `Config` | modified | `meetingSilenceStopSeconds` | — |
| `Meeting` | modified | `silenceStopSeconds: Int?` | — |
| `SilencePromptModel` (new) | `App/Meeting/SilencePrompt/` | Observable text, countdown and meter for the view | — |
| `SilencePromptView` (new) | `App/Meeting/SilencePrompt/` | The card (§5.3) | `SilencePromptModel`, `DS` |
| `SilencePromptPanel` (new) | `App/Meeting/SilencePrompt/` | Non-activating floating `NSPanel` hosting the view | — |
| `SilencePromptController` (new) | `App/Meeting/SilencePrompt/` | `SilencePrompting`: shows, updates, hides and places the panel | panel, model, `DisplayPlacement` |
| `MeetingCoordinator` | modified | Routes `.silence` to the prompt, stops on expiry through its own bookkeeping | `SilencePrompting` |
| `MeetingWindowModel`, `FinishedPage`, `Chip` | modified | Flag chip | — |
| `SettingsModel`, `MeetingsSection` | modified | The setting row | — |

`SilenceWatch` holds every rule so the rules are tested without a controller, clock or engine. The
controller only translates its events into watch calls, and the coordinator only translates `.silence` into
panel calls.

#### `SilenceWatch`

```swift
struct SilenceWatch: Sendable {
    static let grace = 180.0
    static let countdown = 60.0

    init(threshold: Int)                                   // seconds; 0 = Off
    private(set) var threshold: Int
    private(set) var isExpired: Bool
    private(set) var isSuspended: Bool                     // read by the controller on .connected
    private(set) var promptMinutes: Int                    // the open (or expired) prompt's minutes
    private(set) var lastSpeech: Double                    // for the "shown after N s" log

    mutating func partial(_ text: String, at time: Double) -> SilencePrompt?
    mutating func segment(_ text: String, at time: Double) -> SilencePrompt?
    mutating func keep(at time: Double) -> SilencePrompt?        // Keep recording
    mutating func suspend() -> SilencePrompt?                    // Pause, sleep, reconnecting
    mutating func restart(at time: Double)                       // Resume, connected after reconnecting
    mutating func setThreshold(_ seconds: Int) -> SilencePrompt?
    mutating func tick(at time: Double) -> SilencePrompt?
}
```

State: `lastSpeech` (0 at Start), `lastPartial`, `openedAt: Double?`, `promptMinutes`, `isSuspended`,
`isExpired`. Each mutating call returns the event to emit, or nil when nothing changed.

- `partial`: trimmed text non-empty and ≠ `lastPartial` → speech. `lastPartial` always takes the text, so an
  empty partial between two equal hypotheses lets the second count.
- `segment`: trimmed text non-empty → speech.
- Speech, and `keep`: `lastSpeech = time`; an open prompt closes → `.closed`.
- `suspend`: `isSuspended = true`; an open prompt closes → `.closed`.
- `restart`: `isSuspended = false`, `lastSpeech = time`.
- `setThreshold`: 0 with a prompt open → `.closed`. Other values apply to the next prompt.
- `tick`, in order:
  1. Expired or suspended → nil.
  2. Prompt open: left = `openedAt + 60 − time`. Left ≤ 0 → `isExpired = true`, `.expired`; else
     `.open(minutes: promptMinutes, secondsLeft: ceil(left))`.
  3. Closed, threshold > 0, `time ≥ 180`, `time − lastSpeech ≥ threshold` → open: `openedAt = time`,
     `promptMinutes = threshold / 60`, `.open(minutes:, secondsLeft: 60)`.
  4. Otherwise nil.
- After `isExpired`, every call returns nil: expiry is final, and speech in the instant before the stop does
  not reopen anything.

The 1 s tick means a prompt opens up to 1 s late and the stop comes 60 s after it opens, ±1 s.

#### `SilencePrompt` and the event

```swift
public enum SilencePrompt: Sendable, Equatable {
    /// Open, re-sent every tick with the seconds left.
    case open(minutes: Int, secondsLeft: Int)
    case closed
    /// The countdown ran out; the coordinator stops the meeting.
    case expired
}
// MeetingEvent
case silence(SilencePrompt)
```

#### `MeetingController` changes

- `private var silence: SilenceWatch?`: built in `start` from `config.meetingSilenceStopSeconds`; nil for a
  test call (`test != nil`).
- The expired prompt's threshold is `silence.promptMinutes * 60` (R4 with R7: a setting changed during the
  countdown does not change the open prompt, so it does not change what is recorded either).
- `handle(_: SupervisorEvent)`:
  - `.partial(text)` → `silence?.partial(text, at: meetingTime)`.
  - `.segment(segment, …)` → `silence?.segment(segment.text, at: meetingTime)`.
  - `.connection(.reconnecting)` → `suspend()`.
  - `.connection(.connected)` while `silence?.isSuspended == true` → `restart(at: meetingTime)`.
  - Each non-nil result is emitted as `.silence(_)`.
- Ticker: while `state == .recording`, `await configStore.load()`, then
  `setThreshold(config.meetingSilenceStopSeconds)` and `tick(at: meetingTime)`; emit any result. The load is
  the store's cached value; a changed `config.json` is picked up through the store's watcher.
- `pause(_:)` → `suspend()`. `resume()` → `restart(at: time)` with the time `audioPath.resume()` returned.
- `stop(summarise:)` → `suspend()` first, so any open prompt gets `.closed` whatever stopped the meeting.
- New public API, added to `MeetingControlling`:

```swift
/// Keep recording: closes the prompt; silence counts from now.
func keepRecording()
/// Design v7 R4: stops with a summary and records the threshold, only after the countdown expired.
func stopAfterSilence() async
```

`stopAfterSilence` guards `silence?.isExpired == true` and `state == .recording`, sets
`meeting?.silenceStopSeconds = silence.promptMinutes * 60`, then `await stop(summarise: true)`. `stop` saves the field
with the rest of the meeting (line 448).

### 5.2 Data model

- `Config.meetingSilenceStopSeconds: Int = 60`, key `meeting_silence_stop_seconds`, with
  `Config.meetingSilenceStopChoices = [0, 60, 120, 300]`. Decoded with `try?`, like `main_window_frame`, so a
  wrong-typed value reads as 60 (R1) instead of making `ConfigStore` back the whole file up as corrupt; always
  encoded.
  `validated()` replaces a value outside the choices with 60.
- `Meeting.silenceStopSeconds: Int?`, JSON key `silenceStopSeconds`, documented "Set when the meeting stopped
  itself after this many seconds without speech." Added to `init` with default nil. Not copied to
  `IndexEntry`.
- No migration. `Meeting.currentSchema` stays 1: the field is additive and optional.

### 5.3 Interfaces

The accepted mockup is the reference for all three surfaces:
[mockup-v7-overview](./mockups/mockup-v7-overview.html#overview), published at
https://claude.ai/artifact/JM192Aos1DfWHvMZVGttrm.

#### Prompt panel

- **Card.** The Dialog card as a floating panel: 380 pt wide, `radius.card`, `color.card` fill, 1 px
  `color.line` border, `shadow.dialog` through the existing `.dialogShadow()` modifier
  (`App/Design/DS.swift:164`), which carries the dark value. No scrim.
- **Panel.** Transparent and padded so the shadow renders.
  - `SilencePromptPanel: NSPanel` with `[.borderless, .nonactivatingPanel]`, level `.floating`,
    `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`,
    `canBecomeKey` and `canBecomeMain` false.
  - Its hosting view returns true from `acceptsFirstMouse(for:)`, so the first click on a button acts.
- **Placement.** Each time it opens:
  - Screen: `DisplayPlacement.screenFrame(forPID:)` for the frontmost app.
  - Centred horizontally; card top at 20% of that screen's height from its top.
  - `SilencePromptController.frame(size:on:)` is a pure static function.
- **Content, top to bottom:**
  - **Eyebrow.** The recording pill's four bars at rest, in `color.recording`, then "Recording · <meeting
    title>" in `type.meta`, `color.text.secondary`, one line, truncated in the middle.
  - **Title.** `type.title.dialog`: "No one has spoken for 1 minute" or "… for N minutes". N is the
    `minutes` of the event, so it follows the setting.
  - **Body.** `type.body`, `color.text.secondary`: "Recording stops in M:SS unless you keep it going.", where
    M:SS is `secondsLeft`, semibold, tabular digits.
  - **Meter.** 4 pt pill, `color.recording` on `color.hover`, width fraction `secondsLeft / 60`, stepping
    each second.
  - **Buttons**, right-aligned: "Stop now" (Pill button, secondary outlined, label in `color.recording`),
    then "Keep recording" (Pill button, primary filled, the page's one filled button).
  - No close box, no Return or Esc handling: the panel never becomes key.
- **Accessibility.** On open the controller posts an `announcementRequested` notification with the title.

```swift
@MainActor protocol SilencePrompting: AnyObject {
    func show(meetingTitle: String, minutes: Int, secondsLeft: Int,
              keep: @escaping @MainActor () -> Void, stop: @escaping @MainActor () -> Void)
    func hide()
}
```

`show` on an open panel only updates the model; it neither repositions nor re-announces.

`SilencePromptModel` (`@Observable @MainActor`) holds `meetingTitle`, `minutes` and `secondsLeft`, and
derives `title`, `countdownText` ("0:42") and `fraction`.

#### Coordinator

- `Dependencies.silencePrompt: any SilencePrompting`. `AppDelegate` passes one `SilencePromptController`.
- `forwardEvents`:
  - `.silence(.open(m, s))` → `show(meetingTitle: session.model.title, …)`. `keep` calls
    `session.controller.keepRecording()`. `stop` calls `self.stop()`, the manual Stop.
  - `.silence(.closed)` → `hide()`.
  - `.silence(.expired)` → `hide()`, then `Task { await self?.stopAfterSilence() }`.
  - `.state` other than `.recording` from the session that opened the prompt → `hide()`, a backstop. Another
    session's state leaves it: opening a stored meeting emits `.state(.stopped)` for that meeting (R5).
- New `stopAfterSilence()` shares `stop`'s bookkeeping:
  - guards `current`, `isStoppable`, `test == nil`;
  - sets `isStopping` and awaits `controller.stopAfterSilence()`;
  - clears `isStopping`;
  - drops a finished session whose summary is not being written.
  - Implementation: a private `stop(_ session:, using:)` taking the controller call, so the two entry points
    cannot drift.
- A silence stop never presents the meeting page, the same as `stop()`.

#### Settings row

- **Placement and control.** `SettingRow("Stop after silence", description:)` after Keep meeting audio, with
  `SegmentedPill(selection:, options: [(0, "Off"), (60, "1 min"), (120, "2 min"), (300, "5 min")])`, bound
  through `settingsBinding` to `SettingsModel.setMeetingSilenceStop(_:)`.
- **Description**, `SettingsModel.silenceStopDescription(_ seconds: Int)`, follows the value:
  - On: "When no one has spoken for N min, asks whether to keep recording and stops a minute later. Never
    in a meeting's first 3 minutes."
  - Off: "Off: a meeting records until you stop it."

#### Finished page

- `MeetingWindowModel.chips` becomes `[HeaderChip]`, with
  `struct HeaderChip: Equatable { text: String; kind: Chip.Kind; symbol: String? }`.
- With `meeting.silenceStopSeconds = s`, the chip "Stopped after \(s / 60) min without speech" (kind
  `.flag`, symbol `pause.circle`) goes right after the duration chip.
- `FinishedPage.head` draws `Chip(chip.text, chip.kind, symbol: chip.symbol)`.
- `Chip` gains `case flag`: text `color.text`, border `color.line`, fill `color.sidebar`. It also gains an
  optional leading SF Symbol drawn in `color.text.secondary` at the label size.
- `MeetingWindowModel.apply` handles `.silence` as a no-op: the prompt lives outside the window.

### 5.4 Design language

- References: [DESIGN.md](../../DESIGN.md) and the specimen
  ([design/specimen.html](../../design/specimen.html),
  https://claude.ai/artifact/3iQhWG4jNhvrqA4EXTwHGh).
- Deltas recorded by `design-language-update`, both `pending v7`:
  - **Decision 72:** Floating prompt, category other. `radius=radius.card; bg=color.card;
    border=color.line; shadow=shadow.dialog`. A Dialog card without a scrim, outside any window.
  - **Decision 73:** Chip Flag variant. `flag=color.sidebar; flaglabel=color.text`.
- Everything else is recorded:
  - Dialog card values, `type.title.dialog`, `type.body`, `type.meta`;
  - Pill button primary and secondary (decision 57: one filled button);
  - `color.recording`, `color.hover`, recording bars (decision 55, at rest);
  - Segmented pill switch, Setting row, Chip.
- Decision 59 (no shadow inside a window) holds: the prompt is its own window, lifted like a dialog.
- Drift touching these surfaces: none. The one recorded drift (Earlier runs sheet) is elsewhere.

### 5.5 Control flow

**Happy path, forgotten recording, setting 1 min.**

1. Start at 14:30. Words until 14:43:10, then nothing; partials go empty.
2. Each tick: meeting time ≥ 180, silent < 60 → nothing.
3. 14:44:10: the tick opens the prompt → `.silence(.open(1, 60))` → coordinator → panel shows on the front
   app's display. It does not take focus.
4. Each tick: `.open(1, 59…1)` updates the countdown and meter.
5. 14:45:10: `.expired` → panel hides → `coordinator.stopAfterSilence()` → `controller.stopAfterSilence()` →
   field set → `stop(summarise: true)` → saved, summarised. The sidebar pill disappears; the list shows the
   meeting.
6. Opening it shows the Flag chip.

**Keep recording.** Click → `keepRecording()` → `.closed` → hide. Silence counts from the click, so the next
prompt can open 1 min later.

**Stop now.** Click → `coordinator.stop()` → `controller.stop(summarise: true)`: `suspend` → `.closed` →
hide. No field.

**Speech during the countdown.** A new non-empty partial → `.closed` → hide.

**Pause during the countdown.** `.closed`; no ticks are evaluated while paused. Resume → `restart`; a prompt
can come 1 min after Resume.

**Grace.** No prompt before 3:00; at 3:00 the rule uses the last words (words at 0:10 → prompt at 3:00).

### 5.6 Failure and edge cases

- **Mac sleeps** during the countdown: `pause(.sleep)` → `.closed`. The meeting stays paused on wake, as today.
- **Session lost:** `.reconnecting` → `.closed`, watch suspended. Transcripts cannot arrive, so no silence is
  inferred. The first delivery after reconnecting (`.connected`) restarts the clock.
- **Rollover:** `.rolledOver` and the new session's `.connected` do not touch the watch (it was not
  suspended).
- **Setting turned Off** while open: `.closed` on the next tick. Turned On mid-meeting: the next tick uses it,
  silence measured from the last words.
- **Two stops race** (Stop now and expiry in the same second): the second `stop` finds `.stopping` and
  returns. If the manual stop wins, `stopAfterSilence` returns at its `state == .recording` guard, so no
  field is set.
- **Quit** during the countdown: the quit path stops the meeting (`stop(summarise: false)`), whose `suspend`
  closes the prompt. No field.
- **Test call:** no watch. Its conductor stops it.
- **Empty meeting title** (the user cleared it): the eyebrow reads "Recording" alone.
- **Several displays:** placement is computed on open only; the panel does not follow focus while open.
- **Remote call without System Audio Recording permission:** only the user's side is transcribed, so a long
  remote monologue can prompt. The existing silence hint already flags the missing permission; Keep resets
  (§7).

### 5.7 Security

No new trust boundary, input or secret. `config.json`'s value is validated against the four choices. Logs
carry times and thresholds, never transcript text.

### 5.8 Performance

One `ConfigStore.load()` per second while recording, an actor hop returning the cached value. `SilenceWatch`
is O(1) per call; one string compare per partial. The panel is created lazily on the first prompt and reused.

### 5.9 Observability

`Log.meeting.info`:
- "silence prompt shown after \(Int(silent)) s";
- "silence prompt closed (\(reason))", reason one of kept, speech, paused, stopped, setting, reconnecting;
- "meeting stopped after silence (\(threshold) s)".

### 5.10 Compatibility / migration

- **Meetings.** Old `meeting.json` without the field decodes as nil. 0.7.0 and earlier decode new files and
  ignore the field; such an app saving the meeting again drops it (§7).
- **Config.** Old files take the default, 60. The key is always written; older Swift builds keep it in
  `extra` and round-trip it.
- **Behaviour.** Existing users get the prompt by default (1 min). The CHANGELOG entry says so and names the
  setting.

### 5.11 Testing strategy

- **`SilenceWatchTests`** (MWMeetingPipelineTests), pure, times as arguments:
  - no prompt before 180 s however long the silence;
  - prompt at 180 s with no speech, and at last speech + threshold after the grace;
  - repeated, empty and whitespace partials are not speech;
  - an empty partial between two equal texts lets the second count;
  - a non-empty segment is speech;
  - countdown values 60…1, then `.expired` once; nil after expiry;
  - `keep` closes and restarts the clock;
  - `suspend` closes, ticks ignored, `restart` restarts the clock;
  - threshold 0 closes an open prompt; another threshold keeps the countdown and minutes; 120 and 300 open
    at their thresholds.
- **`MeetingControllerSilenceTests`** (VirtualClock, fake engine):
  - `.silence(.open(1, 60))` at 180 s;
  - a partial closes it;
  - pause closes, resume restarts;
  - `.reconnecting` closes, `.connected` after it restarts;
  - `stopAfterSilence()` before expiry does nothing; after expiry it stops, summarises and saves
    `silenceStopSeconds = 60`;
  - a test call never emits `.silence`;
  - Off in config never prompts;
  - Off written mid-countdown closes on the next tick;
  - stop by any path emits `.closed` while open.
- **`ConfigCodingTests`:** default 60, decode and encode of the key, out-of-set → 60, round trip.
- **`MeetingModelTests`:** decode without the field → nil; with it → value; encode includes the key only when
  set.
- **`SilencePromptModelTests`** (AppTests): "1 minute" / "5 minutes", "1:00", "0:42", "0:05", fraction.
- **`SilencePromptPlacementTests`:** frame centred, top at 20% of the screen, on a secondary display.
- **`MeetingCoordinatorTests`** (stubbed controller, fake `SilencePrompting`):
  - open → show with the title, repeated open → update;
  - closed → hide; non-recording state → hide;
  - expired → hide and exactly one `stopAfterSilence`;
  - the prompt's Stop → `stop(summarise: true)`, not `stopAfterSilence`;
  - Keep → `keepRecording`;
  - a session stopped by silence while off the page keeps receiving its summary events (the `finishing`
    rule).
- **`MeetingWindowModelTests`:** the Flag chip after the duration chip only with the field; its text per
  value. The existing chip assertions (lines 675–689) compare `chips.map(\.text)`.
- **`SettingsModelTests`:** `setMeetingSilenceStop` writes the key; the description per value.
- **Stubs:** `StubController` in `MeetingCoordinatorTests` and `TestCallSessionTests` gain the two new
  methods; the `Dependencies` built at `MeetingCoordinatorTests.swift:184` gains the fake
  `SilencePrompting`.
- **Manual acceptance:**
  - Set 1 min, start an in-room meeting, stay silent.
  - At 3:00 the prompt shows over a full-screen app on the front display, typing in that app continues, and
    one click on Keep works.
  - Stay silent again: the meeting stops one minute after the next prompt, the summary is written, and the
    finished page shows the chip.
  - Repeat in dark theme.

## 6. Alternatives considered

- **Audio-level silence** (microphone gate plus system-audio peak): rejected. Room noise, music and a muted
  call's hum keep levels up, and the user's question is whether anyone spoke, which the transcript answers.
- **The controller stopping itself on expiry:** rejected. It would bypass the coordinator's `isStopping` and
  `finishing` bookkeeping; a meeting stopped off the page would be dropped before its summary began.
- **A new `Marker` kind for the stop:** rejected. App 0.7.0 and earlier cannot decode an unknown marker kind,
  so a rollback would break those meetings.
- **An activating modal, or a system notification:** rejected by the user. An activating modal steals focus
  from the call or chat; a notification is easily missed.
- **Re-prompting only after speech resumes:** rejected by the user. A forgotten recording would run on after
  one Keep.
- **A grace that lasts until the first words:** rejected by the user in favour of a flat 3 min.

## 7. Risks and issues

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| A real silent stretch (everyone reading, a video with no speech) goes unanswered and the meeting stops mid-meeting | Low / medium | 3 min grace, one-click Keep, 2 / 5 min / Off; no real meeting showed a gap over 45 s; the stop keeps everything so far, and a new meeting can be started |
| The first click on the non-activating panel only focuses it, so Keep appears to do nothing | Medium / high | `acceptsFirstMouse` true on the hosting view; verified manually over a full-screen app (§5.11) |
| Engine noise (non-empty partials from background TV) keeps resetting the clock, so a forgotten recording runs on | Low / medium | Repeated partials do not count; the outcome is today's behaviour, no worse |
| Remote call without the system-audio permission: the other side is not transcribed, so their monologue prompts | Medium / low | The existing silence hint asks for the permission; Keep resets |
| A reconnect loop suppresses the prompt indefinitely | Low / low | Nothing is transcribed in that state anyway; the connection chip already shows it |
| 0.7.0 or earlier re-saving a meeting drops `silenceStopSeconds` | Low / low | Only the chip is lost; the meeting is intact |
| Default-on changes behaviour for existing users | Certain / low | CHANGELOG names the change and the setting |

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

- Ships in the next release (0.8.0), on by default at 1 min. No feature flag: the setting is the switch, and
  Off restores today's behaviour.
- CHANGELOG `[Unreleased]` → Added: "Meetings stop after silence: with no speech for a minute (never in the
  first 3), a prompt offers to keep recording and stops the meeting a minute later. Settings → Meetings →
  Stop after silence."
- After implementation, `/design-language-update` turns decisions 72 and 73 from `pending v7` to active.
- Rollback: Off in Settings, or a downgrade; both leave every meeting readable.

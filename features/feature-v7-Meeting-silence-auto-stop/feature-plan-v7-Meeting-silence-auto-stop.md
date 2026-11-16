# Meeting Silence Auto-Stop — Implementation Plan v7

**Status:** Draft
**Date:** 2026-11-16
**Design:** [feature-design-v7-Meeting-silence-auto-stop.md](./feature-design-v7-Meeting-silence-auto-stop.md)

## Overview

v7 stops a forgotten meeting: after a stretch with no transcribed speech (default 1 min, never in the first
3 min) a non-activating floating prompt counts down one minute, and an unanswered prompt stops and summarises
the meeting, whose finished page then carries a Flag chip. The plan has 9 stages. **Core (1–3)** lands the
`meeting_silence_stop_seconds` key, the optional `Meeting.silenceStopSeconds` and the pure `SilenceWatch` rules,
each test-first on Swift Testing. **Prompt (4)** builds the floating panel, its model and placement in the app,
self-contained behind the `SilencePrompting` protocol. **Wiring (5–8)** feeds the watch from
`MeetingController` and emits `.silence`, adds the Settings row, the Flag chip, and finally routes `.silence`
through `MeetingCoordinator` to the panel and to a stop that keeps the coordinator's bookkeeping. **Docs (9)**
records the change. Every stage leaves both suites green and the app building; the user-visible feature appears
only with Stage 8, and nothing is released before Stage 9 (design §9). Stages 1–4 have no dependency on each
other and form one parallel batch.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only | integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests, platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a one-line justification.

In Swift a test naming a type or member that does not exist yet fails to **compile**; that is the first red.
The step then adds the minimal empty API (members returning nil, defaults or no-ops) and re-runs to see
**assertion** failures before implementing. Every "confirm fail" step below names both.

**Runners and checks** (each run once on 2026-11-16 at `51bcb14`, before drafting):

| Check | Command | Observed baseline |
|---|---|---|
| Core tests | `cd Packages/MiniWhisperCore && swift test` | 17 Swift Testing runs (one per test target), 1006 tests, every one `✔ … passed`; each run is preceded by an empty XCTest `Executed 0 tests` line |
| One core suite | `cd Packages/MiniWhisperCore && swift test --filter <Suite>` | `--filter MeetingControllerLifecycleTests` → `✔ Test run with 13 tests in 1 suite passed` |
| Core build | `cd Packages/MiniWhisperCore && swift build` | `Build complete!`, exit 0 |
| App tests | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` | `✔ Test run with 438 tests in 44 suites passed` and `** TEST SUCCEEDED **` (the `com.apple.linkd.autoShortcut` connection lines are host noise) |
| One app suite | the app-test command plus `-only-testing:AppTests/<Suite>` | `-only-testing:AppTests/MeetingCoordinatorTests` → `✔ Test run with 51 tests in 1 suite passed`, `** TEST SUCCEEDED **` |
| App build only | the app-test command with `build` in place of `test` | `** BUILD SUCCEEDED **`, exit 0 |

Read the `✔/✘ Test run with …` line, not the XCTest line. The app target is the only one without host tests
for its views, so its build is the check that every view still compiles after a core change.

- **Core-only stages** (1, 2, 3) run the focused suite, the core suite, then the app **build** — never the app
  test host, so they can share a batch with an app-test stage (see *Execution schedule*).
- **Stages that touch the app** run the focused suite, the core suite, the app suite, then the app build.

**Registration.** New core files go into existing SwiftPM targets (`MWMeetingPipeline`,
`MWMeetingPipelineTests`), which compile every file in their folder: `Package.swift` is unchanged. New `App/` and
`AppTests/` files, including the new folder `App/Meeting/SilencePrompt/`, are picked up by xcodegen's recursive
folder sources (`project.yml` `sources: - path: App` / `- path: AppTests`) at the next `xcodegen generate`; the
generated `Mini Whisper.xcodeproj` is git-ignored and never staged.

**Test locations.** Core suites follow `Packages/MiniWhisperCore/Tests/<Module>Tests/<Type>Tests.swift`:
`SilenceWatchTests.swift` sits beside `SpeechGateTests.swift` and uses `@testable import MWMeetingPipeline` as
`MeetingControllerEditingTests.swift` does (the watch is internal); `MeetingControllerSilenceTests.swift` sits
beside `MeetingControllerLifecycleTests.swift` and uses the shared `MeetingHarness` in
`MeetingControllerTests.swift`. App suites follow `AppTests/<Type>Tests.swift` with `@testable import
MiniWhisper`, as `AppTests/DisplayPlacementTests.swift` and `AppTests/SettingsModelTests.swift` do. Durations
run on `VirtualClock` (core); the app pieces hold no durations of their own — the countdown arrives as events —
so no app stage needs `AppTests/ManualClock.swift` (R11).

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: `meeting_silence_stop_seconds` ∈ {0, 60, 120, 300}, default 60, anything else 60; 0 is Off | Stage 1 |
| R2: speech is a new non-empty partial or a non-empty final segment; empty, repeated partials and revisions are not | Stage 3, Stage 5 |
| R3: prompt opens when recording, not a test call, threshold > 0, time ≥ 180 s, silent ≥ threshold, not reconnecting | Stage 3, Stage 5 |
| R4: 60 s countdown; at 0 the meeting stops with a summary and records the threshold | Stage 2, Stage 3, Stage 5, Stage 8 |
| R5: closes on Keep, Stop now, speech, Pause or sleep, any stop, Off, reconnecting | Stage 3, Stage 5, Stage 8 |
| R6: after Resume silence counts from Resume; after a reconnect from the next `.connected` | Stage 3, Stage 5 |
| R7: threshold read every tick; Off closes; other values apply to the next prompt | Stage 3, Stage 5 |
| R8: non-activating, above every window and full-screen Space, never key, no shortcuts, no close box, on the placed display, as the mockup | Stage 4, Stage 8 |
| R9: "Stop after silence" row after Keep meeting audio | Stage 6 |
| R10: Flag chip after the duration chip only with the field; optional `meeting.json` field; index, exports, CLI, MCP unchanged | Stage 2, Stage 7 |
| R11: grace, threshold and countdown tested on `VirtualClock` / `ManualClock`; no real sleeps | Stage 3, Stage 5 |

**User-visible behaviour after each contributing stage.** After Stages 1–4 nothing changes: the key is read by
nothing, the field is set by nothing, the watch and the panel have no caller. After Stage 5 the controller
emits `.silence` and would expire a forgotten meeting's watch, but the app ignores the event (`apply` no-op, the
coordinator's `default:`), so recording behaves as today. After Stage 6 the Settings row writes the key, which
still has no visible effect. After Stage 7 the chip renders only for a meeting carrying the field, which nothing
sets yet. Stage 8 turns it all on. Each intermediate state is today's behaviour, so the stages stay separate
rather than bundled; the one rule is that no release is cut between Stage 6 and Stage 8 (*Risks*).

## Stages

### Phase A — Core rules and the prompt surface

### Stage 1 — The `meeting_silence_stop_seconds` key
**Goal:** `Config` carries the silence threshold: 0, 60, 120 or 300, default 60, any other value 60, always written.
**Design references:** §3 R1, §5.2, §5.10 of feature-design-v7-Meeting-silence-auto-stop.md
**Touches:** `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`, `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`, `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigStoreTests.swift`

**Steps (TDD):**
1. Write tests in `ConfigCodingTests.swift`:
   - `silenceStopAbsentTakesSixty` — `decode("{}").meetingSilenceStopSeconds == 60`;
   - `silenceStopRoundTripsEachChoice` (`@Test(arguments: [0, 60, 120, 300])`) — decoded value equals the
     argument; `saved(config)["meeting_silence_stop_seconds"] as? Int` equals it; and
     `Config.meetingSilenceStopChoices == [0, 60, 120, 300]`;
   - `silenceStopOutsideTheChoicesValidatesToSixty` — a config holding 45, −1, 61 or 600 gives 60 from
     `validated()`; `{"meeting_silence_stop_seconds": "5"}` decodes without throwing and reads 60;
   - `silenceStopIsWrittenForANewConfig` — `saved(Config())["meeting_silence_stop_seconds"] as? Int == 60`;
   - `silenceStopNeverLandsInExtra` — decoding the key leaves `extra` empty.
   In `ConfigStoreTests.swift`: `silenceStopLoadsAChoiceAndReadsAnythingElseAsSixty` — `config.json` holding
   `{"meeting_silence_stop_seconds": 300}` loads as 300, and one holding 45 loads as 60 (pattern of
   `migratesDailyUsageForToday`).
   Expected initial failure: compile error `value of type 'Config' has no member 'meetingSilenceStopSeconds'`.
2. Run `swift test --filter MWConfigTests` — confirm the compile error. Add only
   `public var meetingSilenceStopSeconds = 60` and `public static let meetingSilenceStopChoices = [0, 60, 120, 300]`,
   re-run, and confirm assertion failures: the round trip reads 60 for 0/120/300, the key is absent from the
   saved object and present in `extra`, `validated()` keeps 45, and the store loads 300 as 60.
3. Implement in `Config.swift`: `Key.meetingSilenceStopSeconds = "meeting_silence_stop_seconds"`, added to
   `Key.all`; decode with `if let value: Int = try? value(Key.meetingSilenceStopSeconds)` (the
   `main_window_frame` precedent, so a wrong type reads as the default instead of failing the whole file);
   encode it unconditionally; in `validated()` replace a value not in `meetingSilenceStopChoices` with 60.
4. Run the focused suite — pass. Core suite — 17 runs green. App build only — `** BUILD SUCCEEDED **`.

**Definition of done:**
- The six tests pass; `ConfigCodingTests` and `ConfigStoreTests` otherwise unchanged and green.
- A new `config.json` contains `"meeting_silence_stop_seconds" : 60`; an out-of-set or wrong-typed value reads as 60.

**Risks specific to this stage:** None.

### Stage 2 — `Meeting.silenceStopSeconds`
**Goal:** `meeting.json` carries the optional `silenceStopSeconds`, absent when unset, without touching the index, exports, CLI or MCP output.
**Design references:** §3 R10, §5.2, §5.10
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingModel.swift`, `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingModelTests.swift`, `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingMarkdownTests.swift`

**Steps (TDD):**
1. Write tests in `MeetingModelTests.swift`:
   - `silenceStopAbsentDecodesAsNil` — `MeetingFixtures.northwind().meeting` encoded, then decoded: `silenceStopSeconds == nil`;
   - `silenceStopRoundTrips` — a meeting with `silenceStopSeconds: 120` encodes `"silenceStopSeconds": 120` and decodes equal;
   - `silenceStopIsOmittedWhenUnset` — the encoded object of a meeting without it has no `silenceStopSeconds` key;
     `schema` is still 1.
   Guard in `MeetingMarkdownTests.swift`: `silenceStopLeavesTheMarkdownUnchanged` — the northwind fixture with
   `silenceStopSeconds = 60` still matches the transcript and summary goldens (the `get_*` MCP tools and the CLI
   render this Markdown; `list`/`search` encode `IndexEntry` and hits, which have no such field).
   Expected initial failure: compile error `value of type 'Meeting' has no member 'silenceStopSeconds'` (and
   `extra argument 'silenceStopSeconds' in call`).
2. Run `swift test --filter MWMeetingsTests` — confirm the compile error. Scaffold the stored property and the
   `init` parameter without assigning it (`silenceStopRoundTrips` builds its meeting through `init`); re-run —
   confirm `silenceStopRoundTrips` fails (`nil` ≠ 120, no `silenceStopSeconds` key in the encoded object).
3. Implement in `MeetingModel.swift`: `/// Set when the meeting stopped itself after this many seconds without
   speech.` `public var silenceStopSeconds: Int?`, appended as the last `init` parameter
   (`silenceStopSeconds: Int? = nil`) and assigned. Synthesized `Codable` encodes it with `encodeIfPresent`.
   `currentSchema` stays 1; `IndexEntry` is untouched.
4. Run the focused suite — pass. Core suite — green. App build only — succeeds (every `Meeting(...)` call site
   compiles unchanged through the default).

**Definition of done:**
- The four tests pass; the goldens are unchanged.
- `git diff` shows no change to `IndexEntry`, `MeetingMarkdown.swift`, or anything under `MWAgentAccess`.

**Risks specific to this stage:** None.

### Stage 3 — `SilenceWatch` and `SilencePrompt`
**Goal:** a pure value type holds every R2–R7 rule, fed meeting times and texts and returning the prompt change to emit.
**Design references:** §3 R2–R7, R11; §5.1 (`SilenceWatch`, `SilencePrompt`); §5.5; §5.6; §5.11
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SilenceWatch.swift` (new), `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingEvent.swift` (the `SilencePrompt` enum only — not the `MeetingEvent` case), `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SilenceWatchTests.swift` (new)

**Steps (TDD):**
1. Write `SilenceWatchTests.swift` (`@Suite struct SilenceWatchTests`, `@testable import MWMeetingPipeline`;
   times are arguments, no clock):
   - `noPromptBeforeTheGraceHoweverLongTheSilence` — threshold 60: `tick(at:)` is nil at 61, 120, 179.9;
   - `promptAtTheGraceWithNoSpeech` — `tick(at: 180) == .open(minutes: 1, secondsLeft: 60)`;
   - `promptAtLastSpeechPlusThresholdAfterTheGrace` — segment at 170 → nil at 229, `.open(1, 60)` at 230;
   - `repeatedEmptyAndWhitespacePartialsAreNotSpeech` — `partial("so", at: 150)` counts; `partial("so", at: 180)`,
     `partial("", at: 190)` and `partial("  ", at: 200)` do not → nil at 209, `.open(1, 60)` at 210 (any of the
     last three counting would push it to 240 or later);
   - `anEmptyPartialBetweenTwoEqualTextsLetsTheSecondCount` — `partial("so", 100)`, `partial("", 110)`,
     `partial("so", 150)` → nil at 209, open at 210;
   - `aNonEmptySegmentIsSpeechAnEmptyOneIsNot`;
   - `countdownRunsSixtyToOneThenExpiresOnce` — ticks 180…239 return `.open(1, 60)`…`.open(1, 1)`, 240 returns
     `.expired`, `isExpired` is true, and every later call (`tick`, `partial`, `segment`, `keep`, `suspend`,
     `setThreshold`) returns nil;
   - `fractionalTicksRoundSecondsLeftUp` — open at 180, `tick(at: 180.4) == .open(1, 60)`;
   - `keepClosesAndRestartsTheClock` — open at 180, `keep(at: 200) == .closed`, nil at 259, open at 260;
   - `speechWhileOpenCloses` — `partial("back", at: 190) == .closed`;
   - `suspendClosesIgnoresTicksAndRestartRestartsTheClock` — `suspend() == .closed`, `isSuspended`, ticks nil;
     `restart(at: 300)`; nil at 359, open at 360 (no new grace); `suspend()` with no prompt open returns nil;
   - `thresholdZeroClosesAnOpenPromptAndNeverOpens` — `setThreshold(0) == .closed`, then ticks nil;
   - `anotherThresholdKeepsTheOpenCountdownAndMinutes` — open (1 min) at 180, `setThreshold(300) == nil`,
     `tick(at: 200) == .open(minutes: 1, secondsLeft: 40)`, expiry at 240, `promptMinutes == 1`;
   - `thresholdsOfTwoAndFiveMinutesOpenAtTheirThresholds` — speech at 100: threshold 120 opens at 220 with
     minutes 2, threshold 300 at 400 with minutes 5; with no speech, 120 opens at 180 with minutes 2;
   - `lastSpeechTracksTheLatestSpeech` — `lastSpeech` is 0 at start and the time of the latest speech, keep or
     restart.
   Expected initial failure: compile error `cannot find 'SilenceWatch' in scope` /
   `cannot find type 'SilencePrompt' in scope`.
2. Run `swift test --filter SilenceWatchTests` — confirm the compile error. Scaffold `public enum SilencePrompt`
   in `MeetingEvent.swift` (`open(minutes:secondsLeft:)`, `closed`, `expired`; `Sendable, Equatable`) and
   `struct SilenceWatch: Sendable` with the §5.1 surface — `grace = 180.0`, `countdown = 60.0`, `init(threshold:)`,
   read-only `threshold`, `isExpired`, `isSuspended`, `promptMinutes`, `lastSpeech`, and every mutating method
   returning nil. Re-run — confirm assertion failures (`tick(at: 180)` is nil, expected `.open(minutes: 1,
   secondsLeft: 60)`; `suspend()` nil, expected `.closed`).
3. Implement `SilenceWatch.swift` per design §5.1: state `lastSpeech` (0), `lastPartial`, `openedAt: Double?`,
   `promptMinutes`, `isSuspended`, `isExpired`; `partial` trims, counts a non-empty text that differs from
   `lastPartial`, always stores the text; `segment` counts a non-empty trimmed text; speech and `keep` set
   `lastSpeech` and close an open prompt; `suspend`/`restart`/`setThreshold`/`tick` exactly as the four-step tick
   rule (`secondsLeft = Int(ceil(openedAt + 60 − time))`); after `isExpired` every call returns nil.
4. Run the focused suite — pass. Core suite — green. App build only — succeeds.

**Definition of done:**
- Every bullet of design §5.11 `SilenceWatchTests` has a passing test; no clock or sleep in the suite.
- `SilenceWatch` is internal; `SilencePrompt` is public; `MeetingEvent` is not yet changed.

**Risks specific to this stage:** None.

### Stage 4 — The floating prompt
**Goal:** a reusable non-activating panel shows the silence card on the front app's display, updates it in place and hides it, behind `SilencePrompting`.
**Design references:** §3 R8; §5.1; §5.3 *Prompt panel*; §5.4; §5.6 (empty title, several displays); §5.8; `DESIGN.md` — Dialog card, decision 72 (Floating prompt), Pill button (decision 57), `color.recording`, `color.hover`, recording bars at rest (decision 55), `type.title.dialog`, `type.body`, `type.meta`
**Category:** hybrid — full TDD for the model, the placement, the panel's attributes and the controller's show/update/hide rules; *platform-only remainder*: the SwiftUI card's look, verified by the app build here and by the manual acceptance in Stage 8 (light and dark, over a full-screen app).
**Touches:** `App/Meeting/SilencePrompt/SilencePromptModel.swift` (new), `App/Meeting/SilencePrompt/SilencePromptView.swift` (new), `App/Meeting/SilencePrompt/SilencePromptPanel.swift` (new), `App/Meeting/SilencePrompt/SilencePromptController.swift` (new; also declares `SilencePrompting`), `App/Design/DSDialog.swift` (extract the card chrome), `AppTests/SilencePromptModelTests.swift` (new), `AppTests/SilencePromptControllerTests.swift` (new)

**Steps (TDD):**
1. Write tests:
   - `AppTests/SilencePromptModelTests.swift` — `title` is "No one has spoken for 1 minute" for 1 and
     "No one has spoken for 2 minutes" / "… 5 minutes"; `countdownText` is "1:00", "0:42", "0:05", "0:00" for
     60, 42, 5, 0; `fraction` is 1, 0.7, 0 for 60, 42, 0; `eyebrow` is "Recording · Standup", and "Recording"
     for an empty or whitespace title.
   - `AppTests/SilencePromptControllerTests.swift`:
     - `frameIsCentredWithTheCardTopAtAFifthOfTheScreen` — `SilencePromptController.frame(size:on:)` for a
       380×180 card on the 1920×1080 primary: card `midX == 960`, card top `== 1080 − 216`, returned panel frame
       outset by `SilencePromptPanel.shadowPadding` on every side;
     - `frameFollowsASecondaryDisplay` — the same on a 1440×900 screen at x 1920 (the `DisplayPlacementTests` layout);
     - `panelNeverTakesFocusAndShowsOnEverySpace` — a `SilencePromptPanel` has `.borderless` and
       `.nonactivatingPanel` in `styleMask`, `level == .floating`, `collectionBehavior` containing
       `.canJoinAllSpaces` and `.fullScreenAuxiliary`, `hidesOnDeactivate == false`, `canBecomeKey == false`,
       `canBecomeMain == false`, a clear non-opaque background; its hosting view's `acceptsFirstMouse(for: nil)` is true;
     - `firstShowPlacesAnnouncesAndOrdersFront` — with a recording panel subclass, a fixed `screen` and a
       recording `announce`: one `setFrame`, one `orderFrontRegardless`, one announcement equal to the title;
     - `showWhileOpenOnlyUpdatesTheModel` — a second `show(… secondsLeft: 41 …)` changes `model.secondsLeft`
       to 41 and records no further frame, order-front or announcement, even when `screen` now returns another display;
     - `hideOrdersOutAndTheNextShowPlacesAgain`;
     - `buttonsCallTheLatestClosures` — the model's `keep()`/`stop()` call the closures of the last `show`.
   Expected initial failure: compile error `cannot find 'SilencePromptModel' in scope` (and
   `cannot find 'SilencePromptController' in scope`).
2. Run `-only-testing:AppTests/SilencePromptModelTests -only-testing:AppTests/SilencePromptControllerTests` —
   confirm the compile error. Scaffold the four types with empty members (model strings empty, `fraction` 0,
   `frame` returning `.zero`, `show`/`hide` doing nothing, the panel a bare `NSPanel` subclass); re-run — confirm
   assertion failures (title `""` ≠ "No one has spoken for 1 minute"; frame `.zero`; `styleMask` lacks
   `.nonactivatingPanel`; no `orderFrontRegardless` recorded).
3. Implement:
   - `SilencePromptModel` (`@Observable @MainActor`): `meetingTitle`, `minutes`, `secondsLeft`, the latest
     `keep`/`stop` closures; derived `eyebrow`, `title`, `countdownText` (`m:ss`), `fraction` (`secondsLeft / 60`).
   - `DSDialog.swift`: move the card chrome (padding `22 + hairline`, width 380, `color.card` fill with
     `.dialogShadow()`, `color.line` border, `radius.card`) into a `View.dialogCard()` modifier and use it in
     `DSDialog` — behaviour-preserving for the two existing dialogs.
   - `SilencePromptView`: `.dialogCard()`; eyebrow (`PulseBars(active: false)` in `DS.Colors.recording`, then
     the eyebrow in `type.meta`, `color.text.secondary`, one line, `.truncationMode(.middle)`); title in
     `.titleDialog`; body in `.body` with the countdown semibold and `.monospacedDigit()`; a 4 pt capsule meter
     (`DS.Colors.recording` on `DS.Colors.hover`, width × `fraction`); right-aligned "Stop now"
     (`.pill(tint: DS.Colors.recording)`, secondary outlined) then "Keep recording" (`.pill(.primary)`); no
     `keyboardShortcut`, no close box.
   - `SilencePromptPanel: NSPanel` (non-final so tests can record its calls): `[.borderless,
     .nonactivatingPanel]`, `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate =
     false`, clear and non-opaque, `hasShadow = false` (the card draws its own), `isReleasedWhenClosed = false`,
     `canBecomeKey`/`canBecomeMain` false; `static let shadowPadding: CGFloat = 40`; content is an
     `NSHostingView` subclass whose `acceptsFirstMouse(for:)` returns true, padded by `shadowPadding`.
   - `SilencePromptController: SilencePrompting` (`@MainActor`): `init(screen: @escaping @MainActor () ->
     CGRect, announce: @escaping @MainActor (String) -> Void = Self.postAnnouncement, makePanel: @escaping
     @MainActor (SilencePromptModel) -> SilencePromptPanel = SilencePromptPanel.init(model:))`; the panel is
     made lazily on the first `show` and reused (§5.8); it tracks `isShown` itself; `show` on a shown panel only
     updates the model; otherwise it sizes the card (`fittingSize`), sets `frame(size:on: screen())`, calls
     `orderFrontRegardless()` and announces the title (`NSAccessibility.post(… .announcementRequested …)`);
     `hide` orders out. `static func frame(size:on:)` is pure: card centred horizontally, its top at
     `screen.maxY − 0.2 × screen.height`, returned outset by `shadowPadding`.
4. Run the two focused suites — pass. Core suite — green. App suite — green (DSDialog's users unchanged).
   App build — succeeds.

**Definition of done:**
- Both suites pass; `DSDialog` renders as before through `.dialogCard()`.
- Nothing outside `App/Meeting/SilencePrompt/`, `App/Design/DSDialog.swift` and the two test files changes;
  the controller has no caller yet.

**Risks specific to this stage:** a `fittingSize` read before SwiftUI lays the card out can be zero; size the
hosting view once with `layoutSubtreeIfNeeded()` before reading it, and keep the frame math in the pure
`frame(size:on:)` so only the measured size is untested.

### Phase B — Wiring

### Stage 5 — The controller feeds the watch and emits `.silence`
**Goal:** a recording meeting reports its silence prompt as `.silence` events and stops itself on request after expiry, recording the expired prompt's threshold.
**Design references:** §3 R2–R7, R11; §5.1 (`MeetingController` changes); §5.5; §5.6; §5.7; §5.9; §5.11 `MeetingControllerSilenceTests`
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`, `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingEvent.swift` (`case silence(SilencePrompt)`), `App/Meeting/MeetingWindowModel.swift` (`apply`'s `case .silence: break` — the switch is exhaustive, so the app would not compile without it), `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerSilenceTests.swift` (new), `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTests.swift` (hoist `tick(to:)` onto `MeetingHarness`), `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTestCallTests.swift` (drop its private `tick(to:)`)

**Steps (TDD):**
1. Hoist `tick(to:)` from the private `MeetingHarness` extension in `MeetingControllerTestCallTests.swift` into
   `MeetingHarness` (`MeetingControllerTests.swift`) and run `--filter MeetingControllerTestCallTests` — still
   green. Then write `MeetingControllerSilenceTests.swift` (`@MainActor @Suite(.timeLimit(.minutes(1))) struct`,
   `MeetingHarness`, `VirtualClock`). Each test ends the meeting (`stop(summarise: false)` unless it tests a
   stop) and asserts on the events up to `.state(.stopped)`, so a missing event fails an assertion rather than
   hanging:
   - `promptOpensAtThreeMinutesWithoutSpeech` — `.silence(.open(minutes: 1, secondsLeft: 60))` after
     `.elapsed(180)`, none at 179;
   - `emptyPartialsDoNotDelayThePrompt` — `onPartial("")` at 150 → still opens at 180;
   - `aSegmentDelaysThePrompt` — a segment delivered at 170 → no prompt at 180, `.open(1, 60)` at 230;
   - `aFirstConnectedDoesNotRestartTheClock` — an empty partial at 100 on session 1 (its first delivery, so
     `.connection(.connected)`) → still opens at 180;
   - `aNewPartialClosesTheOpenPrompt` — open at 180, `onPartial("we're back")` → `.silence(.closed)`;
   - `pauseClosesAndResumeCountsFromResume` — open at 180, `pause()` → `.closed`; no `.silence` at 200 while
     paused; `resume()` at 210 → opens at 270 with no new grace;
   - `sleepClosesThePrompt` — `audio.sendMeeting(.systemWillSleep)` while open → `.closed`;
   - `reconnectingClosesAndConnectedCountsFromThere` — open at 180, `onEngineError` on session 1 →
     `.connection(.reconnecting(attempt: 1))` and `.silence(.closed)`; past the 1 s backoff
     (`waitUntilSleeping(count: 2)`: the ticker and the reopen timer) session 2 delivers an empty partial at 200
     → `.connected` → opens at 260, not before;
   - `keepRecordingClosesAndCountsFromTheClick` — open at 180, `keepRecording()` at 190 → `.closed`; opens at 250;
   - `stopAfterSilenceBeforeExpiryDoesNothing` — at 200 with the prompt open → state stays `.recording`, no field;
   - `stopAfterSilenceAfterExpiryStopsSummarisesAndRecordsTheThreshold` — with an Anthropic key and one segment
     delivered at 10 (as `stopWithAKeyStoresTheSummaryAndBillsItsTokens` sets up; without them the summary is
     `.none`): `.silence(.expired)` at 240, then `stopAfterSilence()` → `.state(.stopped)`, `.summary(.ready(_))`,
     stored `meeting.silenceStopSeconds == 60`;
   - `theExpiredPromptsThresholdIsRecorded` — open at 180 with 60, `config.update { …SilenceStopSeconds = 300 }`
     at 200: the next tick still sends `.open(minutes: 1, …)`; expiry at 240; stored field 60;
   - `twoMinuteSettingOpensWithItsMinutes` — config 120: `.open(minutes: 2, secondsLeft: 60)` at 180;
   - `aTestCallNeverPrompts` — `controller.start(mode: .remote, title:, engine: nil, test: TestCallTag(…))` (the
     `startTest` helper and its tag are private to `MeetingControllerTestCallTests.swift`), tick to 300 → no `.silence`;
   - `offNeverPrompts` — config 0, tick to 600 → no `.silence`;
   - `offDuringTheCountdownClosesOnTheNextTick` — open at 180, config 0 at 190, tick 191 → `.closed`;
   - `anyStopWhileOpenEmitsClosed` — open at 180, `stop(summarise: false)` → `.silence(.closed)` before
     `.state(.stopped)`, and no field;
   - `logsCarryTimesNotTranscriptText` — under `logging(to:)` (module-internal, in
     `MeetingControllerTestCallTests.swift`): a partial "the merger" at 10, the prompt at 180, then the partial
     "the merger price" → the lines include `silence prompt shown after 170 s` and `silence prompt closed (speech)`,
     and none contains "merger".
   Expected initial failure: compile errors `type 'MeetingEvent' has no member 'silence'` and
   `value of type 'MeetingController' has no member 'keepRecording'` / `'stopAfterSilence'`.
2. Run `swift test --filter MeetingControllerSilenceTests` — confirm the compile errors. Scaffold: add `case
   silence(SilencePrompt)` to `MeetingEvent`, `case .silence: break` to `MeetingWindowModel.apply` (with a
   comment: the prompt lives outside the window), and empty `keepRecording()` / `stopAfterSilence() async`. Re-run
   — confirm assertion failures (`events.contains(.silence(.open(minutes: 1, secondsLeft: 60)))` is false;
   `controller.state` is `.recording` after `stopAfterSilence()`; stored `silenceStopSeconds` is nil).
3. Implement in `MeetingController.swift`:
   - `private var silence: SilenceWatch?`, built in `start` from `config.meetingSilenceStopSeconds`, nil when
     `test != nil`.
   - A private `report(_ change: SilencePrompt?, reason: String)` that emits `.silence(change)` for a non-nil
     change and logs per §5.9, never the text: on the first `.open` after none (a controller-local
     `promptShown` flag, cleared by `.closed` and `.expired`) "silence prompt shown after
     \(Int(meetingTime − silence.lastSpeech)) s"; on `.closed` "silence prompt closed (\(reason))" with reason
     kept / speech / paused / stopped / setting / reconnecting.
   - `handle(_: SupervisorEvent)`: `.partial` → `silence?.partial(text, at: meetingTime)` (speech); `.segment` →
     `silence?.segment(segment.text, at: meetingTime)` (speech); `.connection(.reconnecting)` → `suspend()`
     (reconnecting); `.connection(.connected)` → `restart(at: meetingTime)` only when
     `silence?.isSuspended == true` and `state == .recording`; existing emits unchanged and first.
   - Ticker: after `.cost`, `await checkSilence()` — `guard state == .recording, silence != nil`; `let config =
     await configStore.load()`; re-check `state == .recording` after the await; `setThreshold` (setting), then
     `tick(at: meetingTime)`. Placing it after `.cost` keeps the `.elapsed` → `.cost` adjacency
     `elapsedAndCostTickEverySecond` asserts.
   - `pause(_:)` → `suspend()` (paused) after the state guard; `resume()` → `restart(at: time)` with the time
     `audioPath.resume()` returned; `stop(summarise:)` → `suspend()` (stopped) right after its guard, before
     `setState(.stopping)`.
   - `public func keepRecording()` → `keep(at: meetingTime)` (kept). `public func stopAfterSilence() async`:
     guard `silence?.isExpired == true`, `state == .recording`; set `meeting?.silenceStopSeconds =
     silence.promptMinutes * 60`; log "meeting stopped after silence (\(seconds) s)"; `await stop(summarise: true)`.
4. Run the focused suite — pass. `--filter MWMeetingPipelineTests`, the core suite — green (existing controller
   tests never reach 180 s while recording). App suite — green; app build — succeeds.

**Definition of done:**
- Every bullet of design §5.11 `MeetingControllerSilenceTests` has a passing test, all on `VirtualClock`.
- The app ignores `.silence` (`apply` no-op, the coordinator's `default:`); no app behaviour changes.

**Risks specific to this stage:** the ticker's new `await` lets a partial, pause or stop run between the load and
the tick; the re-check after the await and reading `meetingTime` after it keep the tick on current state.

### Stage 6 — The "Stop after silence" setting
**Goal:** Settings → Meetings → Recording gains "Stop after silence" with Off / 1 min / 2 min / 5 min and a description that follows the value.
**Design references:** §3 R9; §5.3 *Settings row*; §5.4; `DESIGN.md` — Setting row, Segmented pill switch
**Category:** hybrid — TDD for `SettingsModel`; *platform-only remainder*: the `SettingRow` in `MeetingsSection`, verified by the app build and the Stage 8 manual check.
**Touches:** `App/Settings/SettingsModel.swift`, `App/Settings/MeetingsSection.swift`, `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write tests in `SettingsModelTests.swift` (pattern of `keepAudioToggleWritesConfig`):
   - `silenceStopWritesConfig` — `model.config.meetingSilenceStopSeconds == 60` at first; after
     `setMeetingSilenceStop(120)` both the model and `harness.store.load()` read 120; after `0`, 0;
   - `silenceStopDescriptionFollowsTheValue` — 0 → "Off: a meeting records until you stop it."; 60 → "When no one
     has spoken for 1 min, asks whether to keep recording and stops a minute later. Never in a meeting's first 3
     minutes."; 300 → the same with "5 min".
   Expected initial failure: compile error `value of type 'SettingsModel' has no member 'setMeetingSilenceStop'`.
2. Run `-only-testing:AppTests/SettingsModelTests` — confirm the compile error. Scaffold an empty
   `setMeetingSilenceStop(_:) async` and a `silenceStopDescription(_:)` returning `""`; re-run — confirm the
   assertions fail (`120 != 60`; `"" != "Off: …"`).
3. Implement: `func setMeetingSilenceStop(_ seconds: Int) async { await write { $0.meetingSilenceStopSeconds =
   seconds } }`; `static func silenceStopDescription(_ seconds: Int) -> String` per §5.3. In
   `MeetingsSection.recording`, after the Keep meeting audio row: `SettingRow("Stop after silence", description:
   SettingsModel.silenceStopDescription(model.config.meetingSilenceStopSeconds)) { SegmentedPill(selection:
   settingsBinding(model.config.meetingSilenceStopSeconds) { await model.setMeetingSilenceStop($0) }, options:
   [(0, "Off"), (60, "1 min"), (120, "2 min"), (300, "5 min")]) }`.
4. Run the focused suite — pass. Core suite, app suite — green. App build — succeeds.

**Definition of done:** both tests pass; the row sits between Keep meeting audio and System Audio Recording.

**Risks specific to this stage:** None.

### Stage 7 — The Flag chip
**Goal:** a meeting stopped by silence shows "Stopped after N min without speech" as a Flag chip right after the duration chip on its finished page.
**Design references:** §3 R10; §5.3 *Finished page*; §5.4; `DESIGN.md` — Chip (Flag variant), decision 73
**Category:** hybrid — TDD for `MeetingWindowModel.chips`; *platform-only remainder*: `Chip`'s Flag colours and leading symbol, verified by the app build and the Stage 8 manual check (light and dark).
**Touches:** `App/Design/Chip.swift`, `App/Meeting/MeetingWindowModel.swift`, `App/Meeting/FinishedPage.swift`, `AppTests/MeetingWindowModelTests.swift`

**Steps (TDD):**
1. In `MeetingWindowModelTests.swift`, change the three assertions of
   `chipsReadDateRangeDurationModeSpeakersAndCost` to compare `model.chips.map(\.text)`, and add:
   - `silenceStopChipFollowsTheDuration` — stopped, shown with `silenceStopSeconds = 60`:
     `chips[2] == HeaderChip(text: "Stopped after 1 min without speech", kind: .flag, symbol: "pause.circle")`
     and `chips[1].text == "48 min"`; with 300, "Stopped after 5 min without speech";
   - `noSilenceStopChipWithoutTheField` — the five chips of the existing test, every one `.plain` with no symbol.
   Expected initial failure: compile errors `value of type 'String' has no member 'text'` and
   `cannot find 'HeaderChip' in scope` / `type 'Chip.Kind' has no member 'flag'`.
2. Run `-only-testing:AppTests/MeetingWindowModelTests` — confirm the compile errors. Scaffold `case flag` in
   `Chip.Kind` (handled as `.plain` in `dot` and `foreground`), `struct HeaderChip: Equatable { text; kind; symbol }`
   and `chips` mapping the current strings to `.plain` chips; update `FinishedPage.head` to
   `Chip(chip.text, chip.kind, symbol: chip.symbol)` with a `symbol:` parameter that is ignored for now. Re-run —
   confirm the migrated test passes and `silenceStopChipFollowsTheDuration` fails (index 2 is "Remote call").
3. Implement: `chips` inserts the Flag chip after the duration when `meeting?.silenceStopSeconds` is set
   (`"Stopped after \(s / 60) min without speech"`, `.flag`, `"pause.circle"`). `Chip`:
   `init(_ text: String, _ kind: Kind = .plain, symbol: String? = nil, remove: (() -> Void)? = nil)` (the
   trailing-closure call sites such as `Chip(term) { … }` still bind `remove`); `.flag` draws `DS.Colors.text` text, a `DS.Colors.line` border and a `DS.Colors.sidebar` fill;
   a symbol draws first as `Image(systemName:)` in `DS.Colors.textSecondary` at the label font.
4. Run the focused suite — pass. Core suite, app suite — green. App build — succeeds.

**Definition of done:** both new tests and the migrated one pass; every other `Chip(...)` call site compiles unchanged.

**Risks specific to this stage:** None.

### Stage 8 — The coordinator routes `.silence` to the prompt and the stop
**Goal:** the prompt shows, updates and hides with the meeting's `.silence` events; Keep and Stop now act; expiry stops the meeting through the coordinator's own bookkeeping.
**Design references:** §3 R4, R5, R8; §5.3 *Coordinator*; §5.5; §5.6; §5.11 `MeetingCoordinatorTests`, *Stubs*, *Manual acceptance*; §6 (the controller does not stop itself); `DESIGN.md` — for the manual check of the card, meter and chip
**Category:** hybrid — full TDD for `MeetingCoordinator`; *integration-verified remainder*: `AppDelegate` passing the real `SilencePromptController`, checked by the app build and the manual acceptance below.
**Touches:** `App/Meeting/MeetingCoordinator.swift`, `App/AppDelegate.swift`, `AppTests/MeetingCoordinatorTests.swift`, `AppTests/TestCallSessionTests.swift`

**Steps (TDD):**
1. In `MeetingCoordinatorTests.swift`: add a `FakeSilencePrompt: SilencePrompting` that records `show` arguments
   (title, minutes, secondsLeft, the closures) and `hide` calls and yields each call on its own stream (`.silence`
   does not call `deps.changed()`), with a harness `untilPrompt { … }` wait; pass it as `silencePrompt:` in the
   `Dependencies` at line 184. Give `StubController` `keepRecording()` (counts) and `stopAfterSilence()` (counts,
   then behaves as `stop(summarise: true)`, honouring `stopGate` and `summaryOnStop`). Tests:
   - `openShowsThePromptWithTheMeetingTitle` — `send(.silence(.open(minutes: 1, secondsLeft: 60)))` → one show
     with the model's title, 1, 60; a second open (59) → a second show with 59, no hide;
   - `closedHidesThePrompt`;
   - `aNonRecordingStateOfThePromptingSessionHidesIt` — open, then `send(.state(.paused(.user)))` → hide;
   - `anotherSessionsStateLeavesThePrompt` — open on the live meeting, then `harness.open(UUID())` (whose
     controller sends `.state(.stopped)`) → no hide;
   - `expiryHidesAndStopsOnceThroughTheController` — `send(.silence(.expired))` → hide, then exactly one
     `stopAfterSilence`, `stops == []`, the page not presented again;
   - `expiryOnATestCallStopsNothing` — a test call's controller sends `.expired` → `stopAfterSilences == 0`;
   - `thePromptsStopIsTheManualStop` — invoking the shown `stop` closure → `stops == [true]`, no `stopAfterSilence`;
   - `thePromptsKeepKeepsRecording` — the shown `keep` closure → `keepRecordings == 1`;
   - `aSilenceStopOffThePageKeepsItsSummary` — as `stopWhileNotShownMovesTheSessionToFinishingThenDropsItOnTheSummary`,
     but triggered by `.expired`: with `stopGate` and `summaryOnStop = .writing`, the session stays open until
     `.summary(.ready)` arrives, then is dropped.
   In `TestCallSessionTests.swift`, give its `StubController` the two methods (no-ops).
   Expected initial failure: compile error `extra argument 'silencePrompt' in call` (`Dependencies` has no such
   member yet; the stubs' new methods compile as plain members until the protocol requires them).
2. Run `-only-testing:AppTests/MeetingCoordinatorTests` — confirm the compile error. Scaffold: add
   `keepRecording()` and `stopAfterSilence() async` to `MeetingControlling` (`MeetingController` already
   conforms), `var silencePrompt: any SilencePrompting` to `Dependencies`, and an empty `stopAfterSilence()` on
   the coordinator; in `AppDelegate.makeMeetings` pass `silencePrompt: SilencePromptController(screen: {
   placement.screenFrame(forPID: NSWorkspaceFrontmostApp().frontmost()?.pid) })` with a
   `DisplayPlacement(focused: AXFocusedWindow(), pointer: NSEventPointer(), screens: NSScreenList())`, as
   `UIEventRouter` builds one, so the app builds. Re-run — confirm assertion failures (no show recorded;
   `stopAfterSilences == 0`).
3. Implement in `MeetingCoordinator.swift`:
   - `forwardEvents`: `.silence(.open(m, s))` → `deps.silencePrompt.show(meetingTitle: session.model.title,
     minutes: m, secondsLeft: s, keep: { [weak session] in session?.controller.keepRecording() }, stop: { [weak
     self] in Task { await self?.stop() } })` and remember the session as the prompt's owner;
     `.silence(.closed)` → `hide()`; `.silence(.expired)` → `hide()`, then `Task { await self?.stopAfterSilence() }`;
     `.state` other than `.recording` from the owner → `hide()` (design §5.3 as corrected). No `deps.changed()` for `.silence`.
   - `stopAfterSilence()` and `stop(summarise:)` share a private `stop(_ session:, using: (Session) async -> Void)`
     holding the guard (`current`, `isStoppable`), `isStopping`, the await, and the finishing-drop; the silence
     entry point also guards `session.test == nil` and calls `controller.stopAfterSilence()`. Neither presents.
4. Run the focused suite — pass; `-only-testing:AppTests/TestCallSessionTests` — pass. Core suite, app suite —
   green. App build — succeeds.
5. Integration-verified remainder (manual, design §5.11): run the built app; Settings → Meetings → Stop after
   silence → 1 min; start an in-room meeting and stay silent. At 3:00 the prompt shows on the front app's display
   over a full-screen app, typing in that app continues, and one click on Keep recording closes it. Stay silent:
   one minute after the next prompt the meeting stops, the summary is written, and the finished page shows the
   Flag chip after the duration. Repeat in the dark theme; check the card, the meter and the chip against
   `DESIGN.md` and the accepted mockup.

**Definition of done:** every bullet of design §5.11 `MeetingCoordinatorTests` passes; the manual acceptance passes in light and dark.

**Risks specific to this stage:** a stop that bypassed `stop`'s bookkeeping would drop a session off the page
before `.summary(.writing)` (design §6); `aSilenceStopOffThePageKeepsItsSummary` guards it.

### Phase C — Documentation

### Stage 9 — Documentation
**Goal:** the repository's documents describe v7.
**Design references:** §5.10, §9
**Category:** non-TDD (config-only) — documentation only; nothing executable changes.
**Touches:** `CHANGELOG.md` (`[Unreleased]` → `### Added`: the design §9 entry, plus that it is on by default and Off restores today's behaviour), `README.md` (`## Meetings`: a paragraph on the prompt, Keep recording / Stop now, the setting and the Flag chip), `CLAUDE.md` (module map: `MWMeetingPipeline` gains `SilenceWatch`)

**Steps (non-TDD):**
1. Edit the three files.
2. Check: `grep -n "meeting_silence_stop_seconds\|Stop after silence" README.md CHANGELOG.md` finds the new text;
   `git diff --stat -- Packages/MiniWhisperCore/Package.swift project.yml` is empty; `project.yml`
   `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` unchanged (no release in this plan).
3. Run both suites and the app build one last time — green.

**Definition of done:** the three documents match the shipped behaviour; no version bump.

**Risks specific to this stage:** None.

## Cross-cutting concerns

- **Security** — No new input surface beyond `config.json`'s value, validated against the four choices in
  Stage 1 (wrong types included). Logs carry times, thresholds and close reasons only, never transcript text
  (Stage 5's `logsCarryTimesNotTranscriptText`). No secret, key or trust boundary is touched. The panel never
  becomes key, so it cannot take keystrokes meant for the call (Stage 4's attribute test).
- **Performance** — One `ConfigStore.load()` per second while recording, an actor hop returning the cached value;
  `SilenceWatch` is O(1) per call with one string compare per partial (Stages 3, 5). The panel and its hosting
  view are made once, on the first prompt, and reused; a repeated `show` only sets three model properties (Stage 4).
- **Observability** — `Log.meeting.info` "silence prompt shown after N s", "silence prompt closed (reason)",
  "meeting stopped after silence (N s)" (Stage 5). The VoiceOver announcement on open (Stage 4).
- **Compatibility / migration** — `meeting.json` gains an optional key that older builds ignore; schema stays 1
  (Stage 2). `config.json` always gains `meeting_silence_stop_seconds`; older Swift builds keep it in `extra`
  (Stage 1). Between stages the app behaves as today (see the coverage map); the default-on change is named in
  the CHANGELOG (Stage 9).

## Verification

Once Stage 9 has landed:

1. `cd Packages/MiniWhisperCore && swift test` — 17 runs, all `✔ … passed`, 1006 + the new tests.
2. The app test command — `✔ Test run with … passed`, `** TEST SUCCEEDED **`, 438 + the new tests.
3. The manual acceptance of Stage 8, step 5 (R4, R5, R8, R9, R10), in light and dark.
4. Spot checks: Settings → Off, a silent meeting runs past 5 min with no prompt (R1, R7); a test call runs
   silent with no prompt (R3); Pause during a countdown closes the prompt and Resume gives a prompt one minute
   later (R5, R6); the `meeting.json` of the auto-stopped meeting has `"silenceStopSeconds":60` and its
   `index.json` entry and Markdown export show nothing new (R10).
5. Follow-up outside the plan: `/design-language-update` (record mode) turns decisions 72 and 73 from
   `pending v7` to active in `DESIGN.md` and the specimen (design §9).

## Risks and open issues

1. **Tests waiting for an event that never comes hang.** Mitigation: the controller tests assert on bounded event
   lists ending at `.state(.stopped)`; the new suites carry `.timeLimit(.minutes(1))`; the coordinator fake
   publishes its own stream.
2. **First click on the non-activating panel swallowed.** Mitigation: `acceptsFirstMouse` on the hosting view is
   host-tested (Stage 4) and clicked for real in the Stage 8 acceptance over a full-screen app.
3. **A release cut between Stage 6 and Stage 8** would ship a setting that does nothing. Mitigation: no tag until
   Stage 9 has landed; Stage 9 checks the version is untouched.
4. **Pause in the same second as expiry** leaves the watch expired (final, per design §5.1) and the meeting
   paused; `stopAfterSilence` then returns at its `.recording` guard and that meeting gets no further prompt.
   Mitigation: none needed beyond the design's rule — the user is at the Mac, having just paused; noted so a
   reviewer does not read it as a bug.
5. **Two app test hosts at once on one Mac** are unproven. Mitigation: at most one stage per batch runs the app
   suite; the core stages of batch 1 run only the core suite and the app build.
6. **`fittingSize` of an unlaid-out hosting view** can be zero. Mitigation: lay out once before measuring (Stage 4);
   the placement math stays pure and tested.

## Planning decisions taken

1. Stage order: the three core types and the self-contained prompt surface first (Stages 1–4, one parallel
   batch), the controller next (5), the setting and the chip (6, 7), the coordinator last (8) so the feature turns
   on in one stage, documentation at the end (9).
2. **Design §5.2 vs R1 (internal contradiction, §5.2 corrected in place):** §5.2 decoded the key "like
   `meeting_keep_audio`" (a throwing decode, so a wrong-typed value would make `ConfigStore` back up and reset the
   whole file), while R1 says any other value reads as 60. R1 wins: decode with `try?` as `main_window_frame` does.
3. **Design §5.1, two readings of the recorded threshold (internal contradiction, §5.1 corrected in place):** a
   controller `silenceSeconds` "the threshold of the expired prompt" against `stopAfterSilence` writing the
   current `silence.threshold`. R4 with R7 (an open prompt keeps its countdown and title) wins: record
   `promptMinutes * 60`; the unused `silenceSeconds` is dropped.
4. **Design §5.3 backstop vs R5 (internal contradiction, §5.3 corrected in place):** "`.state` other than
   `.recording` → hide" would hide a live countdown when a stored meeting is opened (its controller emits
   `.state(.stopped)`), a close R5 does not list. The backstop applies only to the session that opened the prompt.
5. `SilenceWatch` exposes read-only `isSuspended`, `promptMinutes` and `lastSpeech`: §5.1's "`.connected` while
   suspended", the recorded threshold and the "shown after N s" log each read one, and the sketch had no reader
   (design sketch updated).
6. The close reason for the log comes from the controller's call site; `SilencePrompt.closed` carries none, so the
   public event shape stays as designed.
7. `MeetingEvent.silence` lands in Stage 5 with `MeetingWindowModel.apply`'s no-op case, since that switch is
   exhaustive; `SilencePrompt` itself lands in Stage 3 so the watch has no dependency on the event.
8. The Dialog card chrome moves from `DSDialog` into a shared `.dialogCard()` modifier used by `DSDialog` and
   `SilencePromptView`, rather than copying padding, width, fill, border and shadow.
9. `SilencePromptController` takes `screen` and `announce` closures and a panel factory; it tracks `isShown`
   itself; `SilencePromptPanel` is non-final so a test subclass records `setFrame` / `orderFrontRegardless` /
   `orderOut` without drawing.
10. `SilencePromptController.frame(size:on:)` takes the card size and returns the panel frame, outset by
    `SilencePromptPanel.shadowPadding` (40 pt, enough for `shadow.dialog`'s 18 pt blur at 14 pt offset).
11. The placement and show/hide tests live in `AppTests/SilencePromptControllerTests.swift`, named for the type
    as CLAUDE.md requires, in place of the design's `SilencePromptPlacementTests`.
12. `SilencePromptModel` gains a derived `eyebrow`, so §5.6's empty-title case is host-tested.
13. `tick(to:)` moves from the private extension in `MeetingControllerTestCallTests.swift` onto the shared
    `MeetingHarness`, instead of a second private copy.
14. The silence check runs after `.cost` in the ticker, keeping the `.elapsed` → `.cost` order existing tests assert.
15. `FakeSilencePrompt` publishes its calls on its own stream, since `.silence` does not call `deps.changed()`,
    which the coordinator harness's `until` relies on.
16. R10's "unchanged" outputs get one guard test (Markdown goldens with the field set); `IndexEntry`, CLI list and
    MCP list/search encode types without the field, so they need no code and no test.
17. The documentation stage also updates `README.md`'s Meetings section and `CLAUDE.md`'s module map, as v6's
    Stage 17 did, beyond the CHANGELOG line §9 names.
18. Decisions 72 and 73 are flipped by `/design-language-update` after the plan (*Verification* 5), not inside a
    stage: that skill is the only writer of `DESIGN.md`.
19. Batch 1's core stages run the core suite and the app build only, never the app test host, so the one
    app-test stage of the batch has the Mac to itself.

## Deviations from the design

None — plan matches design v7 exactly.

## Deviations from plan

Recorded during implementation.

1. **Stage 4, panel sizing.** `SilencePromptPanel` is built at its hosting view's `fittingSize`, as
   `OverlayPanel` is built at its size. Built at `.zero`, the hosting view resized the window lazily on first
   measurement, an extra `setFrame` before the controller's own. `cardSize` still lays out before measuring.
2. **Stage 4, `hide()`** calls `panel?.orderOut(nil)` with no `isShown` guard; harmless when hidden or not yet made.
3. **Stage 4, countdown colour.** The countdown is `DS.Colors.text` inside the `color.text.secondary` body, as the
   accepted mockup draws it (`.count { color: var(--ink) }`).
4. **Stage 4, card spacing** follows the mockup: `DS.Space.s5` between rows, `s3` above the buttons, `s4` in the
   eyebrow; the meter is `s2` (4 pt) high. Padding comes from `.dialogCard()` (22 + hairline), not the mockup's
   20/22/18.

## Execution schedule

Batches run in order; a batch starts only when the previous one has fully landed. Stages inside a *parallel* batch are independent and may be built concurrently; a *serial* batch holds one stage. `/feature-implement` follows this table and demotes any batch it cannot verify to serial.

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1, Stage 2, Stage 3, Stage 4 | parallel | Disjoint files: `MWConfig/Config.swift` + two `MWConfigTests` files; `MWMeetings/MeetingModel.swift` + two `MWMeetingsTests` files; new `SilenceWatch.swift`, `MeetingEvent.swift` (the `SilencePrompt` enum) and new `SilenceWatchTests.swift`; new `App/Meeting/SilencePrompt/*`, `App/Design/DSDialog.swift` and two new `AppTests` files. No symbol or string-keyed dependency: `meetingSilenceStopSeconds` / `meeting_silence_stop_seconds`, `Meeting.silenceStopSeconds`, `SilenceWatch` / `SilencePrompt` and `SilencePrompting` are each introduced by one stage and read by none of the others. No shared registration point: all add files to existing SwiftPM targets or xcodegen folders; `Package.swift` and `project.yml` untouched; no exhaustive switch or enumerated registry edited. Same base: each is green against `51bcb14` alone. Category: all four are feature stages — none is scaffolding, a migration, a gated prerequisite or a dependency change; `Meeting.init` gains only a defaulted trailing parameter, so no call site changes; Stage 4's `.dialogCard()` extraction edits only `DSDialog.swift`, which Stages 1–3 cannot reach (the core package does not see app code). No security ordering. No shared test resource: each runs in its own worktree's `.build` / `.dd` with `TempDirectory`s; only Stage 4 launches the app test host |
| 2 | Stage 5 | serial | Adds a variant to the shared `MeetingEvent` enum, with its exhaustive switch in `MeetingWindowModel` (category exclusion); consumes Stages 1–3 |
| 3 | Stage 6 | serial | App-hosted tests; two concurrent test hosts on one Mac are unproven, and Stage 7 also runs them |
| 4 | Stage 7 | serial | App-hosted tests; edits `MeetingWindowModel.swift`, which Stage 5 also edits |
| 5 | Stage 8 | serial | Consumes `SilencePrompting` (Stage 4) and `keepRecording` / `stopAfterSilence` / `.silence` (Stage 5); changes the shared `MeetingControlling` protocol and `MeetingCoordinator.Dependencies` (category exclusion) |
| 6 | Stage 9 | serial | Documents the behaviour and names every earlier stage introduces |

**Critical path:** Stage 3 → Stage 5 → Stage 8 → Stage 9 by dependency (4 of 9 stages); by schedule 6 batches, since Stages 6 and 7 are serialised by the shared Mac test destination, not by dependency.

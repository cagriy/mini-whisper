# Persistent Speaker Recognition — Implementation Plan v8

**Status:** Draft
**Date:** 2026-11-20
**Design:** [feature-design-v8-Persistent-Speaker-Recognition.md](./feature-design-v8-Persistent-Speaker-Recognition.md)

## Overview

v8 remembers the people the user names in meetings and names them, or offers their name, in later meetings: a
bundled WeSpeaker Core ML model under the two AssemblyAI engines, Speechmatics voice identifiers under the two
Speechmatics engines, both behind switches that ship off. The plan has 21 stages in six phases. **Foundations
(1–4)** add the eight `config.json` keys, the rolling audio buffers on the capture tick, the Credits window and the
stored shapes (`VoiceVector`, `NameMatch`, the `SpeakerLabel` fields, the meeting sidecar). **The `MWVoices`
module (5–10)** registers the new core module and fills it with pure, separately tested parts: people and
samples, the matcher, windows, the Speechmatics enrolment, the people store, the match log and the scrubber, plus
the registry's suggest/apply/accept/dismiss/detach/link and the bundled model with its embedder. **Streaming, the
recogniser and Settings (11–14)** add the Speechmatics identification wire, the per-session enrolment and
`GetSpeakers`, the recogniser actor, and the switches and tuning. **The controller (15–17)** wires the local route,
then confirmation and learning, then the Speechmatics route. **Surfaces (18–21)** add the transcript's provisional
names, the People section, then Forget together with the app wiring that turns the feature on, and the
documentation. The plan maps 1:1 to design §3's 29 requirements and every §5 component; no meeting recognises or
learns anything before Stage 20, by which point Forget exists, and no release is cut before Stage 21.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only | integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests, platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a one-line justification.

In Swift a test naming a type or member that does not exist yet fails to **compile**; that is the first red. The
step then adds the minimal empty API (members returning nil, zero, `self`, empty collections or no-ops) and re-runs
to see **assertion** failures before implementing. Every "confirm fail" step below names both. A stage whose
symbols all exist already (Stage 17) goes straight to assertion failures.

**Runners and checks** (each run once on 2026-11-20 at `6c2e390`, before drafting; the working tree's uncommitted
`DESIGN.md` / `design/specimen.html` changes touch no source):

| Check | Command | Observed baseline |
|---|---|---|
| Core tests | `cd Packages/MiniWhisperCore && swift test` | 17 Swift Testing runs (one per test target), 1067 tests in 102 suites, every run `✔ … passed`, exit 0; each run is preceded by an empty XCTest `Executed 0 tests` line |
| One core suite | `cd Packages/MiniWhisperCore && swift test --filter <Suite>` | `--filter SpeakerRegistryTests` → `✔ Test run with 8 tests in 1 suite passed` |
| Core build | `cd Packages/MiniWhisperCore && swift build` | `Build complete!`, exit 0 |
| App tests | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` | `✔ Test run with 467 tests in 47 suites passed` and `** TEST SUCCEEDED **` (the `com.apple.linkd.autoShortcut` lines are host noise) |
| One app suite | the app-test command plus `-only-testing:AppTests/<Suite>` | `-only-testing:AppTests/SmallWindowsTests` → `✔ Test run with 3 tests in 1 suite passed`, `** TEST SUCCEEDED **` |
| App build only | the app-test command with `build` in place of `test` | `** BUILD SUCCEEDED **`, exit 0 |

Read the `✔/✘ Test run with …` line, not the XCTest line. From Stage 5 on, `swift test` reports **18** runs (the
new `MWVoicesTests` target).

Two further facts were proven by execution in the scratchpad before drafting, so Stage 10 transcribes them rather
than predicting them:

- **The model in the bundle.** A throwaway xcodegen project with `App/Resources/wespeaker_v2.mlmodelc` excluded from
  the `App` source path and re-added as `- path: App/Resources/wespeaker_v2.mlmodelc / type: folder / buildPhase:
  resources` generated one `lastKnownFileType = folder` reference and built an `.app` whose
  `Contents/Resources/wespeaker_v2.mlmodelc/` held `analytics/ coremldata.bin metadata.json model.mil weights/`
  intact; a `.wav` under the test target's `Fixtures/` folder landed in the **test bundle's** `Resources/`, not in
  `Bundle.main`.
- **The fixture clips.** `say -v Daniel|Karen --file-format=WAVE --data-format=LEI16@16000` with the two sentences
  Stage 10 lists gave 16 kHz mono clips of about 5.6 s; the design's probe (`probe.swift`, recompiled) scored them,
  whole clips looped to 10 s: Daniel 1·2 **0.934**, Karen 1·2 **0.866**, every cross-voice pair **≤ 0.248**.

**Which checks a stage runs.**

- **Core-only stages** run the focused suite, the core suite, then the app **build** — never the app test host, so
  they can share a batch with one app-test stage (see *Execution schedule*).
- **Stages that touch `App/` or `AppTests/`** run the focused suite(s), the core suite, the app suite, then the app
  build.

**Registration.** SwiftPM registration is explicit (CLAUDE.md): the one `Package.swift` edit is in **Stage 5**,
which adds the `MWVoices` product and target, the `MWVoicesTests` test target, and `MWVoices` to the dependencies
of `MWMeetingPipeline` and `MWTestSupport`, so no later stage touches `Package.swift`. Every other new core file
lands in an existing target folder, compiled automatically. New `App/` and `AppTests/` files are picked up by
xcodegen's folder sources at the next `xcodegen generate`; the one `project.yml` edit is in **Stage 10** (the model
as a folder resource and the `MWVoices` product for the app target). The generated `Mini Whisper.xcodeproj` is
git-ignored and never staged. New Speechmatics fixtures go under the already-registered
`Tests/MWStreamingTests/Fixtures/streaming/`.

**Test locations.** Core suites follow `Packages/MiniWhisperCore/Tests/<Module>Tests/<Type>Tests.swift` with
`import Testing`, `@Suite struct`, `#expect`/`#require`:

- `MWConfigTests/VoiceSettingsTests.swift` beside `MWConfigTests/MeetingEngineTests.swift`;
- `MWMeetingsTests/VoiceVectorTests.swift` beside `MWMeetingsTests/MeetingModelTests.swift`;
- `MWVoicesTests/<Type>Tests.swift` (new target) following `MWUsageTests/PricingTests.swift`'s shape; fixture meetings
  for the scrubber are written through `MeetingStore` into a `TempDirectory`, as `MeetingStoreTests.swift` does, so
  the new target needs no `Fixtures` resource;
- `MWStreamingTests/SpeechmaticsVoiceTests.swift` beside `CloudAdapterTests.swift` (fixtures read with
  `Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures/streaming")` as it does);
  `MWStreamingTests/SpeechmaticsVoiceLiveTests.swift` beside `MeetingEngineLiveTests.swift`;
- `MWMeetingPipelineTests/VoiceAudioBufferTests.swift` beside `SystemAudioRingTests.swift`,
  `VoiceRecogniserTests.swift` and `MeetingAudioPathVoiceTests.swift` with `@testable import MWMeetingPipeline` as
  `MeetingControllerEditingTests.swift` does (the buffer, audio path and recogniser are internal);
  `MeetingControllerVoiceTests.swift`, `MeetingControllerVoiceLearningTests.swift`,
  `MeetingControllerSpeechmaticsVoiceTests.swift` and `MeetingControllerVoiceScrubTests.swift` beside
  `MeetingControllerSilenceTests.swift`, on the shared `MeetingHarness` in `MeetingControllerTests.swift`.

App suites follow `AppTests/<Type>Tests.swift` with `@testable import MiniWhisper`, as `AppTests/SettingsModelTests.swift`
does; `AppTests/CreditsTests.swift` and `AppTests/VoiceModelTests.swift` read bundle resources as
`AppTests/BundledResourcesTests.swift` does. App suites cannot import `MWTestSupport`, so their fakes are local
closures. No voice behaviour involves wall-clock time (thresholds, speech seconds and buffer length are audio
measures); the controller suites keep `MeetingHarness`'s `VirtualClock`, and no test sleeps.

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: `voice_local_enabled` / `voice_speechmatics_enabled`, default false; local route serves the AssemblyAI tiers, Speechmatics the Speechmatics tiers | Stage 1, Stage 14 |
| R2: route active only with its switch on at Start, not a test call, model loaded; inactive = no buffer, no `StartRecognition` field, no sidecar, no `meeting.json` key | Stage 4, Stage 12, Stage 15, Stage 17, Stage 20 |
| R3: switch off acts at once (no match, learning, log or sidecar); on applies from the next meeting; thresholds read per evaluation, sensitivity per session open | Stage 13, Stage 15, Stage 17 |
| R4: switch disabled with the key hint without its key; local switch disabled when the model fails to load | Stage 14 |
| R5: rolling buffers of `voice_buffer_seconds`: system + microphone remote, microphone in the room | Stage 2, Stage 15 |
| R6: labelled final segment with ≥ 1.5 s of word audio → turn vectors (merge ≤ 0.3 s, pad 0.05 s, ≤ 10 s windows, loop to 160,000, all-ones mask, row 0, L2-normalised, 256 floats) | Stage 6, Stage 10, Stage 13 |
| R7: a key's voice is the normalised seconds-weighted sum; a revision moves vectors, nothing re-embedded | Stage 4, Stage 13, Stage 15 |
| R8: evaluation after each vector once ≥ minimum speech, while default-named, unlinked, not the user; sure / suggestion tiers with margin; rejected excluded; the user a candidate only in the room | Stage 5, Stage 13, Stage 15 |
| R9: a suggestion may be replaced by a later decision; "nothing" leaves it; an applied name is never withdrawn by the app | Stage 9, Stage 15 |
| R10: `get_speakers`, `speaker_sensitivity`, `speakers` (`mw:<uuid>`, newest identifier per tier, most recently heard first, ≤ 50), rebuilt at every session open | Stage 6, Stage 11, Stage 12, Stage 17 |
| R11: an `mw:<id>` label of a known person matches on first sight: suggestion until confirmed under Speechmatics, applied after | Stage 6, Stage 17 |
| R12: every `SpeakersResult` updates identifiers per key; `GetSpeakers final:false` on a live link | Stage 11, Stage 12, Stage 17 |
| R13: a `speaker_id` warning drops the identifier it names; the first one shows the notice once | Stage 7, Stage 11, Stage 17, Stage 18 |
| R14: a suggestion never changes `name`; applying, accepting or renaming does | Stage 9, Stage 15, Stage 18 |
| R15: Accept / Edit / click / Dismiss / "Not <name>" semantics; that person not offered again after Dismiss, Not or a rename away; Accept asks no merge confirmation | Stage 9, Stage 16, Stage 18 |
| R16: recognition never changes a user-named speaker, a linked speaker or the user | Stage 9, Stage 15 |
| R17: learning only on a confirmed link while the switch is on; an applied name teaches nothing; `^Speaker \d+$` never creates a person | Stage 7, Stage 16 |
| R18: a rename onto a name the People list holds is that person; a new name creates one | Stage 7, Stage 16 |
| R19: the user's own voice learned without a click (local remote microphone, Speechmatics gate-bound label, in-room rename) | Stage 16, Stage 17 |
| R20: ≤ 8 local samples per person, one per meeting, 0.85 replace rule, oldest dropped; one Speechmatics identifier per tier | Stage 5, Stage 7 |
| R21: per-meeting `voices.json` (vectors or identifiers, never audio), written at Stop, deleted with the meeting or by Forget | Stage 4, Stage 8, Stage 15, Stage 17, Stage 20 |
| R22: after Stop, Accept / Edit / Dismiss / Not work on a stored meeting; learning there uses its sidecar | Stage 16, Stage 18 |
| R23: `voices.json` 0600, atomic; every match and user action appends to `voice-matches.jsonl` | Stage 7, Stage 8, Stage 15, Stage 16 |
| R24: Settings › People: list, Rename (refused when taken), Merge into…, Forget, Forget everyone; all off while recording; the user's entry has no Rename and is never merged into another | Stage 7, Stage 8, Stage 19, Stage 20 |
| R25: a test call neither recognises nor learns, and shows no recognition control | Stage 15, Stage 18 |
| R26: `wespeaker_v2.mlmodelc` committed under `App/Resources/` and bundled; Credits, opened from About, credits it (CC BY 4.0) and Sparkle | Stage 3, Stage 10 |
| R27: no log line carries a name, vector, identifier or transcript text; Speechmatics receives only opaque `mw:` labels | Stage 6, Stage 11, Stage 15, Stage 17 |
| R28: embedding off the capture thread and the main actor; the capture tick only appends under a lock | Stage 2, Stage 13 |
| R29: Swift 6 strict concurrency, macOS 14 target, no new third-party dependency; `MiniWhisperCore` imports only system frameworks | Stage 5, Stage 10 (and every stage's build) |

**User-visible behaviour after each contributing stage.** Stages 1–2 and 4–13 change nothing a user sees: the keys
are read by nothing, the buffers and recogniser have no caller, the wire carries no voices because nothing passes
any. Stage 3 adds the Credits window (visible, self-contained). Stage 14 shows the switches and tuning; turning them
on has no effect yet because the app passes no `VoiceDependencies`. Stages 15–17 make the controller recognise and
learn, still dormant in the app for the same reason. Stage 18 draws provisional names, the action pills and the
notice for whatever `matches` a meeting holds — none in practice, since nothing produces them in the app yet (a
hand-seeded stored meeting shows them). Stage 19 adds the People list (empty until something is learned). **Stage 20
adds Forget and then turns the feature on** by passing `VoiceDependencies` and the route closure to every meeting:
from there a meeting with a switch on recognises, suggests and learns, and every learned voice can be forgotten. R14,
R15, R22 and R24 are therefore delivered in steps whose intermediate states are either dormant or a strict subset of
the final behaviour; they stay separate stages for review size. The one rule is that **no release is cut before
Stage 21** (*Risks* 3), since builds from Stages 14–19 show switches that do nothing.

## Stages

### Phase A — Foundations

### Stage 1 — Voice settings in `config.json`
**Goal:** `Config.voice` carries the two route switches and six tuning values with their clamps, the Cautious–Eager step mapping, and each engine's route.
**Design references:** §3 R1, R3; §5 Data model (Config, slider mapping); §5 Testing (`VoiceSettings`, `Config`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWConfig/VoiceSettings.swift`, `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`, new `Packages/MiniWhisperCore/Tests/MWConfigTests/VoiceSettingsTests.swift`, `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`

**Steps (TDD):**
1. Write tests in `VoiceSettingsTests.swift`:
   - `defaultsMatchTheDesign` — `VoiceSettings()` has both switches false, sure 0.70, suggestion 0.50, margin 0.10,
     minimum speech 15 s, buffer 120 s, sensitivity 0.80, and `step == 5`;
   - `eachStepSetsItsFiveValues` (`@Test(arguments: 0...10)`) — `VoiceSettings().tuned(toStep: s)` gives sure
     `0.80 − 0.02s`, suggestion `0.60 − 0.02s`, margin `0.15 − 0.01s`, minimum speech `25 − 2s`, sensitivity
     `0.95 − 0.03s` (±1e-9), leaves the switches and the buffer alone, and reads back `step == s`;
   - `stepIsNilOffTheGrid` — sure 0.704 still reads step 5, 0.706 reads nil; minimum speech 15.4 reads 5, 15.6 nil;
   - `validatedClampsEachField` — every field outside its §5 range (sure 0.50–0.95, suggestion 0.30–0.90,
     margin 0–0.30, minimum 5–60, buffer 60–300, sensitivity 0–1) comes back at the bound; suggestion 0.85 with sure
     0.70 comes back 0.70;
   - `eachEngineHasItsRoute` — both Speechmatics tiers → `.speechmatics`, both AssemblyAI tiers → `.local`;
     `isEnabled(_:)` reads the matching switch;
   - `fieldRangesAndValues` — `VoiceSettings.range(of:)` and `value(of:)` / `setting(_:to:)` for each `Field`
     (`.sure, .suggestion, .margin, .minimumSpeech, .buffer, .sensitivity`), `setting` clamping.
   In `ConfigCodingTests.swift`:
   - `voiceKeysAbsentTakeTheDefaults` — `decode("{}").voice == VoiceSettings()`;
   - `voiceKeysRoundTrip` — the eight keys (`voice_local_enabled`, `voice_speechmatics_enabled`,
     `voice_sure_threshold`, `voice_suggest_threshold`, `voice_margin`, `voice_min_speech_seconds`,
     `voice_buffer_seconds`, `voice_speechmatics_sensitivity`) with non-default values decode, and `saved(config)`
     holds each under its snake_case name;
   - `aWrongTypedVoiceKeyReadsAsItsDefault` — `{"voice_sure_threshold": "high", "voice_local_enabled": 1}` decodes
     without throwing and reads the defaults (R3's file must never be backed up as corrupt over a tuning value);
   - `voiceKeysAreWrittenForANewConfig` and `voiceKeysNeverLandInExtra`;
   - `validatedClampsTheVoiceValues` — `Config` with `voice.sureThreshold = 2` → `validated().voice.sureThreshold == 0.95`.
   Expected initial failure: compile errors `cannot find 'VoiceSettings' in scope` and `value of type 'Config' has
   no member 'voice'`.
2. Run `swift test --filter MWConfigTests` — confirm the compile errors. Add the empty API (`VoiceSettings` with
   every value 0 / false, `step` nil, `tuned` / `validated` / `setting` returning `self`, `voiceRoute` always
   `.local`; `Config.voice` stored but neither decoded nor encoded). Re-run and confirm assertion failures: wrong
   defaults and step values, the keys absent from the saved object and present in `extra`, Speechmatics tiers
   reading `.local`.
3. Implement `VoiceSettings.swift` (`VoiceRoute`, `MeetingEngine.voiceRoute`, `VoiceSettings` with `Field`,
   `range(of:)`, `tuned(toStep:)`, `step` within ±0.005 / ±0.5 s, `validated()`) and in `Config.swift` the eight
   `Key` constants, `Key.all`, `try?` decodes (the `main_window_frame` precedent), unconditional encodes and
   `validated()` calling `voice.validated()`.
4. Focused suite — pass. Core suite — 17 runs green. App build — `** BUILD SUCCEEDED **`.

**Definition of done:**
- Both suites pass; a new `config.json` contains the eight keys with the design defaults; out-of-range values clamp; a wrong-typed value reads as its default.
- `MeetingEngine.voiceRoute` maps the four tiers as R1 says.

**Risks specific to this stage:** None.

### Stage 2 — Rolling voice audio buffers
**Goal:** a lock-guarded rolling buffer of 16 kHz samples by meeting time, and the audio tick appending the microphone (and, remote, the system audio) to it when buffers are handed in — and nothing else.
**Design references:** §3 R5, R28; §5 Control flow (Audio tick); §5 Performance; §5 Testing (`VoiceAudioBuffer`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/VoiceAudioBuffer.swift`, `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingAudioPath.swift`, new `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/VoiceAudioBufferTests.swift`, new `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingAudioPathVoiceTests.swift`

**Steps (TDD):**
1. Write tests (`@testable import MWMeetingPipeline`):
   - `VoiceAudioBufferTests`: `returnsTheSamplesBetweenTwoTimes` (1 s ramp appended at 10.0 → `samples(from: 10.25,
     to: 10.5)` has 4,000 samples starting at ramp index 4,000); `aGapYieldsOnlyTheAudioAroundIt` (1 s at 0 and 1 s at
     5 → `samples(from: 0.5, to: 5.5)` has 16,000); `evictsAudioOlderThanItsLength` (`seconds: 2`, 3 s appended →
     `samples(from: 0, to: 1)` empty, `samples(from: 1, to: 3)` 32,000); `aRangeOutsideTheBufferIsEmpty`;
     `concurrentAppendAndReadNeverTear` (a task group appends 200 chunks of 1,600 while another reads; every read's
     count is a multiple of 1,600 and the final span is the last `seconds`).
   - `MeetingAudioPathVoiceTests` (a `SessionSupervisor` over `FakeMeetingEngineProvider`, opened at 0):
     `remoteAppendsMicrophoneAndSystemAtTheTickTime` (0.5 s of 0.2 pushed as system audio, 0.5 s of 0.1 fed in
     0.1 s buffers → microphone buffer `samples(0, 0.5)` all 0.1, system buffer all 0.2);
     `inRoomAppendsTheMicrophoneOnly`; `pausedAppendsNothing`; `withoutBuffersTheTickIsUnchanged` (`voices: nil` →
     the engine's `fedBuffers` and the billed seconds equal a run built without the parameter).
   Expected initial failure: compile errors `cannot find 'VoiceAudioBuffer' in scope` and `extra argument 'voices'
   in call`.
2. Run `swift test --filter "VoiceAudioBufferTests|MeetingAudioPathVoiceTests"` — confirm; add the empty API
   (`append` a no-op, `samples` returning `[]`, `VoiceBuffers { microphone, system }`, the defaulted init
   parameter ignored); re-run — assertion failures: empty reads everywhere.
3. Implement `VoiceAudioBuffer` (`final class`, `Sendable`, `OSAllocatedUnfairLock` over time-stamped chunks,
   eviction by `seconds`, `samples(from:to:)` concatenating the overlapping parts) and in `MeetingAudioPath` an
   optional `voices: VoiceBuffers?` (init parameter defaulting to nil) whose `feed` appends `mic` and, remote, the
   `system` samples it already takes, at `time`, inside the existing lock and after the `streaming` guard. Nothing
   else in the tick changes; `MeetingController` still passes nothing.
4. Focused suites — pass. Core suite green. App build.

**Definition of done:**
- Buffers return audio by meeting time across gaps and evict past their length; the tick appends only when buffers exist and only while streaming.
- `MeetingAudioPath` without buffers behaves byte-for-byte as before (existing controller suites green).

**Risks specific to this stage:** None.

### Stage 3 — The Credits window
**Goal:** About gains a quiet "Credits…" pill and grows to 300 × 330; it opens a fixed 460 × 440 Credits window crediting the WeSpeaker voice model (CC BY 4.0) and Sparkle with its bundled licence.
**Category:** hybrid — TDD for `Credits.entries`, the bundled licence and the window sizes; **platform-only/UI wiring remainder** for `CreditsView` and the About pill, verified by the app build and a manual look against the accepted mockup (they are SwiftUI layout with no host-testable logic left).
**Design references:** §3 R26; §5 Interfaces (App: `Credits.entries`, `CreditsView`, `CreditsWindowController`); §5 UI surfaces (Credits); §5 Compatibility (`THIRD_PARTY_NOTICES.md`, `Sparkle-LICENSE.txt`); `DESIGN.md` (small windows, Settings card, quiet small pill — decisions 74, 75); mockup `mockups/mockup-v8-credits.html`
**Touches:** new `App/Credits.swift`, new `App/CreditsView.swift`, new `App/CreditsWindowController.swift`, `App/AboutView.swift`, `App/AboutWindowController.swift`, new `App/Resources/Sparkle-LICENSE.txt`, new `THIRD_PARTY_NOTICES.md`, `AppTests/SmallWindowsTests.swift`, new `AppTests/CreditsTests.swift`

**Steps (TDD):**
1. Write tests:
   - `CreditsTests`: `entriesAreTheModelThenSparkle` — two entries, names "WeSpeaker voice model" and "Sparkle", their
     one-line purposes, the WeSpeaker attribution exactly as design §5 words it, licence "CC BY 4.0" with
     `licenceURL == URL(string: "https://creativecommons.org/licenses/by/4.0")`;
     `sparkleLicenceIsBundledVerbatim` — `Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt")`
     exists, its text starts `Copyright (c) 2006-2013 Andy Matuschak.` and is the text `Credits` shows.
   - `SmallWindowsTests`: rename `aboutIs300By300AndClosesFromItsCloseButton` to `aboutIs300By330…` asserting
     300 × 330; add `creditsIs460By440AndClosesFromItsCloseButton` (titled "Credits", closable, not resizable).
   Expected initial failure: compile error `cannot find 'Credits' in scope` (and `'CreditsWindowController'`).
2. Run `-only-testing:AppTests/CreditsTests -only-testing:AppTests/SmallWindowsTests` — confirm; add an empty
   `Credits.entries = []` and a `CreditsWindowController` over `NSWindow.small(title: "Credits", size: .zero)`;
   re-run — assertion failures: no entries, no bundled licence, About 300 high, Credits 0 × 0.
3. Implement: copy Sparkle 2.9.6's `LICENSE` verbatim from the resolved checkout
   (`.dd/SourcePackages/checkouts/Sparkle/LICENSE`, revision `ac2def2`, as `Package.resolved` pins) to
   `App/Resources/Sparkle-LICENSE.txt`; `Credits.swift` (static entries; the Sparkle text loaded from the bundle);
   `CreditsWindowController` (`NSWindow.small(title: "Credits", size: 460 × 440)`, scrolling content);
   `CreditsView` per the mockup (lead line "Mini Whisper includes the work of others.", one Settings card, a row per
   entry, the licence address as selectable text with "Open Licence…" calling `NSWorkspace.shared.open`, Sparkle's
   "Show Licence" unfolding the text in a monospaced scrolling box); `AboutView` gains a `showCredits` closure and a
   quiet small "Credits…" pill under the "Powered by" line; `AboutWindowController` grows to 330 and owns a lazily
   made `CreditsWindowController`. Write `THIRD_PARTY_NOTICES.md` naming both components, their authors and licences.
4. Focused suites — pass. Core suite. App suite. App build. **UI check:** run the Debug app, open About → Credits…,
   compare with `mockup-v8-credits.html` in light and dark (row layout, quiet pills, the unfolded licence box).

**Definition of done:**
- The two tests files pass; About is 300 × 330 with "Credits…"; Credits is a fixed 460 × 440 small window with the two rows of the mockup.
- `App/Resources/Sparkle-LICENSE.txt` is byte-identical to Sparkle 2.9.6's `LICENSE`; `THIRD_PARTY_NOTICES.md` exists.

**Risks specific to this stage:** None.

### Stage 4 — Stored voice shapes and the meeting sidecar
**Goal:** `VoiceVector`, `NameMatch` and `MeetingVoices` exist; `SpeakerLabel` gains `person`, `matches` and `rejected`, encoded only when set so a meeting without recognition is written byte-for-byte as today; `MeetingStore` reads, writes and deletes `meetings/<id>/voices.json`.
**Design references:** §3 R2, R7, R21; §5 Data model (`meeting.json`, meeting sidecar); §5 Components (`VoiceVector`, `NameMatch`, `MeetingVoices`, `MeetingStore` extended); §5 Testing (`SpeakerLabel` coding, `VoiceVector`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingVoices.swift`, `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingModel.swift`, `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingStore.swift`, new `Packages/MiniWhisperCore/Tests/MWMeetingsTests/VoiceVectorTests.swift`, `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingModelTests.swift`, `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingStoreTests.swift`

**Steps (TDD):**
1. Write tests:
   - `VoiceVectorTests`: `encodesAsBase64OfLittleEndianFloat32` (a 256-float vector encodes to the JSON string of
     the base64 of its LE bytes and decodes equal); `aStringOfTheWrongLengthFailsToDecode`;
     `cosineOfParallelIsOneAndOrthogonalZero`; `weightedCombineIsUnitLengthAndLeansToTheLongerPart`;
     `combineOfNothingIsNil`.
   - `MeetingModelTests`: `aLabelFromAnOldFileHasNoVoiceFields` (the `meeting-v0.5.json` fixture decodes with
     `person == nil`, `matches == []`, `rejected == []`); `aLabelWithoutVoiceFieldsEncodesAsToday`
     (`MeetingCoding.encoder()` on `SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["1:A"])` gives exactly
     `{"id":1,"isUser":false,"name":"Speaker 1","providerKeys":["1:A"]}`); `aLabelWithAllThreeRoundTrips`;
     `nameMatchEncodesItsSixFields`; `meetingVoicesDecodesTheDesignsTwoShapes` (the local and Speechmatics sidecar
     samples of design §5, with a real 256-float base64 vector, decode and re-encode; `MeetingVoices.userKey == "user"`).
   - `MeetingStoreTests`: `voicesRoundTripAt0600`; `readVoicesIsNilWithoutTheFile`;
     `deleteVoicesRemovesOnlyTheSidecar`; `deletingTheMeetingDeletesItsVoices`; `aMeetingWithoutVoicesHasNoSidecar`
     (create + update + rewriteSegments leave no `voices.json`).
   Expected initial failure: compile errors `cannot find 'VoiceVector' in scope`, `extra argument 'matches' in call`,
   `value of type 'MeetingStore' has no member 'writeVoices'`.
2. Run `swift test --filter MWMeetingsTests` — confirm; add the empty API (types with stored properties, synthesized
   `Codable` for `VoiceVector` over `[Float]`, `SpeakerLabel` fields stored but synthesized-encoded, store methods as
   no-ops returning nil); re-run — assertion failures: the vector is not a base64 string, the old-shape label now
   encodes `"matches":[]` and `"rejected":[]`, no file is written.
3. Implement: `MeetingVoices.swift` (`VoiceVector` with base64 LE `Codable`, `cosine`, `normalised`, `combine`;
   `NameMatch` exactly as design §5; `MeetingVoices { schema, route: VoiceRoute, model, keys: [String: Entry] }`,
   `Entry { seconds, vector?, identifier? }`); `SpeakerLabel` gets the three fields with **defaulted trailing init
   parameters** (the 41 existing `SpeakerLabel(` constructions in source and tests stay untouched) and a hand-written
   `Codable` that decodes the original four keys as before, the new three with `decodeIfPresent`, and encodes
   `person` only when set and `matches` / `rejected` only when non-empty; `MeetingStore` gains `File.voices =
   "voices.json"`, `writeVoices(_:of:)` (temp file + rename, 0600, as `write` does), `nonisolated
   readVoices(_:) throws -> MeetingVoices?` and `deleteVoices(_:)`. `Meeting.schema` stays 1.
4. Focused suite — pass. Core suite (the Markdown goldens and agent-access suites prove names and outputs unchanged).
   App build.

**Definition of done:**
- A label without voice data encodes exactly as today; old files decode; the sidecar round-trips at 0600 and goes with its meeting.
- `MeetingReading` (CLI, MCP) exposes nothing new: `load` and `index` are unchanged.

**Risks specific to this stage:** a hand-written `Codable` that drifts from the synthesized key names would rewrite every stored meeting. Mitigation: the exact-bytes test above and the existing golden suites.

### Phase B — The `MWVoices` module and its pure parts

### Stage 5 — The `MWVoices` module: people, samples, matching
**Goal:** the new core module exists and is wired into the package (with its edges from `MWMeetingPipeline` and `MWTestSupport`), with `Log.voice`, the `Person` shape of `voices.json`, the 8-sample `SampleSet`, the `VoiceMatcher`, the `VoiceEmbedding` seam and a `FakeVoiceEmbedder`.
**Design references:** §3 R8, R20, R29; §5 Architecture (`MWVoices` → `MWMeetings`, `MWConfig`, `MWSupport`; `MWMeetingPipeline` → `MWVoices`); §5 Data model (People); §5 Components (`SampleSet`, `VoiceMatcher`, `VoiceEmbedding`); §5 Observability (`Log.voice`); §5 Testing (`SampleSet`, `VoiceMatcher`)
**Touches:** `Packages/MiniWhisperCore/Package.swift`, `Packages/MiniWhisperCore/Sources/MWSupport/Log.swift`, new `Packages/MiniWhisperCore/Sources/MWVoices/Person.swift`, new `…/MWVoices/SampleSet.swift`, new `…/MWVoices/VoiceMatcher.swift`, new `…/MWVoices/VoiceEmbedding.swift`, new `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeVoiceEmbedder.swift`, new `Packages/MiniWhisperCore/Tests/MWVoicesTests/PersonTests.swift`, new `…/MWVoicesTests/SampleSetTests.swift`, new `…/MWVoicesTests/VoiceMatcherTests.swift`

**Steps (TDD):**
0. **Provision the module first** (scaffolding inside the stage — the test target cannot exist without it): in
   `Package.swift` add product `.library(name: "MWVoices", targets: ["MWVoices"])`, target
   `.target(name: "MWVoices", dependencies: ["MWMeetings", "MWConfig", "MWSupport"])`, test target
   `.testTarget(name: "MWVoicesTests", dependencies: ["MWVoices", "MWTestSupport"])`, and `"MWVoices"` in the
   dependency lists of `MWMeetingPipeline` and `MWTestSupport`; create `VoiceEmbedding.swift` holding only the
   protocol (`func prepare() async throws`, `func embed(_ window: [Float]) async throws -> VoiceVector`) and
   `VoiceEmbeddingError` (`.modelUnavailable`, `.badWindow`); add `Log.voice = LogCategory(name: "voice")`. Run
   `swift build` — exit 0. The "confirm fail" steps below are then about behaviour, not a missing target.
1. Write tests:
   - `PersonTests`: `decodesTheDesignShape` (design §5's `voices.json` sample with ISO dates and a 256-float vector);
     `encodesItBackWithSortedKeys`; `aNewPersonHasNoSamplesNoIdentifiersAndIsUntrusted`.
   - `SampleSetTests`: `aSampleAtPointEightFiveOrCloserReplacesTheClosest` (0.85 exactly replaces);
     `aDistantSampleIsAdded`; `theNinthDistantSampleDropsTheOldest`; `aSecondSampleFromTheSameMeetingReplacesThatMeetingsSample`.
   - `VoiceMatcherTests`: `sureNeedsTheThresholdAndTheMargin` (0.70 vs 0.60 → sure; 0.75 vs 0.70 → none);
     `belowSureAboveSuggestionIsASuggestion`; `marginExactlyMetPasses`; `withOnePersonTheRunnerUpIsZero`;
     `aPersonsScoreIsTheirBestSample`; `rejectedPeopleAreNotCandidates`; `theUserIsACandidateOnlyWhenAsked`;
     `aWeakBestIsNothing`; `noPeopleIsNothing`. Thresholds come from a `VoiceSettings` value (Stage 1).
   Expected initial failure: compile errors `cannot find 'Person' in scope`, `cannot find 'SampleSet' in scope`,
   `cannot find 'VoiceMatcher' in scope`.
2. Run `swift test --filter MWVoicesTests` — confirm; add the empty API (`Person` / `LocalSample` /
   `SpeechmaticsIdentifier` with stored properties, `SampleSet.adding` returning its input, `VoiceMatcher.decide`
   returning `.none`); re-run — assertion failures (decoding drops fields, nothing replaced, every decision none).
3. Implement `Person.swift` (`Person { id, name, isUser, createdAt, lastHeard?, aliases, local: [LocalSample],
   speechmatics: [String: SpeechmaticsIdentifier] keyed by tier ("standard" / "enhanced"), speechmaticsTrusted }`
   with the design's JSON keys), `SampleSet` (capacity 8, replace at ≥ 0.85, one per meeting, oldest dropped),
   `VoiceMatcher.decide(probe:people:settings:excluding:includeUser:) -> Decision { outcome, person, score,
   runnerUp }` (R8). Add `FakeVoiceEmbedder` to `MWTestSupport`: records `prepare` and `embed` calls, can hold or
   fail `prepare`, fail `embed`, and maps a window to a vector through an injected closure (default: a unit vector
   chosen by the window's mean amplitude, so tests make "voices" from constant-amplitude audio).
4. Focused suite — pass. Core suite — **18** runs green. App build.

**Definition of done:**
- `MWVoices` builds with system frameworks and the three internal modules only; `MWMeetingPipeline` and `MWTestSupport` list it.
- `SampleSet` and `VoiceMatcher` implement R20 and R8 to the boundary values; `Log.voice` exists.

**Risks specific to this stage:** None.

### Stage 6 — `VoiceWindow` and `SpeechmaticsEnrolment`
**Goal:** the pure turn-to-window cut of R6 and the enrolment list and label parsing of R10/R11.
**Design references:** §3 R6, R10, R11, R27; §5 Components (`VoiceWindow`, `SpeechmaticsEnrolment`); §5 Control flow (Start: enrolment order); §5 Testing (`VoiceWindow`, `SpeechmaticsEnrolment`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWVoices/VoiceWindow.swift`, new `…/MWVoices/SpeechmaticsEnrolment.swift`, new `Packages/MiniWhisperCore/Tests/MWVoicesTests/VoiceWindowTests.swift`, new `…/MWVoicesTests/SpeechmaticsEnrolmentTests.swift`

**Steps (TDD):**
1. Write tests:
   - `VoiceWindowTests`: `wordsAtMostThreeTenthsApartMerge` (0.30 merges, 0.31 does not);
     `spansArePaddedFiveHundredthsEachSide`; `speechSecondsIsTheMergedPaddedLength`;
     `longSpeechSplitsIntoTenSecondWindows` (23 s → 10, 10, 3); `aTailUnderOneAndAHalfSecondsIsDropped`
     (21 s → 10, 10); `underOneAndAHalfSecondsYieldsNoWindow`; `eachWindowIsLoopedTo160000Samples` (2 s ramp →
     160,000 samples, `samples[32_000] == samples[0]`, `seconds == 2`); `aPartialBufferUsesWhatIsThere` (the read
     closure returns half the span → windows and seconds from the half).
   - `SpeechmaticsEnrolmentTests`: `onlyPeopleWithAnIdentifierForTheTier`; `newestHeardFirstFallingBackToTheIdentifiersDate`;
     `atMostFifty`; `theLabelIsMwAndTheLowercasePersonUUID`; `aLabelParsesBackToAKnownPersonOnly` (unknown UUID →
     nil, `S1` → nil, an uppercase UUID after `mw:` → nil).
   Expected initial failure: compile errors `cannot find 'VoiceWindow' in scope`, `cannot find 'SpeechmaticsEnrolment' in scope`.
2. Run `swift test --filter "VoiceWindowTests|SpeechmaticsEnrolmentTests"` — confirm; add empty API (no spans, no
   windows, no entries, nil parse); re-run — assertion failures.
3. Implement `VoiceWindow` (`spans(of words: [Word])`, `speechSeconds(of:)`, `windows(from samples:)`,
   `windows(spans:read:)`, `Window { samples, seconds }`; constants 16 kHz, 160,000, 1.5 s, 10 s, 0.3 s, 0.05 s) and
   `SpeechmaticsEnrolment` (`entries(people:tier:) -> [Entry { person, label, identifier }]`, `label(for:)`,
   `person(forLabel:among:)`, limit 50). `MWVoices` does not import `MWStreaming`; the controller maps entries to
   `VoiceSessionConfig` in Stage 17.
4. Focused suites — pass. Core suite. App build.

**Definition of done:** R6's cut and R10/R11's list and label rules hold to their boundaries; labels never contain a name (R27).

**Risks specific to this stage:** None.

### Stage 7 — `VoiceStore`
**Goal:** the actor that owns `~/.config/mini-whisper/voices.json`: find-or-create by name, the user's entry, rename with refusal, merge, forget, samples through `SampleSet`, identifiers per tier, trust, last heard, atomic 0600 writes, corrupt-file backup, and a `changes` stream.
**Design references:** §3 R13, R17, R18, R20, R23, R24; §5 Data model (People); §5 Control flow (People actions: Rename, Merge, Forget); §5 Failure cases (`voices.json` unreadable; write fails); §5 Testing (`VoiceStore`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWVoices/VoiceStore.swift`, new `Packages/MiniWhisperCore/Tests/MWVoicesTests/VoiceStoreTests.swift`

**Steps (TDD):**
1. Write tests (each store in a `TempDirectory`): `findOrCreateMatchesTheTrimmedNameExactly`; `aNewNameCreatesAPerson`;
   `aDefaultSpeakerNameNeverCreatesAPerson` (`"Speaker 3"` → nil, R17); `theUsersEntryIsCreatedOnceAndMarkedIsUser`;
   `renameRefusesANameAnotherPersonHas` (throws `VoiceStoreError.nameTaken`); `theUsersEntryHasNoRename`;
   `mergeFeedsBothPeoplesSamplesOldestFirstKeepsTheNewerIdentifierPerTierOrsTrustAndAppendsAliases`;
   `theUserIsNeverMergedIntoAnother`; `forgetReturnsTheIdAndItsAliases`; `forgetEveryoneDeletesTheFile`;
   `aLocalSampleGoesThroughSampleSet`; `removeLocalSampleDropsThatMeetingsSample`; `anIdentifierIsKeptOnePerTierNewest`;
   `dropIdentifierRemovesItAndReturnsItsPerson`; `markHeardSetsLastHeard`; `writesAre0600AndLeaveNoTempFile`;
   `anUnreadableFileMovesToBakAndTheStoreStartsEmpty`; `everyWritePublishesOnChanges`;
   `aFailedWriteThrowsAndKeepsTheChangeForTheNextWrite` (the folder made read-only, then writable again).
   Expected initial failure: compile error `cannot find 'VoiceStore' in scope`.
2. Run `swift test --filter VoiceStoreTests` — confirm; add the empty actor (methods returning nil / empty / no-ops,
   `changes` finished); re-run — assertion failures.
3. Implement `public actor VoiceStore` (pattern of `ConfigStore`: `init(directory:)`, a single-consumer
   `nonisolated let changes: AsyncStream<[Person]>`, temp file renamed into place at 0600, `voices.json.bak` on a
   decode failure with a `Log.voice` line carrying no content) with the API above and `VoiceStoreError`.
4. Focused suite — pass. Core suite. App build.

**Definition of done:** every R24 store rule and R17/R18/R20 rule above is tested; the file is 0600 and atomic; nothing logged carries a name.

**Risks specific to this stage:** None.

### Stage 8 — `MatchLog` and `VoiceScrubber`
**Goal:** the append-only match log with its 2 MB trim and per-person removal, and the scrubber that removes a person's (or everyone's) voice data from meetings on disk, reusable as a pure function for a meeting a session holds.
**Design references:** §3 R21, R23, R24; §5 Data model (Match log); §5 Control flow (People actions: Forget, Forget everyone); §5 Performance (Forget scans once, off the main actor); §5 Testing (`MatchLog`, `VoiceScrubber`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWVoices/MatchLog.swift`, new `…/MWVoices/VoiceScrubber.swift`, new `Packages/MiniWhisperCore/Tests/MWVoicesTests/MatchLogTests.swift`, new `…/MWVoicesTests/VoiceScrubberTests.swift`

**Steps (TDD):**
1. Write tests:
   - `MatchLogTests`: `appendsOneJSONLinePerEntryAt0600` (fields `at, meeting, key, route, event, person, score,
     runnerUp, seconds`; events `suggested, applied, accepted, dismissed, rejected, renamed`);
     `pastTheLimitTheOldestHalfIsDropped` (limit injected at 1 KB); `removePeopleRewritesWithoutTheirLines`;
     `removeAllDeletesTheFile`; `anUnwritableLogThrows`.
   - `VoiceScrubberTests` (meetings written through `MeetingStore` in a `TempDirectory`):
     `scrubbingAPersonClearsTheirLinksMatchesRejectedAndSidecarKeys` (only keys owned by speakers linked to them);
     `anEmptiedSidecarIsDeleted`; `everyIdInTheSetIsScrubbed` (aliases); `skippedMeetingsAreLeftAlone`;
     `everyoneDeletesEverySidecarAndClearsEveryLinkMatchAndRejection`; `namesInTheTranscriptStay` (speaker names and
     `segments.jsonl` bytes unchanged); `aMeetingWithoutVoiceDataIsNotRewritten` (`meeting.json` bytes unchanged);
     `thePureScrubOfOneMeeting` (`VoiceScrubber.scrub(_:voices:people:)` on an in-memory `Meeting`).
   Expected initial failure: compile errors `cannot find 'MatchLog' in scope`, `cannot find 'VoiceScrubber' in scope`.
2. Run `swift test --filter "MatchLogTests|VoiceScrubberTests"` — confirm; empty API; re-run — assertion failures.
3. Implement `public actor MatchLog` (`init(url:limit: = 2 MB)`, `append`, `remove(people:)`, `removeAll()`, 0600)
   and `VoiceScrubber` (`init(store: MeetingStore)`, `scrub(people: Set<UUID>?, skipping: Set<UUID>) async`, the
   pure `static func scrub(_ meeting: inout Meeting, voices: MeetingVoices?, people: Set<UUID>?) -> MeetingVoices?`;
   `nil` people means everyone).
4. Focused suites — pass. Core suite. App build.

**Definition of done:** R21/R23/R24's disk rules for the log and the per-meeting data hold; transcripts are never edited.

**Risks specific to this stage:** None.

### Stage 9 — `SpeakerRegistry`: suggest, apply, accept, dismiss, detach, link
**Goal:** the six pure registry operations of design §5, with `rename`'s merge carrying the new fields to the surviving speaker.
**Design references:** §3 R9, R14, R15, R16; §5 Interfaces (`SpeakerRegistry` additions); §5 Failure cases (two speakers accepted as one person); §5 Testing (`SpeakerRegistry`)
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SpeakerRegistry.swift`, `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SpeakerRegistryTests.swift`

**Steps (TDD):**
1. Write tests in `SpeakerRegistryTests.swift`: `suggestStoresTheMatchAndKeepsTheName`;
   `aLaterMatchForTheSameKeyReplacesTheEarlier`; `applyRenamesADefaultNamedSpeaker`;
   `applyOntoAnExistingNameMergesAndKeepsTheMatchOnTheSurvivor` (returns the `Merge`);
   `applyOfTheUsersPersonRenamesToTheUserName` (merges into the user); `applyLeavesANamedALinkedOrTheUserSpeakerAlone`
   (three cases → nil, labels unchanged); `acceptRenamesLinksAndRemovesTheMatch` (returns the person and nil merge);
   `acceptOntoAnExistingNameMerges`; `dismissRemovesTheMatchAndRejectsThePerson`;
   `detachOfASoleUnlinkedKeyReturnsItToSpeakerN`; `detachOfOneOfSeveralKeysMovesItToANewSpeaker` (id max + 1,
   person in `rejected`, returns `Detach { key, from, to }`); `linkSetsThePersonAndRejectsOtherPeoplesMatches`;
   `aRenameMergeCarriesMatchesRejectedAndPerson` (survivor keeps its person, or takes the absorbed one's when it has
   none; matches and rejections union).
   Expected initial failure: compile error `value of type 'SpeakerRegistry' has no member 'suggest'`.
2. Run `swift test --filter SpeakerRegistryTests` — confirm; empty methods; re-run — the new tests fail, the 8
   existing pass.
3. Implement in `SpeakerRegistry.swift`; `apply` and `accept` go through `rename`, as design §5 says.
4. Focused suite — pass (8 + 13). Core suite. App build.

**Definition of done:** the six operations behave as design §5's table; existing registry, attributor and controller suites green.

**Risks specific to this stage:** None.

### Stage 10 — The bundled voice model and `CoreMLVoiceEmbedder`
**Goal:** `wespeaker_v2.mlmodelc` is committed under `App/Resources/` and bundled as one folder; `CoreMLVoiceEmbedder` loads it lazily and turns a 160,000-sample window into an L2-normalised 256-float vector; a `macos-15` CI job checks the model on the oldest hosted macOS.
**Category:** hybrid — TDD for the embedder's input/output assembly and missing-model path (core) and for the bundled model (AppTests); **integration-verified remainder** for the CI job, verified locally by compiling and running `scripts/voice_model_check.swift` and on the next pushed CI run.
**Design references:** §3 R6, R26, R29; §5 Components (`VoiceEmbedding`, `CoreMLVoiceEmbedder`); §5 Compatibility (`project.yml` folder reference); §5 Testing (Model in the bundle); §7 (macOS 14 unverified; xcodegen flattening); §9 (macos-15 job)
**Touches:** new `App/Resources/wespeaker_v2.mlmodelc/` (`analytics/coremldata.bin`, `coremldata.bin`, `metadata.json`, `model.mil`, `weights/weight.bin`), `project.yml`, new `Packages/MiniWhisperCore/Sources/MWVoices/CoreMLVoiceEmbedder.swift`, new `Packages/MiniWhisperCore/Tests/MWVoicesTests/CoreMLVoiceEmbedderTests.swift`, new `AppTests/VoiceModelTests.swift`, new `AppTests/Fixtures/daniel-1.wav`, `daniel-2.wav`, `karen-1.wav`, `karen-2.wav`, new `scripts/voice_model_check.swift`, `.github/workflows/build.yml`

**Steps (TDD):**
1. Provision the assets (no behaviour yet):
   - Download the five model files from the pinned revision
     `https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/7eab74f3463c736418d0eb10296261ae581146c9/wespeaker_v2.mlmodelc/<path>`
     into `App/Resources/wespeaker_v2.mlmodelc/` and verify them before use: SHA-256 `weights/weight.bin`
     `34004f6798d35cad7071e2fdc67e63faaa782f53697e1cb49bcb452cf81ae151`, `coremldata.bin`
     `6feb2472a71fa9d8a84020c85206138a4f6261c565c9884bf518d59dd5838da7`, `analytics/coremldata.bin`
     `d2b1fcde6121aea3ff0e14c1dc50d09dacb0314a2e89156353c31804230a422f`; `git hash-object` `metadata.json`
     `5cda8cc14897fb37b01552a0fb9fefca31a6c00f`, `model.mil` `977dcf031d18b18fb5096d3e943ff8aa18754e21` (7.6 MB in all).
   - Generate the clips:
     `say -v Daniel --file-format=WAVE --data-format=LEI16@16000 -o AppTests/Fixtures/daniel-1.wav "The quarterly numbers came in higher than we expected, so the team will review the forecast on Thursday."`,
     the same for `karen-1.wav` with `-v Karen`, and `daniel-2.wav` / `karen-2.wav` with
     `"Before we ship the update, someone needs to check the release notes and the installer once more."`.
   - `project.yml`: under the `MiniWhisper` target's sources, `- path: App` gains
     `excludes: ["Resources/wespeaker_v2.mlmodelc"]`, followed by `- path: App/Resources/wespeaker_v2.mlmodelc`,
     `type: folder`, `buildPhase: resources`; add `- package: MiniWhisperCore / product: MWVoices` to its
     dependencies. `xcodegen generate` and confirm `grep -c "lastKnownFileType = folder; name = wespeaker_v2.mlmodelc"
     "Mini Whisper.xcodeproj/project.pbxproj"` is 1 and no `model.mil` reference exists.
2. Write tests:
   - Core `CoreMLVoiceEmbedderTests`: `theInputFillsEveryRowWithTheWindowAndAnAllOnesMask`
     (`CoreMLVoiceEmbedder.input(window)` → `waveform` [3, 160000] each row equal to the window, `mask` [3, 589]
     all 1); `aWindowOfTheWrongLengthIsRejected` (`VoiceEmbeddingError.badWindow`); `outputRowZeroIsNormalised`
     (a [3, 256] array → unit vector in row 0's direction); `withoutAModelPrepareThrows`
     (`CoreMLVoiceEmbedder(modelURL: nil)` and a URL to a missing folder → `.modelUnavailable`).
   - `AppTests/VoiceModelTests`: `theModelIsInTheAppBundleAsOneFolder` (`Bundle.main.url(forResource:
     "wespeaker_v2", withExtension: "mlmodelc")` holds `coremldata.bin`, `model.mil`, `weights/weight.bin`);
     `prepareLoadsTheBundledModel`; `sameVoiceScoresAboveSeventyAndOtherVoicesBelow` — each clip read with
     `AVAudioFile` from the **test bundle** (`Bundle(for: FixtureAnchor.self)`, a private class in the file), cut with
     `VoiceWindow.windows(from:)` (one window each), embedded; Daniel 1·2 and Karen 1·2 > 0.7, every cross pair < 0.7.
   Expected initial failure: compile error `cannot find 'CoreMLVoiceEmbedder' in scope`.
3. Run `swift test --filter CoreMLVoiceEmbedderTests` and `-only-testing:AppTests/VoiceModelTests` — confirm; add
   the empty class (`prepare` and `embed` throwing `.modelUnavailable`, `input` returning zeros); re-run — assertion
   failures (zero rows, `prepare` throwing on the bundled model, no scores).
4. Implement `CoreMLVoiceEmbedder` (`public final class … : VoiceEmbedding, @unchecked Sendable`, `init(modelURL:
   URL?)`, `MLModel` loaded once under a lock on the first `prepare` / `embed`, the three waveform rows filled with
   the window and all-ones masks, output row 0 read and normalised; `import CoreML` only). Write
   `scripts/voice_model_check.swift` (top-level Swift that compiles with the runner's toolchain: load the model with
   `MLModel`, embed each clip looped to 160,000 samples, print the cosine table, exit 1 unless both same-voice pairs
   are > 0.7 and every cross pair < 0.7). Add a CI job `voice-model` (`runs-on: macos-15`; checkout;
   `swiftc -O scripts/voice_model_check.swift -o "$RUNNER_TEMP/voice_model_check"`; run it on
   `App/Resources/wespeaker_v2.mlmodelc` and the four `AppTests/Fixtures/*.wav`), standalone (not in `build`'s
   `needs`).
5. Focused suites — pass. Core suite. App suite. App build. **Integration remainder:** locally
   `swiftc -O scripts/voice_model_check.swift -o "$TMPDIR/voice_model_check" && "$TMPDIR/voice_model_check"
   App/Resources/wespeaker_v2.mlmodelc AppTests/Fixtures/daniel-1.wav AppTests/Fixtures/daniel-2.wav
   AppTests/Fixtures/karen-1.wav AppTests/Fixtures/karen-2.wav` exits 0 with scores near 0.93 / 0.87 / ≤ 0.25; the
   `voice-model` job is checked green on the next pushed run (`gh run view`), outside the stage.

**Definition of done:**
- The model's five files match the published hashes and ship inside `Mini Whisper.app/Contents/Resources/wespeaker_v2.mlmodelc/`.
- `CoreMLVoiceEmbedder` separates the fixture voices in AppTests; the script passes locally; `MiniWhisperCore` imports only `CoreML` beyond its existing frameworks.

**Risks specific to this stage:** the `macos-15` runner's Xcode may compile only Swift 5.10/6.0 syntax — keep the script to plain top-level code (the design probe's shape); the job's first real result arrives only on push (*Risks* 4).

### Phase C — Streaming, the recogniser and Settings

### Stage 11 — The Speechmatics identification wire
**Goal:** `SpeechmaticsAdapter` can enrol voices and ask for identifiers, `WebSocketEngine` can send a command between audio chunks, and `SpeakersResult` and the `speaker_id` warning reach the sink — with `StartRecognition` byte-identical when no voices are passed.
**Design references:** §3 R2, R10, R12, R13, R27; §5 Interfaces (Streaming); §5 Security (Speechmatics trust boundary); §5 Compatibility (both `WebSocketEngine.apply` switches); §5 Testing (`SpeechmaticsAdapter`, `WebSocketEngine`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWStreaming/VoiceSessionConfig.swift` (`VoiceSessionConfig`, `ProviderSpeaker`, `EngineCommand`), `…/MWStreaming/EngineAdapter.swift`, `…/MWStreaming/StreamingEngine.swift`, `…/MWStreaming/TranscriptSink.swift`, `…/MWStreaming/Adapters/SpeechmaticsAdapter.swift`, `…/MWStreaming/WebSocketEngine.swift`, `Packages/MiniWhisperCore/Sources/MWTestSupport/RecordingSink.swift`, `…/MWTestSupport/FakeStreamingEngine.swift`, new `Packages/MiniWhisperCore/Tests/MWStreamingTests/SpeechmaticsVoiceTests.swift`, `…/MWStreamingTests/WebSocketEngineTests.swift`, new `…/MWStreamingTests/Fixtures/streaming/speechmatics_speakers_result.json`, new `…/Fixtures/streaming/speechmatics_speaker_id_warning.json`, new `…/Fixtures/streaming/speechmatics_speaker_id_warning_unparsed.json`

**Steps (TDD):**
1. Write the three fixtures from the shapes recorded in design §4 (placeholder identifiers, never real
   ones): `{"message":"SpeakersResult","speakers":[{"label":"S1","speaker_identifiers":["id-s1"]},{"label":"mw:…","speaker_identifiers":["id-mw"]}]}`;
   `{"message":"Warning","type":"speaker_id","reason":"identifier '1', speaker '2' - reason: identifier from an incompatible model"}`;
   the same with an unparseable reason. Write tests:
   - `SpeechmaticsVoiceTests`: `startRecognitionIsUnchangedWithoutVoices` (`SpeechmaticsAdapter(apiKey:hints:
     diarization: true, model: "standard")` open message bytes equal those with `voices: nil`, and
     `speaker_diarization_config` is exactly `{"max_speakers":10}`); `voicesAddGetSpeakersSensitivityAndSpeakers`
     (two speakers → `get_speakers: true`, `speaker_sensitivity: 0.8`, `speakers: [{label, speaker_identifiers:
     [id]}]` in order); `anEmptyEnrolmentOmitsSpeakers`; `requestSpeakersEncodesGetSpeakersNotFinal`
     (`{"final":false,"message":"GetSpeakers"}`); `otherAdaptersEncodeNoCommand` (`AssemblyAIAdapter` → nil);
     `speakersResultEmitsEachLabelsIdentifiers`; `aSpeakerIdWarningNamesTheEnrolledLabelAndIdentifier` (1-based
     indices into the adapter's own `speakers`); `anUnparsedOrOutOfRangeWarningEmitsNils`;
     `theSessionTimeoutWarningStillRollsOver` (guard of today's behaviour); `warningTextIsNeverLogged`
     (`CapturingLogSink`).
   - `WebSocketEngineTests`: `aCommandIsSentBetweenAudioChunks` (feed, `send(.requestSpeakers)`, feed →
     `FakeWebSocketConnection.sentMessages` open, binary, `GetSpeakers`, binary); `aCommandTheAdapterCannotEncodeIsDropped`
     (`TestAdapter`); `aCommandAfterFinishIsDropped`; `speakersAndIgnoredIdentifiersReachTheSink` (`RecordingSink`
     gains `speakers` and `ignored`).
   Expected initial failure: compile errors `type 'AdapterEmitter.Emission' has no member 'speakers'`, `extra
   argument 'voices' in call`, `value of type 'WebSocketEngine<SpeechmaticsAdapter>' has no member 'send'`.
2. Run `swift test --filter "SpeechmaticsVoiceTests|WebSocketEngineTests"` — confirm; add the empty API (types,
   emission cases handled as `break` in both `apply` switches, protocol defaults: `encode` → nil, `send` no-op, sink
   no-ops, adapter ignoring `voices`); re-run — assertion failures (no new fields, no `GetSpeakers`, nothing emitted).
3. Implement per design §5 Streaming: `VoiceSessionConfig`, `ProviderSpeaker`, `EngineCommand`; the two
   `Emission` cases and emitter methods; `EngineAdapter.encode(_:)` (default nil); `StreamingEngine.send(_:)`
   (default no-op); `TranscriptSink.onSpeakers` / `onIdentifierIgnored` (default no-ops);
   `SpeechmaticsAdapter(…, voices: VoiceSessionConfig? = nil)` (open message, `encode(.requestSpeakers)`,
   `SpeakersResult`, the anchored `identifier '(\d+)', speaker '(\d+)'` parse; warning text never logged or
   emitted); `WebSocketEngine`: `QueueItem.command(EngineCommand)`, `send` enqueueing unless failed or finishing, the
   send loop encoding it between chunks (dropped when `encode` is nil), both `apply` switches forwarding the two
   emissions to the sink; `FakeStreamingEngine` records `commands`; `RecordingSink` records both callbacks.
   `drainAfterComplete` stays zero.
4. Focused suites — pass. Core suite (all four adapters' suites green). App build.

**Definition of done:** with `voices: nil` the Speechmatics wire is byte-identical to today (R2); with voices it matches design §5 exactly; `SpeakersResult` and `speaker_id` reach the sink; warning text is never logged (R27).

**Risks specific to this stage:** the fixtures are written from recorded shapes, not captures. Mitigation: the adapter ignores unknown keys, and Stage 12's live test exercises the real wire.

### Stage 12 — Per-session enrolment and `GetSpeakers`
**Goal:** `makeMeeting` carries a `VoiceSessionConfig?`; `SessionSupervisor` reads it from a closure at every `install`, forwards `requestSpeakers()` to the current session only, and turns the two new sink callbacks into `SupervisorEvent`s; `MeetingController` ignores them for now.
**Category:** hybrid — TDD for the factory and supervisor; **integration-verified remainder**: `SpeechmaticsVoiceLiveTests` (opt-in, `MW_INTEGRATION=1`, spends the user's Speechmatics credits, never in CI).
**Design references:** §3 R2, R10, R12; §5 Interfaces (`MeetingEngineProviding`, `SessionSupervisor`, `SupervisorEvent`); §5 Compatibility; §5 Testing (`SessionSupervisor`, Integration)
**Touches:** `Packages/MiniWhisperCore/Sources/MWStreaming/MeetingEngineProviding.swift`, `…/MWStreaming/EngineFactory.swift`, `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeMeetingEngineProvider.swift`, `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SessionSupervisor.swift`, `…/MWMeetingPipeline/MeetingController.swift` (the `handle` switch only), `Packages/MiniWhisperCore/Tests/MWStreamingTests/EngineFactoryTests.swift`, `…/MWStreamingTests/MeetingEngineLiveTests.swift`, `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SessionSupervisorTests.swift`, new `…/MWStreamingTests/SpeechmaticsVoiceLiveTests.swift`

**Steps (TDD):**
1. Write tests:
   - `EngineFactoryTests`: the private `meetingSession(_:hints:)` helper gains `voices:`;
     `speechmaticsMeetingsCarryTheVoicesIntoStartRecognition` (both tiers; nil → frames as today);
     `assemblyAIIgnoresVoices` (open frames identical with and without).
   - `SessionSupervisorTests`: `voicesAreReadAtEveryInstall` (a counting closure; open, a lost session's reopen and a
     rollover each read it, and `FakeMeetingEngineProvider.calls[i].voices` carries what it returned);
     `requestSpeakersReachesOnlyTheCurrentSession` (after a rollover only the new engine's `commands` hold
     `.requestSpeakers`); `requestSpeakersWithoutASessionDoesNothing`; `speakersAndIgnoredIdentifiersBecomeEvents`
     (`.speakers(_, session: 1)`, `.identifierIgnored(label:identifier:)`).
   Expected initial failure: compile errors `extra argument 'voices' in call` (factory, supervisor) and `type
   'SupervisorEvent' has no member 'speakers'`.
2. Run `swift test --filter "EngineFactoryTests|SessionSupervisorTests"` — confirm; add the parameter everywhere it
   is required (protocol, `EngineFactory`, `FakeMeetingEngineProvider`, the test-private `AnnouncingProvider` in
   `SessionSupervisorTests.swift`, the call in `MeetingEngineLiveTests.swift`, `SessionSupervisor.install`) passing
   nil, the event cases, and `MeetingController.handle`'s two new `case`s as `break`; re-run — assertion failures
   (voices never reach the adapter, the closure never read, no commands, no events).
3. Implement: `makeMeeting(_:key:hints:voices:)` handing `voices` to `SpeechmaticsAdapter` and ignoring it for
   AssemblyAI; `SessionSupervisor.init(…, voices: @escaping @Sendable () -> VoiceSessionConfig? = { nil })` read in
   `install` under the lock; `requestSpeakers()` sending `.requestSpeakers` to `state.current`'s engine outside the
   lock; `SessionSink.onSpeakers` / `onIdentifierIgnored` yielding the two events. Write
   `SpeechmaticsVoiceLiveTests.enrolThenRecognise` (`@Suite(.enabled(if: MW_INTEGRATION == "1"))`,
   `@Test(.enabled(if: SPEECHMATICS_API_KEY != nil))`, key read from the environment only and never printed): play
   `two_speakers.wav` with an empty enrolment and `get_speakers`, take `S1`'s identifier from the recorded
   `SpeakersResult`, play it again enrolling it as `mw:<uuid>`, expect segments labelled `mw:<uuid>`.
4. Focused suites — pass. Core suite. App build. **Integration remainder:** the user runs
   `MW_INTEGRATION=1 SPEECHMATICS_API_KEY=… swift test --filter SpeechmaticsVoiceLiveTests` locally (key set in their
   own shell); without the variables the suite reports skipped.

**Definition of done:** every `makeMeeting` implementer and caller compiles with the new parameter; the supervisor reads the enrolment at every session open and asks only the current session for speakers; meetings behave as today (controller suites green).

**Risks specific to this stage:** None beyond the live test's cost, which is opt-in.

### Stage 13 — `VoiceRecogniser`
**Goal:** the actor that cuts each labelled final segment's audio at once, embeds its windows off the main actor, files turn vectors per segment and key, moves them on a revision, evaluates a key with the settings and people read at that moment, and streams sure/suggestion decisions.
**Design references:** §3 R3, R6, R7, R8, R28; §5 Components (`VoiceRecogniser`); §5 Control flow (Segment arrives, local; Revision); §5 Failure cases (embedding throws; audio older than the buffer; no provider label); §5 Testing (`VoiceRecogniser`)
**Touches:** new `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/VoiceRecogniser.swift`, new `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/VoiceRecogniserTests.swift`

**Steps (TDD):**
1. Write tests (`FakeVoiceEmbedder`; buffers filled with constant-amplitude "voices"):
   `aLabelledSegmentYieldsOneVectorPerWindow` (12 s of words → 2 embeds); `aSegmentWithoutALabelOrUnderOneAndAHalfSecondsYieldsNothing`;
   `aKeysVoiceIsTheSecondsWeightedNormalisedSum`; `evaluationWaitsForTheMinimumSpeech` (14 s → no decision, 16 s →
   one); `settingsAndPeopleAreReadAtEachEvaluation` (a threshold changed between two segments changes the outcome);
   `aSureMatchIsDecidedSure`; `aMiddlingMatchIsASuggestion`; `aWeakMatchDecidesNothing`;
   `rejectedPeopleAreNotOffered`; `theUserIsOfferedOnlyWhenTheContextSaysSo`; `theUserKeyIsFedButNeverEvaluated`;
   `aRevisionMovesVectorsAndReEvaluatesBothKeysWithoutEmbedding`; `anEmbeddingErrorSkipsTheSegmentAndWarnsOncePerMeeting`
   (`CapturingLogSink`, `Log.voice`); `audioIsCutAtIngestNotWhenTheQueueReachesIt` (the buffer evicted right after
   `ingest`); `finishDrainsTheQueue`; `voicesSnapshotsEveryKeyForTheSidecar`; `embeddingRunsOffTheMainThread` (the
   fake records `Thread.isMainThread == false`).
   Expected initial failure: compile error `cannot find 'VoiceRecogniser' in scope`.
2. Run `swift test --filter VoiceRecogniserTests` — confirm; empty actor (`ingest` no-op, `decisions` finished);
   re-run — assertion failures.
3. Implement `actor VoiceRecogniser`: `init(embedder:settings:people:)` (async closures), `nonisolated func
   ingest(_ segment: Segment, key: String, audio: VoiceAudioBuffer, context: Context)` cutting with
   `VoiceWindow.windows(spans:read:)` synchronously and enqueueing the embed work on one internal `AsyncStream`
   consumer; `nonisolated func revise(_ moves: [(segment: UUID, key: String)], context:)`; `nonisolated let
   decisions: AsyncStream<Decision>` (sure and suggestion only, with key, person, score, runner-up, seconds);
   `finish() async`; `voices() -> [String: (vector: VoiceVector, seconds: Double)]`. `Context { evaluate,
   rejected, includeUser }` is the controller's snapshot of R8's eligibility at ingest.
4. Focused suite — pass. Core suite. App build.

**Definition of done:** R6–R8 hold on fakes; nothing embeds on the main thread or the capture thread; an embedding failure costs one segment and one warning.

**Risks specific to this stage:** a queue that never drains would hang Stop. Mitigation: `finishDrainsTheQueue`, and `.timeLimit(.minutes(1))` on the suite.

### Stage 14 — Voice settings in Settings › Meetings
**Goal:** the Engine card shows "Remember voices with Speechmatics" and "Remember voices on this Mac" under their engine rows, disabled with a reason when they cannot work, and while either is on the Cautious–Eager slider with its caption and an Advanced disclosure of six sliders.
**Category:** hybrid — TDD for every rule in `SettingsModel`; **platform-only/UI wiring remainder** for `MeetingsSection`'s layout, verified by the app build and a manual comparison with the accepted mockup.
**Design references:** §3 R1, R3, R4; §5 Interfaces (App: `SettingsModel`); §5 UI surfaces (Settings › Meetings › Engine); §5 Design language; `DESIGN.md` (Settings card, Setting row, Switch, stock slider as Sound › Volume uses it); mockup `mockups/mockup-v8-recognition-settings.html#in-engine-card`
**Touches:** `App/Settings/SettingsModel.swift`, `App/Settings/MeetingsSection.swift`, `App/AppDelegate.swift` (one shared `CoreMLVoiceEmbedder` over `Bundle.main`'s model, and the settings dependency that prepares it), `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write tests in `SettingsModelTests.swift`: `voiceSwitchesWriteTheirKeys`; `aSwitchWithoutItsProvidersKeyIsDisabledWithTheKeyHint`;
   `theLocalSwitchIsDisabledWhenTheModelFailsToLoad` (reason exactly "The voice model could not be loaded on this
   Mac."); `theModelIsPreparedOnceWhenMeetingsFirstAppears` (two `checkVoiceModel()` calls → one prepare);
   `aSwitchOnWhileItsProviderIsNotActiveSaysWhenItIsUsed` ("Used when a Speechmatics engine is selected." / "Used
   when an AssemblyAI engine is selected."); `tuningShowsWhileEitherSwitchIsOn`;
   `aStepWritesItsFiveValuesAndKeepsTheBuffer`; `theCaptionNamesTheStepAndItsThresholds` (5 → "Balanced · applies a
   name at 0.70, suggests from 0.50"; 0 and 1 "Most cautious", 2–4 "Cautious", 6–8 "Eager", 9–10 "Most eager");
   `aHandSetValueIsCustom` (caption "Custom · set in Advanced", reset offered); `resetVoiceTuningReturnsToBalanced`;
   `aValueWhoseRouteIsOffIsDimmed` (sensitivity with Speechmatics off; the other five with the local route off);
   `advancedReadOutsFormatEachValue` ("0.70", "15 s", "120 s").
   Expected initial failure: compile error `value of type 'SettingsModel' has no member 'voice'`.
2. Run `-only-testing:AppTests/SettingsModelTests` — confirm; add the empty API (`voice` returning
   `VoiceSettings()`, setters no-ops, `voiceModelStatus` nil, captions empty, `Dependencies.prepareVoiceModel`
   defaulting to `{ true }`); re-run — assertion failures.
3. Implement in `SettingsModel`: `voice`, `voiceModelStatus` (`.ready` / `.failed`), `checkVoiceModel()`,
   `setVoiceEnabled(_:for:)`, `setVoiceStep(_:)`, `setVoice(_:for:)`, `resetVoiceTuning()`, the disabled reasons
   (reusing `keyHint(for:)`), the "Used when…" line, caption, dimming and read-outs. `MeetingsSection`: each switch
   in an inset box under its two engine rows with the design's disclosure text shown always, a hairline between
   providers, the tuning row (stock `Slider` 0…10 step 1, accent tint, "Cautious" / "Eager" ends, caption) and a
   closed "Advanced" `DisclosureGroup` of six sliders with read-outs; `.task { await model.checkVoiceModel() }`.
   `AppDelegate` creates one `CoreMLVoiceEmbedder(modelURL: Bundle.main.url(forResource: "wespeaker_v2",
   withExtension: "mlmodelc"))` and passes `prepareVoiceModel: { (try? await embedder.prepare()) != nil }`.
4. Focused suite — pass. Core suite. App suite. App build. **UI check:** Settings › Meetings in light and dark against
   `mockup-v8-recognition-settings.html#in-engine-card` (switch boxes, descriptions, the grey line, slider and
   Advanced; a hand-set value's hollow thumb and "Reset to Balanced").

**Definition of done:** R1's switches write `config.json`; R4's two disabled reasons show; the slider and Advanced write the five values; switching on still changes nothing in a meeting (no `VoiceDependencies` yet).

**Risks specific to this stage:** the stock `Slider` may not draw the mockup's hollow thumb for Custom (*Risks* 6).

### Phase D — The controller

### Stage 15 — Controller: local recognition
**Goal:** with the local switch on at Start of an AssemblyAI meeting that is not a test call, the controller allocates the buffers, prepares the model without delaying Start, feeds every labelled segment to the recogniser, applies sure matches and stores suggestions through the registry, follows revisions, logs each match, stops matching the moment the switch goes off, and writes the sidecar at Stop.
**Design references:** §3 R2, R3, R5, R7, R8, R9, R14, R16, R21, R23, R25, R27; §5 Interfaces (`VoiceDependencies`, `MeetingEvent` additions); §5 Control flow (Start; Audio tick; Segment arrives, local; Revision; Stop); §5 Failure cases; §5 Observability; §5 Testing (`MeetingController`)
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingDependencies.swift`, `…/MWMeetingPipeline/MeetingEvent.swift`, new `…/MWMeetingPipeline/MeetingVoiceRoute.swift`, `…/MWMeetingPipeline/MeetingController.swift`, `App/Meeting/MeetingWindowModel.swift` (two no-op cases in `apply`), `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTests.swift` (`MeetingHarness` gains `voices:` and a `deliverWords` helper), new `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerVoiceTests.swift`

**Steps (TDD):**
1. Write `MeetingControllerVoiceTests` (`MeetingHarness(voices: VoiceDependencies(store:embedder:log:))` over a
   `VoiceStore` and `MatchLog` in the harness's `TempDirectory`, `FakeVoiceEmbedder`; people pre-seeded; "voices"
   made of constant-amplitude system audio):
   `withTheSwitchOffNothingChanges` (no prepare, no `.voiceData`, no `voices.json`, `meeting.json` speakers without
   voice keys); `aTestCallNeitherPreparesNorRecognises`; `withoutVoiceDependenciesNothingChanges`;
   `aSpeechmaticsMeetingNeverStartsTheLocalRoute`; `startDoesNotWaitForTheModel` (prepare held → `.state(.recording)`
   arrives first); `aModelThatFailsToLoadTurnsTheRouteOffWithAnError` (`.error("Voice recognition is off for this
   meeting: the voice model could not be loaded.")`, no sidecar); `aSureMatchAppliesTheName`;
   `aSureMatchOntoAnExistingNameMergesSpeakers` (segments re-pointed, `.segmentUpdated`);
   `aSuggestionLeavesTheName` (`name` stays "Speaker 1", `matches` holds the suggestion, `meeting.json` saved);
   `aLaterSureMatchReplacesASuggestion`; `aLaterNothingLeavesTheSuggestion`; `aRenamedSpeakerIsNeverChanged`;
   `theUserIsACandidateOnlyInTheRoom`; `switchingOffMidMeetingStopsMatchingLoggingAndTheSidecar` (config updated
   while recording); `aRevisionMovesTheVectorsToTheNewKey`; `theSidecarIsWrittenAtStopWithVectorsNeverAudio`
   (route local, model `wespeaker_v2`, one entry per key plus `"user"`, 0600, `.voiceData(active: true, keys:)`);
   `aFailedSidecarWriteEmitsAnError` (`voices.json` pre-created as a folder); `eachMatchIsLogged`;
   `logsCarryKeysAndScoresNeverNamesOrVectors` (`CapturingLogSink`).
   Expected initial failure: compile errors `extra argument 'voices' in call` (`MeetingDependencies`) and `type
   'MeetingEvent' has no member 'voiceData'`.
2. Run `swift test --filter MeetingControllerVoiceTests` — confirm; add `VoiceDependencies`, the defaulted
   `MeetingDependencies.voices`, `.notice(String)` and `.voiceData(active:keys:)` (and their `break` cases in
   `MeetingWindowModel.apply`, the only exhaustive switch over `MeetingEvent`), and the harness parameter; re-run —
   assertion failures (no names applied, no sidecar, no log lines).
3. Implement. **Behaviour-preserving refactor first, inside the stage:** extract `rename(speaker:to:)`'s segment
   re-pointing, persist, save and emit into `applyMerge(_:)` and re-run `MeetingControllerEditingTests` green before
   the voice code uses it. Then `MeetingVoiceRoute` (`@MainActor final class`, one per meeting: route kind, buffers,
   recogniser, decision task, settings snapshot) and the controller hooks: `start` (R2 activation, `VoiceBuffers`
   into `MeetingAudioPath`, model prepared in a task, `.voiceData(active: true, keys: [])`), `add` (after store and
   emit, `ingest` each attributed segment with a label; remote user segments feed `"user"`), the decision consumer
   (re-read the switch, drop when off, not default-named, linked, the user, or already standing; `registry.apply` +
   `applyMerge` or `registry.suggest`; save; emit `.speakers`; `MatchLog.append`; `Log.voice` line per design
   §5), `revise` (moves to the recogniser), `stop` (after the session drain and before the last `saveMeeting`:
   `finish()` the recogniser and, if the switch is still on, write the sidecar from `voices()`; emit
   `.voiceData(active: true, keys:)`).
4. Focused suite — pass. Core suite (every existing controller suite green with `voices: nil`). App suite. App build.

**Definition of done:** R2/R3/R5/R7–R9/R14/R16/R21/R25 hold for the local route on fakes; a meeting without the route writes exactly today's files; no log line carries a name, vector or text.

**Risks specific to this stage:** asynchronous decisions make tests order-sensitive. Mitigation: tests wait on events (`waitFor`) and `recogniser.finish()`, never on time; the suite has `.timeLimit(.minutes(1))`.

### Stage 16 — Controller: accept, dismiss, reject and learn
**Goal:** Accept, Dismiss and "Not <name>" work live and on a stored meeting; a rename links the speaker to a person and recomputes that meeting's sample for the previous and the new person; the user's microphone voice is learned at Stop; `lastHeard` is set; a stored meeting learns from its sidecar.
**Design references:** §3 R15, R17, R18, R19, R20, R22, R23; §5 Interfaces (`acceptSuggestion`, `dismissSuggestion`, `rejectMatch`); §5 Control flow (Accept / Dismiss / Not; Rename, including Edit; Link; Stop; Open a stored meeting); §5 Failure cases (rename to the same name; rename before enough speech; quit mid-meeting); §5 Testing (`MeetingController`)
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`, `…/MWMeetingPipeline/MeetingVoiceRoute.swift`, new `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerVoiceLearningTests.swift`

**Steps (TDD):**
1. Write tests: `acceptNamesLinksAndLearns` (store holds this meeting's sample for the person; log `accepted`; no
   merge prompt involved); `acceptOntoAnExistingSpeakerMerges`; `dismissReturnsToSpeakerNAndNeverOffersThatPersonAgain`;
   `notOnASoleKeyReturnsTheVoiceToSpeakerN`; `notOnOneOfSeveralKeysMovesItsUnpinnedSegmentsToANewSpeaker`;
   `renameLinksAndLearns`; `renameOntoAPeopleNameIsThatPerson`; `renameToSpeakerNNeverCreatesAPersonAndClearsTheLink`;
   `renameAwayFromASuggestionRejectsItsPersonAndLogsRenamed`; `nothingIsLearnedWithTheSwitchOff`;
   `anAppliedNameTeachesNothing`; `aRenameBeforeEnoughSpeechLearnsAtStop`; `relinkingRemovesThePreviousPersonsSample`;
   `theUsersMicrophoneVoiceIsLearnedAtStopInARemoteMeeting` (created once, `isUser`, named after the meeting's user
   name); `lessThanTheMinimumSpeechTeachesNoUserVoice`; `renamingASpeakerToTheUserInTheRoomTeachesTheUser`;
   `lastHeardIsSetForLinkedAndAppliedPeopleAtStop`; `aStoredMeetingEmitsItsVoiceDataAndLearnsFromItsSidecar`;
   `aStoredMeetingWithoutASidecarLearnsNothing`; `actionsOnAStoredMeetingPersist`.
   Expected initial failure: compile error `value of type 'MeetingController' has no member 'acceptSuggestion'`.
2. Run `swift test --filter MeetingControllerVoiceLearningTests` — confirm; add the three methods as no-ops; re-run —
   assertion failures (names unchanged, store empty, no user person).
3. Implement: the three actions (registry call, re-point segments on a merge or detach — a detach moves the segments
   whose session and label form the key, whose speaker is the old one and which are not pinned — persist, save, emit,
   log); `rename(speaker:to:)` keeps today's behaviour and then, with the switch on and the name not `^Speaker \d+$`,
   `VoiceStore.findOrCreate` (or the user's person when the survivor is the user) and `registry.link`, else clears
   `person` and matches; the link step recomputing each affected person's sample from the recogniser's (live) or the
   sidecar's (stored) per-key voices through `VoiceStore`; Stop linking the user's label to the user's person, setting
   `lastHeard`; `open` reading the sidecar and emitting `.voiceData(active: false, keys:)`. Store and log failures are
   logged and never stop the meeting.
4. Focused suite — pass. Core suite. App build.

**Definition of done:** R15/R17–R20/R22 hold for the local route, live and stored; only confirmed links and the user's own voice teach.

**Risks specific to this stage:** None beyond Stage 15's.

### Stage 17 — Controller: the Speechmatics route
**Goal:** with the Speechmatics switch on at Start of a Speechmatics meeting, every session opens with the tier's enrolment and the current sensitivity, `mw:` labels of known people are suggested or applied by trust, `SpeakersResult` identifiers are kept per key and learned on a link, a live link asks for speakers, ignored identifiers are dropped with one notice, and the sidecar records identifiers.
**Design references:** §3 R2, R3, R10, R11, R12, R13, R19, R20, R21, R27; §5 Control flow (Start: Speechmatics; Segment arrives, Speechmatics; Link; SpeakersResult; Identifier ignored; Stop); §5 Failure cases (session lost before a `SpeakersResult`; unparsed warning; switch turned off); §5 Testing (`MeetingController`: inactive route leaves the wire unchanged)
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`, `…/MWMeetingPipeline/MeetingVoiceRoute.swift`, new `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerSpeechmaticsVoiceTests.swift`

**Steps (TDD):**
1. Write tests: `withTheSwitchOffStartRecognitionIsUnchanged` (`engines.calls[0].voices == nil`);
   `theTiersPeopleAreEnrolledNewestHeardFirst` (Standard identifiers enrolled, an Enhanced-only person not;
   sensitivity from config); `theEnrolmentIsRebuiltAtEverySessionOpen` (an identifier learned mid-meeting and a
   sensitivity change both appear in the reconnect's call); `aKnownLabelIsSuggestedUntilTrusted`;
   `aTrustedPersonIsApplied`; `anUnknownMwLabelIsAnOrdinarySpeaker`; `speakersResultStoresIdentifiersPerKey`;
   `aLiveLinkRequestsSpeakersAndLearnsTheIdentifier` (engine `commands == [.requestSpeakers]`; after the result the
   person holds it for the tier and is trusted); `acceptLearnsTheIdentifierOfTheKeyWithTheMostSpeech`;
   `notOnASpeechmaticsMatchResetsTrust`; `anIgnoredIdentifierIsDroppedAndNoticedOnce` (two warnings → one
   `.notice("Speechmatics ignored some remembered voices. Rename those speakers to learn them again.")`; the next
   session's enrolment lacks it); `anUnparsedWarningOnlyNotices`; `theGateBoundLabelTeachesTheUserAtStop`;
   `theSidecarRecordsIdentifiersNeverAudio` (route speechmatics, model standard, seconds per key);
   `switchedOffMidMeetingTheNextSessionEnrolsNoOneAndMwLabelsStaySpeakerN`;
   `logsNeverCarryIdentifiersOrNames`.
   Expected initial failure: every symbol exists (Stages 11–16), so the first red is assertion failures:
   `calls[0].voices` nil with the switch on, no match on an `mw:` label, no `.notice`.
2. Run `swift test --filter MeetingControllerSpeechmaticsVoiceTests` — confirm those assertion failures.
3. Implement: at Start build the enrolment box (`OSAllocatedUnfairLock<VoiceSessionConfig?>`, nil when the switch
   is off) from `VoiceStore` and `SpeechmaticsEnrolment` for `engine.providerModel`, refreshed from the config the
   ticker already loads each second and after every store change, and hand `SessionSupervisor(voices: { box })`;
   handle `.speakers` (identifiers per `"<session>:<label>"`, first identifier per label; recompute linked
   people's identifiers) and `.identifierIgnored` (`dropIdentifier`, rebuild, `Log.voice` count, notice once);
   decide `mw:` labels on a key's first segment through the same suggest/apply path and drop gate as Stage 15; track
   each key's speech seconds with `VoiceWindow.speechSeconds`; on a live link call `supervisor.requestSpeakers()`;
   "Not <name>" sets `speechmaticsTrusted` false; Stop writes the Speechmatics sidecar and links the user's
   gate-bound label.
4. Focused suite — pass. Core suite. App build.

**Definition of done:** R10–R13 and R19/R20's Speechmatics parts hold on fakes; only opaque `mw:` labels and stored identifiers are sent (R27); with the switch off the wire is today's.

**Risks specific to this stage:** None beyond Stage 15's.

### Phase E — Surfaces

### Stage 18 — Transcript: provisional names and actions
**Goal:** the transcript shows a suggestion as a provisional name with Accept / Edit / Dismiss, an applied name with a hover "Not <name>", the rename popover's remembered-voice line, and the Speechmatics notice; the coordinator routes the three actions to the controller. The app still passes no `VoiceDependencies` (Stage 20 does).
**Category:** hybrid — TDD for `MeetingWindowModel` and `MeetingCoordinator`; **platform-only/UI wiring remainder** for `TranscriptView`, `LivePage`, `ProvisionalName` and the quiet-action pill, verified by the app build and the manual check in step 4 on a hand-seeded stored meeting.
**Design references:** §3 R13, R14, R15, R22, R25; §5 Interfaces (App: `MeetingControlling`, `MeetingActions`, `MeetingWindowModel.nameState` / `learnsVoice`); §5 UI surfaces (Transcript); §5 Design language (decisions 74, 76); `DESIGN.md` (Provisional name, quiet pill, Status line); mockup `mockups/mockup-v8-provisional-name.html`; §5 Testing (App models)
**Touches:** `App/Meeting/MeetingWindowModel.swift`, `App/Meeting/MeetingCoordinator.swift`, `App/Meeting/TranscriptView.swift`, `App/Meeting/LivePage.swift`, new `App/Design/ProvisionalName.swift`, `App/Design/PillButtonStyle.swift`, `AppTests/MeetingWindowModelTests.swift`, `AppTests/MeetingCoordinatorTests.swift`, `AppTests/TestCallSessionTests.swift`

**Steps (TDD):**
1. Write tests:
   - `MeetingWindowModelTests`: `aSuggestedMatchShowsAsSuggested` (a paragraph whose first segment's session and
     label form the match's key → `.suggested(match)`); `anAppliedMatchShowsAsApplied`; `aParagraphWithoutAMatchIsPlain`;
     `aTestCallIsAlwaysPlain`; `learnsVoiceWhileLiveWithTheRouteOn`; `afterStopLearnsVoiceOnlyForKeysWithVoiceData`;
     `neverLearnsWithTheRouteOff`; `theNoticeIsKeptForTheLiveHeader`; `editOfASuggestionTitlesThePopoverNameSpeakerN`
     ("Name Speaker 2 (every segment)", the suggested name as the draft); `theRejectLabelIsNotName` ("Not Bob").
   - `MeetingCoordinatorTests`: `acceptDismissAndRejectReachTheController` (actions → the stub's recorded keys).
   Expected initial failure: compile errors `value of type 'MeetingWindowModel' has no member 'nameState'` and
   `type 'MeetingControlling' … has no member 'acceptSuggestion'` (the stubs).
2. Run `-only-testing:AppTests/MeetingWindowModelTests -only-testing:AppTests/MeetingCoordinatorTests` — confirm;
   add the empty API (`nameState` → `.plain`, `learnsVoice` → false, the three protocol methods on both
   `StubController`s in `MeetingCoordinatorTests.swift` and `TestCallSessionTests.swift`, `MeetingActions`' three
   closures **defaulted** so `MainWindowModelTests`' construction is untouched); re-run — assertion failures.
3. Implement: `MeetingWindowModel` (`NameState`, `nameState(of:)`, `learnsVoice(speaker:)` over an injected
   `voiceRouteEnabled` closure, `apply` storing `.notice` and `.voiceData` in place of Stage 15's `break`s,
   `renameTitle` for a suggestion); `MeetingControlling` and `MeetingActions` gain the three actions;
   `MeetingCoordinator.Dependencies.voiceRouteEnabled: @MainActor (MeetingEngine) -> Bool` (defaulted false) passed
   into every model; `ProvisionalName` (speaker colour, 13 px semibold, "?" and a 1.5 px dashed underline,
   `Speaker N` in grey 12 px beside it); `PillButtonStyle` gains the quiet action label (secondary, accent on hover
   or keyboard focus, recording when destructive); `TranscriptView` (pills right-aligned on every paragraph of the
   speaker, moving under the name below 470 px; a click on the provisional name or Edit opens the popover with the
   suggested name selected and no merge prompt; "Not <name>" after the time in reserved space on hover or focus; the
   popover's waveform line "This voice will be remembered as <name>." when `learnsVoice`); `LivePage` shows the notice
   as an info `StatusLine` under the header. `AppDelegate` is untouched: `voiceRouteEnabled` keeps its false default
   until Stage 20, so no popover promises learning that cannot happen yet.
4. Focused suites — pass. Core suite. App suite. App build. **UI check without recognition:** copy any stored meeting
   folder under a new UUID, add one `matches` entry (`state: suggested`) and one `state: applied` to two speakers in
   its `meeting.json`, open it from the Meetings page, compare with `mockup-v8-provisional-name.html` in light and
   dark (provisional name, pills, the narrow-width wrap, "Not <name>" on hover and keyboard focus), use Accept, Edit,
   Dismiss and "Not <name>" (R15 on a stored meeting, R22), then delete the throwaway meeting from the Meetings page.

**Definition of done:** R14/R15/R22/R25's surfaces render as the mockup from stored `matches`; the coordinator routes the actions; a test call shows no recognition control.

**Risks specific to this stage:** None.

### Stage 19 — People: list, rename, merge
**Goal:** a tenth Settings section, People, lists everyone remembered with their routes and last-heard date, renames (refusing a taken name) and merges, and locks itself while a meeting records.
**Category:** hybrid — TDD for `PeopleModel` and the section list; **platform-only/UI wiring remainder** for `PeopleSection`, verified by build and a manual comparison with the mockup.
**Design references:** §3 R24; §5 Interfaces (App: `PeopleModel`, `SettingsModel.Section.people`); §5 UI surfaces (People); `DESIGN.md` (Settings card, Day-grouped row list, Chip, Dialog, Pill menu, quiet pill); mockup `mockups/mockup-v8-people.html`
**Touches:** new `App/Settings/PeopleModel.swift`, new `App/Settings/PeopleSection.swift`, `App/Settings/SettingsModel.swift`, `App/Settings/SettingsPage.swift`, `App/AppDelegate.swift`, new `AppTests/PeopleModelTests.swift`, `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write tests:
   - `PeopleModelTests` (closure dependencies, no store): `rowsAreSortedByLastHeardNewestFirst`;
     `aRowListsTheRoutesThatHoldDataAndTheLastHeardDate` ("Local model · Speechmatics Standard · last heard …");
     `theUsersRowCarriesYouAndOffersNoRenameOrMerge`; `rowsFollowTheStoresChanges`;
     `renameRefusesATakenNameWithTheMessage` ("Alice already exists. Use Merge into… instead.");
     `renameWritesThroughTheStore`; `mergeOffersTheOtherPeople`; `theMergeDialogCopy` ("Merge A into B?" / "B keeps the
     name and gets both voices. Past meetings are not changed."); `whileAMeetingRecordsEveryActionIsDisabledWithTheInfoLine`;
     `theEmptyStateCopy`; `openMeetingsSettingsSelectsMeetings`.
   - `SettingsModelTests`: the section-list guard (`allCases`) gains `.people` after `.meetings`; title "People",
     symbol `person.crop.circle`.
   Expected initial failure: compile error `cannot find 'PeopleModel' in scope`; the guard fails on the old list.
2. Run `-only-testing:AppTests/PeopleModelTests -only-testing:AppTests/SettingsModelTests` — confirm; empty model;
   re-run — assertion failures.
3. Implement `PeopleModel` (`@Observable`, `Dependencies` of closures with an inert default: `load`, `changes`,
   `rename`, `merge`, `openMeetingsSettings`; `rows`, `isRecording`, `rename`, `merge(from:into:)`, copy strings);
   `SettingsModel.Section.people` (title, symbol), `SettingsModel.people` built from `Dependencies.people`;
   `SettingsPage`'s new case; `PeopleSection` per the mockup (lead line, "Remembered voices · N" card, rows with the
   "You" chip, hover pills in reserved space, Rename popover with "Past meetings keep the old name.", Merge into…
   pill menu and Dialog, the recording info line, the empty state with the app mark and "Open Meetings Settings").
   `AppDelegate` creates the app's one `VoiceStore(directory: configDirectory)`, builds the dependencies over it
   (the People list is empty until Stage 20 lets meetings learn) and sets `isRecording` from the meeting coordinator
   in `meetingChanged`.
4. Focused suites — pass. Core suite. App suite. App build. **UI check** against `mockup-v8-people.html`.

**Definition of done:** R24's list, Rename and Merge work and lock while recording; the sidebar shows People after Meetings.

**Risks specific to this stage:** None.

### Stage 20 — Forget, and the feature on
**Goal:** Forget and Forget everyone remove the person (or everyone), their samples, their voice data in every past meeting — including meetings a session holds open — and their match-log lines, leaving transcript names as text; then the app passes `VoiceDependencies` and the route closure to every meeting, which turns recognition and learning on.
**Category:** hybrid — TDD for the controller scrub, the coordinator fan-out and `PeopleModel`'s orchestration; **platform-only/UI wiring remainder** for the Forget pills and dialogs and the `AppDelegate` wiring, verified by the app build and the design's manual acceptance in step 4.
**Design references:** §3 R2, R21, R24; §5 Interfaces (`MeetingController.scrubVoices`, `MeetingCoordinator.scrubVoices`, `VoiceDependencies`); §5 Control flow (People actions: Forget); §5 Failure cases (Forget while a stored meeting is open; the user's entry forgotten); §5 Acceptance; mockup `mockups/mockup-v8-people.html`
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`, `…/MWMeetingPipeline/MeetingVoiceRoute.swift`, new `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerVoiceScrubTests.swift`, `App/Meeting/MeetingCoordinator.swift`, `App/Settings/PeopleModel.swift`, `App/Settings/PeopleSection.swift`, `App/AppDelegate.swift`, `AppTests/PeopleModelTests.swift`, `AppTests/MeetingCoordinatorTests.swift`, `AppTests/TestCallSessionTests.swift`

**Steps (TDD):**
1. Write tests:
   - `MeetingControllerVoiceScrubTests`: `scrubbingAPersonClearsTheOpenMeetingAndItsSidecar` (`.speakers` and
     `.voiceData` emitted, names unchanged, `meeting.json` saved); `scrubbingEveryoneDeletesTheSidecar`;
     `otherPeopleAreLeftAlone`.
   - `MeetingCoordinatorTests`: `scrubVoicesReachesEverySessionHoldingAMeetingAndReturnsTheirIds`.
   - `PeopleModelTests`: `forgetRunsStoreThenHeldMeetingsThenStoredMeetingsThenTheLog` (ids include aliases; the
     stored-meeting scrub skips the held ids); `forgetEveryoneClearsEverything`; `theForgetDialogsCopy` ("Forget
     Alice?", "Forget everyone?"); `forgetIsUnavailableWhileRecording`; `theUsersEntryCanBeForgotten`.
   Expected initial failure: compile errors `value of type 'MeetingController' has no member 'scrubVoices'` and
   `value of type 'PeopleModel' has no member 'forget'`.
2. Run `swift test --filter MeetingControllerVoiceScrubTests` and `-only-testing:AppTests/PeopleModelTests
   -only-testing:AppTests/MeetingCoordinatorTests` — confirm; empty API (and the protocol method on both stubs);
   re-run — assertion failures.
3. Implement `MeetingController.scrubVoices(people:)` with `VoiceScrubber.scrub(_:voices:people:)` (Stage 8) over
   the held meeting and its sidecar, then save, write or delete the sidecar, emit; `MeetingControlling.scrubVoices`;
   `MeetingCoordinator.scrubVoices(people:) async -> Set<UUID>` over every session holding a meeting (modelled on
   `retitle`); `PeopleModel.forget(_:)` / `forgetEveryone()` running `VoiceStore.forget` (or `forgetEveryone`), the
   coordinator scrub, `VoiceScrubber.scrub(people:skipping:)` and `MatchLog.remove(people:)` (or `removeAll`), in that
   order; `PeopleSection`'s Forget pill (red on hover), the "Forget everyone" card row with an outlined red-label
   button, and both Dialogs. `AppDelegate` wires the four closures. **Only then, last in the stage,** `AppDelegate`
   turns the feature on: `MatchLog(url: configDirectory/voice-matches.jsonl)`, the Stage 19 `VoiceStore` and the
   Stage 14 embedder passed as `voices:` to every `MeetingDependencies` in `makeMeetings`, and
   `MeetingCoordinator.Dependencies.voiceRouteEnabled` reading `self.config.voice.isEnabled(engine.voiceRoute)`.
4. Focused suites — pass. Core suite. App suite. App build. **Manual acceptance (design §5):** with the local switch
   on, record an AssemblyAI meeting and name a speaker (the popover says "This voice will be remembered as <name>.");
   in a second meeting that person is named or offered within the first minute of their speech; a summary written
   while a suggestion is pending says `Speaker N`; Accept, Edit, Dismiss and "Not <name>" behave as R15 says live and
   after Stop; a test call shows none of it; the person appears in People; Forget removes them from People and from
   both meetings' `voices.json`. Compare the Forget states with the mockup in light and dark.

**Definition of done:** R24's Forget and Forget everyone remove every trace except transcript text; open meetings are scrubbed by their own controller; with a switch on, real meetings recognise and learn; the design's acceptance passes.

**Risks specific to this stage:** None — Forget is wired before the app passes `VoiceDependencies`, inside the stage, so no commit learns voices without a way to forget them.

### Phase F — Documentation

### Stage 21 — Documentation
**Goal:** the repository's documents describe v8.
**Category:** non-TDD (config-only) — documentation only; nothing executable changes.
**Design references:** §9 (release notes), §5 Compatibility (`THIRD_PARTY_NOTICES.md`, added in Stage 3)
**Touches:** `CHANGELOG.md` (`[Unreleased]` → `### Added`: the two switches and what each stores and where; that Speechmatics may split speakers differently with its switch on; that macOS 14 is unverified for the local route; People in Settings; the Credits window), `README.md` (`## Meetings`: a "Remembering voices" paragraph; `## Privacy`: voiceprints and identifiers, where they live, how to forget them), `CLAUDE.md` (Layout/Module map: `MWVoices` row and its dependencies; `MWMeetingPipeline` gains `VoiceAudioBuffer`, `VoiceRecogniser`, `MeetingVoiceRoute` and depends on `MWVoices`; `MWTestSupport` includes it; `App/Resources` lists the model)

**Steps (non-TDD):**
1. Edit the three files.
2. Check: `grep -n "voice_local_enabled\|Remember voices\|People" README.md CHANGELOG.md` finds the new text;
   `grep -n "MWVoices" CLAUDE.md` finds the row; `project.yml` `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
   unchanged (no release in this plan).
3. Run both suites and the app build one last time — green.

**Definition of done:** the three documents match the shipped behaviour; no version bump.

**Risks specific to this stage:** None.

### Stage 22 — Dead-code cleanup
**Goal:** remove the orphans the final whole-project dead-code sweep finds that this feature introduced.
**Category:** behaviour-preserving refactor / deletion — added by `/feature-implement`'s final sweep (periphery 3.8.0 against the run's baseline).
**Touches:** `App/Settings/PeopleModel.swift`

**Steps:** remove `PeopleModel`'s unused `import MWMeetings`; keep `VoiceStore`'s encoded `schema` field (a serialization target); app suite and build green.

**Definition of done:** periphery reports no new finding beyond serialization targets; suites green.

## Cross-cutting concerns

- **Security** — The trust boundary is Speechmatics' messages: `SpeakersResult` labels and identifiers are stored as
  opaque strings and sent back only to Speechmatics; an `mw:` label acts only when it parses to a known person's UUID
  (Stages 6, 17); warning text is parsed with one anchored pattern and never logged or shown (Stage 11). Names never
  leave the Mac: enrolment labels are `mw:<uuid>` (Stage 6). Voice vectors and identifiers are biometric data: stored
  0600 with atomic writes (Stages 4, 7, 8), never logged (Stages 15, 17 test it), removable by Forget (Stage 20), and
  the CLI/MCP read meetings only through `MeetingReading`, which exposes neither the sidecar nor the store (Stage 4
  leaves it unchanged). The model loads only from the app bundle (Stage 10) and its files are hash-checked before
  commit. No key handling changes; the live test reads its key from the environment and never prints it (Stage 12).
  People names are user input shown as plain text and never interpolated into a path or prompt. **Ordering:** the app
  passes `VoiceDependencies` to meetings only at the end of Stage 20, after Forget is wired in the same stage, so no
  commit learns voices without a way to forget them.
- **Performance** — The capture tick does one locked append per buffer (Stage 2); two 7.7 MB buffers in a remote
  meeting. Embedding (≈ 21 ms per window) runs on the recogniser actor's queue, never on the capture thread or the
  main actor (Stage 13 tests it); audio is cut at ingest so the queue never waits on the rolling buffer. Matching is
  one cosine per stored sample (≤ 8 per person). Store, sidecar and log writes happen on user actions and at Stop,
  never per segment (Stages 7, 15, 16). `StartRecognition` grows ≈ 1.6 KB per enrolled person, ≤ 50. Forget scans
  each `meeting.json` once, off the main actor (Stage 8).
- **Observability** — `Log.voice` (Stage 5) carries keys, scores, seconds and the first 8 characters of a person id:
  `match 1:A sure 0.83 (next 0.31) after 22 s`, `model loaded in 0.21 s`, `speechmatics dropped 2 identifiers
  (standard)`, `sidecar written: 6 keys`; an embedding failure warns once per meeting (Stage 13). The match log is the
  durable record (Stage 8). Nothing is alertable.
- **Compatibility / migration** — No migration. The eight config keys take defaults (Stage 1); `SpeakerLabel` decodes
  old files and encodes exactly today's bytes without voice data (Stage 4); `Meeting.schema` stays 1. Every
  `makeMeeting` implementer and caller changes together in Stage 12; every exhaustive switch over a widened enum
  changes in the stage that widens it (Stage 11: both `WebSocketEngine.apply` switches; Stage 12:
  `MeetingController.handle`; Stage 15: `MeetingWindowModel.apply`; Stage 19: `SettingsPage` and the
  `Section.allCases` guard). Defaulted parameters keep the 41 `SpeakerLabel(` constructions, the
  `MeetingDependencies` and `SessionSupervisor` call sites, and `MainWindowModelTests`' `MeetingActions` untouched.
  Between stages meetings behave as today until Stage 20 (see the coverage map's note).

## Verification

Once Stage 21 has landed:

1. `cd Packages/MiniWhisperCore && swift test` — **18** runs, all `✔ … passed`, 1067 + the new tests.
2. The app test command — `✔ Test run with … passed`, `** TEST SUCCEEDED **`, 467 + the new tests.
3. `swiftc -O scripts/voice_model_check.swift -o "$TMPDIR/vmc" && "$TMPDIR/vmc" App/Resources/wespeaker_v2.mlmodelc AppTests/Fixtures/*.wav` exits 0; after the next push, the `voice-model` job on `macos-15` is green.
4. The design's manual acceptance (Stage 20 step 4): name a speaker in an AssemblyAI meeting with the
   local switch on; in a second meeting that person is named or offered within the first minute of their speech; a
   summary written while a suggestion is pending says `Speaker N`; Forget removes them from People and from both
   meetings' `voices.json`.
5. Spot checks: with both switches off, a meeting writes no `voices.json` and `meeting.json` speakers carry no voice
   keys (R2); a Speechmatics meeting with its switch on enrols, and after a rename the person appears in People with
   "Speechmatics Standard" (R10–R12); a test call shows no provisional name or pill (R25); `grep` of the unified log
   (`log show --predicate 'subsystem == "com.ips.mini-whisper" && category == "voice"'`) shows no name (R27).
6. Opt-in: `MW_INTEGRATION=1 SPEECHMATICS_API_KEY=… swift test --filter SpeechmaticsVoiceLiveTests` (the user's key,
   set in their own shell).
7. Follow-up outside the plan: `/design-language-update` (record mode) turns decisions 74–76 from `pending v8` to
   active in `DESIGN.md` and the specimen; that skill is the only writer of `DESIGN.md`.

## Risks and open issues

1. **Asynchronous decisions make controller tests racy.** Mitigation: every test waits on events or
   `VoiceRecogniser.finish()`, never on time; the new suites carry `.timeLimit(.minutes(1))`; the fake embedder is
   deterministic.
2. **Two app test hosts at once on one Mac are unproven** (v7 *Risks* 5). Mitigation: at most one app-test stage per
   batch (Stage 3 in batch 1, Stage 14 in batch 8); every other stage in those batches runs only the core suite and
   the app build.
3. **A release cut before Stage 21** would ship switches that do nothing (Stages 14–19) or a feature without release
   notes (Stage 20). Mitigation: no tag until Stage 21 has landed; Stage 21 checks the version is untouched.
4. **The `macos-15` CI job is proven only on push**, and the runner's Xcode is older. Mitigation: the script is plain
   top-level Swift in the probe's shape, compiled and run locally in Stage 10; a red first run is fixed in a follow-up
   commit without blocking `build` (the job is standalone).
5. **The model download depends on Hugging Face.** Mitigation: pinned revision `7eab74f…` and the five recorded
   hashes; a mismatch stops the stage rather than committing other bytes.
6. **The stock `Slider` may not draw the mockup's hollow thumb** for a Custom value. Mitigation: try the stock
   control's tint/appearance first; if it cannot, keep the stock thumb, show the "Custom · set in Advanced" caption
   and "Reset to Balanced", and record the difference under *Deviations from plan* during implementation.
7. **Hand-written Speechmatics fixtures could miss real fields.** Mitigation: the adapter reads only the fields it
   needs and ignores the rest; Stage 12's opt-in live test runs the real wire.
8. **`MeetingController` grows past 1,000 lines.** Mitigation: per-meeting voice state and logic live in
   `MeetingVoiceRoute`; the controller keeps only its hooks, registry calls and persistence.
9. **Signing and notarization with a folder resource.** The `.mlmodelc` holds no Mach-O code, so it is sealed as
   resources and the workflow's nested-code loop never touches it. Mitigation: the first signed release run's
   `codesign --verify` / `spctl` steps (CLAUDE.md) cover it.

## Planning decisions taken

1. **Stage order and phases:** foundations, then the `MWVoices` parts, the bundled model, the streaming wire, the
   recogniser and Settings, then the controller in three steps (local, learning, Speechmatics), then the surfaces;
   the app passes `VoiceDependencies` to meetings only at the end of Stage 20, after Forget, so every earlier stage
   is dormant and no commit learns a voice it cannot forget (the *Security issues* ordering).
2. **One `Package.swift` edit (Stage 5):** the `MWVoices` target, product and test target, plus `MWVoices` in
   `MWMeetingPipeline`'s and `MWTestSupport`'s dependencies at once, so the later parallel stages share no
   registration point. Internal target edges, no third-party package and no `Package.resolved` change.
3. **One `project.yml` edit (Stage 10):** the model's folder reference and the app target's `MWVoices` product
   together; the folder-reference form was proven to copy the `.mlmodelc` intact (*Development strategy*).
4. **Design §5 Compatibility under-counted `makeMeeting`'s blast radius (design corrected in place):** besides
   `EngineFactory` and `FakeMeetingEngineProvider`, `AnnouncingProvider` in `SessionSupervisorTests.swift` implements
   it and `EngineFactoryTests` and `MeetingEngineLiveTests` call it; Stage 12 updates the three implementers, the two
   test callers and `SessionSupervisor.install` together.
5. **Design §4 anchor drift (corrected in place):** About is `App/AboutView.swift:4`, not `:6`.
6. **Defaulted parameters bound the blast radius** without changing the design's interfaces: `SpeakerLabel`'s three
   fields (41 constructions untouched), `MeetingDependencies.voices`, `SessionSupervisor(voices:)`,
   `MeetingAudioPath(voices:)`, `MeetingActions`' three closures, `MeetingCoordinator.Dependencies.voiceRouteEnabled`,
   `SettingsModel.Dependencies.prepareVoiceModel` / `people`.
7. **`MeetingVoiceRoute`** (internal, `@MainActor`, one per meeting) holds the route's state — buffers, recogniser,
   enrolment box, per-key identifiers and seconds, the notice flag — so `MeetingController` stays readable; the
   controller keeps the registry, persistence and events, as design §5 assigns them.
8. **`VoiceRecogniser` queue and delivery:** `ingest` is nonisolated and cuts the audio synchronously, then enqueues
   the embedding on one internal consumer; decisions arrive on an `AsyncStream` the controller reads on the main
   actor; `finish()` drains the queue for Stop. The controller passes an eligibility snapshot (`Context`) at ingest and
   re-checks it before applying, which is design §5's "a decision is dropped when…".
9. **The drop gate applies to both routes:** an `mw:` decision is dropped on the same conditions as a local one
   (switch off, speaker no longer default-named, linked, the user, or the match already standing), the reading R16
   requires.
10. **Settings reach the supervisor without an await:** the Speechmatics enrolment box is refreshed from the config
    the ticker already loads every second and after each store change, so `install` reads the latest sensitivity
    under its lock; the box is nil once the switch is off, so the next session enrols no one (design §5's "Switch
    turned off mid-meeting" row).
11. **Speechmatics key seconds** are each key's merged, padded word time (`VoiceWindow.speechSeconds`), so "the key
    with the most speech" and the sidecar's `seconds` use the same measure on both routes.
12. **The first identifier of each `SpeakersResult` label** is kept per key; the design shows one per label.
13. **`rename`'s merge carries the voice fields:** the survivor keeps its `person` (or takes the absorbed speaker's
    when it has none) and takes the union of matches (keyed by the moved provider keys) and rejections.
14. **`^Speaker \d+$` is enforced in `VoiceStore.findOrCreate`** (returns nil), so every caller gets R17's rule.
15. **`VoiceSettings.Field`** (`sure, suggestion, margin, minimumSpeech, buffer, sensitivity`) names the Advanced
    sliders, so `SettingsModel.setVoice(_:for:)` has a typed second argument and the clamps live in core.
16. **Tier key:** a person's Speechmatics identifiers and the sidecar's `model` are keyed by
    `MeetingEngine.providerModel` (`standard` / `enhanced`), the strings the design's JSON shows.
17. **Speechmatics fixtures are written by hand** from the shapes recorded in design §4
    with placeholder identifiers; the design's probe printed its captures and saved none.
18. **Scrubber fixtures are built through `MeetingStore` in a `TempDirectory`**, so `MWVoicesTests` needs no
    `Fixtures` resource and no further `Package.swift` edit.
19. **The model is fetched from the pinned Hugging Face revision and hash-checked**; the fixture clips are generated
    with the recorded `say` commands and sentences, which the design probe scored before drafting.
20. **AppTests read fixture clips through `Bundle(for:)` on a private anchor class**: xcodegen puts them in the test
    bundle, not `Bundle.main` (proven), and no AppTests suite read a test-bundle resource before.
21. **The `voice-model` CI job is standalone**, not in `build`'s `needs`: a load failure on macOS 15 disables the
    switch with a reason rather than breaking the app (design §7), so it should flag, not block releases.
22. **One shared `CoreMLVoiceEmbedder`** is created in `AppDelegate` (Stage 14) and reused by every meeting
    (Stage 20), so the model loads once per launch; likewise one `VoiceStore` (Stage 19) serves People and meetings.
23. **`MeetingEvent.notice` / `.voiceData` land in Stage 15 with `break` cases** in `MeetingWindowModel.apply`, the one
    exhaustive switch, replaced by real handling in Stage 18 (v7 decision 7's pattern).
24. **People split in two stages** (list, rename, merge in 19; Forget in 20) for review size; Forget's controller
    scrub reuses Stage 8's pure `VoiceScrubber.scrub(_:voices:people:)` rather than a second implementation.
25. **`PeopleModel` takes closure dependencies with an inert default** and is owned by `SettingsModel`, so
    `SettingsModelTests` constructions stay as they are and App suites need no store; `isRecording` is set by
    `AppDelegate` from the coordinator on every meeting change.
26. **The quiet action pill is a `PillButtonStyle` option**, not a new style, since DESIGN.md lists Quiet as a
    variant of the one pill button and decision 74 only changes its label colour on hover or focus.
27. **Documentation stage** also updates `README.md` (Meetings, Privacy) and `CLAUDE.md`'s module map beyond the
    release notes §9 names, as v7's Stage 9 did.
28. **Batch cut:** see the schedule; the Speechmatics wire, the stored shapes, the module scaffold, the model and the
    session plumbing are serial by category; the four pure `MWVoices`/registry stages form one parallel batch, the
    recogniser runs beside Settings, and each batch with an app-test stage has exactly one.

## Deviations from the design

None — plan matches design v8 exactly.

## Execution schedule

Batches run in order; a batch starts only when the previous one has fully landed. Stages inside a *parallel* batch are independent and may be built concurrently; a *serial* batch holds one stage. `/feature-implement` follows this table and demotes any batch it cannot verify to serial.

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1, Stage 2, Stage 3 | parallel | **Disjoint files:** `MWConfig/VoiceSettings.swift` (new), `Config.swift` + two `MWConfigTests` files; `MWMeetingPipeline/VoiceAudioBuffer.swift` (new), `MeetingAudioPath.swift` + two new `MWMeetingPipelineTests` files; eight `App/`/`AppTests/` files + `THIRD_PARTY_NOTICES.md`. **No symbol or string-keyed dependency:** `VoiceSettings` / the `voice_*` keys, `VoiceAudioBuffer` / `VoiceBuffers`, and `Credits` are each introduced by one stage and read by neither other (the core package cannot see app code). **No shared registration point:** `Package.swift` and `project.yml` untouched, new files land in existing target folders, no exhaustive switch or enumerated registry edited (`SmallWindowsTests` is Stage 3's alone). **Same base:** each is green against `6c2e390` alone. **Category:** feature stages; `MeetingAudioPath.init` gains a defaulted parameter with one internal call site, not a shared signature. **Security ordering:** none involved. **No shared test resource:** own worktrees, `.build`/`.dd` and `TempDirectory`s; only Stage 3 runs the app test host |
| 2 | Stage 4 | serial | Changes the shared `SpeakerLabel` (init and `Codable`, 41 constructions) — category exclusion |
| 3 | Stage 5 | serial | Scaffolds the new module and edits `Package.swift` — category exclusion |
| 4 | Stage 6, Stage 7, Stage 8, Stage 9 | parallel | **Disjoint files:** `VoiceWindow.swift` + `SpeechmaticsEnrolment.swift` + 2 tests; `VoiceStore.swift` + 1 test; `MatchLog.swift` + `VoiceScrubber.swift` + 2 tests; `SpeakerRegistry.swift` + `SpeakerRegistryTests.swift`. **No symbol or string-keyed dependency:** each consumes only Stages 1, 4 and 5 (`Person`, `SampleSet`, `VoiceVector`, `NameMatch`, `MeetingStore` sidecar, `VoiceRoute`); none uses another's new type (`VoiceStore` is not used by the scrubber, which takes ids; the registry uses no `MWVoices` type). **No shared registration point:** no `Package.swift` edit (Stage 5 made every edge), new files in existing target folders, no shared fixture (scrubber meetings are built in a `TempDirectory`). **Same base:** each green against batch 3 alone. **Category:** pure feature stages; the registry change is additive methods plus `rename` carrying new fields, no signature change. **Security ordering:** none. **No shared test resource:** core suites only, own worktrees |
| 5 | Stage 10 | serial | Adds the bundled third-party model, edits `project.yml` and adds a CI job — category exclusion (dependency) |
| 6 | Stage 11 | serial | Adds variants to `AdapterEmitter.Emission` and widens `StreamingEngine` / `TranscriptSink` / `EngineAdapter` — shared signatures (category exclusion) |
| 7 | Stage 12 | serial | Changes the shared `makeMeeting` signature and `SupervisorEvent` — category exclusion; consumes Stage 11 |
| 8 | Stage 13, Stage 14 | parallel | **Disjoint files:** `MWMeetingPipeline/VoiceRecogniser.swift` + its test vs `App/Settings/SettingsModel.swift`, `MeetingsSection.swift`, `App/AppDelegate.swift`, `AppTests/SettingsModelTests.swift`. **No symbol or string-keyed dependency:** the recogniser uses Stages 2, 5, 6 and 1; Settings uses Stages 1 and 10; neither uses the other's symbols or keys. **No shared registration point:** neither edits `Package.swift` or `project.yml`; no exhaustive switch shared. **Same base:** both green against batch 7. **Category:** feature stages. **Security ordering:** nothing turns on (no `VoiceDependencies` passed until Stage 20). **No shared test resource:** only Stage 14 runs the app test host |
| 9 | Stage 15 | serial | Adds `MeetingEvent` variants (with the app's exhaustive switch) and `MeetingDependencies.voices`; consumes Stages 2, 4, 7–9, 13 |
| 10 | Stage 16 | serial | Edits `MeetingController.swift` and `MeetingVoiceRoute.swift`, which Stage 15 creates and Stage 17 extends |
| 11 | Stage 17 | serial | Same two files; consumes Stages 11, 12, 6, 7, 16 |
| 12 | Stage 18 | serial | Widens the shared `MeetingControlling` protocol and `MeetingActions` (category exclusion) |
| 13 | Stage 19 | serial | Adds a `SettingsModel.Section` variant (exhaustive `SettingsPage` switch, `allCases` guard) — category exclusion |
| 14 | Stage 20 | serial | Widens `MeetingControlling` again and edits Stage 19's `PeopleModel`; security ordering: it wires Forget before it turns learning on, so it can share a batch with nothing that would land learning first |
| 15 | Stage 21 | serial | Documents what every earlier stage introduces |
| 16 | Stage 22 | serial | Added by the final dead-code sweep; runs after everything it scans |

**Critical path:** Stage 4 → Stage 5 → Stage 6 → Stage 13 → Stage 15 → Stage 16 → Stage 17 → Stage 18 → Stage 19 → Stage 20 → Stage 21 by dependency (11 of 21 stages); by schedule 15 batches, since Stages 10, 11 and 12 are serialised by category, not by dependency.

## Deviations from plan

1. **Stage 3 (parallel, batch 1):** the Credits licence line uses `ViewThatFits`, so at 460 pt WeSpeaker's "Open Licence…" wraps to its own line, as the mockup's CSS does; the unfolded licence box is 150 pt (the mockup's `max-height`), the one size outside the `DS` tokens; the body reuses `smallWindowBody`, so its bottom inset is 18 pt, not the mockup's 20 px. The three quiet pills keep today's quiet style until Stage 18 applies decision 74.
2. **Stage 6 (parallel, batch 4):** the 1.5 s minimum is compared in whole samples (≥ 24,000); padded spans are not clamped at 0 s, so a word at the start of a meeting reads from −0.05 s and the buffer returns what it holds.
3. **Stage 7 (parallel, batch 4):** `rename` also refuses a blank or `^Speaker \d+$` name (`VoiceStoreError.invalidName`); `forgetEveryone` also deletes `voices.json.bak`; `merge` keeps the later `lastHeard`; `forget` of an unknown id returns `[id]`; `user(named:)` never promotes an existing non-user person of the same name. The atomic 0600 write is a private copy of `MeetingStore.write` (now three private copies with `MatchLog`'s); its temp file is created at the default mode and then set to 0600.
4. **Stage 8 (parallel, batch 4):** a scrub of the user's person also removes the sidecar's `"user"` key (R24); an unreadable sidecar is deleted only where it could hold a forgotten voice, an unreadable `meeting.json` is logged and skipped; `MatchLog.remove(people:)` also drops undecodable lines; `MatchLog.Entry`'s `person`, `score`, `runnerUp` and `seconds` are optional. `VoiceScrubber` reads each meeting with `MeetingStore.load` (segments included).
5. **Stage 9 (parallel, batch 4):** `detach`'s first branch also requires "not the user"; `apply(_:userName:)` takes `String?`, non-nil only for the user's person; `suggest`/`apply` set the stored state; `accept`/`dismiss` act only on a suggestion and `detach` only on an applied match; `dismiss` returns the removed match; `link` takes `person: UUID?` so clearing a link uses the same call. `bindToUser` leaves a match for the moved key on the previous speaker (not covered by the design; left for Stage 15).
6. **Stage 10 (serial):** `CoreMLVoiceEmbedder` keeps the outcome of its one load, so a missing URL or a model that will not load throws `.modelUnavailable` at once from then on, and it serialises predictions under the same lock (synchronous predictions on one `MLModel` are not documented as thread-safe). `input(_:)` returns the `MLFeatureProvider`; the output is read by a public `vector(from:)`, which rejects an output that is not `[3, 256]` as `.modelUnavailable` (extra test `anOutputOfAnotherShapeIsRejected`). `scripts/voice_model_check.swift` takes a clip's voice from its file name before the last `-` and exits 2 on a usage error.
7. **Stage 11 (serial):** R2's "byte-identical" is pinned as exact JSON equality: `AdapterJSON` encodes without sorted keys and Swift orders a dictionary's keys per instance, so two builds of today's `StartRecognition` already differ in bytes (6 distinct encodings in 200 builds); `startRecognitionIsUnchangedWithoutVoices` compares the parsed message with today's shape for both tiers. A `SpeakersResult` entry is kept only with a string label and at least one string identifier (extra test `aMalformedSpeakersResultKeepsOnlyWellFormedEntries`); a `speaker_id` warning names an enrolled speaker only when its identifier index is 1 (one identifier per speaker) and its speaker index is in range; `voices` applies to diarized sessions only. `WebSocketEngine` sends a command without flushing audio held back for a minimum chunk (only AssemblyAI has a minimum, and it encodes no command); audio and commands share one send-or-fail helper.
8. **Stage 12 (serial):** `.speakers` and `.identifierIgnored` are emitted for any session, current or retired, and do not count as a delivery (no `.connected`, no backoff reset). `AnnouncingEngine` in `SessionSupervisorTests.swift` forwards `send` to the fake it wraps; `speakersAndIgnoredIdentifiersBecomeEvents` carries `.timeLimit(.minutes(1))`, since without the events it would wait forever.
9. **Stage 13 (parallel, batch 8):** `revise` takes `contexts: [String: Context]` (one revision can touch several keys); a key missing from the map uses its latest context, a key never given one is not evaluated. Evaluation runs after each new vector, so a two-window segment can yield two decisions. An embedding error skips the whole segment. `finish()` is terminal: it ends `decisions` and later calls are dropped. `Decision.Outcome` has only `suggestion` and `sure`; `Decision.person` is the full `Person`. The test file keeps two private embedders because `FakeVoiceEmbedder` can neither fail per window nor hold `embed`.
10. **Stage 14 (parallel, batch 8):** a Custom value keeps the stock thumb with the track tinted `color.line` (*Risks* 6); a blocked switch keeps its disclosure and adds the reason underneath; the model failure outranks the missing-key hint; "Reset to Balanced" sits at the foot of Advanced and shows whenever the tuning is off step 5; the Advanced sliders are continuous, stored rounded to their read-out, and every slider writes once at drag end; a Custom value places the main slider on the step with the nearest sure threshold; the Engine footnote is its own row after the tuning row.

11. **Stage 15 (serial):** `SpeakerRegistry.bindToUser` now also drops the moved key's match from the speaker it leaves (R16; tests `bindingAKeyToTheUserDropsItsMatch`, `aKeyTheGateGivesTheUserLosesItsMatch`), and `SpeakerRegistry.defaultName(_:)` is module-internal so the route's gate shares it. The drop gate also drops a person the speaker rejected since the segment was fed. A route that ends without a sidecar (the model failed to load, or the switch is off at Stop) emits `.voiceData(active: false, keys: [])`; a sidecar with no key is not written. Stop waits for the model's load before draining the recogniser. Segments are fed only while the switch, as the ticker last read it, is on; decisions re-read the config. The ticker loads the config once per tick for the silence threshold and the voice settings (`checkSilence` takes it). `MeetingHarness` takes `voices: FakeVoiceEmbedder?` and builds the `VoiceStore` and `MatchLog` in its `TempDirectory` (exposed as `voices: VoiceDependencies?`), keeps every pulled event in `seen`, and gains `deliverWords`; `isClose` moved from `VoiceRecogniserTests` to the shared voice helpers. The first red was `cannot find type 'VoiceDependencies'` (the harness names it before the call), not `extra argument 'voices'`.
12. **Stage 16 (serial):** a rename emits `.speakers` twice, after the rename as today and after the link. "Not <name>" also relearns, so a key leaving a linked speaker leaves that person's sample. A person created by a rename whose store write fails is not linked (logged). A meeting whose switch was off at Stop keeps no route, so later renames there learn nothing. At Stop the user's speaker needs `voice_min_speech_seconds` only on the local route in a remote meeting; otherwise any of its keys with voice data links it. Extra test `aMatchLogThatCannotBeWrittenIsLoggedAndTheActionStands`.
13. **Stage 17 (serial):** `MeetingVoiceRoute.live` is async: it reads the people store for the first enrolment. Per-key speech and the `mw:` first-sight decision are gated, like local feeding, on the switch as the ticker last read it. An ignored identifier is dropped, and the notice shown, whatever the switch; "Not <name>" resets trust only with the switch on; a link that stores an identifier sets `speechmaticsTrusted`. Every `SpeakersResult` relearns every linked person. The sidecar holds only keys Speechmatics gave an identifier. Log lines shorten an `mw:` key to eight characters of its person id (`MeetingVoiceRoute.logged`). The commit also removes a needless `await` from a Stage 16 test. `MeetingController.swift` is 1,054 lines (*Risks* 8): the hooks, registry calls and persistence stay there; the per-meeting state and logic are in `MeetingVoiceRoute` (449 lines).
14. **Stage 18 (serial):** the quiet action pill is `PillButtonStyle.Kind.quietAction`: a `color.text.secondary` label lit with `tint` (the accent by default, `color.recording` for Forget) on hover or keyboard focus (`isFocused`); `AboutView.swift` and `CreditsView.swift`, outside the stage's files, move the three Credits pills to it, closing item 1. `learnsVoice` counts a meeting as live only while its state is active and its latest `.voiceData` said `active`, so a model that failed to load promises nothing; the user's speaker also counts the sidecar's `"user"` key. The model adds `renameTitle(of: Paragraph)`, `renameDraft(of:)`, `rejectTitle(of:)` and `rememberLine(speaker:draft:)`, which hides the remembered-voice line for a blank or `Speaker N` draft (R17) where the mockup shows "Type a name." for a blank one. The popover opened from a suggestion accepts it when the suggested name is committed unchanged (the mockup's rule) and renames without the merge prompt otherwise. Pills beside a name take no more height than the name's line, so paragraphs keep today's spacing; the mockup's 24 px header minimum is not applied. The 470 pt breakpoint is measured on the transcript column with `onGeometryChange`; the provisional underline's dash is 3/2 pt, drawn with a `HorizontalRule` shape the marker lines now share; the notice is inset 20 pt with 12 pt above. Extra tests `theRememberedLineNamesTheTrimmedDraft` and `everyModelReadsTheVoiceRouteSwitch`.
15. **Stage 19 (serial):** the Merge Dialog is drawn by `MainView` over the window from `PeopleModel.pending`, as the Meetings page's deletion is; `PillMenu.popUp` is internal so a quiet pill opens the Merge into… menu (its first, disabled line reads "Merge <name> into"), and `Tile.appSoft` draws the empty page's mark on the accent's soft fill as the mockup does (`MainView.swift`, `PillMenu.swift`, `Tile.swift` are outside the stage's files). `PeopleModel.Dependencies` also carries `now` and `calendar`: "last heard" reads "today", "18 Nov" or "16 Oct 2025" in another year and is left out for a person never heard; rows sort by `lastHeard ?? createdAt`, then name. Rename is disabled for a blank or `Speaker N` draft rather than given new copy; a name the store reports taken (`nameTaken`) gets the same refusal. `AppDelegate` wires `openMeetingsSettings` to select Meetings. `isRecording` follows `MeetingCoordinator.isActive` (starting to stopping), and turning it on clears a pending Dialog. Extra test `thePeopleModelIsBuiltFromItsDependencies`; the `SettingsModelTests` harness gains a `people:` parameter.
16. **Stage 20 (serial):** Forget's dependencies are four closures, `forget(UUID?)` (nil runs `forgetEveryone`), `scrubOpenMeetings`, `scrubStoredMeetings` and `removeMatches(Set<UUID>?)`, and the ids come from the row (`[id] + aliases`), so `VoiceStore.forget`'s result is not used. The actions are `requestForget(_:)` / `requestForgetEveryone()` behind the shared `confirm()`, so the first red named `requestForget`, not `forget`. A failed store, rename, merge or match-log write shows "Could not save the remembered voices (<reason>)" as a warning line on People, copy the design does not give. The Forget everyone Dialog reads "Deletes 1 person, …" for one person; the user's own Forget Dialog uses the mockup's text. `MeetingVoiceRoute.scrub(_:people:)` keeps an emptied sidecar as an empty one rather than nil, so a stopped meeting never falls back to the recogniser's vectors (test `aStoppedMeetingTeachesNothingForgottenAfterwards`); `MeetingController.scrubVoices` acts only on a stopped meeting, and on one without a readable sidecar deletes the file when the scrub concerns its linked people or everyone, as `VoiceScrubber` does (test `anUnreadableSidecarOfAnOpenMeetingGoesWithItsPeople`). Stop and the scrub share one `saveSidecar`; the scrub emits `.speakers`, then `.voiceData(active: false, …)` only when the sidecar changed. `MeetingCoordinator.scrubVoices` returns a recording session's meeting id too (its controller skips the scrub); People is locked while one records. `MeetingController.swift` is 1,086 lines (*Risks* 8).

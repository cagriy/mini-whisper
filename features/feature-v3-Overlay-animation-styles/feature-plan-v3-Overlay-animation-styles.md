# Overlay animation styles — Implementation Plan v3

**Status:** Draft
**Date:** 2026-09-07
**Design:** [feature-design-v3-Overlay-animation-styles.md](./feature-design-v3-Overlay-animation-styles.md)

## Overview

Six selectable overlay styles for the 300×300 recording card, five of them ported from the
animation-studies mockup, with Soft meter as the new default and a Settings → Overlay pane that
picks between them beside a looping live preview. The plan lands bottom-up along the module graph:
the config key first (Stage 1), then the two behaviour-preserving extractions the new styles share
with the constellation (Stage 2), then the pure motion model (Stages 3–4), then drawing (Stage 5),
then the animator seam that makes the card honour the stored style (Stage 6), then the Settings
pane (Stage 7) and its live preview plus the release notes (Stage 8). Design §9's rollout order is
followed, with three regroupings recorded under *Planning decisions taken*. Every stage leaves
`swift test` and `xcodebuild … test` green and the app building.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only |
integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests,
platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a
one-line justification.

**Swift's compiled first red.** A stage that introduces a brand-new type cannot reach a red
*assertion* first: the test target fails to build. That build failure — `error: cannot find
'<Type>' in scope` from `swift test` / `xcodebuild` — is the legitimate first red. Each such stage
then scaffolds the minimal empty API, re-runs to confirm red as *assertion* failures (`✘ Test …
recorded an issue`), and only then implements.

**Runners and registration.**

| Layer | Command |
|---|---|
| Core package tests | `cd Packages/MiniWhisperCore && swift test` |
| One core suite | `cd Packages/MiniWhisperCore && swift test --filter MWOverlaySimTests` |
| Core build only | `cd Packages/MiniWhisperCore && swift build` |
| App tests (and build) | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` |
| App build only | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd build` |

- Framework is **Swift Testing** throughout (`@Suite struct`, `@Test func`, `#expect`). No XCTest.
- Core sources and tests are directory-discovered by SwiftPM: new files inside an existing target
  need no `Package.swift` edit. A new *target* or a new *dependency edge* does (Stage 1).
- App and AppTests sources are folder-sourced by xcodegen: every stage that adds a file under
  `App/` or `AppTests/` must re-run `xcodegen generate` before `xcodebuild`, or the file silently
  never compiles.
- Swift Testing output is preceded by an XCTest line `Executed 0 tests, with 0 failures` — read the
  `✔/✘ Test run with N tests in M suites …` line instead.

**Observed baseline, run 2026-09-07 before drafting (all green):**

| Command | Result |
|---|---|
| `swift build` | `Build complete!`, exit 0 |
| `swift test` | `✔ Test run with 480 tests in 50 suites passed` |
| `xcodebuild … test` | `✔ Test run with 105 tests in 16 suites passed` + `** TEST SUCCEEDED **` |

Each stage's "confirm no regressions" step means: core suite ≥ 480 passing and app suite ≥ 105
passing, with no failures.

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: `OverlayStyle`'s six cases and raw values under `overlay_style` | Stage 1 |
| R2: absent → `soft_meter`; unknown → `soft_meter` at runtime, raw preserved until a style is set | Stage 1 |
| R3: the card uses the configured style at every `show()`; a mid-flight change applies at the next show | Stage 6 |
| R4: every style renders all five `OverlayMode`s with the existing choreography | Stage 2, Stage 4, Stage 5, Stage 6 |
| R5: the constellation style is byte-for-byte what ships today | Stage 2, Stage 5, Stage 6 |
| R6: the five new styles reproduce the mockup's `Motion.sample` and drawing | Stage 3, Stage 5 |
| R7: new styles use the app's existing normalisation and attack/decay one-pole | Stage 2, Stage 4 |
| R8: geometry blends toward each sample at 9 s⁻¹ | Stage 4 |
| R9: Reduce Motion — fixed sample time 1.3 s, unsmoothed level, no blend, instant check | Stage 4, Stage 5 |
| R10: Settings gains an **Overlay** section between History and Sound, `sparkles.rectangle.stack` | Stage 7 |
| R11: the pane is the accepted mockup — 214 pt radio list beside a 316×316 well with a 300×300 preview, plus the footnote | Stage 7, Stage 8 |
| R12: picking a style writes `overlay_style` immediately and restarts the preview loop | Stage 7, Stage 8 |
| R13: the preview replays one 13 s loop with no controls | Stage 4, Stage 8 |
| R14: the preview runs only while the pane is on screen in a visible window | Stage 8 |
| R15: a config written elsewhere updates the pane through `refresh(from:)` | Stage 7 |
| R16: CHANGELOG entry and CLAUDE.md module-map edge | Stage 1 (CLAUDE.md), Stage 8 (CHANGELOG) |
| R17: no per-frame heap allocation; buffers sized once | Stage 3, Stage 4, Stage 5 |
| R18: at most 480 points per frame | Stage 3 |
| R19: `MiniWhisperCore` stays dependency-free; the app target adds no dependency | Stage 1 |
| R20: every duration tested on injected `dt`, never a real sleep | Stage 2, Stage 4, Stage 8 |

## Stages

### Stage 1 — `OverlayStyle` and the `overlay_style` config round-trip

**Goal:** The six styles exist as a `Codable` enum in `MWOverlaySim` and `config.json` stores,
defaults and round-trips `overlay_style` exactly as `streaming_engine` does.
**Category:** Hybrid — TDD for the enum and the config round-trip, plus two **non-TDD
(config-only)** steps (tracking the two spec files, editing CLAUDE.md's module map) that are not
host-assertable.

**Design references:** §3 R1, R2, R16, R19; §5.1 (`OverlayStyle`, `MWConfig` modified); §5.2; §5.11

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWOverlaySim/OverlayStyle.swift`
- create `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/OverlayStyleTests.swift`
- edit `Packages/MiniWhisperCore/Package.swift` (add `MWOverlaySim` to `MWConfig`'s dependencies)
- edit `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`
- edit `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`
- edit `CLAUDE.md` (module map)
- `git add` `features/feature-v1-Native-Swift-macOS-rewrite/mockups/mockup-v1-animation-studies.html`
  and `features/feature-v1-Native-Swift-macOS-rewrite/mockups/animation-studies.test.cjs`

**Steps (TDD):**
1. Non-TDD, first: `git add` the two untracked spec files above so the stage's commit tracks them
   (design §7 "Untracked spec files"). They are documentation, not built or run by CI.
2. Write test: `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/OverlayStyleTests.swift` →
   `sixCasesInDeclarationOrderWithPythonRawValues` (`OverlayStyle.allCases.map(\.rawValue) ==
   ["constellation", "silk_ribbon", "resonant_halo", "soft_meter", "liquid_pearl", "petal_iris"]`)
   and `defaultIsSoftMeter` (`OverlayStyle.default == .softMeter`). Expected initial failure:
   `swift test` fails to build with `error: cannot find 'OverlayStyle' in scope`.
3. Write test: extend `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`
   (existing suite `ConfigCodingTests`) with, mirroring its `unrecognisedStreamingEngineIsIgnoredButPreserved`
   / `chosenStreamingEngineReplacesAnUnrecognisedOne` pair:
   `overlayStyleAbsentIsSoftMeter`, `everyOverlayStyleRawValueRoundTrips`,
   `unrecognisedOverlayStyleIsIgnoredButPreserved` (decode `{"overlay_style":"nonsense"}` →
   `.softMeter`, re-encode → `"nonsense"`), `chosenOverlayStyleReplacesAnUnrecognisedOne`
   (set `overlayStyle`, re-encode → the chosen raw value), and `overlayStyleIsWrittenForANewConfig`
   (`Config().encoded()` contains `"overlay_style" : "soft_meter"`). Expected initial failure:
   `error: value of type 'Config' has no member 'overlayStyle'`.
4. Run `swift test` — confirm both build failures.
5. Implement: create `OverlayStyle.swift` with
   `public enum OverlayStyle: String, Codable, CaseIterable, Sendable` (cases `constellation`,
   `silkRibbon`, `resonantHalo`, `softMeter`, `liquidPearl`, `petalIris` with the raw values above)
   and `public static let \`default\` = OverlayStyle.softMeter` (backticks at the declaration only;
   use sites read `OverlayStyle.default`, as `URLSessionConfiguration.default` does).
6. Implement: add `"MWOverlaySim"` to the `MWConfig` target's `dependencies` in `Package.swift`
   (`MWOverlaySim` is a leaf, so no cycle) and `import MWOverlaySim` in `Config.swift`.
7. Implement: in `Config.swift` add
   `public var overlayStyle: OverlayStyle = .default { didSet { unrecognisedOverlayStyle = nil } }`
   and `var unrecognisedOverlayStyle: String?`; add `Key.overlayStyle = "overlay_style"` to `Key`
   and to `Key.all`; in `init(from:)` decode the raw string, assign `overlayStyle` **first** and
   `unrecognisedOverlayStyle` **second** (property observers do not fire inside the type's own
   initializer, verified, so the decoded raw survives); in `encode(to:)` write
   `unrecognisedOverlayStyle` when non-nil, otherwise `overlayStyle.rawValue`. `validated()` is
   untouched.
8. Run `swift test` — confirm pass and no regressions (≥ 480 passing).
9. Non-TDD, docs: edit `CLAUDE.md`'s module map — `MWOverlaySim` row gains `OverlayStyle`, and the
   `MWConfig` row's dependency column becomes `MWSupport, MWOverlaySim`.

**Definition of done:**
- `OverlayStyle` has six cases with the design's raw values and `default == .softMeter`.
- A config without `overlay_style` loads as `.softMeter`; an unknown value loads as `.softMeter`
  and is re-encoded verbatim; assigning `overlayStyle` clears the preserved raw.
- `Package.swift` records `MWConfig → MWOverlaySim`; no third-party dependency added (R19).
- The two spec files are tracked by git.
- `CLAUDE.md`'s module map lists the new edge and type.
- `swift test` ≥ 480 passing; `xcodebuild … test` ≥ 105 passing.

**Risks specific to this stage:** `Config`'s existing coding tests assert individual keys, not an
exhaustive key set, and `writesTwoSpaceIndentWithTrailingNewline` keys off the alphabetically first
key (`cleanup_enabled`, unchanged by `overlay_style`) — checked, so none break. Unlike
`streaming_engine`, `overlay_style` is non-optional and is therefore written into every config this
build saves; that is design §5.11's intent, not a regression.

### Stage 2 — Extract `LevelSmoother` and `Choreography` from `ConstellationSimulation`

**Goal:** The level one-pole and the mode clock/choreography become two reusable values that the
new styles will share, with the constellation's observable behaviour unchanged.
**Category:** Hybrid — TDD for the two extracted types, with step 6's recomposition a
**behaviour-preserving refactor** whose guard is the untouched `ConstellationSimulationTests`
(**characterization**: green before and after; a red there is a defect in this stage).

**Design references:** §3 R4, R5, R7, R20; §5.1 (`LevelSmoother`, `Choreography`, `ConstellationSimulation`); §5.12

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWOverlaySim/LevelSmoother.swift`
- create `Packages/MiniWhisperCore/Sources/MWOverlaySim/Choreography.swift`
- create `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/LevelSmootherTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/ChoreographyTests.swift`
- edit `Packages/MiniWhisperCore/Sources/MWOverlaySim/ConstellationSimulation.swift`
- **not** edited: `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/ConstellationSimulationTests.swift`

**Steps (TDD):**
1. Write test: `LevelSmootherTests.swift` → `attackAndDecayMatchTheShippedOnePole`, asserting the
   exact numbers `ConstellationSimulationTests.audioLevelMapping` pins — after `update(rms:
   Constants.levelCeil)` the level is `Constants.smoothAttack` (0.6); after a second, `0.84`; after
   `update(rms: 0)`, `0.84 * (1 - Constants.smoothDecay)`; plus `resetReturnsToZero`. Expected
   initial failure: `error: cannot find 'LevelSmoother' in scope`.
2. Write test: `ChoreographyTests.swift` → the same numbers the constellation suite asserts, on
   injected `dt` only: `showFadesCardIn120ms` (four 30 ms steps to `cardAlpha == 1`),
   `resultHoldsThenFadesOut` (alpha 1 through 260 ms, 0 after a further 120 ms),
   `errorShakeProfileAndDuration` (`shakeOffset` follows `ConstellationSimulation.shakeOffset(at:)`
   for 450 ms then 0), `contentHiddenAfterShake` (`contentVisible` false from 0.45 s),
   `errorFinishesAt3s` (`isFinished`), `labelStrings` (`"starting…"`, `"processing..."`,
   `String(format: "%.1fs", showTime)`, empty for result and error), `reduceMotionSuppressesShake`.
   Expected initial failure: `error: cannot find 'Choreography' in scope`.
3. Run `swift test` — confirm both build failures; scaffold the two empty types
   (`struct LevelSmoother { … }`, `struct Choreography { … }` with stubbed members) and re-run to
   confirm red as assertion failures (`✘ Test … Expectation failed`).
4. Implement `LevelSmoother`: `public struct LevelSmoother: Sendable` with
   `public private(set) var level = 0.0`, `mutating func update(rms: Double) -> Double` applying
   `ConstellationSimulation.normalisedLevel` then the per-tick one-pole
   (`Constants.smoothAttack` rising, `Constants.smoothDecay` falling), and
   `mutating func reset()`.
5. Implement `Choreography`: `public struct Choreography: Sendable` with
   `init(reduceMotion: Bool = false)`, `mode`, `modeTime`, `showTime`, `errorText`, and the
   computed `cardAlpha`, `shakeOffset`, `contentVisible`, `label`, `isFinished` lifted verbatim
   from `ConstellationSimulation`'s `cardAlpha()`, `shake()`, `dotsVisible()`, `label()` and
   `isFinished`. `show()` resets mode/times/errorText; `set(mode:)` resets `modeTime` and stores
   or clears `errorText`; `advance(dt:)` adds to `modeTime` and `showTime`.
6. **Behaviour-preserving refactor:** recompose `ConstellationSimulation` on the two values —
   `choreography.show()` / `set(mode:)` / `advance(dt:)` inside the existing `show()`, `set(mode:)`
   and `step(dt:level:)` (the `dt` clamp and the free-running ambient `time` stay in the
   simulation); `mode` reads become `choreography.mode`; `updateLevel` keeps its
   `guard case .recording` and delegates to `smoother.update(rms:)`; `show()` calls
   `smoother.reset()`; `step` fills `frame.cardAlpha`, `frame.offsetX`, `frame.dotsVisible`,
   `frame.label` and `frame.errorText` from the choreography. Processing's `rotationAngle` reset
   stays in `set(mode:)`.
7. Run `swift test` — confirm the two new suites pass **and** `ConstellationSimulationTests` passes
   unmodified (the characterization guard for R5). Run `xcodebuild … build` to confirm the app
   target still compiles.

**Definition of done:**
- `LevelSmoother` and `Choreography` exist with the design's interfaces and are covered by their
  own suites, entirely on injected `dt`.
- `ConstellationSimulationTests.swift` is byte-identical to its pre-stage content and green.
- `ConstellationSimulation`'s public API is unchanged.
- `swift test` ≥ 480 + new tests passing; app target builds.

**Risks specific to this stage:** the extraction is the design's own "low likelihood, high impact"
risk. Mitigation is procedural: `ConstellationSimulationTests` is forbidden to change in this stage,
so any drift shows up as a red there rather than in review.

### Stage 3 — `StyleSampler`: the pure motion model

**Goal:** A pure, allocation-free port of the mockup's `Motion.sample` for the five new styles,
pinned by the mockup's own assertions rewritten in Swift.
**Category:** TDD.

**Design references:** §3 R6, R17, R18; §5.1 (`StylePhase`, `StyleGeometry`, `StyleSampler`); §5.2 (Styles constants); §5.3; §5.12

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWOverlaySim/StyleGeometry.swift` (`StylePoint`, `StyleGeometry`, `StylePhase`)
- create `Packages/MiniWhisperCore/Sources/MWOverlaySim/StyleSampler.swift`
- edit `Packages/MiniWhisperCore/Sources/MWOverlaySim/Constants.swift` (new "Styles" section)
- create `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/StyleSamplerTests.swift`

**Steps (TDD):**
1. Write test: `StyleSamplerTests.swift`, a one-for-one port of
   `features/feature-v1-Native-Swift-macOS-rewrite/mockups/animation-studies.test.cjs` for the five
   new styles:
   - `pointCountsPerStyle` — 360 / 360 / 15 / 180 / 480 for ribbon / halo / meter / pearl / iris,
     and `StyleSampler.pointCount(_:) <= Constants.stylePointCapacity` for every style (R18).
   - `everyStyleRespondsToSpeechIntensity` — the cjs `extent` helper
     (`mean((x−150)² + (y−140)² + height²)`) at `level 1` exceeds `level 0` by more than 8 % in
     `.speaking` at `t = 1.3`.
   - `processingIgnoresLevelAndStaysAnimated` — `.processing` output is identical for level 0 and 1
     at `t = 2`, and differs between `t = 2` and `t = 3`.
   - `quietIgnoresLevel` — `.quiet` output identical for level 0 and 1 at `t = 1`.
   - `doneEmitsNoPoints` — `.done` yields `count == 0` for every style (the design's deliberate
     departure from the mockup's single placeholder point; the layer draws the check instead).
   - `everyPointFiniteAndInsideTheCard` — for every style, every phase, `t ∈ {0, 1.3, 20, 500}` and
     `level ∈ {0, 0.5, 1}`: all values finite, `x ∈ [5, 295]`, `y ∈ [5, 275]`.
   - `pearlGlowFollowsTheMockup` — `glowX == 139 + 7·sin(0.8·t)` at several `t`.
   - `phaseFromMode` — `.starting → .quiet`, `.recording → .speaking`, `.processing → .processing`,
     `.result → .done`, `.error → .quiet`.
   Expected initial failure: `error: cannot find 'StyleSampler' in scope`.
2. Run `swift test` — confirm the build failure; scaffold `StylePoint`, `StyleGeometry`,
   `StylePhase` and an empty `StyleSampler.sample`/`pointCount`, re-run and confirm red as
   assertion failures (point counts of 0, `#expect` mismatches).
3. Implement: `StyleGeometry.swift` — `public struct StylePoint: Sendable, Equatable { x, y, alpha,
   height }`; `public struct StyleGeometry: Sendable { public private(set) var points:
   [StylePoint]; public internal(set) var count: Int; public internal(set) var glowX: Double }`
   whose `init()` allocates `Constants.stylePointCapacity` (480) points once and never grows, in
   the shape `Frame.swift` already uses; `public enum StylePhase: Sendable { case quiet, speaking,
   processing, done }` with `public init(_ mode: OverlayMode)`.
4. Implement: `Constants.swift` gains a "Styles" section — `stylePointCapacity = 480`,
   `styleBlendRate = 9.0`, `styleCheckSeconds = 0.35`, `reduceMotionSampleTime = 1.3`,
   `styleMarkWhite = (red: 244.0/255, green: 248.0/255, blue: 255.0/255)`, each with the mockup
   line it came from in a comment, as the file already documents `overlay.py`'s values.
5. Implement: `StyleSampler.swift` — `public enum StyleSampler` with
   `public static func pointCount(_ style: OverlayStyle) -> Int` and
   `public static func sample(_ style: OverlayStyle, time: Double, level: Double, phase:
   StylePhase, into geometry: inout StyleGeometry)`, writing the design §5.3 table into the
   caller's buffer by index (never appending), setting `count` and, for the pearl, `glowX`.
   `.constellation` and `.done` set `count = 0`.
6. Run `swift test` — confirm pass and no regressions.

**Definition of done:**
- All ported assertions pass for the five new styles.
- `sample` writes into a caller-owned buffer and allocates nothing (no `append`, no array literal).
- `Constants` carries the five Styles values with their mockup provenance.
- `swift test` green; app target still builds.

**Risks specific to this stage:** transcription slips in the formulas. Mitigation: §5.3 is
transcribed alongside the mockup's `Motion.sample` open in a diff, and the bounds/response/
processing-invariance tests catch a sign or factor error in every style.

### Stage 4 — `StyleSimulation`, `StyleFrame` and `PreviewScript`

**Goal:** A stateful driver that turns `dt` plus a raw RMS into a drawable `StyleFrame`, with the
shared choreography, the app's level one-pole, the 9 s⁻¹ blend and Reduce Motion; plus the
preview's 13 s script.
**Category:** TDD.

**Design references:** §3 R4, R7, R8, R9, R13, R17, R20; §5.1 (`StyleSimulation`, `StyleFrame`, `PreviewScript`); §5.2 (Preview constants); §5.4; §5.6; §5.12

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWOverlaySim/StyleSimulation.swift` (`StyleSimulation`, `StyleFrame`)
- create `Packages/MiniWhisperCore/Sources/MWOverlaySim/PreviewScript.swift`
- edit `Packages/MiniWhisperCore/Sources/MWOverlaySim/Constants.swift` (new "Preview" section)
- create `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/StyleSimulationTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWOverlaySimTests/PreviewScriptTests.swift`

**Steps (TDD):**
1. Write test: `StyleSimulationTests.swift` — `modeMapsToPhase`; `levelMatchesLevelSmoother` (the
   same 0.6 / 0.84 / 0.84·0.92 sequence, and the smoother holding its value outside `.recording`);
   `blendConvergesWithinOneSecond` (60 steps of `dt = 1/60` leave every point within 1e−3 of
   `StyleSampler.sample`'s output); `modeChangeGlidesRatherThanJumps` (the first frame after a
   phase switch lies strictly between the previous geometry and the new sample);
   `checkProgressRampsOver350ms` (0 → 1 across `styleCheckSeconds` in `.result`, 0 in every other
   phase); `reduceMotionFreezesTimeAndSnaps` (after any number of steps the geometry equals
   `StyleSampler.sample(style, time: Constants.reduceMotionSampleTime, …)` exactly — proving both
   the frozen sample time and a blend factor of 1 — the level equals
   `ConstellationSimulation.normalisedLevel(rms:)` with no smoothing, and `checkProgress == 1` on
   the first result frame); `dtIsClampedTo50ms`; `isFinishedMatchesTheConstellation`
   (result at 260 + 120 ms, error at 3 s); `geometryCapacityIsConstantAcrossShow`. Expected initial
   failure: `error: cannot find 'StyleSimulation' in scope`.
2. Write test: `PreviewScriptTests.swift` — `modeBoundaries` (`mode(at:)` is `.starting` on
   [0, 2), `.recording` on [2, 8), `.processing` on [8, 11.5), `.result` on [11.5, 13), and wraps
   at 13); `simulatedRMSMapsThroughNormalisedLevel`
   (`ConstellationSimulation.normalisedLevel(rms: PreviewScript.simulatedRMS(at: t))` equals
   `Constants.previewVoiceLevel * PreviewScript.phrase(at: t)` within 1e−12);
   `phraseStaysInsideZeroToOne`. Expected initial failure:
   `error: cannot find 'PreviewScript' in scope`.
3. Run `swift test` — confirm both build failures; scaffold both types and re-run to confirm red as
   assertion failures.
4. Implement: `Constants.swift` gains a "Preview" section — `previewLoopSeconds = 13.0`,
   `previewStartingSeconds = 2.0`, `previewRecordingSeconds = 6.0`, `previewProcessingSeconds = 3.5`,
   `previewVoiceLevel = 0.65`.
5. Implement: `StyleFrame` (`geometry`, `cardAlpha`, `offsetX`, `label`, `errorText`,
   `contentVisible`, `checkProgress`, `phase`) and `StyleSimulation` per design §5.6 —
   `init(style:reduceMotion:)`, `show()`, `set(mode:)`, `step(dt:level:) -> StyleFrame`,
   `isFinished`, `level`; two `StyleGeometry` buffers (`sample`, `current`) allocated in `init`,
   blended in place with `1 − exp(−Constants.styleBlendRate·dt)` (1 under Reduce Motion or when
   `count` changed).
6. Implement: `PreviewScript` per design §5.4 — `loopSeconds`, `mode(at:)`, `simulatedRMS(at:)`,
   `phrase(at:)`, with `simulatedRMS` inverting `normalisedLevel` so the smoother sees
   `0.65 · phrase(t)`.
7. Run `swift test` — confirm pass and no regressions; run `xcodebuild … build`.

**Definition of done:**
- `StyleSimulation` reproduces the constellation's fade/hold/shake/finish timings through
  `Choreography`, and its level through `LevelSmoother`.
- The blend, the Reduce Motion behaviour and the `dt` clamp are pinned on injected `dt` only.
- `PreviewScript`'s boundaries and simulated voice are pinned.
- No allocation per `step`: the geometry buffers are created once and their `count` is constant
  for a given style.
- `swift test` green; app target builds.

**Risks specific to this stage:** the design's `.done` path skips sampling, so `current` keeps the
last non-done geometry while the layer draws only the check. The `geometryCapacityIsConstantAcrossShow`
test pins that this never reallocates; the layer's own render test (Stage 5) pins that stale
geometry is never drawn in `.done`.

### Stage 5 — `CardChrome` and `StyleLayer`

**Goal:** The shared card chrome is extracted from `ConstellationLayer`, and a new `StyleLayer`
draws a `StyleFrame` for all five new styles.
**Category:** Hybrid — TDD for `StyleLayer` (host-testable through a `CGContext` bitmap, exactly as
`ConstellationLayerRenderTests` already is), with step 4's `CardChrome` extraction a
**behaviour-preserving refactor** guarded by the untouched `ConstellationLayerRenderTests`
(**characterization**).

**Design references:** §3 R4, R5, R6, R9, R17; §5.1 (`CardChrome`, `StyleLayer`); §5.5; §5.12

**Touches:**
- create `App/Overlay/CardChrome.swift`
- create `App/Overlay/StyleLayer.swift`
- edit `App/Overlay/ConstellationLayer.swift`
- create `AppTests/StyleLayerRenderTests.swift`
- **not** edited: `AppTests/ConstellationLayerRenderTests.swift`

**Steps (TDD):**
1. Write test: `AppTests/StyleLayerRenderTests.swift`, modelled on the existing sibling
   `AppTests/ConstellationLayerRenderTests.swift` (same `makeContext()` bitmap helper, same
   600-frame script through `.starting → .recording → .processing → .result`, driven by
   `StyleSimulation` instead of `ConstellationSimulation`):
   `rendersEveryNewStyleWithoutError` (parameterised over the five new styles; 600 frames drawn,
   bitmap non-empty), `frameBufferIsReusedAcrossDraws` (the layer's point-storage identity is
   stable across 1 and 600 frames, as the constellation test asserts), and
   `errorModeDrawsTheMessageOnceTheShakeIsSpent`. Expected initial failure: `xcodebuild … test`
   fails to build with `error: cannot find 'StyleLayer' in scope`.
2. Run `xcodegen generate && xcodebuild … test` — confirm the build failure; scaffold an empty
   `StyleLayer: CALayer` with `update(_:)` and `draw(in:)`, re-run and confirm red as assertion
   failures (empty bitmap, nil storage identity).
3. Implement: `App/Overlay/CardChrome.swift` — `enum CardChrome` with static
   `drawCard(in:rect:alpha:)`, `drawLabel(in:rect:text:alpha:font:)` and
   `drawError(in:rect:text:alpha:font:)`, lifted verbatim from `ConstellationLayer`'s rounded-card
   fill, `drawLabel` and `drawError` (the instance `cardAlpha` becomes an `alpha` parameter).
4. **Behaviour-preserving refactor:** `ConstellationLayer.draw(in:)` calls `CardChrome` for those
   three pieces and keeps its own link and dot drawing. `AppTests/ConstellationLayerRenderTests.swift`
   stays untouched and green — the characterization guard for R5.
5. Implement: `App/Overlay/StyleLayer.swift` per design §5.5 — a point buffer of
   `Constants.stylePointCapacity` copied element-wise from the frame (never assigned wholesale, so
   no COW allocation and the storage identity holds), `action(forKey:)` returning nil, one
   `CGGradient` built in `init` for the pearl, and the per-style drawing: polyline runs of
   120/180/80 for ribbon/halo/iris, vertical strokes for the meter, clipped radial gradient plus
   outline for the pearl, and the `.done` check stroke at `0.9 · checkProgress · cardAlpha`.
   Expose `pointStorageIdentity` for the render test, as `ConstellationLayer` exposes
   `dotStorageIdentity`.
6. Run `xcodegen generate && xcodebuild … test` — confirm pass and no regressions (≥ 105 + new).
   Run `swift test` to confirm the core package is untouched.

**Definition of done:**
- `CardChrome` owns the card fill, the bottom-right label and the centred error text; both layers
  use it.
- `StyleLayer` renders 600 scripted frames per new style into a non-empty bitmap without error.
- The layer's point storage identity is stable across draws (R17).
- `ConstellationLayerRenderTests.swift` unchanged and green.
- `xcodebuild … test` green; `swift test` green.

**Risks specific to this stage:** the flip into the mockup's y-down space (`translateBy(0, 300)`,
`scaleBy(1, −1)`) is applied only around the geometry, not the label — an over-broad save/restore
would mirror the label. The render test's non-empty-bitmap check will not catch that; the Stage 8
acceptance pass against the mockup will.

### Stage 6 — The `OverlayAnimator` seam and the card honouring `overlay_style`

**Goal:** One protocol both the card and the future preview drive, and the card rendering the
configured style from its next `show()`.
**Category:** Hybrid — TDD for the animator seam and factory, plus an **integration-verified**
remainder (step 7) for the `NSPanel` card and its display placement, which cannot run under the
host test runner; the verification command is named in that step.

**Design references:** §3 R3, R4, R5; §5.1 (App target table); §5.4; §5.6; §5.10; §5.12

**Touches:**
- create `App/Overlay/OverlayAnimator.swift` (`OverlayAnimator`, `OverlayAnimatorFactory`, `ConstellationAnimator`, `StyleAnimator`)
- edit `App/Overlay/OverlayPanelController.swift`
- edit `App/AppDelegate.swift`
- create `AppTests/OverlayAnimatorTests.swift`

**Steps (TDD):**
1. Write test: `AppTests/OverlayAnimatorTests.swift` → `factoryReturnsConstellationForConstellation`
   and `factoryReturnsStyleAnimatorForEveryOtherStyle` (parameterised over
   `OverlayStyle.allCases`), `animatorStyleMatchesWhatItWasMadeFor`,
   `isFinishedPropagatesFromTheSimulation` (drive `set(mode: .result)` then
   `step(dt:level:)` past 380 ms of injected `dt` and expect `isFinished`), and
   `layerIsSizedToTheCard`. Expected initial failure: `xcodebuild … test` fails to build with
   `error: cannot find 'OverlayAnimatorFactory' in scope`.
2. Run `xcodegen generate && xcodebuild … test` — confirm the build failure; scaffold the protocol
   and an empty factory, re-run and confirm red as assertion failures.
3. Implement: `App/Overlay/OverlayAnimator.swift` — `@MainActor protocol OverlayAnimator` with
   `var style: OverlayStyle { get }`, `var layer: CALayer { get }`, `func show()`,
   `func set(mode: OverlayMode)`, `func step(dt: TimeInterval, level: Double)`,
   `var isFinished: Bool { get }`, `func setContentsScale(_ scale: CGFloat)`;
   `ConstellationAnimator` wrapping `ConstellationSimulation` + `ConstellationLayer` (the body of
   today's `OverlayPanelController.step`); `StyleAnimator` wrapping `StyleSimulation` +
   `StyleLayer`; `enum OverlayAnimatorFactory { static func make(style:reduceMotion:) -> any
   OverlayAnimator }`.
4. Implement: `OverlayPanelController` — `init(style:reduceMotion:)` stores both;
   `func setStyle(_:)` stores only; `show(on:)` rebuilds the animator through the factory when the
   stored style differs from the current animator's, removing the old sublayer and adding the new
   one, then sets `contentsScale`, `level = 0`, `animator.show()`, `animator.step(dt: 0, level: 0)`
   before ordering front; the driver tick becomes `animator.step(dt:level:)` +
   `if animator.isFinished { hide() }`. `set(mode:)` and `setLevel(_:)` keep their current
   signatures, so `UIEventRouter` is untouched.
5. Implement: `AppDelegate` — build the controller with `style: config.overlayStyle`, keep the
   reference in a stored `overlay` property, and in `apply(_ config:)` call
   `overlay?.setStyle(config.overlayStyle)`, logging `Log.ui.info("Overlay style: \(raw)")` only
   when the value changed, plus once at start with the initial style (§5.10).
6. Run `xcodegen generate && xcodebuild … test` — confirm pass and no regressions.
7. Integration-verified remainder (the `NSPanel` card and its display placement cannot run under
   the host test runner). Verification command:
   `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd build && open ".dd/Build/Products/Debug/Mini Whisper.app"`.
   Then: dictate once and confirm the card appears in Soft meter; set `overlay_style` to
   `constellation` in `~/.config/mini-whisper/config.json` and confirm the next dictation uses the
   constellation, and that a change made while the card is on screen only takes effect at the next
   show (R3); confirm `log stream --predicate 'subsystem CONTAINS "mini-whisper"'` shows the
   `Overlay style:` line once at start and once per change (§5.10).

**Definition of done:**
- `OverlayAnimatorFactory.make` returns `ConstellationAnimator` for `.constellation` and
  `StyleAnimator` for the other five; `isFinished` propagates.
- `OverlayPanelController` swaps animators only at `show()`.
- `AppDelegate` passes the configured style at build time and on every config change, and logs it.
- `UIEventRouter` is unchanged.
- `xcodebuild … test` green; the manual check in step 7 passes.

**Risks specific to this stage:** this is the merge point where the default look changes for
everyone with no in-app way back until Stage 7 — see *Cross-cutting concerns → Compatibility*.

### Stage 7 — Settings → Overlay: catalog, model and radio list

**Goal:** An Overlay section between History and Sound whose radio list writes `overlay_style`
immediately and follows external config changes.
**Category:** Hybrid — TDD for the catalog and the model, plus a **platform-only / UI wiring**
remainder (step 9) for the SwiftUI pane's layout, which the host runner cannot assert; the
verification steps are named there.

**Design references:** §3 R10, R11 (list half), R12, R15; §5.1 (`OverlayStyleCatalog`, `OverlaySection`, `SettingsModel`); §5.4; §5.12

**Touches:**
- create `App/Settings/OverlayStyleCatalog.swift`
- create `App/Settings/OverlaySection.swift`
- edit `App/Settings/SettingsModel.swift`
- edit `App/Settings/SettingsView.swift`
- create `AppTests/OverlayStyleCatalogTests.swift`
- edit `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write test: `AppTests/OverlayStyleCatalogTests.swift` → `rowsInTheAcceptedOrder`
   (`[.softMeter, .silkRibbon, .resonantHalo, .liquidPearl, .petalIris, .constellation]`),
   `everyRowHasATitleAndSummary`, `exactlyOneRowIsDefault` (Soft meter),
   `everyOverlayStyleHasARow`. Expected initial failure: `error: cannot find
   'OverlayStyleCatalog' in scope`.
2. Write test: extend `AppTests/SettingsModelTests.swift` (existing `Harness`) →
   `overlaySectionSitsBetweenHistoryAndSound` (`Section.allCases` order, `title == "Overlay"`,
   `symbolName == "sparkles.rectangle.stack"`), `setOverlayStyleWritesTheConfigKey` (after
   `await model.setOverlayStyle(.petalIris)`, `store.load().overlayStyle == .petalIris` and
   `model.selectedOverlayStyle == .petalIris`), `refreshFromConfigUpdatesTheSelection` (R15), and
   `overlayStyleRowsMatchTheCatalog`. Expected initial failure: `error: value of type
   'SettingsModel' has no member 'setOverlayStyle'` and `type 'SettingsModel.Section' has no
   member 'overlay'`.
3. Run `xcodegen generate && xcodebuild … test` — confirm both build failures.
4. Implement: `OverlayStyleCatalog` — `struct OverlayStyleCatalog` (or `enum` with statics) holding
   the six `(style, title, summary, isDefault)` rows of design §5.4 in the accepted display order.
5. Implement: `SettingsModel` — `import MWOverlaySim`; `Section.overlay` inserted between
   `.history` and `.sound` in the `case` list (`allCases` follows declaration order) with its
   `title` and `symbolName` arms; `struct OverlayStyleRow: Identifiable, Equatable`;
   `var overlayStyleRows: [OverlayStyleRow]`; `var selectedOverlayStyle: OverlayStyle {
   config.overlayStyle }`; `func setOverlayStyle(_ style: OverlayStyle) async { await write {
   $0.overlayStyle = style } }` through the existing write-through path.
6. Implement: `App/Settings/OverlaySection.swift` — a `SettingsPane(title: "Overlay")` containing
   an `HStack(alignment: .top, spacing: 12)` whose left column is a 214 pt `VStack(spacing: 5)` of
   radio rows in `GeneralSection.engineRow`'s form (`Button(.plain)`,
   `largecircle.fill.circle`/`circle`, title in body text, the selected row's summary as a
   `.caption` secondary line, a `.caption2` "Default" capsule trailing Soft meter) and whose right
   column is the 316×316 `RoundedRectangle(cornerRadius: 12)` well
   (`Color(nsColor: .underPageBackgroundColor)`, 1 pt `separatorColor` border) — empty in this
   stage, filled in Stage 8 — followed by the §5.4 `SettingsFootnote`.
7. Implement: `SettingsView` — add `case .overlay: OverlaySection(model: model)` to the exhaustive
   `pane` switch and correct the file's doc comment from "seven sections" to eight.
8. Run `xcodegen generate && xcodebuild … test` — confirm pass and no regressions.
9. Platform-only remainder (SwiftUI layout cannot be asserted by the host runner): open Settings,
   confirm Overlay sits between History and Sound with the right symbol, that the pane does not
   scroll at 780×560, that only the selected row shows its summary, and that clicking a row writes
   `overlay_style` (check `config.json`) and moves the card's style at the next dictation.

**Definition of done:**
- `Section.allCases` is General, Hotkeys, Keys, Cleanup, Vocabulary, History, Overlay, Sound.
- The catalog's six rows carry the design's titles and summaries in the accepted order, with Soft
  meter alone marked default.
- Picking a row writes `overlay_style` through `ConfigStore.update` and the selection follows
  `refresh(from:)`.
- The pane fits 560 pt without scrolling (step 9).
- `xcodebuild … test` green.

**Risks specific to this stage:** inserting `.overlay` into `Section` forces the exhaustive switch
sites — `SettingsView.pane`, `Section.title`, `Section.symbolName` — to be updated in the same
stage. All three were located; there are no others (`StatusItemController`'s `.history` is a
different enum).

### Stage 8 — The live preview, and the release notes

**Goal:** The 300×300 preview loops a simulated dictation in the selected style inside the pane's
well, starts and stops with the pane, and the change is written up.
**Category:** Hybrid — TDD for the preview view's loop and lifecycle (injected `dt`, injected
driver), plus a **non-TDD (config-only)** CHANGELOG edit and an **integration-verified** acceptance
pass (step 8) whose checks are named there.

**Design references:** §3 R11 (preview half), R12, R13, R14, R16, R20; §5.1 (`OverlayPreviewView`, `OverlayPreview`); §5.4; §5.6; §5.12; §7

**Touches:**
- create `App/Settings/OverlayPreview.swift` (`OverlayPreviewView`, `OverlayPreview`)
- edit `App/Settings/OverlaySection.swift`
- edit `App/Overlay/DisplayLinkDriver.swift` (add `var isRunning`)
- create `AppTests/OverlayPreviewViewTests.swift`
- edit `CHANGELOG.md`

**Steps (TDD):**
1. Write test: `AppTests/OverlayPreviewViewTests.swift`, driving `OverlayPreviewView` directly with
   a fake driver injected through its `makeDriver` parameter and injected `dt` (no `CADisplayLink`,
   no real time) → `attachingToAWindowStartsTheDriverAndShows`,
   `leavingTheWindowStopsTheDriver`, `dismantleStopsTheDriver`,
   `styleChangeRebuildsTheAnimatorAndResetsTheLoop`,
   `thirteenSecondsOfTicksWrapsAndCallsShowAgain` (step `13.0 / 0.05` ticks of `dt = 0.05` and
   assert `show()` ran twice and `loopTime` restarted), and
   `modeFollowsThePreviewScript` (the animator sees `.starting`, `.recording`, `.processing`,
   `.result` at the script's boundaries and each mode is applied once). Expected initial failure:
   `xcodebuild … test` fails to build with `error: cannot find 'OverlayPreviewView' in scope`.
2. Run `xcodegen generate && xcodebuild … test` — confirm the build failure; scaffold
   `OverlayPreviewView: NSView` with the injected `makeDriver` and an internal `tick(_:)`, re-run
   and confirm red as assertion failures.
3. Implement: `DisplayLinkDriver` gains `var isRunning: Bool { link != nil }` (no behaviour
   change).
4. Implement: `App/Settings/OverlayPreview.swift` —
   `final class OverlayPreviewView: NSView` holding the animator, a `loopTime`, the last applied
   mode and a driver built by an injected factory defaulting to `DisplayLinkDriver.init(view:onTick:)`;
   `viewDidMoveToWindow` starts on a non-nil window and stops on nil; `tick(_ dt:)` advances
   `loopTime`, calls `animator.show()` on each wrap, applies `PreviewScript.mode(at:)` when it
   changes, and calls `animator.step(dt:level: PreviewScript.simulatedRMS(at:))`;
   `setStyle(_:)` rebuilds the animator, resets `loopTime` and calls `show()`.
   `struct OverlayPreview: NSViewRepresentable` makes the view, forwards `style` in
   `updateNSView` and stops the driver in `static func dismantleNSView`.
5. Implement: drop `OverlayPreview(style: model.selectedOverlayStyle)` at 300×300, centred, into
   `OverlaySection`'s 316×316 well.
6. Run `xcodegen generate && xcodebuild … test` — confirm pass and no regressions. Run
   `swift test` — confirm the core package is untouched.
7. Non-TDD, docs: `CHANGELOG.md` gains an Unreleased **Added** entry naming the six styles, Soft
   meter as the new default for every install, and Settings → Overlay as the way back to the
   constellation.
8. Integration-verified: run the acceptance list of design §5.12 — pick each style and compare the
   preview against the matching card in `mockup-v1-animation-studies.html` side by side; dictate
   and confirm the card matches; delete `overlay_style` from `config.json` and confirm Soft meter;
   set it to `nonsense`, confirm Soft meter and that the raw value survives a save until a row is
   clicked; enable Reduce Motion and confirm static frames per phase; close Settings and confirm
   the preview's driver stops (the pane's CPU use returns to idle).

**Definition of done:**
- The preview loops the 13 s script in the selected style and restarts on a style change.
- Its driver starts on window attach and stops on detach and on dismantle, pinned by tests on
  injected `dt` (R20).
- The pane matches the accepted mockup.
- `CHANGELOG.md` has the Unreleased Added entry.
- Every acceptance check in step 8 passes.
- `swift test` and `xcodebuild … test` both green.

**Risks specific to this stage:** a display link outliving the pane. Two independent stops (window
detach and `dismantleNSView`) both covered by tests, and `NSView.displayLink` additionally pauses
while the view is off-screen.

## Cross-cutting concerns

- **Security** — the only new input is `overlay_style`, a user-writable string decoded into a
  closed enum with a default fallback (Stage 1); a value of the wrong JSON type is handled by
  `ConfigStore.readFromDisk`'s existing corrupt-file path, verified unchanged. No secrets, network,
  permissions or privileged operations are added at any stage, and the preview never opens the
  microphone. No stage widens a trust boundary, so no ordering window exists.
- **Performance** — the per-frame budget is fixed by construction: `StyleGeometry` allocates
  `Constants.stylePointCapacity` (480) points once in `init` (Stage 3), `StyleSimulation` owns
  exactly two of them (Stage 4), `StyleLayer` copies element-wise into a third and builds its
  `CGGradient` once (Stage 5). Stage 3's `pointCountsPerStyle` pins R18's 480 ceiling; Stage 4's
  `geometryCapacityIsConstantAcrossShow` and Stage 5's `frameBufferIsReusedAcrossDraws` pin R17.
  The preview costs one 300×300 layer only while its view is in a window (Stage 8).
- **Observability** — one addition, in Stage 6: `Log.ui.info("Overlay style: <raw>")` once at start
  and on every changed style in `AppDelegate.apply`. No metrics; the preview is the user-facing
  check that a style renders.
- **Compatibility / migration** — no data migration: older builds and the Python line ignore
  `overlay_style` and Stage 1's round-trip preserves it. The one intermediate window is between
  Stage 6 and Stage 7: the card's default becomes Soft meter with no in-app picker yet, escapable
  only by editing `config.json`. Accepted rather than bundled — design §9 cuts a single release with
  no flag, so no build ships from inside that window, and bundling Stages 6–8 would make one
  unreviewable stage. Every earlier stage is behaviour-neutral to the user; Stages 1–5 add code the
  app does not yet call.

  **User-visible state of each multi-stage requirement, and the bundling decision:**

  | Req | After each contributing stage | Bundle? |
  |---|---|---|
  | R4, R5, R6, R7, R9, R17 (Stages 2–6) | Nothing visible until Stage 6: Stages 2–5 are an internal refactor plus unreferenced new code, with the constellation byte-for-byte as today. | No — no user-visible partial state exists. |
  | R11, R12 (Stages 7–8) | After 7: the pane exists, the picker writes `overlay_style` and the card honours it; the 316×316 well is empty. After 8: the well holds the looping preview. | No — a working picker with an empty well is coherent, and bundling would put ~450 lines of view code in one stage. |
  | R13 (Stages 4, 8) | After 4: `PreviewScript` exists, nothing calls it. After 8: it drives the preview. | No — Stage 4 is invisible. |
  | R16 (Stages 1, 8) | After 1: CLAUDE.md's module map is correct for the edge that just landed. After 8: the CHANGELOG names the feature. | No — writing the CHANGELOG before the feature exists would be wrong. |
  | R3, R10 (single stage each) | n/a | n/a |

## Verification

With all eight stages merged, against design §3's acceptance criteria:

1. `cd Packages/MiniWhisperCore && swift test` — green, ≥ 480 tests.
2. `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` — green, ≥ 105 tests, `** TEST SUCCEEDED **`.
3. Launch the app. Settings → Overlay: the section sits between History and Sound with the
   `sparkles.rectangle.stack` symbol; the pane fits without scrolling; Soft meter is selected and
   tagged Default; the preview loops starting → recording → processing → check → blank.
4. Pick each of the six styles in turn: the preview restarts in that style and matches the
   corresponding card in `features/feature-v1-Native-Swift-macOS-rewrite/mockups/mockup-v1-animation-studies.html`
   opened side by side (R6). `~/.config/mini-whisper/config.json` shows the chosen `overlay_style`
   after each click (R12).
5. Dictate with each style selected: the card uses it, shows "starting…", the elapsed counter,
   "processing...", then the check, and dismisses on the same timing as before (R3, R4).
6. Force an error (dictate with no key configured): the card shakes for 0.45 s with the style's
   marks, then shows the message for the rest of 3 s (R4).
7. Delete `overlay_style` from `config.json` → Soft meter (R2). Set it to `nonsense` → Soft meter,
   and the raw value survives the next save until a row is clicked (R2).
8. Enable Reduce Motion in System Settings, relaunch: each phase draws a static frame and the check
   appears at full strength immediately; the card still fades and does not shake (R9).
9. Close Settings, confirm the app returns to idle CPU — the preview's display link stopped (R14).
10. `git log` shows `mockup-v1-animation-studies.html` and `animation-studies.test.cjs` tracked;
    `CHANGELOG.md` has the Unreleased Added entry; `CLAUDE.md`'s module map shows
    `MWConfig → MWOverlaySim` (R16).

## Risks and open issues

1. **Formula transcription drift from the mockup** (Stage 3). Five styles, ~25 expressions; a wrong
   sign or factor still passes a "renders something" check. *Mitigation:* Stage 3's ported
   assertions cover response-to-level, processing-invariance, animation-over-time, finiteness and
   in-frame bounds per style; Verification step 4 is a side-by-side comparison against the mockup
   itself.
2. **`Choreography` / `CardChrome` extraction changing shipped behaviour** (Stages 2, 5).
   *Mitigation:* `ConstellationSimulationTests.swift` and `ConstellationLayerRenderTests.swift` are
   forbidden to change in those stages and act as characterization guards; a red there fails the
   stage.
3. **`OverlayPreviewView` under the host test runner** (Stage 8). A real `CADisplayLink` will not
   tick in a unit test and may not even be creatable for a view with no screen. *Mitigation:* the
   driver is injected (see *Planning decisions taken* 3), so the tests never construct one; the
   real driver is exercised by Verification step 9.
4. **The `.done` geometry is stale by construction** (Stage 4). `step` skips sampling in `.done`,
   so `current` still holds the last speaking/processing geometry. *Mitigation:* `StyleLayer` draws
   only the check when `phase == .done`; Stage 5's render script covers `.result` frames.
5. **The y-flip in `StyleLayer`** (Stage 5). The mockup's coordinates are y-down and the card's are
   y-up; an over-broad `saveGState` would mirror the label as well as the geometry. *Mitigation:*
   §5.5 scopes the flip to the geometry block; Verification step 5 reads the label.
6. **Stage 6–7 default-change window.** Documented under *Cross-cutting concerns → Compatibility*;
   accepted, not mitigated further.

## Planning decisions taken

1. **`MWConfigTests/ConfigCodingTests`, not `ConfigTests`.** Design §5.12 named a file that does
   not exist; the config coding suite is `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`.
   The design has been corrected in place. Rationale: a factual grounding error, not a scope change.
2. **`Choreography.init(reduceMotion: Bool = false)`.** §5.1's interface list omits the input its
   `shakeOffset` needs (`ConstellationSimulation.shake()` reads `reduceMotion` today). Closed as an
   under-specification, matching `ConstellationSimulation.init(rng:reduceMotion:)`'s shape.
3. **`OverlayPreviewView` takes an injected driver factory**, defaulting to the real
   `DisplayLinkDriver`, and exposes an internal `tick(_ dt:)`; `DisplayLinkDriver` gains an
   internal `isRunning`. Rationale: a backward-compatible test seam that keeps `CADisplayLink` out
   of `AppTests` and makes R14's start/stop assertions runnable — the design's interface contract
   is unchanged.
4. **AppDelegate wiring lands in Stage 6 with the animator seam**, not in a final stage as design
   §9 sequences it. Rationale: R3 is then live the moment its stage merges rather than sitting
   half-built across two merges; the cost is the documented Stage 6–7 window, and staging order is
   the plan's to own.
5. **Design §9's "commit the spec files" stage is folded into Stage 1** as a first non-TDD step
   rather than a stage of its own. Rationale: a `git add` of two documentation files is not a
   reviewable increment; the stage's commit tracks them either way.
6. **R16 is split**: CLAUDE.md's module map is edited in Stage 1, where the `MWConfig → MWOverlaySim`
   edge actually lands, and the CHANGELOG in Stage 8, when the feature is complete. Rationale: the
   repo guide stays accurate between merges.
7. **File placement follows the existing `Frame.swift` convention**: `StyleGeometry.swift` holds
   `StylePoint`, `StyleGeometry` and `StylePhase` together (as `Frame.swift` holds `DotState`,
   `Link` and `Frame`); `StyleSimulation.swift` holds `StyleSimulation` and `StyleFrame`;
   `OverlayStyle.swift` mirrors `OverlayMode.swift`. The design specified types, not files.
8. **New `Constants` land in the stage that first needs them**: the "Styles" block in Stage 3
   (`styleMarkWhite` included, so the whole block is added once) and the "Preview" block in
   Stage 4. Rationale: no stage adds a constant nothing reads.
9. **`SettingsView`'s "seven sections" doc comment is corrected to eight in Stage 7.** Rationale:
   it is the sidebar's only written contract and would otherwise be wrong from that merge on.
10. **`OverlayStyle.default` is declared with backticks** (`static let \`default\``), as
    `URLSessionConfiguration.default` is, keeping the design's spelling at every use site.

## Deviations from the design

None — plan matches design v3 exactly.

## Deviations from plan

1. **Stage 3, step 3: `StyleGeometry.points` is `public internal(set)`, not `public private(set)`.**
   `private(set)` confines the setter to `StyleGeometry.swift`, so `StyleSampler` — which the same
   step puts in its own file — could not write into the buffer at all. `internal(set)` is also what
   the shape the step points at, `Frame.swift`'s `dots`/`links`, actually uses, and design §5.1
   specifies a plain `var`. `count` and `glowX` are `internal(set)` as the step says.

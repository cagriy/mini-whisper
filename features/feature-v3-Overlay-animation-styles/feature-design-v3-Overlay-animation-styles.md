# Overlay animation styles — Design v3

**Status:** Draft
**Date:** 2026-09-07

## 1. Summary

The recording card today shows one animation, the 24-dot constellation. This feature ports the
five alternatives from the animation studies mockup (Silk ribbon, Resonant halo, Soft meter,
Liquid pearl, Petal iris) into the app as selectable **overlay styles**, makes Soft meter the
default, and adds an **Overlay** section to Settings where the user picks a style while a live
in-window preview replays a simulated dictation in that style. It is for every user of the card;
it solves the studies' finding that the constellation's shifting link density competes with the
transcript the user is watching.

## 2. Goals and non-goals

- **Goals**
  - Six overlay styles, one of them the existing constellation, all driving the same 300×300 card
    through the same modes (starting, recording, processing, result, error).
  - Soft meter is the default for every install that has not chosen a style.
  - A Settings → Overlay pane with a radio list and a looping preview, as the accepted mockup shows.
  - The choice persists in `config.json` and takes effect at the card's next appearance.
  - Every style's motion is deterministic and tested without AppKit; every renderer is exercised
    by a scripted render test.
- **Non-goals**
  - Changing the caption bar, the card's size, opacity, radius, placement or its error behaviour.
  - Preview controls (state buttons, voice slider, pause). The preview is a plain loop.
  - Live style switching while the card is on screen; the new style applies at the next show.
  - Running the mockup's Node test file in CI. `animation-studies.test.cjs` tests the HTML mockup,
    not the app; its assertions are ported to Swift (§5.10) and the file is kept as the spec.
  - A per-style tuning UI (speed, size). Values are the mockup's, fixed.

## 3. Requirements

Functional:

1. `OverlayStyle` has six cases with `config.json` raw values `constellation`, `silk_ribbon`,
   `resonant_halo`, `soft_meter`, `liquid_pearl`, `petal_iris`, stored under the key
   `overlay_style`.
2. A config without `overlay_style` resolves to `soft_meter`. A config with an unrecognised value
   resolves to `soft_meter` at runtime and the raw value is preserved on save until the user picks
   a style, exactly as `streaming_engine` behaves today.
3. The card uses the configured style at every `show()`. A config change while the card is visible
   is applied at the next `show()`, not mid-animation.
4. Every style renders all five `OverlayMode`s. Starting shows the style's quiet form; recording
   drives it with the smoothed microphone level; processing shows the style's processing motion;
   result shows the style's completion mark for the existing 260 ms hold then fades over 120 ms;
   error keeps today's shake-then-message behaviour, with the style's marks hidden once the shake
   is spent.
5. The constellation style's behaviour is byte-for-byte what ships today: same simulation, same
   layer, same tests.
6. The five new styles reproduce the mockup's `Motion.sample` value for value (§5.3 table) and its
   drawing (§5.5), in the app's coordinate system.
7. The five new styles' level response uses the app's existing normalisation and attack/decay
   one-pole, so the same voice moves every style with the same envelope.
8. New-style geometry is blended toward each frame's sample with rate 9 s⁻¹ (`1 − e^(−9·dt)`), as
   the mockup does, so a mode change glides rather than jumps.
9. With Reduce Motion on, a new style samples at a fixed time of 1.3 s, takes the level without
   smoothing, skips the geometry blend and draws the completion mark at full strength at once;
   card fades and the existing no-shake rule are unchanged.
10. Settings gains a section **Overlay** between History and Sound, SF Symbol
    `sparkles.rectangle.stack`.
11. The Overlay pane is the accepted mockup: a 214 pt radio list (names only, the selected row
    unfolds its one-line description, Soft meter tagged "Default") beside a 316×316 neutral well
    holding a 300×300 live preview, followed by the footnote in §5.4. It fits the 560 pt window
    without scrolling.
12. Picking a style writes `overlay_style` through `ConfigStore.update` immediately and restarts
    the preview loop in the new style.
13. The preview replays one 13 s loop with no controls: fade-in over 120 ms, starting 0–2 s,
    recording 2–8 s with a simulated voice, processing 8–11.5 s, result at 11.5 s (hold 260 ms,
    fade 120 ms), empty until 13 s, repeat. Labels are the card's own ("starting…", "%.1fs",
    "processing...").
14. The preview runs only while the Overlay pane is on screen in a visible window; leaving the pane
    or closing Settings stops its display link.
15. A config written elsewhere (the correction window, an external edit) updates the pane's
    selection through the existing `refresh(from:)` path.
16. The CHANGELOG gains an Unreleased "Added" entry and CLAUDE.md's module map records the new
    dependency edge (§5.1).

Non-functional:

17. No per-frame heap allocation in any style's step or draw; geometry buffers are sized once.
18. One style step plus draw stays well under a frame at 120 Hz: at most 480 points per frame.
19. `MiniWhisperCore` stays dependency-free; the app target adds no dependency.
20. Every duration in the new code is tested on injected `dt`, never on a real sleep.

## 4. Background and context

- The card: `OverlayPanelController` (`App/Overlay/OverlayPanelController.swift:30-57`) owns one
  `ConstellationSimulation` and one `ConstellationLayer`, steps the simulation from
  `DisplayLinkDriver` and hides when `isFinished`. `UIEventRouter` maps `UIEvent`s to
  `set(mode:)` and `setLevel` (`App/UIEventRouter.swift:52-80`). The controller is built once in
  `AppDelegate.startNormal` (`App/AppDelegate.swift:126-128`) with the Reduce Motion flag.
- The simulation: `ConstellationSimulation` (`Packages/MiniWhisperCore/Sources/MWOverlaySim/ConstellationSimulation.swift`)
  holds the mode clock (`modeTime`, `showTime`), the level one-pole (`updateLevel`, lines 155-162,
  using `normalisedLevel` at line 68), and the choreography helpers `cardAlpha`, `shake`,
  `dotsVisible`, `label`, `isFinished`. `Frame` is a fixed-capacity value. All constants are in
  `Constants.swift`.
- The layer: `ConstellationLayer` (`App/Overlay/ConstellationLayer.swift`) draws the rounded card,
  links, dots, the bottom-right label and the centred error text from copied buffers.
- Config: `Config` (`Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`) decodes known keys
  by hand and round-trips unknown ones; `streamingEngine` / `unrecognisedStreamingEngine`
  (lines 99-102, 205-210, 224-228) is the pattern for an enum whose stored value may be unknown.
  `ConfigStore.update` validates, writes atomically and yields on `changes`; `AppDelegate.apply`
  is the single consumer (`App/AppDelegate.swift:299-313`).
- Settings: `SettingsModel.Section` (`App/Settings/SettingsModel.swift:57-85`) drives the sidebar
  `List` and the `pane` switch in `SettingsView` (`App/Settings/SettingsView.swift:24-33`);
  `GeneralSection.engineRow` (`App/Settings/GeneralSection.swift:65-92`) is the radio-row form the
  mockup reuses; `settingsBinding` and `write` are the write-through path.
- Module rules: `MWOverlaySim` has no dependencies; `MWConfig` depends on `MWSupport`
  (`Packages/MiniWhisperCore/Package.swift`).
- The spec: `features/feature-v1-Native-Swift-macOS-rewrite/mockups/mockup-v1-animation-studies.html`
  (the `Motion.sample` model, the `draw` routine, the concept names and blurbs) and its Node tests
  `animation-studies.test.cjs`. Both are currently untracked in git.
- Prior design: v1 §5.6 fixed the card's geometry, physics and Breathing choreography; this design
  keeps all of it for the constellation style and reuses its mode choreography for the rest.
- Accepted mockup for the Settings surface:
  [Overlay — Side by side](./mockups/mockup-v3-side-by-side.html)
  (https://claude.ai/code/artifact/60f53ea3-1a05-4730-be1a-fcf59ccc80e6).

## 5. Design

### 5.1 Architecture / components

Dependencies still flow downwards. One new edge: `MWConfig → MWOverlaySim`, so the config can
store the style enum the simulation module owns. `MWOverlaySim` stays a leaf.

**`MWOverlaySim` (modified).**

| Component | Responsibility | Interface | Depends on |
|---|---|---|---|
| `OverlayStyle` | The six styles and their raw values | `enum OverlayStyle: String, Codable, CaseIterable, Sendable`; `static let default: OverlayStyle = .softMeter` | — |
| `LevelSmoother` | The level one-pole extracted from `ConstellationSimulation.updateLevel` | `mutating func update(rms: Double) -> Double`, `mutating func reset()`, `var level` | `Constants` |
| `Choreography` | The mode clock and the mode-driven card behaviour extracted from `ConstellationSimulation` | `mutating func show()`, `mutating func set(mode:)`, `mutating func advance(dt:)`, `var mode`, `var modeTime`, `var showTime`, `var cardAlpha`, `var shakeOffset`, `var contentVisible`, `var label`, `var errorText`, `var isFinished` | `Constants` |
| `ConstellationSimulation` | Unchanged behaviour, now composed of `LevelSmoother` + `Choreography` | unchanged public API | the two above |
| `StylePhase` | The sampler's four phases | `enum StylePhase { case quiet, speaking, processing, done }`; `init(_ mode: OverlayMode)` (starting→quiet, recording→speaking, processing→processing, result→done, error→quiet) | `OverlayMode` |
| `StyleGeometry` | Fixed-capacity point buffer | `struct { var points: [StylePoint] (capacity 480); var count: Int; var glowX: Double }`; `StylePoint { x, y, alpha, height }` | — |
| `StyleSampler` | Pure port of `Motion.sample` for the five new styles | `static func sample(_ style: OverlayStyle, time: Double, level: Double, phase: StylePhase, into: inout StyleGeometry)`; `static func pointCount(_ style:) -> Int` | `Constants` |
| `StyleSimulation` | Stateful driver for a new style: choreography, level, blend, reduce motion | `init(style:reduceMotion:)`, `mutating func show()`, `mutating func set(mode:)`, `mutating func step(dt:level:) -> StyleFrame`, `var isFinished`, `var level` | `Choreography`, `LevelSmoother`, `StyleSampler` |
| `StyleFrame` | One frame for `StyleLayer` | `geometry: StyleGeometry`, `cardAlpha`, `offsetX`, `label`, `errorText`, `contentVisible`, `checkProgress: Double`, `phase: StylePhase` | — |
| `PreviewScript` | The preview's timeline and simulated voice | `static let loopSeconds = 13.0`; `static func mode(at t: Double) -> OverlayMode?` (nil = card hidden); `static func simulatedRMS(at t: Double) -> Double`; `static func phrase(at:)` | `Constants` |

**`MWConfig` (modified).** `Config.overlayStyle: OverlayStyle` (default `.softMeter`) with
`didSet { unrecognisedOverlayStyle = nil }`; `unrecognisedOverlayStyle: String?` internal; key
`overlay_style` in `Key.all`, decode and encode.

**App target (modified).**

| Component | File | Responsibility |
|---|---|---|
| `OverlayAnimator` (protocol, `@MainActor`) | `App/Overlay/OverlayAnimator.swift` | `var style: OverlayStyle`, `var layer: CALayer`, `func show()`, `func set(mode:)`, `func step(dt:level:)`, `var isFinished: Bool`, `func setContentsScale(_:)` |
| `OverlayAnimatorFactory` | same file | `static func make(style:reduceMotion:) -> any OverlayAnimator`: `.constellation` → `ConstellationAnimator`, else `StyleAnimator` |
| `ConstellationAnimator` | same file | Wraps `ConstellationSimulation` + `ConstellationLayer`; the code now in `OverlayPanelController.step` |
| `StyleAnimator` | same file | Wraps `StyleSimulation` + `StyleLayer` |
| `CardChrome` | `App/Overlay/CardChrome.swift` | Static drawing shared by both layers, extracted from `ConstellationLayer`: rounded card background, bottom-right label, centred error text |
| `StyleLayer: CALayer` | `App/Overlay/StyleLayer.swift` | Draws a `StyleFrame` from copied buffers; no implicit actions |
| `OverlayPanelController` (modified) | existing | Holds `style` and the current animator; `setStyle(_:)` stores; `show(on:)` rebuilds the animator when the stored style differs from the animator's, swapping the sublayer |
| `OverlayPreviewView: NSView` + `OverlayPreview: NSViewRepresentable` | `App/Settings/OverlayPreview.swift` | Hosts an animator's layer, runs `DisplayLinkDriver` + `PreviewScript`; starts on window attach, stops on detach/dismantle; `style` change rebuilds and restarts |
| `OverlayStyleCatalog` | `App/Settings/OverlayStyleCatalog.swift` | Display order, title and one-line summary per style; `isDefault` |
| `OverlaySection` | `App/Settings/OverlaySection.swift` | The pane of §5.4 |
| `SettingsModel` (modified) | existing | `Section.overlay`; `var overlayStyleRows`; `func setOverlayStyle(_:) async` |
| `AppDelegate` (modified) | existing | Keeps `overlay: OverlayPanelController?`; `apply(config)` calls `overlay?.setStyle(config.overlayStyle)` and logs a change |

Why this split: the sampler is a pure function (the mockup's tests port straight onto it); the
simulation owns time and smoothing without drawing; the layer draws without deciding anything;
the animator is the one seam the panel and the preview share, so the preview cannot drift from
the card. `Choreography` and `LevelSmoother` are extracted rather than duplicated so the existing
constellation tests keep pinning both.

### 5.2 Data model

`config.json` gains one key:

```json
"overlay_style": "soft_meter"
```

Raw values: `constellation`, `silk_ribbon`, `resonant_halo`, `soft_meter`, `liquid_pearl`,
`petal_iris`. Absent → `soft_meter`. Unknown → `soft_meter` at runtime, raw kept in
`unrecognisedOverlayStyle` and written back until `overlayStyle` is set (the `didSet` clears it).
`encode` writes `overlayStyle.rawValue`, or the unrecognised raw when present. `validated()` needs
no change. No migration: existing files simply lack the key. Lifetime: as long as the file.

New `Constants` (all in `Constants.swift`, "Styles" and "Preview" sections):

| Name | Value | Source |
|---|---|---|
| `stylePointCapacity` | 480 | aperture: 6 × 80 |
| `styleBlendRate` | 9.0 s⁻¹ | mockup `blend` |
| `styleCheckSeconds` | 0.35 | mockup done `show` |
| `reduceMotionSampleTime` | 1.3 | mockup reduced `time` |
| `styleMarkWhite` | (244, 248, 255) | mockup stroke colour |
| `previewLoopSeconds` | 13.0 | §3.13 |
| `previewStartingSeconds` | 2.0 | mockup sequence |
| `previewRecordingSeconds` | 6.0 | mockup sequence |
| `previewProcessingSeconds` | 3.5 | mockup sequence |
| `previewVoiceLevel` | 0.65 | mockup slider default |

### 5.3 Motion model (`StyleSampler`)

Coordinates are the mockup's: origin top-left of the 300×300 card, y down, motion centred on
(150, 140). `e = phase == .speaking ? clamp(level, 0, 1) : 0`; `processing = phase == .processing`;
`t` is the simulation's free-running time. `.quiet` is `.speaking` at `e = 0`, as in the source.
`.done` emits no points; the layer draws the check.

| Style | Points | Geometry (per point) | Alpha |
|---|---|---|---|
| Silk ribbon | 3 layers × 120, `u = i/119` | `x = 40 + 220u`; `env = sin(πu)^1.3`; `amp = processing ? 12 : 3 + 53e`; `φ = processing ? 2.4t : 1.8t`; `y = 140 + sin(3πu − φ + 0.22·layer)·amp·env + (layer − 1)·3·env` | layer 0/1/2: .23 / .95 / .35 |
| Resonant halo | 2 layers × 180, `a = 2πi/179` | `ripple = 7e·sin(3a − 2.2t) + 3e·cos(5a + t)`; `r = processing ? 54 + 7·layer : 43 + 24e + 1.7·sin(1.5t) + 5·layer + ripple`; `(150 + r·cos a, 140 + r·sin a)` | processing: `.15 + .8·max(0, cos(a − 1.7t − .5·layer))^8`; else layer 0 .88, layer 1 .24 |
| Soft meter | 15 | `x = 73 + 11i`, `y = 140`; `centre = sin((i+1)π/16)^1.3`; `syllable = .28 + .72·(.5 + .5·sin(7t − .63i))²`; `scan = (.5 + .5·sin(.53i − 3t))^5`; `height = processing ? 7 + 27·scan : 5 + 105·e·centre·syllable` | processing: `.3 + .65·scan`; else .82 |
| Liquid pearl | 180, `a = 2πi/179` | `spin = t·(processing ? 1.5 : .7)`; `r = (processing ? 44 : 29 + 27e) + (processing ? 4 : 2 + 6e)·sin(3a − spin) + 3e·cos(5a + spin)`; `(150 + r·cos a, 140 + r·sin a)`; `glowX = 139 + 7·sin(.8t)` | .85 |
| Petal iris | 6 layers × 80, `a = 2πi/79` | `rot = layer·π/3 + (processing ? .65t : .08·sin(.5t))`; `open = processing ? .5 : e`; `px = 13 + (1 − cos a)(17 + 19·open)`; `py = sin a·(7 + 9·open)`; `(150 + px·cos rot − py·sin rot, 140 + px·sin rot + py·cos rot)` | `.25 + .55·(.5 + .5·sin(a + t + layer))` |

`pointCount`: 360, 360, 15, 180, 480. Every point stays inside x ∈ [5, 295], y ∈ [5, 275] for
all phases, `t ∈ {0, 1.3, 20, 500}` and `level ∈ {0, .5, 1}` (tested).

### 5.4 Interfaces

**`OverlayAnimator`** (§5.1) is the only contract between the card/preview hosts and a style.
`OverlayPanelController` keeps `UIEventRouter`'s existing calls unchanged.

**Settings → Overlay pane**, as [Overlay — Side by side](./mockups/mockup-v3-side-by-side.html)
(https://claude.ai/code/artifact/60f53ea3-1a05-4730-be1a-fcf59ccc80e6):

- Sidebar: `Section.overlay` between `.history` and `.sound`; title "Overlay"; symbol
  `sparkles.rectangle.stack`.
- `SettingsPane(title: "Overlay")` containing an `HStack(alignment: .top, spacing: 12)`:
  - Left, width 214: a `VStack(spacing: 5)` of radio rows in `GeneralSection.engineRow`'s form
    (a `Button(.plain)` with `largecircle.fill.circle` / `circle`, title in body text). The
    selected row shows its summary as a `.caption` secondary line beneath the title and a
    "Default" capsule (`.caption2`, accent border) trails Soft meter. Order:
    Soft meter, Silk ribbon, Resonant halo, Liquid pearl, Petal iris, Constellation.
  - Right, 316×316: a `RoundedRectangle(cornerRadius: 12)` filled with
    `Color(nsColor: .underPageBackgroundColor)` (the mockup's flat `#dfe3e8` well in light
    appearance, the system's darker equivalent in dark) with a 1 pt `separatorColor` border,
    the `OverlayPreview(style:)` 300×300 centred inside.
- Footnote (`SettingsFootnote`): "The card appears beside the text field you are dictating into.
  The preview replays a short dictation with a simulated voice."
- Titles and summaries (`OverlayStyleCatalog`):

| Style | Title | Summary |
|---|---|---|
| `softMeter` | Soft meter | Fifteen rounded strokes. Familiar audio feedback, softened and kept compact. |
| `silkRibbon` | Silk ribbon | Three fine strands breathe as one. The smallest visual footprint of the set. |
| `resonantHalo` | Resonant halo | A thin, imperfect circle. Voice becomes a change in contour, not a burst. |
| `liquidPearl` | Liquid pearl | One luminous, fluid body. A soft centre of gravity instead of a field of marks. |
| `petalIris` | Petal iris | Six tapered loops form an open centre. A mechanical rhythm with an organic outline. |
| `constellation` | Constellation | A connected field of particles. Organic, spatial, and deliberately restless. |

**`SettingsModel`**: `struct OverlayStyleRow: Identifiable { style, title, summary, isDefault }`;
`var overlayStyleRows: [OverlayStyleRow]` (catalog order); `var selectedOverlayStyle: OverlayStyle
{ config.overlayStyle }`; `func setOverlayStyle(_ style: OverlayStyle) async { await write {
$0.overlayStyle = style } }`.

**`OverlayPanelController`**: `init(style: OverlayStyle, reduceMotion: Bool)`;
`func setStyle(_ style: OverlayStyle)`.

**`PreviewScript`** (`t` in seconds since loop start, wrapped modulo 13):

| Interval | `mode(at:)` | Level |
|---|---|---|
| [0, 2) | `.starting` | 0 |
| [2, 8) | `.recording` | `simulatedRMS(t)` |
| [8, 11.5) | `.processing` | 0 |
| [11.5, 13) | `.result` | 0 |

`simulatedRMS(t) = levelFloor + previewVoiceLevel · phrase(t) · (levelCeil − levelFloor)` so that
`normalisedLevel(rms:)` returns `0.65 · phrase(t)`;
`phrase(t) = (.18 + .82·√(.5 + .5·sin(2.05t))) · (.55 + .45·sin²(8.2t))`, the mockup's
"natural pauses". The result mode finishes on its own at 11.88 s (`isFinished`), after which the
host draws nothing until 13 s, then calls `show()` again.

### 5.5 Rendering (`StyleLayer`, `CardChrome`)

`StyleLayer.update(_ frame: StyleFrame)` copies the geometry into a buffer allocated once
(capacity `stylePointCapacity`) plus the scalars, then `setNeedsDisplay()`. `draw(in:)`:

1. `guard cardAlpha > 0`; translate by `offsetX`; `CardChrome.drawCard` (black, alpha
   `0.7 · cardAlpha`, radius 20) — the code now in `ConstellationLayer.draw`.
2. If `contentVisible`: inside a saved state, flip to mockup space
   (`translateBy(0, 300)`, `scaleBy(1, −1)`), then by phase and style:
   - `.done`: stroke the check (139,140)→(147,148)→(163,130), width 2, round caps and joins,
     white alpha `0.9 · checkProgress · cardAlpha`.
   - Silk ribbon / Resonant halo / Petal iris: polylines in runs of 120 / 180 / 80 points; each
     segment stroked in `styleMarkWhite` at the end point's alpha × `cardAlpha`; width 1.2 for
     the ribbon, 1 otherwise; round caps.
   - Soft meter: each point a vertical stroke from `y − height/2` to `y + height/2`, width 5,
     round caps, `styleMarkWhite` at the point's alpha × `cardAlpha`.
   - Liquid pearl: clip to the closed polygon through all points, then
     `drawRadialGradient` with the layer's one `CGGradient` (created in `init`; stops (0, white
     .95), (.45, (235,243,255) .65), (1, (205,225,250) .05)) from centre (`glowX`, 126) r 3 to
     (150, 140) r 76, then stroke the polygon white .45 width .8; all × `cardAlpha`.
   Then, unflipped, `CardChrome.drawLabel` (11 pt monospaced digits, bottom-right 12/10 pt in).
3. Else if `errorText` non-empty: `CardChrome.drawError` (14 pt medium, centred, 20 pt margins,
   nudged 30 pt down), unchanged from today.

`ConstellationLayer` keeps its own dot/link drawing and calls `CardChrome` for the three shared
pieces. Both layers override `action(forKey:)` to return nil.

### 5.6 Control flow

**Card, happy path.** `AppDelegate.startNormal` builds `OverlayPanelController(style:
config.overlayStyle, reduceMotion:)` and keeps the reference. `UIEvent.starting` →
`router.present()` → `overlay.show(on:)`: if `animator.style != style`, remove the old sublayer,
`OverlayAnimatorFactory.make(style:reduceMotion:)`, add its layer; set `contentsScale`; `level = 0`;
`animator.show()`; `animator.step(dt: 0, level: 0)`; order front; start the driver. Each tick:
`animator.step(dt:level:)`; `if animator.isFinished { hide() }`. `.recording`, `.processing`,
`.result`, `.error` → `animator.set(mode:)` exactly as today.

**`StyleSimulation.step(dt:level:)`.** Clamp `dt` to `maxTimestep`; `choreography.advance(dt)`;
`time += dt` (frozen at `reduceMotionSampleTime` under Reduce Motion); if mode is `.recording`,
`level = smoother.update(rms:)` (snap to `normalisedLevel` under Reduce Motion), else the smoother
holds its value as the constellation does; `phase = StylePhase(mode)`; if `phase != .done`,
`StyleSampler.sample(style, time, level, phase, into: &sample)` and blend `current` toward
`sample` with `1 − exp(−styleBlendRate·dt)` (1 under Reduce Motion, or when `count` changed);
`checkProgress = phase == .done ? min(modeTime / styleCheckSeconds, 1) : 0` (1 under Reduce
Motion); fill the frame from the choreography (`cardAlpha`, `shakeOffset` → `offsetX`,
`contentVisible`, `label`, `errorText`). `isFinished` is the choreography's.

**Style change.** `ConfigStore.update` yields → `AppDelegate.apply(config)` →
`overlay?.setStyle(config.overlayStyle)`; when the value differs from the stored one, log
`Overlay style: <raw>`. The next `show()` swaps the animator.

**Settings.** Selecting Overlay renders `OverlaySection`; `OverlayPreview(style:
model.selectedOverlayStyle)` → `makeNSView` creates `OverlayPreviewView`, which on
`viewDidMoveToWindow` (non-nil window) builds the animator, calls `show()`, and starts a
`DisplayLinkDriver` on itself. Each tick: `loopTime += dt`; `mode = PreviewScript.mode(at:
loopTime.truncatingRemainder(dividingBy: 13))`; when `loopTime` wraps, `animator.show()`; when
`mode` differs from the last applied, `animator.set(mode:)`; `animator.step(dt:, level:
PreviewScript.simulatedRMS(at:))`; the view draws nothing between `isFinished` and the wrap
(the card alpha is already 0). Clicking a row → `Task { await model.setOverlayStyle(style) }` →
`write` → `config` updates → `updateNSView` sees a new style → rebuild animator, `loopTime = 0`,
`show()`. `refresh(from:)` covers external edits. Leaving the pane → `dismantleNSView` → stop;
window close → view leaves the window → `viewDidMoveToWindow` with nil → stop.

### 5.7 Failure and edge cases

- **Unknown `overlay_style`**: runtime Soft meter, raw preserved on save; the pane shows Soft
  meter selected; choosing any row overwrites the raw value (R2).
- **`overlay_style` of the wrong JSON type**: `decodeIfPresent(String.self)` throws → the whole
  file is treated as corrupt by `readFromDisk` exactly as any other mistyped key is today; no
  new behaviour.
- **Style changed while the card is visible**: current animation continues; the new style
  appears at the next show (R3).
- **Reduce Motion toggled while running**: as today, read once at launch; the preview reads it
  at view creation.
- **`dt` spikes**: clamped to 50 ms in the simulation and the driver, as today; a blend factor of
  `1 − e^(−0.45)` cannot overshoot.
- **Preview left running with Settings hidden**: the driver stops when the view leaves its
  window; `NSView.displayLink` also pauses while the view is not on a screen.
- **Two previews** (pane re-rendered): each `OverlayPreviewView` owns its driver; the old one is
  dismantled before the new one starts.
- **Result mode with Reduce Motion**: check at full strength immediately, fades with the card.
- **Error mode in a new style**: shake for 0.45 s with the style's marks drawn, then marks hidden
  and the message shown for the rest of the 3 s, then hide, identical to the constellation.
- **Level while not recording**: the smoother holds; new styles read `e = 0` in every phase but
  speaking, so a stale level cannot leak into processing.
- **Config written by the correction window while the pane is open**: `refresh(from:)` updates
  `config`, the radio list re-renders, the preview restarts if the style changed.

### 5.8 Security

The only input is `overlay_style` from a user-writable file; it is decoded into a closed enum and
anything else falls back to the default. No secrets, no network, no new permissions, no
privileged operations. The preview never touches the microphone.

### 5.9 Performance

Per frame, a new style computes at most 480 points (petal iris) with a handful of trig calls
each, blends them, and strokes at most 480 segments; the constellation already strokes up to 276
links plus 24 arcs, so the budget is unchanged in kind. Buffers (`StyleGeometry` sample and
current, the layer's copy) are allocated once per animator, and the pearl's `CGGradient` once
per layer: only its start centre changes per frame, and that is a parameter of
`drawRadialGradient`, not of the gradient. The
preview costs one 300×300 layer at the display's rate while the pane is visible and nothing
otherwise. Animators are rebuilt only on a style change.

### 5.10 Observability

`Log.ui.info("Overlay style: <raw>")` when `apply(config)` sees a changed style, and once at
start with the initial style. No metrics. A wrong or missing render is visible in the preview
itself, which is the user-facing check.

### 5.11 Compatibility / migration

Older builds and the Python line ignore `overlay_style` and preserve it (F2 round-trip). No data
migration. Existing installs switch to Soft meter on update, by decision; the CHANGELOG entry
says so and names Settings → Overlay as the way back. CLAUDE.md's module map gains the
`MWConfig → MWOverlaySim` edge and lists the new `MWOverlaySim` types.

### 5.12 Testing strategy

TDD per component; every duration on injected `dt`.

- **`MWOverlaySimTests/OverlayStyleTests`**: six cases, raw values, `default == .softMeter`.
- **`LevelSmootherTests`**: the values `ConstellationSimulationTests.audioLevelMapping` pins
  (0.6, 0.84, 0.84·0.92), reset.
- **`ChoreographyTests`**: fade-in 120 ms in 30 ms steps, result hold + fade, error shake profile
  and 3 s finish, `contentVisible` after 0.45 s, labels, Reduce Motion no-shake — the same
  numbers the constellation suite asserts, so the extraction is behaviour-preserving.
- **`ConstellationSimulationTests`**: unchanged and must still pass unmodified.
- **`StyleSamplerTests`** (port of `animation-studies.test.cjs`): point counts; every new style's
  spread at level 1 exceeds level 0 by > 8 % in speaking; processing ignores level and differs
  between t = 2 and t = 3; quiet ignores level; every point finite and inside [5, 295]×[5, 275]
  for all phases, `t ∈ {0, 1.3, 20, 500}`, `level ∈ {0, .5, 1}`; done emits zero points;
  pearl `glowX` follows `139 + 7·sin(.8t)`.
- **`StyleSimulationTests`**: mode→phase mapping; level smoothing matches `LevelSmoother`; blend
  converges (after 1 s at 60 Hz within 1e−3 of the sample); a mode change glides (first frame
  after the switch lies between old and new); `checkProgress` 0→1 over 0.35 s and 1 at once under
  Reduce Motion; Reduce Motion freezes time at 1.3 and snaps level; dt clamp; `isFinished`
  timings equal the constellation's; frame capacity constant across `show()`.
- **`PreviewScriptTests`**: mode boundaries at 0, 2, 8, 11.5, 13 (wrap); `simulatedRMS` maps
  through `normalisedLevel` to `0.65·phrase(t)`; phrase in (0, 1].
- **`MWConfigTests/ConfigCodingTests`**: absent key → `.softMeter`; each raw value round-trips;
  unknown value → `.softMeter` and re-encoded verbatim; setting the style clears it; encode
  writes the key sorted with the rest.
- **`AppTests/StyleLayerRenderTests`**: for each new style, 600 scripted frames through every
  mode (the `ConstellationLayerRenderTests` script) draw without error into a bitmap that is
  non-empty; buffer identity stable across draws.
- **`AppTests/ConstellationLayerRenderTests`**: unchanged.
- **`AppTests/OverlayAnimatorTests`**: `make` returns a `ConstellationAnimator` for
  `.constellation` and a `StyleAnimator` otherwise; `isFinished` propagates.
- **`AppTests/OverlayPreviewViewTests`**: adding the view to a window starts its driver and
  calls `show()`; removing it stops the driver; a style change rebuilds the animator and resets
  `loopTime`; stepping 13 s of injected `dt` wraps and calls `show()` again.
- **`AppTests/OverlayStyleCatalogTests`**: six rows in the accepted order, non-empty title and
  summary for every case, exactly one `isDefault`.
- **`AppTests/SettingsModelTests`**: `Section.allCases` order has `.overlay` between `.history`
  and `.sound` with the title and symbol; `setOverlayStyle` writes `overlay_style` and updates
  `selectedOverlayStyle`; `refresh(from:)` with a different style updates the selection;
  `overlayStyleRows` matches the catalog.
- **Acceptance (manual)**: pick each style in Settings and confirm the preview matches the
  corresponding card in `mockup-v1-animation-studies.html`; dictate and confirm the card uses the
  chosen style; delete `overlay_style` from `config.json` and confirm Soft meter; set it to
  `nonsense`, confirm Soft meter and that the value survives a save until a row is clicked;
  enable Reduce Motion and confirm static frames per phase.

## 6. Alternatives considered

- Defining `OverlayStyle` in `MWConfig` and having `MWOverlaySim` depend on `MWConfig` — rejected:
  it would pull config, Keychain and JSON into the leaf animation module; the reverse edge is
  the smaller one.
- One `Frame` type for every style — rejected: dots-and-links and point-runs share nothing but
  the chrome; a union type would force each layer to ignore half of it.
- Re-implementing the mockup's level smoothing (attack 18 s⁻¹, decay 4 s⁻¹) for the new styles —
  rejected: the app's per-tick one-pole is already tuned to the microphone's buffer rate and
  keeps every style on the same envelope (R7).
- Live style swap while the card is visible — rejected by the user: next show is enough.
- Preview driven by the real microphone — rejected by the user: no controls, no mic.
- A longer completion hold so the check reads — rejected by the user: dismiss timing stays.
- Writing `constellation` into existing configs on first load so upgraders keep today's look —
  rejected by the user: everyone gets Soft meter.
- Mockup alternatives: [Stacked list](./mockups/mockup-v3-stacked-list.html)
  (https://claude.ai/code/artifact/bca5207e-e447-40c0-9be4-48ca49249913) — full preview on a
  stage above a list with descriptions; rejected because the pane would scroll.
  [Thumbnail grid](./mockups/mockup-v3-thumbnail-grid.html)
  (https://claude.ai/code/artifact/5c92586c-9483-43b7-b696-6ece77241c91) — six live tiles as
  the picker; rejected because it offers no full-size view of the chosen style.

## 7. Risks and issues

- **Fidelity drift from the mockup** (medium likelihood, medium impact): a transcription slip in
  any formula changes the look. Mitigation: §5.3 is the formula table the tests are written
  from, the cjs assertions are ported one-for-one, and acceptance compares each preview against
  the mockup side by side.
- **Preview display link outliving the pane** (medium, low): a stray link costs a few percent
  CPU. Mitigation: stop on window detach and on dismantle, tested by `OverlayPreviewViewTests`
  (§5.12): start on attach, stop on detach.
- **Untracked spec files** (high, low): the animation-studies mockup and its test are not in git;
  a checkout elsewhere has no spec. Mitigation: Stage 1 of the plan commits both files.
- **`Choreography` extraction changing constellation behaviour** (low, high): mitigated by
  leaving `ConstellationSimulationTests` untouched and green.
- **Check mark barely readable at 260 ms** (certain, low): accepted by decision; the preview
  shows it as it will ship.
- **Module-map edge** (low, low): `MWConfig → MWOverlaySim` is new; CLAUDE.md is updated in the
  same change.

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

Single release, no flag. Stage order for the plan: (1) commit the spec files; (2) `OverlayStyle`
+ config round-trip; (3) `LevelSmoother` and `Choreography` extraction with the constellation
suite green; (4) `StyleSampler` with the ported tests; (5) `StyleSimulation` + `PreviewScript`;
(6) `CardChrome`, `StyleLayer`, animators, panel controller; (7) Settings section, catalog,
preview view; (8) AppDelegate wiring, CHANGELOG, CLAUDE.md. Rollback is removing the key's
effect: an older build ignores `overlay_style`. The CHANGELOG entry under Unreleased/Added names
the six styles, the new default and Settings → Overlay.

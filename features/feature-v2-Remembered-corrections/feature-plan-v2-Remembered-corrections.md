# Remembered corrections — Implementation Plan v2

**Status:** Draft
**Date:** 2026-09-05
**Design:** [feature-design-v2-Remembered-corrections.md](./feature-design-v2-Remembered-corrections.md)

## Overview

This plan builds remembered corrections in thirteen stages, bottom-up along the module
dependency edges the repo already enforces. Four stages land the pure value layer — the two
new `config.json` keys in `MWConfig`, then the new `MWCorrections` package target in three
cohesive slices (matching and validation; hint resolution and per-engine serialisation; tally,
impact preview and prompt text). Three stages wire that layer into the request paths that
already exist: the batch `prompt` field and cleanup blocks, then engine hints on every
streaming engine, then the pipeline's press-time snapshot, deterministic rule application and
`DeliveredDictation` event. Three stages build the user surfaces: the correction window's model
under full TDD, its view plus the menu and History entry points, then the Settings → Vocabulary
groups. The last three cover the measurement: the harness, the gated live run that settles
SpeechAnalyzer's hint label, and the documentation. Every stage leaves both suites green and
both targets building, and the feature is inert until the user remembers a first correction, so
no stage needs a flag. The plan maps 1:1 to design §3 — every requirement R1–R39 and N1–N5
appears in the coverage map below — and follows design §9's implementation order, split finer
where a stage would otherwise be too large to review in one sitting.

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

**Swift's first red is a build error.** A stage that introduces a brand-new type, module or
protocol requirement cannot reach a red *assertion* first: the test target fails to compile
before any `#expect` runs. That is the legitimate first red for this project. Each such stage
records the compile error as its expected initial failure, scaffolds the minimal empty API, and
re-confirms red as assertion failures before implementing.

### Commands and observed baseline

| Layer | Command | Baseline observed 2026-09-05 |
|---|---|---|
| Core package tests | `cd Packages/MiniWhisperCore && swift test` | `✔ Test run with 353 tests in 38 suites passed` |
| One module's suite | `cd Packages/MiniWhisperCore && swift test --filter MWConfigTests` | — |
| Core package build | `cd Packages/MiniWhisperCore && swift build` | `Build complete!`, exit 0 |
| App build + tests | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` | `✔ Test run with 70 tests in 14 suites passed` + `** TEST SUCCEEDED **` |

Both baselines are green, so every stage's "confirm no regressions" step has a clean starting
point. Swift Testing output is preceded by an XCTest line `Executed 0 tests, with 0 failures` —
that is the empty XCTest bundle; read the `✔ Test run with N tests in M suites …` line.

**Registration is explicit in this repo.** A new source file under an existing target is picked
up automatically, but a new *target* must be added to `Packages/MiniWhisperCore/Package.swift`
(`targets:` **and** `products:`) or it silently never compiles, and a new package product the
app imports must be added to `project.yml`'s `MiniWhisper` target dependency list and picked up
by a fresh `xcodegen generate`. Every file-creating stage below carries the registration step it
needs. App sources under `App/` and `AppTests/` are folder-sourced and need no manifest edit.

### Test locations and their siblings

| New test file | Existing sibling it follows |
|---|---|
| `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/*Tests.swift` | `Packages/MiniWhisperCore/Tests/MWProfilesTests/PromptComposerTests.swift` |
| `Packages/MiniWhisperCore/Tests/MWStreamingTests/HintMeasurementTests.swift` | `Packages/MiniWhisperCore/Tests/MWStreamingTests/SpeechAnalyzerLiveTests.swift` |
| `AppTests/CorrectionModelTests.swift` | `AppTests/ProfilesEditorModelTests.swift` |
| `AppTests/CorrectionsEditorModelTests.swift` | `AppTests/SettingsModelTests.swift` |

`MWCorrectionsTests` is a new test target: it is registered in `Package.swift` in Stage 2, with
`MWTestSupport` as its second dependency exactly as every other test target has. `AppTests` is
an existing xcodebuild-hosted bundle whose files use `@testable import MiniWhisper`; both new
files there sit at the right layer and reach the model types under test without any bootstrap.

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: `corrections` array in `config.json` with the six rule fields | Stage 1 |
| R2: `correction_tally` array, cap 200 | Stage 1 (storage), Stage 4 (increment/top/eviction) |
| R3: both keys are known keys, never in `extra`, round-trip through save | Stage 1 |
| R4: load/save validation — trim, collapse, drop empties, keep-first duplicates | Stage 1 |
| R5: save rejects empty Heard/Write, no-change, same-scope duplicate | Stage 2 (validator), Stage 8 (window), Stage 10 (Settings) |
| R6: NFC + trim + whitespace-collapse normalisation; `write` stored as typed | Stage 1 |
| R7: literal whole-phrase matching with Unicode boundaries | Stage 2 |
| R8: Heard and every Sounds-like are match targets; replacement is `write` | Stage 2 |
| R9: single pass, longest-then-app-then-stored-order, no cascade | Stage 2 |
| R10: app-scoped rule suppresses the global rule for the same variant | Stage 2 |
| R11: disabled rules take part in nothing | Stage 2 (matching), Stage 3 (hints/report), Stage 4 (tally `hasRule`) |
| R12: one immutable `CorrectionSnapshot` per recording, plus the press-time app | Stage 7 |
| R13: streaming hints for the press app; batch/cleanup/rules for the release app | Stage 7 |
| R14: rules applied exactly once, after cleanup, before paste/history/`.result` | Stage 7 |
| R15: the live caption is never changed by rules | Stage 7 |
| R16: `.result` carries the delivered text, app name and bundle ID | Stage 7 |
| R17: resolved hint list order and dedupe | Stage 3 |
| R18: SFSpeechRecognizer `contextualStrings`, first 100 | Stage 3 (cap), Stage 6 (request) |
| R19: SpeechAnalyzer `AnalysisContext.contextualStrings[.general]`, first 100 | Stage 3 (cap), Stage 6 (session), Stage 12 (label) |
| R20: OpenAI Realtime `keywords` with the four characters removed | Stage 3 (filter), Stage 6 (open message) |
| R21: Speechmatics `additional_vocab` with `sounds_like`, caps and skips | Stage 3 (entries), Stage 6 (open message) |
| R22: ElevenLabs receives no hints; the report says so | Stage 3 (report row), Stage 6 (adapter untouched) |
| R23: batch multipart field `prompt`; `instructions` no longer sent | Stage 4 (text), Stage 5 (request) |
| R24: cleanup prompt preserve-terms and known-corrections blocks | Stage 4 (text), Stage 5 (composition) |
| R25: empty hints leave every request shape byte-for-byte unchanged | Stage 5, Stage 6 |
| R26: no log line carries a hint term, rule phrase or transcript | Stage 5, Stage 6, Stage 7 |
| R27: "Correct Last Dictation…" under the Last row, works with retention 0 | Stage 9 |
| R28: "Correct…" on each History row | Stage 9 |
| R29: selection snaps outward to whole words and resets Write/Sounds like | Stage 8 |
| R30: scope defaults to This app, disabled without a bundle ID | Stage 8 |
| R31: preview and impact line, with the history-off wording | Stage 4 (compute), Stage 8 (model) |
| R32: Copy / Cancel / Save semantics, confirmation state, tally once | Stage 8 |
| R33: Settings Corrections, Often corrected and Recognition hints groups | Stage 3 (report data), Stage 10 (UI) |
| R34: detail-form commit, persistence and in-place validation messages | Stage 10 |
| R35: Remember… opens the window with the tallied phrase, scope All apps | Stage 10 |
| R36: a rule saved from the window appears in an open Settings table | Stage 10 |
| R37: opt-in measurement suite, per-engine reports under `measurements/` | Stage 11 (harness), Stage 12 (run) |
| R38: SpeechAnalyzer's label decided by the measurement; dead path removed | Stage 12 |
| R39: README and CHANGELOG describe the change | Stage 13 |
| N1: bundle ID, macOS 14, Swift 6 strict concurrency, no third-party deps | every stage (enforced by the unchanged `project.yml` and `Package.swift` settings) |
| N2: every timing on the injected clock; no test sleeps | Stage 6, Stage 7, Stage 9 |
| N3: rule application adds no network call and stays well under a millisecond | Stage 2 (guard test), Stage 7 |
| N4: Settings never gains a second consumer of `ConfigStore.changes` | Stage 10 |
| N5: TDD — each behaviour gets a failing test before its implementation | every stage |

### Requirements delivered across several stages

Each of these is split deliberately, and the state after every contributing stage is a working
system; none should be bundled.

- **R2 (tally)** — Stage 1 stores and round-trips the key; Stage 4 adds increment, eviction and
  top-five. After either stage the tally is still empty in practice, because nothing increments it
  until the correction window's model exists (Stage 8). Bundling Stage 4 into Stage 1 would double
  the size of the config stage for no earlier visible behaviour.
- **R5 (validation)** — Stage 2 builds the validator, Stage 8 applies it in the correction window,
  Stage 10 in the Settings detail form. The two surfaces are separate stages by construction; the
  validator is shared, so neither surface can drift.
- **R18–R22 (per-engine hints)** — Stage 3 fixes the caps, filters and skip reasons as values;
  Stage 6 puts them in the requests. Nothing user-visible changes at either point, because the
  controller still resolves `.none` until Stage 7; the requests are proven by contract test in
  Stage 6 and go live in Stage 7.
- **R23/R24 (prompts)** — Stage 4 fixes the exact text, Stage 5 puts it in the request. R23 and
  R24 are fully live and user-visible after Stage 5.
- **R31 (impact preview)** — Stage 4 computes it, Stage 8 drives it from the model, Stage 9
  renders it.
- **R33 (Settings groups)** — Stage 3 produces the report rows, Stage 10 renders all three groups.
- **R37/R38 (measurement)** — Stage 11 builds the harness, Stage 12 runs it and applies the
  verdict. Stage 12 is gated on a clip set that does not exist in the repository, so it cannot be
  bundled into Stage 11.

## Stages

### Stage 1 — Correction rules and tally in `config.json`

**Goal:** `Config` carries `corrections` and `correction_tally` as typed, validated, round-tripping keys.
**Design references:** §3 R1–R4, R6; §5.2; §5.9
**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWConfig/CorrectionRule.swift`
- create `Packages/MiniWhisperCore/Sources/MWConfig/CorrectionTallyEntry.swift`
- create `Packages/MiniWhisperCore/Sources/MWConfig/PhraseKey.swift`
- modify `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`
- modify `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`
- modify `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigStoreTests.swift`

**Steps (TDD):**
1. Write tests. In `ConfigCodingTests.swift`: `decodesCorrectionsAndTally` (a JSON body with both
   keys decodes to typed values, `bundle_id: null` becoming `nil`); `correctionDefaultsOnDecode`
   (absent `id` gets a UUID, absent `sounds_like` gets `[]`, absent `enabled` gets `true`);
   `correctionsRoundTripWithExplicitNullBundleID`; `correctionKeysNeverLandInExtra`;
   `malformedTallyTimestampDecodesAsDistantPast`; `validatedNormalisesAndDropsInvalidRules`
   (leading/trailing space and doubled inner spaces collapsed, empty `heard` or `write` dropped,
   empty `sounds_like` values dropped, two same-scope rules with the same normalised `heard`
   keeping the first, the same `heard` under two different scopes both kept);
   `phraseKeyNormalisesAndLowercases` (NFC composition, trim, whitespace collapse, `key` lowercased).
   In `ConfigStoreTests.swift`: `unrelatedKeysSurviveACorrectionsEdit` (an `extra` key and
   `usage` are intact after `update { $0.corrections = [...] }`).
   Expected initial failure: the `MWConfigTests` target fails to build with
   `error: cannot find 'CorrectionRule' in scope`, `cannot find 'PhraseKey' in scope` and
   `value of type 'Config' has no member 'corrections'`.
2. Run `cd Packages/MiniWhisperCore && swift test --filter MWConfigTests` — confirm the build
   errors above. Add empty `CorrectionRule`, `CorrectionTallyEntry` and `PhraseKey` declarations
   plus the two `Config` stored properties, re-run, and confirm red as assertion failures
   (decoded arrays empty, `validated()` a no-op) before implementing.
3. Implement. `CorrectionRule.swift`: `public struct CorrectionRule: Equatable, Sendable, Codable`
   with `id`, `heard`, `write`, `soundsLike`, `bundleID`, `enabled`; `CodingKeys` mapping
   `soundsLike = "sounds_like"` and `bundleID = "bundle_id"`; a custom `init(from:)` supplying
   the three defaults and throwing only when `heard` or `write` is missing; a custom `encode(to:)`
   writing `bundle_id` as an explicit `null`, mirroring `HistoryEntry.encode(to:)`.
   `CorrectionTallyEntry.swift`: `heard`, `count`, `last`, with `last` written through a private
   `ISO8601DateFormatter` configured `[.withInternetDateTime]` (MWHistory's equivalent is
   internal to that module) and a malformed value decoding to `Date.distantPast`.
   `PhraseKey.swift`: `normalised` (trim, `precomposedStringWithCanonicalMapping`, collapse
   internal whitespace runs to one space) and `key` (`normalised` lowercased).
   `Config.swift`: two stored properties defaulting to `[]`, `Key.corrections = "corrections"`
   and `Key.correctionTally = "correction_tally"` added to `Key.all`, decode and encode branches
   beside `profiles`, and the R4 rules inside `validated()`.
4. Run `swift test --filter MWConfigTests` — confirm pass. Run `swift test` (expect 353 plus the
   new cases, no pre-existing test changed) and `swift build` — confirm no regressions.

**Definition of done:**
- `swift test --filter MWConfigTests` green; full `swift test` green; `swift build` exit 0.
- A `config.json` containing both keys survives load → save unchanged apart from key sorting.
- Neither key appears in `Config.extra`.
- `validated()` enforces R4 on both the load and the save path.

**Risks specific to this stage:** `validated()` runs on every `ConfigStore.load()` and every
`update`, so an over-eager R4 rule would silently drop a rule the user just typed. R5's validator
(Stage 2) is the user-facing guard that keeps R4 from ever being the first thing a user meets;
the duplicate test above pins keep-first rather than drop-both.

### Stage 2 — `MWCorrections`: phrase matching, scope resolution, validation

**Goal:** A new pure module that decides which rules apply to a delivery app and rewrites a transcript with them.
**Design references:** §3 R5, R7–R11, N3; §5.1; §5.3 (Matching); §5.5 (overlaps, boundaries, possessives)
**Touches:**
- modify `Packages/MiniWhisperCore/Package.swift` (target, product, test target, `MWTestSupport` dependency)
- modify `project.yml` (`MiniWhisper` gains `product: MWCorrections`)
- modify `CLAUDE.md` (module map row for `MWCorrections`)
- create `Packages/MiniWhisperCore/Sources/MWCorrections/ResolvedRule.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/CorrectionResolver.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/PhraseMatcher.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/CorrectionApplier.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/CorrectionValidator.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/CorrectionResolverTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/PhraseMatcherTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/CorrectionApplierTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/CorrectionValidatorTests.swift`

**Steps (TDD):**
1. Write tests. `PhraseMatcherTests` — R7: `chari` does not match inside `charity`, `mark` does
   not match inside `bookmark`, `eefa's` matches `eefa` (apostrophe is a boundary), a doubled
   space or newline between the phrase's words still matches, `e-mail` matches literally,
   matching is case-insensitive, a digit or underscore adjacent to the phrase blocks the match,
   a combining mark adjacent to the phrase blocks the match. `CorrectionResolverTests` — R10/R11:
   only enabled rules whose `bundleID` is nil or equal come back, app rules first, a global rule's
   variant is dropped when an app rule owns the same normalised key while its other variants
   survive, disabled rules contribute nothing, stored order is preserved within a scope.
   `CorrectionApplierTests` — R8/R9: a single replacement, several in one text, the write is
   verbatim, a variant fires the same replacement as the heard phrase, `get hub actions` with both
   `get hub` and `get hub actions` yields the longer, an equal-length app and global candidate
   yields the app one, an equal-length equal-scope pair yields the earlier stored rule, a rule
   whose `write` equals another rule's `heard` does not cascade, a case-only fix applies, empty
   rules are the identity, `replacements` counts accepted ranges. Add the N3 guard test
   `hundredsOfRulesStayUnderAMillisecond` — 300 rules over a 1,200-character transcript, asserted
   against a generous wall-clock ceiling (characterization guard; it names the regression it
   guards: an accidental per-match regex recompile). `CorrectionValidatorTests` — R5: each of
   `.emptyHeard`, `.emptyWrite`, `.noChange` and `.duplicate` with its exact `message`, a
   case-only fix passing, and exclude-self returning nil when editing the rule in place.
   Expected initial failure: `error: no such module 'MWCorrections'` from every new test file.
2. Run `cd Packages/MiniWhisperCore && swift test --filter MWCorrectionsTests` — confirm the
   missing-module error. Register the target, product and test target in `Package.swift`, add the
   `product: MWCorrections` line to `project.yml`, add empty declarations for the five types,
   re-run, and confirm red as assertion failures before implementing.
3. Implement. `ResolvedRule`: `{ rule: CorrectionRule; variants: [String]; isAppScoped: Bool }`.
   `CorrectionResolver`: filters by `enabled` and scope, orders app-scoped first then global in
   stored order, builds each rule's `variants` from `PhraseKey.normalised(heard)` plus each
   normalised `sounds_like` deduped by `PhraseKey.key`, and drops a global rule's variant whose
   key an app-scoped rule already owns. `PhraseMatcher`: one `NSRegularExpression` per variant,
   `(?<![\p{L}\p{M}\p{N}_])` + tokens escaped with `NSRegularExpression.escapedPattern(for:)`
   joined by `\s+` + `(?![\p{L}\p{M}\p{N}_])`, option `[.caseInsensitive]`; a compilation failure
   drops that variant and is surfaced as `Application.droppedVariants`, a count the caller logs —
   `MWCorrections` keeps the design's "no I/O" property and its single `MWConfig` dependency edge,
   so it never imports `MWSupport.Log`. `CorrectionApplier`: compiles one matcher per
   variant in `init`, normalises the input with `precomposedStringWithCanonicalMapping`, collects
   `(range, ruleIndex, isAppScoped, length)` for every variant of every rule, sorts by lower
   bound then longer-first then app-before-global then rule index, sweeps left to right accepting
   non-overlapping candidates, and splices `rule.write` for each, returning
   `Application { text, replacements, droppedVariants }`.
   `CorrectionValidator.validate(_:against:excluding:)` per R5.
4. Run `swift test --filter MWCorrectionsTests` — confirm pass. Run `swift test` and `swift build`;
   run `xcodegen generate && xcodebuild … build` to confirm the app target still builds with the
   new product listed.

**Definition of done:**
- `MWCorrections` and `MWCorrectionsTests` appear in `Package.swift` under both `products:` and `targets:`.
- `project.yml` lists `product: MWCorrections` and `xcodegen generate` regenerates cleanly.
- `CLAUDE.md`'s module map has an `MWCorrections` row reading "Correction rules, matching, hints" with dependency `MWConfig`.
- Every R7–R11 case above is a named test; the N3 guard test is green.
- Full `swift test` green and the app target builds.

**Risks specific to this stage:** the `\s+` join means a rule's inner whitespace matches a newline
run, so a phrase split across a line break is rewritten — intended by R7 but worth the explicit
test above so it is a decision rather than an accident.

### Stage 3 — `MWCorrections`: hint resolution, per-engine serialisation, report

**Goal:** The exact term list, per-engine payload values and skip reasons every engine and the Settings report will use.
**Design references:** §3 R11, R17–R22, R33, R38; §5.1; §5.5 (hint caps)
**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWCorrections/CorrectionSnapshot.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/RecognitionHints.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/HintResolver.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/HintSerializer.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/HintSupport.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/HintReport.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/HintResolverTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/HintSerializerTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/HintReportTests.swift`

**Steps (TDD):**
1. Write tests. `HintResolverTests` — R17: for one app rule and one global rule plus vocabulary,
   `terms` is `[appWrite, appHeard, appSoundsLike…, globalWrite, globalHeard, globalSoundsLike…,
   vocabulary…]`; duplicates by normalised key are removed keeping the first spelling; disabled
   rules and rules for another bundle ID contribute nothing; `rules` is in the same app-then-global
   order with each `soundsLike` deduped and the write excluded; `vocabulary` keeps stored order;
   an empty snapshot resolves to `.none`. `HintSerializerTests` — R18/R19: 120 hints yield 100
   sent and 20 skipped with reason `.overCap`, and app-scoped terms are never the ones dropped;
   R20: `<`, `>`, CR and LF are stripped from each keyword and a term that becomes empty is
   skipped with reason `.emptyAfterFilter`; R21: entries are one per rule as
   `{content: write, soundsLike: [heard, variants…]}` then one `{content: term}` per vocabulary
   term in app-then-global-then-vocabulary order, a `content` over six words is skipped with
   reason `.tooManyWords`, a word over 4,000 characters is skipped with reason `.wordTooLong`,
   a `sounds_like` value that would be skipped is dropped from its entry while the entry survives,
   and the list is capped at 1,000. `HintReportTests` — R22/R33/R38: one row per engine with its
   sent count and cap; ElevenLabs's row is `.notSent`; SpeechAnalyzer's row reflects
   `HintSupport.speechAnalyzer`; the batch row is `.prompt`; counts are computed over every
   enabled rule regardless of scope; disabled rules are excluded from the counts.
   Expected initial failure: `error: cannot find 'HintResolver' in scope` (and the same for the
   other four new types) in the three new files.
2. Run `swift test --filter MWCorrectionsTests` — confirm those errors. Scaffold the empty types,
   re-run, confirm red as assertion failures.
3. Implement. `CorrectionSnapshot { rules: [CorrectionRule]; vocabulary: [String] }` with
   `init(config: Config)`. `RecognitionHints { terms: [String]; rules: [HintRule]; vocabulary: [String] }`
   and `HintRule { write: String; soundsLike: [String] }`, plus `static let none`.
   `HintResolver.resolve(_:bundleID:)` building both from a `CorrectionResolver` pass.
   `HintSerializer` with `contextualStrings`, `openAIKeywords` and `speechmaticsVocab`, each
   returning `sent` plus `skipped: [(term, SkipReason)]`. `HintSupport` as
   `enum { case supported, unavailable(reason: String) }` with
   `static let speechAnalyzer: HintSupport = .unavailable(reason: "effect not yet measured")`.
   `HintReport.report(rules:vocabulary:support:)` returning the rows R33 renders.
4. Run `swift test --filter MWCorrectionsTests` — confirm pass. Run `swift test` and `swift build`.

**Definition of done:**
- The three caps (100, 100, 1,000) and the four skip reasons are each pinned by a named test.
- Every serializer preserves resolver order, so an app-scoped term is never the one dropped.
- `HintSupport.speechAnalyzer` is a single constant with the pre-measurement value.
- Full `swift test` green; `swift build` exit 0.

**Risks specific to this stage:** none.

### Stage 4 — `MWCorrections`: tally, impact preview, prompt sections

**Goal:** The remaining pure values the window, Settings and the prompts need.
**Design references:** §3 R2, R11, R23, R24, R31; §5.1; §5.2 (tally cap and eviction); §5.5
**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWCorrections/CorrectionTally.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/ImpactPreview.swift`
- create `Packages/MiniWhisperCore/Sources/MWCorrections/PromptSections.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/CorrectionTallyTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/ImpactPreviewTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/PromptSectionsTests.swift`

**Steps (TDD):**
1. Write tests. `CorrectionTallyTests` — R2: a first increment creates an entry with count 1 and
   the supplied `now`; a second increment of a differently-cased spelling of the same phrase
   raises the count and keeps the first-seen spelling; at 200 entries the 201st evicts the lowest
   `count`, and among equal counts the oldest `last`; `top(_:limit:rules:)` returns five rows
   ordered by count then most-recent `last`, with `hasRule` true when an enabled rule's `heard`
   *or* any `sounds_like` matches the tallied key and false when the only such rule is disabled.
   `ImpactPreviewTests` — R31: entries outside the rule's scope are excluded, `matching` and
   `total` are counted, at most three snippets are returned each ±30 characters around the first
   match with an ellipsis where truncated, and a nil entry list yields the history-off result.
   `PromptSectionsTests` — R23/R24: `vocabularyLine(terms:)` is exactly
   `Vocabulary (spell exactly as written): a, b, c` and nil for an empty list; `cleanupBlocks`
   emits exactly `\n\nPreserve these terms exactly as written: …` listing every `write` then every
   vocabulary term, and `\n\nKnown corrections — replace the exact phrase on the left with the
   spelling on the right:` followed by one `"variant" → "write"` line per variant in resolver
   order; each block is omitted when its input is empty; both empty yields no blocks.
   Expected initial failure: `error: cannot find 'CorrectionTally' in scope` and the same for the
   other two types.
2. Run `swift test --filter MWCorrectionsTests` — confirm those errors, scaffold, re-run, confirm
   red as assertion failures.
3. Implement the three types per §5.1, keying the tally on `PhraseKey.key(heard)`.
4. Run `swift test --filter MWCorrectionsTests` — confirm pass. Run `swift test` and `swift build`.

**Definition of done:**
- Tally eviction order (lowest count, then oldest `last`) is pinned by a named test.
- The two prompt blocks are asserted as exact strings, including the em-dash heading and the curly quotes.
- Full `swift test` green; `swift build` exit 0.

**Risks specific to this stage:** the prompt strings are compared byte-for-byte here and again in
Stage 5's composition tests; a wording change has to be made in both places, which the exact-string
assertions make loud rather than silent.

### Stage 5 — Batch `prompt` field and cleanup prompt blocks

**Goal:** The batch transcription request sends the documented `prompt` field and the cleanup prompt carries the preserve-terms and known-corrections blocks.
**Design references:** §3 R23–R26; §5.1 (`MWTranscription`, `MWProfiles`); §5.3 (Wire shapes); §5.9
**Touches:**
- modify `Packages/MiniWhisperCore/Package.swift` (`MWProfiles` and `MWPipeline` gain `MWCorrections`)
- modify `Packages/MiniWhisperCore/Sources/MWTranscription/OpenAIClient.swift`
- modify `Packages/MiniWhisperCore/Sources/MWProfiles/PromptComposer.swift`
- modify `Packages/MiniWhisperCore/Sources/MWPipeline/ProcessingJob.swift`
- modify `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeTranscriber.swift`
- modify `App/KeyedOpenAIClient.swift`
- modify `Packages/MiniWhisperCore/Tests/MWTranscriptionTests/OpenAIClientTests.swift`
- modify `Packages/MiniWhisperCore/Tests/MWTranscriptionTests/OpenAIIntegrationTests.swift`
- modify `Packages/MiniWhisperCore/Tests/MWProfilesTests/PromptComposerTests.swift`
- modify `Packages/MiniWhisperCore/Tests/MWPipelineTests/ProcessingJobTests.swift`

**This stage is atomic and exempt from stage-size splitting.** `instructions` and `prompt` are two
names for the same multipart field, and R23 says `instructions` is no longer sent, so the two
cannot coexist: the protocol rename, the request change, all four `Transcriber` conformers
(`OpenAIClient`, `KeyedOpenAIClient`, `FakeTranscriber` and the test-local `StalingTranscriber` in
`ProcessingJobTests`), the `ProcessingJob` call site and every test call site (eight in
`OpenAIClientTests`, one in `OpenAIIntegrationTests`) land together or the package does not
compile.

**Steps (TDD):**
1. Write tests. In `OpenAIClientTests.swift`, migrate the three field tests:
   `transcribeBuildsMultipartWithFileModelAndFormat` keeps `["file", "model", "response_format"]`;
   `transcribeIncludesPromptWhenNonEmpty` asserts `["file", "model", "response_format", "prompt"]`
   with the value verbatim; `transcribeOmitsPromptWhenEmpty` asserts the part list contains
   neither `prompt` nor `instructions`. In `PromptComposerTests.swift`: `transcribePrompt` returns
   the base alone with no terms and base + `\n\nVocabulary (spell exactly as written): …` with
   terms; `cleanupPrompt` returns the base alone with `.none` hints and no rules, and the base
   plus both R24 blocks in order with hints and rules. In `ProcessingJobTests.swift`: the batch
   path's recorded `FakeTranscriber` call carries the composed prompt including the vocabulary
   line, and the cleanup path's recorded prompt carries both blocks for the release app's rules.
   Expected initial failure: `#expect(parts.map(\.name) == ["file", "model", "response_format", "prompt"])`
   fails with the actual value `["file", "model", "response_format", "instructions"]`, and the
   `PromptComposer` tests fail to build with `error: incorrect argument labels in call (have
   'base:terms:', expected 'base:vocabulary:')`.
2. Run `swift test --filter MWTranscriptionTests` and `--filter MWProfilesTests` — confirm both
   failures above.
3. Implement. `Transcriber.transcribe(wav:prompt:)` and `OpenAIClient.transcribe` adding the
   multipart field `prompt` when non-empty and no longer adding `instructions`.
   `PromptComposer.transcribePrompt(base:terms:)` and `cleanupPrompt(base:hints:rules:)` built from
   `PromptSections`; `MWProfiles` gains the `MWCorrections` dependency in `Package.swift`.
   `ProcessingJob` builds `let snapshot = CorrectionSnapshot(config: input.config)`,
   `let releaseHints = HintResolver.resolve(snapshot, bundleID: input.target.bundleID)` and
   `let rules = CorrectionResolver(rules: snapshot.rules).rules(for: input.target.bundleID)`, and
   feeds both composers. Update `FakeTranscriber.Call.prompt`, `KeyedOpenAIClient`,
   `OpenAIIntegrationTests` and the test-local `StalingTranscriber` in `ProcessingJobTests` to the
   new label. No log line gains a term (R26).
4. Run both filtered suites — confirm pass. Run `swift test`, `swift build`, and
   `xcodegen generate && xcodebuild … test` — confirm no regressions in either suite.

**Definition of done:**
- No occurrence of the multipart field name `instructions` remains in `Sources/` or `Tests/`
  (`PromptFiles.transcribeInstructions()`, the *file* reader, is a different thing and stays).
- With no rules and no vocabulary the multipart body is byte-for-byte what it was before this
  stage apart from the `prompt` part being absent exactly as `instructions` was (R25).
- Both suites green; both targets build.

**Risks specific to this stage:** `transcribe_prompt.txt` now actually reaches the model, which
changes batch output for existing users — certain, low impact, and called out in Stage 13's
release note. The shipped default asks only for accurate punctuation and capitalisation, which
the model already does.

### Stage 6 — Engine hints on every streaming engine

**Goal:** Every hint-capable engine sends the resolved terms in the field its provider documents, and every request shape is unchanged when there are none.
**Design references:** §3 R18–R22, R25, R26, N2; §5.1 (`MWStreaming`); §5.3 (Wire shapes); §5.5 (hint caps, AnalysisContext rejected)
**Touches:**
- modify `Packages/MiniWhisperCore/Package.swift` (`MWStreaming` gains `MWCorrections`)
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/SpeechRecognitionAPI.swift` (`RecognitionOptions.contextualStrings`)
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/SFSpeechRecognitionBridge.swift`
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/SFSpeechEngine.swift`
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/SpeechAnalyzerAPI.swift` (`makeSession(locale:contextualStrings:)`)
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/SpeechAnalyzerBridge.swift`
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/SpeechAnalyzerEngine.swift`
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/Adapters/OpenAIRealtimeAdapter.swift`
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/Adapters/SpeechmaticsAdapter.swift`
- modify `Packages/MiniWhisperCore/Sources/MWStreaming/EngineProvider.swift`, `EngineFactory.swift`
- modify `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeEngineProvider.swift`, `FakeSpeechAnalyzerAPI.swift`
- modify `Packages/MiniWhisperCore/Sources/MWPipeline/DictationController.swift` (one call site, passing `.none`)
- modify `Packages/MiniWhisperCore/Tests/MWStreamingTests/SFSpeechEngineTests.swift`, `SpeechAnalyzerEngineTests.swift`, `CloudAdapterTests.swift`, `EngineFactoryTests.swift`

**This stage covers all four engines deliberately, and is exempt from stage-size splitting.**
Widening `EngineProvider.make` is what forces every engine construction site in `EngineFactory` to
change, so splitting the engines across two stages would leave the seam half-wired — a `hints`
parameter that the cloud branch accepts and drops — for a whole stage. The diff is wide but
shallow: each engine gains one stored property, one serialisation call at `start` and one field in
an existing request literal, and the work is one theme a reviewer holds in one sentence.

**Steps (TDD):**
1. Write tests. `SFSpeechEngineTests` — the request options recorded by `FakeSpeechRecognitionAPI.startOptions`
   carry the capped contextual strings, and `.none` hints leave `contextualStrings` empty.
   `SpeechAnalyzerEngineTests` — `FakeSpeechAnalyzerAPI` records the strings it was handed per
   session, `.none` records `[]`, and a fake whose context application throws leaves the engine
   running and producing its transcript (§5.5). `CloudAdapterTests` — the OpenAI `session.update`
   frame equals the exact JSON of §5.3 with `keywords` present, and is byte-for-byte today's
   frame with `.none`; the Speechmatics `StartRecognition` frame equals the exact JSON with
   `additional_vocab` (rule entries with their `sounds_like` arrays, then plain vocabulary
   entries), and is today's frame with `.none`; the ElevenLabs frames are unchanged even when
   hints are supplied. `EngineFactoryTests` — hints reach each engine type, observable through
   the fakes and the adapters' first sent message. A `CapturingLogSink` assertion that no emitted
   line contains a hint term (R26).
   Expected initial failure: the `MWStreamingTests` target fails to build with
   `error: extra argument 'hints' in call` and `value of type 'RecognitionOptions' has no member
   'contextualStrings'`.
2. Run `swift test --filter MWStreamingTests` — confirm those errors. Add the parameters with
   defaults but no behaviour, re-run, confirm red as assertion failures (recorded strings empty,
   frames missing `keywords`/`additional_vocab`).
3. Implement. `RecognitionOptions` gains `contextualStrings: [String] = []` as a defaulted
   initialiser parameter, so the two existing construction sites keep compiling.
   `SFSpeechRecognitionBridge` sets `request.contextualStrings` when non-empty.
   `SpeechAnalyzerAPI.makeSession(locale:contextualStrings:)`; the bridge's `Session` builds an
   `AnalysisContext`, sets `contextualStrings[.general]` and calls `analyzer.setContext(_:)`
   inside the analysis task before `analyzeSequence` when the list is non-empty, logging a thrown
   error at info level and continuing without hints. `SFSpeechEngine(api:clock:hints:)` and
   `SpeechAnalyzerEngine(api:locale:clock:hints:)` take `RecognitionHints = .none` and serialise
   through `HintSerializer` at `start`, logging `hints: N sent, K skipped`.
   `OpenAIRealtimeAdapter(apiKey:hints:)` adds `keywords` to the transcription object of its open
   message when non-empty; `SpeechmaticsAdapter(apiKey:hints:)` adds `additional_vocab` to
   `transcription_config` when non-empty. `EngineProvider.make(config:secrets:hints:)`;
   `EngineFactory` forwards to every engine it builds; `FakeEngineProvider` records the hints;
   `DictationController.startStream` passes `.none` for this stage.
4. Run `swift test --filter MWStreamingTests` — confirm pass. Run `swift test`, `swift build`,
   and `xcodegen generate && xcodebuild … test`.

**Definition of done:**
- Each of the four hint-capable engines has both an exact-payload test with hints and an
  unchanged-payload test without (R25).
- The four `SpeechAnalyzerAPI.makeSession` sites (protocol, bridge, fake, engine) and the four
  `EngineProvider.make` sites (protocol, factory, fake, controller) all compile against the new
  signatures with no shim left behind.
- No log line carries a term; the two engine log lines carry counts only.
- Both suites green; both targets build. Behaviour is unchanged end to end, because the
  controller still resolves `.none`.

**Risks specific to this stage:** `AnalysisContext.contextualStrings` is documented by Apple as
consumed by `DictationTranscriber`, not `SpeechTranscriber`, so this path may be inert. It is
written behind `HintSupport.speechAnalyzer` and Stage 12 removes it if the measurement says so;
until then it cannot fail a dictation, because a throwing `setContext` is logged and analysis
continues.

### Stage 7 — Press-time snapshot, rule application and `DeliveredDictation`

**Goal:** A recording captures one immutable snapshot at press, hints go to the engine for the press app, and the resolved rules rewrite the final text exactly once before it is delivered.
**Design references:** §3 R12–R16, R26, N2, N3; §5.1 (`MWPipeline`); §5.3 (Pipeline); §5.4 (Press, Release, Processing); §5.5
**Touches:**
- modify `Packages/MiniWhisperCore/Sources/MWPipeline/ControllerState.swift` (`RecordingSession.startTarget`, `.snapshot`)
- modify `Packages/MiniWhisperCore/Sources/MWPipeline/ProcessingInput.swift` (`snapshot`)
- modify `Packages/MiniWhisperCore/Sources/MWPipeline/UIEvent.swift` (`case result(DeliveredDictation)`)
- create `Packages/MiniWhisperCore/Sources/MWPipeline/DeliveredDictation.swift`
- modify `Packages/MiniWhisperCore/Sources/MWPipeline/DictationController.swift`
- modify `Packages/MiniWhisperCore/Sources/MWPipeline/ProcessingJob.swift`
- modify `App/UIEventRouter.swift`, `App/StatusItemController.swift`, `App/MenuModel.swift`
- modify `Packages/MiniWhisperCore/Tests/MWPipelineTests/DictationControllerTests.swift`, `ProcessingJobTests.swift`
- modify `AppTests/MenuModelTests.swift`

**Steps (TDD):**
1. Write tests. `DictationControllerTests` — R12/R13: the frontmost app is captured at press,
   before `.starting` has been consumed; the snapshot is taken at press and a config edit before
   release does not change it; `FakeEngineProvider` receives hints resolved for the *press* app;
   a release with a different frontmost app puts the release target and the press snapshot into
   `ProcessingInput`; a release that lands before `startStream` ran falls back to a snapshot built
   from the release config. All of these drive `VirtualClock` (N2). `ProcessingJobTests` — R14/R16:
   the corrected text reaches paster, history and `.result` on the streamed path with cleanup off
   and no key; on the batch path; on the cleanup path, where the rule is applied to the cleaner's
   output and not to its input; a nil bundle ID applies global rules only; an app switch between
   press and release excludes the previous app's rules; no matching rule leaves the text identical;
   `.result` carries the app name and bundle ID; a stale job at each checkpoint applies no rules.
   R15: the `.caption` events emitted during the recording are unaffected by a rule that matches
   the partial text. `MenuModelTests` — the existing initial-order and `setLast` tests adapted to
   the new payload with the row titles unchanged.
   Expected initial failure: the `MWPipelineTests` target fails to build with
   `error: value of type 'ProcessingInput' has no member 'snapshot'` and
   `error: cannot find 'DeliveredDictation' in scope`.
2. Run `swift test --filter MWPipelineTests` — confirm those errors. Scaffold the new type and
   fields, re-run, confirm red as assertion failures (uncorrected text delivered, hints `.none`).
3. Implement. `DeliveredDictation { text, appName, bundleID, engine, deliveredAt }`.
   `hotkeyPressed` records `startTarget = deps.frontmost.frontmost()` into the new
   `RecordingSession` synchronously, before `.starting` is emitted. `startStream` builds
   `snapshot = CorrectionSnapshot(config:)` and `hints = HintResolver.resolve(snapshot, bundleID:
   startTarget?.bundleID)`, stores the snapshot on the session and passes the hints to
   `deps.engines.make`. `stop` sets `ProcessingInput.snapshot = session.snapshot ?? CorrectionSnapshot(config: config)`.
   `ProcessingJob` resolves from `input.snapshot` instead of the Stage 5 local snapshot, and after
   the cleanup block and before checkpoint 3 applies
   `finalText = CorrectionApplier(rules: rules).apply(to: finalText).text`, logging
   `corrections: N replacement(s) from M rule(s)` only when `N > 0` and only as counts (R26).
   `.result` emits the `DeliveredDictation`. `UIEventRouter` forwards it to
   `StatusItemController.setLast(_:)`, which forwards to `MenuModel.setLast(_ dictation:)`;
   `MenuModel` stores `lastDictation` and derives `lastText`. The menu rows are unchanged in this
   stage.
4. Run `swift test --filter MWPipelineTests` — confirm pass. Run `swift test`, `swift build`, and
   `xcodegen generate && xcodebuild … test`.

**Definition of done:**
- The feature is functionally complete end to end for a rule that already exists in
  `config.json`: it fires on every path, once, for the right app.
- The three `.result` sites (job, router, pipeline test) compile against the new payload; the menu
  row titles are byte-identical to before.
- Both suites green; both targets build.

**Risks specific to this stage:** `hotkeyPressed` gains a synchronous `frontmost()` call on the
press path, which N1 keeps to one frame. It is the same call `stop` already makes at release, so
the cost is known; the `noPollingTimers` and press-latency tests in `DictationControllerTests`
stay green as the guard.

### Stage 8 — Correction window model

**Goal:** Every rule the correction window follows — snapping, prefill, preview, validation, impact, Copy, Save, tally — as a host-tested model with no view.
**Design references:** §3 R5, R29–R32; §5.1 (`App/Correction`); §5.4 (In the window); §5.5
**Touches:**
- create `App/Correction/CorrectionSource.swift`
- create `App/Correction/CorrectionModel.swift`
- create `AppTests/CorrectionModelTests.swift`

**Steps (TDD):**
1. Write tests in `AppTests/CorrectionModelTests.swift`, following `AppTests/ProfilesEditorModelTests.swift`
   for its fakes-in-the-file style and `@MainActor @Suite`. R29: a selection that starts and ends
   inside words snaps outward to whole words; a selection with surrounding whitespace is trimmed;
   an empty or whitespace-only selection leaves Heard empty; each new selection resets Write and
   Sounds like to the new Heard. R30: with a bundle ID the scope defaults to This app and the
   option shows the app name; without one, This app is disabled and All apps is selected. R31: the
   preview is the transcript with the draft rule applied; the impact counts only entries in scope,
   returns up to three snippets, and reads the history-off sentence when the entry list is nil.
   R32: Copy writes the previewed text to the fake pasteboard and never pastes or submits; Cancel
   writes nothing; Save with the Remember toggle off is disabled and persists nothing; Save
   persists exactly one rule with the chosen scope and only then enters the confirmation state; a
   failing `ConfigStore.update` shows `AnyError(error).description`, keeps the draft and does not
   enter the confirmation state; Copy then Save increments the tally exactly once. R5: each
   validation message appears in place and blocks the write, and a case-only fix is allowed.
   Expected initial failure: the `AppTests` target fails to build with
   `error: cannot find 'CorrectionModel' in scope`.
2. Run `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper
   -destination 'platform=macOS' -derivedDataPath .dd test` — confirm the build error. Scaffold
   `CorrectionSource` and an empty `CorrectionModel`, re-run, confirm red as assertion failures.
3. Implement. `CorrectionSource { text, appName, bundleID, preselectAll }` with initialisers from
   `DeliveredDictation`, `HistoryEntry` and a bare tally phrase. `CorrectionModel` as
   `@MainActor @Observable final class` with a `Dependencies` struct in the shape of
   `HistoryListModel.Dependencies` (config store, pasteboard, a `historyEntries` closure returning
   nil when retention is 0), the draft state, the snapping rule of §5.5, the derived preview and
   error, a cancellable impact task, and `copy()` / `save()` / `tallyOnce()` writing through
   `ConfigStore.update`.
4. Run the app test command — confirm pass. Run `swift test` and `swift build` to confirm the core
   package is untouched.

**Definition of done:**
- Every R29–R32 clause and every R5 message is a named test in `AppTests/CorrectionModelTests.swift`.
- No view type exists yet; the model is reachable and green without one.
- App suite green (70 + the new cases); core suite unchanged.

**Risks specific to this stage:** the impact task is cancelled and restarted on every draft
change, so a slow history read could deliver a stale result. The tests drive it with an
immediately-returning fake; the model tags each task with the draft it was started for and
discards a result whose draft no longer matches.

### Stage 9 — Correction window UI, menu entry and History action

**Goal:** The user can open the correction window from the menu bar's last dictation and from any History row.
**Design references:** §3 R27, R28, R30; §5.1 (App); §5.3 (UI surfaces, mockups); §5.4 (Correct last, Correct from History)
**Touches:**
- create `App/Correction/CorrectionView.swift`, `App/Correction/CorrectionWindowController.swift`
- modify `App/MenuModel.swift` (`.correctLast` action and its row)
- modify `App/StatusItemController.swift` (`onCorrectLast`)
- modify `App/History/HistoryListModel.swift` (`Row.appName`, `Row.bundleID`, `Dependencies.correct`, `func correct(_:)`, `engineLabel` promoted from `private static` to an internal shared helper)
- modify `App/History/HistoryView.swift` (the Correct… button between Paste and Copy)
- modify `App/AppDelegate.swift` (composition: window controller, `openCorrection`, the two closures)
- modify `AppTests/MenuModelTests.swift`, `AppTests/HistoryListModelTests.swift`

**Category: hybrid.** The menu model and the history list model are host-testable and follow the
full TDD cycle below. The SwiftUI view, the `NSTextView` selection bridge and the window
controller are **platform-only / UI wiring** — they cannot run under the AppTests host — and are
verified by the app build plus the named manual checks in this stage's definition of done.

**Steps (TDD, host-testable portion):**
1. Write tests. `MenuModelTests` — R27: with no delivered dictation neither the Last row nor the
   Correct row is present; after the first `setLast` the rows read
   `[Today, Month, Last: "…", Correct Last Dictation…, separator, History..., Settings...,
   separator, About Mini Whisper, Quit]` with the Correct row's action `.correctLast` at index 3;
   a second `setLast` updates in place rather than inserting a second pair.
   `HistoryListModelTests` — R28: `Row` carries the entry's `appName` and `bundleID`, and
   `correct(row)` calls `deps.correct` with a `CorrectionSource` carrying the row's text, app name
   and bundle ID.
   Expected initial failure: `AppTests` fails to build with
   `error: type 'MenuItem.Action' has no member 'correctLast'`.
2. Run the app test command — confirm that error. Scaffold the enum case and the `Row` fields,
   re-run, confirm red as assertion failures (row absent, `correct` unimplemented).
3. Implement. `MenuItem.Action.correctLast` and the row inserted directly after the Last row;
   `StatusItemController` gains an `onCorrectLast` initialiser closure and a `case .correctLast`
   arm in `handle(_:)` — the only exhaustive switch over `MenuItem.Action` in the app.
   `HistoryListModel.Row` gains the two fields, `Dependencies` gains
   `correct: @MainActor (CorrectionSource) -> Void`, and `engineLabel` becomes internal so the
   window's source line can reuse it rather than re-deriving the labels.
4. Run the app test command — confirm pass. Run `swift test` and `swift build`.

**Integration-verified remainder:** build `CorrectionView` (560×520, the source line, the
read-only selectable `NSTextView` in an `NSViewRepresentable` reporting selection to the model,
the Heard/Write/Sounds-like grid, the scope segmented control, the Remember toggle, the preview
box, the impact line and the Copy · Cancel · Save footer, plus the confirmation state) and
`CorrectionWindowController` (one reused instance, `NSHostingView`, activation-policy toggling and
`EditMenu.ensure()`, exactly as `HistoryWindowController` does), then wire both in `AppDelegate`.
Verification command: `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme
MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd build`, followed by the manual
checks below on the built app.

**Definition of done:**
- The two host-tested models are green and the menu row order matches §5.3 exactly.
- App builds; both suites green.
- Manual, on the built app: dictate, open Correct Last Dictation…, select a phrase, see it snap
  and the preview update, Save, dictate the same phrase to the same app and see it corrected;
  dictate it to a different app and see it untouched; open Correct… from a History row; set
  history retention to 0 and confirm the menu route still opens with the fixed impact sentence;
  tab through the window and confirm keyboard navigation reaches every control.

**Risks specific to this stage:** bridging a read-only selectable `NSTextView` into SwiftUI and
reporting its selection reliably is the fiddly part. Every rule that depends on the selection lives
in `CorrectionModel` and is already tested from Stage 8, so a bridging bug shows up as "the model
never received a selection", not as wrong rule behaviour.

### Stage 10 — Settings → Vocabulary: corrections table, tally and hint report

**Goal:** Every rule is visible and editable in Settings, with the often-corrected list and the per-engine hint report beside it.
**Design references:** §3 R33–R36, N4; §5.1 (`App/Settings`); §5.3 (Vocabulary pane); §5.4 (Settings)
**Touches:**
- create `App/Settings/CorrectionsEditorModel.swift`, `App/Settings/CorrectionsEditor.swift`
- modify `App/Settings/VocabularySection.swift`, `App/Settings/VocabularyModel.swift` (`replace(terms:)`)
- modify `App/Settings/SettingsModel.swift` (`let corrections`, `refresh(from:)`, `Dependencies.openCorrection`)
- modify `App/AppDelegate.swift` (`apply(config)` also calls `settings?.model.refresh(from: config)`)
- create `AppTests/CorrectionsEditorModelTests.swift`
- modify `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write tests. `CorrectionsEditorModelTests`, following `AppTests/ProfilesEditorModelTests.swift`
   — R33/R34: `rows` render Heard, Write, Scope and Enabled for each stored rule in stored order;
   editing a field persists through `ConfigStore.update`; an edit that violates R5 shows the
   message in place and writes nothing, leaving the stored rule as it was; the Enabled switch and
   the − button persist; `tallyRows` are the top five with counts and `hasRule`; `hintRows` come
   from `HintReport` and reflect `HintSupport.speechAnalyzer`; R35: Remember… calls
   `deps.openCorrection` with a source whose transcript is the tallied phrase, fully preselected,
   scope All apps; R36: `refresh(config)` replaces the rows from a config the model did not write.
   `SettingsModelTests` — `refresh(from:)` updates both the vocabulary terms and the corrections
   rows, and N4: `SettingsModel` subscribes to nothing — a grep-backed assertion is not possible
   in a test, so this is pinned by the definition of done below instead.
   Expected initial failure: `AppTests` fails to build with
   `error: cannot find 'CorrectionsEditorModel' in scope`.
2. Run the app test command — confirm that error. Scaffold the model, re-run, confirm red as
   assertion failures.
3. Implement. `CorrectionsEditorModel` mirroring `ProfilesEditorModel`'s table-plus-detail-form
   shape: `rows`, `selection`, an `edit(id:)` that validates through `CorrectionValidator` before
   persisting `store.update { $0.corrections = rules }` or setting `error`, `remove`, the tally
   rows and the hint rows. `CorrectionsEditor.swift` renders the three groups per §5.3 with the
   scope popup built from `AppListing.runningApps()` and `AppChooser`, exactly as the profiles
   editor's Add… menu does. `VocabularyModel.replace(terms:)`; `SettingsModel` owns
   `let corrections`, gains `refresh(from:)` and the `openCorrection` dependency;
   `VocabularySection` composes the four groups; `AppDelegate.apply(config)` calls
   `settings?.model.refresh(from: config)`.
4. Run the app test command — confirm pass. Run `swift test` and `swift build`.

**Definition of done:**
- Every R33–R36 clause is a named test.
- N4 holds by construction: `grep -rn "configStore.changes\|store.changes" App` returns exactly
  the one `AppDelegate` consumer it returns today.
- App builds; both suites green.
- Manual: with Settings open, save a rule from the correction window and see the table update
  without reopening Settings.

**Risks specific to this stage:** a detail-form text field whose edit is uncommitted when a
config-change refresh lands could lose the in-flight text. §5.5 records the resolution — refresh
replaces model state, not the SwiftUI drafts, which recommit on Return — and the
`refresh(config)` test asserts the model state, not the field.

### Stage 11 — Measurement harness

**Goal:** A runnable, opt-in suite that transcribes a user-provided clip set hints-off and hints-on per engine and writes a per-engine report.
**Design references:** §3 R37; §5.3 (Measurement manifest); §5.4 (Measurement)
**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWTestSupport/HintMeasurement.swift` (manifest decoding, hit counting, report rendering)
- create `Packages/MiniWhisperCore/Tests/MWStreamingTests/HintMeasurementTests.swift` (the opt-in suite)
- create `Packages/MiniWhisperCore/Tests/MWStreamingTests/HintMeasurementReportTests.swift` (the host-testable half)

**Category: hybrid.** Manifest decoding, hit counting and report rendering are pure values and
follow the full TDD cycle. The suite that drives real engines against real audio is
**integration-verified**: it cannot run without a clip set and provider keys, and its verification
command is named below.

**Steps (TDD, host-testable portion):**
1. Write `HintMeasurementReportTests`: the manifest JSON of §5.3 decodes to rules, vocabulary and
   clips with `control` defaulting to false; hit counting is case-insensitive and counts a target
   term once per occurrence in the pre-rule transcript; a control clip's rule firings are counted
   from the applier's `replacements`; the rendered markdown has one row per clip with the
   hints-off count, hints-on count and rule firings, a totals row, and the SpeechAnalyzer verdict
   line; the report contains no audio and no file path outside the report directory.
   Expected initial failure: `MWStreamingTests` fails to build with
   `error: cannot find 'HintMeasurementManifest' in scope`.
2. Run `swift test --filter HintMeasurementReportTests` — confirm that error, scaffold, re-run,
   confirm red as assertion failures.
3. Implement `HintMeasurement.swift` in `MWTestSupport` (manifest types, `hits(in:targets:)`,
   `render(_:)`), and `HintMeasurementTests.swift` as
   `@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1" &&
   ProcessInfo.processInfo.environment["MW_HINT_AUDIO_DIR"] != nil))`, following
   `SpeechAnalyzerLiveTests`' gating style and its `AVAudioFile` feeding loop. Per available
   engine — SFSpeechRecognizer; SpeechAnalyzer on macOS 26 with the model installed; OpenAI
   Realtime and batch with `OPENAI_API_KEY`; Speechmatics with `SPEECHMATICS_API_KEY` — it runs
   each clip twice, once with `RecognitionHints.none` and once with
   `HintResolver.resolve(snapshot, bundleID: nil)`, and writes
   `features/feature-v2-Remembered-corrections/measurements/<engine>-<YYYY-MM-DD>.md`. The report
   directory is derived from `#filePath` up to the package's parent, overridable with
   `MW_HINT_REPORT_DIR`. No audio is written anywhere and no provider key is written or logged.
4. Run `swift test --filter HintMeasurementReportTests` — confirm pass. Run `swift test` and
   confirm the opt-in suite is skipped (no `MW_INTEGRATION` in the environment) and the count is
   unchanged apart from the new report tests.

**Integration-verified remainder:** the live suite itself. Verification command:
`MW_INTEGRATION=1 MW_HINT_AUDIO_DIR=<dir> swift test --filter HintMeasurementTests`, run in
Stage 12 once the clip set exists.

**Definition of done:**
- `swift test` with no environment variables set leaves the live suite skipped and CI unaffected.
- The report renderer is fully host-tested with no engine running.
- Both suites green.

**Risks specific to this stage:** a test that writes into the repository is unusual here. It
writes only under the feature folder's `measurements/`, only when explicitly opted in, and the
path is asserted by the renderer test.

### Stage 12 — Run the measurement and settle SpeechAnalyzer's hint label

**Goal:** The per-engine hint effect is measured and recorded, and SpeechAnalyzer's label — and its code path — reflect the result.
**Design references:** §3 R37, R38; §5.8; §7 (SpeechAnalyzer risk); §9
**Category: external prerequisite (gated).** This stage consumes a clip set and provider
credentials that do not exist in the repository, so it opens with a gate check rather than
implementation steps.
**Touches:**
- create `features/feature-v2-Remembered-corrections/measurements/<engine>-<YYYY-MM-DD>.md` (one per engine run)
- modify `Packages/MiniWhisperCore/Sources/MWCorrections/HintSupport.swift`
- conditionally modify `Packages/MiniWhisperCore/Sources/MWStreaming/SpeechAnalyzerAPI.swift`, `SpeechAnalyzerBridge.swift`, `SpeechAnalyzerEngine.swift`, `Sources/MWTestSupport/FakeSpeechAnalyzerAPI.swift` and `Tests/MWStreamingTests/SpeechAnalyzerEngineTests.swift` (only if the verdict is `.unavailable`)

**Steps:**
1. **Gate check.** Confirm the clip set exists: `ls "$MW_HINT_AUDIO_DIR/manifest.json"` and at
   least one target clip plus one control clip. Confirm which engines can run: macOS 26 with the
   speech model installed for SpeechAnalyzer, `OPENAI_API_KEY` for OpenAI Realtime and batch,
   `SPEECHMATICS_API_KEY` for Speechmatics. If the clip set is absent, stop here and report it —
   R38 cannot be answered without it and no code below may be guessed.
2. Run `MW_INTEGRATION=1 MW_HINT_AUDIO_DIR=<dir> swift test --filter HintMeasurementTests` once
   per available engine's credentials, and read the written reports.
3. Commit the reports under `measurements/`.
4. Apply the verdict. If hints-on recognises more target terms than hints-off across the set with
   no more false corrections, set
   `HintSupport.speechAnalyzer = .supported` and keep the `AnalysisContext` path. Otherwise set
   `.unavailable(reason: "<measured reason>")` and delete the `AnalysisContext` path outright:
   the `contextualStrings` parameter on `SpeechAnalyzerAPI.makeSession`, the context construction
   in `SpeechAnalyzerBridge.Session`, the hints argument on `SpeechAnalyzerEngine`, the recording
   in `FakeSpeechAnalyzerAPI`, and the three `SpeechAnalyzerEngineTests` cases that pin it —
   adjusting those tests before the deletion so the suite stays green throughout
   (behaviour-preserving deletion).
5. Run `swift test`, `swift build`, and `xcodegen generate && xcodebuild … test`.

**Definition of done:**
- One committed report per engine actually run, with per-clip counts, totals and, for
  SpeechAnalyzer, the verdict line.
- `HintSupport.speechAnalyzer` holds the measured value and is the only place it is stated in code.
- If the verdict is `.unavailable`, `grep -rn "AnalysisContext\|contextualStrings" Packages/MiniWhisperCore/Sources/MWStreaming`
  returns only the SFSpeechRecognizer occurrences.
- Both suites green; both targets build; no audio file is committed.

**Risks specific to this stage:** the clip set is user-provided and may not exist when the rest of
the plan lands, and cloud runs cost the user's own credits. Stage 13's README wording is written
from whatever this stage measures, so the two stages ship together; if the set never materialises,
the feature ships with `HintSupport.speechAnalyzer` at its pre-measurement value and the label
saying so, which is a truthful statement rather than a broken one.

### Stage 13 — README and CHANGELOG

**Goal:** The documented behaviour matches what ships, including the two facts that change for existing users.
**Design references:** §3 R39; §5.9; §9 (Communication)
**Category: non-TDD (config-only).** Documentation edits with nothing host-assertable.
**Touches:**
- modify `README.md` (a Corrections and vocabulary section, plus one Privacy line)
- modify `CHANGELOG.md` (the `## [Unreleased]` block)

**Steps:**
1. `README.md` gains a short section covering: rules are deterministic and hints are
   probabilistic; per-engine hint support as Stage 12 measured it, naming SFSpeechRecognizer,
   SpeechAnalyzer, OpenAI Realtime, Speechmatics, the batch request and the cleanup prompt, and
   stating that ElevenLabs receives no hints in this version; scope semantics (This app vs All
   apps). The Privacy section gains one line: correction rules and the tally of corrected phrases
   are stored locally in `~/.config/mini-whisper/config.json` and are never sent anywhere except
   as recognition hints to the engine the user selected.
2. `CHANGELOG.md` `## [Unreleased]` gains an Added entry for remembered corrections and the
   Settings groups, and a Changed entry for the batch transcription request moving from the
   undocumented `instructions` field to the documented `prompt` field — noting that a customised
   `transcribe_prompt.txt` now reaches the model for the first time.
3. Verification: re-read both files against §3 R39's five points and against
   `HintSupport.speechAnalyzer`'s committed value, so the README and the constant agree (R38).

**Definition of done:**
- All five R39 points appear in `README.md`.
- The CHANGELOG's Unreleased block names the `prompt` change and the two new config keys.
- The README's SpeechAnalyzer statement matches `HintSupport.speechAnalyzer`.

**Risks specific to this stage:** none.

## Cross-cutting concerns

- **Security.** Rules, variants and vocabulary are user-typed data in a user-owned file, never
  secrets, and never logged: the only new log lines are `hints: N sent, K skipped` (Stage 6) and
  `corrections: N replacement(s) from M rule(s)` (Stage 7), both counts only, both pinned by R26
  assertions in their stage. Every phrase reaching a provider is encoded by `JSONEncoder` (the
  WebSocket adapters) or as a multipart text part (`prompt`) — never concatenated into JSON — and
  OpenAI's four forbidden characters are stripped before encoding (Stage 3). Every regex token is
  escaped with `NSRegularExpression.escapedPattern(for:)` (Stage 2), so a phrase can never become a
  pattern. No hint reaches a URL. Keychain access is unchanged, and the measurement suite reads
  provider keys from the environment exactly as the existing integration tests do (Stage 11). The
  stage order opens no insecure window: hints only leave the machine from Stage 6, by which point
  Stage 3's filters and caps are already in place and tested.
- **Performance.** `HintResolver` and `CorrectionResolver` are O(rules) at press and release;
  `CorrectionApplier` compiles one regex per variant once per job. N3's ceiling is pinned by the
  guard test in Stage 2 and re-exercised end to end in Stage 7. Press latency gains one
  synchronous `frontmost()` call in Stage 7 — the same call release already makes. Payload sizes
  are bounded by the caps of Stage 3; config growth is bounded by the 200-entry tally cap
  (Stage 1) and the user's own rule count. The impact preview (Stages 4 and 8) runs on a
  cancellable background task over the already-in-memory history.
- **Observability.** Two new log lines, both counts (Stages 6 and 7); a `Log.config` error on a
  failed rule or tally write (Stages 8 and 10); a `Log.ui` error when the impact preview or Copy
  fails (Stage 8). The Settings Recognition hints group (Stage 10) is the user-visible report of
  what each engine actually receives, and the committed measurement reports (Stage 12) are the
  record of whether it helped.
- **Compatibility / migration.** No migration: both new keys default to empty, older builds of
  this app carry them through `Config.extra`, and the Python app round-trips them as unknown dict
  keys (`config.py`'s `save` dumps the whole dict — verified). The batch field rename is the one
  user-visible behaviour change and lands atomically in Stage 5 with its release note in Stage 13.
  Four shared signatures widen — `Transcriber.transcribe` (Stage 5, six conformers and call sites),
  `EngineProvider.make` and `SpeechAnalyzerAPI.makeSession` (Stage 6, four sites each),
  `UIEvent.result` (Stage 7, three sites) — each small enough to land with its stage and each with
  every site listed in that stage's *Touches*. `RecognitionOptions` gains a defaulted parameter
  rather than a new initialiser, so its two construction sites are untouched. Rollback at any
  point after Stage 7 is disabling or deleting the rules, or removing the two keys from
  `config.json`.

## Verification

Once every stage is complete, the acceptance criteria of design §3 are confirmed as follows.

1. **Automated.** `cd Packages/MiniWhisperCore && swift test` — green, with the new
   `MWCorrectionsTests` suite present. `xcodegen generate && xcodebuild -project "Mini
   Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test`
   — `** TEST SUCCEEDED **`. `swift build` — exit 0.
2. **Request contracts.** The exact-JSON tests in `CloudAdapterTests`, the multipart tests in
   `OpenAIClientTests` and the request-options tests in `SFSpeechEngineTests` /
   `SpeechAnalyzerEngineTests` are the proof required by R17–R25, each with an empty-hints twin
   proving R25.
3. **Measurement.** One committed report per engine under
   `features/feature-v2-Remembered-corrections/measurements/`, and
   `HintSupport.speechAnalyzer` matching the SpeechAnalyzer report's verdict line and the README.
4. **Manual, on the built app** (design §5.10's list):
   menu → Correct Last Dictation… → select → Save → the next dictation to the same app is
   corrected; a dictation to another app is not; Correct… from a History row opens the same
   window with that entry's app; disabling a rule stops it firing from the next recording and
   deleting it removes it; a rule saved while Settings is open appears in the table without
   reopening Settings; the window is fully keyboard-navigable; with history retention 0 the menu
   route still works and the impact line reads "History is off — no preview of past dictations";
   on the on-device engine with no cloud key and cleanup off, rules still apply to the raw text.

## Risks and open issues

- **The clip set for Stage 12 does not exist yet.** R37 and R38 cannot be answered without a
  user-provided `MW_HINT_AUDIO_DIR`. Mitigation: Stage 12 opens with an explicit gate check and
  stops rather than guessing; `HintSupport.speechAnalyzer` ships with a truthful pre-measurement
  value if the set never arrives, and every other engine's hint support is proven by contract
  tests that need no audio.
- **`AnalysisContext.contextualStrings` may be inert for `SpeechTranscriber`.** Apple documents it
  as consumed by `DictationTranscriber`. Mitigation: the path is written so a throwing
  `setContext` is logged and analysis continues, so it can never fail a dictation; Stage 12
  deletes it if the measurement says it does nothing.
- **An ordinary word in a rule silently rewrites correct text.** Mitigation, in the plan's order:
  whole-phrase matching with Unicode boundaries (Stage 2, with the `charity` and `bookmark`
  tests), per-app scope (Stage 2), the impact preview before saving (Stages 4 and 8) and the
  Enabled switch (Stage 10).
- **`Config.validated()` runs on every load and every save.** An R4 rule that is stricter than R5
  would silently drop a rule the user just typed and the user would see it vanish from the table.
  Mitigation: Stage 1's tests pin keep-first rather than drop-both for duplicates, and Stage 2's
  validator rejects at the point of entry so R4 is never the first thing a user meets.
- **Two writers of `config.json`.** The Python app and this app already race on `usage`; the new
  keys add no new exposure. A lost rule edit is visible in the Settings table and can be redone.
- **The exact prompt strings are asserted in two places.** `PromptSectionsTests` (Stage 4) and
  `PromptComposerTests` (Stage 5) both pin them byte-for-byte, so a wording change costs two
  edits. Accepted deliberately: the composition test is what proves the blocks reach the request
  in the right order, and the section test is what proves the text.

## Planning decisions taken

1. **`PhraseKey` lives in `MWConfig`, not `MWCorrections`.** `Config.validated()` implements R4
   and R6, and `MWConfig` cannot import `MWCorrections` without inverting the module dependency
   the design itself fixes; `MWCorrections` reaches it through its `MWConfig` dependency, so there
   is still one implementation. Design §5.1 corrected in place.
2. **`RecognitionHints` carries an ordered `rules: [HintRule]` plus `vocabulary: [String]` instead
   of `pronunciations: [String: [String]]`.** R21 fixes the order of `additional_vocab` entries
   (app rules, then global, then vocabulary) and distinguishes rule entries from vocabulary
   entries, and `SpeechmaticsAdapter(apiKey:hints:)` receives only `RecognitionHints`; a Swift
   dictionary has no order and cannot make that distinction. The numbered requirement wins over
   the §5.1 sketch. Design §5.1 corrected in place; no wire shape changes.
3. **`ResolvedRule` is defined as `{ rule: CorrectionRule; variants: [String]; isAppScoped: Bool }`.**
   §5.1 used the type in three signatures without defining it. Design §5.1 corrected in place.
4. **`PromptComposer` stays a `struct`.** §5.3's interface sketch wrote `public enum
   PromptComposer`; the existing declaration is `public struct PromptComposer` and nothing in the
   feature needs it changed. Design §5.3 corrected in place.
5. **Engine hints (Stage 6) land before the pipeline's press-time resolution (Stage 7).** The
   reverse order would leave `EngineProvider.make(config:secrets:hints:)` carrying a parameter no
   engine reads for a whole stage; this way the controller passes `.none` for one stage instead,
   which is inert and honest.
6. **Stage 5 resolves rules from a release-time snapshot built from `input.config`; Stage 7 swaps
   the source to the press-time snapshot.** This delivers R23 and R24 a stage earlier without
   waiting on R12, and the swap changes no observable prompt text — only which config the terms
   came from when the config changed mid-recording.
7. **The measurement's manifest decoding, hit counting and report rendering live in
   `Sources/MWTestSupport/HintMeasurement.swift`**, unit-tested from `MWStreamingTests`. The
   shipping modules carry no test-only code, and R37's logic is still host-tested rather than only
   exercised by a suite nobody can run in CI.
8. **The measurement report directory is derived from `#filePath`, overridable with
   `MW_HINT_REPORT_DIR`.** §5.4 fixes the output path but not how a test resolves the repository
   root from inside the package.
9. **`MWCorrections` is registered in `project.yml` in Stage 2, alongside `Package.swift`**, even
   though the app first imports it in Stage 8 — one registration point rather than two, and a
   listed-but-unimported product costs nothing.
10. **`HistoryListModel.engineLabel` is promoted from `private static` to internal in Stage 9**,
    the stage whose correction-window source line first needs it, rather than earlier.
11. **Stage 6 covers all four engines in one stage rather than splitting on-device from cloud.**
    Widening `EngineProvider.make` forces every engine construction site in `EngineFactory` to
    change together; a split would leave the cloud branch accepting and dropping a `hints`
    parameter for a whole stage. The diff is wide but shallow and single-themed.
12. **No feature flag.** Design §9 fixed a single release; rules and hints are inert until the user
    remembers a first correction, and manual vocabulary behaviour is unchanged except for reaching
    engines it never reached, so a flag would guard nothing.

## Deviations from the design

None — plan matches design v2 exactly. The four corrections listed under *Planning decisions
taken* are factual grounding fixes and internal under-specifications resolved in the design file
in place; none changes scope, requirements, approach or an external interface.

## Deviations from plan

Recorded during implementation. Each is a resolution of an internal contradiction or an
under-specification, not a scope or approach change.

- **Stage 1 — `write` is whitespace-collapsed and NFC-composed in `validated()`.** R4 says
  `heard`, `write` and each `sounds_like` value are "trimmed and whitespace-collapsed"; R6 says
  `write` is "stored exactly as typed after trimming". The two contradict. `validated()` applies
  `PhraseKey.normalised` to all three, so `write` keeps its case, punctuation and spelling exactly
  as typed but loses a doubled inner space and is NFC-composed. NFC on `write` is what §5.3
  already promises of the applier's output ("the output is NFC"), and R4's field list is the more
  specific instruction for the validation path. Pinned by
  `ConfigCodingTests.validatedNormalisesAndDropsInvalidRules`.
- **Stage 2 — `CorrectionValidator.ValidationError.duplicate` carries `heard`, and `validate`
  takes a defaulted `scopeName`.** §5.1 gives the case as `.duplicate(existingWrite:scope:)` with
  a `message`, but §5.5's message ("‘eefa’ is already remembered for Slack as ‘Aoife’.") needs
  both the heard phrase and a display app name, neither of which the three listed parameters
  supply — a `CorrectionRule` carries a bundle ID, not "Slack". The case gained
  `heard: String`, and `validate(_:against:excluding:)` gained a fourth parameter
  `scopeName: String? = nil` which the message uses when the caller has an app name and which
  falls back to the bundle ID (or "All apps") otherwise. The design's three-argument call site
  still compiles unchanged.
- **Stage 2 — `PhraseMatcher.init(variant:)` throws on an empty variant.** The design leaves the
  `throws` unexplained. An empty variant compiles to a pattern that matches at every position, so
  it is rejected as `PhraseMatcher.Failure.emptyVariant`; `CorrectionApplier` counts it under
  `droppedVariants` rather than failing.
- **Stage 3 — `HintReport.State` has no `.measured` case.** §5.1 lists five states
  (`.supported`, `.measured`, `.unavailable`, `.notSent`, `.prompt`), but `HintSupport` has only
  two cases, so nothing can ever produce `.measured`: a measured-supported SpeechAnalyzer is
  `.supported` and a measured-unavailable one is `.unavailable(reason)`. The unreachable case is
  omitted.
- **Stage 4 — `ImpactPreview.compute` takes an optional entry list and `Result` carries
  `historyOff`.** §5.1 declares `compute(rule:over: [Entry]) -> Result` with
  `Result { matching, total, snippets }`, but §5.4 passes the window's `historyEntries()`
  result, which is nil when retention is 0, and Stage 4's own step 1 requires "a nil entry list
  yields the history-off result" — which the three counted fields cannot express, since zero
  matches over zero entries is also what an empty history looks like. The parameter became
  `over entries: [Entry]?` and `Result` gained `historyOff: Bool`, leaving the sentence itself to
  the window model (Stage 8). Pinned by `ImpactPreviewTests.aNilEntryListReadsAsHistoryOff`.
- **Stage 5 — `MWPipeline` gains its `MWCorrections` dependency here, not in Stage 7.** Stage 5's
  own step 3 has `ProcessingJob` build a `CorrectionSnapshot` and resolve `HintResolver` and
  `CorrectionResolver`, and the new `PromptComposer.cleanupPrompt(base:hints:rules:)` takes two
  `MWCorrections` types, so the target cannot compile without the edge. The `Package.swift` line
  moved from Stage 7's *Touches* to Stage 5's; Stage 7 still owns the snapshot's move to press
  time.

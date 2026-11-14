# Unified Window and Design Language — Implementation Plan v6

**Status:** Draft
**Date:** 2026-11-13
**Design:** [feature-design-v6-Unified-window-and-design-language.md](./feature-design-v6-Unified-window-and-design-language.md)

## Overview

v6 replaces the Meetings, History, Settings and Meeting windows with one resizable main window, gives every window but the dictation overlay the language recorded in `DESIGN.md` (light and dark, with a Theme setting), turns summaries into topic-based documents with Regenerate and Copy, and adds one search over meetings and dictations. The plan has 17 stages in four phases. **Core (1–5)** lands every non-UI rule in `MiniWhisperCore` test-first: the summary document, total cost, the config keys, the prompt and its migration, Regenerate, and usage totals. **App foundations (6–9)** adds the `DS` tokens and components, the navigation, frame-policy and search models, and the activation and paste-target adapters, each host-tested where it has logic. **Main window (10–14)** swaps the list windows for pages, moves Settings in, renders summaries from blocks, moves the coordinator onto present/dismiss, and finally replaces the meeting window with pages. **Finish (15–17)** adds the Theme setting, restyles Correction, Onboarding and About, and updates the documentation. Each stage leaves the app building, both suites green and every existing flow working; nothing is released until Stage 17 is in (R28). The staging follows design §9's order with three changes: its step 3 (main window) is split into Stages 7, 9, 10 and 11, its step 4 (meeting pages) into Stages 12, 13 and 14, and its step 5 (search) moves ahead as Stage 8 so that Stage 10 can swap list search for global search in one go.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only | integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests, platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a one-line justification.

In Swift a test naming a type or member that does not exist yet fails to **compile**; that is the first red. The step then adds the minimal empty API (a type whose members return empty or default values) and re-runs to see **assertion** failures before implementing. Every "confirm fail" step below names both.

**Runners and checks** (each run once on 2026-11-13 at `5456c80`, before drafting):

| Check | Command | Observed baseline |
|---|---|---|
| Core tests | `cd Packages/MiniWhisperCore && swift test` | 17 Swift Testing runs (one per test target), 935 tests, all `✔ … passed`; each run is preceded by an empty XCTest `Executed 0 tests` line |
| One core module | `cd Packages/MiniWhisperCore && swift test --filter MWMeetingsTests` | — |
| Core build | `cd Packages/MiniWhisperCore && swift build` | exit 0 |
| App tests | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` | `✔ Test run with 307 tests in 34 suites passed` and `** TEST SUCCEEDED **` |
| One app suite | the app-test command plus `-only-testing:AppTests/<Suite>` | `-only-testing:AppTests/MenuModelTests` → `✔ Test run with 8 tests in 1 suite passed` |
| App build only | the app-test command with `build` in place of `test` | `** BUILD SUCCEEDED **`, exit 0 |
| Appcast scripts | `uv run --no-project --with pytest pytest scripts/tests/` | untouched by this plan |

Read the `✔/✘ Test run with …` line, not the XCTest line. A stage's step 4 runs the focused suite, then **both** the core and the app suites, then the app build — the app target has no tests of its own for its views, so its build is the check that every view still compiles. The two core-only stages of batch 1 run the core suite and the app **build** only (see *Execution schedule*); the next stage's run covers the app suite.

**Registration.** New core files go into existing SwiftPM targets, which compile every file in their folder: `Package.swift` is unchanged (design §5.1). New `App/` and `AppTests/` files, including the new folders `App/Design/`, `App/Main/` and `App/Search/`, are picked up by xcodegen's folder sources at the next `xcodegen generate`; `project.yml` is unchanged. The generated `Mini Whisper.xcodeproj` is git-ignored.

**Test locations.** Core suites follow `Packages/MiniWhisperCore/Tests/<Module>Tests/<Type>Tests.swift`; app suites follow `AppTests/<Type>Tests.swift` with `@testable import MiniWhisper`. Shared app-test helpers live as plain files in `AppTests/`, as `AppTests/StubApps.swift` does. `AppTests` cannot import `MWTestSupport`, so app suites drive time with a manual `MWSupport.Clock` fake (the existing `ManualClock` in `AppTests/MeetingsListModelTests.swift:120`, hoisted in Stage 8) and never with `VirtualClock` (design R26 as corrected).

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: one resizable main window, 1080×720 default, 900×600 minimum; four windows gone | Stage 7, Stage 10, Stage 11, Stage 14 |
| R2: sidebar order; Settings' sections only while Settings shows | Stage 10, Stage 11 |
| R3: recording pill replaces Start Meeting while a meeting is active | Stage 12, Stage 14 |
| R4: menu rows open the window at a destination; Stop Meeting does not | Stage 10, Stage 11, Stage 13, Stage 14 |
| R5: ⌘1 ⌘2 ⌘, ⌘F ⌘N ⌘[ ⌘W; Esc clears search | Stage 7, Stage 10, Stage 11, Stage 14 |
| R6: close hides; recording continues; frame stored and restored | Stage 2, Stage 7, Stage 10, Stage 13, Stage 14 |
| R7: Dock icon while any titled window is visible | Stage 9 |
| R8: Theme setting for the four windows; overlay unchanged | Stage 15 |
| R9: chooser as a page, Test Call step, Cancel returns, ⌘N and the hotkey | Stage 13, Stage 14 |
| R10: live page; navigating away or closing does not affect the recording | Stage 13, Stage 14 |
| R11: live page becomes finished page; Summary · Transcript · Notes; Score pane | Stage 12, Stage 14 |
| R12: one meeting on screen; delete blocked while recording, shown or summarising | Stage 13 |
| R13: carried-over meeting behaviours | Stage 12, Stage 14 |
| R14: new default prompt; unmodified legacy file migrated | Stage 3 |
| R15: summary Markdown rendered as blocks; four-section summaries too | Stage 1, Stage 12 |
| R16: Regenerate with confirmation, old summary kept, cost accumulated | Stage 1, Stage 4, Stage 12, Stage 13, Stage 14 |
| R17: Copy summary as Markdown, HTML and RTF | Stage 1, Stage 12, Stage 13, Stage 14 |
| R18: Meetings row sub line: topics, first sentence or first transcript line | Stage 1, Stage 10 |
| R19: one search over meetings and dictations; pages have no search fields | Stage 1, Stage 7, Stage 8, Stage 10, Stage 14 |
| R20: Dictations page; paste into the last frontmost app after hiding | Stage 9, Stage 10 |
| R21: sidebar usage table; menu Month row; `2h 14m` | Stage 5, Stage 10 |
| R22: Settings keeps its nine sections; History titled Dictations; two buttons gone; capture cancelled on Esc, leaving or hiding | Stage 11 |
| R23: every colour, type style, radius and component from `DESIGN.md`, light and dark | Stage 6, Stage 10, Stage 11, Stage 14, Stage 16 |
| R24: Correction, Onboarding, About sizes and behaviour | Stage 16 |
| R25: macOS 14, arm64, Swift 6 strict; no dependency added | Every stage (no build-setting or manifest change); checked in Stage 17 |
| R26: logic in core or host-testable models, each tested; durations on a virtual clock | Stage 1, Stage 2, Stage 3, Stage 4, Stage 5, Stage 7, Stage 8, Stage 10, Stage 11, Stage 12, Stage 13, Stage 15 |
| R27: no summary, transcript, dictation or search text logged | Stage 4, Stage 8 |
| R28: no release from `main` until v6 is complete | Every stage (no version bump, no tag); Stage 17 leaves `project.yml` versions alone |

## Stages

### Phase A — Core

### Stage 1 — Summary document, search excerpt and meeting total cost
**Goal:** `MWMeetings` parses summary Markdown into blocks with topics, excerpt, inline text, HTML and Markdown; exposes `SearchExcerpt`; and defines a meeting's total cost once, including replaced summaries.
**Design references:** §5.1 (Core), §5.2 (`meeting.json`, `index.json`), §5.4, §5.15, §5.16, §5.20 of feature-design-v6-Unified-window-and-design-language.md
**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWMeetings/SummaryDocument.swift`, `Packages/MiniWhisperCore/Sources/MWMeetings/SearchExcerpt.swift`
- edit `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingSearch.swift` (private `excerpt` at `:76-90` replaced by `SearchExcerpt.around(_:in:context: 40)`), `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingModel.swift` (`Billing.replacedSummaryCostUSD` with a written-out `init(from:)`; `Meeting.totalCostUSD`; doc comments of `Summary.text` and `IndexEntry.excerpt`), `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingStore.swift` (`entry(for:)` at `:233` and `:236`; `firstSentence` at `:256-263` removed)
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/MeetingFixtures.swift` (a topic-based summary fixture beside the existing four-section `northwind()`)
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/SummaryDocumentTests.swift` (sibling `Tests/MWMeetingsTests/MeetingSearchTests.swift`); edit `Tests/MWMeetingsTests/MeetingSearchTests.swift`, `Tests/MWMeetingsTests/MeetingStoreTests.swift`, `Tests/MWMeetingsTests/MeetingModelTests.swift`

**Steps (TDD):**
1. Write tests in `SummaryDocumentTests` (`@Suite struct SummaryDocumentTests`): one `@Test` per parsing rule of §5.4 (fenced code incl. unclosed fence; ATX headings with level capped at 3 and closing `#`s; rules `---`/`***`/`___`; unordered and ordered items with ordinals; blank lines; continuation lines appended to an item with `\n`; `> ` stripped; tables and HTML as paragraph text); item depths for 2-space, 4-space and tab nesting and the depth cap at 3; `topics` (top-level = smallest level present, `Next Steps` excluded case-insensitively); `isFourSection` true for `MeetingFixtures.northwind()` and false for the topic fixture; `excerpt(ofSummary:)` for the topic fixture (`"A · B · C"`), the four-section fixture (its first sentence), heading-less input and empty input; `inline(_:)` drops `link` and `imageURL` and keeps bold, italic, strikethrough and code runs; `html(title:)` escapes `& < > "`, nests `<ul>`/`<ol>` by depth, maps `\n` in an item to `<br>`, never emits `<a`, `<img`, `script` or an attribute; `markdown(title:summary:)` is `"# " + title + "\n\n" + trimmed summary`. In `MeetingSearchTests` add `excerptKeeps90CharactersOfContext` calling `SearchExcerpt.around(_:in:context: 90)`. In `MeetingModelTests` add `billingWithoutReplacedCostDecodesAsZero` (decodes `{"engineSeconds":1,"diarizationSeconds":0,"costUSD":0.4}`) and `totalCostAddsBillingReplacedAndSummary`. In `MeetingStoreTests` add `indexExcerptOfATopicSummaryJoinsItsTopics` and `indexCostIncludesReplacedSummaries`; keep `indexExcerptIsTheSummaryOpeningOrTheFirstSegment` unchanged as the guard that four-section excerpts do not move.
   Expected initial failure: `swift test --filter MWMeetingsTests` fails to compile with `cannot find 'SummaryDocument' in scope`, `cannot find 'SearchExcerpt' in scope` and `value of type 'Billing' has no member 'replacedSummaryCostUSD'`.
2. Run the tests — confirm the compile failure. Add the empty API (`SummaryDocument(markdown:)` storing `[]`, derived values returning empty, `SearchExcerpt.around` returning `nil`, `replacedSummaryCostUSD = 0`, `totalCostUSD` returning `billing.costUSD`) and re-run: confirm assertion failures such as `#expect(document.blocks == […])` → `[] == [.heading(level: 2, text: "…")]` and `abs(entry.costUSD - …) < 1e-9` failing.
3. Implement: the line parser with the indent stack exactly as §5.4 states; `inline(_:)` moved from today's `MeetingView.rendered` rule (`App/Meeting/MeetingView.swift:303-319`) into core plus `imageURL` removal; `html(title:)` from the parsed blocks and each run's `inlinePresentationIntent`; `SearchExcerpt.around` from `MeetingSearch.excerpt`; `MeetingSearch` calling it with `context: 40`; `Billing.init(from:)` decoding `replacedSummaryCostUSD` with `decodeIfPresent ?? 0`; `Meeting.totalCostUSD`; `MeetingStore.entry(for:)` using `meeting.totalCostUSD` and `SummaryDocument.excerpt(ofSummary:)`; delete `firstSentence`.
4. Run `swift test --filter MWMeetingsTests` — confirm pass. Run the full core suite and the app build-only check — confirm no regressions (`MWAgentAccessTests` reads `IndexEntry` and must stay green).

**Definition of done:**
- Every §5.4 rule and derived value has a test; all pass.
- `MeetingSearch` output is unchanged for every existing `MeetingSearchTests` case.
- The four-section index excerpt is byte-identical to before; a topic summary's excerpt is its topics joined by ` · `.
- `meeting.json` without the new key decodes; the key is always encoded; `Meeting.currentSchema` stays `1`.
- `MeetingStore.firstSentence` no longer exists; the app still builds.

**Risks specific to this stage:** `AttributedString(markdown:)` inline parsing differs slightly across macOS releases. Mitigation: the tests assert the plain text and the presence of bold/italic/code runs, never run boundaries.

### Stage 2 — Theme and main-window-frame config keys
**Goal:** `config.json` carries `theme` and `main_window_frame` with the round-trip and malformed-value rules of §5.2.
**Design references:** §5.1, §5.2, §5.15, §5.16, §5.19
**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWConfig/AppTheme.swift` (`AppTheme` and `WindowFrame`)
- edit `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift` (`Key.theme`, `Key.mainWindowFrame`, both in `Key.all` at `:201`; `theme`, `unrecognisedTheme`, `mainWindowFrame`; decode and encode)
- edit `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`

**Steps (TDD):**
1. Write tests in `ConfigCodingTests`: `themeDefaultsToSystemAndIsWritten` (decoding `{}` gives `.system`; encoding writes `"theme": "system"`); `themeRoundTripsEachValue` (`system`, `light`, `dark`); `unknownThemeReadsAsSystemAndSurvivesASave` (as `overlay_style`'s case at `:187-191`); `windowFrameRoundTrips`; `windowFrameAbsentIsNil` and is not written when nil; `malformedWindowFrameReadsAsAbsentAndKeepsTheRestOfTheConfig` (a string, a missing `width`, and a non-finite number each give `mainWindowFrame == nil` with `hotkey` still decoded); `settingThemeClearsTheUnrecognisedValue`.
   Expected initial failure: compile error `value of type 'Config' has no member 'theme'` and `cannot find 'WindowFrame' in scope`.
2. Run `swift test --filter MWConfigTests` — confirm the compile failure; add `AppTheme`/`WindowFrame` and the two stored properties with no coding; re-run and confirm assertion failures (`saved?["theme"] as? String == "system"` → `nil == "system"`).
3. Implement: decode `theme` as `overlay_style` is decoded (`Config.swift:247-250`), keeping the raw string in `unrecognisedTheme`; decode the frame with `try?` so a malformed value cannot make `Config.init(from:)` throw (a throw there would make `ConfigStore` back up the whole file as corrupt), rejecting non-finite numbers; encode `theme` always and the frame only when set.
4. Run the focused suite — pass. Full core suite and app build-only — no regressions.

**Definition of done:** both keys in `Key.all`; every rule of the §5.2 table and the §5.15 rows *main_window_frame malformed* and *theme unrecognised* tested and passing; a malformed frame never triggers the corrupt-file backup.

**Risks specific to this stage:** None.

### Stage 3 — Topic-based summary prompt and its migration
**Goal:** the bundled default prompt is the §5.3 text, and an unmodified legacy `summary_prompt.txt` is replaced by it once at launch.
**Design references:** §3 R14, §5.3, §5.15, §5.18, §5.19
**Category:** hybrid — full TDD for the migration and the bundled text; the one-line launch call in `AppDelegate` is integration-verified.
**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWConfig/PromptFiles.swift` (`legacySummaryDefaults`, `migrateSummaryPrompt() throws -> Bool`)
- edit `App/Resources/default_summary_prompt.txt` (the §5.3 text)
- edit `App/AppDelegate.swift` (`startNormal()`: call the migration straight after constructing `PromptFiles`, log `Log.ui.info` on `true`, `Log.ui.warning` on a throw)
- edit `Packages/MiniWhisperCore/Tests/MWConfigTests/PromptFilesTests.swift`
- create `AppTests/BundledResourcesTests.swift` (sibling `AppTests/LaunchArgumentsTests.swift`)

**Steps (TDD):**
1. Write tests in `PromptFilesTests` using its `makeFixture` temp bundle: `migrationLeavesAMissingFileAlone` (returns `false`, file still absent); `migrationReplacesTheLegacyDefault` (file holds `legacySummaryDefaults[0]` → `true`, content now the bundled text); `migrationMatchesIgnoringSurroundingWhitespace` (legacy text with a trailing newline and leading spaces → `true`); `migrationLeavesAnEditedFileByteForByte` (returns `false`, bytes and modification date unchanged); `legacyDefaultIsTheTextShippedAtE64ed39` (compares with the literal from `git show e64ed39:App/Resources/default_summary_prompt.txt`). In `BundledResourcesTests`: `bundledSummaryPromptIsTheTopicPrompt` reads `Bundle.main`'s `default_summary_prompt.txt` (the test host is the app) and checks it equals the §5.3 text and is not in `PromptFiles.legacySummaryDefaults`.
   Expected initial failure: `type 'PromptFiles' has no member 'migrateSummaryPrompt'` (core); `type 'PromptFiles' has no member 'legacySummaryDefaults'` (app tests).
2. Run `swift test --filter MWConfigTests` and `-only-testing:AppTests/BundledResourcesTests` — confirm the compile failures; add `legacySummaryDefaults` and a `migrateSummaryPrompt` returning `false`; re-run and confirm assertion failures (`migrateSummaryPrompt() == true` → `false`; the bundled prompt still starts `You summarise a meeting`).
3. Implement the three outcomes of §5.3 (missing → `false`; trimmed match → write bundled default, `true`; otherwise `false` without opening the file for writing); replace `default_summary_prompt.txt` with the §5.3 text; add the call in `AppDelegate.startNormal()`.
4. Run both focused suites — pass. Full core and app suites, app build — no regressions (`SettingsModelTests` *Restore Default* cases write their own fixture prompt and stay green).
5. Integration check (the launch call): the app build passes, and `startNormal()` calls the migration on the line after `PromptFiles(…)` and before `HistoryStore`, `DictationController` or `MeetingCoordinator` is built. The live migration is not run here, because the only legacy file is the user's own; *Verification* step 3 checks it on the developer's Mac (§5.19).

**Definition of done:** the three migration outcomes and the whitespace rule pass; an edited file's bytes are untouched; the bundled prompt is the §5.3 text; `Summariser` is unchanged.

**Risks specific to this stage:** a migration that rewrites a user's file. Mitigation: it writes only on an exact trimmed match with a shipped default, which the byte-for-byte test pins.

### Stage 4 — Regenerate in the meeting controller
**Goal:** `MeetingController.regenerateSummary()` writes a new summary while the old one stays current, keeps the old one on every failure, accumulates the replaced cost and records usage once; the meeting model's cost follows.
**Design references:** §3 R16, R27, §5.6, §5.15, §5.18, §5.20
**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingEvent.swift` (`SummaryState.rewriting(Summary)`, `.kept(Summary, reason: String)`)
- edit `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift` (`regenerateSummary()`; the request code `summarise()` uses moved into one private helper both call; `Log.meeting.info` for start and result)
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeSummarizer.swift` (an optional queue of results and a hold/release gate, so a test can keep a request in flight)
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerRegenerateTests.swift` (sibling `Tests/MWMeetingPipelineTests/MeetingControllerEditingTests.swift`; reuses `MeetingHarness` from `MeetingControllerTests.swift`)
- edit `App/Meeting/MeetingWindowModel.swift` (`summaryPanel` `:370-382` maps `.rewriting`/`.kept` to `.ready` so the exhaustive switch compiles — the notice comes in Stage 12; `costText` `:360-363`; `apply` `:550-552`; `show` `:461`)
- edit `AppTests/MeetingWindowModelTests.swift`

**Steps (TDD):**
1. Write tests in `MeetingControllerRegenerateTests`, each seeding `MeetingFixtures.northwind()` and opening it: `regenerateWritesANewSummaryAndKeepsTheOldOneCurrentMeanwhile` (events in order `.summary(.rewriting(old))`, `.summary(.ready(new))`; stored summary is `new`; `billing.replacedSummaryCostUSD == old.costUSD`; `usage.added` has exactly one new record with `new`'s tokens and cost); `regenerateWithoutAKeyKeepsTheSummary` (`.kept(old, noSummaryKey)`, nothing saved, no usage, no summariser call); `regenerateWithNothingTranscribedKeepsTheSummary`; `regenerateDeclinedKeepsTheSummary` (`.kept(old, "Summary declined (cyber)")`); `regenerateFailureKeepsTheSummaryAndLogsTheReasonOnly` (`.kept(old, "API error (503).")`, `meeting.json` bytes unchanged, and under `Log.withSinks` with a `CapturingLogSink` no line contains the summary text); `regenerateIsANoOpWithoutASummaryOrBeforeStop`; `aSecondRegenerateWhileOneIsInFlightReturns` (gate held: second call returns, one summariser call); `summariseAndRegenerateDoNotOverlap`. In `MeetingWindowModelTests`: `costAfterARegenerateIncludesTheReplacedSummary` (apply `.rewriting(old)` then `.ready(new)`: `costText == dollars(billing + old + new)`), `showReadsTheReplacedCostFromBilling`, `rewritingAndKeptStillShowTheCurrentSummary`.
   Expected initial failure: `type 'SummaryState' has no member 'rewriting'` and `value of type 'MeetingController' has no member 'regenerateSummary'`.
2. Run `swift test --filter MWMeetingPipelineTests` — confirm the compile failure. Add the two cases, a `regenerateSummary()` that only emits `.summary(.kept(current, ""))` (so `harness.waitFor` returns rather than hangs), and the app's minimal `summaryPanel` mapping; re-run and confirm assertion failures (`events.last == .summary(.ready(new))` → got `.kept`). Run `-only-testing:AppTests/MeetingWindowModelTests` and confirm the cost test fails (`costText` omits the replaced cost).
3. Implement §5.6 steps 1–5 exactly; extract the shared request helper so `summarise()` keeps its contract; update the four `MeetingWindowModel` sites per the §5.6 table.
4. Run both focused suites — pass. Full core and app suites — the existing `MeetingControllerTests` summary cases and `MeetingWindowModelTests` stay green.

**Definition of done:** every §5.6 branch and the §5.15 rows *Regenerate with no key…* and *pressed twice* tested; nothing is written to disk on a `.kept` path; usage recorded once; R27 asserted by the capturing sink; the app builds with the new cases handled.

**Risks specific to this stage:** a test waiting on an event that never comes hangs the suite. Mitigation: the scaffold emits a terminal event, and every regenerate test waits for a terminal summary event.

### Stage 5 — Usage totals, the usage table and the menu's Month row
**Goal:** usage reports month totals as well as today's, renders the two table rows and the two menu rows from one set of cells, and carries the totals to the menu.
**Design references:** §3 R21, §5.1, §5.11, §5.15 (*Usage for a month with no entries*)
**Category note:** this stage changes the shared `UsageRecording.totals()` signature and `UIEvent.usage`; the blast radius is 2 conformers of `UsageRecording` (`UsageStore`, `FakeUsageStore`), 3 production callers of `totals()` (`ProcessingJob`, `AppDelegate` twice), 3 of `formatUsageRows` (`ProcessingJob`, `MenuModel` twice), one exhaustive `UIEvent` switch (`UIEventRouter`), and 14 test sites; every one changes here, atomically.
**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWUsage/UsageTotals.swift` (`UsageTotals`, `UsageTable`)
- edit `Packages/MiniWhisperCore/Sources/MWUsage/UsageStore.swift` (`totals() -> UsageTotals`, month merged per engine), `Packages/MiniWhisperCore/Sources/MWUsage/Pricing.swift` (`usageTable(_:)`, `formatUsageRows(_:)` replacing the two-argument form at `:104-112`), `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeUsageStore.swift`, `Packages/MiniWhisperCore/Sources/MWPipeline/UIEvent.swift` (`.usage(UsageTotals)`), `Packages/MiniWhisperCore/Sources/MWPipeline/ProcessingJob.swift` (`:188-190`)
- edit `Packages/MiniWhisperCore/Tests/MWUsageTests/UsageStoreTests.swift`, `Packages/MiniWhisperCore/Tests/MWUsageTests/PricingTests.swift`, `Packages/MiniWhisperCore/Tests/MWPipelineTests/ProcessingJobTests.swift` (`:651-672`), `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingBillingTests.swift` (`:48-49`)
- edit `App/UIEventRouter.swift` (`:77-78`), `App/StatusItemController.swift` (`:53-60` → one `setUsage(_ totals:)`), `App/MenuModel.swift` (`:42`, `:69-77` → one overload taking `UsageTotals`), `App/AppDelegate.swift` (`:172-173`, `:372-373`), `AppTests/MenuModelTests.swift`

**Steps (TDD):**
1. Write tests: in `UsageStoreTests`, `totalsSumTheMonthPerEngine` (two days, two engines: tokens added, `streamedSeconds` merged per engine, cost added; previous-month days excluded) and update `totalsSumMonth`/`totalsEmpty` to the new shape; in `PricingTests`, `usageTableAt0_59And134Minutes` (`0m`, `59m`, `2h 14m`; tokens `1.2k/340`; cost via `dollars`), `menuRowsShowTheSameThreeFiguresForTodayAndMonth` (`Month: 48.6k/9.1k tok · 2h 14m · $1.50`), `emptyMonthReads0Over0` (`0/0`, `0m`, `$0.00`), and the existing `formatUsageRows`/`formatSmallValues`/`formatZero`/`thousandsAreAbbreviated`/`menuRowsMarkASubCentDay` re-expressed through `UsageTotals` with their new Month strings; in `ProcessingJobTests`, `usageEventCarriesTheTotals` replaces `usageEventCarriesFormattedRows`; in `MenuModelTests`, `emptyMonth` becomes `Month: 0/0 tok · 0m · $0.00` and the string-overload test is replaced by `setUsageFormatsTheTotals`.
   Expected initial failure: `cannot find 'UsageTotals' in scope` in `MWUsageTests`, then (app) `cannot find 'UsageTotals' in scope` in `MenuModelTests`.
2. Run `swift test --filter MWUsageTests` — confirm the compile failure; add the types and a `Pricing.usageTable` returning empty strings; re-run and confirm assertion failures (`table.today.audio == "2h 14m"` → `""`).
3. Implement §5.11: the month sum, `usageTable`, `formatUsageRows(_:)`; change `UsageRecording.totals()`, `UsageStore`, `FakeUsageStore`, `UIEvent.usage`, `ProcessingJob`; in the app, `UIEventRouter` and both `AppDelegate` sites pass `UsageTotals` to `StatusItemController.setUsage(_:)`; `MenuModel` keeps one `setUsage(_ totals:)` and builds its initial rows from `UsageTotals()`.
4. Run `swift test --filter MWUsageTests`, `--filter MWPipelineTests`, `--filter MWMeetingPipelineTests`, `-only-testing:AppTests/MenuModelTests` — pass. Full core and app suites — no regressions.

**Definition of done:** cells and both menu rows at 0, 59 and 134 minutes tested; a month with no entries reads `0/0`, `0m`, `$0.00`; the old two-argument `formatUsageRows` and `MenuModel.setUsage(today:month:)` are gone with no caller left; the app builds.

**Risks specific to this stage:** the Today row's audio format also changes from `134m` to `2h 14m` (R21 applies it to both rows). Mitigation: stated in the changelog in Stage 17.

### Phase B — App foundations

### Stage 6 — Design tokens and components
**Goal:** `DS` holds every colour (light and dark), type style, radius and spacing value of `DESIGN.md`, and the components of §5.1 exist, ready for the pages.
**Design references:** §3 R23, §5.1 (App), §5.9 (*Dialogs*), §5.10; `DESIGN.md` — every section of the managed region; mockups `mockup-v6-overview.html`, `mockup-v6-recording.html`, `mockup-v6-windows.html`
**Category:** hybrid — full TDD for token resolution; the components are platform-only/UI wiring (SwiftUI views with no logic beyond layout), verified by build and the hand check.
**Touches:**
- create `App/Design/DS.swift` (colours via `Color(light:dark:)` over `NSColor(name:dynamicProvider:)`, an `NSColor` accessor for tests and AppKit text, fonts with `Font.system(size:weight:design: .serif)` for display type, radii, spacing)
- create `App/Design/PillButtonStyle.swift`, `App/Design/DSFieldStyle.swift`, `App/Design/DSToggleStyle.swift`, `App/Design/SegmentedPill.swift`, `App/Design/Chip.swift`, `App/Design/Tile.swift`, `App/Design/Card.swift`, `App/Design/SettingRow.swift`, `App/Design/StatusLine.swift`, `App/Design/PageColumn.swift`, `App/Design/DSDialog.swift`, `App/Design/CloudPulseMark.swift` (the two paths of `#i-cloud` in `mockup-v6-overview.html`)
- edit `App/Meeting/MeetingView.swift` (delete the file-private `Chip` at `:690` — its name collides with the new `Chip` — and use the `DS` `Chip` at `:175-183`; `SpeakerColor.palette` at `:659-668` from `DS` speaker colours)
- edit `App/TestCall/TestTag.swift` (text and fill from `DS`; no border, as the mockups draw `.chip.test` with a transparent border), `App/TestCall/ScorePane.swift` (`HeardWord.errorText` at `:173` → `DS` recording colour, as the mockup's `.err` uses `--rec`)
- create `AppTests/DSTests.swift` (sibling `AppTests/OverlayStyleCatalogTests.swift`)
- add to version control `DESIGN.md` and `design/specimen.html` (already on disk, written by `/design-language-update`)

**Steps (TDD):**
1. Write `DSTests`: a parameterised `@Test(arguments:)` over every colour token in `DESIGN.md`'s palette that the language uses (`canvas`, `sidebar`, `card`, `hover`, `line`, `text`, `text.secondary`, `text.tertiary`, `accent`, `accent.on`, `accent.soft`, `recording`, `recording.soft`, `ok`, `warn`, `teal`, `teal.soft`, `test.text`, `test.fill`, `speaker.1–3`) resolving, inside `NSAppearance(named: .aqua)` and `.darkAqua` `performAsCurrentDrawingAppearance`, to its light and dark hex in sRGB; `radiiMatchDesignMD` (`field` 8, `row` 10, `card` 14); `typeScaleMatchesDesignMD` (point sizes of the twelve v6 styles); `appGlyphPaletteIsUnchanged` (the eight literals of `App/History/AppGlyph.swift:16-25`).
   Expected initial failure: `cannot find 'DS' in scope` (the app-test target fails to build; `** TEST FAILED **`).
2. Run `-only-testing:AppTests/DSTests` — confirm the build failure; add `DS` with every colour set to one placeholder value; re-run and confirm assertion failures per token (`#2A6FC9` expected, placeholder found).
3. Implement `DS` with the `DESIGN.md` values; build each component to the mockups (Pill button primary/secondary/quiet × regular/small; Rounded field and search pill; toggle; Segmented pill switch; Chip with optional dot and the TEST variant; Tile by mode; Settings card with optional group label; SettingRow with name, description and trailing control; Status line with info and warning variants; PageColumn at 736 points with a display-serif title; `DSDialog` with scrim, 380-point card, Return on the filled button, Esc and scrim click cancelling, an accessibility label and modal trait; `CloudPulseMark` as a `Shape`). Replace the colliding `Chip`; point `SpeakerColor` and `TestTag` at `DS`.
4. Run `DSTests` — pass. Full app suite and app build — no regressions.

**Definition of done:** every token used by the language resolves to its `DESIGN.md` light and dark value under test; the components compile and are used by nothing yet except `Chip`, `SpeakerColor` and `TestTag`; no literal colour exists outside `DS` except `AppGlyph`'s eight (`grep -rn "Color(red:\|rgb(0x" App --include='*.swift' | grep -v App/Overlay` lists only `App/History/AppGlyph.swift:17-24`); `DESIGN.md` and `design/specimen.html` are in the stage commit.

**Risks specific to this stage:** components built ahead of their pages may need adjustment when first used. Mitigation: pages in Stages 10–16 change a component in place rather than forking it.

### Stage 7 — Navigation and window-frame models
**Goal:** the main window's navigation rules and frame restoration exist as pure, fully tested models.
**Design references:** §3 R1, R5, R6, R19, §5.7, §5.8 (*Frame*), §5.15, §5.16
**Touches:**
- create `App/Main/MainNavigationModel.swift` (`Destination`, `destination`, `origin`, `beforeSearch`, `query`, `go(_:)`, `showMeeting()`, `back()`, `revealDictation(_:)`, the back pill's label, and injected hooks `meetingPageLeft`, `settingsLeft`, `entered(_:)`, `reveal(_:)`)
- create `App/Main/WindowFramePolicy.swift` (`frame(saved: WindowFrame?, screens:) -> CGRect`, pure over visible-frame rectangles and the main screen's)
- create `AppTests/MainNavigationModelTests.swift` (sibling `AppTests/MenuModelTests.swift`), `AppTests/WindowFramePolicyTests.swift` (sibling `AppTests/DisplayPlacementTests.swift`)

**Steps (TDD):**
1. Write `MainNavigationModelTests` with one `@Test` per row of the §5.7 tables: starts at `.meetings`; `go` sets the destination, clears the query except to `.search`, calls `meetingPageLeft` when leaving `.meeting` and `settingsLeft` when leaving `.settings`, and calls `entered` for the new destination; `showMeeting` records the origin (incl. `.search`, query kept) and never records `.meeting`; `back` returns to the origin and keeps a search origin's query; typing a non-empty query from any destination (incl. `.meeting`, which calls `meetingPageLeft`) goes to `.search`; clearing it on `.search` returns to `beforeSearch`; `beforeSearch` skips `.search` and `.meeting`; `revealDictation` goes to `.dictations` then calls `reveal(id)`; back-pill labels `Meetings`, `Dictations`, `Results`, `Settings`. Write `WindowFramePolicyTests`: on-screen saved frame returned as is; a frame overlapping a screen by less than 100×100 → default; a frame on a disconnected display → default 1080×720 centred on the main visible frame; a too-small frame raised to 900×600; a frame larger than its screen clamped to the visible frame; nil → default.
   Expected initial failure: `cannot find 'MainNavigationModel' in scope`, `cannot find 'WindowFramePolicy' in scope`.
2. Run `-only-testing:AppTests/MainNavigationModelTests -only-testing:AppTests/WindowFramePolicyTests` — confirm; add empty types (methods that do nothing, a policy returning `.zero`); re-run and confirm assertion failures (`destination == .search` → `.meetings`; `frame == (90, 60, 1080, 720)` → `.zero`).
3. Implement both per §5.7 and §5.8.
4. Run both suites — pass. Full app suite and build — no regressions.

**Definition of done:** every §5.7 row and the four frame cases of §5.20 tested and passing; neither type imports AppKit beyond `CGRect`; nothing uses them yet.

**Risks specific to this stage:** None.

### Stage 8 — Search model
**Goal:** `SearchModel` runs a debounced, cancellable search over meetings and dictations with a per-session cache, labelled snippets and newest-first results.
**Design references:** §3 R19, R27, §5.12, §5.15 (*Search load of a meeting fails*, *Query changes during a search*), §5.17
**Touches:**
- create `App/Search/SearchModel.swift` (`query`, `meetings: [MeetingHit]`, `dictations: [DictationHit]`, `invalidate()`, the snippet `label(of:in:)` moved from `App/Meetings/MeetingsListModel.swift:284-296`; long dictations through `SearchExcerpt.around(_:in:context: 90)`)
- edit `App/Meetings/MeetingsListModel.swift` (its `matches` calls `SearchModel.label` until Stage 10 removes list search)
- create `AppTests/ManualClock.swift` and `AppTests/StubMeetingLibrary.swift` (hoisted from the private `StubLibrary` and `ManualClock` of `AppTests/MeetingsListModelTests.swift:44-148`; sibling `AppTests/StubApps.swift`), and edit `AppTests/MeetingsListModelTests.swift` to use them
- create `AppTests/SearchModelTests.swift` (sibling `AppTests/MeetingsListModelTests.swift`)

**Steps (TDD):**
1. Hoist `ManualClock` and `StubLibrary` unchanged (a behaviour-preserving test refactor; `MeetingsListModelTests` stays green). Write `SearchModelTests` with a real `HistoryStore` on a temp file: `searchWaits150MillisecondsBeforeRunning` (nothing published until `clock.wake()`); `aNewQueryCancelsTheRunningSearch` (the first query's results are never published); `emptyQueryClearsResultsAndCache`; `meetingsAndDictationsNewestFirst`; `upToTwoLabelledSnippets` (ported from `MeetingsListModelTests.searchShowsUpToTwoLabelledSnippets`: `Note · 00:40:05`, `Speaker 3 · 01:12:48`, `Summary`); `testMeetingsAreFound`; `cacheLoadsEachMeetingOncePerSession` (two queries → one `load` per id) and drops word timings; `invalidateEmptiesTheCacheAndReRuns`; `aMeetingThatFailsToLoadIsSkippedAndCountedInTheLog` (a test-local `LogSink` under `Log.withSinks` sees `search skipped 1 meetings` and no query text); `aLongDictationIsShownAsAnExcerpt` (> 200 characters → `SearchExcerpt.around(query, in:, context: 90)`); `meetingMetaReadsDayDurationMode` and `dictationMetaReadsDayTimeApp`.
   Expected initial failure: `cannot find 'SearchModel' in scope`.
2. Run `-only-testing:AppTests/SearchModelTests` — confirm; add `SearchModel` with properties that never change; re-run and confirm assertion failures (`model.meetings.map(\.title) == ["Northwind rollout sync"]` → `[]`).
3. Implement §5.12 steps 1–3 with the loading and matching off the main actor in a detached task, as `MeetingsListModel.scheduleSearch` does today (`:254-272`); the detached work returns its skipped count and the model's own (non-detached) task logs it, because `Log.withSinks` is task-local and a detached task would not see the test's sink; move `label(of:in:)`.
4. Run `SearchModelTests` and `MeetingsListModelTests` — pass. Full app suite and build — no regressions.

**Definition of done:** every §5.20 *SearchModel* case passes with no real sleep; no search text reaches a log line (asserted); `MeetingsListModel` search still works through the moved label; the two hoisted helpers are the only copies.

**Risks specific to this stage:** None.

### Stage 9 — Window activation and the paste target
**Goal:** the Dock icon follows the visible titled windows across every window and alert, and the paste target is the last app frontmost before Mini Whisper, whatever window is open.
**Design references:** §3 R7, R20, §5.8 (*Activation*, as corrected), §5.13
**Category:** hybrid — full TDD for `HistoryListModel`'s paste target; `WindowActivation` and `FrontAppTracker` are thin AppKit adapters, integration-verified.
**Touches:**
- create `App/WindowActivation.swift` (`shown(_:)`, `closed()` on the next main-queue turn), `App/FrontAppTracker.swift`
- edit `App/History/HistoryListModel.swift` (`previousApp` becomes a read of `deps.previousApp()`), `App/History/HistoryWindowController.swift` (no longer sets `previousApp`), `App/AppDelegate.swift` (owns one `FrontAppTracker`; passes `previousApp`)
- edit the activation-policy calls in `App/Settings/SettingsWindowController.swift`, `App/Meeting/MeetingWindowController.swift`, `App/Meetings/MeetingsWindowController.swift`, `App/History/HistoryWindowController.swift`, `App/Correction/CorrectionWindowController.swift`, `App/Onboarding/OnboardingWindowController.swift`, `App/AboutPanel.swift`, `App/AppUpdater.swift` (`:57-59`), `App/Onboarding/SpeechModelPrompt.swift` (`:43`, `:55`)
- edit `AppTests/HistoryListModelTests.swift` (`:304-355`)

**Steps (TDD):**
1. Change the harness in `HistoryListModelTests` to supply `previousApp` through a settable closure and rewrite `pasteEnabledOnlyWhenTargetRunning`, `pasteUsesPreviousAppPidAndNoSubmit`, `pasteDoesNothingWhenTheTargetIsGone` to set it there; add `pasteTargetIsReadAtPasteTime` (the closure's value changes between two pastes; each goes to the current target).
   Expected initial failure: `extra argument 'previousApp' in call` (`HistoryListModel.Dependencies` has no such member).
2. Run `-only-testing:AppTests/HistoryListModelTests` — confirm; add the dependency without reading it; re-run and confirm `pasteTitle == "Paste into Slack"` → `nil`.
3. Implement the read; `FrontAppTracker` per §5.13; `WindowActivation` per §5.8 and replace every listed unconditional `.regular`/`.accessory` pair with it.
4. Run the suite — pass. Full app suite and build — no regressions.
5. Integration check (built app): open Settings, then Correction, close Settings — the Dock icon stays; close Correction — it goes; open History from the menu while TextEdit is frontmost, click into another Mini Whisper window, Paste — the text lands in TextEdit; run *Check for Updates…* while History is open — the Dock icon stays after the update dialog closes.

**Definition of done:** no `setActivationPolicy` call remains outside `WindowActivation` except the launch default at `App/main.swift:10` (grep); paste-target tests pass; the integration check passes.

**Risks specific to this stage:** `WindowActivation.closed()` counting a window still closing. Mitigation: it runs on the next main-queue turn (§5.8) and the integration check closes windows in both orders.

### Phase C — Main window

### Stage 10 — Main window with Meetings, Dictations and Search pages
**Goal:** one resizable main window with the sidebar, usage table, Meetings, Dictations and Search pages replaces the Meetings and History windows, and one sidebar search replaces both list searches.
**Design references:** §3 R1, R2, R4, R5, R6, R18, R19, R20, R21, R23, §5.7, §5.8, §5.9 (*Sidebar*, *Usage table*, *Page column*, *Meetings*, *Dictations*, *Search results*, *Dialogs*, *Menu*), §5.11, §5.12, §5.13, §5.14, §5.15, §5.17, §5.18; `DESIGN.md` — Sidebar, Day-grouped row list, Rounded field (search pill), Tile, Dialog, the usage table's tabular figures; mockup `mockup-v6-overview.html`
**Category:** hybrid — full TDD for the list models and the menu row; the window, sidebar and pages are platform-only/UI wiring over models tested here and in Stages 7–8. Old and new list UIs cannot usefully coexist, and per-list search can only go when global search arrives, so the swap is one atomic stage.
**Touches:**
- create `App/Main/MainWindowModel.swift` (navigation, the page models, `SearchModel`, `usage: UsageTotals` → `Pricing.usageTable`), `App/Main/MainWindowController.swift` (`MainWindow`; style, `minSize` 900×600, `show(_ destination:)`, `hide()`, frame restore on first show through `WindowFramePolicy`, frame save with `ConfigStore.update` on hide, close and quit only when changed; `Log.ui` lines of §5.18), `App/Main/MainView.swift`, `App/Main/SidebarView.swift` (search pill with `⌘F` hint, Start Meeting, Meetings, Dictations, Settings, usage table; hidden ⌘F and ⌘W buttons; ⌘1, ⌘2, ⌘N; Esc in the field clears the query), `App/Main/UsageTableView.swift`, `App/Meetings/MeetingsPage.swift`, `App/History/DictationsPage.swift`, `App/Search/SearchPage.swift`
- edit `App/Meetings/MeetingsListModel.swift` (search removed — `query`, `hits`, `Snippet`, `Row.snippets`, the task, the match footer; `Row` gains the sub line of R18 with its transcript flag and the right-hand `HH:mm`; meta becomes `duration · mode · N speakers · cost[ · No summary]` or, for a test call, `duration · WER x.x% · engine · cost`; the delete-blocked help text), `App/History/HistoryListModel.swift` (`query` removed; `selection`; `reveal(_:)`; a `changed` hook after delete and clear), `App/MenuModel.swift` (`.history` → `.dictations`, `Dictations…`), `App/StatusItemController.swift` (`:103`), `App/UIEventRouter.swift` (forwards usage to the main window through an injected closure), `App/AppDelegate.swift` (composition at the end of `startNormal()`; `Meetings…`/`Dictations…` → `main.show`; Settings… and the sidebar's Settings row still open the Settings window until Stage 11, and that window's `Open History…`/`Open Meetings…` dependencies point at `main.show(.dictations)`/`main.show(.meetings)` until Stage 11 removes them; `meetingChanged` reloads the Meetings page, calls `search.invalidate()` and sets `main.usage`; the coordinator's `openMeetings` → `main.show(.meetings)`; quit hides the main window; `deps.hide` hides it before a paste)
- delete `App/Meetings/MeetingsWindowController.swift`, `App/Meetings/MeetingsListView.swift`, `App/History/HistoryWindowController.swift`, `App/History/HistoryView.swift`
- edit `AppTests/MeetingsListModelTests.swift` (search tests `:285-363` removed — ported in Stage 8; row and meta tests rewritten), `AppTests/HistoryListModelTests.swift` (`searchFiltersCaseInsensitive` `:171-190` removed — covered by `SearchModelTests`; reveal tests added), `AppTests/MenuModelTests.swift`

**Steps (TDD):**
1. Write tests: `MeetingsListModelTests` — `rowSubLineIsTheTopicsOrTheFirstSentence` (excerpt as stored, not italic), `rowSubLineQuotesTheFirstTranscriptLineWhenThereIsNoSummary` (`“…”`, italic flag), `metaReadsDurationModeSpeakersCost`, `metaMarksNoSummary`, `testCallMetaReadsDurationWerEngineCost` (WER only once scored), `startTimeSitsApartFromTheMeta`, `audioSizeStaysInTheExportMenuOnly`, `deleteIsBlockedWithHelpWhileOpen`; `HistoryListModelTests` — `revealSelectsTheRow`, `revealOfARemovedDictationSelectsNothing`, `deleteAndClearReportAChange`; `MenuModelTests` — rows read `Dictations…` with action `.dictations` in place of `History...`.
   Expected initial failure: `value of type 'MeetingsListModel.Row' has no member 'subLine'`, `value of type 'HistoryListModel' has no member 'reveal'`, `type 'MenuItem.Action' has no member 'dictations'`.
2. Run `-only-testing:AppTests/MeetingsListModelTests -only-testing:AppTests/HistoryListModelTests -only-testing:AppTests/MenuModelTests` — confirm; add the members returning defaults; re-run and confirm assertion failures (`row.meta == "48 min · Remote call · 3 speakers · $0.40"` → today's string with time and audio).
3. Implement the model changes; build `MainWindowModel`, `MainWindowController`, `MainView`, `SidebarView`, `UsageTableView` and the three pages to `mockup-v6-overview.html` with the Stage 6 components (meeting and audio deletes and Clear… through `DSDialog`; rows double-click/Return to open; hover and focus actions kept in the layout); wire search through `MainNavigationModel.query` → `SearchModel.query`; a dictation result → `revealDictation`; a meeting result → `coordinator.open(id)` (the meeting window until Stage 14); delete the four files.
4. Run the three suites — pass. Full core and app suites and the app build — no regressions.
5. Integration check (built app, light appearance): menu `Meetings…` and `Dictations…` open the window there; ⌘1/⌘2/⌘F/⌘W/Esc behave per R5; typing shows results for both kinds, clearing returns to the page before; a dictation result opens Dictations with the row selected; Paste into *app* hides the window and pastes into the previous app; resize below 900×600 is refused; quit and relaunch restores the frame, and moving it to a disconnected display's coordinates in `config.json` gives the default; the usage table and the menu's Month row show the same figures; deleting a meeting with its meeting window open is disabled with the help text.

**Definition of done:** the Meetings and History windows and their controllers are gone (grep shows no reference); list and menu tests pass; the integration check passes; `MainNavigationModel`, `WindowFramePolicy` and `SearchModel` are in use.

**Risks specific to this stage:** the largest UI stage of the plan; review fatigue. Mitigation: all logic it adds is in the three tested models, and the views are a projection of the accepted mockup; the integration check lists every R it touches.

### Stage 11 — Settings in the main window
**Goal:** Settings becomes a destination of the main window with its nine sections in the sidebar and each section restyled as cards of `SettingRow`s, and the Settings window goes.
**Design references:** §3 R1, R2, R4, R5, R22, R23, §5.7 (*settingsLeft*, `.settings` entry), §5.8 (`cancelOperation`, `firstRunSettings`, capture routing), §5.9 (*Settings*, *Dialogs*); `DESIGN.md` — Settings card, SettingRow, Segmented pill switch, toggle, radio lists with a filled accent ring, sentence-case group labels; mockup `mockup-v6-overview.html` (General, Meetings)
**Category:** hybrid — full TDD for the `SettingsModel` changes; the section pages are platform-only/UI wiring (a mechanical mapping of existing controls, bindings and texts).
**Touches:**
- create `App/Settings/SettingsPage.swift`, `App/EditMenu.swift` (moved verbatim from `App/Settings/SettingsWindowController.swift:56-83`)
- edit `App/Settings/SettingsModel.swift` (`Section.history.title` → `Dictations` at `:83`; `openHistory`/`openMeetings` dependencies and methods removed; `selection` `didSet` calls `cancelCapture()` when leaving `.hotkeys`), and the nine section views `App/Settings/GeneralSection.swift`, `HotkeysSection.swift`, `KeysSection.swift`, `CleanupSection.swift`, `VocabularySection.swift`, `HistorySection.swift` (`Open History…` at `:35` removed; Clear History through `DSDialog` with its texts), `MeetingsSection.swift` (`Open Meetings…` at `:133` removed), `OverlaySection.swift`, `SoundSection.swift`, plus `App/Settings/CorrectionsEditor.swift`, `App/Settings/ProfilesEditor.swift`, `App/Settings/HotkeyCaptureField.swift` where they carry styling
- edit `App/Main/SidebarView.swift` (the nine sections under Settings while `destination == .settings`; ⌘,), `App/Main/MainWindowController.swift` (`MainWindow.cancelOperation` → `cancelCapture()` when capturing; `hide()` and `windowWillClose` cancel capture), `App/Main/MainWindowModel.swift`, `App/AppDelegate.swift` (Settings… and the sidebar row → `main.show(.settings)`; `firstRunSettings` → the same; `GlobalKeyListener` capture actions → the main window's `SettingsModel`; `apply(_:)` refreshes it; `clearHistory` also calls `search.invalidate()`; entering `.settings` calls `refreshKeys()`)
- delete `App/Settings/SettingsWindowController.swift`, `App/Settings/SettingsView.swift` (`SettingsPane`, `SettingsFootnote` and `settingsBinding` move to `SettingsPage.swift` or are replaced by `SettingRow`)
- edit `AppTests/SettingsModelTests.swift` (harness without `openHistory`/`openMeetings`; `:569` order unchanged; `:767` test removed)

**Steps (TDD):**
1. Write tests in `SettingsModelTests`: `historySectionIsTitledDictations`; `leavingTheHotkeysSectionCancelsCapture` (capturing, `selection = .keys` → `hotkeys.cancelled == 1`, combo restored); `changingSectionWhileNotCapturingCancelsNothing`.
   Expected initial failure: `#expect(SettingsModel.Section.history.title == "Dictations")` → `"History"`; `#expect(hotkeys.cancelled == 1)` → `0`.
2. Run `-only-testing:AppTests/SettingsModelTests` — confirm the two assertion failures.
3. Implement the model changes; remove the `openHistory`/`openMeetings` dependencies and methods together with the harness arguments at `:97` and `:102` and the `openMeetings()` test at `:767` (a behaviour-preserving deletion once the buttons go); build `SettingsPage` and restyle the nine sections by the §5.9 mapping (label-and-control → `SettingRow`; footnote → the row's description; `Divider()`/heading → new card with group label; editors and previews span the card; General's cards Dictation and Updates; Meetings' Engine, Recording, Summary, Storage, Command line and agents; the two described exceptions *Live transcript* and *Check for an update now*); move `EditMenu`; wire capture and Esc; delete the Settings window.
4. Run the suite — pass. Full app suite and build — no regressions (`KeysSectionTests`, `HotkeyBindingsTests`, `OverlayPreviewViewTests` stay green).
5. Integration check (built app): menu `Settings...` and ⌘, open Settings at the last section; the nine sections appear under Settings only while it is shown; every control of every section still reads and writes `config.json` (spot-check one per section); capture a hotkey and press Esc, switch section, click Meetings, and hide the window — each restores the previous combo; ⌘C/⌘V work in the key fields; with no OpenAI key, launch opens the main window at Settings.

**Definition of done:** the Settings window and its controller are gone; R22's capture rules tested or checked; `Open History…` and `Open Meetings…` gone with their dependencies; every section in cards.

**Risks specific to this stage:** a binding lost in the restyle. Mitigation: the restyle changes containers only — each control keeps its existing `settingsBinding` call — and the integration check touches every section.

### Stage 12 — Finished-meeting model and summary rendering
**Goal:** the meeting model exposes everything the finished and live pages show — summary blocks with a regenerate notice, tab, chips, pill text, copy payload and state — and summaries render from blocks.
**Design references:** §3 R3, R11, R13, R15, R16, R17, §5.6 (`SummaryPanel.ready`), §5.9 (*Sidebar* pill, *Finished meeting*, *Live meeting* source line), §5.14 (*Copy*), §5.16, §5.17, §5.20
**Category:** hybrid — full TDD for `MeetingWindowModel` and `SummaryRichText`; `SummaryView` and `RichPasteboardWriting` are platform-only/UI wiring.
**Touches:**
- edit `App/Meeting/MeetingWindowModel.swift` (`SummaryPanel.ready(blocks:meta:notice:)` with `Notice` `.rewriting` / `.failed(String)`; the document parsed once per summary event; `sections(of:)` and `SummarySection` removed; `selectedTab` set when the meeting first becomes stopped; `notesTabTitle`; `chips`; `pillTitle`/`pillDetail`; `canCopySummary`, `canRegenerate`, `regeneratePrompt`; `copyPayload` (Markdown, HTML, RTF); `justCopied` cleared after 1.5 s on an injected `clock`, defaulting to `SystemClock()`; the source-line suffix for non-test meetings)
- create `App/Meeting/SummaryView.swift` (blocks in a 640-point `LazyVStack`, heading levels mapped to `type.heading`, `.heading.2`, `.heading.3`, items indented 20 points per depth, deeper items secondary, rules as hairlines, code on a card, the meta line, the notice status lines), `App/Meeting/SummaryRichText.swift` (`rtf(title:blocks:)`), `App/Meeting/RichPasteboardWriting.swift` (`write(markdown:html:rtf:)` clearing the pasteboard and setting `.string`, `.html`, `.rtf`)
- edit `App/Meeting/MeetingView.swift` (`SummaryPanelView` at `:250-320` replaced by `SummaryView`, which the meeting window shows until Stage 14)
- edit `AppTests/MeetingWindowModelTests.swift` (`:304-415` summary fixture and cases rewritten for blocks); create `AppTests/SummaryRichTextTests.swift` (sibling `AppTests/MeetingExporterTests.swift`)

**Steps (TDD):**
1. Write tests in `MeetingWindowModelTests` using the shared `ManualClock`: `summaryPanelForEachOfTheSixStates` (none, writing, ready, failed, rewriting → `.ready` with `.rewriting` notice, kept → `.ready` with `.failed(reason)`); `fourSectionSummaryRendersAsHeadedBlocks`; `partialMarkStaysInTheMeta`; `opensOnSummaryOrOnTranscriptForATestCall` and `tabIsSetOnlyWhenTheMeetingFirstStops`; `notesTabCountsOnlyAboveZero`; `chipsReadDateRangeDurationModeSpeakersAndCost` (`+N` after three names); `pillTextIsMinutesSecondsUnderAnHourThenHours`, `pillReadsPausedAndStarting`; `copyAndRegenerateAvailability`; `regeneratePromptNamesTheCurrentCost`; `copyPayloadCarriesTitleAndSummaryInThreeForms`; `justCopiedClearsAfter1point5Seconds` (true after copy; `clock.wake()` after a recorded `.milliseconds(1500)` sleep → false); `sourceLineInvitesEditingOnlyOutsideATestCall`. Write `SummaryRichTextTests`: `stringIsTitleThenBlocksInOrder`, `itemsAreIndentedByDepth` (paragraph style `headIndent` 20 × depth), `rtfIsNonEmptyAndReadsBackToTheSameString`, `linksAreNotCarried`.
   Expected initial failure: `MeetingWindowModelTests` fails to compile — `enum case 'ready' has no associated value 'blocks'` style pattern errors and `value of type 'MeetingWindowModel' has no member 'selectedTab'`; `cannot find 'SummaryRichText' in scope`.
2. Run `-only-testing:AppTests/MeetingWindowModelTests -only-testing:AppTests/SummaryRichTextTests` — confirm; add the members returning defaults and an `rtf` returning empty data; re-run and confirm assertion failures (`notice == .rewriting` → `nil`; `rtf.isEmpty == false` fails).
3. Implement the model members, `SummaryRichText`, `RichPasteboardWriting` and `SummaryView`; swap `SummaryPanelView` for `SummaryView` in the meeting window; remove `sections(of:)` and `SummarySection`.
4. Run both suites — pass. Full app suite and build — no regressions.
5. Integration check (built app): open a stored four-section meeting and a topic-based one (Regenerate is not wired yet, so produce a topic summary with *Summarise* on a meeting without one) — headings, nested bullets and bold render in one column, links show as text.

**Definition of done:** §5.20's *MeetingWindowModel* and *SummaryRichText* rows pass; the two-column grid and `SummarySection` are gone; the old window renders blocks.

**Risks specific to this stage:** `NSAttributedString` RTF output differs by OS. Mitigation: tests read the RTF back and compare the string and paragraph indents, not the bytes.

### Stage 13 — Meeting sessions behind present and dismiss
**Goal:** `MeetingCoordinator` holds `current`, `opened`, `finishing` and `shown` and drives one meeting surface through `present`/`dismiss`, with the release, page-left and finishing rules of §5.5; the surface is, for this stage only, a single reused meeting window.
**Design references:** §3 R9, R10, R12, R16, R17, §5.5 (as corrected), §5.6 (`MeetingControlling`), §5.14 (*Record a meeting*, *Stop with the window hidden*), §5.15, §5.20
**Category:** hybrid — full TDD for the coordinator; the transitional window adapter is integration-verified. The coordinator is the riskiest new logic of the feature (design §7), so it lands on a surface that is already known before Stage 14 swaps that surface for pages.
**Touches:**
- edit `App/Meeting/MeetingCoordinator.swift` (`MeetingWindowPresenting` and `Dependencies.makeWindow` replaced by `present` and `dismiss`; `Session` loses `window`, gains `isStopping`; the four slots; `openChooser`, `toggle`, `show`, `open(id)`, `pageLeft()`, `isOpen`, `liveModel`; the `.state(.stopped)` and finishing rules; `MeetingActions` loses `backToMeetings` and `closed`, gains `back`, `copySummary`, `regenerate`; `cancel`/`back` → `dismiss`; `openSettings` selects the Meetings section; `MeetingControlling.regenerateSummary()`; a `copy` dependency that receives the model's `copyPayload`)
- edit `App/Meeting/MeetingWindowController.swift` (one reused instance: `show(model:actions:)` swaps the hosting view; closing calls an `onClose` hook; no `MeetingWindowPresenting`), `App/Meeting/MeetingView.swift` (the *Meetings* button → `actions.back`), `App/AppDelegate.swift` (`present` → the reused window, `dismiss` → close it, `onClose` → `coordinator.pageLeft()`; `copy` → `RichPasteboardWriting`; `openSettings` → `main.show(.settings)` with `.meetings` selected)
- edit `AppTests/MeetingCoordinatorTests.swift` (the 26 tests ported from `StubWindow` to recorded `present`/`dismiss` calls; `StubController` gains `regenerateSummary`)

**Steps (TDD):**
1. Port the 26 tests to a harness that records `present(model)` and `dismiss()` and calls `pageLeft()` where a window close was simulated. Add one `@Test` per §5.5 row: `openChooserShowsAnActiveMeeting`, `openChooserPresentsAnIdleChooserAgain`, `openChooserReleasesAStoppedCurrentAndOpened`; `toggle…` (unchanged rows kept); `openPresentsASessionAlreadyHoldingTheMeeting`, `openPromotesAFinishingSessionAndReleasesThePreviousOpened`, `openDropsAnIdleChooser`; `pageLeftDropsAnIdleChooser`, `pageLeftKeepsAnActiveMeeting`, `pageLeftReleasesAStoppedMeeting`, `pageLeftWhileItsSummaryIsWritingKeepsItFinishing`; `stopWhileShownKeepsTheSession`; `stopNeverPresents` (R4: Stop Meeting does not open or move the window); `stopWhileNotShownMovesTheSessionToFinishingThenDropsItOnTheSummary` (event order `.state(.stopped)` before `.summary(.writing)`); `stopWithoutSummaryDropsTheSessionWhenStopReturns`; `presentingAnotherSessionReleasesThePreviouslyShownOne`; `isOpenCoversCurrentOpenedAndFinishing`; `liveModelIsCurrentsWhileActive`; `regenerateActionCallsTheController`; `copyActionHandsThePayloadToCopy`; `cancelAndBackDismiss`; `openSettingsSelectsMeetings`.
   Expected initial failure: `MeetingCoordinatorTests` fails to compile — `extra arguments 'present', 'dismiss'` / `missing argument for parameter 'makeWindow'` in `MeetingCoordinator.Dependencies`, and `type 'MeetingActions' has no member 'back'`.
2. Run `-only-testing:AppTests/MeetingCoordinatorTests` — confirm; add the new dependencies and members with empty bodies (and `makeWindow` gone); re-run and confirm assertion failures (`presented.count == 1` → `0`; `isOpen(id) == false` after a drop → `true`).
3. Implement §5.5 as corrected (release includes "Stop still returning"); a session moved out of `shown` by another `present` gets the `pageLeft` rule; promoting from `finishing` releases a different `opened` first; adapt `MeetingWindowController` and `AppDelegate` to the transitional single window.
4. Run the suite — pass. Full app suite and build — no regressions (`TestCallSessionTests` stay green).
5. Integration check (built app): start a meeting from the menu, close the meeting window — recording continues, *Show Meeting…* brings it back; stop it from the hotkey with the window closed — the summary is written and the Meetings page reloads with it; open a stored meeting from the Meetings page, then another — one meeting window, the first no longer blocks its delete; Cancel on the chooser closes it.

**Definition of done:** every §5.5 row and the 26 ported tests pass; `MeetingWindowPresenting` is gone; one meeting window at most.

**Risks specific to this stage:** session lifetime regressions (design §7). Mitigation: one test per table row, the event-order case pinned, and the transitional surface is the existing window whose behaviour the hand check knows.

### Stage 14 — Meeting pages, recording pill, Regenerate and Copy
**Goal:** the chooser, live and finished meetings are pages of the main window, the recording pill replaces Start Meeting while a meeting is active, and the finished page offers Copy summary and Regenerate; the meeting window is gone.
**Design references:** §3 R1, R3, R4, R5, R6, R9, R10, R11, R13, R16, R17, R19, R23, §5.5 (`present`/`dismiss`), §5.7 (`showMeeting`, `back`), §5.9 (*Sidebar*, *Finished meeting*, *Chooser and Test Call setup*, *Live meeting*, *Dialogs*), §5.14; `DESIGN.md` — Pill button, Segmented pill switch, Chip, Status line, Dialog, Tile, the recording-pill motion rule; mockups `mockup-v6-recording.html`, `mockup-v6-overview.html`
**Category:** platform-only/UI wiring — every rule these pages show was put under test in Stages 7, 12 and 13; what remains is SwiftUI layout and AppKit wiring, checked by build and by hand.
**Touches:**
- create `App/Meeting/MeetingPage.swift` (switches on the model's state), `App/Meeting/ChooserPage.swift` (with the Test Call setup step), `App/Meeting/LivePage.swift`, `App/Meeting/FinishedPage.swift` (top bar: back pill, Copy summary, Regenerate, Export ▾; title; chips; `Summary · Transcript · Notes · N`; Score pane beside the transcript for a test call; Regenerate and merge-speakers `DSDialog`s), `App/Meeting/TranscriptView.swift`, `App/Meeting/NotesPane.swift`, `App/Meeting/SpeakerColor.swift` (with `PaneHeader`, moved from `MeetingView.swift:659-688`), `App/Main/RecordingPill.swift` (four bars pulsing while `.recording`, still when paused or under Reduce Motion)
- edit `App/TestCall/TestCallSetupView.swift`, `App/TestCall/ScriptPane.swift`, `App/TestCall/ScorePane.swift` (restyled with components: pane header, the current line on an accent-soft card labelled `Your line — read it aloud`, chips for per-voice rates, the display serif for the word error rate), `App/Main/SidebarView.swift`, `App/Main/MainView.swift`, `App/Main/MainWindowModel.swift` (`liveMeeting`; the meeting page's model and actions), `App/AppDelegate.swift` (`present` → `main.showMeeting`, `dismiss` → `navigation.back()`, `meetingPageLeft` → `coordinator.pageLeft()`; *Start Meeting…* and *Show Meeting…* through the coordinator to the page; ⌘[)
- delete `App/Meeting/MeetingView.swift`, `App/Meeting/MeetingWindowController.swift`

**Steps (platform-only/UI wiring):**
1. Build the four pages and the pill to `mockup-v6-recording.html`, moving `TranscriptView`, `NotesPane`, `NoteEditor`, `TitleField`, `MarkerLine` and `Banner` out of `MeetingView.swift` unchanged in behaviour and restyled with `DS`.
2. Wire `present`/`dismiss`/`pageLeft` to the main window and navigation; route Copy summary through `actions.copySummary` and Regenerate through the `DSDialog` to `actions.regenerate`.
3. Delete `MeetingView.swift` and `MeetingWindowController.swift`.
4. Run the full core and app suites and the app build — all green (`MeetingCoordinatorTests`, `MeetingWindowModelTests`, `TestCallPaneModelTests`, `TestCallSetupModelTests` unchanged).
5. Integration check (built app, light appearance): ⌘N shows the chooser page; Test Call… shows the setup step and Back returns; Cancel returns to the page it came from; Start records — the pill shows the title, `mm:ss`, then `Paused`; open Dictations, click the pill — the live page; ⌘W, hotkey Stop — window stays hidden, summary written; reopen the meeting — Summary tab; Copy summary, paste into TextEdit (rich) and a plain-text field (Markdown); Regenerate — confirmation with the cost, `Writing a new summary…` while the old summary stays, the new one replaces it and the cost chip grows; Regenerate with the Anthropic key removed — `Not regenerated: …`; a remote test call end to end opens on Transcript with the Score pane; rename a speaker onto another name — merge `DSDialog`; edit a paragraph by double-click; reconnecting chip, silence hint and quit confirmation as before; open a stored meeting from Search, ⌘[ returns to the results.

**Definition of done:** no reference to `MeetingView`, `MeetingWindowController` or a meeting `NSWindow` remains; R3, R9–R11, R13, R16, R17 hand-checked; both suites green.

**Risks specific to this stage:** behaviour lost while moving `TranscriptView` (editing, reassign menu, rename popover). Mitigation: the move keeps each view's code and model calls as they are; the integration check exercises each R13 behaviour.

### Phase D — Theme, small windows, documentation

### Stage 15 — Theme setting
**Goal:** Settings → General → Appearance offers System, Light and Dark; the choice applies app-wide from launch, onboarding included, and the overlay is unaffected.
**Design references:** §3 R8, §5.2, §5.8 (*Theme*, as corrected), §5.9 (*Settings* — General's Appearance card), §5.15, §5.18; `DESIGN.md` — Segmented pill switch, decision 5
**Category:** hybrid — full TDD for `SettingsModel`'s theme; `ThemeApplier` and the launch order are integration-verified.
**Touches:**
- create `App/ThemeApplier.swift`
- edit `App/Settings/SettingsModel.swift` (`theme`, `setTheme(_:)`, `refresh(from:)` reads it), `App/Settings/GeneralSection.swift` (Appearance card between Dictation and Updates), `App/AppDelegate.swift` (`applicationDidFinishLaunching` creates the one `ConfigStore`, applies the theme, then shows onboarding or calls `startNormal(configStore:)`; `apply(_:)` calls `ThemeApplier` on every change; `Log.ui.info` with the value only)
- edit `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write `setThemeWritesTheKey` (`await model.setTheme(.dark)` → `store.load().theme == .dark`), `refreshReadsTheTheme`, `themeStartsFromTheConfig`.
   Expected initial failure: `value of type 'SettingsModel' has no member 'setTheme'`.
2. Run `-only-testing:AppTests/SettingsModelTests` — confirm; add `theme` and an empty `setTheme`; re-run and confirm `theme == .dark` → `.system`.
3. Implement; add `ThemeApplier`, the Appearance card and the launch reordering.
4. Run the suite — pass. Full app suite and build — no regressions.
5. Integration check (built app): set Dark with the system in Light and vice versa — main window, a `DSDialog`, the rename popover, an export panel and the quit alert follow; System follows the system; relaunch keeps it; with permissions revoked, onboarding opens in the chosen theme; dictate once in each theme — the overlay looks identical.

**Definition of done:** theme persisted and applied at launch and on change; tests pass; overlay unchanged by hand check.

**Risks specific to this stage:** reordering launch could start something before onboarding. Mitigation: only the `ConfigStore` construction and the theme move ahead; `startNormal` keeps its body and order.

### Stage 16 — Correction, Onboarding and About
**Goal:** the three small windows follow the language: Correction restyled at 560 points and sized to content, Onboarding as a SwiftUI view at 460×330, About as a 300×300 window.
**Design references:** §3 R23, R24, §5.8 (*Activation*), §5.9 (*Small windows*); `DESIGN.md` — Pill button, Segmented pill switch, Settings card, CloudPulseMark on a Tile; mockup `mockup-v6-windows.html`
**Category:** platform-only/UI wiring — the windows' logic lives in `CorrectionModel` and `OnboardingModel`, whose suites stay unchanged and green; the change is layout and window hosting.
**Touches:**
- edit `App/Correction/CorrectionView.swift`, `App/Correction/CorrectionWindowController.swift` (sized to the hosting view's fitting height at each `show`)
- create `App/Onboarding/OnboardingView.swift`; edit `App/Onboarding/OnboardingWindowController.swift` (hosts it; keeps the 1.5 s poll and the unclosable window)
- create `App/AboutWindowController.swift`, `App/AboutView.swift`; edit `App/StatusItemController.swift` (`.about` at `:106`), `App/AppDelegate.swift`; delete `App/AboutPanel.swift`

**Steps (platform-only/UI wiring):**
1. Restyle `CorrectionView` keeping every field, its order and binding (sentence-case labels, Scope as a `SegmentedPill`, Save as the filled pill).
2. Build `OnboardingView` over `OnboardingModel` with the §5.9 texts; host it at 460×330.
3. Build `AboutView` with `CloudPulseMark`, the version and the three lines of `AboutPanel.swift:15-18`; `AboutWindowController` through `WindowActivation`; remove `AboutPanel`.
4. Run the full app suite (`CorrectionModelTests`, `OnboardingModelTests` unchanged) and build — green.
5. Integration check (built app, both themes): *Correct Last Dictation…* and a Dictations row's Correct… open Correction with today's fields and behaviour; launch with a permission revoked — onboarding cannot be closed, shows `Not granted yet` / `Granted`, Continue enables once both are granted; *About Mini Whisper* opens the 300×300 window and closes from its close button.

**Definition of done:** `AboutPanel` gone; the three windows match `mockup-v6-windows.html` in both themes; model suites unchanged and green.

**Risks specific to this stage:** None beyond layout.

### Stage 17 — Documentation
**Goal:** the repository's documents describe v6.
**Design references:** §5.19, §9
**Category:** non-TDD (config-only) — documentation only; nothing executable changes.
**Touches:** `README.md` (the main window, Dictations, search, theme, topic summaries, Regenerate and Copy), `CLAUDE.md` (layout: `App/Design`, `App/Main`, `App/Search`; module map: `MWMeetings` gains `SummaryDocument`, `SearchExcerpt`; `MWUsage` gains `UsageTotals`), `CHANGELOG.md` (`[Unreleased]`: Added, Changed, Removed — including the Today row's `2h 14m` format and the prompt migration)

**Steps (non-TDD):**
1. Edit the three files.
2. Check: `grep -n "History window\|Meetings window\|History\.\.\." README.md CLAUDE.md` returns nothing stale; `project.yml` `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` still read `0.6.2` (R28); `git diff --stat -- Packages/MiniWhisperCore/Package.swift project.yml` is empty (R25).
3. Run both suites and the app build one last time — green.

**Definition of done:** the three documents match the shipped behaviour; no version bump.

**Risks specific to this stage:** None.

## Cross-cutting concerns

- **Security** — Summaries are model output over untrusted speech. `SummaryDocument.inline` strips links and images (Stage 1) before any view renders it (Stage 12); `html(title:)` escapes every text node and emits a fixed tag set with no attribute (Stage 1, tested), and `SummaryRichText` carries text, fonts and indents only (Stage 12, tested), before Copy is wired (Stages 13–14). `main_window_frame` is rejected when malformed or non-finite (Stage 2) and clamped to a screen (Stage 7) before Stage 10 hands it to AppKit. The summariser's data rule and escaping are untouched. No secret is read or written by any stage; key handling stays in Settings → Keys.
- **Performance** — `SummaryDocument` parses once per summary event and the blocks render lazily (Stages 1, 12). Search loads each meeting once per search session off the main actor and caches text only (Stage 8). The Meetings page reads the index only (Stage 10). The frame is written at hide, close and quit, never during a resize (Stage 10). The transcript reduction (`MeetingWindowModel.swift:597-725`) is not touched.
- **Observability** — `Log.ui.info` for window shown/hidden, frame restored or defaulted (Stage 10), theme applied (Stage 15), prompt migrated (Stage 3); `Log.ui.warning` for frame-write and migration failures (Stages 10, 3); `Log.meeting.info` for regenerate started and its result (Stage 4); `Log.meeting.warning` for meetings skipped by search (Stage 8). No log line carries summary, transcript, dictation or query text; Stages 4 and 8 assert it.
- **Compatibility / migration** — `config.json` gains two additive keys (Stage 2), `meeting.json` one additive key that decodes as 0 when absent (Stage 1), `index.json` no shape change; 0.6.2 reads all of it. The prompt migration touches only an unmodified legacy file (Stage 3). Between stages the app is in a mixed but working state, never released:

  | After stage | What the user sees |
  |---|---|
  | 1–5 | Today's windows; new summaries are topic-based; the menu's Month row shows tokens and audio; Regenerate exists in the controller with no button yet |
  | 6–9 | Today's windows, with the Dock icon following every window correctly |
  | 10 | Main window with Meetings, Dictations, Search; Settings opens its old window; meetings open in the old meeting window |
  | 11 | Settings in the main window |
  | 12 | The old meeting window renders summaries as blocks |
  | 13 | One reused meeting window driven by the new coordinator |
  | 14 | Meeting pages and the recording pill; no meeting window |
  | 15–17 | Theme, small windows, documents |

  R16 and R17 are delivered across Stages 1, 4, 12, 13 and 14: the rules land first, the buttons last; until Stage 14 neither action is reachable by the user, so no half-built action is exposed. They are not bundled into one stage because the controller, model and coordinator layers each carry their own tests and would make one stage too large to review.

## Verification

Once Stage 17 is in, on a built app (`xcodebuild … build`, then run `.dd/Build/Products/Debug/Mini Whisper.app`), in Light and in Dark:

1. Both suites green: `swift test` (all 17 runs `✔`) and `xcodebuild … test` (`** TEST SUCCEEDED **`).
2. Walk R1–R24 in order against the main window, using the integration checks of Stages 9–16 as the script; then the R13 list one by one; then a remote test call end to end.
3. On the developer's Mac, whose `summary_prompt.txt` equals the legacy default (§5.19), the first launch migrates it (`summary prompt migrated` in the debug log with `--debug`) and the next new meeting's summary has topic sections and a `## Next Steps`.
4. A stored four-section meeting still renders, its Meetings row still shows its first sentence, and Regenerate turns it into a topic summary with its cost added to the total.
5. Relaunch restores the window frame; quitting during a recording asks first and saves without a summary.
6. `config.json` holds `theme` and `main_window_frame`; 0.6.2 opened on the same files (from the `v0.6.2` tag) still starts, lists meetings and shows a topic summary as headed sections (rollback, §9).

## Risks and open issues

| Risk | Mitigation |
|---|---|
| Stage 10 and Stage 14 are large UI stages | Their logic is in models tested in earlier stages; each carries an integration checklist keyed to the R numbers it touches |
| Concurrent app-test runs in two worktrees launch two test hosts with bundle ID `com.ips.mini-whisper`, which is unproven | No batch holds two stages that run the app-test suite (see *Execution schedule*) |
| The transitional single meeting window of Stage 13 is code deleted in Stage 14 | It reuses the existing `MeetingWindowController` with a small change; the cost buys an isolated, tested coordinator change |
| A hand check finds a mockup detail the components cannot express | Change the component in `App/Design` in the stage that needs it; never fork a page-local copy |
| A `swift test` focused filter hangs on a regenerate test waiting for an event | Scaffolds emit a terminal event (Stage 4 step 2); every regenerate test waits on a terminal summary event |
| The release freeze lasts all 17 stages | An urgent fix ships from a branch off `v0.6.2` (design §9); pull before committing after any release, as `CLAUDE.md` requires |

## Planning decisions taken

1. **Seventeen stages in four phases** — design §9's seven steps, with its step 3 split into Stages 7, 9, 10 and 11, its step 4 into Stages 12–14 and its step 5 moved ahead as Stage 8, so that each stage fits one review; the plan owns staging order.
2. **Core first, UI last** — every rule the pages show is tested before a view uses it, so the UI stages are wiring.
3. **Search before the shell, swapped atomically in Stage 10** — `SearchModel` lands additively in Stage 8; list search and the two list windows go in the same stage that adds the sidebar search, so search is never missing.
4. **Settings moves in its own stage (11)** — the sidebar's Settings row opens the old Settings window during Stage 10 only.
5. **The coordinator changes before the meeting pages (Stage 13 before 14), on a transitional single meeting window** — isolates the riskiest logic (design §7) from the largest view port.
6. **Fact correction to design R26 and §5.20** — `AppTests` cannot link `MWTestSupport` (`project.yml` gives it only the app target; `App/TestCall/TestCallSession.swift:8-9` says so), so app suites use a manual `MWSupport.Clock` fake, hoisted to `AppTests/ManualClock.swift` in Stage 8; corrected in the design.
7. **Fact correction to design §5.8** — `ConfigStore.load()` writes defaults, a corrupt-file backup and the `daily_usage` migration (`ConfigStore.swift:75-120`); loading it before onboarding moves those writes earlier and adds none; corrected in the design.
8. **Fact correction to design §5.5's release rule** — `MeetingController.stop` emits `.state(.stopped)` before `.summary(.writing)` (`MeetingController.swift:451-452`), so release also keeps a session whose `stop()` has not returned and drops it when `stop()` returns with no summary under way; corrected in the design.
9. **Design internal contradiction, R7 over §5.8's list** — `WindowActivation` also replaces the unconditional `.accessory` of `AppUpdater` and `SpeechModelPrompt`, which would hide the Dock icon with the main window open; corrected in the design, delivered in Stage 9 for every window at once.
10. **Fact correction to design §5.9 and §7: six in-window confirmations, not five** — Settings → Dictations' Clear History (`HistorySection.swift:38`) is also an in-window clear-dictations confirmation and uses `DSDialog` with its texts (§6 rejects native in-window dialogs); corrected in the design.
11. **Presenting another session applies the page-left rule to the one shown before, and promoting a `finishing` session releases a different `opened` first** — otherwise an unseen session would keep blocking its meeting's delete, against R12's wording; §5.5 does not say what happens to the outgoing session.
12. **`MeetingCoordinator.Dependencies` gains `copy`** — the coordinator hands the model's payload to an injected writer, so its tests never touch `NSPasteboard.general`.
13. **`HistoryListModel.Dependencies` gains `changed`, and Settings' `clearHistory` closure also invalidates search** — the producer of §5.12's "every dictation delete or clear call `invalidate()`".
14. **`MeetingWindowModel` gains an injected `clock` (default `SystemClock()`)** for `justCopied`, so the 1.5 s is tested without sleeping.
15. **`UIEventRouter` forwards usage to the main window through an injected closure** (Stage 10), keeping the router free of a main-window type.
16. **Regenerate tests in a new `MeetingControllerRegenerateTests.swift`** (sibling of `MeetingControllerEditingTests.swift`) rather than the 560-line `MeetingControllerTests.swift`; `FakeSummarizer` gains a result queue and a hold gate.
17. **Shared app-test helpers hoisted** — `ManualClock` and `StubLibrary` move out of `MeetingsListModelTests` into `AppTests/ManualClock.swift` and `AppTests/StubMeetingLibrary.swift` (Stage 8) for `SearchModelTests` to reuse.
18. **The private `Chip` in `MeetingView.swift:690` is removed in Stage 6** — the new `Chip` component has the same name; one definition avoids an ambiguous type lookup.
19. **The TEST chip has no border and score error words use the recording colour (Stage 6)** — the accepted mockups draw `.chip.test` with a transparent border and `.err` in `--rec` (§5.9: the mockup wins); `color.test.border` and `color.error.text` leave the code, which keeps R23's light-and-dark rule for every colour used.
20. **`DESIGN.md` and `design/specimen.html` enter version control with the `DS` tokens (Stage 6)**, so the record and the code that implements it land together.
21. **A bundled-resource guard test (`AppTests/BundledResourcesTests.swift`)** pins the shipped prompt to the §5.3 text, so the migration can never loop back to a legacy default.
22. **Batch 1 runs Stages 1 and 2 in parallel; every other batch is serial** — see the schedule; app-test stages never share a batch.

## Deviations from the design

None — plan matches design v6 exactly.

## Deviations from plan

- Before Stage 1: `DESIGN.md` and `design/specimen.html` entered version control with the feature documents in `736827b`, not in Stage 6, so every checkout carries the design language. Stage 6 leaves both as they are.
- Batch 1: Stage 1 left the parallel wave. Its *Touches* missed `Tests/MWMeetingsTests/TestCallModelTests.swift`, a file a worktree may not cross into, so it was finished serially in the main tree and Stage 2 landed after it by cherry-pick.
- Stage 1: `TestCallModelTests.legacyMeetingAndIndexDecodeWithoutATag` asserted that a v0.5 `meeting.json` re-encodes byte for byte. Design §5.2 always encodes `replacedSummaryCostUSD`, so the test now expects the legacy bytes plus that one key; the index bytes are unchanged.
- Stage 1: parsing rule 3 matches `^ {0,3}(#{1,6})\s+` and cuts the closing `#`s and whitespace by hand. Same result as `(.*?)\s*#*$`, which backtracks quadratically on a long run of `#` or spaces; `aLongRunOfHashesOrSpacesParsesInLinearTime` guards it.
- Stage 1: rule 5's `\d` is ASCII-only, because `Int` reads no other digits.
- Stage 1: tests beyond the named ones: `billingAlwaysEncodesReplacedCost`, `aLongRunOfHashesOrSpacesParsesInLinearTime` and edge cases in `SummaryDocumentTests`.
- Stage 2: two tests beyond the named ones: `themeAndWindowFrameNeverLandInExtra` (both keys in `Key.all`) and `nonFiniteWindowFrameReadsAsAbsentWhateverTheDecoderAllows` (the stock `JSONDecoder` already refuses `1e999`, so only a decoder converting non-finite spellings reaches `WindowFrame`'s own check).
- Stage 3: two tests beyond the named ones, for §5.15's *cannot read or write* row: `migrationThrowsOnAnUnreadableFileAndLeavesIt` and `migrationThrowsWithoutABundledDefaultAndLeavesTheLegacyFile`. `migrationMatchesIgnoringSurroundingWhitespace` runs two cases: the trimmed text Settings saves, and the text with leading spaces and an extra newline.
- Stage 3: `legacySummaryDefaults[0]` is the file as `git show e64ed39:…` prints it, final newline included; the match trims both sides, so behaviour is the same as without it.
- Outside the stages: `RepeatingTimerTests.firesRepeatedlyUntilStopped`, an existing test, failed about once in sixty runs. `stop()` cancels the timer but does not interrupt a tick already running, which could land after the count was read. The test now drains the timer's queue before counting (400 repetitions green); `RepeatingTimer` is unchanged.
- Stage 4: one test beyond the named ones, `regeneratingTwiceAddsEachReplacedCostAndLogsNoSummaryText`: it uses `FakeSummarizer`'s result queue, checks that a later save keeps the replaced cost, and pins the log lines of the success path. The suite carries `.timeLimit(.minutes(1))`, so a wait that never returns fails instead of hanging the run.
- Stage 4: `logging(to:_:)` in `Tests/MWMeetingPipelineTests/MeetingControllerTestCallTests.swift`, a file outside the stage's *Touches*, lost its `private` so the new suite reuses it.
- Stage 5: `DayEntry.add(_:)`, for a `DayEntry` and for a `ProviderUsage`, is a public extension in `MWUsage/UsageTotals.swift`. The month sum would have been the third copy of the accumulation in `UsageStore.add` and `FakeUsageStore.add`; all three now call it.
- Stage 5: `PricingTests.partialMinutesFloor`, not in the stage's list, also moved to `UsageTotals`. `usageTableAt0_59And134Minutes` also checks `1h 0m` and `10h 0m`.
- Stage 6: the user's speaker colour is `SpeakerColor.user`, `DS.Colors.accent`, where it was the system accent. `App/TestCall/ScriptPane.swift`, outside the stage's *Touches*, reads it for `.you`, so the user has one colour in the transcript and the script.
- Stage 6: `DS` holds values beyond the tested palette, each read off the mockups: `Colors.white`, `knobShadow`, `scrim` and `dialogShadow`, `Radius.small` (6), `Size` (`hairline`, `control` 30, `controlSmall` 24, `pageColumn` 736, `readingColumn` 640) and `TextStyle.label` (11/14 semibold, chips). `typeScaleMatchesDesignMD` pins line heights, weights and designs as well as point sizes.
- Stage 6: `textStyle(_:)` gives each line the style's line height, as CSS does: the font, line spacing and half the difference above and below. The mockups' boxes include their 1-point border, so padding inside a bordered component adds `DS.Size.hairline`.
- Stage 6: `DSFieldStyle` is a `ViewModifier` applied with `.dsField()`, not a `TextFieldStyle`, so it also dresses a `TextEditor` (`.area`). `SearchPill` lives in `DSFieldStyle.swift` and `PulseBars` in `StatusLine.swift`, each a view of its own. `DSToggleStyle` draws the switch only; the label reaches assistive technology through an accessibility representation.
- Stage 6: a setting's description uses `type.meta` (12/16); the mockup's `.set .d` is 12/17, so a row is a point shorter per description line.
- Stage 6: the components were also rendered to bitmaps, light and dark, by a temporary test that is not in the commit, and compared with the mockups. The hand check in the running app is still due.
- Stage 7: one rule beyond §5.7. Clearing the query on a meeting page opened from results sets `origin` to `beforeSearch`; otherwise Back would lead to a results page with no query. `clearingTheQueryOnAMeetingOpenedFromResultsMovesTheOriginToThePageBefore` covers it.
- Stage 7: `go` to the current destination calls `entered` again, which is how showing the window reloads its page (§5.7); the leaving hooks fire only when the destination changes, and `showMeeting` applies them too, so opening a meeting from Settings calls `settingsLeft`. Hooks run after the state is set. A query counts as empty only when it has no characters.
- Stage 7: `WindowFramePolicy.frame` takes `Screens(visible:main:)`, `main` optional as `NSScreen.main` is; without one the default sits at the origin. A frame across two screens goes to the one showing more of it, and clamping moves the frame onto that screen as well as limiting its size. Tests beyond the named ones cover these, the exact 100×100 boundary and a raised frame pushed back on screen.
- Outside the stages: `DictationControllerTests.tickPlaysWhenNotLiveWithin100ms`, an existing core test, failed once in Stage 8's full core run. It advanced the clock, yielded twice and read the sounds, but the tick task resumes on the clock's executor and hops back to the main actor, which under CPU load lands after both yields; repetition under load failed it within two seconds. `FakeSoundPlayer` gains `waitUntilPlayed(count:)` and the test waits on it (10,000 repetitions under the same load green); `DictationController` is unchanged. Commit `4b3e449`.
- Stage 8: `SearchModel` also publishes `isSearching`, true from a non-empty query until its results arrive. Without it the results page cannot tell `No matches for “query”` (§5.9) from a search still waiting. Stage 8 has no view; Stage 10 reads it.
- Stage 8: the cache also remembers meetings that failed to load, so a search session reads each once and logs `search skipped N meetings` once, not at every keystroke. An unreadable index searches the dictations alone and logs `search: index unreadable`. Cancelling a running search cancels its detached work, which stops reading meetings.
- Stage 8: `MeetingsListModel.formatter`, `duration` and a static `dayTitle(_:now:calendar:format:)` lost `private` so `SearchModel` builds its meta lines from them; a day older than yesterday reads `Tuesday 3 Nov`, as the Meetings list writes it. `MeetingsListModel.Snippet` is an alias of `SearchModel.Snippet` until Stage 10 removes it.
- Stage 8: `MessageSink` and `logging(to:_:)` in `AppTests/TestCallSessionTests.swift`, a file outside the stage's *Touches*, lost `private` so `SearchModelTests` reuses them. `StubLibrary` is named `StubMeetingLibrary` after its file. The suite carries `.timeLimit(.minutes(1))`: with the empty scaffold its waits never returned.
- Stage 8: tests beyond the named ones: `aTitleMatchCarriesNoSnippets`, `invalidateWithoutAQueryRunsNothing`, `anUnreadableIndexLeavesTheDictationsAndIsLogged`, `labelNamesTheSpeakerNoteOrSummary`. `aNewQueryCancelsTheRunningSearch` holds the first search inside a meeting load with a gated library, so the query changes while it runs.
- Stage 9: `WindowActivation.foreground()` is a third entry point: `.regular` and activate, with no window to order front. The About alert, the speech-model prompt and Sparkle's windows are not this code's to order; `shown(_:)` calls it first. `UpdaterUserDriverSupport.beginForeground()` gave way to it, so `AppUpdater` changes beyond `:57-59`.
- Stage 9: `closed()` also counts a minimised titled window, beyond §5.8's "visible": restoring it from the Dock would otherwise show a window with no Dock icon (R7). `closed()` is `nonisolated`, so Sparkle's delegate calls it directly.
- Stage 9: the AppKit behaviour was checked before building on it. Inside `windowWillClose` the closing window still reports `isVisible`, and a main-queue turn later it does not; the status item's window is not titled; an alert's panel is titled and hidden once `runModal` returns; Sparkle 2.9.6 calls `standardUserDriverWillFinishUpdateSession` first and closes its windows after, in the same turn.
- Stage 9: `FrontAppTracker.init(center:frontmost:ownPID:)` takes the notification centre, the starting app and its own process id, all defaulted, so its rule is tested: `AppTests/FrontAppTrackerTests.swift`, five tests, where the plan had it integration-verified only. `AppDelegate` creates the tracker with itself, so it knows the app frontmost at launch, before onboarding, and it also exists in the test host.
- Stage 9: `PasteTarget.init(_ app: NSRunningApplication)` in `App/NSWorkspaceFrontmostApp.swift`, a file outside the stage's *Touches*, is the one mapping from a running app; `NSWorkspaceFrontmostApp` and the tracker both use it. `HistoryWindowController.init` lost `frontmost:`.
- Stage 10: tests beyond the named ones: `AppTests/MainWindowModelTests.swift` (nine, the wiring of navigation, pages, search, usage and a meeting result that fails to open) and `AppTests/QueryHighlightTests.swift` (five, the results' marking of the query, case-insensitive as search matches).
- Stage 10: `HistoryListModel.reveal(_:)` is `async` and reloads before it selects, so a dictation result selects its row whether or not the page was loaded. `MeetingsListModel.Dependencies` lost `clock`, which only the list search used.
- Stage 10: Settings' `clearHistory` closure already calls `search.invalidate()`, not from Stage 11. `meetingChanged` reloads the Meetings page whether or not it is shown; it reads the index only.
- Stage 10: components changed in place: `DSDialog.message` is optional (Clear History has none), and `SearchPill` takes its focus binding from its owner (⌘F) and empties on Esc. New in `App/Design`: `PillMenu` for Export ▾ (a SwiftUI `Menu` ignores a custom button style on macOS, so it opens an AppKit menu under the pointer), and `DayHeader` and `ListRow`, the Day-grouped row list the three pages share. `DS.TextStyle` gains `usage` (11/16) and `usageHeader` (10/16), read off the mockup's usage table; `DESIGN.md` does not list them yet.
- Stage 10: `MainWindow` arrives in Stage 11 with `cancelOperation`, its only override; Stage 10 hosts the page in a plain `NSWindow`.
- Stage 10: `applicationShouldTerminate` also hides the main window, so ⌘Q, logout and the Dock's Quit store the frame, not only the menu's Quit.
- Stage 10: the empty Meetings page keeps today's explanation, as §5.9 says, not the mockup's shorter wording. A comment in `App/Correction/CorrectionWindowController.swift`, outside the stage's *Touches*, named the deleted `HistoryWindowController`.
- Stage 10: the window, sidebar, usage table and the three pages were rendered offscreen, light and dark, by a temporary test that is not in the commit, and compared with `mockup-v6-overview.html`. A test call's meta line wraps beside the row actions: its engine title, `AssemblyAI Universal-Streaming`, is longer than the mockup's `AssemblyAI`.
- Stage 11: tests beyond the named ones: `MainWindowModelTests` `enteringSettingsRereadsTheKeys` and `leavingSettingsCancelsHotkeyCapture`. The Settings fakes moved from `SettingsModelTests` to `AppTests/SettingsFakes.swift`, which both suites use.
- Stage 11: `MainWindowModel.openSettings()` and `Dependencies.openSettings` are gone; the sidebar's Settings row navigates itself. The coordinator's `openSettings` shows Settings at the last section; selecting Meetings stays with Stage 13.
- Stage 11: `SettingsModel` is built at launch with the main window, no longer at the first Settings open, so its `refreshKeys()` reads the Keychain then.
- Stage 11: components changed in place: `SettingRow` takes `error:` (and `ErrorLine` exists for a full-width error), `FieldChrome` is internal so the hotkey field wears it, `Chip` takes `remove:`, the `.ds` toggle dims when disabled, and `fieldPlaceholder(_:shown:)` draws a field's placeholder in `text.tertiary` (macOS draws a field's own prompt in a fixed dark grey whatever its style, so it read as a value; `SearchPill` uses it too). New in `App/Design`: `RadioRow` (the filled-accent-ring radio lists of General, Meetings and Overlay), `StepperPill` and `FlowLayout`; `DESIGN.md` does not list them yet. Stock `Stepper`, `Picker` and `Menu` give way to `StepperPill`, `SegmentedPill` and `PillMenu`.
- Stage 11: texts that named the removed windows now name pages: Corrections' footnote ends "on a Dictations row", Keep meeting audio's "from the Meetings page". Clear History sits in a row titled "Delete every stored dictation", the dialog's question. A footnote that followed a group of rows (Hotkeys, Keys) is the last row's description.
- Stage 11: errors use `DS.Colors.recording` and missing-key hints `DS.Colors.warn`. The Clear History confirmation is a second `DSDialog` in `MainView`, beside Stage 10's.
- Stage 11: the window at General, Meetings and Dictations and all nine sections were rendered offscreen, light and dark, by a temporary test that is not in the commit, and compared with `mockup-v6-overview.html`. The overlay preview stays blank offscreen, and capsule borders show bracket marks at their ends there; both are taken for offscreen artefacts, not checked in a live window.
- Stage 12: the model does not write the pasteboard: `didCopySummary()` sets `justCopied` and starts the 1.5-second reset, kept as `copyReset` for the test to await, and `copyPayload` is what Stage 13's `copy` receives. `RichPasteboardWriting` is a `@MainActor enum` whose `write(markdown:html:rtf:to:)` defaults to the general pasteboard. Until Stages 13 and 14 nothing calls either, nor reads `selectedTab`, `notesTabTitle`, `chips`, the pill text, `canCopySummary`, `canRegenerate` or `regeneratePrompt`, which is the dialog's message only.
- Stage 12: `SummaryRichText.attributed(title:blocks:)` sits beside `rtf(title:blocks:)`, so `stringIsTitleThenBlocksInOrder` reads the text before RTF and the other three read it back. Type follows `DS`: the title in `type.title`, headings ranked as the view ranks them, text in `type.reading`, code in `type.mono`. Beyond fonts and indents the RTF carries strikethrough; a rule is `———`; an item's continuation line is a line separator, so it stays in the item's paragraph.
- Stage 12: the model keeps the parsed blocks; the view parses each block's inline Markdown as it draws the row, not kept in the model as §5.17 has it.
- Stage 12: the source line's editing suffix shows once the meeting is stopped, when editing is possible; the live line is unchanged. The speaker chip lists every speaker label, a test call's too, though the recording mockup's finished test call shows none. The tab is chosen from `isTest` at the first `.state(.stopped)`.
- Stage 12: tests: `readyPanelSplitsTheFourSections`, `metaLineShowsModelTimeTokensCostAndPartial` and `rewritingAndKeptStillShowTheCurrentSummary` gave way to the six-state, four-section and partial-mark tests; `ordinaryMeetingsUnchanged` expects the suffix once stopped. `justCopiedClearsAfter1point5Seconds` requires `copyReset` before it waits on the clock: against the stubs it hung there. `tabIsSetOnlyWhenTheMeetingFirstStops` passed against the stubs, whose tab never moved. The private `clock(_:)` formatter is now `timeOfDay(_:)`, as `clock` is the injected clock.
- Stage 12: the reading column puts 22 points above a heading, read off the mockup; `DS.Space` has no such step.
- Stage 12: the Summary panel in all six states, a topic summary, a four-section one and one with ordered items, a rule, code and strikethrough, and the meeting window holding a summary, were rendered offscreen, light and dark, by a temporary test that is not in the commit, and compared with `mockup-v6-recording.html` and the overview's finished meeting. The meeting window keeps its own chrome until Stage 14.
- Stage 13: `MeetingCoordinator.Dependencies` gains `clock` (default `SystemClock()`), handed to every model, so Copy summary's `Copied` reset is tested on `ManualClock`. `openSettings` takes a `SettingsModel.Section` and the coordinator passes `.meetings`, so the rule is tested there; `openMeetings` is gone. `copySummary` calls `didCopySummary()` after `copy`.
- Stage 13: `open(id)` loads the stored meeting before it releases `opened` or drops the chooser, so a load that throws leaves the page as it was. Dropping an idle chooser, there and on leaving the page, spares one whose start is under way.
- Stage 13: the transitional window is titled `Meeting` throughout; the per-session window titles went with `MeetingWindowPresenting`. Its Meetings button closes the window rather than opening the Meetings page.
- Stage 13: tests beyond the named ones: `showPresentsTheCurrentMeetingOnlyWhileActive`, `openThatFailsLeavesThePageAsItWas`, `pageLeftKeepsAChooserWhoseStartIsUnderWay` and `aFinishingSessionIsDroppedWhenItsSummaryEnds` (ready, failed, none and kept). The suite carries `.timeLimit(.minutes(1))`. `AppTests/TestCallSessionTests.swift`, outside the stage's *Touches*, gave its `StubController` an empty `regenerateSummary()`.
- Stage 14: `MainWindowModel` gains `presented` (the page's model and actions, cleared when the page is left), `liveMeeting`, `showMeeting(_:actions:)`, `showLiveMeeting()` and the defaulted dependencies `showLiveMeeting` and `meetingPageLeft`; `MainWindowController.showMeeting(_:actions:)` brings the window forward on the meeting page. `MainWindowModelTests` gained three tests: `showMeetingPresentsTheSessionAndLeavingThePageClearsIt`, `presentingAnotherSessionOnTheMeetingPageDoesNotLeaveIt` and `recordingPillShowsTheLiveMeeting`.
- Stage 14: the Regenerate and merge-speakers confirmations are a `PageDialog` lifted to `MainView`, the third `DSDialog` there, cleared when the destination or the presented session changes. Each session's page carries `.id` of its model, so editing and popover state do not carry over.
- Stage 14: `Banner` gave way to `StatusLine`, which gains an `.error` kind in the recording colour. `DS` gains `type.transcript` (14/22), `type.score` (serif 500 34/40) and `hairline(_:)`; `PaneHeader` is sentence case with its own hairline and `sidePane()` gives a side pane its fill and edge. `TopBar` and `TitleField` live in `MeetingPage.swift`. `DESIGN.md` lists none of these yet.
- Stage 14: `MeetingWindowModel.partialSpeaker` is readable, so the partial line's name takes the speaker's colour as in the mockup. The current script line is labelled "Your line — read it aloud" by the view; the model's "Your turn" text is no longer shown. Role rates are chips, with the engine label and purity in their help text. `LineRing` is gone. `EarlierRunsSheet` keeps its system styling.
- Stage 14: Copy summary and Regenerate show on a test call too (disabled without a summary), though the mockup's finished test call has neither. Test Call… is disabled while Start is blocked, e.g. without an engine key. The Notes tab reads "No notes." when empty. Note markers are tertiary, gaps in the warning colour. The note composer shows no focus ring.
- Stage 14: ⌘[ is on the finished page's back pill only; the chooser, setup and live pages have no back pill. ⌘N sits on the sidebar slot, so it starts a meeting or, as the recording pill, returns to the live one.
- Stage 14: a session presented between the meeting hotkey's start and the main window's creation at launch is not shown; the next *Start Meeting…* or *Show Meeting…* shows it.
- Stage 14: Meetings' engine footnote, outside the stage's *Touches*, reads "a live meeting's running cost" instead of naming the meeting window.
- Stage 14: the window with the chooser, the setup step, a live meeting with the recording pill, a paused one, a live test call, a just-stopped meeting writing its summary, the finished Summary, Transcript and Notes tabs, a scored test call and the Regenerate dialog were rendered offscreen, light and dark, by a temporary test that is not in the commit, and compared with `mockup-v6-recording.html`. The same test hit-tested a titled, full-size-content window: points 6 to 36 points below the top of the page land in the hosting view, so the top bar's pills take clicks under the transparent title bar.

## Execution schedule

Batches run in order; a batch starts only when the previous one has fully landed. Stages inside a *parallel* batch are independent and may be built concurrently; a *serial* batch holds one stage. `/feature-implement` follows this table and demotes any batch it cannot verify to serial.

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1, Stage 2 | parallel | Disjoint files: `MWMeetings` sources, `MeetingFixtures.swift` and four `MWMeetingsTests` files against `MWConfig/Config.swift`, a new `MWConfig/AppTheme.swift` and `ConfigCodingTests.swift`. No symbol or string-keyed dependency: `SummaryDocument`, `SearchExcerpt`, `Billing.replacedSummaryCostUSD` against `theme` and `main_window_frame`. No shared registration point: both add files to existing SwiftPM targets, `Package.swift` untouched. Same base: both are green on `5456c80`. Neither is scaffolding, a migration, a shared-signature change or a dependency change. No security ordering between them. No shared test resource: each runs the core suite in its own worktree's `.build` with unique `TempDirectory`s, and the app build-only check into its own `.dd`; neither launches the app test host |
| 2 | Stage 3 | serial | Migrates a user file (category exclusion) |
| 3 | Stage 4 | serial | Consumes `Billing.replacedSummaryCostUSD` from Stage 1; app-hosted tests |
| 4 | Stage 5 | serial | Changes the shared `UsageRecording.totals()` and `UIEvent.usage` (category exclusion) |
| 5 | Stage 6 | serial | Establishes the `DS` tokens and components every later UI stage uses |
| 6 | Stage 7 | serial | App-hosted tests; two concurrent test hosts of one bundle ID are unproven |
| 7 | Stage 8 | serial | App-hosted tests; hoists the shared app-test helpers |
| 8 | Stage 9 | serial | App-hosted tests; edits every window controller's activation |
| 9 | Stage 10 | serial | Consumes Stages 6–9 |
| 10 | Stage 11 | serial | Edits `SidebarView`, `MainWindowController`, `AppDelegate` from Stage 10 |
| 11 | Stage 12 | serial | Edits `MeetingView.swift` and `MeetingWindowModel` that Stages 13–14 also edit |
| 12 | Stage 13 | serial | Consumes `copyPayload` and `canRegenerate` from Stage 12 |
| 13 | Stage 14 | serial | Consumes the coordinator of Stage 13 and the shell of Stages 10–11 |
| 14 | Stage 15 | serial | Edits `GeneralSection`, `SettingsModel`, `AppDelegate` |
| 15 | Stage 16 | serial | Edits `StatusItemController`, `AppDelegate` |
| 16 | Stage 17 | serial | Documents names introduced by every earlier stage |

**Critical path:** Stage 1 → Stage 3 → Stage 4 → Stage 5 → Stage 6 → Stage 7 → Stage 8 → Stage 9 → Stage 10 → Stage 11 → Stage 12 → Stage 13 → Stage 14 → Stage 15 → Stage 16 → Stage 17 (16 of 17 stages).

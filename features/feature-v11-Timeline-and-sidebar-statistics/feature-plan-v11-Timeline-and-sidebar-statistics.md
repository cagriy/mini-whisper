# Timeline and Sidebar Statistics — Implementation Plan v11

**Status:** Draft
**Date:** 2026-11-24
**Design:** [feature-design-v11-Timeline-and-sidebar-statistics.md](./feature-design-v11-Timeline-and-sidebar-statistics.md)

## Overview

v11 adds a numbers-only record of meetings, dictation and spend under `~/.config/mini-whisper/stats/`, and two surfaces that read it: a Timeline page and a foldable stats block in the sidebar. The plan follows the design's three phases (§9, R36), and each phase ends on a batch boundary after which the user can cut a 0.9.0 beta.

- **Phase A, the record (Stages 1–11).** Stage 1 creates the `MWStats` module, its registrations and its seams. Stage 2 makes every usage state its purpose. Stages 3–7 build the store, the meeting-file reads, the seed, the meeting figures and the reconciler, bottom-up and partly in parallel. Stages 8–10 wire capture into dictation and meetings and start the record at launch. Stage 11 adds Settings › Statistics with Reset and the truthful History row.
- **Phase B, the block and the page (Stages 12–21).** Stage 12 adds the two config keys and the Typing speed row. Stages 13–15 and 17 build the pure figures: formats, the sidebar summary, streaks and milestones, and the Timeline report for panels 1–5, 7, 8 and 10. Stage 16 adds the DS tokens and chart components beside them. Stages 18–20 add the Timeline model, the page and its navigation. Stage 21 adds the sidebar block.
- **Phase C, People, Words, Quality (Stages 22–27).** People (Stage 22), the word tally and cloud (23) and the word cache (24) come first. The report's last three panels (25) and the app wiring of word counts (26) follow, then the panels themselves (27).

Every numbered requirement R1–R36 maps to at least one stage below, and every §5 component has a stage that creates or changes it.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only | integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests, platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a one-line justification. Hybrid stages carry full TDD steps for their host-testable part and an *integration-verified remainder* naming its check.

**Swift's first red.** A stage that introduces a new type, member, argument or target cannot reach a red assertion first. The test target fails to build first, and that build error is the expected initial failure: `error: cannot find 'X' in scope`, `value of type 'Y' has no member 'z'`, `missing argument for parameter 'z' in call`, `type 'E' has no member 'c'`, or for a new SwiftPM target `no such module 'MWStats'`. The stage then scaffolds the minimal empty API and re-confirms red as Swift Testing failures (`✘ Test … recorded an issue … Expectation failed`) before implementing.

**Path shorthand.** `Sources/…` and `Tests/…` mean `Packages/MiniWhisperCore/Sources/…` and `Packages/MiniWhisperCore/Tests/…`. `Package.swift` means `Packages/MiniWhisperCore/Package.swift`. `App/…`, `AppTests/…`, `project.yml`, `CLAUDE.md` and `README.md` are at the repository root.

**Runners and commands.** Each was run once before drafting; baselines observed 2026-11-24 on `main` at `18678a5`:

| Layer | Command | Baseline |
|---|---|---|
| Core package tests (Swift Testing) | `cd Packages/MiniWhisperCore && swift test` | exit 0; 19 `✔ Test run with …` lines (one per test target), 1,494 tests in total, 0 `✘` |
| One suite or target | `cd Packages/MiniWhisperCore && swift test --filter <SuiteOrTarget>` | — |
| App tests (Swift Testing via xcodebuild) | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` | `✔ Test run with 568 tests in 53 suites passed` + `** TEST SUCCEEDED **` |
| App build-only check | same, with `build` in place of `test` | `** BUILD SUCCEEDED **` |

Read the `✔/✘ Test run with N tests…` lines, not the XCTest `Executed 0 tests` lines (CLAUDE.md). A new test target adds one `✔ Test run` line, so after Stage 1 the core run prints 20.

**Per-stage regression rule.**
- A stage touching only `Packages/MiniWhisperCore` runs the full `swift test` plus the app build-only check, because the app imports every core module it links.
- A stage touching `App/`, `AppTests/` or `project.yml` also runs the full app test command.
- Only `xcodebuild … test` launches the app test host, the shared resource that keeps two app stages out of one batch.

**Conventions grounded in the repo.**
- **Registration is explicit** (CLAUDE.md).
  - A new target goes into `Package.swift` `targets:` and `products:`, and a new target dependency into its `dependencies:`.
  - The app links each core product by name in `project.yml` (`targets.MiniWhisper.dependencies`), so its first `import MWStats` needs a `project.yml` entry (Stage 8).
  - New files inside an existing target or app folder are auto-discovered, by SwiftPM folders and by xcodegen folder sources after `xcodegen generate`. The new `App/Timeline/` folder is picked up the same way.
- **Test locations** follow `Tests/<Module>Tests/<Type>Tests.swift` with `@Suite struct <Type>Tests`. Siblings:
  - `Tests/MWNamingTests/NameSpotterTests.swift`, the newest module's own target, for `MWStatsTests`;
  - `Tests/MWUsageTests/UsageStoreTests.swift` and `Tests/MWHistoryTests/HistoryStoreTests.swift`, actors over a `TempDirectory`, for `StatsStoreTests`, `WordCacheTests` and `MeetingReconcilerTests`;
  - `Tests/MWMeetingsTests/MeetingStoreTests.swift`, with `Fixtures/` and `Bundle.module`, for the fixture pattern;
  - `Tests/MWConfigTests/ConfigCodingTests.swift`, `Tests/MWMeetingsTests/MeetingModelTests.swift`, `Tests/MWPipelineTests/ProcessingJobTests.swift`, `Tests/MWPipelineTests/DictationControllerTests.swift`, `Tests/MWMeetingPipelineTests/MeetingControllerTests.swift` (`MeetingHarness`, line 448) and `Tests/MWMeetingPipelineTests/MeetingControllerRegenerateTests.swift`;
  - app side: `AppTests/SettingsModelTests.swift`, `AppTests/MainNavigationModelTests.swift`, `AppTests/MainWindowModelTests.swift`, `AppTests/MenuModelTests.swift`, `AppTests/MeetingsListModelTests.swift` and `AppTests/DSTests.swift`.
- **The new test target** `MWStatsTests` is declared with `resources: [.copy("Fixtures")]`, as the design says. SwiftPM refuses a missing resource folder, so Stage 1 creates `Tests/MWStatsTests/Fixtures/` with its first fixture.
- **Shared fakes and clocks.**
  - Shared fakes live in the library target `Sources/MWTestSupport`; the sibling for `FakeStatsRecorder` is `FakeUsageStore.swift`.
  - Durations run on `VirtualClock`, and dates on an injected `now` and calendar.
  - App tests cannot import `MWTestSupport`; they use `AppTests/ManualClock.swift` and stubs.
  - Stored meetings come from `MeetingFixtures` (`northwind()`, `make(...)`) in a `TempDirectory`.
  - Log content is checked with `CapturingLogSink` and `Log.withSinks`.
- **No synthetic figure is taken from a real Mac** (storm §4). Fixtures and expected values are hand-built.

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: `stats/` (0700) with four 0600 files, numbers and identifiers only, nothing sent | Stage 1, Stage 3, Stage 5, Stage 6, Stage 7 |
| R2: First launch without `meta.json` seeds and sets `since`; seeding before any hotkey or meeting can record | Stage 5, Stage 8 |
| R3: Every dictation attempt ends in exactly one row with one of ten outcomes | Stage 1, Stage 3, Stage 8, Stage 10 |
| R4: `days.jsonl` per local day: counts, words, seconds, undelivered, apps, hours, spend by purpose | Stage 3, Stage 5 |
| R5: Every usage states a purpose; spend by purpose; test calls not recorded; costs summed | Stage 2, Stage 3, Stage 8 |
| R6: One row per finished non-test meeting, written at stop, refreshed on change, kept after delete | Stage 6, Stage 7, Stage 9 |
| R7: Reconcile at launch, at stop, when Timeline opens and after reset | Stage 7, Stage 9, Stage 11, Stage 18 |
| R8: Dictation rows pruned at 13 months; day and meeting rows kept for life | Stage 1, Stage 3 |
| R9: Under 60 s kept but not counted; test calls excluded; history clearing and retention 0 leave numbers | Stage 3, Stage 5, Stage 7, Stage 8, Stage 13, Stage 15, Stage 17, Stage 25 |
| R10: Seed from history, current-month unsplit cost and earlier months' meeting costs; idempotent; no overlap | Stage 5, Stage 8 |
| R11: A crash leaves at most one torn line, skipped and dropped; no row written twice | Stage 1, Stage 3 |
| R12: Reset erases the record and word counts, reseeds, sets `since` | Stage 5, Stage 11, Stage 26 |
| R13: `meeting.json` stores UTC offset, transcript delay stats and summary wait | Stage 4, Stage 9 |
| R14: `word-counts.json` for kept meetings, added at stop and launch, removed on delete | Stage 23, Stage 24, Stage 26 |
| R15: No failure in the record, reconcile or word counts fails a dictation, meeting or summary | Stage 3, Stage 7, Stage 8, Stage 9, Stage 10, Stage 24 |
| R16: Timeline destination, sidebar row with ⌘3, menu row, back pill "Timeline" | Stage 20 |
| R17: Empty state, progress line from five meetings, panels | Stage 18, Stage 19 |
| R18: Panels in order, each at its threshold | Stage 15, Stage 17, Stage 19, Stage 25, Stage 27 |
| R19: A kept record opens its meeting; a deleted one shows its date and "Deleted meeting" | Stage 17, Stage 18, Stage 19 |
| R20: Every cost labelled an estimate | Stage 19 |
| R21: Panels play once on first view; Reduce Motion; a return restores and plays nothing | Stage 16, Stage 18, Stage 19, Stage 20 |
| R22: Every chart has a VoiceOver summary and its values as a list | Stage 16, Stage 19, Stage 27 |
| R23: Sidebar block: label, six figures, 30-bar trend, lifetime line, opens Timeline | Stage 13, Stage 21 |
| R24: Fold handle on the usage table's hairline; persisted; starts unfolded | Stage 12, Stage 21 |
| R25: Block hidden in Settings and until data; drops trend, then hides, when short | Stage 13, Stage 21 |
| R26: Block refreshes after each recorded row and when the window comes forward | Stage 3, Stage 21 |
| R27: Settings › Statistics after People: Typing speed, Reset, the "what is kept" line | Stage 11, Stage 12, Stage 26 |
| R28: Typing speed 10–120 in steps of 5, default 40, drives every "saved typing" figure | Stage 12, Stage 13, Stage 17 |
| R29: Reset asks in the in-window dialog first | Stage 11 |
| R30: History row text and the footnote under the card | Stage 11 |
| R31: macOS 14, arm64, Swift 6 strict; no new dependency; shape charts; NaturalLanguage | Stage 1, Stage 16, Stage 23 (and every stage's DoD) |
| R32: ≤ 3 small appends per dictation, no network; report off the main actor; first reconcile in the background | Stage 3, Stage 7, Stage 9, Stage 18, Stage 19 |
| R33: Every value from `DS`; the 15 `pending v11` changes become DS code | Stage 16, Stage 19, Stage 21, Stage 27 |
| R34: Counts and durations only, under a new `stats` log category | Stage 1, Stage 3, Stage 5, Stage 7, Stage 24 |
| R35: CHANGELOG, CLAUDE.md module map and layout, README window and privacy sections per phase | Stage 11 (CLAUDE.md, README privacy), Stage 21 (CLAUDE.md, README window), Stage 27 (CLAUDE.md, README privacy); CHANGELOG per phase by `/feature-implement` |
| R36: Phase A, B and C content and order | Stage 11 (end of A), Stage 21 (end of B), Stage 27 (end of C); see *Execution schedule* |

## Stages

### Stage 1 — `MWStats` module: registration, time, JSONL file, word count and recording seams
**Goal:** A registered, tested `MWStats` module holding the low-level pieces every later stage uses, plus the two recording protocols, `DictationAttempt`, `FakeStatsRecorder` and `Log.stats`.
**Design references:** §5 Architecture (`StatsTime`, `JSONLFile`, `WordCount`, registration), §5 Interfaces (`DictationStatsRecording`, `MeetingStatsRecording`, `DictationAttempt`), §5 Data model (`at` format, outcomes), §5 Failure cases (torn line, missing final newline), §5 Observability, R1, R3, R8, R11, R31, R34
**Touches:**
- `Package.swift`: add the `MWStats` target (deps `MWMeetings`, `MWUsage`, `MWHistory`, `MWConfig`, `MWSupport`) and product, the `MWStatsTests` test target (deps `MWStats`, `MWTestSupport`; `resources: [.copy("Fixtures")]`), and `MWStats` in the dependencies of `MWPipeline`, `MWMeetingPipeline` and `MWTestSupport`.
- Create in `Sources/MWStats/`: `StatsTime.swift`, `JSONLFile.swift`, `WordCount.swift`, `StatsRecording.swift`.
- Change `Sources/MWSupport/Log.swift` (`Log.stats`). Create `Sources/MWTestSupport/FakeStatsRecorder.swift`.
- Move `Sources/MWVoices/PrivateFile.swift` to `Sources/MWSupport/PrivateFile.swift` (public) and its test to `Tests/MWSupportTests/PrivateFileTests.swift`; `Sources/MWVoices/MatchLog.swift` imports `MWSupport` (see *Deviations from plan*).
- Create in `Tests/MWStatsTests/`: `StatsTimeTests.swift`, `JSONLFileTests.swift`, `WordCountTests.swift`, `StatsRecordingTests.swift`, `Fixtures/torn-days.jsonl`.

The fixture is synthetic: two well-formed day lines and a third cut mid-object with no final newline.

**Steps (TDD, convention-establishing):**
1. Write the tests.
   - `StatsTimeTests`:
     - `dayKey` and `hour` of instants either side of a DST change in `Europe/London` (2026-03-29 and 2026-10-25), with an injected calendar;
     - the same instant keyed under two time zones gives two days;
     - `iso(_:timeZone:)` writes `2026-11-30T09:14:03+00:00` for UTC, and `+05:30` and `-08:00` forms;
     - `parse` returns the instant and offset, round-tripping all three;
     - `dictationCutoff(now:calendar:)` is 13 calendar months back, and 2026-03-31 gives 2025-02-28.
   - `JSONLFileTests`, on a `TempDirectory`:
     - append creates the file 0600 in a 0700 directory;
     - append to a file without a final newline writes the newline first, so the old last line stays whole;
     - `read` of the copied `torn-days.jsonl` returns two values and `skipped == 1`, with one `stats` warning `stats: torn-days.jsonl: skipped 1 unreadable line(s)` (file name only, via `CapturingLogSink`);
     - `rewrite` is atomic and leaves 0600;
     - `writeAtomically(_:to:)` for single-document files leaves 0600.
   - `WordCountTests`: `"Hello, world. It's fine."` counts 4; an unspaced Japanese sentence counts more than 1; a mixed Latin and CJK line; `""` counts 0.

   Expected initial failure: `no such module 'MWStats'` (the target has no sources), then `cannot find 'StatsTime' in scope`, `cannot find 'JSONLFile' in scope` and `cannot find 'WordCount' in scope`.
2. Run `swift test --filter MWStatsTests` — confirm. Scaffold empty types and re-confirm red as expectation failures.
3. Implement:
   - `StatsTime`: `dayKey`, `hour`, `iso`, `parse`, `dictationCutoff`, with an `en_US_POSIX` formatter per time zone.
   - `JSONLFile(url:)` with `append(_:)`, `read(_:)`, `rewrite(_:)` and `static writeAtomically(_:to:)` (temp file, 0600, rename, as `MeetingStore.write` does).
   - `WordCount.count(_:)`, using `enumerateSubstrings(in:options: .byWords)`.
   - `StatsRecording.swift`: `DictationStatsRecording`, `MeetingStatsRecording` and `DictationAttempt` with `Outcome` (ten cases, raw values `delivered`, `too_short`, `silent`, `superseded`, `no_key`, `empty`, `failed`, `mic_error`, `device_changed`, `aborted`).
   - `Log.stats = LogCategory(name: "stats")`.
   - `FakeStatsRecorder`, lock-guarded like `FakeUsageStore`, conforming to both protocols with `attempts: [DictationAttempt]` and `stopped: [UUID]`.
4. Run — pass. Full `swift test` (now 20 `✔ Test run` lines) and the app build-only check — green.

**Definition of done:**
- `MWStats` builds in Swift 6 language mode with no new package dependency.
- `MWPipeline`, `MWMeetingPipeline` and `MWTestSupport` list it.
- The three suites pass, and nothing outside the new files changes behaviour.

**Risks specific to this stage:** DST tests depend on the system time-zone database. Use fixed `TimeZone(identifier:)` values and instants that are hours away from the transition, never system-local time.

### Stage 2 — Every usage states its purpose
**Goal:** `ProviderUsage` carries a required `UsagePurpose`; every producer states it, and a test call's meeting, summary and naming usage are `testCall`.
**Design references:** §5 Interfaces (`UsagePurpose`, `ProviderUsage`), §5 Control flow (Spend), §5 Architecture ("Every site of each extended type"), §5 Compatibility, R5
**Touches:**
- `Sources/MWUsage/ProviderUsage.swift`.
- `Sources/MWPipeline/ProcessingJob.swift`: two producers, `.dictation`.
- `Sources/MWMeetingPipeline/MeetingBilling.swift`: `finalUsage(purpose:)`; `summaryUsage` states `.summary`.
- `Sources/MWMeetingPipeline/MeetingController.swift`: the stop, summary and naming producers, `.testCall` when `meeting.test != nil`.
- Tests: `Tests/MWUsageTests/UsageStoreTests.swift`, `Tests/MWPipelineTests/ProcessingJobTests.swift`, `Tests/MWPipelineTests/DictationControllerTests.swift`, and in `Tests/MWMeetingPipelineTests/`: `MeetingBillingTests.swift`, `MeetingControllerTests.swift`, `MeetingControllerNamingTests.swift`, `MeetingControllerNamingStopTests.swift`, `MeetingControllerRegenerateTests.swift`, `MeetingControllerTestCallTests.swift`.

**Steps (TDD):**
1. Write the tests.
   - `UsageStoreTests.purposeLeavesTheDayEntryAsBefore`: adds under `.dictation` and `.meeting` sum into `config.usage` exactly as before.
   - `ProcessingJobTests`: a delivered dictation's and a stale discard's usage are `.dictation`.
   - `MeetingBillingTests`: `finalUsage(purpose: .meeting).purpose == .meeting`, and `summaryUsage(_:).purpose == .summary`.
   - `MeetingControllerTests`: Stop adds `.meeting` and the summary adds `.summary`. `MeetingControllerNamingTests`: a naming request adds `.naming`.
   - `MeetingControllerTestCallTests.aTestCallsUsageIsTestCall`: stop, summary and naming of a test call each add `.testCall`.
   - Every existing `ProviderUsage(` literal in these files gains its purpose.

   Expected initial failure: `cannot find type 'UsagePurpose' in scope` and `extra argument 'purpose' in call`.
2. Run `swift test --filter "MWUsageTests|MWPipelineTests|MWMeetingPipelineTests"` — confirm. Scaffold the enum and the required argument with every producer passing the plain purpose (`.meeting`, `.summary`, `.naming`). Re-confirm red: `aTestCallsUsageIsTestCall` fails on `.meeting != .testCall`.
3. Implement:
   - `UsagePurpose` (`dictation`, `meeting`, `summary`, `naming`, `testCall = "test_call"`).
   - `ProviderUsage.init(purpose:…)` with no default.
   - `MeetingBilling.finalUsage(purpose:)`.
   - The controller picks `.testCall` when `meeting.test != nil` at the three add sites (`stop`, `adopt`, `applyNaming`).
   - `DayEntry.add(_:)` is unchanged and ignores the purpose.
4. Run — pass. Full `swift test` and the app build-only check — green. No `App/` file constructs a `ProviderUsage`.

**Definition of done:**
- `grep -rn 'ProviderUsage(' Sources` shows a purpose at every site.
- `config.json` is written byte-for-byte as before.

**Risks specific to this stage:** A shared-signature change with 6 producers and about 20 test literals. It lands atomically, because a required argument cannot be split across stages.

### Stage 3 — Stats rows, the store, and `RecordedUsage`
**Goal:** The four row types and the `StatsStore` actor: open, record attempts and spend, upsert meeting rows, snapshot, changes, prune and compact. Plus the `UsageRecording` decorator that records spend.
**Design references:** §5 Data model (all of `stats/`), §5 Interfaces (`StatsStore`, `RecordedUsage`), §5 Control flow (Dictation: "`StatsStore.record(attempt)` stamps…", Spend), §5 Failure cases, §5 Security (at rest), §5 Performance (Recording, Memory, Compaction), §5 Observability, R1, R4, R5, R8, R9, R11, R15, R26, R32, R34
**Touches:**
- Create in `Sources/MWStats/`: `StatsRows.swift`, `StatsStore.swift`, `RecordedUsage.swift`.
- Create in `Tests/MWStatsTests/`: `StatsRowsTests.swift`, `StatsStoreTests.swift`, `RecordedUsageTests.swift`.

**Steps (TDD):**
1. Write the tests.
   - `StatsRowsTests`:
     - a delivered `DictationRow` encodes with sorted keys and its zero fields left out;
     - an empty `DayRow` encodes only `day`;
     - missing fields read as zero and unknown keys are ignored;
     - the design's snake-case keys hold (`timed_words`, `tokens_in`, `user_known`, `longest_turn`, `summary_wait`, `silence_stop`);
     - `DayRow.add` sums field by field, maps included;
     - a `MeetingRow` with only `id` decodes;
     - `MeetingRow.isCounted` is `duration >= 60`;
     - `MeetingRow.localStart` uses the offset inside the row's own `at`.
   - `StatsStoreTests`, on a `TempDirectory` with injected `now` and calendar:
     - a delivered attempt appends one `dictations.jsonl` row and one day line: `delivered` 1, `words`, `apps[bundle]` (or `other` with no bundle), `hours["9"]`, and `seconds` and `timed_words` only when `seconds > 0`;
     - an undelivered attempt appends `undelivered[outcome]` 1;
     - twenty attempts give twenty rows with distinct ids;
     - `record(spend:)` appends one line under each of `dictation`, `meeting`, `summary` and `naming`, with `usd`, tokens and engine seconds; `.testCall` appends nothing;
     - a delivered attempt plus its spend append exactly three lines across the files (R32);
     - closing and reopening gives a snapshot equal to the folded state;
     - `open` prunes dictation rows past the 13-month cutoff and rewrites the file;
     - the first attempt recorded on a new local day prunes too;
     - `open` folds `days.jsonl` to one line a day, and 2,000 appended lines trigger a fold;
     - `open` compacts `meetings.jsonl` when it holds more lines than ids;
     - `upsert` keeps the latest row per id;
     - `changes` yields after `record`, `record(spend:)` and `upsert`;
     - a write failure (the directory made 0500 after `open`, before any file exists) leaves the snapshot updated, logs `stats: dictations.jsonl not written: …` under `stats`, and throws nothing;
     - a torn final line (the Stage 1 fixture copied in as `days.jsonl`) is skipped and gone after the next fold;
     - every file is 0600 in a 0700 directory;
     - no log line contains the attempt's bundle identifier.
   - `RecordedUsageTests`:
     - each of the four purposes reaches its day spend;
     - `.testCall` reaches the base store but no day line;
     - a throwing base still records the spend first, then the error is rethrown;
     - `totals()` is the base's.

   Expected initial failure: `cannot find 'DictationRow' in scope`, `cannot find 'StatsStore' in scope` and `cannot find 'RecordedUsage' in scope`.
2. Run `swift test --filter MWStatsTests` — confirm. Scaffold and re-confirm red.
3. Implement:
   - `StatsRows.swift`: `DictationRow`, `DayRow`, `Spend`, `MeetingRow` (nested `Delay`, `Speaker`, `Costs`; every field optional on read), `StatsMeta`, `StatsSnapshot`, and the `isCounted` and `localStart`/`localEnd` helpers.
   - `StatsStore`: `init(directory:now:calendar:)`, `changes` (`bufferingNewest(1)`), `open()`, `record(_:)`, `record(spend:)`, `upsert(_:)`, `meetingRows()` and `snapshot()`, with the prune and compaction rules.
   - Writes go through `JSONLFile`, and every failure is logged and swallowed.
   - `RecordedUsage(base:stats:)`: `add` records spend unless `.testCall`, then forwards to `base.add` and rethrows its error.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:**
- No entry point throws.
- Logs carry counts and file names only.
- Two appends for an attempt and one for a spend.

**Risks specific to this stage:** The read-only directory test needs a non-root runner; the GitHub macOS runner and a developer Mac both qualify. The test restores 0700 in a `defer` so `TempDirectory` can clean up.

### Stage 4 — Meeting timing fields and two `MeetingStore` reads
**Goal:** `meeting.json` can hold the UTC offset and the timing record. `MeetingStore` gains `meeting(_:)`, which reads `meeting.json` alone, and `modified(_:)`.
**Design references:** §5 Data model (`meeting.json` additions), §5 Interfaces (`MeetingStore` gains…), §5 Control flow (Meeting: "median; 90th percentile by nearest rank"), §5 Compatibility, R13
**Touches:** `Sources/MWMeetings/MeetingModel.swift` (`Meeting.utcOffsetSeconds`, `Meeting.timing`, `MeetingTiming`, `DelayStats`); `Sources/MWMeetings/MeetingStore.swift`; `Tests/MWMeetingsTests/MeetingModelTests.swift`; `Tests/MWMeetingsTests/MeetingStoreTests.swift`

**Steps (TDD):**
1. Write the tests.
   - `MeetingModelTests`:
     - `timingAndOffsetAbsentDecodeAsNil`, with the existing `meeting-v0.5.json` fixture;
     - `aMeetingWithoutTimingEncodesAsToday`, with no `timing` or `utcOffsetSeconds` key;
     - `timingAndOffsetRoundTrip`;
     - `delayStatsTakeTheMedianAndTheNearestRankP90`: `[0.4, 1.2, 0.8, 2.0, 1.0]` gives median 1.0, p90 2.0 and count 5, and `[1, 2, 3, 4]` gives median 2.5 and p90 4;
     - `delayStatsOfNoSamplesIsNil`.
   - `MeetingStoreTests`:
     - `meetingReadsOnlyMeetingJSON` works with `segments.jsonl` deleted;
     - `meetingOfAMissingFolderThrows`;
     - `modifiedIsTheNewestOfTheThreeFiles`, with modification dates set explicitly through `FileManager.setAttributes`;
     - `modifiedIsNilWithoutTheFolder`.

   Expected initial failure: `value of type 'Meeting' has no member 'timing'`, `cannot find 'DelayStats' in scope` and `value of type 'MeetingStore' has no member 'modified'`.
2. Run `swift test --filter MWMeetingsTests` — confirm. Scaffold and re-confirm red.
3. Implement:
   - `public var utcOffsetSeconds: Int?` and `public var timing: MeetingTiming?` on `Meeting`, defaulting to nil and outside `init`. The synthesized `Codable` writes them only when set.
   - `MeetingTiming { transcriptDelay: DelayStats?; summaryWaitSeconds: Double? }`.
   - `DelayStats { median; p90; count }` with `init?(samples:)`.
   - `public nonisolated func meeting(_:) throws -> Meeting` and `modified(_:) -> Date?`.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:**
- Older files decode unchanged.
- A meeting without the fields encodes byte-for-byte as before.
- `Meeting.init` is unchanged.

**Risks specific to this stage:** None.

### Stage 5 — Seed, `meta.json` and reset
**Goal:** A pure `StatsSeed` from history, the current month's usage and kept meetings. The store's `needsSeed`, `seed` and `reset`, and the `meta.json` rules.
**Design references:** §5 Control flow (Seed, Reset), §5 Data model (`meta.json`, Lifetimes), §5 Failure cases (crash during seeding, `meta.json` unreadable), §5 Security ("No names or text in the record"), §5 Observability (`seeded…`, `reset`), R1, R2, R4, R9, R10, R12, R34
**Touches:** `Sources/MWStats/StatsSeed.swift` (create); `Sources/MWStats/StatsStore.swift` (`needsSeed`, `seed`, `reset`, meta handling in `open`); `Tests/MWStatsTests/StatsSeedTests.swift` (create); `Tests/MWStatsTests/StatsStoreSeedTests.swift` (create)

**Steps (TDD):**
1. Write the tests.
   - `StatsSeedTests`, with `monthStart` from an injected `now` and calendar:
     - step 1: each history entry becomes a `delivered` row with `seeded: true`, its id, timestamp, bundle id, engine, streamed seconds, `WordCount` words and cost;
     - its day line counts `delivered`, `words`, `apps` and `hours`, with `seconds` and `timed_words` only when streamed seconds exist;
     - `spend.dictation` appears only for days before `monthStart`;
     - step 2: each current-month day in `config.usage` becomes `spend.unsplit` with its cost, tokens and engine seconds;
     - step 2 subtracts the cost and engine seconds of kept test calls that ended that day, floored at zero;
     - days outside the month are ignored;
     - step 3: kept, ended, non-test meetings started before `monthStart` add `spend.meeting` (`billing.costUSD`, seconds under `engine.pricingKey`), `spend.summary` (current plus replaced cost, the current summary's tokens) and `spend.naming`;
     - current-month meetings, unfinished meetings and test calls add nothing;
     - no overlap: total seeded spend equals pre-month history cost plus unsplit plus pre-month meeting cost;
     - no history text, meeting title or speaker name appears in the encoded output.
   - `StatsStoreSeedTests`:
     - `needsSeed` is true without `meta.json`;
     - `seed` removes stray `days.jsonl`, `dictations.jsonl` and `meetings.jsonl`, writes the seeded files, then `meta.json` last with `schema` 1, `since` today and `created` as a UTC instant;
     - a directory with seeded files but no `meta.json` still `needsSeed`, and reseeding gives the same files;
     - `reset` replaces everything in one call and sets `since` to the reset date;
     - an unreadable `meta.json` is rewritten at `open` with `since` the earliest day row, or today, without reseeding;
     - `changes` yields after `seed` and `reset`;
     - the log line `stats: seeded D dictations, N days, M meetings with cost`.

   Expected initial failure: `cannot find 'StatsSeed' in scope` and `value of type 'StatsStore' has no member 'needsSeed'`.
2. Run `swift test --filter MWStatsTests` — confirm. Scaffold and re-confirm red.
3. Implement `StatsSeed.init(history:usage:meetings:now:calendar:)`, a value holding seeded dictation rows and day lines, and the store's `needsSeed`, `seed(_:)`, `reset(_:)` and the meta rules in `open()`.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:**
- Seeding is idempotent and empties the directory first.
- `meta.json` is written last.
- The seed holds numbers and identifiers only.

**Risks specific to this stage:** Floating-point sums depend on order, so the seed iterates days and meetings sorted, as `UsageStore.totals` does, and the tests compare with a tolerance of 1e-9.

### Stage 6 — `MeetingFigures`
**Goal:** A pure function from a loaded meeting to its `MeetingRow`.
**Design references:** §5 Data model (`meetings.jsonl`, segment words rule), §5 Control flow (Reconcile step 3: `user_known`, offset fallback, copied timing), §5 Security, R1, R6, R9
**Touches:** `Sources/MWStats/MeetingFigures.swift` (create); `Tests/MWStatsTests/MeetingFiguresTests.swift` (create)

**Steps (TDD):**
1. Write `MeetingFiguresTests` on `MeetingFixtures.northwind()` and hand-built `LoadedMeeting`s. They cover every field:
   - `at` and `end` with the meeting's `utcOffsetSeconds`, or the fallback zone's offset at that instant;
   - `duration`, `mode` and `engine` as raw values;
   - `speech` (Σ segment lengths) and `words` (`words.count`, or `WordCount` for an edited segment or one with no word list);
   - `user` and `user_known` (remote, or the user has words; an in-room meeting with no user words is false);
   - per-speaker `seconds`, `words` and `questions`, and `named` (non-user labels not equal to `SpeakerLabel.defaultName`);
   - `turns`, `longest_turn` and `questions` (`?` or `？`);
   - `notes`, `gaps` (gap markers), `paused` (paused and sleep markers) and `reconnects` (distinct sessions minus one);
   - `silence_stop` and `summary`;
   - `usd.meeting`, `usd.summary` (current plus replaced) and `usd.naming`;
   - `delay` and `summary_wait` copied from `timing`, `figures == 1`, and `computed == now`;
   - no transcript text, title or speaker name in the encoded row.

   Expected initial failure: `cannot find 'MeetingFigures' in scope`.
2. Run `swift test --filter MeetingFiguresTests` — confirm. Scaffold and re-confirm red.
3. Implement `MeetingFigures.version = 1` and `MeetingFigures.compute(_ loaded: LoadedMeeting, fallback: TimeZone, now: Date) -> MeetingRow`. `DelayStats` maps into `MeetingRow.Delay`.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** Every `meetings.jsonl` field in the design's table has an assertion, and the encoded row holds no text.

**Risks specific to this stage:** None.

### Stage 7 — `MeetingReconciler` and `MeetingSource`
**Goal:** Bring meeting rows up to date from the meeting files, in single flight with progress. `meetingStopped` handles one meeting. Word counts come later, in Stage 24.
**Design references:** §5 Control flow (Reconcile steps 1–3 and 5, `meetingStopped`), §5 Interfaces (`MeetingSource`, `MeetingReconciler`), §5 Failure cases (reconcile cannot load, deleted in Finder, never finished, under 60 s), §5 Performance (Reconcile), §5 Security, R1, R6, R7, R9, R15, R32, R34
**Touches:** `Sources/MWStats/MeetingReconciler.swift` (create): `MeetingSource`, `extension MeetingStore: MeetingSource {}`, `MeetingSource.keptMeetings()`, `ReconcileProgress` and `MeetingReconciler`. Also `Tests/MWStatsTests/MeetingReconcilerTests.swift` (create).

**Steps (TDD):**
1. Write `MeetingReconcilerTests` with a private spy `MeetingSource` that counts `load` calls and serves `modified` dates, plus a real `MeetingStore` in a `TempDirectory`:
   - a missing row is computed; a row whose `figures` is below the version is computed; a row whose `computed` precedes `modified(id)` is computed;
   - a fresh row is not loaded (load count 0);
   - test calls and meetings without `endedAt` are skipped;
   - a meeting whose `load` throws is skipped with `stats: meeting <uuid> not reconciled: …`, and the pass continues;
   - two concurrent `reconcile()` calls make one pass (load count 1 per meeting), and both return `true`;
   - `progress` yields `(1, 3)`, `(2, 3)`, `(3, 3)`, then `nil`;
   - `reconcile()` returns `false` when nothing changed;
   - `meetingStopped(id)` waits for a running pass, then upserts that meeting alone, and skips a test call or an unfinished meeting;
   - the log line `stats: reconcile, C computed, W word entries, R removed, T ms`;
   - end to end: the `northwind` fixture through a real `MeetingStore` gives `stats/` files with no transcript, title or speaker-name string in their bytes;
   - `keptMeetings()` returns ended, non-test meetings.

   Expected initial failure: `cannot find 'MeetingReconciler' in scope` and `cannot find type 'MeetingSource' in scope`.
2. Run `swift test --filter MeetingReconcilerTests` — confirm. Scaffold and re-confirm red.
3. Implement `MeetingReconciler.init(stats:source:timeZone:now:)` with `progress`, `reconcile()` and `meetingStopped(_:)`. The design gives no init, see *Planning decisions*. One shared in-flight `Task` provides single flight.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:**
- Steps 1–3 and 5 of the design's reconcile hold.
- No entry point throws.
- Unchanged meetings cost a stat call only.

**Risks specific to this stage:** Single-flight tests can race, so the spy source holds `load` on a continuation the test releases. No real sleep.

### Stage 8 — Dictation capture in the job, and the record at launch
**Goal:** `ProcessingJob` records exactly one attempt for every terminus it owns, with the wait measured from key release. The app creates the store, seeds or opens it before anything can record, and routes all spend through `RecordedUsage`.
**Design references:** §5 Control flow (Launch steps 1–3, Dictation, the terminus table's "Job:" rows), §5 Interfaces (`Dependencies.stats`, `ProcessingJob.init` takes a clock, `ProcessingInput.releasedAt`), §5 Architecture ("The usage store in `AppDelegate`"), R2, R3, R5, R9, R10, R15
**Touches:**
- Core: `Sources/MWPipeline/Dependencies.swift` (`stats: any DictationStatsRecording`, no default), `Sources/MWPipeline/ProcessingInput.swift` (`releasedAt`), `Sources/MWPipeline/ProcessingJob.swift` (`init(deps:clock:)`, `run` → private `perform` → one record, `StreamBilling.record` returns its cost), `Sources/MWPipeline/DictationController.swift` (reads `releasedAt` in `stopAndProcess`, builds the job with its clock).
- Tests: `Tests/MWPipelineTests/ProcessingJobTests.swift`, `Tests/MWPipelineTests/DictationControllerTests.swift` (harness gains `stats`).
- App: `App/AppDelegate.swift`, `project.yml` (the `MWStats` product).

**Steps (hybrid — TDD for the job; integration-verified remainder for the launch wiring):**
1. Write `ProcessingJobTests`, with a `FakeStatsRecorder` and a `VirtualClock`. Each case asserts exactly one attempt:
   - parameterised over checkpoint 1, 2 and 3: a stale job records `superseded` with the recording length and the streamed seconds' bill;
   - no key and no streamed text: `no_key`, streamed bill;
   - an empty transcript: `empty`, streamed bill;
   - a transcription error and a cleanup error: `failed`, cost 0;
   - a paste error: `failed`, with the dictation's cost;
   - delivered: `delivered`, with `WordCount` words of the pasted text, recording length, cost, and `wait` equal to the clock reading after the paste minus `releasedAt` (for example 2.0 − 0.5 = 1.5);
   - `theAttemptIDIsTheHistoryEntryID`;
   - `historyRetentionZeroStillRecordsTheAttempt`, using a real `HistoryStore` with retention 0 in a `TempDirectory` (R9).

   Expected initial failure: `missing argument for parameter 'stats' in call` and `extra argument 'clock' in call`.
2. Run `swift test --filter ProcessingJobTests` — confirm. Scaffold the new arguments with no recording and re-confirm red (`attempts.count == 0`).
3. Implement:
   - `Dependencies.stats`.
   - `ProcessingInput.releasedAt`.
   - `ProcessingJob(deps:clock:)`: `run` generates the id, calls `perform` (today's body, unchanged except that it returns `(outcome, words, cost, wait)`), then `deps.stats.record(...)`.
   - `StreamBilling.record` returns the cost it billed.
   - `DictationController` reads `clock.now` as `releasedAt` before spawning `stopTask`, and builds `ProcessingJob(deps:clock:)`.
4. Run — pass. Full `swift test` — green.
5. **Integration-verified remainder** (app). Edit `App/AppDelegate.swift`:
   - move `MeetingStore` creation above `DictationController`;
   - create `StatsStore(directory: configDirectory/stats)`;
   - if `needsSeed`, call a private `makeSeed()` (`history.entries()`, `config.usage`, `store.keptMeetings()`) and `seed` it, else `open()`;
   - wrap the `UsageStore` in `RecordedUsage` for `Dependencies.usage` and for `makeMeetings`;
   - keep the bare `UsageStore` for `meetingChanged`'s totals;
   - set `Dependencies.stats` to the store.

   All of this happens before `DictationController` and `listener.start()` (R2). Add the `MWStats` product to `project.yml`. Verify with `xcodegen generate && xcodebuild … build` (`** BUILD SUCCEEDED **`) and the full app test command. Then, by hand on a dev build: launch, dictate once, and check that `~/.config/mini-whisper/stats/` holds `meta.json`, one `dictations.jsonl` row and day lines. `stat -f %Lp` gives 700 for the folder and 600 for the files.

**Definition of done:**
- Every job terminus in the design's table records once with the stated seconds and cost.
- The app seeds before the hotkey listener starts.
- Dictation, meeting, summary and naming spend reach `days.jsonl`; test-call spend does not.

**Risks specific to this stage:** `Dependencies(` has three construction sites (two tests and `AppDelegate`), and `ProcessingJob(`/`ProcessingInput(` two each. All are in this stage. Seeding reads every kept `meeting.json` on the main actor at launch: small files, but measure the launch on a large library during Phase A acceptance.

### Stage 9 — Meeting capture and the reconciler at launch
**Goal:** A meeting stores its UTC offset, live transcript delay and summary wait, and reports its stop. The app runs the reconciler at launch and at every stop.
**Design references:** §5 Control flow (Meeting, Launch steps 4–5), §5 Interfaces (`MeetingDependencies.stats`, `timeZone`), §5 Performance (At stop), R6, R7, R13, R15, R32
**Touches:**
- Core: `Sources/MWMeetingPipeline/MeetingDependencies.swift` (`stats: any MeetingStatsRecording`, no default; `timeZone: @Sendable () -> TimeZone = { .current }`) and `Sources/MWMeetingPipeline/MeetingController.swift`.
- Tests: `Tests/MWMeetingPipelineTests/MeetingControllerTests.swift` (`MeetingHarness` gains `stats` and a fixed zone) and `Tests/MWMeetingPipelineTests/MeetingControllerStatsTests.swift` (create).
- App: `App/AppDelegate.swift`.

**Steps (hybrid — TDD for the controller; integration-verified remainder for the wiring):**
1. Write `MeetingControllerStatsTests`:
   - `startStoresTheOffsetOfItsTimeZone`: +3600 for a fixed zone;
   - `stopWritesTheTranscriptDelayOfItsSegments`: three provider segments arrive at known meeting times on the `VirtualClock`, and `timing.transcriptDelay` gets the expected median, p90 and count 3;
   - `aTestCallTakesNoSamples`;
   - `segmentsWhilePausedTakeNoSample`;
   - `stopReportsTheMeetingOnceAfterItHasStopped`: `stats.stopped == [id]`, recorded with state `.stopped` and before the summarizer's first call;
   - `aTestCallIsReportedToo` (the reconciler skips it);
   - `theSummaryWaitIsStored`: `FakeSummarizer.hold()`, advance 4 s, `release()`, and `timing.summaryWaitSeconds == 4`;
   - `aRegeneratedSummaryReplacesTheWait`.

   Expected initial failure: `missing argument for parameter 'stats' in call` in `MeetingHarness`, then expectation failures.
2. Run `swift test --filter MeetingControllerStatsTests` — confirm. Add the harness argument and re-confirm red.
3. Implement:
   - `start` sets `utcOffsetSeconds = deps.timeZone().secondsFromGMT(for: startedAt)`.
   - `add` appends `max(0, meetingTime − shifted.end)` once per provider segment while `.recording` and not a test.
   - `stop` writes `timing.transcriptDelay` via `DelayStats(samples:)` before `saveMeeting`, and awaits `deps.stats.meetingStopped(id)` right after `setState(.stopped)`.
   - `requestSummary` reads `deps.clock` before and after, and `adopt` stores the wait.
4. Run — pass. Full `swift test` — green.
5. **Integration-verified remainder** (app). In `AppDelegate`:
   - create `MeetingReconciler(stats:source: store)`;
   - pass it as `MeetingDependencies.stats`, with `timeZone: { .current }`;
   - after `main = makeMain(…)`, start `Task(priority: .utility) { await reconciler.reconcile() }`.

   Verify with the app build and full app test command. By hand: record a meeting of over a minute, stop it, and check that `meetings.jsonl` gains its row and `meeting.json` holds `utcOffsetSeconds` and `timing`.

**Definition of done:**
- R13's three fields are written.
- A stop upserts the row before the summary request.
- The first reconcile runs off the main actor at utility priority.

**Risks specific to this stage:** `MeetingDependencies(` has two construction sites, the harness and `AppDelegate`, both in this stage.

### Stage 10 — Dictation capture in the controller
**Goal:** The six termini that never reach the job each record one attempt.
**Design references:** §5 Control flow (terminus table, controller rows), R3, R15
**Touches:** `Sources/MWPipeline/DictationController.swift` (records at capture error, device change, both gates, profile error and `abort`; `discard` returns its bill); `Tests/MWPipelineTests/DictationControllerTests.swift`

**Steps (TDD):**
1. Write `DictationControllerTests`:
   - `micErrorRecordsNoLengthAndNoCost`;
   - `deviceChangeRecordsTheLengthAndTheDiscardBill`;
   - `aShortRecordingIsTooShort` (under 0.5 s);
   - `aQuietRecordingIsSilent`;
   - `aProfileErrorIsFailedWithNoCost`;
   - `abortWithASessionRecordsAbortedWithTheDiscardBill` (seconds 0);
   - `abortWithoutASessionRecordsNothing`;
   - `theWaitRunsFromReleaseToThePaste`: press, hold, advance the `VirtualClock`, release, and check that the delivered attempt's wait is measured from the release.

   Each asserts exactly one attempt and its outcome.

   Expected initial failure: expectation failures, `stats.attempts.count == 0` for the controller termini.
2. Run `swift test --filter DictationControllerTests` — confirm.
3. Implement the six recordings, splitting the gate into `too_short` and `silent`. The bundle id comes from the press or release target. `discard` returns the cost `StreamBilling.record` billed.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** All fourteen termini of §4 record exactly one attempt (Stages 8 and 10 together).

**Risks specific to this stage:** None.

### Stage 11 — Settings › Statistics with Reset, the History row, and Phase A docs
**Goal:** The Statistics section with Reset and its line (Phase A form), the in-window confirmation, the truthful History row, and the reset wiring. Phase A ends here.
**Design references:** §5 Interfaces (Settings, "By phase"), §5 Control flow (Reset), §5 Security (Destructive action), §5 Design language, R7, R12, R27, R29, R30, R35, R36; `DESIGN.md`; mockup `mockup-v11-settings-placement.html#statistics-section`
**Touches:** `App/Settings/SettingsModel.swift` (`Section.statistics` after `.people`, "Statistics", `chart.bar`; `Dependencies.resetStatistics`, defaulting to `{}`; `confirmingReset`, `requestReset()`, `confirmReset()`, `cancelReset()`); `App/Settings/SettingsPage.swift`; `App/Settings/StatisticsSection.swift` (create); `App/Settings/HistorySection.swift`; `App/Main/MainView.swift` (dialog chain; cancel on destination change); `App/AppDelegate.swift` (`resetStatistics`: `makeSeed()`, `stats.reset(seed)`, `reconciler.reconcile()`); `AppTests/SettingsModelTests.swift`; `CLAUDE.md` (module map row for `MWStats` and its dependents); `README.md` (Privacy section)

**Steps (hybrid — TDD for the model; platform-only/UI remainder):**
1. Write `SettingsModelTests`:
   - `sectionsListStatisticsAfterPeople`: update the `allCases` guard at line 568;
   - `statisticsIsTitledWithChartBar`;
   - `resetAsksFirst`;
   - `confirmingResetCallsTheDependencyOnce`;
   - `cancellingResetCallsNothing`.

   Expected initial failure: `type 'SettingsModel.Section' has no member 'statistics'`.
2. Run the app test command — confirm `** TEST FAILED **` on that build error. Scaffold and re-confirm red.
3. Implement the model, the `SettingsPage` case, and `StatisticsSection`:
   - one `Card` with the Reset row (small pill tinted `DS.Colors.recording`, "Reset Statistics");
   - the Phase A line: the first two sentences, with "They stay on this Mac and are never sent anywhere.";
   - the `DSDialog` in `MainView` with the design's title, message and "Reset Statistics" confirm;
   - the History row's new description and the full-width footnote under Clear History;
   - the `AppDelegate` reset closure.
4. Run — pass. Full app tests and `swift test` — green.
5. **Remainder (platform-only/UI, manual).** Compare the section and dialog with the accepted mockup in light and dark. Press Reset Statistics, confirm, and check that the files under `stats/` are rebuilt and `meta.json`'s `since` is today. The full Phase A acceptance runs once Batch 8 has landed (*Verification* 1).
6. Docs:
   - `CLAUDE.md`: the module-map row for `MWStats` (Phase A components) and the added edges.
   - `README.md`: the Privacy section gains the numbers-only record, where it lives, and Reset (planning decision 30).
   - The CHANGELOG `[Unreleased]` *Added* entry (the numbers-only record, what it holds, where, and Reset) is written by `/feature-implement`'s main agent as its side artefact.

**Definition of done:**
- R27 (Phase A form), R29 and R30 hold.
- Reset rebuilds from what is stored.
- Once Batch 8 (Stages 10 and 11) has landed, the user can cut 0.9.0b4.

**Risks specific to this stage:** None.

### Stage 12 — Config keys and the Typing speed row
**Goal:** `timeline_sidebar_folded` and `typing_wpm` in `config.json`, and Settings › Statistics' Typing speed row.
**Design references:** §5 Data model (`config.json`), §5 Interfaces (Settings › Typing speed), §5 Architecture ("`Config`'s two keys"), R24, R27, R28
**Touches:** `Sources/MWConfig/Config.swift`; `Tests/MWConfigTests/ConfigCodingTests.swift`; `App/Settings/SettingsModel.swift` (`typingSpeedRange`, `setTypingSpeed(_:)`, label); `App/Settings/StatisticsSection.swift` (the row, first in the card); `AppTests/SettingsModelTests.swift`

**Steps (hybrid — TDD; UI remainder):**
1. Write the tests.
   - `ConfigCodingTests`:
     - `timelineKeysAbsentTakeDefaults` (false, 40);
     - `timelineKeysRoundTrip`;
     - `timelineKeysNeverLandInExtra`;
     - `timelineKeysAreWrittenForANewConfig`;
     - `aWrongTypedTypingSpeedReadsAsForty`, and a wrong-typed fold flag reads false;
     - `validatedClampsTheTypingSpeed` (5 → 10, 200 → 120).
   - `SettingsModelTests`: `typingSpeedStepsByFiveFromTenToOneTwenty`, `settingTheTypingSpeedWritesTheConfig` and `typingSpeedLabelReadsWPM` ("40 wpm").

   Expected initial failure: `value of type 'Config' has no member 'typingWPM'`.
2. Run `swift test --filter ConfigCodingTests` and the app test command — confirm. Scaffold and re-confirm red.
3. Implement the two properties, their `Key` constants, `Key.all`, `init(from:)` (`try?`), `encode(to:)` and the `validated()` clamp. Add the model's bounds and setter, and the `StepperPill` row with the design's description.
4. Run — pass. Full `swift test` and the app tests — green.
5. **Remainder:** check the row against the Statistics section mockup.

**Definition of done:** Both keys round-trip and clamp. The row writes `typing_wpm`.

**Risks specific to this stage:** None.

### Stage 13 — `StatFormat` and `SidebarStats`
**Goal:** Number, duration and money text, and the sidebar block's figures, trend and lifetime line.
**Design references:** §5 Interfaces (Figure rules: Numbers; Sidebar), R9, R23, R25, R28
**Touches:** `Sources/MWStats/StatFormat.swift` (create); `Sources/MWStats/SidebarStats.swift` (create); `Tests/MWStatsTests/StatFormatTests.swift` (create); `Tests/MWStatsTests/SidebarStatsTests.swift` (create)

**Steps (TDD):**
1. Write the tests.
   - `StatFormatTests` at every boundary:
     - page: 9,999 → `9,999`, 10,000 → `10k`, 86,400 → `86.4k`, 1,420,000 → `1.42M`;
     - sidebar: 999 → `999`, 1,000 → `1k`, 8,400 → `8.4k`, 126,000 → `126k`, 1,400,000 → `1.4M`;
     - durations: `42 m`, `1 h 50 m`, `14.5 h`, and whole hours from 100 h;
     - money via `Pricing.dollars`.
   - `SidebarStatsTests`:
     - nil until one counted meeting or delivered dictation exists;
     - the window is today and the 29 local days before it, so day −30 is excluded;
     - meetings under 60 s are excluded;
     - the six figures, with saved typing = `max(0, Σ timed_words ÷ wpm − Σ seconds ÷ 60)` at 40 and 80 wpm;
     - the 30 trend values run oldest first, with zero days as zero;
     - the lifetime line's meetings and hours count every counted row.

   Expected initial failure: `cannot find 'StatFormat' in scope` and `cannot find 'SidebarStats' in scope`.
2. Run `swift test --filter "StatFormatTests|SidebarStatsTests"` — confirm. Scaffold and re-confirm red.
3. Implement both, pure over `StatsSnapshot`, `typingWPM`, `now` and calendar.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** Every format boundary in the design is asserted, and the block's figures follow R23.

**Risks specific to this stage:** `NumberFormatter` output depends on locale; pin `en_US_POSIX` grouping in the tests, and use the user's locale in the app.

### Stage 14 — `Milestones` and `Streaks`
**Goal:** Ladders, dated milestones, next steps, and streaks overall and within a year.
**Design references:** §5 Interfaces (Figure rules: Streak, Milestones, "A ladder with no step left shows no meter"), R18
**Touches:** `Sources/MWStats/Milestones.swift` (create); `Sources/MWStats/Streaks.swift` (create); `Tests/MWStatsTests/MilestonesTests.swift` (create); `Tests/MWStatsTests/StreaksTests.swift` (create)

**Steps (TDD):**
1. Write the tests.
   - `StreaksTests`:
     - active days are local days with a counted meeting or a delivered dictation;
     - the longest streak with its dates;
     - a streak across a year end (30 Dec – 2 Jan) counts 4 overall and 2 within each year;
     - a gap day breaks the streak.
   - `MilestonesTests`:
     - each ladder (meetings, hours, words transcribed plus dictated, dictations, streak) is dated on the local day its running total first reached the step;
     - the next step and its progress per ladder;
     - no next step once a ladder is exhausted;
     - the latest eight reached, oldest first.

   Expected initial failure: `cannot find 'Streaks' in scope` and `cannot find 'Milestones' in scope`.
2. Run `swift test --filter "MilestonesTests|StreaksTests"` — confirm. Scaffold and re-confirm red.
3. Implement both, pure over the snapshot via `MeetingRow.isCounted` and `localStart`.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** All ladder values and streak rules of the design are asserted.

**Risks specific to this stage:** None.

### Stage 15 — Timeline report I: totals, the year, weekly rhythm, talk share
**Goal:** The `TimelineReport` type, its inputs and the thresholds, with panels 1–4.
**Design references:** §5 Interfaces (Timeline page table rows 1–4; Figure rules: Heat levels, Week, Streak, Back-to-back, Latest finish, Talk share), R9, R18
**Touches:** `Sources/MWStats/TimelineStats.swift` (create); `Tests/MWStatsTests/TimelineStatsTests.swift` (create)

**Steps (TDD):**
1. Write `TimelineStatsTests` on hand-built rows. Test each panel one below and at its threshold.
   - **Lifetime totals:** zero figures are left out.
   - **The year:**
     - 7 rows by 53 or 54 columns from the calendar's first weekday, for a Monday-first and a Sunday-first calendar;
     - heat levels for meetings by hours and for dictation by count;
     - a meeting counts on the local start day of its own offset;
     - the caption's active days and in-year longest streak;
     - the year range runs from the earliest year with data to this year.
   - **Weekly rhythm:**
     - the dictation switch at 50 delivered;
     - quarter levels of the grid maximum;
     - the busiest hour;
     - back-to-back means a 0–300 s gap after the previous counted meeting ended;
     - the earliest start;
     - the latest finish, with an end on the next day counting past 24:00.
   - **Talk share:**
     - only meetings with `user_known`;
     - Σ user seconds ÷ Σ speech;
     - pace and questions asked;
     - the last 20 shares;
     - the caption's count.

   Expected initial failure: `cannot find 'TimelineStats' in scope`.
2. Run `swift test --filter TimelineStatsTests` — confirm. Scaffold and re-confirm red.
3. Implement:
   - `TimelineInputs` with the snapshot, kept meetings by id (title and start, from the index), typing speed, `now` and calendar. Phase C fields are added in Stage 25.
   - `TimelineReport`, with an optional value for each of panels 1–4 and the year grids for every year in both modes. Stages 17 and 25 add the other panels' fields.
   - `TimelineStats.compute(_:)` for panels 1–4.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** Panels 1–4 match every figure rule above.

**Risks specific to this stage:** The year grid's week columns depend on `Calendar.firstWeekday`, so the tests construct both calendars explicitly.

### Stage 16 — DS tokens, chart components and panel playback
**Goal:** The `pending v11` tokens as DS code, the shape-drawn chart components, the milestone strand, and the rule for when a panel plays.
**Design references:** §5 Design language (Deltas, Mapping to tokens, DS code), §5 Control flow (A panel plays), §5 Performance (Page), R21, R22, R31, R33; `DESIGN.md` (the `pending v11` entries: `type.score`, `type.title`, `type.cloud.small`, `radius.cell`, six components (Timeline panel, Stat figure, Heat grid, Bar chart, Split bar, Milestone strand), Timeline motion, and the two chart Do's); mockup `mockup-v11-overview.html`
**Touches:** `App/Design/DS.swift` (`Radius.cell`, `TextStyle.cloudSmall`, `Colors.heat(_:)`); `App/Design/Charts.swift` (create: `HeatGrid` as one `Canvas`, `BarChart`, `SplitBar`, `MeterBar`, `StatFigure`, `CountUpText`, `TimelinePanel`); `App/Design/MilestoneStrand.swift` (create); `App/Timeline/TimelineMotion.swift` (create: motion constants, `PanelPlayback`); `AppTests/DSTests.swift`; `AppTests/PanelPlaybackTests.swift` (create)

**Steps (hybrid — TDD for tokens and playback; platform-only/UI remainder for the views):**
1. Write the tests.
   - `DSTests`:
     - `heat(0)` is `hover` and `heat(4)` is `accent` in both appearances;
     - `heat(1…3)` blend `accent` into `hover` at 25, 50 and 75%;
     - `Radius.cell == 2`;
     - `cloudSmall` is serif, 400, 13/18.
   - `PanelPlaybackTests`:
     - a panel plays once 20% of its height is inside the viewport, and not at 19%;
     - once played it stays played after scrolling away;
     - a new `playID` clears the played set;
     - Reduce Motion counts every panel as played;
     - panels in view at opening get start delays 80 ms apart.

   Expected initial failure: `type 'DS.Colors' has no member 'heat'` and `cannot find 'PanelPlayback' in scope`.
2. Run the app test command — confirm. Scaffold and re-confirm red.
3. Implement the tokens, `PanelPlayback` and the components.
   - Components take plain values: labels, numbers, levels, series and accessibility sentences.
   - Each chart is one accessibility element whose label is its headline sentence, with child elements for its values.
   - `CountUpText` animates 0→1 over the design's durations and staggers.
4. Run — pass. Full app tests — green.
5. **Remainder:** the components are first seen on the page in Stage 20; their visual check is part of that stage.

**Definition of done:**
- The 15 `pending v11` entries have code homes: tokens here, the Stats block in Stage 21, the word cloud in Stage 27.
- No chart library is used.
- The year grid is one `Canvas`.

**Risks specific to this stage:** None.

### Stage 17 — Timeline report II: spend, dictation, records, milestones
**Goal:** Panels 5, 7, 8 and 10 of the report.
**Design references:** §5 Interfaces (table rows 5, 7, 8, 10; Figure rules: Order and ties, Captions (Spend), Spend, Time saved, Typical and longest dictation, Most words in a day, Milestones), R9, R18, R19, R28
**Touches:** `Sources/MWStats/TimelineStats.swift`; `Tests/MWStatsTests/TimelineStatsTests.swift`

**Steps (TDD):**
1. Extend `TimelineStatsTests`. Test each panel one below and at its threshold.
   - **Spend:**
     - 12 months ending this month, stacked by `dictation`, `meeting`, `summary`, `naming` and `unsplit`;
     - the series present;
     - this year and all time;
     - per recorded hour, shown from 1 h;
     - the unsplit caption flag while a shown month has an unsplit part.
   - **Dictation:**
     - words dictated;
     - time saved at 40 wpm;
     - words a minute;
     - top 5 apps without `other`;
     - typical (median) and longest dictation from delivered rows.
   - **Records:**
     - longest meeting;
     - busiest day: most counted meetings, then hours, then the later day;
     - most words in a day: meeting words by start day plus words dictated;
     - longest streak and most speakers;
     - a tie goes to the later one;
     - a record carries its meeting id and whether that meeting is kept;
     - the next milestone meters for meetings, hours and dictations.
   - **Milestones:** the 8 latest reached.

   Expected initial failure: `value of type 'TimelineReport' has no member 'spend'`, since Stage 15 declares the panel 1–4 fields only.
2. Run `swift test --filter TimelineStatsTests` — confirm. Scaffold the four optional fields, always nil, and re-confirm red as expectation failures.
3. Implement the four panels in `TimelineStats.compute`.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** Panels 1–5, 7, 8 and 10 are complete in the report.

**Risks specific to this stage:** None.

### Stage 18 — `TimelineModel` and `TimelineSource`
**Goal:** The page's state machine (empty, reading, report), replay and return, opening a record, and the off-main gathering of inputs.
**Design references:** §5 Architecture (App side: `TimelineModel`, `TimelineSource`), §5 Control flow (Timeline opens, A record is clicked, "Change…" is clicked), §5 Failure cases (Timeline opened during the first reconcile; record clicked after delete), R7, R17, R19, R21, R32
**Touches:** `App/Timeline/TimelineModel.swift` (create); `App/Timeline/TimelineSource.swift` (create); `AppTests/TimelineModelTests.swift` (create)

**Steps (hybrid — TDD for the model; integration-verified source):**
1. Write `TimelineModelTests` against stub closures for report, reconcile, progress, open meeting and open settings:
   - no data shows `.empty`;
   - a report shows `.report`;
   - progress of 5 or more meetings to read shows `.reading(done, total)`, and 4 does not;
   - `reload(replay: true)` bumps `playID` and resets the anchor, the year (to the current one) and both switches to Meetings;
   - `reload(replay: false)` keeps all four;
   - a reconcile that changed something triggers a second report shown without a new `playID`;
   - `open(record)` calls `openMeeting` with its id;
   - a throwing open logs and rebuilds the report;
   - `changeTypingSpeed()` calls the settings closure.

   Expected initial failure: `cannot find 'TimelineModel' in scope`.
2. Run the app test command — confirm. Scaffold and re-confirm red.
3. Implement:
   - `TimelineModel`, `@MainActor @Observable`, with `Dependencies` as closures.
   - `TimelineSource`, a `Sendable` struct whose `report()` reads `stats.snapshot()`, the meeting index (kept ids and titles) and `typing_wpm` from the config store, then calls `TimelineStats.compute` outside the main actor.
4. Run — pass. Full app tests — green. `TimelineSource` is verified end to end in Stage 20's manual check.

**Definition of done:** R17's three states and R21's replay-and-return rules hold in tests.

**Risks specific to this stage:** None.

### Stage 19 — The Timeline page and panels 1–5, 7, 8, 10
**Goal:** The page as accepted in the overview mockup: title, sub line, states, panels in order with motion and accessibility.
**Category:** platform-only/UI wiring — every rule behind the page is host-tested in Stages 13–18; what remains is SwiftUI layout.
**Design references:** §5 Interfaces (Timeline page, States, Captions, Accessibility), §5 Design language, §5 Performance (Page), R17, R18, R19, R20, R21, R22, R33; `DESIGN.md`; mockup `mockup-v11-overview.html`
**Touches:** `App/Timeline/TimelinePage.swift` (create); `App/Timeline/TimelinePanels.swift` (create); `App/Timeline/TimelinePanelsMore.swift` (create); `App/Design/PageColumn.swift` (optional scroll-position binding and named coordinate space, defaulting to today's behaviour)

**Steps (platform-only/UI wiring):**
1. Build `TimelinePage`:
   - `PageColumn("Timeline")` with the sub line "Tracking since <date> · Kept on this Mac · Costs are estimates";
   - the empty state (cloud-and-pulse mark and the design's text) and the `StatusLine` progress line;
   - panels under hairlines, `space.10` apart;
   - frame reporting into `PanelPlayback`, and `scrollPosition(id:)` bound to the model's anchor.
2. Build the panel views in `TimelinePanels.swift` (1–4) and `TimelinePanelsMore.swift` (5, 7, 8, 10):
   - the Estimate chip on Spend, and "Estimated spend" in the totals;
   - records that open a kept meeting, and the "Deleted meeting" text for a deleted one;
   - the "Change…" link;
   - the year stepper and the Meetings/Dictation switches.
3. Verify with `xcodegen generate && xcodebuild … build` and the full app test command (green; `PageColumn`'s other users unchanged). The visual check against the mockup runs in Stage 20, once the page is reachable.

**Definition of done:**
- Builds clean.
- No colour, size or type outside `DS`.
- Every chart has a sentence label and child values.

**Risks specific to this stage:** Frame preferences fire on every scroll tick. `PanelPlayback` flips a panel's flag once, and the page ignores later updates for played panels.

### Stage 20 — Navigation: the Timeline destination, sidebar row, ⌘3 and the menu row
**Goal:** Timeline is reachable from the sidebar, ⌘3 and the menu. A meeting opened from it returns to it with the scroll position and year kept.
**Design references:** §5 Architecture ("Every site of each extended type": `Destination.timeline`, `MenuItem.Action.timeline`), §5 Interfaces (Sidebar NavRow, Menu), §5 Control flow (Timeline opens), R7, R16, R21
**Touches:**
- `App/Main/MainNavigationModel.swift`: `.timeline`, `backLabel` "Timeline", and `isReturning`, true only inside `back()`.
- `App/Main/MainWindowModel.swift`: `timeline: TimelineModel`; `entered(.timeline)` calls `timeline.reload(replay: !navigation.isReturning)`.
- `App/Main/MainView.swift`: the `page` case.
- `App/Main/SidebarView.swift`: `NavRow` "Timeline", `chart.bar`, `.keyboardShortcut("3")`, between Dictations and Settings.
- `App/MenuModel.swift`: `.timeline`, "Timeline…" after "Dictations…".
- `App/StatusItemController.swift`: `onTimeline` and the `handle` case.
- `App/AppDelegate.swift`: `TimelineModel` with `TimelineSource`, the reconciler, `openMeeting`, and `openStatisticsSettings` (sets `settings.selection = .statistics`, then goes to Settings); `onTimeline: { main?.show(.timeline) }`.
- Tests: `AppTests/MainNavigationModelTests.swift`, `AppTests/MainWindowModelTests.swift`, `AppTests/MenuModelTests.swift`.

**Steps (hybrid — TDD for navigation and menu; manual remainder):**
1. Write the tests.
   - `MainNavigationModelTests`:
     - `.timeline` joins each parameterised destination list;
     - `backPillIsLabelledWithTheOrigin` gains `(.timeline, "Timeline")`;
     - `isReturningIsTrueOnlyDuringBack`;
     - `showMeetingFromTimelineReturnsToTimeline`.
   - `MainWindowModelTests`: `enteringTimelineReloadsWithReplay` and `returningToTimelineReloadsWithoutReplay`, both through stub `TimelineModel` dependencies.
   - `MenuModelTests.initialOrder`: "Timeline…" with `.timeline` after "Dictations…".

   Expected initial failure: `type 'MainNavigationModel.Destination' has no member 'timeline'` and `type 'MenuItem.Action' has no member 'timeline'`.
2. Run the app test command — confirm. Scaffold and re-confirm red.
3. Implement every listed site, so the exhaustive switches in `backLabel`, `entered`, `MainView.page` and `StatusItemController.handle` all compile. `MainWindowModel.init` gains `timeline:` at its two construction sites, `AppDelegate.makeMain` and the test.
4. Run — pass. Full app tests and `swift test` — green.
5. **Remainder (manual).** Open Timeline from the sidebar, from ⌘3 and from the menu. Compare it with the overview mockup in light and dark, at 900 × 600, with Reduce Motion on and off. Open a record and press back: the pill reads "Timeline", and scroll position and year are kept with no replay. "Change…" opens Settings › Statistics.

**Definition of done:** R16 holds end to end, and the page shows panels 1–5, 7, 8 and 10 at their thresholds.

**Risks specific to this stage:** None.

### Stage 21 — The sidebar stats block and its fold handle; Phase B docs
**Goal:** The block above the usage table, the handle on its hairline, fit and visibility rules, and freshness. Phase B ends here.
**Design references:** §5 Interfaces (Sidebar), §5 Control flow (Sidebar refresh), §5 Failure cases (Sidebar too short, Typing speed changed), §5 Design language (Stats block), R23, R24, R25, R26, R33, R35, R36; `DESIGN.md` (the `Stats block` component); mockup `mockup-v11-figures-handle.html`
**Touches:**
- `App/Main/StatsBlockView.swift` (create): the block and its handle.
- `App/Main/UsageTableView.swift`: hosts the handle centred on its top hairline.
- `App/Main/SidebarView.swift`: the block in `ViewThatFits(in: .vertical)` (full, without trend, nothing), hidden while Settings shows or while `sidebarStats` is nil.
- `App/Main/MainWindowModel.swift`: `sidebarStats`, `statsFolded`, `toggleStatsFold()` (flips at once, writes through a dependency), and `windowCameForward()`.
- `App/Main/MainWindowController.swift`: `bringForward` calls `model.windowCameForward()`.
- `App/AppDelegate.swift`: a task over `stats.changes`; refresh computes `SidebarStats` off the main actor; `apply(config)` confirms the fold and refreshes on a new typing speed; the fold dependency writes `timeline_sidebar_folded` via `ConfigStore.update`.
- `AppTests/MainWindowModelTests.swift`.
- `CLAUDE.md`: layout gains `App/Timeline/`; module map row updated.
- `README.md`: "The window" section.

**Steps (hybrid — TDD for the model; manual remainder):**
1. Write `MainWindowModelTests`:
   - `foldFlipsAtOnceAndWritesTheConfig`;
   - `applyingTheConfigConfirmsTheFold`;
   - `theBlockIsHiddenWhileSettingsShows`;
   - `theBlockIsHiddenUntilThereIsData` (nil summary);
   - `comingForwardRefreshes`;
   - `clickingTheBlockOpensTimeline`.

   Expected initial failure: `value of type 'MainWindowModel' has no member 'statsFolded'`.
2. Run the app test command — confirm. Scaffold and re-confirm red.
3. Implement:
   - the model members and the refresh wiring;
   - `StatsBlockView`: "Last 30 days", the 3 × 2 figures, the 26 px trend with 2 px zero ticks in `color.line`, the lifetime line, `space.4` and `space.3`, one button with `color.hover` fill on hover;
   - the 34 × 20 handle with its chevron and accessibility labels;
   - the `ViewThatFits` candidates.
4. Run — pass. Full app tests and `swift test` — green.
5. **Remainder (manual).**
   - Compare against the figures-handle mockup in light and dark.
   - At 900 × 600 the full block fits with 20 px to spare; while a meeting records the trend drops; shorter still, the block and handle hide.
   - The fold persists across a relaunch.
   - The block updates after a dictation.
6. Docs: the `CLAUDE.md` layout and module map, and the README's window section. The CHANGELOG `[Unreleased]` *Added* entry for Timeline and the sidebar block is written by `/feature-implement`'s main agent.

**Definition of done:**
- R23–R26 hold.
- The user can cut the Phase B beta.

**Risks specific to this stage:** The 20 px margin at the minimum height leaves little room for type-size drift. The `ViewThatFits` fallback is the guard, and the manual check measures it.

### Stage 22 — `PeopleStats`
**Goal:** The People panel's rows from kept meetings and remembered people.
**Design references:** §5 Interfaces (People row; Figure rules: Order and ties, Captions (People), People), §5 Architecture (`PeopleStats`), R18
**Touches:** `Package.swift` (`MWStats` gains `MWVoices` and `MWNaming`); `Sources/MWStats/PeopleStats.swift` (create); `Tests/MWStatsTests/PeopleStatsTests.swift` (create)

**Steps (TDD):**
1. Write `PeopleStatsTests`:
   - only speakers of kept, counted meetings with a real name who are not the user;
   - linked speakers group by person, with an alias id resolving to the person that holds it in `aliases`;
   - unlinked speakers group by `NameFold.key`, so "Zoë" and "zoe" are one;
   - hours come from the row's per-speaker seconds;
   - sorting by meetings, then hours, then name;
   - at most 6 rows;
   - a linked group shows the person's current name, and an unlinked one the spelling from its newest meeting.

   Expected initial failure: `cannot find 'PeopleStats' in scope`.
2. Run `swift test --filter PeopleStatsTests` — confirm. Scaffold and re-confirm red.
3. Add the two target dependencies. Implement `PeopleStats.compute(meetings: [Meeting], rows: [UUID: MeetingRow], people: [Person])`.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** The People rules of the design are asserted, and the module graph still flows downwards.

**Risks specific to this stage:** None.

### Stage 23 — `WordTally` and `WordCloud`
**Goal:** A meeting's noun counts and topic words, and the cloud built from cached entries.
**Design references:** §5 Control flow (Word tally, Cloud), §5 Data model (`word-counts.json` entry, 200 and 600 limits), §5 Security (Untrusted content), R14, R31
**Touches:** `Sources/MWStats/WordTally.swift` (create, with the entry type `WordEntry` that `WordCache` stores); `Sources/MWStats/WordCloud.swift` (create); `Tests/MWStatsTests/WordTallyTests.swift` (create); `Tests/MWStatsTests/WordCloudTests.swift` (create)

**Steps (TDD):**
1. Write the tests.
   - `WordTallyTests`:
     - English nouns are kept and personal names dropped;
     - lemmas are lower-cased;
     - the fallback path (forced through the injectable noun-support predicate) keeps words of three or more letters that are not numbers, with `nouns: false`;
     - the 200 and 600 limits break ties alphabetically;
     - topics come from `SummaryDocument(markdown:).topics` through the same filter, and are skipped when `isFourSection`.
   - `WordCloudTests`:
     - topic counts are tripled;
     - fallback-entry terms in half or more of those entries are dropped;
     - fallback entries are ignored while there are fewer than five;
     - names are excluded: speaker-name words, remembered names, the user's name and aliases;
     - the top 40 are sized by rank (10/20/30/40%);
     - the order follows the FNV-1a 64 hash and is stable across runs.

   Expected initial failure: `cannot find 'WordTally' in scope` and `cannot find 'WordCloud' in scope`.
2. Run `swift test --filter "WordTallyTests|WordCloudTests"` — confirm. Scaffold and re-confirm red.
3. Implement with `NLLanguageRecognizer` and `NLTagger` (`.lexicalClass`, `.nameType`, `.lemma`), creating a tagger per call because it is not `Sendable`.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** The design's tally and cloud rules are asserted; NaturalLanguage is the only framework added.

**Risks specific to this stage:** NLTagger output can differ between macOS releases. Test sentences use unambiguous nouns and names, and the fallback is asserted through the predicate rather than a language guess.

### Stage 24 — `WordCache` and the reconciler's word step
**Goal:** `word-counts.json` kept in step with the kept meetings.
**Design references:** §5 Control flow (Reconcile step 4, `meetingStopped`), §5 Data model (`word-counts.json`), §5 Security (At rest), §5 Performance (Word counts), R14, R15, R34
**Touches:** `Sources/MWStats/WordCache.swift` (create); `Sources/MWStats/MeetingReconciler.swift` (`init` gains `words: WordCache? = nil`; step 4 in `reconcile` and `meetingStopped`); `Tests/MWStatsTests/WordCacheTests.swift` (create); `Tests/MWStatsTests/MeetingReconcilerTests.swift`

**Steps (TDD):**
1. Write the tests.
   - `WordCacheTests`:
     - `set`, `entries`, `remove` and `clear`;
     - the file is `{"schema":1,"meetings":{…}}`, 0600 after each atomic rewrite;
     - an unreadable file reads as empty with a `stats` warning, and nothing throws.
   - `MeetingReconcilerTests`:
     - an entry is added for a kept meeting of 60 s or more;
     - none for one under 60 s or for a test call;
     - an entry older than `modified(id)` is recomputed;
     - an entry whose meeting left the store is removed;
     - `meetingStopped` adds the stopped meeting's entry;
     - the log line counts word entries and removals.

   Expected initial failure: `cannot find 'WordCache' in scope` and `extra argument 'words' in call`.
2. Run `swift test --filter "WordCacheTests|MeetingReconcilerTests"` — confirm. Scaffold and re-confirm red.
3. Implement `WordCache(url:)` over `JSONLFile.writeAtomically`, and the reconciler's step 4.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** R14's add and remove rules hold at the core. Nothing writes `word-counts.json` in the app until Stage 26.

**Risks specific to this stage:** Tagging a long transcript at stop adds to Stop's work. The design's budget is under 200 ms for an hour; check it in the Phase C acceptance.

### Stage 25 — Timeline report III: People, Words, Quality
**Goal:** Panels 6, 9 and 11 of the report.
**Design references:** §5 Interfaces (table rows 6, 9, 11; Figure rules: Captions (People, Words, Quality), Quality, Quality table, Quality lines), R9, R18
**Touches:** `Sources/MWStats/TimelineStats.swift` (`TimelineInputs` gains people, kept meetings' `meeting.json`, word entries, names to leave out, and newest scored test calls by engine); `Tests/MWStatsTests/TimelineStatsTests.swift`

**Steps (TDD):**
1. Extend `TimelineStatsTests`. Test each panel one below and at its threshold.
   - **People:** 2 people.
   - **Words:** 5 entries and 30 terms.
   - **Quality** appears at 1 scored test call, 5 counted meetings, or a timing with 10 samples. Its table, one row per engine:
     - accuracy `1 − WER` of the newest scored test call, or "No test call yet";
     - gap share;
     - reconnects per meeting, shown from 5 counted meetings;
     - median live delay once the engine has 10 samples, as the count-weighted median of its meetings' medians.
   - **Quality lines**, each from 10 samples:
     - summary wait median;
     - dictation wait median and p90;
     - undelivered attempts N of M (P%) since `since`, with reasons in falling order;
     - the under-10-samples caption.

   Expected initial failure: `value of type 'TimelineInputs' has no member 'people'`.
2. Run `swift test --filter TimelineStatsTests` — confirm. Scaffold and re-confirm red.
3. Implement the three panels.
4. Run — pass. Full `swift test` and the app build-only check — green.

**Definition of done:** All eleven panels are in the report.

**Risks specific to this stage:** None.

### Stage 26 — Word counts in the app, the delete hook, and the full Settings line
**Goal:** The app keeps `word-counts.json`, removes a meeting's entry when the meeting is deleted, clears it on Reset, and says so in Settings.
**Design references:** §5 Control flow (Meeting deleted, Reset), §5 Interfaces (Settings line, "By phase": C adds the third sentence), §5 Security (word counts), R12, R14, R27
**Touches:** `App/Meetings/MeetingsListModel.swift` (`Dependencies.deleted`, no default, called after a successful whole-meeting delete); `AppTests/MeetingsListModelTests.swift`; `App/AppDelegate.swift` (`WordCache` at `configDirectory/word-counts.json`, the reconciler built with `words:`, `deleted: { await words.remove($0) }`, reset adds `words.clear()` before `reconcile()`); `App/Settings/StatisticsSection.swift` (the third sentence; "They stay" becomes "Both stay")

**Steps (hybrid — TDD for the hook; integration-verified remainder):**
1. Write `MeetingsListModelTests`:
   - `deletingAMeetingReportsItsID`;
   - `deletingOnlyTheAudioReportsNothing`;
   - `aFailedDeleteReportsNothing`.

   Expected initial failure: `value of type 'MeetingsListModel.Dependencies' has no member 'deleted'`.
2. Run the app test command — confirm. Scaffold and re-confirm red.
3. Implement the hook and its two construction sites, the `AppDelegate` wiring, and the Settings line.
4. Run — pass. Full app tests and `swift test` — green.
5. **Remainder (manual).** Stop a meeting of over a minute: its entry appears in `word-counts.json` (0600). Delete it: the entry goes. Reset: the file is cleared and rebuilt.

**Definition of done:** The file is written only alongside its deletion path, its Reset path and its disclosure (security ordering).

**Risks specific to this stage:** None.

### Stage 27 — Timeline panels 6, 9 and 11, and Phase C docs
**Goal:** People, Words and Quality on the page. Phase C ends here.
**Category:** platform-only/UI wiring — the rules are host-tested in Stages 22–25; what remains is gathering inputs and SwiftUI layout.
**Design references:** §5 Interfaces (panels 6, 9, 11; Quality folded on every opening), §5 Design language (Word cloud), §5 Performance (People), R18, R22, R33, R35, R36; `DESIGN.md` (the `Word cloud` component, `type.cloud.small`); mockup `mockup-v11-overview.html`
**Touches:**
- `App/Timeline/TimelineSource.swift`: gathers people from `VoiceStore`, kept meetings' `meeting.json`, word entries, names to leave out (speaker names, people, `meeting_user_name` and aliases), and newest scored test calls from `IndexEntry.test.wer`.
- `App/Timeline/TimelinePanelsMore.swift`: the People, Words and Quality panels; Quality folded on every opening.
- `App/Timeline/TimelinePage.swift`: panel order.
- `App/Design/WordCloudView.swift` (create).
- `App/AppDelegate.swift`: `TimelineSource` gets the voice store and word cache.
- `CLAUDE.md`: module map row with the final component list and edges.
- `README.md`: Privacy section.

**Steps (platform-only/UI wiring):**
1. Build `WordCloudView`:
   - `FlowLayout` of plain `Text` in the four cloud sizes (`type.cloud.small`, `type.title.dialog`, `type.title`, `type.display`);
   - topics in `color.accent`;
   - read in weight order by VoiceOver.
2. Build the three panels with their captions, and extend `TimelineSource`.
3. Verify with `xcodegen generate && xcodebuild … build` and the full app and core suites — green.
4. **Manual:** the design's Phase C acceptance.
   - Delete a meeting and confirm its words leave `word-counts.json`.
   - Compare the three panels with the overview mockup in light and dark, with Reduce Motion on and off.
   - Quality is folded on each opening.
5. Docs: `CLAUDE.md` and the README's privacy section (the record, the word counts file, Reset; everything stays on the Mac). The CHANGELOG `[Unreleased]` entry for People, Words and Quality is written by `/feature-implement`'s main agent.

**Definition of done:**
- All eleven panels show at their thresholds.
- The user can cut the Phase C beta, and later 0.9.0.

**Risks specific to this stage:** Each report reads every kept `meeting.json`, off the main actor. Check the page opens promptly on a large library during acceptance.

## Cross-cutting concerns

- **Security**
  - **No text in the record.** No transcript text, title or person's name enters `stats/`. `StatsSeed` (Stage 5), `MeetingFigures` (Stage 6) and the reconciler end to end (Stage 7) each assert it on fixture bytes.
  - **Permissions.** `stats/` is 0700 and every file in it 0600, reapplied after each atomic rewrite (Stages 1, 3). `word-counts.json` is 0600 (Stage 24).
  - **Logs.** They carry counts, durations, file names and meeting UUIDs, never a word, title, name, bundle identifier or deeper path (Stages 1, 3, 5, 7, 24).
  - **Reset** asks first and names what cannot be recovered (Stage 11).
  - **Word counts.** The app starts writing `word-counts.json` in the same stage that wires its deletion path, its Reset path and its Settings disclosure (Stage 26).
  - **No network or agent access.** Nothing in this feature opens a network connection. The CLI and MCP server keep `MeetingReading` only.
- **Performance**
  - **Recording.** A dictation costs at most three appends, asserted in Stage 3.
  - **Snapshot and report.** The snapshot copies arrays. The report is computed off the main actor by `TimelineSource` (Stage 18).
  - **Charts.** The year grid is one `Canvas` (Stages 16, 19).
  - **Reconcile.** It stats unchanged meetings only (Stage 7) and runs at utility priority at launch (Stage 9).
  - **Budgets.** The design's budgets (50 ms report, 10 s first reconcile at 500 meetings, 200 ms at stop) are checked by hand at each phase acceptance. No timing test runs in CI, where machine speed varies.
- **Observability.** `Log.stats` arrives in Stage 1. The design's info lines land with their owners: seeded and reset (Stage 5); opened, pruned and compacted (Stages 3, 5); reconcile (Stage 7, extended in Stage 24). The three warnings land in Stages 1, 3 and 7.
- **Compatibility / migration**
  - **Shapes and keys.** Only new files are written. `config.usage` keeps its shape (Stage 2), the two config keys round-trip through older builds via `extra` (Stage 12), and `meeting.json`'s new fields are optional and omitted when unset (Stage 4).
  - **Source changes.** `ProviderUsage.purpose` is a source change only (Stage 2).
  - **Phase boundaries.** Rows written in Phase A are read unchanged by B and C. `python-legacy` is untouched.
  - **Between stages** the system builds and its suites stay green. Phase boundaries (after Batch 8 and after Stage 21) are the only points the user cuts a beta.
  - **Intermediate states** of requirements delivered across stages:
    - **R5 (spend).** No spend reaches `stats/` until Stage 8 wires `RecordedUsage`; from then on every purpose is recorded.
    - **R3 (attempts).** Stage 8 records the job's termini; Stage 10 adds the controller's.
    - **R6 (meeting rows).** Rows appear from Stage 9, at stop and at launch.
    - **R12 (Reset).** The control arrives in Stage 11, and Stage 26 adds clearing the word counts, which exist only from then.
    - **R18 (panels).** Panels 1–5, 7, 8 and 10 arrive in Stages 19–20, and panels 6, 9 and 11 in Stage 27.
    - **Bundling.** None of these intermediate states is released, since betas are cut only at phase boundaries, so the stages stay separate rather than bundled.
  - **Disclosure.** The record starts writing in Stage 8. Its Settings line, History footnote and Reset arrive in Stage 11, before Phase A can be cut. The record holds no text in between.

## Verification

1. After Batch 8 (Stages 10 and 11, Phase A), run the design's acceptance by hand on a dev build:
   - dictate, and record a meeting of over a minute;
   - confirm `meta.json`, `dictations.jsonl`, `days.jsonl` and `meetings.jsonl` under `~/.config/mini-whisper/stats/`, at 0700 and 0600;
   - Clear History and delete the meeting: the rows stay;
   - Reset: the record rebuilds and `since` is today.

   Run `/design-language-update`, then cut 0.9.0b4 with `/release` when the user asks.
2. After Stage 21 (Phase B), compare the block and the page with the three accepted mockups in light and dark, at 900 × 600, with Reduce Motion on and off. Check ⌘3, the menu row, the back pill, scroll and year restore, the fold handle across a relaunch, and the "Change…" link. Run `/design-language-update`, then cut the next beta when asked.
3. After Stage 27 (Phase C):
   - delete a meeting and confirm its words leave `word-counts.json`;
   - People, Words and Quality appear at their thresholds;
   - Quality is folded on each opening.

   Run `/design-language-update`. 0.9.0 is released only once the user decides Phase C and v9 have proven themselves on the beta channel.
4. At every stage: the full `swift test` (every `✔ Test run` line green) and the app build-only check. For app stages, also the full app test command.

## Risks and open issues

- **Phase boundaries versus one implement run.** `/feature-implement` builds the whole plan by default, but each phase should be cut as a beta first. **Mitigation:** the schedule puts each phase boundary on a batch boundary (after Batch 8 and after Batch 15). Stop the run there, cut the beta, then resume.
- **Shared-signature stages.** `ProviderUsage` (Stage 2), `Dependencies` (Stage 8), `MeetingDependencies` (Stage 9), `MainWindowModel.init` (Stage 20) and `MeetingsListModel.Dependencies` (Stage 26) each change in one stage, with every construction site listed in its *Touches*.
- **NaturalLanguage variance.** Tagger results vary across macOS releases. **Mitigation:** unambiguous test sentences, and an injectable noun-support predicate for the fallback (Stage 23).
- **Launch seeding on the main actor.** **Mitigation:** small files only. Measure at the Phase A acceptance on a large library. If slow, gathering moves into a detached task before the controller is built, keeping R2's order.
- **`AsyncStream` consumers.** `stats.changes` and `reconciler.progress` each have exactly one consumer: the sidebar refresh task and `TimelineModel`. A second consumer would starve one of them, so the plan adds none.
- **Floating-point totals.** Sums iterate in sorted order (Stages 3, 5), and tests compare with a tolerance.
- **Read-only directory test.** It needs a non-root runner. **Mitigation:** the GitHub macOS runner and a developer Mac both qualify, and the test restores permissions in a `defer`.

## Planning decisions taken

1. **Bottom-up stage order per phase, with hard phase boundaries.** No Phase B or C stage shares a batch with an earlier phase's stage, so each phase can ship as its own beta (R36, §9).
2. **The recording seams land in Stage 1.** `DictationStatsRecording`, `MeetingStatsRecording` and `DictationAttempt` live in `Sources/MWStats/StatsRecording.swift` beside `FakeStatsRecorder`. The design names no file, and both capture stages need only Stage 1.
3. **Stage 1 makes every `Package.swift` registration the design lists for `MWStats` at once.** Later stages never edit the manifest until Stage 22.
4. **`MWStats` also depends on `MWVoices` and `MWNaming`, added in Stage 22.** People groups "by remembered person, resolved through `aliases`", and `Person` and its `aliases` live in `MWVoices`. Names fold "for case and diacritics", which `MWNaming.NameFold.key` already does. The design's dependency sentence and `PeopleStats` row omitted them, and are corrected in place.
5. **`project.yml` gains the `MWStats` product in Stage 8.** The app links each core product by name. Found during grounding: the design's registration paragraph named only `Package.swift`, and is corrected in place.
6. **`Meeting.utcOffsetSeconds` and `Meeting.timing` are properties defaulting to nil, not `init` parameters.** `Meeting.init` and its many callers stay unchanged.
7. **`DelayStats.init?(samples:)` in `MWMeetings` computes the statistics.** Median is the mean of the two middle values for an even count, as `TestCallScorer` does; p90 is nearest rank. The controller calls it, and it is pure and tested where the type lives.
8. **`MeetingRow.Delay` is `MWStats`'s own `{median, p90, count}`.** The design's `StatsRows.swift` depends on nothing, which also lets Stages 3 and 4 run in parallel.
9. **One kept-meeting rule.** `MeetingSource`, `ReconcileProgress`, the `MeetingStore` conformance and `MeetingSource.keptMeetings()` (ended and not a test) live in `MeetingReconciler.swift`. Reconcile and seed gathering share the rule.
10. **`MeetingReconciler.init(stats:source:words:timeZone:now:)`.** `words` defaults to nil until Stage 26 wires a `WordCache`; the design gives no initialiser.
11. **`MeetingDependencies.timeZone` defaults to `{ .current }`.** Both `stats` parameters have no default, as the design requires.
12. **`ProcessingJob.init(deps:clock:)` and `ProcessingInput.releasedAt` are required.** There are two construction sites each, both in Stage 8.
13. **`StatsStore.record(spend:)` ignores `.testCall`.** This is defence in depth behind `RecordedUsage`'s filter.
14. **`MeetingRow.isCounted` and `localStart`/`localEnd` live in `StatsRows.swift` (Stage 3).** `SidebarStats`, `Streaks`, `Milestones` and `TimelineStats` share one counting rule and one local-time rule, which keeps Stages 13 and 14 independent.
15. **Busiest day is the day with the most counted meetings, then the most hours, then the later day.** The design names the record without a rule; the accepted mockup shows "5 meetings, 6 h 10 min".
16. **An engine's median live delay is the count-weighted median of its meetings' `delay.median`, shown once Σ `count` ≥ 10.** Rows keep no raw samples.
17. **People display names.** A linked group shows the person's current name; an unlinked group shows the spelling from its newest meeting. The design was silent.
18. **Design components take plain values, not `MWStats` types.** This applies to `Charts.swift` and `MilestoneStrand.swift`, so Stage 16 builds beside the pure stages.
19. **`PageColumn` gains an optional scroll-position binding and a named coordinate space.** Both default to today's behaviour. Timeline needs them for anchor restore and panel frames, and `PageColumn` owns the `ScrollView`.
20. **`TimelineModel`'s dependencies are closures.** They are report, reconcile, progress, open meeting and open settings, so `TimelineModelTests` run on stubs. `TimelineSource` holds the store reads.
21. **Stage 1 creates `Tests/MWStatsTests/Fixtures/torn-days.jsonl` (synthetic).** The `.copy("Fixtures")` resource then exists from the first stage.
22. **`WordTally` takes an injectable noun-support predicate.** The fallback path is then tested without depending on which NaturalLanguage models a Mac has.
23. **Both new config keys decode with `try?`.** A wrong type reads as the default; the design states this for `typing_wpm`, and the plan applies it to the fold flag too.
24. **`MeetingsListModel.Dependencies.deleted` has no default.** It has two construction sites.
25. **CHANGELOG entries per phase are written by `/feature-implement`'s main agent as its side artefact.** `CLAUDE.md` and `README.md` edits ride in each phase's closing stage (Stages 11, 21, 27).
26. **No CI timing tests.** The design's performance budgets are checked by hand at each phase acceptance; R32's three-append rule is asserted in Stage 3.
27. **One seed-gathering helper.** A private `AppDelegate.makeSeed()` is shared by launch (Stage 8) and Reset (Stage 11), so Reset gathers "a seed as at launch".
28. **The Reset confirmation follows `confirmingBetaChannel`.** Its state lives on `SettingsModel`, the dialog in `MainView`'s chain, and it is cancelled when the destination changes.
29. **The dictation capture is split across two stages.** Stage 8 covers the job's termini with the launch wiring; Stage 10 covers the controller's. Together they deliver R3 before the Phase A beta. Meeting capture (Stage 9) is numbered between them because the controller stage then shares a batch with Stage 11.
30. **README Privacy changes in Stage 11 and again in Stage 27.** R35 says the README describes the feature "as each phase lands", and §9 lists the README under Phase C. The plan reads §9 as the section's completion: Phase A adds the record and Reset, and Phase C adds the word counts. The design is not edited, since the two do not conflict.

## Deviations from the design

1. **R25 extended by the user, 2026-11-25.** While Settings is open the usage table hides too, so every Settings section fits at the 900 × 600 minimum. Found in Stage 21's renders (the Timeline row and the Statistics section took the Settings sidebar to 657 pt); decided on [Settings sidebar fit](./mockups/mockup-v11-settings-overflow.html#usage-hidden) over scrolling the sections or a 660 pt minimum. The design was updated in place (R25, §5 Interfaces › Sidebar, §6).

## Execution schedule

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1 | serial | Establishes the `MWStats` module, its test target and every `Package.swift` registration (convention-establishing). |
| 2 | Stage 2 | serial | Shared-signature change: `ProviderUsage.init` gains a required argument at about 26 sites (category exclusion). |
| 3 | Stage 3, Stage 4 | parallel | **Disjoint files:** new `MWStats` files and tests; `MeetingModel.swift`, `MeetingStore.swift` and their tests. **No symbol or string-keyed dependency:** `StatsRows` defines its own delay type (planning decision 8). **No shared registration:** no manifest or exhaustive-switch edit. **Same base state:** both need only Batches 1–2. **Categories:** neither excluded; Stage 4 adds properties, not `init` parameters. **Security:** no data path opens. **No shared test resource:** core-only, separate `TempDirectory`s, no app test host. |
| 4 | Stage 5, Stage 6 | parallel | **Disjoint files:** `StatsSeed.swift`, `StatsStore.swift` and two new test files; `MeetingFigures.swift` and its test. **No dependency:** the seed writes no meeting rows, and figures do not touch the store. **No shared registration** point. **Same base state:** Batch 3. **Categories:** not excluded. **Security:** nothing is wired into the app. **No shared test resource:** core only. |
| 5 | Stage 7 | serial | Consumes `MeetingFigures` (Stage 6) and the `MeetingStore` reads (Stage 4). |
| 6 | Stage 8 | serial | Shared-signature change (`Dependencies`, `ProcessingJob`, `ProcessingInput`); adds a product to `project.yml`; edits `AppDelegate.swift`. |
| 7 | Stage 9 | serial | Shared-signature change (`MeetingDependencies`); edits `AppDelegate.swift` after Stage 8. |
| 8 | Stage 10, Stage 11 | parallel | **Disjoint files:** `DictationController.swift` and its test; `App/Settings/*`, `MainView.swift`, `AppDelegate.swift`, `SettingsModelTests.swift`, `CLAUDE.md` and `README.md`. **No dependency:** Stage 10 records through Stage 8's `stats`, while Stage 11 uses Stage 8's `makeSeed()` and Stage 9's reconciler. **No shared registration:** the `Section` switch sites belong to Stage 11 alone, and there is no manifest edit. **Same base state:** Batch 7. **Categories:** neither excluded (`SettingsModel.Dependencies` gains a defaulted field). **Security:** Reset only erases, behind its confirmation. **Test resource:** only Stage 11 launches the app test host. Ends Phase A. |
| 9 | Stage 12, Stage 13, Stage 14 | parallel | **Disjoint files:** `Config.swift` and the Settings files with their tests; `StatFormat`/`SidebarStats`; `Milestones`/`Streaks`. **No dependency:** `SidebarStats` takes the typing speed as an `Int`, and all three use only Stage 3's row helpers. **No shared registration** point. **Same base state:** Batch 8. **Categories:** not excluded. **Security:** n/a. **Test resource:** only Stage 12 launches the app test host. |
| 10 | Stage 15, Stage 16 | parallel | **Disjoint files:** `TimelineStats.swift` and its test; `App/Design`, `App/Timeline/TimelineMotion.swift`, `DSTests` and `PanelPlaybackTests`. **No dependency:** components take plain values (planning decision 18). **No shared registration:** a new app folder is picked up by `xcodegen generate`, no manifest edit. **Same base state:** Batch 9. **Categories:** not excluded. **Security:** n/a. **Test resource:** only Stage 16 launches the app test host. |
| 11 | Stage 17 | serial | Same `TimelineStats.swift` as Stage 15. |
| 12 | Stage 18 | serial | Consumes the complete Phase B report (Stages 15, 17) and the typing-speed key (Stage 12). |
| 13 | Stage 19 | serial | Consumes `TimelineModel` (Stage 18) and the components (Stage 16). |
| 14 | Stage 20 | serial | Shared-signature change (`MainWindowModel.init`); exhaustive switches over `Destination` and `MenuItem.Action`. |
| 15 | Stage 21 | serial | Same `MainWindowModel.swift`, `SidebarView.swift` and `AppDelegate.swift` as Stage 20. Ends Phase B. |
| 16 | Stage 22 | serial | Adds target dependencies in `Package.swift` (category exclusion). |
| 17 | Stage 23 | serial | No sibling ready: Stage 24 needs its `WordEntry`, and Stage 25 its `WordCloud`. |
| 18 | Stage 24, Stage 25 | parallel | **Disjoint files:** `WordCache.swift`, `MeetingReconciler.swift` and their tests; `TimelineStats.swift` and its test. **No dependency:** both consume Stage 23's types, neither the other's. **No shared registration** point. **Same base state:** Batch 17. **Categories:** not excluded. **Security:** nothing is wired into the app (the app's `words` stays nil until Stage 26). **No shared test resource:** core only. |
| 19 | Stage 26 | serial | Consumes `WordCache` (Stage 24); edits `AppDelegate.swift`. |
| 20 | Stage 27 | serial | Consumes the full report (Stage 25) and the app wiring (Stage 26); same `AppDelegate.swift`. Ends Phase C. |

**Critical path:** Stage 1 → 2 → 3 → 6 → 7 → 8 → 9 → 11 → 14 → 15 → 17 → 18 → 19 → 20 → 21 → 22 → 23 → 24 → 26 → 27 (20 of 27 stages).

## Deviations from plan

Recorded during implementation.

- **Stage 1, `PrivateFile` moved to `MWSupport`.** `JSONLFile` needs a 0600 append and a temp-0600-rename write, which `MWVoices`' internal `PrivateFile` already provides beside a second copy in `MeetingStore.write`. A third copy was avoided by making `PrivateFile` public in `MWSupport` (its tests move to `MWSupportTests`); `MatchLog` imports `MWSupport`. Behaviour is unchanged.
- **Stage 1, `StatsTime` without formatters.** Keys and ISO times are computed from the zone's offset at the instant over one static UTC Gregorian calendar, and `parse` reads the fixed 25-character shape byte by byte. This keeps output locale- and calendar-independent, as the `en_US_POSIX` formatter would, without a per-zone formatter cache that Swift 6 cannot share safely. Day keys are Gregorian even when the injected calendar is not (tested with a Buddhist calendar).
- **Stage 1, `dictationCutoff` is the start of a local day.** The plan says "13 calendar months back"; the cutoff is the start of the local day 13 months before `now`, so pruning removes whole days.
- **Stage 1, first red.** SwiftPM refuses a target with no sources (`target 'MWStats' referenced in product 'MWStats' is empty`), so `no such module 'MWStats'` cannot occur. The first red was that manifest error, then `cannot find 'DictationAttempt' in scope`, then expectation failures against the scaffold.
- **Stage 1, `StatsRecordingTests.swift` added.** One test pins the ten `Outcome` raw values, the on-disk names Stage 1 promises.
- **Stage 2, a test call never names.** `MeetingController.namingRoute(test:_:)` returns nil for a test call, so no naming usage of one can be produced and the planned "naming of a test call adds `.testCall`" cannot be observed. `aTestCallsUsageIsTestCall` gives the test call a naming client and speaks a naming trigger, then asserts no naming request and that stop and summary add `[.testCall, .testCall]`. The naming site still states its purpose through the same `usagePurpose(_:)` helper as stop and summary, so the design's rule holds if test calls ever name.
- **Stage 2, first red.** The tests never name `UsagePurpose` as a type, so the build errors were `extra argument 'purpose' in call` and `value of type 'ProviderUsage' has no member 'purpose'` rather than `cannot find type 'UsagePurpose' in scope`.
- **Stage 3, an unreadable file is never rewritten.** The design covers unwritable files and undecodable lines, not a whole file failing to read. `open` logs `stats: <file> not read: <reason>`, holds that file empty in memory, and refuses every rewrite of it (fold, prune, compaction) for the session, so memory missing those lines never replaces them. Appends continue.
- **Stage 3, `dictations.jsonl` is rewritten at open when it holds more lines than rows.** It has no compaction, so this is how a torn line or pruned rows leave it, keeping R11 true for that file.
- **Stage 3, row shapes.** `localStart`/`localEnd` are `DateComponents?` at the row's own offset (nil for an unparseable time). `DayRow.undelivered` and `.spend` are keyed by raw strings, since `unsplit` is not a `UsagePurpose`. Non-optional fields are omitted at zero; optional ones are written whenever set, so `user: 0` survives; `seeded` is written only when true. `StatsSnapshot` holds the three arrays only; `meta` arrives in Stage 5. `open()` does not create `stats/`; the first append does, 0700.
- **Stage 3, first red.** Synthesized `Codable` made round-trip tests pass against the scaffold, so the scaffold carried stub coding; two absence-only tests were folded into tests with a positive counterpart, so every test was red first.
- **Stage 4, `meeting(_:)` replaces the private `readMeeting(_:)`.** Same body; the store's four internal callers use the public read. `aMeetingWithoutTimingEncodesAsToday` and `timingAndOffsetAbsentDecodeAsNil` guard today's behaviour and pass against the scaffold by design.
- **Stages 3 and 4 ran as parallel batch 3.** Both landed without conflict.
- **Stage 5, the seed takes every stored meeting.** `StatsSeed(meetings:)` applies the rules itself: finished non-test meetings give earlier months' spend (step 3), finished test calls come out of this month's unsplit usage (step 2), unfinished meetings are ignored. `keptMeetings()` excludes test calls, so **Stage 8's `makeSeed()` passes every stored meeting (index → `meeting(_:)`), not `keptMeetings()`.**
- **Stage 5, test-call subtraction.** Step 2 subtracts the call's `Meeting.totalCostUSD` and its `billing.engineSeconds` under `engine.pricingKey`; tokens are not subtracted (the design names cost and seconds only). Seconds keys at or below zero are dropped; a day with no unsplit spend left gets no line.
- **Stage 5, seeded `spend.dictation`** holds the entry's cost and its streamed seconds under the engine name, as `StreamBilling` records live. History keeps no tokens.
- **Stage 5, day keys.** Meeting start days and test-call end days use the injected calendar, not `utcOffsetSeconds`. `monthStart` is the `yyyy-MM-01` of `now`'s local day key, compared as strings.
- **Stage 5, `meta.json` only after a complete seed.** `seed` removes `meta.json` first, then the row files, and writes `meta.json` back only if every removal and seeded write succeeded, so a failed write behaves as a crash and the next launch reseeds. `reset` logs `stats: reset`, then seeds. An unreadable `meta.json` logs `stats: meta.json not read: <reason>` before it is rewritten. `created` uses `StatsTime.iso` at UTC (`+00:00`).
- **Stage 5, `StatsSnapshot.meta: StatsMeta?`** added in `StatsRows.swift` (defaulted in `init`).
- **Stage 5, noted, not changed.** A meeting started before `monthStart` whose usage landed this month (one running past a month-end midnight, or a summary regenerated this month) counts in both step 3 and this month's unsplit, as the design's "started before `monthStart`" rule implies.
- **Stage 6, one offset per row.** `at` and `end` both use `utcOffsetSeconds`, or the fallback zone's offset at the start, so a meeting across a DST change keeps its start offset on both. A meeting without `endedAt` gets no `end`.
- **Stage 6, turn and question rules.** Segments in start order; `turns` counts speaker changes between neighbours; `longest_turn` sums one speaker's run of segment lengths; a question is a segment whose last non-space character is `?` or `？`; `speakers` lists ids with at least one segment, by id; `duration` is `meeting.durationSeconds` (pauses excluded). The no-text test also asserts the row's only strings are the id, the three times, `mode` and `engine`.
- **Stage 6, `computed`** is `StatsTime.iso(now, timeZone: .gmt)`, whole seconds; Stage 7 compares it with `modified(id)` at whole seconds.
- **Open design question (Stage 6): `reconnects` counts pauses.** The row records distinct sessions minus one, as the design says, but `MeetingController.resume()` opens a new session after every pause and `SessionSupervisor` one at each session-limit rollover, so the Quality panel's "reconnects a meeting" would read high. Left as designed; to settle before Phase C (Stage 25).
- **Stages 5 and 6 ran as parallel batch 4.** Both landed without conflict. A full-suite run after landing Stage 5 hung idle in `MWTestCallTests` (unrelated); that target passed alone in 0.25 s and the full suite then passed.
- **Stage 7, `keptMeetings()` returns index entries.** `[IndexEntry]` (ended, no test tag), so no `meeting.json` is read; a caller that needs the meeting reads `meeting(_:)`.
- **Stage 7, `MeetingReconciler.init(stats:source:timeZone:now:)`** with `timeZone` defaulting to `{ .current }` and `now` to `{ Date() }`. `words` arrives in Stage 24.
- **Stage 7, `progress` keeps every value.** The stream is unbounded: a pass yields one value per meeting read, then nil, so a reader sees each step in order. It holds at most one pass's values while nobody reads.
- **Stage 7, `meetingStopped`** applies the kept rule to the loaded `meeting.json` (the same function as `keptMeetings()`), recomputes whether or not the row looks stale, and publishes no progress and no log line. An unreadable index logs `stats: index.json not read: <reason>` and the pass returns false. A row whose `computed` cannot be parsed is recomputed; a meeting whose files give no modification date keeps its row.
- **Stage 7, single-flight tests.** `MeetingSource` is synchronous, so the spy holds `load` on an `NSCondition`, not a continuation. The second caller is the test's own main-actor task, and the release is a main-actor task that can run only once that call has moved onto the busy reconciler, so the join is deterministic without a sleep.
- **Stage 8, `makeSeed` takes the stores.** `private static func makeSeed(history:configStore:store:) async -> StatsSeed`, because the three are locals of `startNormal`; Stage 11 passes the same. It reads every stored meeting through the index (`meeting(_:)` per entry; one that cannot be read is left out) and the config's current `usage`.
- **Stage 8, `makeMeetings`** gains `recordedUsage: RecordedUsage` for `MeetingDependencies.usage`, beside `usage: UsageStore` for `meetingChanged`'s totals.
- **Stage 8, one controller test added.** `DictationControllerTests.theWaitRunsFromTheKeyRelease`: cleanup advances the clock 2 s after a release, and the delivered attempt's wait is 2. The job test measures the wait across a paste that itself takes 0.8 s, so the reading is taken after the paste returns.
- **Stage 8, first red** was `extra argument 'stats' in call`: the tests were written against the new signature first.
- **Stage 9, the harness takes a probe.** `MeetingHarness(stats:)` accepts any `MeetingStatsRecording` in place of its `FakeStatsRecorder`. The stats suite's `StopProbe` takes down, at the report, the controller's state, the summary requests made so far and whether the stored meeting has ended: `.stopped`, 0 and true.
- **Stage 9, `aTestCallTakesNoSamples`** runs the same segment in a meeting and in a test call, so it is red first.
- **Stage 9, the summary wait** is read at the start of `requestSummary`, before its config read, so a test that sees `.summary(.writing)` or `.rewriting` can move the clock knowing the start is taken. `adopt` keeps the stored `transcriptDelay`.
- **Stage 9, `timing` at stop** is written only when there is a sample; a meeting with none keeps `timing` nil until its summary.
- **Stage 9, `AppDelegate`** relies on `MeetingDependencies.timeZone`'s default `{ .current }` rather than passing it.
- **Stage 9, noted, not changed.** `meetingStopped` waits for a running pass, as the design says, so a meeting stopped during the first launch pass over a large library waits for that pass before its summary is requested.
- **Stage 10, a short quiet recording is `too_short`.** The gate tests length first, as its guard does.
- **Stage 10, ordering.** Device change, gate, profile error and abort record before the off sound and UI event; the mic error records after its error, so a new press cannot show `.starting` before the old error.
- **Stage 10, `theWaitRunsFromReleaseToThePaste` not added.** Stage 8's `theWaitRunsFromTheKeyRelease` covers it. With Stage 8, all fourteen termini of design §4 record exactly one attempt, each pinned by a test.
- **Stage 11, confirm runs once.** `confirmReset()` returns unless the question is open; a second confirm calls nothing.
- **Stage 11, README history bullet.** "nothing further is written" became "no further text is written", to match the reworded History row.
- **Stage 11, CLAUDE.md.** The `MWStats` row sits after `MWTestCall`; `MWPipeline`, `MWMeetingPipeline` and `MWTestSupport` list it; `MWSupport` gains `PrivateFile`.
- **Stage 11, noted, not changed.** A reset during a running reconcile pass joins that pass (single flight), so meetings that pass refreshed before the reset lose their rows until the next reconcile: next launch, a meeting stop, or, from Phase B, Timeline opening.
- **Stages 10 and 11 ran as parallel batch 8.** Both landed without conflict. Offscreen snapshots of the Statistics section, History card and Reset dialog (light and dark) match the design's strings and the accepted mockup's structure.
- **Phase A boundary.** The run stopped after Batch 8, as *Risks and open issues* prescribes, for the 0.9.0b4 cut. Stages 12–27 remain.
- **Stage 12, `Config.typingWPMRange`.** The 10…120 bounds live once on `Config` (as `meetingSilenceStopChoices` does); `validated()` clamps to it and `SettingsModel.typingSpeedRange` is that constant. `SettingsModel.typingSpeedStep` (5) is tested rather than inlined. A wrong-typed value of either key reads as the default and the next save writes the default.
- **Stage 13, rounding and forms.** Values round half away from zero at the precision shown, and the form is chosen after rounding (9,999.5 → `10k`, 999,950 → `1M`; sidebar 999.5 → `1k`, 99,950 → `100k`; 59 m 30 s → `1 h`, 99.95 h → `100 h`). Page `k` has up to one decimal and `M` up to two; sidebar one decimal from 1k, whole thousands from 100k, `M` with up to one decimal; durations read `h m` from 1 h to under 10 h (dropping `0 m`), `14.5 h` from 10 h, whole and grouped from 100 h. Trailing zero decimals are dropped.
- **Stage 13, locale.** Every `StatFormat` function takes a `Locale` (default `.current`); the suffixes are literal. Tests pin `en_US`, not `en_US_POSIX`, which groups no thousands; a `de_DE` test proves the locale is used. `money` follows `Pricing.dollars`.
- **Stage 13, units and window.** `SidebarStats` durations are seconds (`recorded`, `savedTyping`, `trend`, `lifetimeRecorded`), for `StatFormat.duration`. The 30-day window is counted on a Gregorian calendar in the injected zone from midday, so a DST change cannot shift it; a meeting falls on its own local start day; a row with an unreadable `at` counts only in the lifetime line; a typing speed ≤ 0 saves nothing.
- **Stage 14, day arithmetic and ties.** Streaks take recorded local day keys (`DayRow.day`, a meeting's start day at its own offset), so `Streaks` and `Milestones` take no calendar or `now`; consecutive days add calendar days on a fixed UTC Gregorian calendar. Milestones reached on one day are ordered by ladder, then value; of equal streaks the later is the longest. A streak step is dated on the step-th day of the first streak that long; dictations and dictated words come from `days.jsonl`, kept for life. `Milestones(snapshot, streaks:)` reuses the report's `Streaks`.
- **Stages 12–14 ran as parallel batch 9** and landed without conflict. Two siblings had each derived a meeting's local start day, so a follow-up `refactor` commit put one `MeetingRow.startDay` in `StatsRows.swift` for `SidebarStats`, `Streaks`, `Milestones` and Stage 15.
- **Stage 15, report shape.** `TimelineInputs(snapshot:kept:typingWPM:now:calendar:)` takes `kept: [UUID: KeptMeeting {title, start}]` and has no defaults, so Stage 18's wiring cannot be missed. `TimelineReport.weekdays` gives the row order (from `calendar.firstWeekday`) once for both grids. The year range is `min(earliest active year, this year)…this year`. Values are numbers, durations in seconds; formatting is the view's.
- **Stage 15, rhythm in Meetings mode counts meeting starts** by local weekday and hour at the meeting's own offset; each mode has its own busiest cell. Of equal cells the later in the grid is busiest. Quarter levels are `ceil(4 × count ÷ largest)`. Back-to-back uses meetings with a readable start and end, sorted by start. Latest finish is whole local days from start to end × 24 h plus the end's time of day. Talk share divides by zero as 0; a meeting whose `user` is missing from `speakers` adds no user seconds.
- **Stage 15, open for Stages 18–19.** The report does not carry `meta.since` (the page's "Tracking since …"): read it from the snapshot. The mockup's Dictation caption ("from 24 Nov") names a first day the design does not; the report gives `dictationDays`, and the first day can be read from the grid.
- **Stage 16, `type.score` reused.** `DS.TextStyle.score` already existed for the test call's WER; only its comment changed, and `DSTests` pins `score` and `cloudSmall`.
- **Stage 16, extra pieces in `Charts.swift`.** `ChartColors` (the code home of the chart-series Do, decision 88), `ChartLegend` (series dots and the Less→More heat steps) and `View.timelineFade(_:)`. Layout-local sizes from the mockup: heat cells at most 10 px, shrinking to fit; meters 6 px (milestones) and 8 px (people, apps); legend dot 8 px; strand dot 9 px with a 3 px canvas ring.
- **Stage 16, how motion is driven.** `TimelinePanel` puts a `TimelinePlay` (played, start delay) in the environment; shapes animate with `TimelineMotion.Track` animations, and `CountUpText` and the `HeatGrid` Canvas redraw from an animated clock. Counts and fades ease out; bars and meters use the mockup's `cubic-bezier(.2,.8,.2,1)`. Going back to the start state is instant.
- **Stage 16, `PanelPlayback`.** Panels starting in the same `update` start 80 ms apart, top first; `update` returns whether anything started, so scroll ticks need not write state back; `replay(_:)` takes an `Int` play ID and clears the played set only when it is new. It keeps no frames, so Stage 19 calls `update` again after a replay's start states have drawn.
- **Stages 15 and 16 ran as parallel batch 10** and landed without conflict. Offscreen renders of every component (light and dark, 54 columns at the 588 px minimum column) match the overview mockup. `StatsTime`, `Streaks` and `TimelineStats` each held a private UTC Gregorian calendar and parsed day keys their own way, so a follow-up `refactor` commit made `StatsTime.utc` and `StatsTime.date(ofDay:)` the one home.
- **Stage 17, report shape.** `TimelineReport` gains `spend: Spending?` (named so beside the `Spend` row type), `dictation: Dictation?`, `records: Records?` and `milestones: [Milestone]?` (the eight latest, nil until one is reached). `Spending` has `months` (12 `Month {year, month, amounts: [Purpose: Double]}`, a purpose without a cost left out), `series` (purposes with a cost in a shown month, in stacking order `dictation, meeting, summary, naming, unsplit`), `thisYear`, `allTime` and `perRecordedHour`; the caption flag is `showsUnsplitCaption`, read from `series`. `Records` has `longestMeeting` and `mostSpeakers` as `MeetingRecord {id, day, amount, meeting: KeptMeeting?}` (nil `meeting` once deleted), `busiestDay {day, meetings, recorded}`, `mostWords {day, words}`, `longestStreak` and `next` (meetings, hours, dictations; an exhausted ladder left out). `Dictation` carries the `typingWPM` it was saved against for the label.
- **Stage 17, figure rules the design left open.** The Spend panel appears at any day with a cost, even one before the 12 months shown; a spend key that is not one of the five purposes counts in all time only. Day spend is summed in key order, so equal records give equal totals. Per recorded hour takes every meeting row, under a minute included (its cost still counts, R9), as meeting + summary + naming ÷ hours. Words a minute is Σ timed words ÷ Σ speaking minutes, nil without timed speech. Apps of equal count order by bundle identifier. The typical dictation is `DelayStats(samples:)`'s median (mean of the two middles). Meeting records take counted meetings with a readable start; most speakers counts `speakers` and is nil while no meeting has one; most words is nil while no day has words.
- **Stage 17, `SidebarStats.swift` touched.** Time saved lives once as the internal `TypingSpeed.saved(timedWords:spoken:wpm:)`, used by `SidebarStats` and the Dictation panel. `Streaks` is computed once per report and shared by the year, the records and `Milestones`.
- **Stage 18, model shape.** `TimelineModel.Dependencies { report: @Sendable () async -> TimelineContent, reconcile: @Sendable () async -> Bool, progress: AsyncStream<ReconcileProgress?>, openMeeting: @MainActor (UUID) async throws -> Void, openSettings: @MainActor () -> Void }`. `progress` is the stream itself, not a closure: the model reads it on one task started in `init`, as `PeopleModel` reads `changes`, so Stage 20 hands `reconciler.progress` to the one `TimelineModel` and nothing else iterates it. `TimelineContent { report, since: String? }` carries `meta.since` beside the report. `state` is nil until the first report (so the empty state never flashes before it), `.reading(done, total)` while `progress.total >= 5` (also before the first report), else `.empty` when every panel is nil, else `.report`; while reading, the page shows the progress line over whatever panels the report gives (design failure case "Timeline opened during the first reconcile"). `selectedYear: Int?` is nil for this year (`shownYear` falls back to the last year), with `canStepYear(by:)`/`stepYear(by:)`; `yearMode`/`rhythmMode: Mode {meetings, dictation}`; `anchor: Panel?`; `Panel` lists panels 1–5, 7, 8, 10 in page order. The model owns `playback: PanelPlayback<Panel>` so a return, which rebuilds the page view, keeps the played set; `reload(replay: true)` calls `playback.replay(playID)` when it bumps the ID.
- **Stage 18, reload order.** The report is built first and then, in one main-actor step, shown together with the replay's resets, so the page never plays an old report. A failed `open` logs `timeline: meeting <uuid> not opened: <reason>` under `Log.stats` and rebuilds without replay.
- **Stage 18, `TimelineSourceTests` added.** One app test runs `TimelineSource.report()` over a seeded `StatsStore` in a temp directory, a stub `MeetingSource` and a `ConfigStore`: `since`, the typing speed, a kept record's title and an unfinished meeting's record without one. Written after the source (integration-verified category); Stage 20's manual check still covers the live wiring. An unreadable index logs `timeline: index.json not read: <reason>` and every record then reads as deleted.
- **Stage 19, model changes found while wiring the page.** `reload(replay: true)` now starts over (bumps `playID`, replays `playback`, clears the anchor, the year and both switches) before its first suspension, then builds the report; this supersedes Stage 18's "reload order". A fresh page is built from whatever the model holds, so resetting after the report showed a stale anchor and final values for a moment; the shown report then plays (`anOpeningStartsOverBeforeItsReportIsBuilt`). Stage 20's `entered(.timeline)` should call `reload` so its synchronous prefix runs before the page draws. `canStepYear`/`stepYear` are gone: the year stepper is a `StepperPill` bound to the shown year over the report's year range, and `StepperPill` gains defaulted `decrease`/`increase` symbol names for its chevrons. `TimelineContent.appNames` (bundle identifier → name) is filled off the main actor by `TimelineSource.apps: any AppListing` (default `NSWorkspaceApps()`, through `name(forBundleID:)`, which falls back to the readable end of the identifier); `TimelineSourceTests` covers it.
- **Stage 19, `PageColumn`.** `PageColumn<Content, Position: Hashable>`; the existing `init(_:content:)` lives in `extension PageColumn where Position == Never`, so every other page is unchanged and gets exactly today's view. `init(_:scrollPosition:coordinateSpace:content:)` applies `scrollPosition(id:)` and `coordinateSpace(.named(_:))` to the scroll view. Checked on the macOS 27.2 SDK interfaces: `onGeometryChange(for:of:action:)` is back-deployed to macOS 13; `scrollPosition(id:anchor:)`, `scrollTargetLayout()`, `coordinateSpace(_:)` and `NamedCoordinateSpace.named` are macOS 14.
- **Stage 19, frames and playback.** Each panel reports its frame in the scroll view's named space through one preference (`GeometryReader` background), so `onPreferenceChange` sees every frame at once and panels starting together get their 80 ms stagger. Frames and the viewport live in a reference held in `@State`, so scrolling writes no view state; played panels are filtered out and `model.playback` is written back only when a panel starts. After a new `playID` the page replays from the last frames in a task, once the start states have drawn. Panels are `id`'d by `TimelineModel.Panel` inside a `scrollTargetLayout()` stack, in `Panel.allCases` order, so Phase C adds its cases where they belong.
- **Stage 19, wording and layout decisions.** Dates use fixed `en_US_POSIX` patterns as the rest of the app does (`MeetingsListModel.formatter`), day keys read and written in UTC. Figures and record values go through `StatFormat` ("41.2k words", "1 h 30 m"); milestone and meter names are ladder steps written out with grouping, as in the mockup ("100,000 words", "1 million words", "First meeting", "7-day streak", "250 hours"). The year grid labels the Mon, Wed and Fri rows wherever the first weekday puts them; the Dictation caption adds ", from <d MMM>" on the first year with dictation; a finish on a later day reads "24:30". The rhythm's Dictation switch shows only once its grid exists, and the busiest hour follows the switch. Talk share's bars are scaled to a 100% share. Changing the year or a switch does not replay its panel (the mockup does; the design is silent). The empty state keeps the Meetings empty state's spacing. Lifetime totals step down to `type.title`, labels wrapping to two lines, when a final figure (measured in the tabular digits it is drawn in) or its label does not fit an equal fifth: at the 588-pt minimum column; the mockup's 672 keeps `type.score`.
- **Stage 19, visual check.** Offscreen renders (light and dark; full report at 832 and 652 pt, empty, reading) match the overview mockup. `cacheDisplay` draws stray vertical strokes at capsule ends (the Estimate chip and the existing `SegmentedPill`); `ImageRenderer` draws the same views clean, so it is a capture artifact.
- **Stage 20, wiring.** `makeMain` gains `timeline: TimelineSource` and `reconciler:` and builds the one `TimelineModel` itself, sharing one `openMeeting` closure with the results page; "Change…" sets `settings.selection = .statistics`, then opens Settings. `isReturning` is `@ObservationIgnored`. `entered(.timeline)` reads it before starting `reload` in a main-actor task, since the task starts after `back()` returns; the task's synchronous prefix runs before the next view update in practice (`Task.immediate` needs macOS 26). `MenuModelTests.lastAndCorrectRowsInsertedAfterMonthOnFirstResult` also gains the row, since it pins the whole menu.
- **Stage 20, no "⌘3" hint on the row.** The figures-handle mockup draws one on Timeline alone; the overview mockup, the design text and the Meetings (⌘1) and Dictations (⌘2) rows have none, so the row matches its neighbours.
- **Stage 20, first red.** `type 'MenuItem.Action' has no member 'timeline'` was not reached: the build stopped at the navigation and window suites (`Destination` has no member `timeline`, `extra argument 'timeline'`, no member `isReturning`), and the harness's untyped `lazy var model` read inside its own hook gave `circular reference` until typed. The scaffold then made all three suites fail as expectations (13 issues).
- **Stage 20, visual check.** Offscreen renders of the main window on Timeline at 900 × 600 and 1180 × 760, light and dark: the row sits between Dictations and Settings with `chart.bar`, selected. The live checks (⌘3, the menu row, the back pill, scroll and year restore, Reduce Motion, "Change…") need the running app and were not performed.
- **Stage 21, each fit candidate carries the usage table.** `ViewThatFits(in: .vertical)` holds block over table, the block without its trend over table, and the table alone, and sits under the nav rows in a bottom-aligned `.frame(maxHeight: .infinity)` with a `space.5` top padding in place of the `Spacer` (the same two gaps). With the block's `ViewThatFits` beside the table, in a stack of its own or beside the `Spacer`, with or without `layoutPriority(1)`, it was offered only a share of the free height and chose nothing at 600 pt; the full block first appeared near 800 pt. The handle rides on the candidates' tables, so it goes with the block without a preference key; folding swaps the handle into another branch, so its chevron flips without the mockup's 0.15 s turn. While folded the handle shows at any height; unfolding where nothing fits hides it with the block.
- **Stage 21, measured fit.** The block is 223 pt and the usage table 65 pt, not the design's 218 and the 62 its 362 sum assumes: each `type.usage` line lays out at 17 pt. At the 600 pt minimum 12 pt remain, 6 pt while a meeting records (design: 20 and 14). The full block fits from a 588 pt sidebar (594 recording), the block without its trend from 554 pt (560); below that the table shows alone, without its handle.
- **Stage 21, block shape.** Padding is `space.3` vertically and `space.2` horizontally, as the accepted mockup's 6 px 4 px, so the figures line up with the usage table's labels. Columns are equal halves `space.6` apart, rows `space.4`; trend bars are `space.1` apart with `radius.cell` tops. The block is one button whose label is its text, with the hint "Opens Timeline"; the trend is hidden from VoiceOver. The lifetime line uses `StatFormat.sidebarNumber` and `StatFormat.duration` ("256 meetings · 224 h all time").
- **Stage 21, model and refresh.** `MainWindowModel.Dependencies` gains defaulted `foldStats: @MainActor (Bool) -> Void` and `refreshStats: @MainActor () -> Void`; the model gains `sidebarStats`, `statsFolded`, `showsStats` (data and not Settings), `toggleStatsFold()`, `apply(_ config:)` (the fold; `makeMain` calls it at launch), `windowCameForward()` and `openTimeline()`. `AppDelegate` feeds one `bufferingNewest(1)` request stream from the `stats.changes` reader, `refreshStats` and a typing-speed change in `apply(config)`, and one task computes `SidebarStats` in a detached task per request, so refreshes never overlap or land out of order. A failed fold write logs `sidebar fold not saved: <reason>` under `Log.ui`; the model stays flipped until the next config change.
- **Stage 21, docs.** `CLAUDE.md`'s layout lists folders only, so it gains `App/Timeline/` and not `StatsBlockView.swift`.
- **Stage 21, open issue found, not changed: Settings overflows the sidebar at the minimum height.** With Settings' eleven sections showing, the sidebar needs 657 pt: 598 before v11, plus 27 for Statistics (Stage 11) and 32 for the Timeline row (Stage 20). At the 600 pt minimum the overflow splits, the search pill rises under the traffic lights and the usage table's Month row is cut off; at the 720 pt default it fits. The stats block is hidden in Settings and plays no part. The fix (scroll the sections, hide the usage table in Settings, or a taller minimum) is a design decision.
- **Stage 21, visual check.** Offscreen renders (light and dark) of the main window at 900 × 600 and of the sidebar: idle at 600 (full), 570 (no trend) and 530 (table alone, no handle); recording at 600 and 594 (full) and 590 (no trend); folded at 600 and 530 (chevron up); Settings; no data. They match the figures-handle mockup. Hover, the fold across a relaunch and the refresh after a dictation need the running app and were not checked.
- **After Stage 21, `fix: hide the usage table while Settings shows`.** Lands the R25 extension above in Stage 21's files (`MainWindowModel.showsUsage`, the sidebar foot, one test), test first, as a `fix:` commit rather than a new numbered stage so Phase C's numbering holds. A re-render of the Settings sidebar at 600 pt shows every section with the search pill in place.
- **Phase B boundary.** The run stopped after Batch 15 and the fix, for the next beta cut. Stages 22–27 (Phase C) remain.

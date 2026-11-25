# Timeline and Sidebar Statistics — Design v11

**Status:** Draft
**Date:** 2026-11-24
**Storm:** [feature-storm-v11-Timeline-and-sidebar-statistics.md](./feature-storm-v11-Timeline-and-sidebar-statistics.md)

## 1. Summary

Mini Whisper gains a numbers-only record of its user's meetings, dictation and estimated spend, and two surfaces that show it: a Timeline page and a foldable stats block in the sidebar. The record exists because today only meeting figures reach back in time: dictation history is pruned after 7 days, daily usage at the month end, and deleting a meeting lowers every total. The record ships first, in a beta, so history starts accruing before the page exists; the page and block follow in later betas. Everything stays on the Mac.

## 2. Goals and non-goals

- **Goals:**
  - A record under `~/.config/mini-whisper/stats/` that keeps per-day and per-meeting numbers for life and per-dictation numbers for 13 months, and survives meeting deletion, history pruning and the month end.
  - New capture: every dictation attempt with its outcome, the wait from key release to pasted text, live transcript delay, summary wait, and the UTC offset a meeting started in.
  - A Timeline page reached from a sidebar row, ⌘3 and the menu-bar menu, built from the record and from the meetings still kept.
  - A sidebar block showing the last 30 days and one lifetime line, foldable, above the usage table.
  - Settings › Statistics with a typing speed and Reset statistics; a truthful History row.
  - Delivery in three phases on the 0.9.0 betas, record first. 0.9.0 is released only when all three are done.
- **Non-goals:**
  - Year in review, a page-wide range switch, opening a day from the year calendar, sharing the infographic, announcing milestones on a meeting page, a statistics CLI command or MCP tool, month-on-month deltas, showing sub-minute recordings as false starts, app-use counts, goals, invoice reconciliation. All deferred by the storm.
  - A per-request timing file. Summary wait lives with its meeting (§6).
  - Any change to the usage table or to `UsageStore`'s month pruning.
  - Changing existing behaviour this design only records around: streamed seconds are not billed when batch transcription fails, the streaming engine is not finished when profile resolution fails, open bugs 1 and 2, and the early binding of a remote label to the user (§7).
  - Other projects. The feature lives in this repository alone; there are no briefs.

## 3. Requirements

**Record**

1. **R1 Location and content.** The record is `~/.config/mini-whisper/stats/` (0700) holding `meta.json`, `days.jsonl`, `dictations.jsonl` and `meetings.jsonl` (each 0600). It holds numbers and identifiers only: meeting UUIDs, dictation ids, app bundle identifiers, engine names. No transcript text, title or person's name. Nothing is sent off the Mac.
2. **R2 Start.** On the first launch without `meta.json` the record is seeded (R10) and `meta.json` is written with `since` set to that local date. Seeding completes before a hotkey or meeting can record.
3. **R3 Dictation attempts.** Every dictation attempt ends in exactly one row in `dictations.jsonl`, with one of ten outcomes (§5 Data model). A delivered row carries words, seconds, wait and cost.
4. **R4 Day rows.** `days.jsonl` holds, per local day: dictations delivered, words, speaking seconds, undelivered attempts by outcome, delivered count by app and by hour, and spend by purpose.
5. **R5 Spend.** Every `UsageRecording.add` states a purpose. Dictation, meeting, summary and naming spend is added to the day row. Test-call spend is not recorded. Stored costs are summed, never recomputed.
6. **R6 Meeting rows.** Every finished, non-test meeting has one row in `meetings.jsonl`, written when it stops and refreshed when its files change. Deleting the meeting leaves its row.
7. **R7 Reconcile.** At launch, when a meeting stops, when Timeline opens and after a reset, each kept, finished, non-test meeting whose row is missing, older than its files, or of an older figures version is recomputed.
8. **R8 Retention.** Dictation rows older than 13 calendar months are pruned. Day and meeting rows are kept for life.
9. **R9 Counting rules.** A meeting with under 60 s of recorded time is kept in the record but excluded from every count and display; its cost still counts. Test calls are excluded. Clearing dictation history, and a history retention of 0 days, leave dictation numbers untouched.
10. **R10 Seed.** The seed takes dictation rows from `history.jsonl`, the current month's unsplit cost from `config.json`, and earlier months' meeting costs from kept meetings (§5 Control flow). It is idempotent and cannot overlap rows written live.
11. **R11 Crash safety.** A crash leaves at most one torn line, which is skipped on read and dropped at the next compaction. No row is written twice.
12. **R12 Reset.** Reset statistics erases the record and the word-count file, seeds again and sets `since` to the reset date. Figures of deleted meetings and pruned dictations are lost. Timing fields inside `meeting.json` are untouched.
13. **R13 Meeting capture.** A meeting stores the UTC offset it started in, its live transcript delay (median, 90th percentile, sample count) and the wait for its latest summary, in `meeting.json`.
14. **R14 Word counts.** `~/.config/mini-whisper/word-counts.json` (0600) holds per-meeting word counts for the word cloud, for kept meetings only. A meeting's entry is added when it stops and at launch, and removed when the meeting is deleted.
15. **R15 Isolation.** No failure in the record, the reconcile or the word counts fails a dictation, a meeting or a summary. Their entry points do not throw. Failures are logged.

**Timeline page**

16. **R16 Navigation.** Timeline is a destination of the main window: a sidebar row between Dictations and Settings with ⌘3, and "Timeline…" in the menu-bar menu after "Dictations…". A meeting opened from it returns to it, with the back pill reading "Timeline".
17. **R17 States.** With no data the page shows the empty state. While a reconcile has five or more meetings to read it shows a progress line with the count. Otherwise it shows its panels.
18. **R18 Panels.** The page shows, in this order, each only at its threshold (§5 Interfaces): lifetime totals, the year, weekly rhythm, talk share, spend, people, dictation, records with next milestones, words, milestones reached, quality.
19. **R19 Records.** A record tied to a kept meeting opens it. One tied to a deleted meeting shows its date and "Deleted meeting" and is not a control.
20. **R20 Estimates.** Every cost on the page is labelled an estimate.
21. **R21 Motion.** On an opening that is not a return from a meeting, each panel plays once when it first comes into view: figures count up, charts draw in. With Reduce Motion, final values show at once. A return restores the scroll position and the selected year and plays nothing.
22. **R22 Accessibility.** Every chart has a written VoiceOver summary and exposes its values as a list.

**Sidebar**

23. **R23 Block.** Above the usage table the sidebar shows "Last 30 days", six figures (meetings, recorded, dictations, saved typing, words transcribed, words dictated), a 30-bar trend of hours recorded and one lifetime line. Clicking it opens Timeline.
24. **R24 Fold.** A handle on the usage table's top hairline folds the block, leaving the table and the handle. The state persists across launches. The block starts unfolded.
25. **R25 Visibility and fit.** The block and its handle are hidden while Settings is open and until one counted meeting or delivered dictation exists. While Settings is open the usage table is hidden too, so every Settings section fits at the 900 × 600 minimum (decided 2026-11-25, [Settings sidebar fit › usage-hidden](./mockups/mockup-v11-settings-overflow.html#usage-hidden)). When the sidebar is too short the block drops its trend, then hides.
26. **R26 Freshness.** The block updates after each recorded dictation, spend or meeting row, and when the window comes forward.

**Settings and menu**

27. **R27 Statistics section.** Settings gains a Statistics section after People with one card: Typing speed, Reset statistics, and a line saying what is kept.
28. **R28 Typing speed.** 10 to 120 words a minute in steps of 5, default 40. It drives every "saved typing" figure.
29. **R29 Reset control.** Reset Statistics asks in the in-window dialog before erasing.
30. **R30 History row.** The History row reads "0 days turns history off and keeps no dictation text", with a line under the card saying dictation numbers are kept regardless.

**Non-functional**

31. **R31 Platform.** macOS 14, arm64, Swift 6 with complete strict concurrency. No new dependency: charts are SwiftUI shapes, word tagging is Apple's NaturalLanguage.
32. **R32 Performance.** Recording a dictation adds no network call and at most three small file appends. The page's report is computed off the main actor. A first reconcile of a large library runs in the background and never blocks dictation.
33. **R33 Design language.** Every colour, size and type style comes from `DS`. The 15 changes recorded as `pending v11` become DS code.
34. **R34 Logging.** The record logs counts and durations only, under a new `stats` category.
35. **R35 Documentation.** `CHANGELOG.md`, the module map and layout in `CLAUDE.md`, and the README's window and privacy sections describe the feature as each phase lands.
36. **R36 Phases.** Phase A is the record and its Settings control. Phase B is the block, navigation and every panel but three. Phase C is People, Words and Quality.

## 4. Background and context

- **Basis.** [docs/statistics-findings.md](../../docs/statistics-findings.md) lists what the app stores and loses. The storm closed its five decisions; this design closes the storm's eighteen open questions.
- **Daily usage is pruned at the month end.** `UsageStore.add` filters `config.usage` to the current month on every write (`Packages/MiniWhisperCore/Sources/MWUsage/UsageStore.swift:30`). A `DayUsage` holds one cost and one token pair for every purpose (`MWConfig/Config.swift:53`).
- **Dictation numbers go with the text.** `history.jsonl` is the only per-dictation record and is pruned at `history_retention_days` (`MWHistory/HistoryStore.swift:66`). Only delivered dictations are recorded (`MWPipeline/ProcessingJob.swift:167`).
- **A meeting's numbers go with the meeting.** `MeetingStore.delete` removes the folder and its index row (`MWMeetings/MeetingStore.swift:83`).
- **Usage is built in six places and carries no purpose.** `ProviderUsage(` appears in `ProcessingJob.swift:144` and `:233`, `MeetingBilling.swift:40` and `:44`, and `MeetingController.swift:915` and `:1240`. A test call bills through the same path as a meeting (`MeetingController.swift:588`).
- **Dictation ends in fourteen places.** In the controller: the capture error (`DictationController.swift:114`), a device change (`:182`), the too-short or silent gate (`:208`), a profile error (`:227`) and `abort` (`:100`). In the job: three stale checkpoints (`ProcessingJob.swift:58`, `:105`, `:129`), no key (`:62`), a transcription error (`:85`), an empty transcript (`:91`), a cleanup error (`:113`), a paste error (`:162`) and delivery (`:181`).
- **Nothing after the press is timed.** `RecordingSession.pressedAt` is held (`MWPipeline/ControllerState.swift:9`); `ProcessingJob` has no clock.
- **Transcript delay is measured in test calls only.** `segmentArrivals` is filled only when `meeting.test != nil` (`MeetingController.swift:289`), and the scorer takes arrival minus the line's end (`MWTestCall/TestCallScorer.swift:203`).
- **The user's voice.** In a remote meeting the microphone gate attributes words to the user (`MWMeetingPipeline/SpeakerAttributor.swift:48`). In an in-room meeting no speaker is the user unless one is merged into the user's label.
- **Main window.** Destinations are an enum with five cases (`App/Main/MainNavigationModel.swift:8`), switched over in `backLabel` (`:48`), `MainWindowModel.entered` (`App/Main/MainWindowModel.swift:107`) and `MainView.page` (`App/Main/MainView.swift:30`). In-window confirmations are a chain in `MainView.dialog` (`:50`).
- **Sidebar.** 248 px wide (`MainView.swift:15`). A `VStack` with 10 px spacing holds search, Start Meeting or the 36 px recording pill (`App/Main/RecordingPill.swift:24`), the nav rows, a spacer and the usage table (`App/Main/SidebarView.swift:15`–`:52`). The window's minimum is 900 × 600 with a full-size content view (`App/Main/WindowFramePolicy.swift:15`, `App/Main/MainWindowController.swift:23`, `:32`).
- **Settings.** Ten sections in an enum (`App/Settings/SettingsModel.swift:76`), each with a title and a symbol, switched over in `SettingsPage` (`App/Settings/SettingsPage.swift:11`). The History row says "0 days turns history off and writes nothing" (`App/Settings/HistorySection.swift:18`).
- **Menu.** The menu's rows are data in `MenuModel` (`App/MenuModel.swift:42`), dispatched in `StatusItemController` (`App/StatusItemController.swift:101`).
- **Composition root.** `AppDelegate.startNormal` builds the stores and both controllers (`App/AppDelegate.swift:106`). The hotkey listener starts at `:212`, after everything it drives.
- **Prior design.** [v6](../feature-v6-Unified-window-and-design-language/feature-design-v6-Unified-window-and-design-language.md) set the window, sidebar and design language this feature extends.
- **Design language state.** `DESIGN.md` was reconciled in this design (region `e198965`). Its recorded drift, the test call's Earlier runs sheet, touches none of these surfaces.

## 5. Design

### Architecture / components

One new core module, `MWStats`, holds every rule. It depends on `MWMeetings`, `MWUsage`, `MWHistory`, `MWConfig` and `MWSupport`, and, for `PeopleStats`, on `MWVoices` (`Person` and its `aliases`) and `MWNaming` (`NameFold`, the case-and-diacritic fold). `MWPipeline`, `MWMeetingPipeline` and `MWTestSupport` gain a dependency on it. Nothing in `MWStats` imports AppKit or SwiftUI.

| Component (file in `Sources/MWStats/`) | Responsibility | Depends on |
|---|---|---|
| `StatsRows.swift` | `DictationRow`, `DayRow`, `MeetingRow`, `StatsMeta`, `StatsSnapshot`; their JSON shapes | — |
| `StatsTime.swift` | Local day keys, hours, ISO times with a UTC offset, the 13-month cutoff | — |
| `JSONLFile.swift` | Append a line, read lines tolerantly, rewrite atomically, 0600 | MWSupport |
| `StatsStore.swift` | Actor owning the four files: seed, record, upsert, fold, prune, compact, reset, snapshot, change stream | the three above |
| `StatsSeed.swift` | Pure: seed rows and day deltas from history, usage and kept meetings | MWHistory, MWMeetings, MWConfig |
| `WordCount.swift` | Pure: words in a text | — |
| `MeetingFigures.swift` | Pure: a `MeetingRow` from a `LoadedMeeting` | MWMeetings |
| `MeetingReconciler.swift` | Actor: brings meeting rows and word counts up to date | StatsStore, WordCache, `MeetingSource` |
| `RecordedUsage.swift` | `UsageRecording` decorator that also records spend | MWUsage, StatsStore |
| `WordTally.swift` | A meeting's word counts and topic words (NaturalLanguage) | MWMeetings |
| `WordCache.swift` | Actor owning `word-counts.json` | JSONLFile's atomic write |
| `WordCloud.swift` | Pure: the cloud from cached entries and names to leave out | — |
| `TimelineStats.swift` | Pure: the page's report from a snapshot | StatsRows |
| `Milestones.swift`, `Streaks.swift` | Pure: ladders, dated milestones, streaks | StatsRows |
| `PeopleStats.swift` | Pure: people from kept meetings and their rows | MWMeetings, MWVoices, MWNaming |
| `SidebarStats.swift` | Pure: the block's figures and trend | StatsRows |
| `StatFormat.swift` | Pure: number, duration and money text | — |

App side, new folder `App/Timeline/`:

| File | Responsibility |
|---|---|
| `TimelineModel.swift` | `@MainActor @Observable`: state, selected year and modes, replay token, scroll anchor, opening a record |
| `TimelineSource.swift` | Gathers the report's inputs off the main actor and calls `TimelineStats` |
| `TimelinePage.swift` | The page: title, sub line, states, panels in order, visibility tracking |
| `TimelinePanels.swift`, `TimelinePanelsMore.swift` | One view per panel |
| `TimelineMotion.swift` | Motion constants and `PanelPlayback` |
| `App/Design/Charts.swift` | `HeatGrid`, `BarChart`, `SplitBar`, `MeterBar`, `StatFigure`, `CountUpText`, `TimelinePanel` |
| `App/Design/WordCloudView.swift`, `MilestoneStrand.swift` | The two remaining components |
| `App/Main/StatsBlockView.swift` | The sidebar block and its handle |
| `App/Settings/StatisticsSection.swift` | The Statistics section |

Changed: `MainNavigationModel`, `MainWindowModel`, `MainView`, `SidebarView`, `UsageTableView` (hosts the handle), `MainWindowController`, `MenuModel`, `StatusItemController`, `SettingsModel`, `SettingsPage`, `HistorySection`, `MeetingsListModel`, `AppDelegate`, `DS`; in core `Config`, `ProviderUsage`, `MeetingBilling`, `MeetingController`, `MeetingDependencies`, `MeetingModel`, `MeetingStore`, `DictationController`, `ProcessingJob`, `ProcessingInput`, `Dependencies`, `Log`, `Package.swift`.

Each pure component is tested alone. The three actors are tested against a temp directory and fakes; none needs the app.

Registration is explicit. `Package.swift` gains the `MWStats` target and product and an `MWStatsTests` test target with `resources: [.copy("Fixtures")]`, and adds `MWStats` to the dependencies of `MWPipeline`, `MWMeetingPipeline` and `MWTestSupport`. `project.yml` adds the `MWStats` product to the app target's dependencies, which name each core product. `CLAUDE.md` gains the module-map row and `App/Timeline/` in its layout.

Every site of each extended type:

- **`MainNavigationModel.Destination.timeline`**: `backLabel` returns "Timeline"; `MainWindowModel.entered` reloads the page; `MainView.page` shows `TimelinePage`. `beforeSearch` already covers it. `MainNavigationModel` also gains `isReturning`, true only inside `back()`.
- **`SettingsModel.Section.statistics`**: `title`, `symbolName`, and the switch in `SettingsPage`. The sidebar's list reads `allCases`.
- **`MenuItem.Action.timeline`**: the row in `MenuModel.init` and the case in `StatusItemController.handle`.
- **`Config`'s two keys**: the properties, their `Key` constants, `Key.all`, `init(from:)`, `encode(to:)` and `validated()`.
- **`ProviderUsage.purpose`**: the six producers, `DayEntry.add(_:)`, which ignores it, and `FakeUsageStore`.
- **The usage store in `AppDelegate`**: `Dependencies.usage` and `MeetingDependencies.usage` take the `RecordedUsage` wrapper. `makeMeetings` takes both, the wrapper for the dependency and the `UsageStore` for `meetingChanged`'s totals.

### Data model

All JSON uses sorted keys. Zero and empty fields are omitted on write and read as zero. Unknown keys are ignored on read.

**`stats/meta.json`**

| Key | Type | Meaning |
|---|---|---|
| `schema` | int | 1 |
| `since` | string | Local date the record started, `yyyy-MM-dd` |
| `created` | string | UTC instant |

Its existence, not its readability, marks the record as seeded. An unreadable file is rewritten with `since` set to the earliest day in `days.jsonl`, or today when there is none.

**`stats/dictations.jsonl`**, one line per attempt

| Key | Type | Meaning |
|---|---|---|
| `id` | string | UUID. Equals the history entry's id when delivered |
| `at` | string | ISO 8601 with numeric offset, `2026-11-30T09:14:03+00:00` |
| `app` | string? | Bundle identifier of the target app |
| `engine` | string? | `EngineName` raw value; absent for batch only |
| `seconds` | number | Recording length. Seeded rows: streamed seconds |
| `words` | int | 0 unless delivered |
| `outcome` | string | `delivered`, `too_short`, `silent`, `superseded`, `no_key`, `empty`, `failed`, `mic_error`, `device_changed`, `aborted` |
| `wait` | number? | Seconds from key release to the paste returning. Delivered, live rows only |
| `usd` | number | What the attempt was billed |
| `seeded` | bool? | `true` only for rows taken from history |

**`stats/days.jsonl`**, additive lines folded by `day`

| Key | Type | Meaning |
|---|---|---|
| `day` | string | Local `yyyy-MM-dd` |
| `delivered` | int | Dictations delivered |
| `words` | int | Words dictated |
| `seconds` | number | Speaking seconds of delivered dictations that have a length |
| `timed_words` | int | Words of those same dictations |
| `undelivered` | {outcome: int} | Attempts not delivered |
| `apps` | {key: int} | Delivered count by bundle identifier; `other` when unknown |
| `hours` | {"0"…"23": int} | Delivered count by local hour |
| `spend` | {purpose: Spend} | Purposes `dictation`, `meeting`, `summary`, `naming`, `unsplit` |

`Spend` is `{usd, tokens_in, tokens_out, seconds: {engineKey: number}}`. Each event appends one line holding only its own increments. Reading sums lines of the same day. The file is rewritten folded, one line a day, at open and after every 2,000 appended lines.

**`stats/meetings.jsonl`**, latest line per `id` wins

| Key | Type | Meaning |
|---|---|---|
| `id` | string | Meeting UUID |
| `at`, `end` | string | Start and end, ISO 8601 with offset |
| `duration` | number | Recorded seconds, pauses excluded |
| `mode`, `engine` | string | `MeetingMode`, `MeetingEngine` raw values |
| `speech` | number | Σ segment lengths |
| `words` | int | Words transcribed |
| `user` | int? | Speaker id of the label marked `isUser` |
| `user_known` | bool | `mode` is remote, or the user has words |
| `speakers` | [{`id`, `seconds`, `words`, `questions`}] | Per speaker id |
| `named` | int | Non-user speakers with a real name |
| `turns` | int | Speaker changes |
| `longest_turn` | number | Longest run by one speaker, seconds |
| `questions` | int | Segments ending in `?` or `？` |
| `notes` | int | Notes taken |
| `gaps`, `paused` | number | Seconds in gap markers; in paused and sleep markers |
| `reconnects` | int | Distinct sessions minus one |
| `silence_stop`, `summary` | bool | Stopped by silence; has a summary |
| `usd` | {`meeting`, `summary`, `naming`} | `billing.costUSD`; current plus replaced summaries; naming |
| `delay` | {`median`, `p90`, `count`}? | Copied from `meeting.timing` |
| `summary_wait` | number? | Copied from `meeting.timing` |
| `figures` | int | `MeetingFigures.version`, 1 |
| `computed` | string | UTC instant |

A segment's words are `words.count`, or `WordCount.count(text)` when the segment is edited or has no word list. `WordCount` counts with Foundation's `.byWords` enumeration, so unspaced scripts count too. The file is compacted to one line per id at open when it holds more lines than ids.

**`meeting.json`** gains two optional fields on `Meeting`: `utcOffsetSeconds: Int?` and `timing: MeetingTiming?`, where `MeetingTiming` is `{transcriptDelay: DelayStats?, summaryWaitSeconds: Double?}` and `DelayStats` is `{median, p90, count}`. Files without them decode as before.

**`word-counts.json`** (beside `stats/`, not in it)

```json
{"schema":1,"meetings":{"<uuid>":{"computed":"2026-11-30T10:02:11Z","language":"en","nouns":true,
  "words":{"budget":12,"release":9},"topics":["budget"]}}}
```

An entry keeps the 200 most frequent terms when `nouns` is true and 600 when false, ties broken alphabetically. The whole file is rewritten atomically on change.

**`config.json`** gains `timeline_sidebar_folded` (bool, default `false`) and `typing_wpm` (int, default 40, clamped to 10…120 in `validated()`, a wrong type read as the default).

**Lifetimes.** Dictation rows: 13 calendar months from `at`, pruned at open and on the first row recorded each new local day. Everything else in `stats/`: until Reset. A word-count entry: until its meeting is deleted.

### Interfaces

**Core**

```swift
// MWUsage
public enum UsagePurpose: String, Sendable, Codable { case dictation, meeting, summary, naming, testCall = "test_call" }
public struct ProviderUsage {            // purpose has no default: every producer states it
    public init(purpose: UsagePurpose, inputTokens: Int = 0, outputTokens: Int = 0,
                streamedSeconds: [String: Double] = [:], costUSD: Double = 0)
}

// MWStats
public protocol DictationStatsRecording: Sendable { func record(_ attempt: DictationAttempt) async }
public protocol MeetingStatsRecording: Sendable { func meetingStopped(_ id: UUID) async }
public protocol MeetingSource: Sendable {
    func index() throws -> [IndexEntry]
    func load(_ id: UUID) throws -> LoadedMeeting
    func meeting(_ id: UUID) throws -> Meeting
    func modified(_ id: UUID) -> Date?      // newest mtime of meeting.json, segments.jsonl, notes.jsonl
}
public struct DictationAttempt: Sendable, Equatable {
    public var id: String, bundleID: String?, engine: String?
    public var seconds: Double, words: Int, outcome: Outcome, wait: Double?, costUSD: Double
}
public actor StatsStore: DictationStatsRecording {
    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() },
                calendar: @escaping @Sendable () -> Calendar = { .current })
    public nonisolated let changes: AsyncStream<Void>          // buffers the newest only
    public var needsSeed: Bool { get }
    public func open()                                          // load, prune, compact
    public func seed(_ seed: StatsSeed)                         // empties the directory first
    public func record(_ attempt: DictationAttempt)
    public func record(spend usage: ProviderUsage)
    public func upsert(_ row: MeetingRow)
    public func meetingRows() -> [UUID: MeetingRow]
    public func snapshot() -> StatsSnapshot
    public func reset(_ seed: StatsSeed)
}
public actor MeetingReconciler: MeetingStatsRecording {
    public nonisolated let progress: AsyncStream<ReconcileProgress?>   // (done, total); nil when idle
    @discardableResult public func reconcile() async -> Bool            // true when a row or entry changed
}
public struct RecordedUsage: UsageRecording                 // init(base: any UsageRecording, stats: StatsStore)
public actor WordCache { func set(_:for:), remove(_:), clear(), entries() }
```

`MeetingStore` gains `public nonisolated func meeting(_ id: UUID) throws -> Meeting` and `modified(_:)`, and conforms to `MeetingSource`. `Dependencies` (MWPipeline) gains `stats: any DictationStatsRecording`; `MeetingDependencies` gains `stats: any MeetingStatsRecording` and `timeZone: @Sendable () -> TimeZone`. Neither `stats` has a default, so a missed wiring fails to compile. `ProcessingJob.init` takes a `clock`; `ProcessingInput` gains `releasedAt: TimeInterval`.

**Timeline page**, as accepted in [Timeline overview](./mockups/mockup-v11-overview.html) ([artifact](https://claude.ai/artifact/YFMu3DbgPPg3APpFnc7h5p)). A `PageColumn` titled "Timeline" with the sub line "Tracking since <date> · Kept on this Mac · Costs are estimates". Panels are open on the canvas, each under a hairline, with a `type.heading` title; none is a card. Counted meetings are rows with `duration ≥ 60`.

| # | Panel | Appears when | Content |
|---|---|---|---|
| 1 | Lifetime totals | 1 counted meeting or 1 delivered dictation | Meetings, hours recorded, words transcribed, dictations, estimated spend, in `type.score`. A zero figure is left out |
| 2 | The year | 1 active day | Heat grid, 7 rows by 53 or 54 week columns, with a Meetings/Dictation switch and a year stepper from the earliest year with data to this year. Caption: active days and longest streak in that year; in Dictation mode, days with dictation |
| 3 | Weekly rhythm | 10 counted meetings; the Dictation switch at 50 delivered | Heat grid, weekday by hour. Figures: busiest hour, back-to-back meetings, earliest start and latest finish |
| 4 | Talk share | 3 counted meetings with `user_known` | Split bar "You N%" against everyone else; your words a minute; questions you asked; your share in each of the last 20 such meetings as bars; a caption giving how many meetings count |
| 5 | Spend | 1 day with a cost | Estimate chip; 12 monthly bars stacked by purpose with a legend of the series present; this year, all time, per recorded hour |
| 6 | People | 2 people | Up to 6 rows: name, a bar by hours, "N meetings · H h" |
| 7 | Dictation | 20 delivered | Words dictated; time saved at the typing speed with a "Change…" link to Settings › Statistics; words a minute; top 5 apps as glyph, name, bar and count; typical and longest dictation |
| 8 | Records | 3 counted meetings | Longest meeting, busiest day, most words in a day, longest streak, most speakers; then the next milestone for meetings, hours and dictations as meters |
| 9 | Words | 5 word-count entries and 30 terms | 40 words in the serif at four sizes; summary-topic words in the accent |
| 10 | Milestones | 1 reached | The 8 latest reached milestones on a rail, oldest first, each with its date |
| 11 | Quality | 1 scored test call, or 5 counted meetings, or a timing with 10 samples | Folded. A table by engine and three lines (below) |

Figure rules:

- **Heat levels.** Year, meetings: 0 for none, then under 1 h, under 2 h, under 4 h, 4 h or more. Year, dictation: 0, 1–5, 6–15, 16–40, over 40. Rhythm: 0 for none, then quarters of the grid's largest cell.
- **Week.** Weekday order and week columns follow the system calendar's first weekday. A meeting counts on the local day it started.
- **Streak.** Consecutive local days with at least one counted meeting or delivered dictation. The year's caption counts a streak only within that year.
- **Order and ties.** People sort by meetings, then hours, then name. Top apps leave out `other`. A record shared by two days or meetings goes to the later one. A ladder with no step left shows no meter. The 12 spend months end with the current month.
- **Captions.** Spend, while any shown month has an unsplit part: "This month's usage was recorded before costs were split by purpose, so it shows as one part. Earlier months come from the meetings still stored." People: "From the meetings you keep. Deleting a meeting or forgetting a person removes them here." Words: "The nouns heard most in the meetings you keep. Names of people are left out." Quality, while a timing has under 10 samples: "Delays, waits and undelivered attempts appear after ten have been measured."
- **Quality.** Folded on every opening; the state is not stored. The dropout and reconnect columns show from 5 counted meetings.
- **Accessibility.** Each chart is one element whose label is a sentence stating its headline figure, with its values as child elements: one per month, weekday, person, app or milestone. A heat grid's children are its non-empty weeks. Stat figures read as "214 meetings". Cloud words read in weight order.
- **Back-to-back.** A counted meeting starting 0 to 300 s after the previous counted meeting ended.
- **Latest finish.** The greatest end time of day, an end on a later local day than its start counting as past 24:00.
- **Talk share.** Σ user seconds ÷ Σ speech over meetings with `user_known`. Pace is Σ user words ÷ Σ user minutes.
- **Spend.** A month is the sum of its day rows by purpose. Per recorded hour is Σ `usd` of all meeting rows ÷ Σ their hours, shown from 1 h.
- **People.** Speakers of kept, counted meetings with a real name who are not the user. They group by remembered person, resolved through `aliases`, when linked; otherwise by name, folded for case and diacritics. Hours come from the meeting row's per-speaker seconds.
- **Time saved.** `max(0, Σ timed_words ÷ typing speed − Σ seconds ÷ 60)` minutes.
- **Typical and longest dictation.** Median and maximum words of delivered rows in `dictations.jsonl`.
- **Most words in a day.** Meeting words by start day plus words dictated that day.
- **Milestones.** Meetings and hours: 1, 10, 25, 50, 100, 250, 500, 1,000. Words (transcribed plus dictated): 10k, 50k, 100k, 250k, 500k, 1M. Dictations: 1, 100, 500, 1,000, 5,000, 10,000. Streak: 7, 30, 100 days. A milestone is dated the local day its running total first reached it.
- **Quality table**, one row per engine with a counted meeting or a scored test call: test-call accuracy `(1 − WER)` of its newest scored test call, or "No test call yet"; share of recorded time in gap markers; reconnects a meeting; median live transcript delay once an engine has 10 samples.
- **Quality lines**, each from 10 samples: "Summary wait: half arrive within X s"; "Dictation wait: half within X s, nine in ten within Y s"; "Attempts not delivered: N of M (P%)" with reasons in falling order, counted from `since`.
- **Numbers.** On the page: under 10,000 with separators, then `86.4k`, then `1.42M`. In the sidebar: from 1,000 as `8.4k`, `126k`, `1.4M`. Durations: `42 m`, `1 h 50 m`, `14.5 h`, whole hours from 100 h. Money: `Pricing.dollars`.

States: the empty state is the cloud-and-pulse mark, "Nothing to show yet" in `type.title` and "Record a meeting or dictate something. Your totals, records and milestones build up here, and stay on this Mac." The progress line is a `StatusLine`, "Reading stored meetings… D of T".

**Sidebar**, as accepted in [Figures grid with handle](./mockups/mockup-v11-figures-handle.html) ([artifact](https://claude.ai/artifact/Qn2P2K7L8A669fHR833VtC)).

- A `NavRow` "Timeline", symbol `chart.bar`, between Dictations and Settings, with `.keyboardShortcut("3")`.
- The block sits between the spacer and the usage table: the label "Last 30 days" (`type.usage`, medium, secondary); a 3 × 2 grid of figures in `type.heading.3` over `type.usage` labels in tertiary, in the order Meetings, Recorded, Dictations, Saved typing, Words transcribed, Words dictated; a 26 px trend of 30 bars, oldest first, each a day's hours recorded, a zero day drawn as a 2 px tick in `color.line`; the line "N meetings · H h all time". Inner spacing `space.4`, padding `space.3`.
- The whole block is one button that opens Timeline, with a `color.hover` fill at `radius.field` on hover.
- The handle is a 34 × 20 pill, `color.sidebar` fill and `color.line` border, centred on the usage table's top hairline, with a chevron pointing down when unfolded and up when folded. Its accessibility label is "Fold statistics" or "Unfold statistics".
- "Last 30 days" is today and the 29 local days before it. A figure with nothing in that window shows zero.
- Fit: the block is 218 px. Everything else in the sidebar, spacing included, is 362 px, so at the 600 px minimum 20 px remain, and 14 px while a meeting records. The block sits in `ViewThatFits(in: .vertical)` with three candidates: full, without the trend, nothing.
- Settings: with Settings' eleven sections showing the column needs 657 px, so while Settings is open the usage table hides as the block does, and the sections fit at the 600 px minimum ([Settings sidebar fit](./mockups/mockup-v11-settings-overflow.html#usage-hidden), [artifact](https://claude.ai/artifact/6hvrrh4ipkvpDuvUMUetSd#usage-hidden)).

**Settings**, as accepted in [Statistics settings placement › Statistics section](./mockups/mockup-v11-settings-placement.html#statistics-section) ([artifact](https://claude.ai/artifact/4MT6gNnJH7KqxZd31kRCVf#statistics-section)).

- `SettingsModel.Section.statistics`, after `.people`: title "Statistics", symbol `chart.bar`.
- One `Card`:
  - **Typing speed** — "Used to estimate the time dictation saves you, shown on Timeline." A `StepperPill`, range 10…120, step 5, label "40 wpm".
  - **Reset statistics** — "Erases the totals, records and milestones kept for Timeline, then rebuilds them from the meetings and dictations still stored." A small pill tinted `color.recording`, "Reset Statistics".
  - A full-width line: "Statistics are numbers only: counts, lengths, word counts and estimated costs, plus which app each dictation went to. No text, titles or names of people. The word cloud keeps a separate count of the words in the meetings you still have. Both stay on this Mac and are never sent anywhere."
- The dialog is the existing `DSDialog`, its confirm button the accent fill: title "Reset statistics?", message "Totals, records and milestones are erased and rebuilt from what is still stored. Figures from deleted meetings and from dictations already pruned cannot be recovered.", confirm "Reset Statistics". The accepted mockup first drew this button red; it was corrected to the existing dialog after acceptance.
- History card: the first row's description becomes "0 days turns history off and keeps no dictation text. Maximum 30 days. Stored only on this Mac." A full-width line is added under Clear History: "Numbers about each dictation (time, app, length, word count) are kept for Timeline whatever this is set to, never the text. Reset statistics erases them."
- By phase: A ships the Reset row and the line without its third sentence and with "Both stay" as "They stay"; B adds the Typing speed row; C adds the third sentence.

**Menu.** `MenuItem.Action.timeline`; the row "Timeline…" after "Dictations…"; `StatusItemController` takes `onTimeline`, which calls `main?.show(.timeline)`.

### Design language

- **References.** The surfaces follow [DESIGN.md](../../DESIGN.md) (region `e198965`) and its specimen ([design/specimen.html](../../design/specimen.html), [artifact](https://claude.ai/artifact/WwtdFm3B6EEUxCKMZ3b4PB)).
- **Reused.** `PageColumn`, `Card`, `SettingRow`, `StepperPill`, the small pill button, `DSDialog`, `Chip` (Plain), `SegmentedPill`, `StatusLine`, `AppGlyph`, `FlowLayout`, the cloud-and-pulse mark, `RowList` hover.
- **Deltas, all `pending v11`:**
  - Components: Timeline panel, Stat figure, Heat grid, Bar chart, Split bar, Word cloud, Milestone strand, Stats block.
  - `type.score` also sets Timeline's lifetime totals; `type.title` also sets figures inside panels.
  - `type.cloud.small`, New York 400 at 13 px / 18 px, the smallest cloud words.
  - `radius.cell`, 2 px, for heat cells and bar tops.
  - Timeline motion, an exception to "motion lives in the overlay, the pulse bars and the level bars".
  - Do: chart series take `color.teal` (dictation), `color.accent` (meetings), `color.speaker.1` (summaries), `color.speaker.3` (naming), `color.text.tertiary` (unsplit).
  - Do: a heat cell shades from `color.hover` through three mixes of `color.accent` to `color.accent`.
- **Mapping to tokens.** Panels are `space.10` apart with `space.8` above each heading and `space.6` inside. Cloud sizes are `type.cloud.small`, `type.title.dialog`, `type.title` and `type.display`. The mockup's pixel values fall within 3 px of these steps; the steps are what ships. Chart heights (132 px bars, 44 px share bars, 26 px trend, 10 px year cells, 16 px rhythm cells) are layout local to the feature.
- **DS code.** `DS.Radius.cell`, `DS.TextStyle.cloudSmall`, and `DS.Colors.heat(_ level: Int)`, which blends `accent` into `hover` at 0, 25, 50, 75 and 100%.
- **Drift.** None touches these surfaces.

### Cross-project contract

Not applicable — the feature lives in this repository alone.

### Control flow

**Launch** (`AppDelegate.startNormal`), before `DictationController` is created:

1. Create `MeetingStore` (moved up from `:158`) and `StatsStore`.
2. If `needsSeed`: gather `history.entries()`, `config.usage` and every kept meeting's `meeting.json`; call `seed`. Otherwise `open`.
3. Wrap the `UsageStore` in `RecordedUsage` and hand that to both `Dependencies` and `MeetingDependencies`. `UsageStore` itself still serves `totals()`.
4. Create `WordCache` and `MeetingReconciler`; hand the reconciler to `MeetingDependencies.stats` and the store to `Dependencies.stats`.
5. After the window exists: start a utility-priority task running `reconcile()`, and a task that refreshes the sidebar summary for every element of `stats.changes`.

**Seed** (`StatsSeed`, pure), with `monthStart` the first local day of the current month:

1. Each history entry becomes a `delivered` row with `seeded: true`, its id, timestamp, bundle id, engine, streamed seconds, word count and cost; and a day line: `delivered` 1, `words`, `apps`, `hours`, plus `seconds` and `timed_words` when it has streamed seconds. If its day is before `monthStart` the line also carries `spend.dictation`.
2. Each day of the current month in `config.usage` becomes `spend.unsplit`: its cost, tokens and engine seconds, less the cost and engine seconds of kept test calls that ended that day, floored at zero.
3. Each kept, non-test meeting that started before `monthStart` adds to its start day `spend.meeting` (`billing.costUSD`, engine seconds under `engine.pricingKey`), `spend.summary` (current plus replaced summary cost, the current summary's tokens) and `spend.naming`.
4. `StatsStore.seed` deletes any `days.jsonl`, `dictations.jsonl` and `meetings.jsonl`, writes the seeded files, then writes `meta.json` last.

**Dictation.** `stopAndProcess` reads `clock.now` as `releasedAt` before spawning its task. `ProcessingJob.run` generates the id, calls a private `perform` that holds today's body unchanged and returns `(outcome, words, cost, wait)`, then records one attempt. `perform` uses the id for the `HistoryEntry` and measures `wait` when `paster.paste` returns. `StreamBilling.record` returns the cost it billed. The controller records the termini that never reach the job:

| Terminus | Outcome | Seconds | Cost |
|---|---|---|---|
| Capture error | `mic_error` | 0 | 0 |
| Device change | `device_changed` | recording length | discard's bill |
| Gate: under 0.5 s | `too_short` | recording length | discard's bill |
| Gate: quiet | `silent` | recording length | discard's bill |
| Profile error | `failed` | recording length | 0 |
| `abort` with a session | `aborted` | 0 | discard's bill |
| Job: stale at any checkpoint | `superseded` | recording length | streamed seconds' bill |
| Job: no key | `no_key` | recording length | streamed seconds' bill |
| Job: empty transcript | `empty` | recording length | streamed seconds' bill |
| Job: transcription or cleanup error | `failed` | recording length | 0 |
| Job: paste error | `failed` | recording length | the dictation's cost |
| Job: delivered | `delivered` | recording length | the dictation's cost |

`StatsStore.record(attempt)` stamps the time, appends the row, then appends one day line: for `delivered`, the counts above; otherwise `undelivered[outcome]` 1.

**Spend.** `RecordedUsage.add` calls `stats.record(spend:)` unless the purpose is `testCall`, then `base.add`, whose error it rethrows. `record(spend:)` appends one day line under the purpose. Purposes: `ProcessingJob` and `StreamBilling` state `dictation`; `MeetingBilling.finalUsage(purpose:)` and the controller's summary and naming adds state `meeting`, `summary` and `naming`, each replaced by `testCall` when `meeting.test != nil`.

**Meeting.** `start` stores `utcOffsetSeconds` from `deps.timeZone()`. While the state is `recording` and the meeting is not a test, `add` appends `max(0, meetingTime − segment.end)` to an in-memory sample list, once per provider segment. `stop` writes `timing.transcriptDelay` from the samples (median; 90th percentile by nearest rank) before `saveMeeting`, and after `setState(.stopped)` awaits `deps.stats.meetingStopped(id)`. `requestSummary` times the request on `deps.clock`; `adopt` stores the wait in `timing.summaryWaitSeconds`.

**Reconcile** (`MeetingReconciler.reconcile`, one pass at a time; callers during a pass await the same pass):

1. Read the index. Kept meetings are entries with no test tag and an end time.
2. A meeting needs its row when the row is missing, its `figures` is below `MeetingFigures.version`, or `modified(id)` is later than the row's `computed`.
3. For each: `load`, `MeetingFigures.compute`, `upsert`. `user_known`, the offset (falling back to the current time zone's offset at that instant) and the copied timing come from the loaded meeting.
4. Word counts (phase C): for each kept meeting of 60 s or more whose entry is missing or older than `modified(id)`, compute `WordTally` and `set` it; `remove` entries whose meeting is no longer kept.
5. Publish progress after each meeting; yield `nil` at the end.

`meetingStopped(id)` awaits a running pass, then applies steps 1 to 4 to that one meeting, so a test call or an unfinished meeting is skipped there too.

**Word tally.** The dominant language comes from `NLLanguageRecognizer` over the transcript. When `NLTagger` offers the lexical-class scheme for it: keep nouns, drop tokens tagged as a personal name, use the lemma when offered, lower-cased. Otherwise: every word of three or more letters that is not a number, lower-cased, with `nouns: false`. Topics are the words of the summary's `topics`, through the same filter, skipped for four-section summaries. **Cloud:** a term's weight is Σ over entries of its count, tripled where it is one of that entry's topics. Terms from `nouns: false` entries are dropped when they occur in half or more of those entries, and all such entries are ignored while there are fewer than five. Then any term matching a word of a speaker name in a kept meeting, a remembered person's name, or the user's name and aliases is dropped. The top 40 by weight are sized by rank (top 10%, next 20%, next 30%, rest) and ordered by the 64-bit FNV-1a hash of the term's UTF-8 bytes, so the order is the same on every launch.

**Timeline opens.** `MainWindowModel.entered(.timeline)` calls `timeline.reload(replay: !navigation.isReturning)`. `isReturning` is true only inside `MainNavigationModel.back()`. `reload`: build the report and show it; when `replay`, bump `playID`, which clears the page's set of played panels, its scroll anchor, and resets the year to the current one and both switches to Meetings; await `reconcile()`; if it changed anything, build the report again and show it without bumping `playID`. On a return the model still holds the anchor, the year and the switches, and the page restores the anchor through `scrollPosition(id:)`.

**A panel plays.** Each panel reports its frame in the scroll view's coordinate space. `PanelPlayback.shouldPlay` is true once 20% of the panel's height is inside the viewport. A panel not yet played draws its start state; on playing, its progress animates from 0 to 1: counts over 0.9 s ease-out, vertical bars over 0.6 s, horizontal bars and meters over 0.7 s, cells and words fading over 0.45 s, staggered by 18, 45 and 12 ms per item. Panels in view at opening start 80 ms apart. With Reduce Motion every panel counts as played.

**A record is clicked.** `timeline.open(record)` calls the same throwing `openMeeting` dependency the results page uses. `showMeeting` records `.timeline` as the origin. On a throw the model logs the reason and rebuilds the report, where the record now shows as deleted.

**"Change…" is clicked.** The model sets `settings.selection` to `.statistics` and navigates to Settings.

**Sidebar refresh.** On each element of `stats.changes`, on `MainWindowController.bringForward`, and when `apply(config)` sees a new typing speed: take a snapshot, compute `SidebarStats` off the main actor, assign it to `MainWindowModel`. The handle writes `timeline_sidebar_folded` through `ConfigStore.update`; the model flips at once and `apply(config)` confirms it.

**Meeting deleted.** `MeetingsListModel.Dependencies` gains `deleted: (UUID) async -> Void`, called after a successful whole-meeting delete; it calls `words.remove(id)`. The meeting's row stays.

**Reset.** The Settings dependency gathers a seed as at launch, then calls `stats.reset(seed)`, `words.clear()` and `reconcile()`. `reset` deletes the four files and seeds in one actor call, so no row can land between the two, and `since` becomes today.

### Failure and edge cases

| Case | Behaviour |
|---|---|
| A stats file cannot be written | Warning under `stats`; the in-memory state is still updated; the caller is not told |
| A line cannot be decoded | Skipped; one warning with the count per file per load; dropped at the next compaction |
| A file does not end in a newline | A newline is appended before the next write, so a torn line never joins the next |
| Crash between a dictation row and its day line | The day totals are one short. Accepted (§7) |
| Crash during seeding | `meta.json` is absent, so the next launch empties the directory and seeds again |
| `meta.json` unreadable | Rewritten; `since` from the earliest day row. The record is not reseeded |
| Meeting deleted in Finder | Its row stays; its word-count entry goes at the next reconcile |
| Meeting never finished (bug 2) | No row until it has an end time |
| Meeting under 60 s | Row written; excluded from counts, panels, the block and the word counts |
| In-room meeting, no speaker marked as the user | `user_known` false; left out of talk share |
| A meeting row's meeting was edited | Recomputed at the next reconcile; totals may move by the edit |
| Reconcile cannot load a meeting | Warning; that meeting is skipped; the pass continues |
| Timeline opened during the first reconcile | Panels show what the rows already give; the progress line shows from five meetings to read; the page redraws once at the end, without motion |
| Record clicked after its meeting was deleted | The open fails; the report is rebuilt; the record shows "Deleted meeting" |
| `config.usage` write fails | Spend is still recorded; the error reaches the caller as today |
| Local day or time zone changes | Day keys use the calendar at the moment of the event; nothing is rekeyed |
| Year with 54 week columns | Cell size is computed from the column width, so the grid always fits |
| Language without a tagger model | The frequency fallback; ignored until five such meetings exist |
| Reset during a recording | Allowed. The live meeting has no row yet; its spend so far returns in the month's unsplit seed |
| Sidebar too short | The block drops the trend, then hides; the handle hides with it |
| Typing speed changed | The Settings stepper writes through; the block refreshes; Timeline recomputes on its next open |

### Security

- **Trust boundary.** All inputs are the app's own files and the user's own speech, processed locally. Nothing in this feature opens a network connection.
- **At rest.** `stats/` is created 0700 and every file 0600, reapplied after each atomic rewrite, as `MeetingStore.write` does. `word-counts.json` is 0600. It holds words from transcripts; it sits beside the transcripts it derives from and adds no exposure beyond them.
- **No names or text in the record.** `MeetingFigures` and `StatsSeed` take only numbers and identifiers from their inputs. A test asserts that no string from a fixture's transcript, title or speaker names appears in any byte written under `stats/`.
- **Agents.** The CLI and MCP server hold `MeetingReading` only and gain no access to the record or the word counts.
- **Logs.** Counts, durations and error descriptions only. No word, title, name, bundle identifier or path below the config directory is logged.
- **Destructive action.** Reset asks first and names what cannot be recovered.
- **Untrusted content.** Transcript text reaches only `WordCount` and `WordTally`, which count it. Cloud words are drawn as plain `Text`.
- **Secrets.** None are read, written or logged.

### Performance

- **Recording.** An attempt costs two appends of under 300 bytes; a spend, one. Both run on the store's actor, off the paste path's critical section: the paste has already returned.
- **Memory.** The store holds all rows in memory. Budget: 20,000 dictation rows (13 months at 50 a day), one row a meeting, one a day; under 10 MB.
- **Snapshot and report.** A snapshot copies three arrays by reference. The report is one pass over each, computed off the main actor. Budget: under 50 ms at the sizes above.
- **Reconcile.** Stat calls only for unchanged meetings. A changed meeting costs one read of its `segments.jsonl`. The first pass over a large library is the heaviest work in the feature; it runs at utility priority and its budget is 10 s for 500 one-hour meetings, word tagging included. A synthetic benchmark of the same file shape informed these budgets; no figure from a real store appears here.
- **At stop.** A meeting's row and word counts are computed before its summary is requested: one transcript read and one tagging pass. Budget: under 200 ms for a one-hour meeting.
- **Word counts.** One rewrite of `word-counts.json` per changed meeting. Budget: 2 MB at 500 meetings.
- **People.** Each report reads every kept meeting's `meeting.json`, off the main actor. These are small files; no transcript is read.
- **Page.** Charts are shapes; the year grid is one `Canvas`, not 371 views. Frame preferences fire while scrolling and only flip a panel's played flag once.
- **Compaction.** `days.jsonl` is refolded at open and every 2,000 lines, keeping it at one line a day plus the current run's.

### Observability

A new `Log.stats` category, info level unless stated:

- `stats: seeded D dictations, N days, M meetings with cost` · `stats: opened, D dictations, N days, M meetings`
- `stats: pruned N dictation rows` · `stats: compacted <file>, N lines to M`
- `stats: reconcile, C computed, W word entries, R removed, T ms`
- `stats: reset`
- Warning: `stats: <file> not written: <reason>` · `stats: <file>: skipped N unreadable line(s)` · `stats: meeting <uuid> not reconciled: <reason>`

Nothing is alertable. The user-visible signs of a broken record are a block or panel that stops moving; Reset rebuilds from what is stored.

### Compatibility / migration

- **New files only.** No existing file changes shape. `config.usage` is written exactly as before.
- **`config.json`.** Two added keys. A build without them keeps them in `Config.extra` and writes them back.
- **`meeting.json`.** Two optional fields. Older builds ignore them on read and drop them on rewrite; Sparkle never downgrades.
- **`ProviderUsage`.** `purpose` is a required initialiser argument: a source change for every producer and test, none on disk.
- **Schema.** `meta.schema` and `word-counts.json`'s `schema` are 1. `MeetingRow.figures` lets a later build recompute kept meetings' rows; rows of deleted meetings keep their old shape, which is why every field is optional on read.
- **Across phases.** Rows written by phase A are read unchanged by B and C.
- **`python-legacy`.** Untouched. The Python app ignores `stats/`.

### Testing strategy

Swift Testing throughout. Core suites live in a new `MWStatsTests` target with fixtures under `Fixtures/`; every duration runs on `VirtualClock`, every date on an injected `now` and calendar.

| Component | Unit tests, each without the rest of the feature |
|---|---|
| `StatsTime` | Day keys and hours across a DST change and a time zone change; the offset round trip; the 13-month cutoff |
| `JSONLFile` | Append to a file without a final newline; skip a torn line; atomic rewrite keeps 0600 |
| `StatsStore` | Record then reopen equals the folded state; prune at open and on a new day; compaction thresholds; seed refuses nothing and empties first; reset; `changes` fires; a write failure leaves memory updated; exactly one row per attempt |
| `StatsSeed` | Each of the three steps; test-call subtraction floored at zero; a history entry before and after `monthStart`; no overlap between steps |
| `WordCount` | Spaced, unspaced and mixed scripts; empty text |
| `MeetingFigures` | Every field on a fixture meeting; edited segments; in-room without a user; no text, title or name in the encoded row |
| `MeetingReconciler` | Missing, stale and old-version rows recomputed; fresh ones not loaded; test and unfinished meetings skipped; a failed load skipped; single flight; progress; removal of word entries |
| `RecordedUsage` | Each purpose reaches the right day line; `testCall` reaches none; the base's error is rethrown after the spend is recorded |
| `WordTally`, `WordCloud` | Nouns kept and personal names dropped in English; the fallback path; topic weighting; the document-frequency drop; name exclusion; rank sizes; stable order |
| `TimelineStats` | Each panel at one below and at its threshold; each figure rule above on hand-built rows |
| `Milestones`, `Streaks` | Ladders, dating, a streak across a year end |
| `PeopleStats` | Grouping by person, by alias and by folded name; the user and default names excluded |
| `SidebarStats`, `StatFormat` | The 30-day window's edges; every format's boundaries |

Existing suites change: `ProcessingJobTests` and `DictationControllerTests` gain one case per terminus asserting exactly one attempt with its outcome, and a wait measured on `VirtualClock`; `MeetingControllerTests` assert the offset, the delay stats, the summary wait, `meetingStopped` and the purpose of each usage add; `UsageStoreTests` and the meeting billing tests state a purpose; `MWConfigTests` cover the two keys, their clamp and their round trip. `MWTestSupport` gains `FakeStatsRecorder`.

App suites (`AppTests`, `ManualClock`): `MainNavigationModelTests` gain `.timeline` in their destination list, the "Timeline" back label and `isReturning`; `MainWindowModelTests` cover reload with and without replay; `TimelineModelTests` cover states, the second report after a reconcile, a failed open; `PanelPlaybackTests` the 20% rule and Reduce Motion; `MenuModelTests` the new row's place; `SettingsModelTests` the section order, typing speed bounds and reset; `MeetingsListModelTests` the `deleted` hook; `DSTests` the heat steps and the two new tokens.

Acceptance, by hand on a beta: after phase A, dictate and record, then confirm rows appear under `stats/` and survive Clear History and a meeting delete; after B, compare the block and the page against the three accepted mockups in light and dark, at 900 × 600, with Reduce Motion on and off; after C, delete a meeting and confirm its words leave `word-counts.json`.

## 6. Alternatives considered

- **Swift Charts for the bar charts.** Rejected by the user: two drawing systems on one page, and styling bound to its defaults.
- **A 90-day file of single-request waits.** Rejected: the only such wait in scope is the summary's, which belongs to its meeting and is kept in `meeting.json`.
- **Rewriting `days.jsonl` whole on every event.** Rejected: the cost grows with the file for life, where an appended line does not.
- **Deriving pre-record spend from meeting rows on read.** Rejected: a summary regenerated later would be counted both in its old meeting's row and in its new day line.
- **A stats call at every meeting edit.** Rejected for one call at stop plus a reconcile on file dates: one mechanism covers the backfill, edits, late summaries and crashes, with no write point to miss.
- **Timings kept only in the record.** Rejected: stored in `meeting.json`, a row is a pure function of its folder and survives Reset.
- **Word counts in memory only.** My recommendation; the user chose a permanent file, updated when a meeting stops and at launch.
- **Word counts kept for life.** Rejected by the user: an entry leaves with its meeting.
- **Word cloud from a frequency filter alone, or from summary headings alone.** Rejected by the user for nouns with a fallback.
- **Counting test-call cost in spend.** Rejected by the user.
- **"Since" from the oldest data, an editable date, or the config folder's creation date.** Rejected by the user for the day the record starts.
- **Releasing 0.9.0 on v9 alone, or with the record only.** Rejected by the user: 0.9.0 waits for all of v11.
- **Sidebar block: Figures grid as drawn** ([figures-grid](./mockups/mockup-v11-sidebar-block.html#figures-grid), [artifact](https://claude.ai/artifact/6L1dfSCN1bUMK43HQiPSu2#figures-grid)). Its figures and type were kept; its header row gave way to the handle and it gained a third row.
- **Sidebar block: Headline and bars** ([headline-bars](./mockups/mockup-v11-sidebar-block.html#headline-bars), [artifact](https://claude.ai/artifact/6L1dfSCN1bUMK43HQiPSu2#headline-bars)). Only its fold handle was kept: too few numbers.
- **Sidebar block: Compact lines** ([compact-lines](./mockups/mockup-v11-sidebar-block.html#compact-lines), [artifact](https://claude.ai/artifact/6L1dfSCN1bUMK43HQiPSu2#compact-lines)). Not chosen.
- **Settings: in Dictations** ([in-dictations](./mockups/mockup-v11-settings-placement.html#in-dictations), [artifact](https://claude.ai/artifact/4MT6gNnJH7KqxZd31kRCVf#in-dictations)). Not chosen: Reset also erases meeting figures.
- **Settings: in General** ([in-general](./mockups/mockup-v11-settings-placement.html#in-general), [artifact](https://claude.ai/artifact/4MT6gNnJH7KqxZd31kRCVf#in-general)). Not chosen: a full scroll down the longest page.
- **One module for the whole feature in the app target.** Rejected: the rules would be testable only through `xcodebuild`.
- **Settings sidebar: the sections scroll** ([scrolling-sections](./mockups/mockup-v11-settings-overflow.html#scrolling-sections)). Not chosen: the last sections would sit below a fade at the minimum height.
- **Settings sidebar: a taller minimum window** ([taller-minimum](./mockups/mockup-v11-settings-overflow.html#taller-minimum)), 660 instead of 600 pt. Not chosen: every page would lose 60 pt of the smallest window.

## 7. Risks and issues

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| The page opens thin: no dictation or timing panels for weeks | Certain / low | Phase A ships first so history accrues before the page; panels appear at thresholds; the sub line says when tracking began |
| A missed or doubled write corrupts totals that cannot be rebuilt | Low / high | Spend rides on `UsageRecording`, whose producers must state a purpose to compile; one recording point in the job; a parameterised test per terminus; the seed runs before any producer exists |
| A crash between a dictation row and its day line | Very low / low | Accepted: one dictation short in day totals. The two appends are adjacent on one actor |
| File dates mislead the reconcile (restore from backup, clock change) | Low / low | A needless recompute is harmless; a missed one is corrected by bumping `MeetingFigures.version` |
| Talk share and People are only as good as attribution | Medium / medium | In-room meetings without a marked user are left out; the caption says what is counted. Known issue: a remote label can be bound to the user after a few words, which inflates the user's share; not fixed here |
| `word-counts.json` puts words from private meetings in a second file | Certain / low | 0600, beside the transcripts; an entry leaves with its meeting; Reset clears it; the Settings line says it exists |
| Word tagging depends on language models the Mac has installed | Medium / low | The fallback needs five meetings and drops common words; the cloud needs 30 terms to show |
| An estimate read as an invoice | Medium / low | The Estimate chip on Spend, "Estimated spend" in the totals, "Costs are estimates" under the title |
| The first month's spend is unsplit, and its test-call cost is removed only for test calls still kept | Certain / low | Shown as its own "Not split" series with a caption in that state |
| Backfilled meetings assume today's time zone | Medium / low | Affects rhythm and day keys of old meetings only; live meetings store their offset |
| The sidebar block leaves 20 px at the minimum height | Low / medium | `ViewThatFits` drops the trend, then the block |
| Motion looks out of place beside static pages | Low / low | Once per opening, under a second, off with Reduce Motion; recorded as an exception |
| Size: the largest feature since the unified window | High / medium | Three phases, each a shippable beta; core rules in one module with pure components |
| Reset is final for deleted meetings and pruned dictations | Certain / medium | The dialog says so before erasing |
| 0.9.0, and with it v9, waits for all of v11 | Certain / medium | The user's decision; beta users get each phase as it lands |
| Known issue: streamed seconds are not billed when batch transcription fails (`ProcessingJob.swift:85`) | Existing / low | Such an attempt is recorded as `failed` with cost 0, matching what was billed. Not fixed here |
| Known issue: a profile error leaves the streaming engine unfinished (`DictationController.swift:227`) | Existing / low | Recorded as `failed` with cost 0. Not fixed here |
| Known issue: a force-quit meeting is never recovered (bug 2) | Existing / low | It has no row until it gains an end time; the reconcile then picks it up |

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

One plan, built in this order on `main`, each phase cut as a 0.9.0 beta. Release users stay on 0.8.2 until 0.9.0.

1. **Phase A, the record.** `MWStats` (rows, store, seed, figures, reconciler without word counts, `RecordedUsage`), the capture changes in both pipelines, `MeetingStore`'s two reads, `Log.stats`, Settings › Statistics with Reset and its line, the History row. Cut as the next beta, 0.9.0b4. CHANGELOG, under Added: the numbers-only record, what it holds, where, and Reset.
2. **Phase B, the block and the page.** The two config keys, `SidebarStats` and the block, navigation, ⌘3, the menu row, `TimelineStats` and panels 1–5, 7, 8 and 10, the empty and progress states, motion, the Typing speed row, the DS additions. Cut as a beta.
3. **Phase C, People, Words, Quality.** `PeopleStats`, `WordTally`, `WordCache`, `WordCloud`, the reconciler's word step, the delete hook, panels 6, 9 and 11, the third sentence of the Settings line, the README. Cut as a beta.
4. **0.9.0.** Released once phase C has been used on the beta channel and v9 has proven itself. Its CHANGELOG section lists everything since 0.8.2.

- **After each phase:** run `/design-language-update` so the `pending v11` entries that now match code become active.
- **Rollback.** Before 0.9.0: remove the bad beta's item from `appcast.xml` or ship the next beta. The record needs no undo: a build without the feature ignores `stats/` and `word-counts.json`. A record that went wrong is repaired by Reset statistics, or by deleting `stats/`, which a later launch reseeds.
- **No flag.** The record is on for every beta user from phase A. Its control is Reset; there is no switch to stop recording.
- **Communication.** Each beta's CHANGELOG section says what was added. The 0.9.0 notes state that Timeline begins on the day of the update, that meetings already stored are counted, and that everything stays on the Mac.

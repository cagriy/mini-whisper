# Meeting transcripts — Implementation Plan v4

**Status:** Draft
**Date:** 2026-11-09
**Design:** [feature-design-v4-Meeting-transcripts.md](./feature-design-v4-Meeting-transcripts.md)

## Overview

Meeting mode: a third hotkey and menu items open a chooser between a remote call (microphone plus
a Core Audio process tap of system audio, mixed into one diarized provider session) and an in-room
meeting (microphone only). A live window shows the speaker-labelled transcript, notes, elapsed
time and cost. Stop bills the meeting, stores it under `~/.config/mini-whisper/meetings/` and asks
Claude Sonnet 5.5 for a summary. A Meetings window lists, searches and exports meetings, and a
read-only CLI and stdio MCP server serve the same Markdown.

The plan has 28 stages and lands bottom-up along the module graph, following design §9's order:

1. Config, keys, pricing and the Anthropic client (Stages 1–3).
2. Streaming extensions (Stages 4–7).
3. Audio (Stages 8–10).
4. The new `MWMeetings` store and Markdown (Stages 11–12).
5. The `MWMeetingPipeline` components and controller (Stages 13–18).
6. `MWAgentAccess` and the app's CLI entry (Stages 19–21).
7. The app's hotkey, windows and Settings (Stages 22–27).
8. README and CHANGELOG (Stage 28).

After every stage, `swift test` and `xcodebuild … test` stay green and the app builds. Meeting
mode stays unreachable from the UI until Stage 24 wires the hotkey and menu. That is the design's
"no feature flag" rollout: nothing user-visible changes until the surface is complete enough to
use.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Some stages fit a sanctioned non-red-first category instead. Each is labelled with its category
and a one-line justification:

- non-TDD (scaffolding | config-only | integration-verified);
- behaviour-preserving refactor/deletion;
- characterization/guard tests;
- platform-only/UI wiring;
- external prerequisite (gated).

A **hybrid** stage runs full TDD for its host-testable core. Its *integration-verified remainder*
names the concrete command or manual check.

**Swift's compiled first red.** A stage that introduces a brand-new type, case or module cannot
reach a red *assertion* first, because the test target fails to build. That build failure is the
legitimate first red, for example:

- `error: cannot find '<Type>' in scope`
- `error: type '<Enum>' has no member '<case>'`
- `error: no such module '<Module>'`

The stage then scaffolds the minimal empty API. It re-runs to confirm red as *assertion* failures
(`✘ Test <name>() recorded an issue … Expectation failed`) and only then implements.

**Runners and registration.**

| Layer | Command |
|---|---|
| Core package tests | `cd Packages/MiniWhisperCore && swift test` |
| One core suite | `cd Packages/MiniWhisperCore && swift test --filter <Target>Tests` |
| Core build only | `cd Packages/MiniWhisperCore && swift build` |
| App tests (and build) | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` |
| App build only | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd build` |
| Opt-in integration | `cd Packages/MiniWhisperCore && MW_INTEGRATION=1 swift test --filter <Suite>` (plus provider keys in the environment where the suite needs one) |

- **Framework.** Swift Testing throughout (`@Suite struct`, `@Test func`, `#expect`, `#require`).
  No XCTest.
- **Core registration.** Core sources and tests are directory-discovered inside an existing target.
  A new **target**, **product**, **dependency edge** or **resource directory** needs a
  `Packages/MiniWhisperCore/Package.swift` edit. Stages 11, 13 and 19 add targets.
  - A declared `resources: [.copy("Fixtures")]` directory must exist. Stage 11 seeds
    `MWMeetingsTests/Fixtures/` when it declares it.
- **App linkage.** The app links core products **explicitly** in `project.yml` (one
  `- package: MiniWhisperCore` / `product:` pair each). The first stage whose `App/` code imports a
  new product adds it there:
  - `MWMeetings` and `MWAgentAccess` in Stage 21;
  - `MWMeetingPipeline` in Stage 23.
- **App sources.** `App/` and `AppTests/` are folder-sourced by xcodegen. Every stage that adds a
  file there re-runs `xcodegen generate` before `xcodebuild`, or the file silently never compiles.
  AppTests do not link `MWTestSupport`; app-side stubs live in `AppTests/` (as `StubApps.swift`
  does today).
- **Reading results.** Swift Testing output is preceded by an XCTest line `Executed 0 tests, with 0
  failures`. Read the `✔/✘ Test run with N tests in M suites …` line instead.
- **Durations.** Every duration test runs on `VirtualClock` (`advance(by:)`, `waitUntilSleeping`).
  A real sleep in a unit test is a defect.

**Observed baseline, run 2026-11-09 before drafting — core is RED:**

| Command | Result |
|---|---|
| `swift build` | `Build complete!`, exit 0 |
| `swift test` | 12 of 13 test targets pass, **506 tests**. **`MWHistoryTests` crashes**: `retentionChangeFromZeroReenablesWrites` fails at `HistoryStoreTests.swift:227-228`, then `Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range` (signal 5). Reproduced 3 of 3 runs. |
| `xcodebuild … test` | `✔ Test run with 127 tests in 20 suites passed` + `** TEST SUCCEEDED **` |

The `MWHistoryTests` crash is a date time-bomb in the test file, not in product code:

- `entry()` defaults to timestamp `2026-09-01T17:38:02Z`;
- the store uses `now: { Date() }` with 7-day retention;
- so the fixture entries are now pruned on write.

It is out of scope for this feature. `/feature-implement` halts on a red baseline, so it must be
fixed first (`/bug-submit` then `/bug-fix`), before Stage 1. After that fix, "no regressions" in
every stage means:

- the core suite passes in full, with at least the 506 + MWHistoryTests tests it has today;
- the app suite passes with at least 127 tests.

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: `BindingName.meeting` / `meeting_hotkey` toggles chooser / stop; menu items per state | Stage 1 (key), Stage 22 (binding, capture), Stage 24 (toggle, Start/Stop/Show menu), Stage 26 (*Meetings…*) |
| R2: chooser cards, per-hour price, 14.2 gate, first-remote System Audio note | Stage 2 (`Pricing.perHour`), Stage 7 (`PlatformInfo.supportsSystemAudio`), Stage 17 (explained flag), Stage 23 (chooser model), Stage 24 (chooser view) |
| R3: remote = mic + tap mixed into one session, mic-overlap → user; in-room = mic only | Stage 13 (gate, mixer), Stage 14 (attributor), Stage 17 (tick paths) |
| R4: `meeting_engine` four tiers, first-with-key fallback, Start disabled without key, English only | Stage 1 (`MeetingEngine.resolve`), Stage 7 (`makeMeeting`), Stage 23 (Start gating), Stage 27 (Settings rows) |
| R5: `EngineName.assemblyai` dictation engine | Stage 6 |
| R6: `KeyAccount.assemblyai/.anthropic`, Keys rows, `sk-ant-` check | Stage 1 |
| R7: merged speaker paragraphs, grey partial, rename popover applies to all | Stage 18 (rename/merge), Stage 23 (merge + partial model), Stage 24 (popover) |
| R8: notes stamped at first keystroke, inline / pane / exports / summariser input | Stage 12 (exports), Stage 16 (summariser input), Stage 18 (`addNote`), Stage 23 (inline + pane model), Stage 24 (Enter / Shift+Enter) |
| R9: pause closes session, silence padding, Paused marker, sleep auto-pause | Stage 8 (sleep event while held), Stage 16 (silence padding), Stage 18 (pause/resume/sleep), Stage 23 (marker text), Stage 24 (buttons) |
| R10: reconnect with backoff, gap marker, AssemblyAI / Speechmatics rollover | Stage 4 (close codes, session-limit seam), Stage 5 (`session_timeout`), Stage 6 (`expires_at`), Stage 15 (supervisor), Stage 17 (gap persisted), Stage 23 (gap text) |
| R11: fresh labels after reconnect, `SpeakerRevision` re-map, pinned reassignment wins | Stage 6 (revision parsing), Stage 14 (registry), Stage 15 (session index), Stage 18 (revisions, pinned) |
| R12: Stop shows transcript, bills, writes, summarises; summary panel states | Stage 3 (client), Stage 16 (summariser), Stage 17 (stop flow), Stage 25 (panel) |
| R13: edit paragraph and reassign segment after Stop, persisted | Stage 18 (controller), Stage 25 (UI) |
| R14: meeting folder layout, 0700/0600, AAC 16 kHz mono, never auto-deleted | Stage 9 (AAC writer), Stage 11 (store), Stage 16 (recorder), Stage 17 (keep-audio) |
| R15: default title from front app, renamable in window and list | Stage 12 (`MeetingTitle`), Stage 17 (title at start), Stage 18 (`retitle`), Stage 25 (window header), Stage 26 (list) |
| R16: Meetings window rows, hover actions, footer, search snippets, empty state | Stage 12 (`MeetingSearch`), Stage 26 |
| R17: two Markdown exports, sanitised names, Export both, summary refusal | Stage 12 (Markdown, `TitleSanitizer`), Stage 25 (exporter, window), Stage 26 (list menu) |
| R18: live estimate, Stop billing, summary tokens, new pricing keys | Stage 2 (rates), Stage 16 (`MeetingBilling`), Stage 17 (billing on Stop and after summary) |
| R19: dictation hotkeys locked during a meeting with overlay notice | Stage 18 (`isActive`), Stage 24 (routing) |
| R20: Settings → Meetings section contents | Stage 1 (summary prompt file + restore), Stage 21 (installer), Stage 27 |
| R21: `meetings list/transcript/summary/search`, `mcp` server, read-only | Stage 11 (`MeetingReading`), Stage 19 (CLI), Stage 20 (MCP), Stage 21 (`AgentCommand`, `main.swift`) |
| R22: *Install…* writes a wrapper script via admin `osascript`, never a symlink | Stage 21 (installer), Stage 27 (row) |
| R23: README and CHANGELOG | Stage 28 |
| R24: no new dependency, core dependency-free, Swift 6, macOS 14 with `@available(macOS 14.2, *)` tap | Stage 10 (tap guard), Stage 11, Stage 13, Stage 19 (new targets with no third-party edge); held by every stage |
| R25: every duration on `VirtualClock`; wire shapes on fixtures; no network | Stage 3, Stage 5, Stage 6, Stage 13, Stage 15, Stage 17, Stage 18, Stage 26 |
| R26: ≤ ~2 s audio in memory, segments stream to disk, view model scales to 20 000 segments | Stage 8 (listener never accumulates), Stage 11 (appends), Stage 13 (2 s ring), Stage 23 (incremental merge) |
| R27: no secret on disk / log / fixture / comment; Anthropic logs sizes and status only | Stage 1, Stage 3, Stage 6, Stage 15 (close codes only) |
| R28: `config.json` round-trips the five new optional keys | Stage 1 |

## Stages

### Phase A — Foundations

### Stage 1 — Meeting config keys, `MeetingEngine`, two Keychain accounts, the summary prompt file

**Goal:** `MWConfig` knows the five `meeting_*` keys, the four meeting engine tiers, the
AssemblyAI and Anthropic Keychain accounts and the summary prompt file. Settings → Keys shows and
validates the two new keys.

**Category:** Hybrid.
- TDD for the config, enum, account and prompt-file behaviour.
- **Non-TDD (config-only)** for the `Log.meeting` category, the bundled prompt text and the
  `AppDelegate` construction-site edit: none of these is host-assertable beyond compiling.

**Design references:** §3 R4, R6, R20, R27, R28; §5.1 (`MWConfig`, `MWSupport` rows); §5.2 (Config,
`MeetingEngine`, Keychain, Prompt file); §5.5; §5.11.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWConfig/MeetingEngine.swift`
- create `Packages/MiniWhisperCore/Sources/MWConfig/SummaryPromptProviding.swift`
- edit `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`
- edit `Packages/MiniWhisperCore/Sources/MWConfig/SecretStore.swift`
- edit `Packages/MiniWhisperCore/Sources/MWConfig/PromptFiles.swift`
- edit `Packages/MiniWhisperCore/Sources/MWConfig/KeychainStore.swift` (doc comment's account count)
- edit `Packages/MiniWhisperCore/Sources/MWSupport/Log.swift`
- create `Packages/MiniWhisperCore/Tests/MWConfigTests/MeetingEngineTests.swift`
- edit `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`
- edit `Packages/MiniWhisperCore/Tests/MWConfigTests/PromptFilesTests.swift`
- edit `Packages/MiniWhisperCore/Tests/MWConfigTests/KeychainStoreTests.swift`
- create `App/Resources/default_summary_prompt.txt`
- edit `App/AppDelegate.swift` (the `PromptFiles(…)` construction)
- edit `App/Settings/KeysSection.swift`
- edit `App/Settings/SettingsModel.swift` (`saveKey`)
- edit `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write test: `MeetingEngineTests.swift` (new suite `MeetingEngineTests`):
   - `fourTiersWithDesignRawValues`: raw values are `speechmatics_standard`,
     `speechmatics_enhanced`, `assemblyai_streaming`, `assemblyai_pro`, in that order.
   - `keyAccountsPricingKeysAndDiarizationKeys`: `pricingKey` and `diarizationPricingKey` per tier,
     as listed in design §5.2.
   - `titlesAndProviderModels`: "Speechmatics Standard" … ; `standard`, `enhanced`,
     `universal-streaming-english`, `universal-3-6-pro`.
   - `resolveKeepsTheStoredTierWhenItsKeyExists`.
   - `resolveFallsBackToTheFirstTierWithAKey`: covers both an absent and a keyless stored value.
   - `resolveIsNilWithoutAnyKey`.

   Expected initial failure: `error: cannot find 'MeetingEngine' in scope`.
2. Write test, extending `ConfigCodingTests`:
   - `meetingKeysAbsentTakeDefaults`: `meetingHotkey == "ctrl+alt+cmd+m"`,
     `meetingKeepAudio == true`, `meetingSystemAudioExplained == false`, `meetingEngine == nil`,
     `meetingUserName == nil`.
   - `meetingKeysRoundTrip`.
   - `unrecognisedMeetingEngineIsIgnoredButPreserved`: the same pattern as
     `unrecognisedStreamingEngineIsIgnoredButPreserved`.
   - `meetingKeysNeverLandInExtra`.
   - `optionalMeetingKeysAreOmittedWhenUnset`: no `meeting_engine` or `meeting_user_name` in
     `Config().encoded()`. The three defaulted keys are written.

   Expected initial failure: `error: value of type 'Config' has no member 'meetingHotkey'`.
3. Write test, extending `KeychainStoreTests` with `keyAccountRawValuesMatchTheKeychainItems`:
   `KeyAccount.allCases.map(\.rawValue)` ends with `assemblyai-api-key`, `anthropic-api-key`.
   Expected initial failure: `error: type 'KeyAccount' has no member 'assemblyai'`.
4. Write test, extending `PromptFilesTests`:
   - `seedsSummaryPromptFromTheBundledDefault`;
   - `writeSummaryPromptReplacesContent`;
   - `restoreDefaultSummaryPromptOverwritesAnEdit`;
   - `promptFilesIsASummaryPromptProvider`: `let _: any SummaryPromptProviding = files`.

   Expected initial failure: `error: extra argument 'bundledSummary' in call`.
5. Run `swift test --filter MWConfigTests`. Confirm the four build failures.
6. Implement `MeetingEngine.swift`:
   - `public enum MeetingEngine: String, Codable, CaseIterable, Sendable` with the four cases.
   - Properties `keyAccount`, `pricingKey`, `diarizationPricingKey`, `title`, `providerModel`.
   - `public static func resolve(stored: MeetingEngine?, hasKey: (KeyAccount) -> Bool) -> MeetingEngine?`.
7. Implement `SecretStore.swift`: add `case assemblyai = "assemblyai-api-key"` and
   `case anthropic = "anthropic-api-key"`. Update the doc comment ("five accounts").
8. Implement `Config.swift`:
   - Add `meetingHotkey`, `meetingEngine` (with `unrecognisedMeetingEngine` preservation, mirroring
     `streamingEngine`), `meetingKeepAudio`, `meetingUserName` and `meetingSystemAudioExplained`.
   - Add the five `Key` constants to `Key.all`.
   - Encode the three defaulted keys always, and the two optional keys only when set.
9. Implement `SummaryPromptProviding.swift`: `public protocol SummaryPromptProviding: Sendable { func summaryPrompt() throws -> String }`.
   Then edit `PromptFiles.swift`:
   - add `init(…, bundledSummary: URL? = nil)`;
   - add `summaryPromptURL`, `summaryPrompt()`, `write(summaryPrompt:)` and
     `restoreDefaultSummaryPrompt()`, seeding
     `summary_prompt.txt` exactly as `prompt.txt` is seeded;
   - conform `PromptFiles` to `SummaryPromptProviding`.
10. Run `swift test`. Confirm pass and no regressions.
11. Write test, extending `AppTests/SettingsModelTests.swift`:
    - `anthropicKeyMustStartWithSkAnt`: `saveKey(.anthropic, value: "sk-abc")` sets
      `error(for: .anthropic) == "Invalid key — must start with 'sk-ant-'."` and stores nothing.
      `"sk-ant-abc"` is stored.
    - `assemblyAIKeyAcceptsAnyNonEmptyValue`.

    Run `xcodebuild … test`. Expected failure:
    `✘ Test anthropicKeyMustStartWithSkAnt() recorded an issue … Expectation failed: (harness.secrets…) == nil`.
12. Implement the app side:
    - `SettingsModel.saveKey` adds the `.anthropic` prefix rule beside the `.openai` one.
    - `KeysSection.rows` gains `(.assemblyai, "AssemblyAI")` and `(.anthropic, "Anthropic")`.
13. Non-TDD (config-only):
    - Create `App/Resources/default_summary_prompt.txt` with design §5.5's text verbatim.
    - `AppDelegate`'s `PromptFiles(…)` passes `bundledSummary: Self.bundledPrompt("default_summary_prompt")`.
    - `Log.swift` gains `public static let meeting = LogCategory(name: "meeting")`
      beside the six existing categories.
14. Run `xcodegen generate && xcodebuild … test`. Confirm pass. Run `swift test`. Confirm no
    regressions.

**Definition of done:**
- Five optional `meeting_*` keys round-trip. An unknown `meeting_engine` is preserved verbatim
  (R28).
- `MeetingEngine.resolve` implements R4's fallback.
- `KeyAccount` has five accounts. Keys shows AssemblyAI and Anthropic rows, and Anthropic rejects a
  non-`sk-ant-` value.
- `summary_prompt.txt` seeds from the bundle and can be restored.
- `Log.meeting` exists.
- Both suites are green.

**Risks specific to this stage:** `KeysSection`'s drafts dictionary iterates `KeyAccount.allCases`
(`KeysSection.swift:56`), so the two rows appear only once `rows` lists them. Both edits land
together.

### Stage 2 — Meeting pricing keys and the Speechmatics price correction

**Goal:** `Pricing` carries the five new per-minute keys, the two Sonnet 5.5 token rates, the
corrected Speechmatics rate 0.0075, `meetingCost` and the per-hour figure the chooser and
Settings show.

**Category:** TDD.

**Design references:** §3 R2, R18; §5.2 (Pricing); §5.3 (`MeetingBilling`, `Pricing.meetingCost`);
§5.11.

**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWUsage/Pricing.swift`
- edit `Packages/MiniWhisperCore/Tests/MWUsageTests/PricingTests.swift`

**Steps (TDD):**
1. Write test in `PricingTests`:
   - Change the `speechmatics` row of the argument table at `:20` and the expectation at `:94`
     (`overrideLeavesOthers`) to `0.0075`.
   - Add `meetingRatesPerMinute` (arguments: `speechmatics_enhanced` 0.013333, `assemblyai` 0.0025,
     `assemblyai_pro` 0.0075, `assemblyai_diarization` 0.002).
   - Add `sonnetRatesPerMTok` (`claude-sonnet-5-5_in` 2.00, `_out` 10.00).
   - Add `meetingCostSpeechmaticsStandardOneHourIs45Cents`.
   - Add `meetingCostAssemblyAIAddsDiarization`: 3600 s streaming is 0.15 + 0.12.
   - Add `meetingCostIncludesSummaryTokens`: 1 M in + 100 k out is 2.00 + 1.00.
   - Add `meetingCostHonoursOverridesOfEveryNewKey`.
   - Add `perHourMatchesTheChooserLabels`: `Pricing.perHour(.speechmaticsStandard, overrides: [:]) == 0.45`;
     enhanced 0.80; AssemblyAI streaming 0.27; pro 0.57.

   Expected initial failure: `error: type 'Pricing' has no member 'meetingCost'`.
2. Run `swift test --filter MWUsageTests`. Confirm the build failure. After stubbing
   `meetingCost`/`perHour` to return 0, confirm assertion failures, including
   `Expectation failed: close(cost, 0.0075)`.
3. Implement in `Pricing.swift`:
   - the `perMinute` and `perMTok` additions and the 0.0075 correction;
   - `public static func meetingCost(engine: MeetingEngine, seconds: Double, tokens: TokenUsage, overrides: [String: Double]) -> Double`,
     which is seconds/60 × (rate(pricingKey) + rate(diarizationKey)) + tokens at the Sonnet rates;
   - `public static func perHour(_ engine: MeetingEngine, overrides: [String: Double]) -> Double`.
4. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- Every new key is overridable.
- Speechmatics bills 0.0075.
- `meetingCost` and `perHour` return design §5.3's figures.
- Suite green.

**Risks specific to this stage:** Changing the 0.0067 constant raises the cost of new
Speechmatics dictations. Past `DayEntry.costUSD` values are stored at write time and do not
change. See *Planning decisions taken* #1.

### Stage 3 — `AnthropicClient`, `Summarizing` and `SummaryResult`

**Goal:** One Messages API call with design §5.3's request shape, text-block joining, refusal
category and `APIError` mapping, tested against `FakeHTTPTransport`.

**Category:** TDD, plus an opt-in **integration-verified** live call.

**Design references:** §3 R12, R25, R27; §5.3 (`MWTranscription`, `Summariser` parameters);
§5.8; §5.10.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWTranscription/AnthropicClient.swift`
  (`Summarizing`, `SummaryResult`, `AnthropicClient`)
- create `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeSummarizer.swift`
- create `Packages/MiniWhisperCore/Tests/MWTranscriptionTests/AnthropicClientTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWTranscriptionTests/AnthropicIntegrationTests.swift`

**Steps (TDD):**
1. Write test: `AnthropicClientTests`:
   - `postsToMessagesWithHeaders`: `https://api.anthropic.com/v1/messages`, `x-api-key`,
     `anthropic-version: 2026-10-21`, `anthropic-beta: server-side-fallback-2026-07-01`,
     `content-type: application/json`.
   - `bodyCarriesModelMaxTokensEffortAndFallbacks`: `model: "claude-sonnet-5-5"`,
     `max_tokens: 16000`, `output_config.effort: "low"`, `fallbacks: "default"`, `system`, and one
     `user` message. The body has no `temperature`, `top_p` or `top_k`.
   - `timeoutIs180Seconds`: `transport.calls[0].timeout == .seconds(180)`.
   - `joinsTextBlocksAndReadsUsage`.
   - `refusalCarriesTheCategory`: `stop_reason: "refusal"` with `stop_details.category: "cyber"`
     gives `refusalCategory == "cyber"`.
   - `non2xxMapsToHTTPStatus`.
   - `transportFailureMapsToTransport`.
   - `logsSizesAndStatusOnly`: with `CapturingLogSink`, no captured line contains the key or the
     user text, and one line carries the byte count and status.

   Expected initial failure: `error: cannot find 'AnthropicClient' in scope`.
2. Run `swift test --filter MWTranscriptionTests`. Confirm the build failure. Then scaffold an
   `AnthropicClient` that throws, and confirm assertion failures.
3. Implement `AnthropicClient.swift`:
   - `Summarizing`, `SummaryResult` and `AnthropicClient(apiKey:transport:)` as design §5.3
     specifies.
   - The request is built with `JSONSerialization` from typed values.
   - Log via `Log.meeting`: request bytes, status, input/output tokens.
   - No retry.
4. Implement `FakeSummarizer` (records `system`/`user`, returns a stubbed result or throws).
5. Write `AnthropicIntegrationTests.summarisesAFixtureTranscript`:
   - enabled only when `MW_INTEGRATION == "1"` and `ANTHROPIC_API_KEY` is set;
   - it asserts non-empty text containing `## Summary`.
6. Run `swift test`. Confirm pass and no regressions; the integration test is skipped.

**Definition of done:**
- Request shape, timeout, refusal and error mapping are all covered.
- No key or transcript text reaches a log.
- `FakeSummarizer` is available to later stages.

**Risks specific to this stage:** None.

### Phase B — Streaming

### Stage 4 — The streaming seam: segments, speaker revisions, session limits, close codes, minimum chunk

**Goal:** Adapters can emit `.segment`, `.speakerRevision` and `.sessionLimit`.
- `WebSocketEngine` routes the three new emissions to the sink only, leaving the assembler's text
  untouched.
- A server close surfaces its code through `onEngineError`.
- An adapter can require a minimum chunk duration.

**Category:** TDD.

**Design references:** §3 R10, R11, R25; §5.1 (`MWStreaming` row); §5.3 (`MWStreaming`); §5.7
(provider close rows); §5.11. Also *Planning decisions taken* #5, #6, #7, #8.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWStreaming/TranscriptSegment.swift`
  (`TranscriptWord`, `TranscriptSegment`, `SpeakerRevision`, `SessionLimit`)
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/EngineAdapter.swift`
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/TranscriptSink.swift`
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/WebSocketEngine.swift`
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/WebSocketConnection.swift`
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/URLSessionWebSocketConnection.swift`
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/RecordingSink.swift`
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/TestAdapter.swift`
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/FixtureScript.swift` (`Step.serverClose`)
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeWebSocketConnection.swift`
- edit `Packages/MiniWhisperCore/Tests/MWStreamingTests/WebSocketEngineTests.swift`

**Steps (TDD):**
1. Write test, extending `WebSocketEngineTests`. Server messages are scripted through
   `TestAdapter`'s new event types `segment`, `revision` and `limit`.
   - `segmentReachesTheSinkButNotTheAssembler`: a `final "a b"` then a `segment "a b"` give
     `finish().text == "a b"`, `sink.finals == ["a b"]` and `sink.segments.count == 1`.
   - `speakerRevisionReachesTheSink`.
   - `sessionLimitReachesTheSink`.
   - `serverCloseSurfacesItsCode`: a new `FixtureScript.Step.serverClose(code: 4005, reason:
     "quota")` (JSON key `server_close`) makes the fake connection's `receive` throw
     `WebSocketConnectionError.closed(code: 4005, reason: "quota")`, so `sink.errors` has one error
     whose description contains `4005`.
   - `accumulatesToTheAdaptersMinimumChunk`: with `TestAdapter(minimumChunkSeconds: 0.1)`, feeding
     five 20 ms buffers sends one binary message of 3200 bytes.
   - `flushesTheRemainderBeforeEnd`.
   - `noMinimumChunkKeepsOneMessagePerBuffer`: a guard on today's behaviour.

   Expected initial failure: `error: cannot find 'TranscriptSegment' in scope`.
2. Write test: `URLSessionWebSocketConnectionTests.closeErrorCarriesCodeAndReason` (new file
   `Tests/MWStreamingTests/URLSessionWebSocketConnectionTests.swift`), driven through the pure
   `static func closeError(code: Int, reason: Data?) -> WebSocketConnectionError?`. The `.invalid`
   (0) code gives `nil`. Expected initial failure:
   `error: type 'URLSessionWebSocketConnection' has no member 'closeError'`.
3. Run `swift test --filter MWStreamingTests`. Confirm the build failures.
4. Implement `TranscriptSegment.swift`:
   - Value types per design §5.3.
   - `public enum SessionLimit: Sendable, Equatable { case expiresAt(Date), warning }`.
5. Implement `EngineAdapter.swift`:
   - `Emission` gains `.segment`, `.speakerRevision` and `.sessionLimit`.
   - `AdapterEmitter` gains `segment(_:)`, `speakerRevision(_:)` and `sessionLimit(_:)`.
   - `EngineAdapter` gains the protocol requirement `var minimumChunkSeconds: Double? { get }`.
     A protocol extension supplies the `nil` default. It must be a requirement, not an
     extension-only member, so the generic `WebSocketEngine<Adapter>` dispatches to an adapter's
     own value.
6. Implement `TranscriptSink.swift`:
   - Add `onSegment`, `onSpeakerRevision` and `onSessionLimit`.
   - The default no-op bodies go in a protocol extension, so `StreamSink` and every existing sink
     compile unchanged.
7. Implement `WebSocketEngine.swift`:
   - At the assembler switch (`:287-288`) the three new cases `break`.
   - At the sink switch (`:295-296`) they call the matching sink method.
   - The chunk path accumulates converted samples until `minimumChunkSeconds` is reached and
     flushes the remainder before `endMessages()`.
8. Implement the close codes:
   - `WebSocketConnectionError.closed(code: Int, reason: String?)`, with a description that names
     the code.
   - `URLSessionWebSocketConnection.receive` maps a thrown receive to `closeError(...)` when
     `task.closeCode != .invalid`.
9. Implement the test support:
   - `RecordingSink` records `segments`, `revisions` and `limits`.
   - `TestAdapter` gains `minimumChunkSeconds` and the three event types.
   - `FixtureScript` gains `serverClose`, which `FakeWebSocketConnection` throws as `.closed`.
10. Run `swift test`. Confirm pass and no regressions; every dictation test stays green.

**Definition of done:**
- New emissions reach only the sink.
- Assembler text is unchanged for existing adapters.
- Close codes are visible in `onEngineError`.
- Chunk accumulation is opt-in per adapter.
- Suite green.

**Risks specific to this stage:** `WebSocketEngine`'s two switch sites are the only `Emission`
switches (verified). No other target switches over it.

### Stage 5 — Speechmatics diarization, model and session-timeout warning

**Goal:** `SpeechmaticsAdapter(diarization: true, model:)` requests speaker diarization and emits
one `.segment` per same-speaker run, alongside the existing `.final`. A `session_timeout`
`Warning` emits `.sessionLimit(.warning)`. With `diarization: false` the wire is byte-identical.

**Category:** TDD, with one **characterization/guard** test (the byte-identical start message,
guarding today's dictation contract).

**Design references:** §3 R3, R10, R25; §5.3 (`SpeechmaticsAdapter`); §5.7 (48 h warning);
§5.11.

**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/Adapters/SpeechmaticsAdapter.swift`
- create `Packages/MiniWhisperCore/Tests/MWStreamingTests/Fixtures/streaming/speechmatics_diarized.json`
- edit `Packages/MiniWhisperCore/Tests/MWStreamingTests/CloudAdapterTests.swift`

**Steps (TDD):**
1. Write the guard test in `CloudAdapterTests`:
   `speechmaticsWithoutDiarizationSendsNoDiarizationOrModel` asserts the `StartRecognition`
   `transcription_config` keys equal today's set. It is green now and must stay green.
2. Write tests:
   - `speechmaticsDiarizedStartRecognitionShape`: `diarization: "speaker"`,
     `speaker_diarization_config.max_speakers: 10`, `model: "enhanced"` when passed.
   - `speechmaticsDiarizedFixtureEmitsSegmentsSplitBySpeaker`: two segments, `S1` then `S2`, with
     per-word `start_time`/`end_time`. Punctuation attaches to the previous word, and `UU` maps to a
     `nil` speaker.
   - `speechmaticsDiarizedFixtureStillEmitsFinals`: the assembled text equals the plain
     transcript.
   - `speechmaticsSessionTimeoutWarningEmitsSessionLimit`.
   - `speechmaticsOtherWarningsAreIgnored`.

   The fixture follows the vendor's documented `AddTranscript.results[]` shape. Expected initial
   failure: `error: extra arguments at positions #3, #4 in call`.
3. Run `swift test --filter CloudAdapterTests`. Confirm the build failure.
4. Implement `SpeechmaticsAdapter.swift`:
   - `init(apiKey:hints:diarization: Bool = false, model: String = "standard")`.
   - The config additions are made only when `diarization` is true.
   - `AddTranscript` parses `results[]` into words and groups same-speaker runs into `.segment`,
     after the existing `.final`.
   - `Warning` with `type == "session_timeout"` gives `.sessionLimit(.warning)`.
5. Run `swift test`. Confirm pass and no regressions, including `speechmaticsHappyPathFixture` and
   `speechmaticsMessageShapes`.

**Definition of done:**
- Diarized sessions yield speaker segments with word times.
- Undiarized sessions are byte-identical (guard green).
- Warning-driven rollover signal exists.

**Risks specific to this stage:** Speechmatics punctuation results carry no speaker. They take
the preceding word's run, which the fixture covers.

### Stage 6 — AssemblyAI streaming adapter and the `assemblyai` dictation engine

**Goal:** A tested `AssemblyAIAdapter` for v3 streaming, and `EngineName.assemblyai` as a gated
cloud dictation engine.

The stage covers every exhaustive switch site in core and App, the hint serializer, the
vocabulary report row and the Settings / History / Corrections labels.

**Category:** TDD. The stage is deliberately atomic: the adapter's `name: EngineName` needs the
new case, and the new case breaks every exhaustive switch until all are handled, so the pieces
cannot land apart. Stage-size pressure is waived (see *Risks*).

**Design references:** §3 R5, R10, R11, R25, R27; §5.1 (`MWStreaming`, `MWCorrections`); §5.3
(`AssemblyAIAdapter`, `EngineFactory`, App labels); §5.7.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWStreaming/Adapters/AssemblyAIAdapter.swift`
- create `Packages/MiniWhisperCore/Tests/MWStreamingTests/Fixtures/streaming/assemblyai.json`
- create `Packages/MiniWhisperCore/Tests/MWStreamingTests/Fixtures/streaming/assemblyai_diarized.json`
- edit `Packages/MiniWhisperCore/Tests/MWStreamingTests/CloudAdapterTests.swift`
- edit `Packages/MiniWhisperCore/Sources/MWConfig/EngineName.swift`
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/EngineFactory.swift` (`:46-51`, `:109-115`,
  `KeyAccount(engine:)` `:148-157`)
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/EngineSelection.swift` (`EngineNotice.label`)
- edit `Packages/MiniWhisperCore/Sources/MWCorrections/HintSerializer.swift`
- edit `Packages/MiniWhisperCore/Sources/MWCorrections/HintReport.swift`
- edit `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/HintSerializerTests.swift`
- edit `Packages/MiniWhisperCore/Tests/MWCorrectionsTests/HintReportTests.swift`
- edit `Packages/MiniWhisperCore/Tests/MWStreamingTests/EngineFactoryTests.swift`
- edit `App/Settings/SettingsModel.swift` (`cloudEngines`)
- edit `App/History/HistoryListModel.swift` (`engineLabel`)
- edit `App/Settings/CorrectionsEditorModel.swift` (`noun`)
- edit `AppTests/SettingsModelTests.swift`
- edit `AppTests/HistoryListModelTests.swift`

**Steps (TDD):**
1. Write the hint serializer tests in `HintSerializerTests`:
   - `assemblyAIKeytermsCapAt100`;
   - `assemblyAIKeytermsSkipTermsOver50Characters`: reported as `.wordTooLong` or `.overCap`, as
     the Speechmatics cap reports them.

   Expected initial failure: `error: type 'HintSerializer' has no member 'assemblyAIKeyterms'`.
2. Write the adapter tests in `CloudAdapterTests`:
   - `assemblyAIDictationURLAndHeader`:
     - the query has `speech_model=universal-streaming-english`, `encoding=pcm_s16le`,
       `sample_rate=16000`, `format_turns=true`, and no `speaker_labels`;
     - the header is `Authorization` equal to the key, with no `Bearer`.
   - `assemblyAIDiarizedURLCarriesSpeakerParams`: `speaker_labels=true`, `max_speakers=10`,
     `speaker_labels_revision_interval_ms=300000`.
   - `assemblyAIKeytermsPromptIsAJSONArray`.
   - `assemblyAIHappyPathFixture`: partials then a formatted final give the assembled text.
   - `assemblyAIUnformattedEndOfTurnIsPartialWhenFormatting`.
   - `assemblyAIProFinalisesOnEndOfTurnWithoutFormatting`.
   - `assemblyAIBeginEmitsExpiresAt`: `expires_at` is Unix seconds, giving `.sessionLimit(.expiresAt(date))`.
   - `assemblyAIWordTimesAreConvertedFromMilliseconds`.
   - `assemblyAITurnEmitsASegmentWithTurnOrderAndSpeaker`.
   - `assemblyAISpeakerRevisionIsForwarded`.
   - `assemblyAIEndMessageIsTerminate`.
   - `assemblyAITerminationCompletes`.
   - `assemblyAIErrorMessageFails`.
   - `assemblyAIRequiresHundredMillisecondChunks`: `minimumChunkSeconds == 0.1`.

   Expected initial failure: `error: cannot find 'AssemblyAIAdapter' in scope`.
3. Write the wiring tests:
   - `EngineFactoryTests`: add `.assemblyai` to `cloudEngines` (`:38`), and add
     `assemblyAIUsesTheAssemblyAIKeyAccount` and `assemblyAIDictationHasNoSpeakerLabels` (inspect
     the URL passed to the injected `connect`).
   - `HintReportTests.oneRowPerEngineThenTheBatchRow`: its labels list gains `"AssemblyAI"` before
     `"Batch transcription"`.
   - `AppTests/SettingsModelTests`: `assemblyAIEngineIsGatedOnItsKey`.
   - `AppTests/HistoryListModelTests`: `assemblyAIEngineLabel`.

   Expected initial failure: `error: type 'EngineName' has no member 'assemblyai'`.
4. Run `swift test` and `xcodebuild … test`. Confirm the build failures.
5. Implement `HintSerializer.assemblyAIKeyterms(_:) -> Capped` (≤ 100 terms, ≤ 50 characters each).
6. Implement `AssemblyAIAdapter.swift` per design §5.3:
   - `expires_at` becomes `Date(timeIntervalSince1970:)`.
   - Word `start`/`end` are divided by 1000.
   - A `Turn` speaker label of `UNKNOWN`, or a missing one, maps to `nil`.
   - `minimumChunkSeconds = 0.1`.
   - `drainAfterComplete` is `.milliseconds(200)`, the window `ElevenLabsAdapter` and
     `OpenAIRealtimeAdapter` use; the design asks for a drain.
   - A JSON `error` field throws.
7. Implement the engine case:
   - `EngineName.assemblyai` (raw value `assemblyai`, appended last).
   - `EngineFactory`:
     - the `.assemblyai` case at both switches builds
       `AssemblyAIAdapter(model: "universal-streaming-english", speakerLabels: false, formatTurns: true)`;
     - `KeyAccount(engine:)` maps `.assemblyai` to `.assemblyai`.
   - `EngineNotice.label` gives `"AssemblyAI"`.
   - `HintReport` adds an AssemblyAI row (cap 100) before the batch row.
8. Implement the app side:
   - `cloudEngines` gains `(.assemblyai, .assemblyai, "AssemblyAI", "Add an AssemblyAI key under Keys to enable")`.
   - `HistoryListModel.engineLabel` gains `"AssemblyAI"`.
   - `CorrectionsEditorModel.noun` gains `"terms"` explicitly.
9. Run `swift test` and `xcodegen generate && xcodebuild … test`. Confirm pass and no regressions.

**Definition of done:**
- AssemblyAI is a selectable dictation engine, gated on its key, with keyterms.
- Adapter wire shapes match the fixtures.
- Every `EngineName` switch handles the case.
- Both suites green.

**Risks specific to this stage:**
- **Size.** The stage is large because it is atomic; the adapter and the wiring are reviewed as
  separate commits' worth of diff inside one stage.
- **Unknown parameters.** AssemblyAI ignores unknown query parameters silently. Stage 7's opt-in
  live test asserts that two distinct speaker labels arrive, which proves the diarization
  parameters were honoured.
- **Partial text.** Partial `Turn.transcript` may hold only finalized words. If live captions lag
  in the manual check, build the partial from `words[]` instead; this is recorded as a Stage 24
  verification point.

### Stage 7 — Meeting engines: `MeetingEngineProviding`, `makeMeeting` and `PlatformInfo.supportsSystemAudio`

**Goal:** The factory builds a diarized meeting session per tier behind a new protocol that
fakes can satisfy. `PlatformInfo` knows the minor OS version and whether process taps exist. Two
opt-in live tests prove both providers diarize a two-speaker recording.

**Category:** TDD, plus an opt-in **integration-verified** live check (design §5.12 Integration).

**Design references:** §3 R2, R3, R4; §5.3 (`makeMeeting`, `PlatformInfo`); *Planning decisions
taken* #10, #15.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWStreaming/MeetingEngineProviding.swift`
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/EngineFactory.swift`
- edit `Packages/MiniWhisperCore/Sources/MWStreaming/PlatformInfo.swift`
- create `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeMeetingEngineProvider.swift`
- edit `Packages/MiniWhisperCore/Tests/MWStreamingTests/EngineFactoryTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWStreamingTests/PlatformInfoTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWStreamingTests/MeetingEngineLiveTests.swift`
- create `Packages/MiniWhisperCore/Sources/MWTestSupport/Fixtures/wav/two_speakers.wav`

**Steps (TDD):**
1. Write test in `EngineFactoryTests`:
   - `makeMeetingSpeechmaticsTiersAreDiarizedWithTheirModel`, with arguments `standard` and
     `enhanced`. The test starts the engine against a `FakeWebSocketConnection` and reads the
     `StartRecognition` message.
   - `makeMeetingAssemblyAIStreamingFormatsTurns`.
   - `makeMeetingAssemblyAIProDoesNotFormatTurns`.
   - `makeMeetingPassesHints`.

   Expected initial failure: `error: value of type 'EngineFactory' has no member 'makeMeeting'`.
2. Write test in `PlatformInfoTests`:
   - `supportsSystemAudio`, with arguments: (14, 1) gives false, (14, 2) true, (15, 0) true,
     (26, 0) true;
   - `osMinorDefaultsToTheRunningSystem`.

   Expected initial failure: `error: extra argument 'osMinor' in call`.
3. Run `swift test --filter MWStreamingTests`. Confirm the build failures.
4. Implement `MeetingEngineProviding`, `PlatformInfo` and `FakeMeetingEngineProvider`:
   - `public protocol MeetingEngineProviding: Sendable { func makeMeeting(_ engine: MeetingEngine, key: String, hints: RecognitionHints) -> any StreamingEngine }`,
     with `EngineFactory` conforming. It returns a `WebSocketEngine` over
     `SpeechmaticsAdapter(diarization: true, model:)` or
     `AssemblyAIAdapter(speakerLabels: true, formatTurns: engine == .assemblyaiStreaming)`.
   - `PlatformInfo(osMajor:osMinor:locale:)` with a defaulted `osMinor`, and
     `supportsSystemAudio`. All six existing construction sites compile unchanged.
   - `FakeMeetingEngineProvider` returns a fresh `FakeStreamingEngine` per call and records the
     tier, key and hints.
5. Run `swift test`. Confirm pass and no regressions.
6. Integration-verified, in two parts.
   - **Fixture.** Generate `two_speakers.wav` (16 kHz mono int16, about 20 s, no real person's
     voice):
     - render two alternating sentences with `say -v Samantha -o a.aiff "…"` and
       `say -v Daniel -o b.aiff "…"`;
     - convert each with `afconvert -f WAVE -d LEI16@16000 -c 1`;
     - join them with Python's stdlib `wave` module via `uv run --no-project python`, working in the
       scratchpad;
     - copy the result into `Sources/MWTestSupport/Fixtures/wav/` (already a declared resource;
       reached through `TestFixtures.wav("two_speakers")`).
   - **Live tests.** `MeetingEngineLiveTests`, enabled only with `MW_INTEGRATION == "1"` and the
     provider key in the environment:
     - `speechmaticsDiarizesTwoSpeakers` (`SPEECHMATICS_API_KEY`);
     - `assemblyAIDiarizesTwoSpeakers` (`ASSEMBLYAI_API_KEY`).

     Each streams the fixture at real-time pace through `makeMeeting` and a `RecordingSink`. It
     asserts at least two distinct speaker labels and non-empty segment text.
   - **Run.** `MW_INTEGRATION=1 swift test --filter MeetingEngineLiveTests`, with the keys exported
     in that shell only.

**Definition of done:**
- Each tier builds the right diarized session.
- `supportsSystemAudio` is correct for 14.1, 14.2, 15 and 26.
- The fake is available.
- Both providers diarize the fixture in the opt-in run.

**Risks specific to this stage:** None.

### Phase C — Audio

### Stage 8 — Capture engine meeting mode: hold, meeting listener, voice processing, meeting events

**Goal:** While a meeting holds it, `AudioCaptureEngine` survives idle stop and sleep. It feeds a
meeting listener without accumulating samples, toggles voice processing (reapplied after every
reinstall), and reports sleep and device change on its own `meetingEvents` stream.

**Category:** Hybrid.
- TDD for the engine behaviour on `FakeAudioBackend`.
- An **integration-verified** remainder for `AVAudioEngineBackend.setVoiceProcessing`, which
  needs real hardware.

**Design references:** §3 R9, R26; §5.1 (`MWAudio` row); §5.3 (`MWAudio`); §5.6 (Start step 2,
Pause/Resume, Device change); *Planning decisions taken* #16.

**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWAudio/AudioCapture.swift`
- edit `Packages/MiniWhisperCore/Sources/MWAudio/AudioBackend.swift`
- edit `Packages/MiniWhisperCore/Sources/MWAudio/AudioEvent.swift` (adds `MeetingAudioEvent`)
- edit `Packages/MiniWhisperCore/Sources/MWAudio/AudioCaptureEngine.swift` (and its `CaptureState`)
- edit `Packages/MiniWhisperCore/Sources/MWAudio/AVAudioEngineBackend.swift`
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeAudioBackend.swift`
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeAudioCapture.swift`
- edit `Packages/MiniWhisperCore/Tests/MWAudioTests/AudioCaptureEngineTests.swift`
- edit `Packages/MiniWhisperCore/Tests/MWAudioTests/AVAudioEngineBackendIntegrationTests.swift`

**Steps (TDD):**
1. Write test in `AudioCaptureEngineTests`, all on `VirtualClock`:
   - `heldEngineIgnoresIdleStop`: `scheduleIdleStop(after: .seconds(5))`, then `holdRunning(true)`,
     then advance 6 s. Expect `backend.stopCount == 0` and no `.stopped` event.
   - `releasingTheHoldRestoresIdleStop`.
   - `heldEngineSurvivesSleepAndReportsIt`: `emit(.systemWillSleep)` gives `stopCount == 0` and
     `meetingEvents` yields `.systemWillSleep`.
   - `unheldEngineStillStopsOnSleep`: a guard on today's behaviour.
   - `meetingListenerReceivesBuffersWithoutACapture`.
   - `meetingListenerNeverGrowsTheDictationSnapshot`: buffers delivered before `beginCapture` are
     absent from `endCapture()`.
   - `heldEngineRestartsAfterAConfigurationChange`: `emit(.configurationChanged)` gives
     `startCount == 2`, the tap reinstalled, voice processing reapplied, and `meetingEvents` yields
     `.deviceChanged`.
   - `setVoiceProcessingForwardsToTheBackend`.

   Expected initial failure: `error: value of type 'AudioCaptureEngine' has no member 'holdRunning'`.
2. Run `swift test --filter MWAudioTests`. Confirm the build failure.
3. Implement the protocols and the event type:
   - `AudioBackend` gains `func setVoiceProcessing(_ on: Bool) throws`.
   - `AudioCapture` gains `holdRunning(_:)`, `attachMeetingListener(_:)`, `setVoiceProcessing(_:)`
     and `var meetingEvents: AsyncStream<MeetingAudioEvent>`.
   - `MeetingAudioEvent` is `.systemWillSleep` or `.deviceChanged`.
4. Implement `AudioCaptureEngine`:
   - A `held` flag suppresses the idle stop and the sleep stop.
   - `CaptureState` gains a meeting-listener slot that is called on every ingest and never
     accumulates.
   - The voice-processing flag is stored and reapplied in `ensureRunning()`.
   - On `.configurationChanged` while held, it tears down, restarts, and emits `.deviceChanged`.
5. Implement the backend and fakes:
   - `AVAudioEngineBackend.setVoiceProcessing` stops the engine, calls
     `inputNode.setVoiceProcessingEnabled(_:)`, restarts and reinstalls the tap.
   - `FakeAudioBackend` records `voiceProcessingCalls`.
   - `FakeAudioCapture` gains the four members, records them in its `Call` enum, and adds
     `sendMeeting(_:)`.
6. Run `swift test`. Confirm pass and no regressions; every `DictationControllerTests` test stays
   green.
7. Integration-verified remainder: add `AVAudioEngineBackendIntegrationTests.voiceProcessingTogglesAndBuffersKeepFlowing`
   (`MW_INTEGRATION=1`). It waits on the first buffers with a 5 s deadline, not a sleep. Run
   `MW_INTEGRATION=1 swift test --filter AVAudioEngineBackendIntegrationTests` on a Mac with a
   microphone.

**Definition of done:**
- A held engine never stops on idle or sleep.
- The meeting listener is continuous and non-accumulating (R26).
- Voice processing survives a reinstall.
- Sleep and device change are observable.
- Dictation is unchanged.

**Risks specific to this stage:** `setVoiceProcessingEnabled` can change the input format.
`ensureRunning` already reinstalls the tap at the current format, which the integration test
exercises.

### Stage 9 — `AACFileWriter`

**Goal:** A 16 kHz mono AAC writer that writes int16 PCM, pads silence and finishes into a
decodable 0600 `.m4a`.

**Category:** TDD.

**Design references:** §3 R14; §5.3 (`AACFileWriter`); §5.9 (≈ 29 MB/h); *Planning decisions
taken* #17.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWAudio/AACFileWriter.swift` (with
  `public protocol AudioFileWriting`)
- create `Packages/MiniWhisperCore/Tests/MWAudioTests/AACFileWriterTests.swift`

**Steps (TDD):**
1. Write test in `AACFileWriterTests`, using `TempDirectory` and `SignalFixtures`:
   - `writesADecodable16kMonoAACFile`: one second of ramp, then `finish()`. Reopening with
     `AVAudioFile` gives 16000 Hz, 1 channel, and a length of 1.0 s ± 0.1.
   - `writeSilencePadsTheDuration`: 1 s audio plus 0.5 s silence gives 1.5 s ± 0.1.
   - `fileIsOwnerReadWriteOnly`: `0o600`.
   - `writeAfterFinishThrows`.

   Expected initial failure: `error: cannot find 'AACFileWriter' in scope`.
2. Run `swift test --filter AACFileWriterTests`. Confirm the build failure.
3. Implement `AACFileWriter.swift`:
   - `AudioFileWriting` declares `write(_ pcm16: Data)`, `writeSilence(seconds:)` and `finish()`.
   - `AACFileWriter` conforms. It writes through an `AVAudioFile` with `kAudioFormatMPEG4AAC`,
     16 kHz, mono, from an int16 processing format, and sets permissions to 0600 on create.
4. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- Valid AAC at 16 kHz mono.
- Silence padding is exact to a tenth of a second.
- The file is 0600.

**Risks specific to this stage:** If the system AAC encoder rejects 16 kHz, encode at 16 kHz
with `AVEncoderBitRateKey` 32 000. If that also fails, the test shows it at once, and the
fallback is 22.05 kHz AAC. That fallback would be a design change, so it is a halt-and-ask
point.

### Stage 10 — `SystemAudioTap` and its seams

**Goal:** A Core Audio process tap of every process except this one, read through a private
aggregate device into 16 kHz mono float buffers. It rebuilds on a default-output change, sits
behind a protocol and factory that tests fake, and has the usage string the TCC prompt shows.

**Category:** Hybrid.
- TDD for the pure aggregate-device description, the factory's OS gate and the fake.
- An **integration-verified** remainder for the live tap.
- A **non-TDD (config-only)** `Info.plist` edit.

**Design references:** §3 R2, R3, R24; §4 (Platform facts); §5.3 (`SystemAudioTap`); §5.7 (tap
failure rows); §5.8; *Planning decisions taken* #17, #42.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWAudio/SystemAudioTapping.swift`
  (`SystemAudioTapping`, `SystemAudioTapEvent`, `SystemAudioTapFactory`, `CoreAudioTapFactory`)
- create `Packages/MiniWhisperCore/Sources/MWAudio/SystemAudioTap.swift` (`@available(macOS 14.2, *)`)
- create `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeSystemAudioTap.swift`
  (`FakeSystemAudioTap`, `FakeSystemAudioTapFactory`)
- create `Packages/MiniWhisperCore/Tests/MWAudioTests/SystemAudioTapTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWAudioTests/SystemAudioTapIntegrationTests.swift`
- edit `App/Info.plist`

**Steps (TDD):**
1. Write test in `SystemAudioTapTests`:
   - `aggregateDescriptionIsPrivateWithOneDriftCompensatedTap`: the pure
     `SystemAudioTap.aggregateDescription(tapUID:name:)` has `kAudioAggregateDeviceIsPrivateKey: 1`
     and `kAudioAggregateDeviceTapListKey` with one entry carrying `kAudioSubTapUIDKey` and drift
     compensation on.
   - `factoryReturnsNilWhenTheSystemIsTooOld`: `CoreAudioTapFactory(isSupported: { false })` makes
     `nil`.
   - `fakeTapRecordsStartStopAndDeliversBuffers`.

   Expected initial failure: `error: cannot find 'SystemAudioTap' in scope`.
2. Run `swift test --filter SystemAudioTapTests`. Confirm the build failure.
3. Implement the seams:
   - `SystemAudioTapping`: `start(_ handler:) throws`, `stop()`, `events`.
   - `SystemAudioTapFactory.make(excluding: pid_t) -> (any SystemAudioTapping)?`.
   - `CoreAudioTapFactory` gates on `#available(macOS 14.2, *)` and its injected `isSupported`.
4. Implement `SystemAudioTap`:
   - `CATapDescription(monoGlobalTapButExcludeProcesses: [ownProcessObject])` (the own process is
     found via `kAudioHardwarePropertyTranslatePIDToProcessObject`), with `isPrivate = true` and
     `muteBehavior = .unmuted`.
   - `AudioHardwareCreateProcessTap`, then a private aggregate device from `aggregateDescription`.
   - An `AudioDeviceCreateIOProcIDWithBlock` IOProc that converts with `AVAudioConverter` to 16 kHz
     mono float.
   - A `kAudioHardwarePropertyDefaultOutputDevice` listener that tears down, rebuilds and yields
     `.defaultOutputChanged`. Errors yield `.stopped(error)`.
   - `stop()` destroys the IOProc, the aggregate device and the tap.
5. Implement the fakes:
   - `FakeSystemAudioTap` offers `push(_:)`, `send(_:)`, `startError`, `startCount` and `stopCount`.
   - `FakeSystemAudioTapFactory` can return `nil`.
6. Run `swift test`. Confirm pass and no regressions.
7. Non-TDD (config-only): `App/Info.plist` gains `NSAudioCaptureUsageDescription` with design
   §5.3's sentence. The entitlements are unchanged.
8. Integration-verified remainder: `SystemAudioTapIntegrationTests.tapDeliversBuffersOn142`
   (`MW_INTEGRATION=1`, macOS 14.2+).
   - It starts the tap and plays `TestFixtures.wav(…)` through `AVAudioPlayer`.
   - It awaits the first buffer with RMS above −60 dBFS, with a 5 s deadline.
   - Run `MW_INTEGRATION=1 swift test --filter SystemAudioTapIntegrationTests`. The terminal
     running it needs the System Audio Recording permission.
9. Run `xcodegen generate && xcodebuild … build`. Confirm `Info.plist` compiles.

**Definition of done:**
- The tap seam exists with a fake.
- The OS gate is tested.
- The live tap delivers buffers on 14.2+ in the opt-in test.
- The usage string is present.

**Risks specific to this stage:** Process-tap behaviour differs across 14.2–26 (design §7). The
integration test runs on the developer's macOS 26 only, so 14.2–15 remain untested until a user
reports; the mic-only fallback (Stage 17) bounds the impact.

### Phase D — Meeting store

### Stage 11 — `MWMeetings` target: model, `MeetingStore`, `MeetingReading`

**Goal:** The meeting model and an actor store. The store writes the design §5.2 folder layout
with 0700/0600, appends segments and notes, rewrites atomically, tolerates corrupt lines, keeps
`index.json`, and offers synchronous read-only access to the CLI.

**Category:** Hybrid.
- TDD for model and store.
- **Non-TDD (scaffolding)** for the `Package.swift` registration and the CLAUDE.md module-map row.

**Design references:** §3 R14, R21, R24, R26; §5.1 (`MWMeetings`); §5.2 (Meeting store); §5.3
(`MWMeetings`); §5.6 (Agent read); §5.7 (corrupt line, missing index, concurrent readers);
§5.8; *Planning decisions taken* #12, #19, #20, #37.

**Touches:**
- edit `Packages/MiniWhisperCore/Package.swift`:
  - library `MWMeetings` (deps `MWConfig`, `MWSupport`) and its product;
  - test target `MWMeetingsTests` with `resources: [.copy("Fixtures")]`;
  - `MWTestSupport` gains the `MWMeetings` dependency.
- create `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingModel.swift` (`Meeting`, `Segment`,
  `Word`, `Note`, `Marker`, `Summary`, `SpeakerLabel`, `Billing`, `MeetingMode`, `LoadedMeeting`,
  `IndexEntry`)
- create `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingStore.swift` (actor, plus `MeetingReading`)
- create `Packages/MiniWhisperCore/Sources/MWTestSupport/MeetingFixtures.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingModelTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingStoreTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/Fixtures/corrupt-segments.jsonl`
- edit `CLAUDE.md` (module map, Package layout)

**Steps (TDD):**
1. Non-TDD (scaffolding):
   - Register the three entries in `Package.swift`.
   - Create `Sources/MWMeetings/MeetingModel.swift` with only `import Foundation`.
   - Create `Tests/MWMeetingsTests/Fixtures/corrupt-segments.jsonl`: three lines, the middle one
     malformed.
2. Write test in `MeetingModelTests`:
   - `meetingJSONRoundTripsWithSchemaOne`;
   - `segmentEncodesAsOneLine`: no newline in the encoded data;
   - `speakerLabelKeepsProviderKeys`.

   Expected initial failure: `error: cannot find 'Meeting' in scope`.
3. Write test in `MeetingStoreTests`, using `TempDirectory`:
   - `createMakesA0700FolderAnd0600Files`.
   - `appendedSegmentsAndNotesLoadInOrder`.
   - `updateRewritesMeetingJSONAndItsIndexEntry`.
   - `indexExcerptIsTheSummaryOpeningOrTheFirstSegment`.
   - `rewriteSegmentsReplacesAtomically`: no temp file is left, and the content is replaced.
   - `corruptSegmentLineIsSkippedAndLogged`: the fixture is copied in, 2 of 3 lines load, and
     `CapturingLogSink` has "skipped 1".
   - `missingIndexIsRebuiltAndPersistedByTheActor`: `refreshIndex()` writes `index.json`.
   - `readerRebuildsInMemoryWithoutWriting`: the nonisolated `index()` on a folder without
     `index.json` returns entries and leaves no file (R21).
   - `readerSeesCompleteFilesWhileTheActorWrites`.
   - `deleteRemovesTheFolderAndItsIndexEntry`.
   - `deleteAudioRemovesTheFileAndZeroesAudioBytes`.
   - `audioURLIsInsideTheMeetingFolder`.

   Expected initial failure: `error: cannot find 'MeetingStore' in scope`.
4. Run `swift test --filter MWMeetingsTests`. Confirm the build failures. Scaffold empty types,
   then confirm assertion failures.
5. Implement `MeetingModel.swift`:
   - Every type in design §5.2 is `Codable, Sendable, Equatable`.
   - Dates are ISO 8601.
6. Implement `MeetingStore.swift`:
   - `public actor MeetingStore: MeetingReading` with design §5.3's API plus `refreshIndex()`.
   - One `FileHandle` per open meeting file, flushed per line.
   - Temp-and-rename writes for `meeting.json`, `segments.jsonl` and `index.json`.
   - The index entry is rebuilt on every `meeting.json` write.
   - `nonisolated func index()` and `nonisolated func load(_:)` read files only. They rebuild a
     missing index in memory and never write.
   - Paths are built only from a `UUID`'s `uuidString`.
7. Implement `MeetingFixtures` (MWTestSupport):
   - `northwind()` returns the export mockup's meeting as a `LoadedMeeting`: "Northwind rollout
     sync", id `7f3a9c2e-5b1d-4e0a-9c77-2d8f1a6b3c40`, Alex / Marta / Priya, its notes, gap and
     paused markers, its summary, and `durationSeconds` 2932.
   - `make(...)` is a small builder for other tests.
8. Run `swift test`. Confirm pass and no regressions.
9. Non-TDD (docs): in `CLAUDE.md`'s module map, add the row
   `MWMeetings | Meeting model, MeetingStore, MeetingMarkdown, MeetingSearch, TitleSanitizer | MWConfig, MWSupport`,
   and add `MWMeetings` to `MWTestSupport`'s dependency text.

**Definition of done:**
- The store writes the §5.2 layout with 0700/0600 and survives corrupt lines.
- The index is rebuilt by the actor and read-only for readers.
- `MeetingFixtures.northwind()` exists.
- CLAUDE.md is updated.
- No third-party dependency is added (R24).

**Risks specific to this stage:** A missing declared resource directory fails `swift build`, so
step 1 creates it first.

### Stage 12 — `MeetingMarkdown`, `TitleSanitizer`, `MeetingTitle`, `MeetingSearch`

**Goal:** The transcript and summary exports, byte-for-byte as the accepted mockup. Also the
transcript body the summariser sends, file-name stems, the default title, and the case-insensitive
search with two snippets per meeting.

**Category:** TDD (golden-file tests).

**Design references:** §3 R8, R15, R16, R17; §5.3 (`MeetingMarkdown`, `MeetingSearch`,
`TitleSanitizer`); §5.4; §5.5; §5.9 (search); *Planning decisions taken* #28, #36.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingMarkdown.swift` (with `MeetingTime`)
- create `Packages/MiniWhisperCore/Sources/MWMeetings/TitleSanitizer.swift` (with `MeetingTitle`)
- create `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingSearch.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/Fixtures/golden/northwind-transcript.md`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/Fixtures/golden/northwind-summary.md`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingMarkdownTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/TitleSanitizerTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingSearchTests.swift`

**Steps (TDD):**
1. Write the golden files by copying the two documents from
   `mockups/mockup-v4-export-markdown.html` verbatim.
   - Transcript front-matter order: title, id, date, start, end, duration, mode, app, engine,
     speakers, generator.
   - Summary front-matter order: title, id, date, start, end, duration, mode, app, speakers,
     summary_model, summary_at, transcript, generator.
   - The generator line is `Mini Whisper 0.6.0`.
2. Write test in `MeetingMarkdownTests`:
   - `transcriptMatchesTheGolden`: `MeetingMarkdown.transcript(MeetingFixtures.northwind(), generator: "Mini Whisper 0.6.0")`;
   - `summaryMatchesTheGolden`;
   - `summaryWithoutASummaryThrows`;
   - `sleepPauseAddsMacSlept`;
   - `meetingTimeFormatsHHMMSS`;
   - `transcriptBodyIsTheTranscriptSectionOnly`.

   Expected initial failure: `error: cannot find 'MeetingMarkdown' in scope`.
3. Write test in `TitleSanitizerTests`:
   - `slashAndColonBecomeHyphens`, `trimsAndCollapsesSpaces`, `capsAt120Characters`;
   - `defaultTitleUsesTheFrontApp`: "Zoom · 9 Nov 2026 14:00";
   - `defaultTitleWithoutAnAppIsMeeting`.

   Expected initial failure: `error: cannot find 'TitleSanitizer' in scope`.
4. Write test in `MeetingSearchTests`:
   - `matchesCaseInsensitivelyAcrossTitleTranscriptNotesSummary`;
   - `atMostTwoSnippetsPerMeeting`;
   - `snippetsOrderTranscriptThenNoteThenSummaryByTime`;
   - `titleOnlyMatchListsTheMeetingWithoutSnippets`.

   Expected initial failure: `error: cannot find 'MeetingSearch' in scope`.
5. Run `swift test --filter MWMeetingsTests`. Confirm the build failures.
6. Implement the three files per design §5.3/§5.4. `MeetingTitle.default(app:date:timeZone:)`
   formats `d MMM yyyy HH:mm` with `en_US_POSIX`.
7. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- Both exports equal the mockup.
- File stems, default title and search behave as specified.

**Risks specific to this stage:** The mockup is HTML. Copy its `<pre>` text exactly, decoding
`&lt;`, `&gt;` and `&amp;`. A mis-copied golden is the most likely cause of a later "export differs
from mockup" report.

### Phase E — Meeting pipeline

### Stage 13 — `MWMeetingPipeline` target: `SpeechGate`, `AudioMixer`, system-audio ring, float resampling

**Goal:** The pipeline target exists with the mic voice-activity gate, the two-source mixer with
soft limiter, the 2 s system-audio ring, and a float 16 kHz resampler.

**Category:** Hybrid.
- TDD for the four units.
- **Non-TDD (scaffolding)** for the target registration and the CLAUDE.md row.

**Design references:** §3 R3, R25, R26; §5.1 (`MWMeetingPipeline`); §5.3 (`SpeechGate`,
`AudioMixer`); §5.6 (Audio tick); §5.9; *Planning decisions taken* #21, #25.

**Touches:**
- edit `Packages/MiniWhisperCore/Package.swift`:
  - library `MWMeetingPipeline` with deps `MWMeetings`, `MWStreaming`, `MWAudio`, `MWConfig`,
    `MWCorrections`, `MWUsage`, `MWTranscription`, `MWSupport`;
  - its product;
  - test target `MWMeetingPipelineTests`.
- edit `Packages/MiniWhisperCore/Sources/MWAudio/PCMConverter.swift` (`resample(_:) -> [Float]`)
- edit `Packages/MiniWhisperCore/Tests/MWAudioTests/PCMConverterTests.swift`
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SpeechGate.swift`
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/AudioMixer.swift`
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SystemAudioRing.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SpeechGateTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/AudioMixerTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SystemAudioRingTests.swift`
- edit `CLAUDE.md` (module map)

**Steps (TDD):**
1. Non-TDD (scaffolding): register the target, product and test target in `Package.swift`, with
   `Sources/MWMeetingPipeline/SpeechGate.swift` holding only `import Foundation`.
2. Write test in `PCMConverterTests`:
   - `resampleTo16kFloatHasTheExpectedCount`: 4800 samples at 48 kHz give 1600;
   - `resampleCarriesStateAcrossChunks`: chunked equals batch, mirroring
     `chunkedMatchesBatch48kTo24k`.

   Expected initial failure: `error: value of type 'PCMConverter' has no member 'resample'`.
3. Write test in `SpeechGateTests`, on synthetic 20 ms frames from `SignalFixtures`:
   - `onsetNeedsThreeConsecutiveLoudFrames`;
   - `releaseAfter300MillisecondsBelowThreshold`;
   - `framesBelowMinus45dBFSNeverOpen`;
   - `noiseFloorAdaptsOverTenSeconds`: a steady level stops counting as speech;
   - `spansAreStampedInMeetingTime`;
   - `ringKeepsTheLastTenMinutes`;
   - `overlapFractionOfAWord`;
   - `isSpeakingNowFollowsTheOpenSpan`.

   Expected initial failure: `error: cannot find 'SpeechGate' in scope`.
4. Write test in `AudioMixerTests`:
   - `sumsBothSources`, `missingSourceContributesZeros`;
   - `softLimiterKeepsTheOutputBelowOne`: inputs at 0.8 + 0.8 give an output in (0.9, 1.0);
   - `outputLengthFollowsTheMicBuffer`.

   Write test in `SystemAudioRingTests`:
   - `holdsAtMostTwoSeconds`;
   - `takeReturnsTheRequestedCountPaddingWithZeros`;
   - `peakSinceReportsTheLoudestSample`, used later by the silence hint.

   Expected initial failure: `error: cannot find 'AudioMixer' in scope`.
5. Run `swift test --filter MWAudioTests` and `swift test --filter MWMeetingPipelineTests`.
   Confirm the build failures.
6. Implement:
   - `PCMConverter.resample(_:) -> [Float]`, the float path of the existing converter.
   - `SpeechGate` per design §5.3: thresholds as named constants; a running 5th-percentile noise
     floor over 10 s; a `[SpeechSpan]` ring of 10 minutes; `View` with
     `overlap(start:end:) -> Double` and `isSpeakingNow`.
   - `AudioMixer.mix(mic:system:)`, with `tanh` above 0.9.
   - `SystemAudioRing`: lock-guarded, 32 000 samples.
7. Run `swift test`. Confirm pass and no regressions.
8. Non-TDD (docs): in `CLAUDE.md`'s module map, add the row
   `MWMeetingPipeline | SpeechGate, AudioMixer, SpeakerAttributor, SpeakerRegistry, SessionSupervisor, MeetingRecorder, MeetingBilling, Summariser, MeetingController | MWMeetings, MWStreaming, MWAudio, MWConfig, MWCorrections, MWUsage, MWTranscription, MWSupport`.
   Change "nothing depends on `MWPipeline`" to name both pipelines.

**Definition of done:**
- The gate, mixer, ring and resampler match design §5.3/§5.9.
- The ring caps memory at 2 s (R26).
- The target is registered and documented.

**Risks specific to this stage:** Gate thresholds are tuned on synthetic frames only; see *Risks
and open issues*.

### Stage 14 — `SpeakerRegistry` and `SpeakerAttributor`

**Goal:** Stable speaker numbering across sessions, user binding, rename and merge, and the 50 %
word rule plus the 70 % label rule that attribute mixed-stream words to the user.

**Category:** TDD.

**Design references:** §3 R3, R7, R11; §5.3 (`SpeakerAttributor`, `SpeakerRegistry`); §5.7
(diarizer merge/split, rename to existing name); *Planning decisions taken* #31.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SpeakerRegistry.swift`
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SpeakerAttributor.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SpeakerRegistryTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SpeakerAttributorTests.swift`

**Steps (TDD):**
1. Write test in `SpeakerRegistryTests`:
   - `userIsIdZeroWithTheUsersName`;
   - `firstSightAllocatesTheNextSpeakerNumber`: "Speaker 1", "Speaker 2";
   - `sameSessionAndLabelMapToOneID`;
   - `aNewSessionsLabelsAllocateFreshNumbers` (R11);
   - `renameChangesTheNameOnly`;
   - `renameToAnExistingNameMergesAndRepointsProviderKeys`;
   - `bindingALabelToTheUserMapsItToZero`;
   - `restoresFromStoredSpeakerLabels`.

   Expected initial failure: `error: cannot find 'SpeakerRegistry' in scope`.
2. Write test in `SpeakerAttributorTests`:
   - `wordWithHalfItsSpanInSpeechIsTheUsers`;
   - `wordBelowHalfKeepsTheProviderLabel`;
   - `adjacentWordsWithOneOutcomeFormOneSegment`;
   - `labelWithSeventyPercentGateWordsBindsToTheUser`: later words of that label become the user's;
   - `inRoomNeverConsultsTheGate`;
   - `nilProviderLabelIsItsOwnSpeakerPerSession`;
   - `attributionIsDeterministic`.

   Expected initial failure: `error: cannot find 'SpeakerAttributor' in scope`.
3. Run `swift test --filter MWMeetingPipelineTests`. Confirm the build failures.
4. Implement both per design §5.3. The registry is a value type held by the controller. The
   attributor is a pure function that also returns updated per-label tallies.
5. Run `swift test`. Confirm pass and no regressions.

**Definition of done:** The two rules and the registry semantics are covered, including the
cross-session reset and merge.

**Risks specific to this stage:** None.

### Stage 15 — `SessionSupervisor`

**Goal:** One provider session at a time.
- Reconnect after a failure with backoff 1, 2, 4, 8, 15, 30 s, then 30 s forever.
- Session indices and audio origins.
- A gap marker on the first segment after a reconnect.
- AssemblyAI rollover at `expires_at − 60 s`, Speechmatics rollover on the `session_timeout`
  warning.
- Audio fed while closed is dropped.
- The whole thing is tested on `VirtualClock`.

**Category:** TDD.

**Design references:** §3 R10, R11, R25; §5.3 (`SessionSupervisor`); §5.6 (Pause/Resume, Stop);
§5.7 (key revoked, 3 h limit, 48 h warning, close codes); §5.10; *Planning decisions taken* #6,
#24.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SessionSupervisor.swift` (with
  `ConnectionState`, `SupervisorEvent`)
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SessionSupervisorTests.swift`

**Steps (TDD):**
1. Write test in `SessionSupervisorTests`, using `FakeMeetingEngineProvider`, `VirtualClock` and
   an injected wall-clock `now`. Failures and limits are driven by calling the sink captured by each
   `FakeStreamingEngine`, for example `onEngineError(WebSocketConnectionError.closed(code: 4005, reason: nil))`.
   - `openStartsOneSessionAndFeedsIt`.
   - `engineErrorReconnectsWithTheBackoffSequence`: open times are 1, 2, 4, 8, 15, 30, 30 s after
     each failure.
   - `backoffResetsOnceTheNewSessionDelivers`.
   - `reconnectingEventCarriesTheAttempt`.
   - `firstSegmentAfterAReconnectEmitsAGapMarker`: from the last segment's end to the new
     segment's start, in meeting seconds.
   - `rolloverOpensTheNextSessionAtExpiresAtMinusSixty`: then the old one finishes with 5 s.
   - `rolloverAfterASuccessfulOverlapEmitsNoGap`.
   - `speechmaticsWarningRollsOverAtOnce`.
   - `oldSessionSegmentsStillDrainWithTheirSessionIndex`.
   - `audioFedWhileClosedIsDropped`.
   - `sessionAudioOriginIsTheMeetingTimeOfTheFirstFedBuffer`.
   - `closeFinishesWithFiveSecondsAndStopsReconnecting`.
   - `closeCodeAndAttemptAreLogged`: `CapturingLogSink` has "4005" and "attempt 3", and no key.

   Expected initial failure: `error: cannot find 'SessionSupervisor' in scope`.
2. Run `swift test --filter SessionSupervisorTests`. Confirm the build failure.
3. Implement `SessionSupervisor`:
   - `init(provider:engine:key:hints:clock:now:)`, with `open(at:)`, `feed(_:at:)`, `close() async`
     and `events: AsyncStream<SupervisorEvent>`.
   - `SupervisorEvent` is `.partial`, `.segment(TranscriptSegment, session:, origin:)`,
     `.revision`, `.connection(ConnectionState)` or `.gap(Marker)`.
   - Each session gets its own `TranscriptSink` adapter object, which forwards `onSessionLimit` and
     `onEngineError` into the supervisor.
4. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- Backoff, rollover, gap and drop rules are covered on `VirtualClock`.
- Close codes are logged without secrets.

**Risks specific to this stage:** A finished old session can still call its sink after the
rollover. The per-session sink tags every callback with its session index, so late segments land
in the right session.

### Stage 16 — `MeetingRecorder`, `MeetingBilling`, `Summariser`

**Goal:**
- The recorder writes PCM through `AudioFileWriting` and pads paused spans.
- Billing gives the live estimate and the two `ProviderUsage` records per meeting.
- The summariser builds the system and user messages, truncates at 600 000 characters, and maps
  outcomes.

**Category:** TDD.

**Design references:** §3 R8, R9, R12, R14, R18; §5.3 (`MeetingRecorder`, `MeetingBilling`,
`Summariser`); §5.5; §5.7 (empty transcript, refusal, errors); *Planning decisions taken* #13,
#18, #26.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingRecorder.swift`
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingBilling.swift`
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/Summariser.swift`
- create `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeAudioFileWriter.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingRecorderTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingBillingTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SummariserTests.swift`

**Steps (TDD):**
1. Write test in `MeetingRecorderTests`, with `FakeAudioFileWriter`:
   - `writesInt16PCM`;
   - `resumePadsThePausedSpanWithSilence`;
   - `finishClosesTheWriter`.

   Write test in `MeetingBillingTests`:
   - `liveCostSpeechmaticsStandard`;
   - `liveCostAssemblyAIIncludesDiarization`;
   - `finalUsageRecordsSecondsOnceUnderThePricingKey`: `streamedSeconds == ["assemblyai": s]` and
     `costUSD` includes the diarization add-on;
   - `todayMinutesAreNotDoubled`: `Pricing.formatUsageRows` over the final usage shows the
     meeting's minutes once;
   - `summaryUsageCostsAtSonnetRates`;
   - `overridesApply`.

   Expected initial failure: `error: cannot find 'MeetingRecorder' in scope`.
2. Write test in `SummariserTests`, with `FakeSummarizer` and a stub `SummaryPromptProviding`:
   - `systemIsThePromptFileText`.
   - `userCarriesSpeakersNotesAndTranscriptInDelimiters`: the exact design §5.5 string over
     `MeetingFixtures.northwind()`.
   - `transcriptOver600000CharactersIsTruncatedFromTheStart`: the leading line is "[earlier part of
     the meeting omitted]" and `Summariser.isTruncated(meeting) == true`.
   - `emptyTranscriptSkipsTheRequest`: the outcome is `.empty` and the fake gets no call.
   - `refusalIsDeclinedWithItsCategory`.
   - `errorsPropagate`.
   - `summaryCarriesModelTimeTokensAndCost`.

   Expected initial failure: `error: cannot find 'Summariser' in scope`.
3. Run `swift test --filter MWMeetingPipelineTests`. Confirm the build failures.
4. Implement the three units:
   - `MeetingRecorder(writer:)`: `write(_ samples: [Float])` converts to int16;
     `pause(at:)`/`resume(at:)` pad the paused span; `finish()`.
   - `MeetingBilling(engine:overrides:)`: `add(seconds:)`, `liveCost`, `finalUsage()`,
     `summaryUsage(_:)`.
   - `Summariser(prompts:client:clock:)`: `run(_ meeting: LoadedMeeting) async throws -> SummaryOutcome`,
     where the outcome is `.ready(Summary)`, `.declined(String)` or `.empty`, plus
     `static func isTruncated(_ meeting: LoadedMeeting) -> Bool`.
5. Implement `FakeAudioFileWriter`, which records writes, silence and finish.
6. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- Recorder padding is covered.
- Billing never double-counts minutes (R18).
- The summariser request text equals design §5.5, with truncation and outcome mapping.

**Risks specific to this stage:** None.

### Stage 17 — `MeetingController` I: start, audio tick, segments, stop, persistence, billing, summary

**Goal:** The happy path end to end on fakes:
- start a remote or in-room meeting;
- mix, gate and feed audio;
- attribute, persist and emit segments;
- tick elapsed time and cost;
- stop, bill and summarise.

**Category:** TDD.

**Design references:** §3 R2, R3, R12, R14, R15, R18; §5.3 (`MeetingController`,
`MeetingDependencies`, `MeetingEvent`); §5.6 (Start, Audio tick, Segment arrives, Stop,
Summarise); §5.7 (no key, tap failure, 14.0/14.1, empty transcript, Anthropic failures);
*Planning decisions taken* #9, #16, #21, #40.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingDependencies.swift`
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingEvent.swift` (`MeetingEvent`,
  `MeetingState`, `SummaryState`, `SystemAudioState`, `MeetingError`)
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingAudioPath.swift` (the
  tap-thread, lock-guarded tick: resample, gate, mix, record, feed, bill)
- create `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTests.swift`

**Steps (TDD):**
1. Write test in `MeetingControllerTests`. The fixture uses `FakeAudioCapture`,
   `FakeSystemAudioTapFactory`, `FakeMeetingEngineProvider`, `FakeSecretStore`, a `MeetingStore`
   on `TempDirectory`, `FakeSummarizer`, `FakeUsageStore`, a stub prompt provider, `VirtualClock`
   and a `ConfigStore` on `TempDirectory`. Tests:
   - `startWithoutAnyKeyThrowsNoEngineKey`.
   - `startUsesTheConfiguredTierAndItsKey`.
   - `startHoldsCaptureEnablesVoiceProcessingAndAttachesTheMeetingListener`: the
     `FakeAudioCapture.calls` order.
   - `remoteStartStartsTheTapExcludingOurPID`.
   - `tapStartFailureContinuesMicOnly`: emits `.systemAudio(.unavailable(_))`.
   - `remoteWithoutATapFactoryResultRunsMicOnly`: the macOS 14.0/14.1 path.
   - `startCreatesTheMeetingOnDiskWithTitleAppModeAndEngine`.
   - `firstRemoteStartSetsSystemAudioExplained`.
   - `remoteTickFeedsMixedAudioToTheSessionTheRecorderAndBilling`.
   - `inRoomTickBypassesTheGateAndTheMixer`.
   - `segmentIsShiftedAttributedPersistedAndEmitted`: a word overlapping a mic span gets speaker 0.
   - `partialIsTaggedWithTheUserWhileTheGateIsOpen`.
   - `elapsedAndCostTickEverySecond`.
   - `stopDrainsTheSessionReleasesCaptureAndStopsTheTap`.
   - `stopWritesEndedAtDurationAndBilling`.
   - `stopAddsOneUsageRecord`.
   - `stopWithoutAnAnthropicKeyReportsNoSummary`: "No summary: add an Anthropic key under Keys."
   - `stopWithAKeyStoresTheSummaryAndBillsItsTokens`.
   - `summaryFailureLeavesNoSummary`.
   - `refusalReadsSummaryDeclinedWithCategory`.
   - `emptyTranscriptReportsNothingTranscribed`.
   - `keepAudioOffWritesNoAudioFile`.

   Expected initial failure: `error: cannot find 'MeetingController' in scope`.
2. Run `swift test --filter MeetingControllerTests`. Confirm the build failure. Scaffold the types,
   then confirm assertion failures.
3. Implement the support types:
   - `MeetingDependencies`: design §5.3's fields, where `engines` is
     `any MeetingEngineProviding`, `prompts` is `any SummaryPromptProviding` and `tapFactory` is
     `any SystemAudioTapFactory`.
   - `MeetingEvent` and its states per design §5.3, plus `.error(String)`.
   - `MeetingAudioPath`: a final class with a lock, running on the capture thread.
4. Implement `MeetingController` (`@MainActor`, like `DictationController`):
   - `start` follows design §5.6 steps 1–7.
   - Hints come from `HintResolver.resolve(CorrectionSnapshot(config:), bundleID: nil)`.
   - `stop(summarise: Bool = true)` follows §5.6 Stop.
   - `summarise()` follows §5.6 Summarise.
   - `events` is an `AsyncStream`.
   - Log start/stop, mode and engine through `Log.meeting`.
5. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- A remote and an in-room meeting run start to stop on fakes.
- Every Stop branch (no key, ready, failed, declined, empty) emits the right summary state.
- Usage is recorded once for audio and once for tokens.

**Risks specific to this stage:** The capture tap thread must not hop to the main actor per
buffer. `MeetingAudioPath` keeps the tick off the main actor and hands only segments, partials
and one-second ticks to it.

### Stage 18 — `MeetingController` II: pause, sleep, device change, silence hint, rename, notes, revisions, edits, open, retitle

**Goal:** Every remaining controller behaviour:
- pause/resume and sleep auto-pause, device-change gaps, the 60 s silence hint;
- rename/merge, notes, `SpeakerRevision` re-mapping that respects pinned segments;
- edit and reassign after Stop;
- `open` of a stored meeting, `retitle`, summarise later;
- `isActive` for the dictation lock and the quit prompt;
- the write-error fallback.

**Category:** TDD.

**Design references:** §3 R7, R8, R9, R11, R13, R15, R19; §5.3 (`MeetingController` API); §5.6
(Silence hint, Pause/Resume, Device change, Second hotkey press, Rename); §5.7 (sleep, device
change, rename to existing, reassignment vs revision, quit, disk full); *Planning decisions
taken* #22, #23, #27.

**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`
- edit `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingAudioPath.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerLifecycleTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerEditingTests.swift`

**Steps (TDD):**
1. Write test in `MeetingControllerLifecycleTests`, on `VirtualClock`:
   - `pauseClosesTheSessionAndOpensAPausedMarker`;
   - `resumePadsSilenceClosesTheMarkerAndOpensANewSession`;
   - `sleepAutoPausesWithTheSleepReasonAndStaysPaused`;
   - `deviceChangeRestartsCaptureAndReappliesVoiceProcessing`;
   - `deviceChangeLosingMoreThanTwoSecondsWritesAGap`: "input device changed";
   - `deviceChangeUnderTwoSecondsWritesNoGap`;
   - `defaultOutputChangeFollowsTheSameTwoSecondRule`;
   - `silenceHintAfterSixtySecondsOfOneSidedSpeech`: emitted once;
   - `noSilenceHintWhenSystemAudioArrives`;
   - `isActiveWhileStartingRecordingPausedAndStopping`;
   - `appendFailureEmitsAnErrorKeepsSegmentsInMemoryAndRetries`: the store directory is made
     read-only, then restored.

   Expected initial failure: `error: value of type 'MeetingController' has no member 'pause'`.
2. Write test in `MeetingControllerEditingTests`:
   - `renameUpdatesSpeakers`;
   - `renameToAnExistingNameMergesAndRewritesSegments`;
   - `addNotePersistsAndEmitsAtTheFirstKeystrokeTime`;
   - `speakerRevisionRemapsByTurnOrderWithinItsSession`;
   - `pinnedSegmentIsNeverRevised`;
   - `editIsRefusedWhileRecording`;
   - `editAfterStopPersistsAndMarksEdited`;
   - `reassignAfterStopPinsAndPersists`;
   - `openLoadsAStoredMeetingIntoStopped`;
   - `retitleRewritesMeetingJSON`;
   - `summariseLaterWorksOnAnOpenedMeetingWithoutASummary`;
   - `summariseIsANoOpWhenASummaryExists`.

   Expected initial failure: `error: value of type 'MeetingController' has no member 'rename'`.
3. Run `swift test --filter MWMeetingPipelineTests`. Confirm the build failures.
4. Implement per design §5.6/§5.7, with `pause()`, `resume()`, `rename(speaker:to:)`,
   `addNote(_:firstKeystrokeAt:)`, `edit(segment:text:)`, `reassign(segment:to:)`, `open(_:)`,
   `retitle(_:)` and `isActive`. The controller consumes `meetingEvents` from `AudioCapture` and
   `events` from the tap.
5. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- Every row of design §5.7 that belongs to the controller is covered.
- A stored meeting can be opened, edited, retitled and summarised.

**Risks specific to this stage:** The write-error test depends on POSIX permissions under the
test user. Run as root it would pass vacuously, so the test `#require`s that the directory is
unwritable before asserting.

### Phase F — Agent access

### Stage 19 — `MWAgentAccess` target and `MeetingsCLI`

**Goal:** `meetings list [--json]`, `transcript <id>`, `summary <id>` and `search <text> [--json]`
print the right text and exit codes against any `MeetingReading`. Ids are validated before any
path is built.

**Category:** Hybrid.
- TDD for the CLI.
- **Non-TDD (scaffolding)** for the target registration and the CLAUDE.md row.

**Design references:** §3 R21, R24; §5.1 (`MWAgentAccess`); §5.3 (`MWAgentAccess`); §5.7 (CLI bad
id); §5.8 (read-only, id validation); *Planning decisions taken* #29.

**Touches:**
- edit `Packages/MiniWhisperCore/Package.swift`:
  - library `MWAgentAccess` (deps `MWMeetings`, `MWSupport`) and its product;
  - test target `MWAgentAccessTests`.
- create `Packages/MiniWhisperCore/Sources/MWAgentAccess/MeetingID.swift`
- create `Packages/MiniWhisperCore/Sources/MWAgentAccess/MeetingsCLI.swift`
- create `Packages/MiniWhisperCore/Tests/MWAgentAccessTests/MeetingIDTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWAgentAccessTests/MeetingsCLITests.swift`
- edit `CLAUDE.md` (module map)

**Steps (TDD):**
1. Non-TDD (scaffolding): register the target, product and test target, with
   `Sources/MWAgentAccess/MeetingID.swift` holding only `import Foundation`.
2. Write test in `MeetingIDTests`:
   - `fullUUIDResolves`;
   - `eightHexPrefixResolvesWhenUnambiguous`;
   - `ambiguousPrefixIsRejected`;
   - `shortOrNonHexInputIsRejectedBeforeAnyLookup`: `"../etc"` and `"7f3a"`.

   Expected initial failure: `error: cannot find 'MeetingID' in scope`.
3. Write test in `MeetingsCLITests`, over a `MeetingStore` seeded with `MeetingFixtures`, with
   injected `out`/`err` closures:
   - `listPrintsOneLinePerMeeting`;
   - `listJSONIsTheIndex`;
   - `transcriptPrintsExactlyMeetingMarkdown`;
   - `summaryPrintsExactlyMeetingMarkdown`;
   - `summaryOfAMeetingWithoutOneExits2`;
   - `searchPrintsIdTimeSourceSnippet`;
   - `searchJSON`;
   - `unknownIdExits2WithOneStderrLine`: "no meeting <id>";
   - `unknownSubcommandExits2WithUsage`;
   - `everyCommandExitsZeroOnSuccess`.

   Expected initial failure: `error: cannot find 'MeetingsCLI' in scope`.
4. Run `swift test --filter MWAgentAccessTests`. Confirm the build failures.
5. Implement the two types:
   - `MeetingID.resolve(_:in:) -> Result<UUID, MeetingIDError>`.
   - `MeetingsCLI(reader: any MeetingReading, generator: String)` with
     `run(_ arguments: [String], out: (String) -> Void, err: (String) -> Void) -> Int32`. It takes
     only `MeetingReading`, so no write method is reachable.
6. Run `swift test`. Confirm pass and no regressions.
7. Non-TDD (docs): in `CLAUDE.md`'s module map, add the row
   `MWAgentAccess | MeetingsCLI, MCPServer, MeetingID | MWMeetings, MWSupport`.

**Definition of done:**
- The CLI outputs equal `MeetingMarkdown`.
- Exit codes are 0 or 2.
- Ids are validated before lookup.
- The target links no audio, streaming or pipeline code.

**Risks specific to this stage:** None.

### Stage 20 — `MCPServer`

**Goal:** A stdio JSON-RPC server that:
- speaks both the legacy `initialize` handshake and the 2026-07-28 stateless shape
  (`server/discover`, per-request `_meta` version);
- offers four read-only tools;
- answers every error case with the right code;
- writes one JSON object per line.

**Category:** TDD.

**Design references:** §3 R21; §5.3 (`mini-whisper mcp`); §5.7 (MCP rows); §5.8 (typed decoding,
10 000-character cap); *Planning decisions taken* #30.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWAgentAccess/MCPServer.swift`
- create `Packages/MiniWhisperCore/Sources/MWAgentAccess/MCPMessages.swift` (typed request/response
  structs)
- create `Packages/MiniWhisperCore/Tests/MWAgentAccessTests/MCPServerTests.swift`

**Steps (TDD):**
1. Write test in `MCPServerTests`, through the pure `handle(line:) -> String?` and the
   `run(readLine:write:) -> Int32` loop:
   - `initializeEchoes20251125` and `initializeEchoes20250618`;
   - `initializeWithAnUnknownVersionAnswers20251125`;
   - `initializedNotificationGetsNoReply`;
   - `pingReturnsAnEmptyObject`;
   - `serverDiscoverReturnsCompleteWithCapabilitiesAndTools`;
   - `toolsListHasFourReadOnlyToolsWithSchemas`;
   - `listMeetingsReturnsText`;
   - `getTranscriptReturnsTheMarkdown`;
   - `getSummaryWithoutOneIsAnError`: `isError: true`;
   - `searchMeetingsCapsLimitAt50`;
   - `unknownToolIsAnError`;
   - `unknownMethodIsMinus32601`;
   - `malformedJSONIsMinus32700AndTheLoopContinues`;
   - `metaVersion20260728IsServed`;
   - `otherMetaVersionIsMinus32022WithSupportedAndRequested`;
   - `stringsOver10000CharactersAreInvalidParams`;
   - `everyResponseIsOneLine`;
   - `eofExitsZero`.

   Expected initial failure: `error: cannot find 'MCPServer' in scope`.
2. Run `swift test --filter MCPServerTests`. Confirm the build failure.
3. Implement `MCPServer(reader: any MeetingReading, version: String)` with typed `Codable` messages
   (unknown fields ignored), tool dispatch over `MeetingID`, `MeetingMarkdown` and `MeetingSearch`,
   and logs to stderr only.
4. Run `swift test`. Confirm pass and no regressions.

**Definition of done:**
- Both protocol eras are served.
- All error codes are covered.
- Output is newline-delimited with no embedded newlines.
- The server is read-only by type.

**Risks specific to this stage:** None.

### Stage 21 — App CLI entry: `AgentCommand`, `main.swift`, `CommandLineToolInstaller`

**Goal:**
- `Mini Whisper meetings …` and `Mini Whisper mcp` run before `NSApplication` and exit.
- The installer builds the wrapper script and the admin `osascript` command, and reports the
  result.
- `project.yml` links `MWMeetings` and `MWAgentAccess`.

**Category:** Hybrid.
- TDD for `AgentCommand` parsing and the installer's script and command builders.
- An **integration-verified** remainder for the built binary's CLI and MCP behaviour.
- The `NSAppleScript` run itself is **platform-only**.

**Design references:** §3 R21, R22; §5.3 (App: `main.swift`, `CommandLineToolInstaller`); §5.8
(installer quoting); §6 (no symlink); *Planning decisions taken* #38.

**Touches:**
- edit `project.yml` (products `MWMeetings`, `MWAgentAccess`)
- create `App/AgentCommand.swift`
- edit `App/main.swift`
- create `App/CommandLineToolInstaller.swift`
- create `AppTests/AgentCommandTests.swift`
- create `AppTests/CommandLineToolInstallerTests.swift`

**Steps (TDD):**
1. Write test in `AgentCommandTests`:
   - `meetingsSubcommandIsRecognised`;
   - `mcpIsRecognised`;
   - `debugFlagStartsTheGUI`;
   - `noArgumentsStartsTheGUI`;
   - `finderProcessSerialNumberIsIgnored`: `-psn_0_123` returns `nil`.

   Expected initial failure: `error: cannot find 'AgentCommand' in scope`.
2. Write test in `CommandLineToolInstallerTests`:
   - `scriptBakesTheBundlePath`;
   - `scriptFallsBackToTheBundleID`: contains `path to application id "com.ips.mini-whisper"`;
   - `aPathWithASingleQuoteIsEscaped`: uses `'\''`;
   - `installCommandMakesTheDirectoryWritesTheFileAndChmods755`: `mkdir -p /usr/local/bin`, and the
     command contains no `ln`;
   - `isInstalledReadsTheWrapper`;
   - `mcpCommandUsesTheShortNameWhenInstalled`;
   - `mcpCommandUsesTheFullBinaryPathOtherwise`.

   Expected initial failure: `error: cannot find 'CommandLineToolInstaller' in scope`.
3. Run `xcodegen generate && xcodebuild … test`. Confirm the build failures.
4. Implement:
   - `project.yml` gains the two product entries.
   - `AgentCommand(arguments:)` returns `nil` unless `arguments[1]` is `meetings` or `mcp`.
     `run() -> Int32` builds `MeetingStore(directory: AppDelegate.configDirectory/meetings)` and runs
     `MeetingsCLI` or `MCPServer`, with the version from `CFBundleShortVersionString`.
   - `main.swift` gets the early branch from design §5.3 before `NSApplication.shared`.
     `SingleInstanceGuard` is not consulted on that path.
   - `CommandLineToolInstaller` offers `script(appPath:)`, `installCommand(script:)`, `install()`
     (via `NSAppleScript`, returning a `Result` with the error text), `isInstalled` and
     `mcpCommand(installed:binaryPath:)`.
5. Run `xcodegen generate && xcodebuild … test`. Confirm pass and no regressions.
6. Integration-verified remainder (the build products live under `.dd/Build/Products/Debug/`):
   - Run `".dd/Build/Products/Debug/Mini Whisper.app/Contents/MacOS/Mini Whisper" meetings list; echo $?`
     and expect exit 0.
   - Run
     `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' | ".dd/Build/Products/Debug/Mini Whisper.app/Contents/MacOS/Mini Whisper" mcp`
     and expect exactly one JSON line with `"protocolVersion":"2025-11-25"` and exit 0.
   - Run `".../Mini Whisper" meetings transcript zzzzzzzz; echo $?` and expect exit 2 with one
     stderr line.
   - The installer's admin prompt is checked once by hand from Stage 27's row.

**Definition of done:**
- The binary serves CLI and MCP without starting the GUI or capture.
- The wrapper is a script, never a symlink.
- Both suites are green.

**Risks specific to this stage:** Under the hardened runtime, `NSAppleScript` `do shell script …
with administrator privileges` runs in-process and needs no Apple Events entitlement. If it is
refused at runtime, the row shows the error text (design §7), and the Claude Code row falls back
to the full binary path.

### Phase G — App user interface

### Stage 22 — The meeting hotkey binding

**Goal:**
- `BindingName.meeting` is captured in Settings → Hotkeys and stored in `meeting_hotkey`.
- A combo equal to another binding is refused.
- An unparsable or duplicate stored combo falls back to `ctrl+alt+cmd+m`.
- `.meeting` presses are ignored until Stage 24 wires them.

**Category:** Hybrid.
- TDD for the matcher, the binding table, the capture rule and the refusal.
- **Platform-only / UI wiring** for the `HotkeysSection` field.

**Design references:** §3 R1; §4 (Hotkeys switch sites); §5.3 (App: `bindings(from:)`,
`HotkeysSection`, `handle(.captured)`); §5.7 (unparsable hotkey, duplicate combo); *Planning
decisions taken* #33.

**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWHotkeys/HotkeyAction.swift`
- edit `Packages/MiniWhisperCore/Tests/MWHotkeysTests/HotkeyMatcherTests.swift`
- edit `Packages/MiniWhisperCore/Tests/MWHotkeysTests/HotkeyComboTests.swift`
- edit `App/AppDelegate.swift` (`bindings(from:)` made internal; `onAction` ignores `.meeting`)
- edit `App/Settings/SettingsModel.swift` (`handle(.captured)`, `stored(_:)`, refusal)
- edit `App/Settings/HotkeysSection.swift`
- create `AppTests/HotkeyBindingsTests.swift`
- edit `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write the core tests:
   - `HotkeyComboTests.defaultMeetingComboParses`.
   - `HotkeyMatcherTests.meetingRawValue`.
   - `HotkeyMatcherTests.meetingChordFiresOnlyTheMeetingBinding`: with the three default bindings,
     ctrl+alt+left-cmd+m yields `.pressed(.meeting)` and no dictation press.

   Expected initial failure: `error: type 'BindingName' has no member 'meeting'`.
2. Write the app tests:
   - `HotkeyBindingsTests.meetingBindingComesFromConfig`.
   - `HotkeyBindingsTests.unparsableMeetingComboFallsBackToTheDefault`.
   - `HotkeyBindingsTests.meetingComboEqualToADictationComboFallsBackToTheDefault`.
   - `SettingsModelTests.capturingMeetingStoresMeetingHotkey`.
   - `SettingsModelTests.captureEqualToAnotherBindingIsRefused`: the error is "Already used by
     Record" and the config is unchanged.

   Expected initial failure: `error: 'bindings' is inaccessible due to 'private' protection level`.
3. Run `swift test --filter MWHotkeysTests` and `xcodebuild … test`. Confirm the failures.
4. Implement:
   - `BindingName.meeting = "meeting"`.
   - `bindings(from:)` becomes `static func` (internal), adds the meeting entry, and drops a
     duplicate to the default with a `Log.hotkey` warning.
   - `onAction` gets `case .pressed(.meeting), .released(.meeting): break`, with the comment
     "wired in Stage 24".
   - `SettingsModel` gains the `.meeting` cases and a duplicate-combo refusal that names the
     clashing field's title.
   - `HotkeysSection` gains `HotkeyCaptureField(title: "Meeting", binding: .meeting, model:)`.
5. Run both suites. Confirm pass and no regressions.

**Definition of done:**
- The binding exists, is configurable, and never collides with dictation.
- Presses are not yet acted on.

**Risks specific to this stage:** Pressing right ⌘ first while forming the chord matches the
modifier-only `cmd_r` dictation binding before `m` arrives; see *Risks and open issues*.

### Stage 23 — `MeetingWindowModel`: chooser and live transcript reduction

**Goal:** A host-tested `@MainActor` view model with two parts.
- **Chooser:** card availability, the 14.2 gate, price label, Start gating and message, and the
  first-remote note.
- **Live state:** merged speaker paragraphs, grey partial, markers rendered as text, inline notes,
  notes pane, connection and capture chips, elapsed and cost text, silence hint, merge
  confirmation text, and the note composer's first-keystroke time.

**Category:** TDD, plus a **non-TDD (config-only)** `project.yml` product entry.

**Design references:** §3 R2, R4, R7, R8, R9, R10, R26; §5.3 (App: `MeetingWindowController`
states); §5.6 (Silence hint); §5.7 (no key, macOS 14.0/14.1, rename to existing); §5.10; accepted
mockup `mockups/mockup-v4-meeting-window.html` (States 1–2).

**Touches:**
- edit `project.yml` (product `MWMeetingPipeline`)
- create `App/Meeting/MeetingWindowModel.swift`
- create `AppTests/MeetingWindowModelTests.swift`

**Steps (TDD):**
1. Non-TDD (config-only): `project.yml` gains `MWMeetingPipeline`.
2. Write test in `MeetingWindowModelTests`.

   Chooser:
   - `chooserShowsAboutPricePerHourForTheResolvedEngine`: "About $0.45 per hour".
   - `remoteCardIsDisabledBelow142`: "needs macOS 14.2".
   - `startIsDisabledWithoutAnyKey`: "Add a Speechmatics or AssemblyAI key under Keys."
   - `systemAudioNoteShowsOnlyBeforeTheFirstRemoteMeeting`.

   Live state:
   - `consecutiveSegmentsOfOneSpeakerMergeIntoOneParagraph`.
   - `paragraphHeaderIsNameAndFirstWordTime`.
   - `appendingASegmentTouchesOnlyTheLastParagraph`: incremental merge, 20 000 segments (R26).
   - `partialRendersAfterTheLastParagraph`.
   - `gapMarkerReadsTranscriptGapConnectionLost`.
   - `pausedMarkersReadPausedAndMacSlept`.
   - `notesAppearInlineAtTheirTimeAndInThePane`.
   - `noteTimeIsTheFirstKeystroke`.
   - `connectionChipReadsReconnectingWithAttempt`.
   - `captureChipReadsSystemAudioOff`.
   - `elapsedAndCostFormat`.
   - `silenceHintTextAndPaneURL`.
   - `renameToAnExistingNameAsksToMerge`: "Merge Speaker 3 into Marta?".

   Expected initial failure: `error: cannot find 'MeetingWindowModel' in scope`.
3. Run `xcodegen generate && xcodebuild … test`. Confirm the build failure.
4. Implement `MeetingWindowModel` (an `ObservableObject`) with `apply(_ event: MeetingEvent)`,
   chooser inputs (engines with keys, `PlatformInfo`, explained flag, pricing overrides) and
   formatting through `MeetingTime` and `Pricing.dollars`.
5. Run `xcodebuild … test`. Confirm pass and no regressions.

**Definition of done:** Every chooser and live-state text in mockup States 1–2 is produced by the
model and covered by a test.

**Risks specific to this stage:** None.

### Stage 24 — `MeetingCoordinator`, the meeting window (chooser and recording), menu, dictation lock, quit prompt

**Goal:** Meeting mode becomes reachable.
- The hotkey and *Start Meeting…* open the chooser.
- *Start* runs a meeting in a 920×620 window that shows the live transcript, notes pane, chips,
  Pause/Resume/Stop and rename popover.
- The menu switches to *Stop Meeting* / *Show Meeting…* while a meeting is active.
- Dictation presses show the lock notice.
- Quit asks before stopping a recording meeting.

**Category:** Hybrid.
- TDD for the routing policy, coordinator toggle semantics and menu rows.
- **Platform-only / UI wiring** for the window, views and composition root, verified by build and
  the manual check below.

**Design references:** §3 R1, R2, R7, R8, R9, R19; §5.3 (App: `AppDelegate`, `MenuModel`,
`StatusItemController`, `MeetingWindowController`); §5.6 (Start, Second hotkey press); §5.7
(window closed, quit); accepted mockup States 1–2; *Planning decisions taken* #22, #23, #32, #34,
#39.

**Touches:**
- create `App/Meeting/MeetingCoordinator.swift` (with a `MeetingControlling` protocol that
  `MeetingController` conforms to through an extension in the same file)
- create `App/Meeting/HotkeyRouting.swift` (pure routing decision)
- create `App/Meeting/MeetingWindowController.swift`
- create `App/Meeting/MeetingView.swift` (chooser and recording states)
- create `App/KeyedAnthropicClient.swift`
- edit `App/MenuModel.swift`, `App/StatusItemController.swift`, `App/AppDelegate.swift`
  (composition root, `onAction`, `applicationShouldTerminate`, `quit()`)
- create `AppTests/MeetingCoordinatorTests.swift` (with a stub `MeetingControlling`)
- create `AppTests/HotkeyRoutingTests.swift`
- edit `AppTests/MenuModelTests.swift`

**Steps (TDD):**
1. Write test in `HotkeyRoutingTests`:
   - `meetingPressTogglesTheMeeting`;
   - `dictationPressWhileAMeetingIsActiveShowsTheNotice`: "Dictation is off while a meeting is
     recording";
   - `dictationReleaseWhileActiveIsIgnored`;
   - `dictationPressWhenIdleGoesToDictation`;
   - `captureActionsStillReachSettings`.

   Expected initial failure: `error: cannot find 'HotkeyRouting' in scope`.
2. Write test in `MeetingCoordinatorTests`:
   - `firstPressOpensTheChooser`;
   - `pressWhileTheChooserIsOpenIsIgnored`;
   - `pressWhileRecordingStops`;
   - `pressWhilePausedStops`;
   - `pressWhileStoppingIsIgnored`;
   - `chooserCapturesTheFrontAppBeforeItOpens`;
   - `quitWhileActiveNeedsConfirmation`;
   - `confirmedQuitStopsWithoutSummary`.

   Expected initial failure: `error: cannot find 'MeetingCoordinator' in scope`.
3. Write test in `MenuModelTests`:
   - `initialOrder` is updated: *Start Meeting…* sits before *History...*.
   - `activeMeetingShowsStopAndShowMeeting`.
   - `endingTheMeetingRestoresStartMeeting`.
   - `lastAndCorrectRowsStillFollowMonth`.

   Expected initial failure:
   `✘ Test initialOrder() recorded an issue … Expectation failed: (model.items.map(\.title)) == […]`.
4. Run `xcodegen generate && xcodebuild … test`. Confirm the failures.
5. Implement the routing, coordinator and menu:
   - `HotkeyRouting.route(_:meetingActive:) -> Route`, where `Route` is `.dictation(HotkeyAction)`,
     `.meeting`, `.notice(String)`, `.settings(HotkeyAction)` or `.ignore`.
   - `MeetingCoordinator` (`@MainActor`):
     - `toggle()`, `show()`, `stop()`, `isActive`, `needsQuitConfirmation`;
     - it reads `NSWorkspace.shared.frontmostApplication` before the chooser opens;
     - it creates one `MeetingController` per window.
   - `MenuItem.Action` gains `startMeeting`, `stopMeeting` and `showMeeting`, and `MenuModel` gains
     `setMeetingActive(_:)`.
6. Implement the window and views:
   - `MeetingWindowController`: 920×620, hides on close.
   - `MeetingView`: the chooser cards; the recording header (title, chips, elapsed, cost); the
     transcript in a `LazyVStack` from `MeetingWindowModel`; the rename popover with merge
     confirmation; the notes pane, where Enter commits and Shift+Enter adds a newline; and
     Pause/Resume/Stop.
7. Implement the app shell:
   - `KeyedAnthropicClient` reads the key at call time, like `KeyedOpenAIClient`.
   - The `AppDelegate` composition root builds `MeetingDependencies`: the existing `audio` engine,
     `CoreAudioTapFactory()`, `EngineFactory()`, `KeychainStore`, `MeetingStore(directory:
     configDirectory/meetings)`, `KeyedAnthropicClient`, `UsageStore`, `PromptFiles`, the front-app
     closure, `meeting_user_name ?? NSFullUserName()`, `PlatformInfo()` and `SystemClock()`.
   - `onAction` goes through `HotkeyRouting`.
   - `applicationShouldTerminate` and `quit()` ask "A meeting is recording. Stop and quit?" and
     stop with `summarise: false` on confirm.
   - `StatusItemController`'s switch gains the three cases.
8. Run `xcodegen generate && xcodebuild … test`. Confirm pass and no regressions. Run
   `swift test`. Confirm green.
9. Integration-verified remainder, a manual check with a Speechmatics or AssemblyAI key in the
   Keychain:
   1. Launch the build.
   2. Press ⌃⌥⌘M; the chooser appears.
   3. Press it again; nothing happens.
   4. Pick *In the room*, then *Start*; the window records.
   5. Speak; paragraphs appear under your name or Speaker 1, with grey partials (check the Stage 6
      partial-text point).
   6. Type a note and press Enter.
   7. Pause, then Resume; a Paused line appears.
   8. Press a dictation hotkey; the notice shows.
   9. Close the window; the menu shows *Show Meeting…*.
   10. Choose Quit and cancel.
   11. Press ⌃⌥⌘M; the meeting stops.
   12. On macOS 14.2+, repeat with *Remote call* during a call and confirm the TCC prompt and the
       other participants' words.

**Definition of done:**
- R1 (except *Meetings…*), R2, R7–R9 and R19 are visible in the running app.
- Routing, toggle and menu rules are host-tested.
- Quit never loses a recording silently.

**Risks specific to this stage:** This is the largest UI stage. If review stalls, the window views
can be split out of the commit only by moving them to Stage 25, which would leave meeting mode
reachable without a window. Keep the stage whole.

### Stage 25 — Stopped state: summary panel, Summarise, edit and reassign, export, header rename

**Goal:** After Stop, or when a stored meeting is opened:
- the window shows the summary panel in every state, with *Summarise* when there is no summary;
- double-click edits a paragraph and right-click reassigns a segment;
- the header title is editable;
- Export writes the two Markdown files through save/open panels, and refuses a missing summary.

**Category:** Hybrid.
- TDD for the panel model, the exporter's names, writes and refusal, and the edit/reassign
  intents.
- **Platform-only / UI wiring** for the views and panels.

**Design references:** §3 R12, R13, R15, R17; §5.3 (App); §5.4 (save panel, Export both); §5.7
(export summary with none, title with `/` or `:`); accepted mockup State 3.

**Touches:**
- edit `App/Meeting/MeetingWindowModel.swift`
- edit `App/Meeting/MeetingView.swift`
- create `App/Meeting/MeetingExporter.swift`
- create `App/Meeting/ExportPanels.swift`
- edit `AppTests/MeetingWindowModelTests.swift`
- create `AppTests/MeetingExporterTests.swift`

**Steps (TDD):**
1. Write test in `MeetingWindowModelTests`:
   - `noKeyPanelReadsAddAnAnthropicKey`;
   - `failedPanelShowsTheReasonAndSummarise`;
   - `declinedPanelReadsSummaryDeclinedCategory`;
   - `emptyPanelReadsNothingWasTranscribed`;
   - `readyPanelSplitsTheFourSections`;
   - `metaLineShowsModelTimeTokensCostAndPartial`;
   - `summariseButtonExistsOnlyWithoutASummary`;
   - `editAndReassignAreOfferedOnlyWhenStopped`;
   - `reassignMenuListsEverySpeaker`;
   - `titleEditCallsRetitle`.

   Write test in `MeetingExporterTests`, using a temp directory:
   - `suggestedNamesUseTheSanitisedStem`: "Q3: plan/review" gives "Q3- plan-review - transcript.md";
   - `exportTranscriptWritesMeetingMarkdown`;
   - `exportBothWritesTwoFilesIntoTheFolder`;
   - `exportSummaryWithoutOneIsRefused`: "This meeting has no summary yet."

   Expected initial failure: `error: cannot find 'MeetingExporter' in scope`.
2. Run `xcodegen generate && xcodebuild … test`. Confirm the failures.
3. Implement:
   - Model additions for the panel, meta line and intents.
   - `MeetingExporter(generator:)` with `suggestedNames(title:)`, `transcript(_:)`, `summary(_:)
     throws`, `writeTranscript(_:to:)`, `writeSummary(_:to:)` and `writeBoth(_:folder:)`.
   - `ExportPanels`: `NSSavePanel` with a `.md` content type and the suggested name; `NSOpenPanel`
     in folder mode for *Export both*; `NSAlert` for the refusal.
   - `MeetingView`: the stopped state with the summary panel (Markdown via `AttributedString`),
     double-click edit, context-menu reassign, title field and Export ▾ menu.
4. Run both suites. Confirm pass and no regressions.
5. Integration-verified remainder, a manual check:
   1. Stop a meeting with an Anthropic key; the summary appears with the meta line.
   2. Without a key, the panel reads the no-key text; add a key, then *Summarise*.
   3. Edit a paragraph and reassign a segment. Confirm both persisted with the built binary's
      `meetings transcript <id>`; the list that reopens meetings arrives in Stage 26.
   4. Export both into a folder.
   5. `diff` the files against `mini-whisper meetings transcript <id>` output; they are identical.

**Definition of done:**
- R12's panel states, R13's edits, R15's header rename and R17's exports are all working.
- Exported text equals the CLI's.

**Risks specific to this stage:** None.

### Stage 26 — Meetings list window

**Goal:** A 680×480 Meetings window. It has:
- day-grouped rows with mode glyph, title, summary excerpt or italic first line, and meta line;
- hover actions Open / Export ▾ / Delete, with Export ▾ holding transcript, summary, both and
  *Delete audio (n MB)*;
- a footer with count, audio size, *Show in Finder* and *Start Meeting…*;
- title-bar search with up to two labelled snippets and a 150 ms debounce;
- rename, and an empty state naming the hotkey;
- the *Meetings…* menu item.

**Category:** Hybrid.
- TDD for `MeetingsListModel` (grouping, row texts, footer, debounce on `VirtualClock`-style
  injected sleeper, snippets, empty state, delete and rename intents) and the menu row.
- **Platform-only / UI wiring** for the window and view.

**Design references:** §3 R1 (*Meetings…*), R15, R16, R17; §5.3 (App: `MeetingsWindowController`);
§5.7 (audio deleted, missing index); §5.9 (search debounce); accepted mockup
`mockups/mockup-v4-meetings-list.html`.

**Touches:**
- create `App/Meetings/MeetingsListModel.swift`
- create `App/Meetings/MeetingsWindowController.swift`
- create `App/Meetings/MeetingsListView.swift`
- edit `App/MenuModel.swift`, `App/StatusItemController.swift`, `App/AppDelegate.swift`
  (`meetings` action, window ownership)
- edit `App/Meeting/MeetingCoordinator.swift` (`open(_:)` from the list)
- create `AppTests/MeetingsListModelTests.swift`
- edit `AppTests/MenuModelTests.swift`

**Steps (TDD):**
1. Write test in `MeetingsListModelTests`, using a stub reader built from `IndexEntry` values and a
   manual sleeper for the debounce:
   - `rowsGroupByDayNewestFirst`: Today / Yesterday / a weekday-date heading;
   - `rowShowsSummaryExcerptOrItalicFirstLine`;
   - `metaLineShowsDurationSpeakersCostAndAudioSize`;
   - `deletedAudioReadsAudioDeleted`;
   - `footerCountsMeetingsAndAudio`;
   - `searchWaits150MillisecondsBeforeRunning`;
   - `searchShowsUpToTwoLabelledSnippets`;
   - `emptyStateNamesTheHotkey`;
   - `exportMenuOffersDeleteAudioWithItsSize`;
   - `deleteAsksForConfirmationThenRemovesTheRow`;
   - `renameUpdatesTheRowAndTheStore`;
   - `missingIndexTriggersRefreshIndex`.

   Write test in `MenuModelTests`: `meetingsRowIsAlwaysPresent`.

   Expected initial failure: `error: cannot find 'MeetingsListModel' in scope`.
2. Run `xcodegen generate && xcodebuild … test`. Confirm the failures.
3. Implement:
   - `MeetingsListModel` over `MeetingStore`. Search runs `MeetingSearch` in a detached task after
     the debounce.
   - `MeetingsWindowController` and `MeetingsListView`, as in the mockup: `.searchable`, hover
     buttons, Export ▾ through `MeetingExporter` and `ExportPanels`, Delete with an `NSAlert`, and
     `NSWorkspace.activateFileViewerSelecting` for Show in Finder.
   - The menu gains `meetings` (*Meetings…*) in both states.
4. Run both suites. Confirm pass and no regressions.
5. Integration-verified remainder, a manual check:
   - Open *Meetings…* with at least two stored meetings.
   - Search for a word in a note and see the labelled snippet.
   - Rename a row; the window title follows when the row is opened.
   - Delete audio; the meta line reads "Audio deleted".
   - Delete a meeting; the folder is gone in Finder.
   - With no meetings, the empty state names ⌃⌥⌘M.

**Definition of done:**
- R16 and R17's list exports are working.
- *Meetings…* is in the menu (R1 complete).

**Risks specific to this stage:** None.

### Stage 27 — Settings → Meetings section

**Goal:** One Meetings section after History, with:
- the four engine rows with prices and key gating;
- Your name;
- Keep meeting audio;
- Open Privacy Settings…;
- the summary prompt editor (Save Prompt / Open in Editor / Restore Default);
- the Storage row (count, audio size, Show in Finder, Open Meetings…);
- under "Command line and agents", Command-line tool (*Install…*) and Claude Code (MCP command and
  *Copy*).

**Category:** Hybrid.
- TDD for every `SettingsModel` behaviour behind the rows.
- **Platform-only / UI wiring** for `MeetingsSection`'s layout.

**Design references:** §3 R4, R20, R22; §5.3 (App: `Section.meetings`, Claude Code row); §5.7
(stored engine without key); accepted mockup `mockups/mockup-v4-settings-one-pane.html`;
*Planning decisions taken* #35.

**Touches:**
- edit `App/Settings/SettingsModel.swift` (`Section.meetings` after `.history`, with title
  "Meetings" and symbolName `person.2.wave.2`; meeting rows; new defaulted `Dependencies` fields)
- edit `App/Settings/SettingsView.swift`
- create `App/Settings/MeetingsSection.swift`
- edit `App/AppDelegate.swift` (passes the installer, meeting stats and open-meetings closures into
  `SettingsModel.Dependencies`)
- edit `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write test in `SettingsModelTests`:
   - `overlaySectionSitsBetweenHistoryAndSound` is updated, and its `allCases` gains `.meetings`
     after `.history`.
   - `meetingsSectionTitleAndSymbol`.
   - `engineRowsShowPricesAndKeyGating`: "$0.45/h", disabled with "Add a Speechmatics key under
     Keys".
   - `selectingAnEngineWritesMeetingEngine`.
   - `storedEngineWithoutAKeyShowsDisabledAndTheFirstKeyedTierIsActive`.
   - `userNameDefaultsToTheFullName`.
   - `keepAudioToggleWritesConfig`.
   - `privacySettingsURLIsTheAudioCaptureAnchor`.
   - `summaryPromptSavesAndRestoresTheDefault`.
   - `storageRowCountsMeetingsAndAudio`.
   - `installReportsSuccessOrTheErrorText`.
   - `claudeCodeCommandFollowsInstallState`.
   - `copyPutsTheCommandOnThePasteboard`.

   Expected initial failure: `error: type 'SettingsModel.Section' has no member 'meetings'`.
2. Run `xcodegen generate && xcodebuild … test`. Confirm the failures.
3. Implement the model, section and wiring:
   - The model rows and actions use `Pricing.perHour`, `MeetingEngine.resolve`,
     `PromptFiles.restoreDefaultSummaryPrompt()`, `CommandLineToolInstaller` and the pasteboard
     closure.
   - `MeetingsSection` lays out the accepted mockup.
   - `SettingsView` gains `case .meetings: MeetingsSection(model: model)`.
   - `AppDelegate` wires the closures.
4. Run both suites. Confirm pass and no regressions.
5. Integration-verified remainder, a manual check:
   1. Open Settings → Meetings; it matches the mockup.
   2. Pick each engine row; `config.json` updates.
   3. *Restore Default* resets the prompt.
   4. *Install…* shows the admin prompt and then "Installed".
   5. `which mini-whisper` resolves; `/usr/local/bin/mini-whisper` is a regular file (`test ! -L`).
   6. The Claude Code row copies `claude mcp add --transport stdio mini-whisper -- mini-whisper mcp`.

**Definition of done:** R20 and R22 are visible and working, and every model behaviour is
host-tested.

**Risks specific to this stage:** None.

### Phase H — Documentation

### Stage 28 — README and CHANGELOG

**Goal:** Document the feature: permissions, engines and per-hour prices, storage and retention,
consent responsibility, known limitations, and CLI/MCP usage. Record the release notes under
`[Unreleased]`.

**Category:** Non-TDD (config-only). Documentation has nothing host-assertable; it is verified by
the checks below.

**Design references:** §3 R23; §5.8 (consent, retention); §5.11; §7 (overlapping speech,
diarizer merges); §9 (CHANGELOG items, README "Meetings" section).

**Touches:**
- edit `README.md`
- edit `CHANGELOG.md`

**Steps (non-TDD):**
1. In `README.md`:
   - Add a "Meetings" section after "Corrections and vocabulary", covering:
     - hotkey and menu;
     - remote vs in-room;
     - the four engines with prices per hour: $0.45, $0.80, $0.27 and $0.57, the AssemblyAI figures
       including the $0.12/h diarization;
     - the Anthropic key and summary;
     - storage path and file layout;
     - Keep meeting audio and per-meeting deletion;
     - "you are responsible for consent to record";
     - limitations: overlapping speech in one stream, a diarizer merge cannot be split, English
       only, chord with left ⌘;
     - CLI usage (`mini-whisper meetings list|transcript|summary|search`) and the `claude mcp add`
       command.
   - "Permissions" gains System Audio Recording (macOS 14.2+).
   - "Privacy" gains the meetings folder.
2. In `CHANGELOG.md` `[Unreleased]`:
   - **Added:** meeting mode; the System Audio Recording permission; the AssemblyAI and Anthropic
     keys; AssemblyAI as a dictation engine; the CLI and MCP server.
   - **Changed:** the Speechmatics rate is now 0.0075 per minute, so new usage costs more and past
     totals are unchanged.
3. Verify:
   - `grep -n "## Meetings" README.md` returns a line.
   - `grep -n "0.0075\|System Audio Recording\|mcp" CHANGELOG.md` covers each item.
   - Every price in the README equals `Pricing.perHour` for its tier.
   - No key or secret-looking string appears in either file.

**Definition of done:** R23's five topics (permission, engines, prices, storage, consent) and the
CLI/MCP usage are in the README, and the CHANGELOG lists every item in design §9.

**Risks specific to this stage:** None.

## Cross-cutting concerns

**Security.**
- **Secrets.**
  - Keys live only in the Keychain (Stage 1 adds the two accounts).
  - The AssemblyAI key travels only in `Authorization` (Stage 6), and the Anthropic key only in
    `x-api-key` (Stage 3). `KeyedAnthropicClient` reads the key at call time (Stage 24).
  - Logs carry sizes, status codes, close codes and attempt numbers only. Stages 3 and 15 assert
    this with `CapturingLogSink`.
  - Fixtures use `placeholder-not-a-real-key`.
- **Untrusted input.**
  - The transcript and notes enter the summary request as delimited data under a system prompt
    that treats them as content (Stage 16).
  - MCP input is decoded into typed structs, and strings over 10 000 characters are rejected
    (Stage 20).
  - CLI and MCP ids are validated as a UUID or an ≥ 8-hex prefix before any lookup. Paths are
    built only from a `UUID` (Stages 11, 19).
- **Read-only agents.** `MeetingsCLI` and `MCPServer` take `any MeetingReading`, so no write method
  is reachable. `MWAgentAccess` links only `MWMeetings` and `MWSupport` (Stage 19). The reader's
  index rebuild never writes (Stage 11).
- **Files.** Meeting folders are 0700 and files 0600, including `audio.m4a` (Stages 9, 11).
- **Installer.** It writes a fixed-content wrapper script, never a symlink. The baked path is
  single-quoted with `'\''` escaping, and no user input reaches the script (Stage 21).
- **Ordering.** The meeting UI and the dictation lock land together in Stage 24, after the
  read-only reader and id validation (Stages 11, 19, 20). The installer row (Stage 27) lands after
  the script builder's quoting tests (Stage 21). No stage opens a window where an unprotected path
  is reachable.

**Performance.**
- Memory is bounded: the meeting listener never accumulates (Stage 8), and the system ring holds
  2 s (Stage 13).
- Segments and notes stream to disk per line (Stage 11).
- The tick runs off the main actor in `MeetingAudioPath`; only segments, partials and one-second
  ticks hop to it (Stage 17).
- The view model's paragraph merge is incremental (Stage 23).
- Search is debounced 150 ms and runs off the main actor (Stage 26).
- AssemblyAI chunks are accumulated to 100 ms (Stages 4, 6).

**Observability.**
- `Log.meeting` (Stage 1) is used for:
  - start/stop, mode and engine (Stage 17);
  - session open/close, close code, attempt and rollover (Stage 15);
  - pause/resume reason and device change (Stage 18);
  - tap start/stop and default-output change (Stage 10);
  - summary size, status and tokens (Stage 3);
  - skipped jsonl lines (Stage 11);
  - export destination path (Stage 25);
  - CLI/MCP command names (Stages 19, 20).
- The window shows connection and capture chips, elapsed time, cost and summary state (Stages 23,
  25).
- Usage rows update on Stop (Stage 17).

**Compatibility / migration.**
- The five new config keys are optional and round-trip (Stage 1); the Python app preserves them as
  unknown keys.
- Dictation is unchanged: segments never reach the assembler (Stage 4), and undiarized
  Speechmatics is byte-identical, guarded in Stage 5.
- The Speechmatics rate change affects new usage only (Stage 2).
- On macOS 14.0/14.1 everything but remote mode works (Stages 7, 10, 23).
- Every intermediate commit leaves the app shippable. Meeting mode is unreachable until Stage 24.
  The meeting hotkey is bound but ignored between Stages 22 and 24.

## Verification

After Stage 28, on macOS 26 with Speechmatics, AssemblyAI and Anthropic keys in the Keychain:

1. **Automated.**
   - `cd Packages/MiniWhisperCore && swift test` is green: baseline + MWHistoryTests fix + every
     new suite.
   - `xcodegen generate && xcodebuild … test` is green.
   - `MW_INTEGRATION=1 swift test --filter "SystemAudioTapIntegrationTests|AVAudioEngineBackendIntegrationTests|AnthropicIntegrationTests|MeetingEngineLiveTests"`
     passes, with `ANTHROPIC_API_KEY`, `SPEECHMATICS_API_KEY` and `ASSEMBLYAI_API_KEY` exported in
     that shell only.
2. **Design §5.12 acceptance.** Run a remote Zoom call of a few minutes. It produces:
   - a transcript with your name and Speaker 1..N;
   - a note at its time;
   - a summary on Stop;
   - two exported files matching `mockups/mockup-v4-export-markdown.html`'s layout;
   - a Meetings row with its cost;
   - a Today row increment;
   - `mini-whisper meetings transcript <id>` printing the same Markdown (`diff` against the
     exported file is empty).
3. **Requirement spot checks.**
   - R9: Pause/Resume and sleep (close the lid) give Paused lines.
   - R10: switching Wi-Fi off for 20 s gives "Reconnecting (n)", then a gap line.
   - R11: rename Speaker 2 to Marta and see every paragraph update.
   - R13: edit and reassign after Stop, then reopen.
   - R16: list search snippets.
   - R19: a dictation hotkey during a meeting shows the notice.
   - R20: the Settings → Meetings rows.
   - R21: `claude mcp add --transport stdio mini-whisper -- mini-whisper mcp`, then ask Claude Code
     to list meetings.
   - R22: `test -f /usr/local/bin/mini-whisper && test ! -L /usr/local/bin/mini-whisper`.
   - R28: `config.json` opens in the Python app's config loader unchanged.
4. **AssemblyAI dictation (R5).** Select AssemblyAI under the dictation engine and dictate one
   sentence with a vocabulary term.

## Risks and open issues

| Risk | Mitigation |
|---|---|
| **Red baseline.** `MWHistoryTests` crashes on a date time-bomb (`HistoryStoreTests.swift:227-228`) | Fix before Stage 1 via `/bug-submit` → `/bug-fix`: inject a fixed `now` or derive fixture dates from it. `/feature-implement` halts on a red suite otherwise |
| Pressing right ⌘ first while forming ⌃⌥⌘M fires the modifier-only `cmd_r` dictation binding | Stage 22 tests the left-⌘ chord; README (Stage 28) says to use left ⌘. A matcher change for right ⌘ would alter dictation and is out of scope |
| AAC at 16 kHz rejected by the system encoder | Stage 9's first test shows it immediately. Set a 32 kbit/s bit rate. A different sample rate would be a design change and halts |
| `NSAppleScript` admin `do shell script` blocked under hardened runtime | Stage 21 keeps the run behind a `Result`, and the row shows the error. The Claude Code row falls back to the full binary path (design §7) |
| AssemblyAI silently ignores unknown or misspelt query parameters | URL contract tests (Stage 6). The opt-in integration run and the Stage 24 manual check confirm diarized labels actually arrive |
| AssemblyAI word times in milliseconds, `expires_at` in seconds | Explicit unit tests in Stage 6 |
| Mic gate thresholds tuned only on synthetic frames | Thresholds are named constants (Stage 13). The 70 % label rule and voice processing absorb errors, and reassignment fixes the rest. Tune from the Stage 24 manual check if needed |
| Process-tap behaviour across macOS 14.2–26 | Opt-in integration test (Stage 10). Mic-only fallback on any tap error (Stage 17). Rebuild on output change |
| 28 stages; Stages 6, 17, 18 and 24 are large | Each is cohesive and atomic where noted. Stage 6 is atomic by necessity; Stages 17/18 split the controller by concern |
| Golden files copied by hand from HTML | Stage 12 decodes entities and compares byte-for-byte. The Stage 25 manual `diff` re-checks against the CLI |

## Planning decisions taken

**Factual corrections.** The design has been corrected in place for each of these.

1. **Speechmatics past totals.** §5.11 and §7 said past Speechmatics totals recompute after the
   price change. `UsageStore` stores `costUSD` at write time, so only new usage bills at 0.0075.
2. **Usage call name.** §5.6's `UsageRecording.record(...)` is `add(_:)` (`MWUsage/UsageStore.swift:7`).
3. **Speechmatics `model` field.** §5.3 said `"model"` replaces `operating_point`. The adapter sends
   neither today; `model` is the current field and `operating_point` its deprecated alias.
4. **Settings names.** The `sk-ant-` check belongs in `SettingsModel.saveKey(_:value:)`, where the
   `sk-` check lives, not in `mask(of:account:)`. `Section`'s property is `symbolName`, not `icon`.
5. **Segment routing (internal contradiction).**
   - §5.3 routed `.segment` into `assembler.addFinal`, while the adapters also emit `.final`, which
     would double the text.
   - The adapters' prose and §5.11's "dictation unchanged" win: `.segment` goes only to
     `sink.onSegment`.
   - §5.3, §5.11 and §5.12 are corrected.
6. **Session-limit signal.** §5.3 had `SessionSupervisor` read `AssemblyAIAdapter.expiresAt`, but
   the supervisor only sees `any StreamingEngine`.
   - Added `Emission.sessionLimit(SessionLimit)` (`.expiresAt(Date)` / `.warning`) and
     `TranscriptSink.onSessionLimit` with a default no-op.
   - The Speechmatics trigger is the `Warning` with `type: "session_timeout"`.
7. **Close codes.** Surfaced as `WebSocketConnectionError.closed(code:reason:)` from
   `URLSessionWebSocketConnection`, so they reach `onEngineError` and the log.
8. **AssemblyAI chunk size.** AssemblyAI requires 100 ms chunks; the capture tap delivers about
   21 ms. `EngineAdapter.minimumChunkSeconds` (default `nil`) lets `WebSocketEngine` accumulate.
   No other adapter changes.
9. **Audio tick feed.** §5.6 said the supervisor feeds "int16 PCM via the adapter's
   `encodeChunk`". It actually feeds 16 kHz float `AVAudioPCMBuffer`s to `StreamingEngine.feed`,
   and `WebSocketEngine` converts.

**Planning choices.**

10. **`MeetingEngineProviding`.** It is a new protocol in `MWStreaming` that `EngineFactory`
    conforms to, rather than widening `EngineProvider`, so dictation fakes stay unchanged.
11. **`HintReport` row.** The AssemblyAI row lands in the same stage as `EngineName.assemblyai`,
    because `HintReportTests` enumerates `EngineName.allCases`. The design missed this site.
12. **`MWMeetings` dependency (internal contradiction).** §5.1 said `MWMeetings` depends on
    `MWSupport` only, but §5.2's `Meeting.engine: MeetingEngine` lives in `MWConfig`. `MWConfig` is
    added. It links no audio or networking, so §5.8's CLI claim holds; §5.1 is corrected.
13. **Diarization seconds (internal contradiction).** §5.3/§5.12 recorded AssemblyAI diarization
    seconds as a second `streamedSeconds` key, which doubles the Today minutes. R18 wins: seconds go
    under the pricing key only, and `costUSD` includes the add-on. §5.3 and §5.12 are corrected.
14. **`SummaryPromptProviding` location.** It lives in `MWConfig` beside `PromptFiles` rather than in
    `MWMeetingPipeline`. The contract is unchanged, and fakes need no new edge.
15. **`PlatformInfo`.** It gains a defaulted `osMinor`, so all six construction sites compile
    unchanged. `supportsSystemAudio` is tested in `MWStreamingTests`, where the type lives, not in
    `AppTests`.
16. **`AudioCapture.meetingEvents`.** It is a separate `AsyncStream<MeetingAudioEvent>`
    (`.systemWillSleep`, `.deviceChanged`) because `events` already has one consumer
    (`DictationController`). The engine reapplies voice processing on every reinstall.
17. **Audio protocols.** `SystemAudioTapping`, `SystemAudioTapFactory` and `AudioFileWriting` live
    in `MWAudio` with their implementations, so the shared fakes in `MWTestSupport` need no new
    edge.
18. **Summary request split.** `Summarizing` lives in `MWTranscription`. `AnthropicClient` owns
    model, `max_tokens`, effort, the fallbacks header, the 180 s timeout and no-retry.
    `Summariser` owns prompt composition, delimiters, truncation and billing. Each is tested where
    it lives.
19. **`MeetingStore` reads.** `MeetingStore` is an actor whose `index()` and `load(_:)` are
    `nonisolated` file reads, so it satisfies the synchronous `MeetingReading`. A reader rebuilds a
    missing index in memory only (R21). The actor's `refreshIndex()` persists it.
20. **Shared fixtures.** `MWTestSupport` gains an `MWMeetings` dependency for the shared
    `MeetingFixtures` builder.
21. **Meeting hints.** `MWMeetingPipeline` also depends on `MWCorrections`. Meeting hints are
    `HintResolver.resolve(CorrectionSnapshot(config:), bundleID: nil)`.
22. **Opening stored meetings.** `MeetingController.open(_:)` loads a stored meeting into
    `.stopped`, and `retitle(_:)` serves R15, with one controller per window. The list renames and
    deletes through `MeetingStore` directly. *Delete audio* sits in the Export ▾ menu, per the
    mockup.
23. **Quit stop.** `stop(summarise: Bool = true)` is a defaulted parameter used by the quit path
    (§5.7 "Stop runs without summary").
24. **Backoff reset.** The attempt counter resets when a new session delivers its first partial,
    segment or session-limit callback.
25. **Float resampling.** `PCMConverter.resample(_:) -> [Float]` is added for the 16 kHz float
    path the gate and mixer need.
26. **"Partial" summary note.** §5.5's "partial" meta note is derived when displayed, as
    `Summariser.isTruncated(_:)` (transcript body over 600 000 characters). `Summary` keeps exactly
    the design's fields, with no stored flag.
27. **`MeetingEvent.error(String)`.** Carries §5.7's write-error message.
28. **Default title format.** `MeetingTitle` formats `d MMM yyyy HH:mm` with `en_US_POSIX` in the
    user's time zone, so tests are deterministic.
29. **CLI exit codes.** A summary request for a meeting without one exits 2 with one stderr line,
    like an unknown id. Usage errors also exit 2, with usage on stderr.
30. **MCP versions.** `initialize` with a version other than 2025-11-25/2025-06-18 is answered with
    2025-11-25.
31. **Unlabelled words.** A `nil` (`UU`) provider label is treated as its own provider key per
    session.
32. **`KeyedAnthropicClient`.** It lives in `App/` and reads the key at call time, mirroring
    `KeyedOpenAIClient`.
33. **Bindings.** `AppDelegate.bindings(from:)` becomes internal so `AppTests` can cover the
    meeting fallback. The duplicate-combo refusal names the clashing field's title.
34. **App file layout.** App files go under `App/Meeting/` (window) and `App/Meetings/` (list).
35. **No General-section change.** §5.1's App row mentions "General rows", but no requirement or
    accepted mockup has one; every meeting setting is in Settings → Meetings.
36. **Golden files.** They reproduce the export mockup's text. The fixture stores `durationSeconds`
    2932 directly.
37. **Fixtures directory.** `MWMeetingsTests` declares `resources: [.copy("Fixtures")]` when the
    target is created, seeded with the corrupt-jsonl fixture. Stage 12 then adds goldens without a
    `Package.swift` edit.
38. **Installer directory.** The installer script runs `mkdir -p /usr/local/bin`; a fresh Apple
    silicon Mac may lack it.
39. **Quit confirmation.** `quit()` (the menu path) and `applicationShouldTerminate` (⌘Q, logout)
    both confirm before stopping a recording meeting.
40. **Concurrency.** The audio tick runs on the tap thread in a lock-guarded `MeetingAudioPath`.
    `MeetingController` is `@MainActor`, like `DictationController`.
41. **Stage ordering.** The meeting hotkey (Stage 22) lands just before the UI stages, so the bound
    but ignored interval is short. Meeting mode is unreachable until Stage 24; that is the design's
    no-flag rollout.
42. **Integration tests.** Unit tests never sleep. Opt-in integration tests stream audio at
    real-time pace where a provider needs it, and wait on results with a deadline rather than a
    fixed sleep. The two-speaker fixture is synthesised with `say`, so no real person's voice is
    committed.
43. **Concurrent app tests.** `xcodebuild … test` runs in separate worktrees with separate `.dd`
    derived data are not a shared test resource. AppTests use temp directories and fakes, and app
    startup is skipped under tests (`LaunchArguments.isRunningTests`).
44. **Parallel batches.** The cut is B2 (Stages 2, 3, 9, 10), B5 (Stages 5, 12), B11 (Stages 14,
    15, 16, 20) and B20 (Stages 27, 28). Every other stage is serial because it:
    - adds a target (Stages 11, 13, 19);
    - changes a shared protocol or enum (Stages 1, 4, 6, 8, 22);
    - adds a product dependency (Stages 21, 23);
    - or consumes the previous stage.
45. **Config encoding.** `meeting_hotkey`, `meeting_keep_audio` and
    `meeting_system_audio_explained` are written always, like the other defaulted keys.
    `meeting_engine` and `meeting_user_name` are written only when set.

## Deviations from the design

None — plan matches design v4 exactly.

## Deviations from plan

- **Stage 1.** `PromptFiles` writes the summary prompt with `write(summaryPrompt:)`, matching
  `write(cleanupPrompt:)` and `write(transcribeInstructions:)`, not `writeSummaryPrompt(_:)`. It
  also exposes `summaryPromptURL` beside `cleanupPromptURL` for Stage 27's *Open in Editor*.
  `Log.meeting` is a `LogCategory(name:)` like the six existing categories; `LogCategory` wraps
  `Logger`. `KeychainStore`'s doc comment no longer counts accounts.
- **Stage 2.** `Pricing.perHour` rounds to the cent; unrounded, Speechmatics Enhanced is 0.79998
  and the plan's `== 0.80` fails. `meetingCost` rounds to six decimals like `dictationCost`, which
  now shares the private `tokenCost` and `roundedToMicros` helpers.
- **Stage 3.** A `refusal` with a null `stop_details.category` reports `refusalCategory`
  `"unspecified"`. Request parameters are public static constants on `AnthropicClient`, like
  `OpenAIClient`. Request/response handling mirrors `OpenAIClient`'s private `send`; sharing it
  would have meant editing `OpenAIClient.swift`, outside the stage.
- **Stage 9.** The encoder accepts 16 kHz mono AAC at its default bit rate (≈ 24 kbit/s,
  ≈ 13.6 MB/h, not design §5.9's ≈ 29 MB/h), so no bit-rate key is set; it rejects 64 kbit/s.
  Writing after `finish()` throws the new `AACFileWriterError.finished`.
- **Stage 10.** `SystemAudioTap.init(excluding:)` takes no clock: nothing in the tap is timed.
  The integration test plays its fixture with `/usr/bin/afplay` in a child process, because the
  tap excludes the test's own PID. The aggregate device holds only the tap and carries a name and
  UID `com.ips.mini-whisper.system-audio.<tapUID>`. New `SystemAudioTapError` names the failing
  Core Audio call and its `OSStatus`. With no Core Audio process object for our PID, nothing is
  excluded.
- **Stage 5.** Speechmatics punctuation results carry a `speaker`, so punctuation joins the
  preceding word whatever its label. `.segment` is emitted only when diarizing;
  `.sessionLimit(.warning)` always, which dictation sinks ignore. The diarized fixture ends with a
  `UU` result, giving a third, `nil`-speaker segment.
- **Stage 12.** `MeetingMarkdown.transcript`/`summary` take a defaulted `timeZone` (goldens use
  UTC; `summary_at` is always UTC). `northwind()` gains Alex's opening segment so speaker order
  matches the mockup's `[Alex, Marta, Priya]`; the transcript golden therefore adds that paragraph
  and the 00:12:40 / 00:27:15 notes, and drops the mockup's trailing "…". `transcriptBody`
  excludes notes (Stage 16 sends them in `<notes>`), so `Summariser` must test
  `segments.isEmpty`, not the body. `TitleSanitizer` also provides
  `transcriptFileName`/`summaryFileName`. Search: one hit per meeting in input order, at most two
  snippets ordered transcript → notes → summary, ~40 characters each side.
- **Between batches (not a stage).** `FakeWebSocketConnection` lost a wakeup when a `send` landed
  between `receive()` choosing to wait and parking, hanging `replay` tests ≈ 1 run in 15. Fixed
  in `fix: …` with a 20 000-iteration regression test.
- **Stage 4.** `WebSocketConnectionError` is now `LocalizedError` and `Equatable`, so `AnyError`, and
  with it the engine's failure log, names the close code. An empty close reason is `nil`.
  `RecordingSink.revisions` keeps one array per callback. `WebSocketEngine` sends everything
  accumulated once the minimum is reached, not exact minimum-sized slices.
- **Stage 11.** Every meeting file shares `MeetingCoding.encoder()`/`decoder()`: whole-second ISO 8601
  dates, as `history.jsonl` uses, so dates round-trip at second precision. `audioURL(_:)` and
  `directory` are `nonisolated`. `refreshIndex()` always rescans and returns the entries.
  `rewriteSegments` and `deleteAudio` also refresh the index entry; `delete` tolerates a missing
  folder. The index is newest first; its `costUSD` adds the summary's cost, and its `excerpt` is the
  summary's first sentence, both per the list mockup. `northwind()` gives Alex (the user) id 0,
  Marta 1, Priya 2, segments without words, `endedAt` 15:19:20Z. Its notes at 00:12:40 and 00:27:15
  precede the mockup transcript's first paragraph (00:39:02), so Stage 12's transcript golden shows
  them first.
- **Stage 6.** Checked against AssemblyAI's v3 docs. A short turn's documented label is `PENDING`;
  it maps to `nil` with `UNKNOWN` and a missing label. The provider closes a session on a chunk
  under 20 ms (3007), which the flushed remainder can be, so `encodeChunk` pads it with silence.
  `Error` frames are `{"type":"Error","error_code","error"}`; any `error` field throws. Query values
  are percent-encoded to unreserved characters only, so `&` and `+` in a keyterm survive. A keyterm
  over 50 characters is skipped before the cap counts, as the new `SkipReason.termTooLong`
  ("is over 50 characters"), since `.wordTooLong`'s Settings text names 4000. `.segment` is
  emitted for dictation too (design §5.3); dictation sinks ignore it. Exhaustive `EngineName`
  sites outside Touches also changed: `ConfigCodingTests`, `HintMeasurementTests`,
  `PricingTests` (an `assemblyai` rate row) and `CorrectionsEditorModelTests`' label list.
- **Stage 7.** `makeMeeting` is an `EngineFactory` extension in `EngineFactory.swift`, so the
  private `webSocketEngine` helper stays private. AssemblyAI rejects audio faster than real time,
  so `ClipPlayback.play` gains `realTime: Bool = false` for the live tests. The fixture is
  Samantha and Daniel alternating four sentences with 0.6 s gaps (21.3 s). Stage 6's two
  never-mutated `var`s in `CloudAdapterTests` are fixed here.
- **Stage 8.** An idle stop that fires while held re-arms for the same duration instead of being
  dropped, so it applies once the hold is released and the tests have a barrier. Releasing the hold
  schedules nothing: a meeting that started a stopped engine must `scheduleIdleStop` or `stop()`
  after `holdRunning(false)` (Stage 17), or the microphone stays open. `setVoiceProcessing` always
  forwards; `ensureRunning` reapplies only `true`, before the tap, logging rather than throwing on
  failure. `AVAudioEngineBackend` skips an unchanged setting and restarts even when the toggle
  fails. While held, a device change yields no `.stopped` on `events`. `FakeAudioCapture.feed`
  reaches the meeting listener too, as the real tap does; `FakeAudioBackend` gains
  `tapInstallCount`.
- **Stage 13.** The noise-floor window starts as 10 s of zeros (the silence before the meeting):
  over a part-filled window a steady voice becomes its own floor within a frame, so for the first
  ~9.5 s only −45 dBFS applies. A span closes at the end of its last loud frame, not after the
  300 ms release; the open span is in `View.spans`. `resample` is unclipped. The silence-hint peak
  is `SystemAudioRing.peakSinceLastCall()`, reset on read. The module-map row also lists
  `SystemAudioRing`, and `Package.swift`'s header names both pipelines.
- **Stage 19.** `MeetingID.resolve(_:in:)` takes the `MeetingReading` itself, so validation
  provably precedes the index read; a full UUID must also be in the index. Prefixes may carry the
  UUID's hyphens and match case-insensitively; ASCII hex only. `MeetingIDError` gains
  `.unreadable(reason)` for an index read failure and carries the input in each case, with the
  stderr text as its `errorDescription`. `MeetingsCLI` gains a defaulted `timeZone`; `out`/`err`
  receive text verbatim, newline-terminated, so `transcript` output is byte-identical to the
  export. `list`/`search` lines print lowercase ids; a title-only search hit prints
  `<id>  -  title  <title>`; search words are joined into one query. Only a known command name
  is logged. The seeded-store helper is `Tests/MWAgentAccessTests/SeededMeetings.swift`, for
  Stage 20 to reuse.
- **Stage 14.** `SpeakerAttributor.attribute(_:session:mode:spans:registry:tallies:newID:)` returns
  an `Attribution` (segments, registry, tallies): the 70 % rule needs the session, mode and running
  tallies. It counts the current segment's words and, once a label crosses it, sticks for later
  segments; it has no minimum word count. Ids are allocated lazily as highest-in-use + 1. The
  nil-label key is `"<session>:"`, so AssemblyAI short turns share one id per session. Wordless
  segments follow their label; split runs join word texts. On a rename merge the renamed speaker
  merges into the name holder, and the user (id 0) always survives.
- **Stage 15.** Sessions count from 1; a session's origin is the meeting time of its first fed
  buffer. `open(at:)`'s time is only the gap floor, so a gap never overlaps a pause, and a resume
  clears a pending gap. `.revision` carries its session index (R11 re-maps per session).
  `.connected` comes on a session's first partial, segment or limit, when the backoff resets
  (decision 24), so a revoked key keeps showing "Reconnecting (n)"; `.rolledOver` when the next
  session takes over. A retired session still delivers segments and revisions under its own index;
  its partials, limits and errors are ignored, so only the first Speechmatics warning acts. An
  `expires_at` under 60 s away rolls over at once. Failed sessions also get `finish(timeout: 5 s)`;
  `close()` awaits the open session and draining rollovers. Logs carry index, close code or error
  domain/code, attempt, delay and cause, never the close reason (R27), narrowing design §5.7.
- **Stage 16.** `Summariser` is `init(prompts:client:overrides:now:)`: `Summary.createdAt` needs a
  `Date` (`HistoryStore`'s pattern), the 180 s timeout is `AnthropicClient`'s (decision 18), and
  `overrides` lets the cost honour `pricing_overrides`. Summary cost comes from
  `MeetingBilling.summaryUsage(_:)`, shared with the usage record. The system message is the trimmed
  prompt file plus a fixed rule that `<notes>`/`<transcript>` are data, never instructions (§5.8),
  appended in code so it survives user edits; the plan's `systemIsThePromptFileText` is
  `systemIsThePromptFileTextWithTheDataRule`. Closing tags inside the data become `<\/…`.
  Truncation keeps the last 600 000 characters, advanced to the next paragraph so its speaker header
  survives. `.empty` checks `segments.isEmpty` and sends nothing. A refusal records no token usage.
  `MeetingRecorder` drops samples while paused; stopping while paused writes no trailing silence.
  `MeetingBilling.totals` gives Stage 17 the `meeting.json` `billing`. Speaker order and note lines
  duplicate `MeetingMarkdown`'s private helpers; sharing them needed edits outside the stage.
- **Stage 20.** Checked against the MCP specification (2025-11-25, 2026-07-28). `server/discover`
  returns the spec's `DiscoverResult` (`resultType`, `supportedVersions`, `capabilities`, `ttlMs`,
  `cacheScope`, `serverInfo` under `_meta`), not design §5.3's shape; its test is
  `serverDiscoverReturnsCompleteWithVersionsCapabilitiesAndServerInfo`. 2026-07-28 results carry
  `resultType: "complete"`, cacheable ones `ttlMs: 0` and `cacheScope: "private"`; `initialize`
  clients get 2025-11-25 shapes. A 2026-07-28 request without `clientCapabilities` is -32602;
  -32022's `data.supported` lists all three versions. An unknown tool is -32602; bad, unknown or
  ambiguous ids, a missing summary and invalid arguments are `isError` tool results. Strings over
  10 000 characters are -32602 (a string request id -32600). `search_meetings`' `limit` defaults to
  50, clamped to 1…50. Batches are -32600; a reply to an unreadable id omits `id`; U+0085, U+2028
  and U+2029 are escaped. Only method and known tool names are logged. The `meeting`/`index`/`json`
  helpers copy `MeetingsCLI`'s; sharing them needed edits outside the stage. Stage 21 must flush
  stdout after each write.
- **Stage 17.** `MeetingController` is `init(deps:config:)`: `MeetingDependencies` carries the
  `clock`, a wall-clock `now` (start, end, note and summary stamps) and `makeAudioWriter`, and no
  `platform`, since `CoreAudioTapFactory` already returns nil below 14.2. `userName` is the
  fallback when `meeting_user_name` is blank. `MeetingEvent` has no `captureHint`: nothing produces
  one; the capture chip reads `.systemAudio`. `SessionSupervisor.feed` returns a discardable `Bool`
  so only audio a session took is billed (`feedReportsWhetherASessionTookTheBuffer`). Start creates
  the folder and recorder before touching capture and undoes both on failure. Stop closes the
  session, releases capture and arms `scheduleIdleStop(idle_stop_seconds)` (Stage 8), then drops the
  supervisor and awaits its event stream so drained segments land before `meeting.json`. Audio-path
  time counts 16 kHz samples from the first buffer; elapsed and duration read the clock. A recorder
  write error ends the audio file. `summarise()` checks for an empty transcript before the
  Anthropic key. The test harness (`MeetingHarness`) lives in `MeetingControllerTests.swift` for
  Stage 18; a second session comes from a Speechmatics warning rollover.
- **Stage 18.** `resume()` does not throw: nothing in it can fail (a recorder error ends the
  audio file, as in Stage 17). Pause writes `meeting.json` with the marker open (end = start) and
  Resume or Stop closes it; Resume waits for the pause's session close so a quick Resume is not
  closed with it. Resume and Stop first move the audio time up to the clock, so a sleep's silence
  is in the file and the marker. A device change moves it up likewise and records the jump, so the
  open session's later words land after the gap; the output-device rule measures time since the
  last tap buffer. The silence hint needs mic speech and no tap sample above −60 dBFS by meeting
  second 60. The write-error test makes `segments.jsonl` read-only (an open handle or a directory
  mode does not stop writes to an existing file); every segment stays in memory for the summary,
  so the 10 000 cap is not applied, and one loop serialises appends and rewrites. Revisions skip
  segments whose speaker is not their label's (the gate gave them to the user);
  `pinnedSegmentIsNeverRevised` calls the internal `MeetingController.revise` through
  `@testable`, since nothing pins a segment while a session is open. Rename and titles are trimmed;
  reassignment to an unknown speaker is ignored. Added `stopWhilePausedClosesThePauseMarker`.
- **Stage 21.** `AgentCommand.run()` is `@MainActor` (it reads `AppDelegate.configDirectory`).
  Replies go through `FileHandle`, whose writes are unbuffered, so no explicit flush; checked with
  two `initialize` replies read while stdin stayed open. The install command runs `rm -f` before
  writing, so a symlink already at `/usr/local/bin/mini-whisper` is replaced, not written through
  as root; it writes the script with `printf '%s'`. `appleScript(command:)` (escapes `\` and `"`)
  has its own test, `appleScriptEscapesQuotesAndBackslashes`. `install(appPath:)` returns
  `Result<Void, Failure>` with AppleScript's message. `isInstalled(at:)` checks for the wrapper's
  shebang and bundle-id lookup. The Claude Code line single-quotes the full binary path, which
  contains spaces.
- **After Stage 21 (not a stage).** `install()` uses administrator privileges only when
  `/usr/local/bin` is not writable by the user (design §5.8 always used them); otherwise it writes
  the wrapper as the user, exclusively, so a symlink planted between `rm` and a root write cannot
  redirect it.
- **Stage 22.** A refused capture ends capture and keeps the field's old combo, with the error
  under the field until the next capture; the matcher has already left capture mode on
  `.captured`. Only the meeting binding yields to a duplicate in `bindings(from:)`, so dictation is
  unchanged; it is left unbound if its default clashes too. Field titles live in
  `SettingsModel.title(of:)`, which the refusal and `HotkeysSection` share.
- **Stage 23.** `MeetingWindowModel` is `@Observable`, like every other app model, not an
  `ObservableObject`. `Chooser(config:platform:accountName:hasKey:)` also takes the account name,
  since the Remote card names the user; without a key it has no price or engine line. The capture
  chip reads `.systemAudio` (no capture-hint event, Stage 17): "Mic" in the room or before the tap
  reports, "Mic · System audio", or "System audio off". The mockup's open gap line ("reconnecting
  (audio is still being recorded)") has no event; the chip shows the reconnect and the gap line
  appears once words return, with the marker's reason. A pause not yet resumed reads "Paused from
  hh:mm:ss". A partial continues the last paragraph unless its speaker is known and different,
  when it carries that name. Paragraph time is the first segment's start, as in the export. Rows
  are cached: an item that sorts last extends them; anything else (a late segment, a note typed
  earlier, a revision) invalidates them for one rebuild on the next read, counted by `rebuilds`.
  Added `remoteDescriptionNamesTheUser`, `lateOrRevisedSegmentsRegroupParagraphs` and
  `headerShowsTheMeetingTitleModeAndEngine`.
- **Stage 24.** `MeetingControlling` also exposes `events`, `meeting`, `pause`, `resume`, `rename`
  and `addNote`, which the window needs. The window is behind `MeetingWindowPresenting` and its
  buttons go through a `MeetingActions` value, so the coordinator is host-tested without AppKit.
  The front app comes from an injected closure that skips Mini Whisper itself, and it is passed to
  that meeting's controller. The coordinator also has `openChooser()` for *Start Meeting…*, which
  brings an open chooser to the front, and `start()`. A press after a meeting has stopped opens a
  new chooser (added test `pressAfterTheMeetingStoppedOpensANewChooser`); the stopped meeting's
  window stays open until closed. A failed Start shows its error in the chooser
  (`MeetingWindowModel.showError`). The chooser reads the config as last applied. Window titles are
  "New Meeting", then "Meeting". The menu rows and usage totals refresh on every state change and
  on the summary. The notes composer is an `NSTextView`, because its `insertNewline:` command tells
  Enter from Shift+Enter. A dictation release while a meeting is active is ignored, as planned, so
  a dictation held across the meeting's start ends through its own toggle cap.
- **After Stage 24 (not a stage).** `MeetingCoordinator.start()` first calls a new `endDictation`
  dependency (`DictationController.abort()`): a toggle dictation running at Start would otherwise
  keep the microphone, its stopping press would get the R19 notice, and its cap would paste
  mid-meeting.

## Execution schedule

Batches run in order; a batch starts only when the previous one has fully landed. Stages inside a
*parallel* batch are independent and may be built concurrently; a *serial* batch holds one stage.
`/feature-implement` follows this table and demotes any batch it cannot verify to serial.

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1 | serial | Adds `KeyAccount` cases and `Config` keys every later stage uses; convention-establishing |
| 2 | Stage 2, Stage 3, Stage 9, Stage 10 | parallel | Disjoint files: `MWUsage/Pricing.swift`; new `MWTranscription` files + `FakeSummarizer.swift`; new `AACFileWriter.swift`; new tap files + `FakeSystemAudioTap.swift` + `Info.plist`. No symbol or string-keyed dependency between them; each uses only Stage 1. No shared registration point (no `Package.swift` or `project.yml` edit; new files only in shared modules). Same base state. No excluded category (only new protocols, no shared signature changed). No security ordering involved. No shared test resource (temp dirs; the tap integration test is opt-in) |
| 3 | Stage 4 | serial | Changes the shared `TranscriptSink` protocol and the `Emission` enum (excluded category) |
| 4 | Stage 11 | serial | Adds the `MWMeetings` target and edits `Package.swift` (scaffolding) |
| 5 | Stage 5, Stage 12 | parallel | Disjoint files: `SpeechmaticsAdapter.swift` + `CloudAdapterTests.swift` + a streaming fixture, vs new `MWMeetings` files + goldens under the already-declared `MWMeetingsTests/Fixtures`. No symbol or string-keyed dependency (both consume only Stages 4 and 11). No shared registration point. Same base state. The init gains only defaulted parameters, so no call site changes. No security ordering involved. No shared test resource |
| 6 | Stage 6 | serial | Adds an `EngineName` case with exhaustive switch sites in core and App (shared signature) |
| 7 | Stage 7 | serial | Consumes Stages 5 and 6; edits `EngineFactory.swift` |
| 8 | Stage 8 | serial | Widens the shared `AudioCapture` and `AudioBackend` protocols (shared signature) |
| 9 | Stage 13 | serial | Adds the `MWMeetingPipeline` target (scaffolding, `Package.swift`) |
| 10 | Stage 19 | serial | Adds the `MWAgentAccess` target (scaffolding, `Package.swift`) |
| 11 | Stage 14, Stage 15, Stage 16, Stage 20 | parallel | Disjoint files: each creates its own files (registry/attributor; supervisor; recorder/billing/summariser + `FakeAudioFileWriter.swift`; MCP server) and its own test files. No symbol or string-keyed dependency between them; all consume Stages 1–13 and 19 only. No shared registration point (targets already exist). Same base state. No excluded category (only new types). No security ordering involved. No shared test resource (temp dirs, `VirtualClock`) |
| 12 | Stage 17 | serial | Consumes Stages 13–16 |
| 13 | Stage 18 | serial | Edits `MeetingController.swift` from Stage 17 |
| 14 | Stage 21 | serial | Adds product dependencies to `project.yml` and edits `main.swift` |
| 15 | Stage 22 | serial | Adds a `BindingName` case (shared enum with exhaustive switches) |
| 16 | Stage 23 | serial | Adds the `MWMeetingPipeline` product to `project.yml`; establishes the app meeting model |
| 17 | Stage 24 | serial | Consumes Stage 23; edits `AppDelegate`, `MenuModel` |
| 18 | Stage 25 | serial | Edits `MeetingWindowModel` and `MeetingView` from Stage 24 |
| 19 | Stage 26 | serial | Consumes Stage 25's exporter; edits `MenuModel`, `AppDelegate`, `MeetingCoordinator` |
| 20 | Stage 27, Stage 28 | parallel | Disjoint files: Settings sources, `AppDelegate` and `SettingsModelTests`, vs `README.md` and `CHANGELOG.md` (docs only). No symbol or string-keyed dependency (prose only). No shared registration point. Same base state. No excluded category. No security ordering involved. No shared test resource (Stage 28 runs no tests) |

**Critical path:** Stage 1 → Stage 2 → Stage 4 → Stage 11 → Stage 5 → Stage 6 → Stage 7 → Stage 8 →
Stage 13 → Stage 19 → Stage 15 → Stage 17 → Stage 18 → Stage 21 → Stage 22 → Stage 23 → Stage 24 →
Stage 25 → Stage 26 → Stage 27 (20 of 28 stages).

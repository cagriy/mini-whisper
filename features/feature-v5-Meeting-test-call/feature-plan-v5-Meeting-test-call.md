# Meeting Test Call — Implementation Plan v5

**Status:** Draft
**Date:** 2026-11-11
**Design:** [feature-design-v5-Meeting-test-call.md](./feature-design-v5-Meeting-test-call.md)

## Overview

The plan builds the test call in four layers, bottom up, and keeps the app working after every
stage. No test call can start until the last code stage.

1. **Foundation (Stages 1–3).**
   - Stage 1 lands the uncommitted ducking and leveller fix the design measures (§7, §9 step 1).
   - Stage 2 adds the tag, the score record and the store support to `MWMeetings`.
   - Stage 3 creates the `MWTestCall` module with its value model, the normaliser and the aligner.
2. **Independent components (Stages 4–10).** Two parallel batches:
   - the agent filter;
   - voice casting and run history;
   - the scenario catalogue;
   - the conductor;
   - the Meetings-list TEST chip;
   - then the scorer and the `say` player.
3. **Controller (Stages 11–12).** Starting with an engine and a tag, timing, arrivals, the Pause
   guard and `.testScore` on open; then `finishTest` scoring at Stop.
4. **App surfaces (Stages 13–17).**
   - the session and Stop order;
   - the script pane;
   - the score pane with Earlier runs;
   - last, the setup page and the **Test Call…** link that makes the feature reachable;
   - then docs and acceptance.

Every numbered requirement in design §3 maps to at least one stage below. Every component in
design §5.1 is created or modified by at least one stage.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only |
integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests,
platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a
one-line justification. A **hybrid** stage runs full TDD for its host-testable core and names the
concrete check for its *integration-verified remainder*.

**Swift's compiled first red.** A stage that adds a new type, case, member or module cannot reach
a red *assertion* first: the test target fails to build. That build error is the legitimate first
red, for example:

- `error: cannot find 'TestCallTag' in scope`
- `error: type 'MeetingEvent' has no member 'testScore'`
- `error: no such module 'MWTestCall'`

The stage then scaffolds the minimal empty API. It re-runs to confirm red as assertion failures
(`✘ Test <name>() recorded an issue … Expectation failed`) and only then implements.

**Runners and registration.**

| Layer | Command |
|---|---|
| Core package tests | `cd Packages/MiniWhisperCore && swift test` |
| One core target | `cd Packages/MiniWhisperCore && swift test --filter <Target>Tests` |
| Core build only | `cd Packages/MiniWhisperCore && swift build` |
| App tests (and build) | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` |
| App build only | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd build` |
| Core opt-in integration | `cd Packages/MiniWhisperCore && MW_INTEGRATION=1 swift test --filter <Suite>` |
| App opt-in integration | `TEST_RUNNER_MW_INTEGRATION=1 xcodebuild … test -only-testing:AppTests/<Suite>` (xcodebuild strips the `TEST_RUNNER_` prefix; `man xcodebuild`) |

- **Framework.** Swift Testing throughout (`@Suite struct`, `@Test func`, `#expect`, `#require`,
  `@Test(arguments:)` for tables). No XCTest.
- **Core registration is explicit.** A new target, product, dependency edge or resource directory
  needs a `Packages/MiniWhisperCore/Package.swift` edit. Only Stages 3 and 12 edit it. Sources and
  tests inside an existing target are directory-discovered.
- **A declared `resources: [.copy("Fixtures")]` directory must exist**, or `swift build` fails.
  Stage 3 creates `Tests/MWTestCallTests/Fixtures/` in the same step that declares it.
- **App linkage is explicit.** `project.yml` lists every core product the app links. Stage 3 adds
  `MWTestCall`.
- **App sources** under `App/` and `AppTests/` are folder-sourced. Every App stage re-runs
  `xcodegen generate` before `xcodebuild`. AppTests do not link `MWTestSupport`: no
  `VirtualClock` there, so app-side fakes live in `AppTests/` and app code takes protocols.
- **Reading results.** Swift Testing output is preceded by XCTest lines `Executed 0 tests, with 0
  failures`. `swift test` prints one `✔/✘ Test run with N tests in M suites …` line per test
  target; read those.
- **Durations** (1.2 s, 20 s, 30 s, 1.5 s, the 100 ms poll, the 1 s tick) are tested on
  `VirtualClock` (`advance(by:)`, `waitUntilSleeping`). A real sleep in a test is a defect (R25).
- **Test conventions.**
  - One file per type: `Packages/MiniWhisperCore/Tests/<Target>Tests/<Type>Tests.swift`, sibling
    `Tests/MWMeetingPipelineTests/SpeechGateTests.swift`.
  - App: `AppTests/<Type>Tests.swift` with `@testable import MiniWhisper`, sibling
    `AppTests/MeetingWindowModelTests.swift`.
  - Fakes used by one target stay `private` in that target's test file, as `MeetingHarness` does.

**Observed baseline, run 2026-11-11 before drafting.** The working tree includes the uncommitted
ducking and leveller fix.

| Command | Result |
|---|---|
| `swift test` | exit 0; 16 `✔ Test run with …` lines (one per test target), **827 tests**, all passed |
| `xcodebuild … test` | `✔ Test run with 243 tests in 29 suites passed` + `** TEST SUCCEEDED **` |

"No regressions" in every stage means the core suite passes with at least 827 tests plus the
stage's additions, and the app suite passes with at least 243.

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: Chooser keeps cards; **Test Call…** link swaps to the setup page, **‹ Back** returns | Stage 16 |
| R2: Setup page: Scenario (Random + 8, latest WER or "not run"), Engine (4, "no key", "default"), Overlap; Start disabled without a key | Stage 5 (latest WER), Stage 16 |
| R3: Random picks uniformly, reproducible under an injected RNG | Stage 6, Stage 13 |
| R4: Remote meeting `Test call · <Scenario title>`, selected engine, tagged | Stage 11, Stage 13 |
| R5: Named voices, substitution recorded, disabled with fewer than two English voices | Stage 5, Stage 9 (record), Stage 13, Stage 16 |
| R6: Voice lines via `/usr/bin/say -v`, no shell, next line on exit | Stage 7, Stage 10 |
| R7: User hand-over after a 1.2 s pause following speech | Stage 7 |
| R8: 20 s silence skips; 30 s cap hands over and is scored | Stage 7 |
| R9: Skip ends the current line at once, terminates `say`, excluded | Stage 7, Stage 10, Stage 14 |
| R10: Overlap ⌈n/3⌉ by injected RNG, voice at onset + 1.5 s, recorded | Stage 7, Stage 16 (checkbox) |
| R11: Pause disabled with tooltip; `pause()`/`resume()` no-ops | Stage 11, Stage 14 |
| R12: Stop and sleep end the script (`stopped`/`notReached`), sleep message | Stage 7, Stage 13, Stage 14 |
| R13: Score at Stop and on quit, after drain, `done` lines only | Stage 9, Stage 12, Stage 13 |
| R14: Shared normalisation function | Stage 3 |
| R15: WER = (S+D+I)/N per line, per role and overall; "—" for N = 0 | Stage 2 (counts), Stage 3 (aligner), Stage 9, Stage 15 |
| R16: Majority label, purity, clean, cross-credited counts | Stage 9, Stage 15 |
| R17: Latency to final arrival, median and max with line | Stage 11 (arrivals), Stage 9 |
| R18: Score pane after Stop and on reopen | Stage 15 |
| R19: Earlier runs: same id and revision, newest first, ≤ 50, this run bold | Stage 5, Stage 15 |
| R20: Missing-score reasons (interrupted, unreadable, no lines scored) | Stage 11 (open payloads), Stage 12, Stage 15 |
| R21: `testcall.json` 0600; optional `test` tag on `meeting.json` and index row | Stage 2, Stage 12 |
| R22: CLI and MCP never list, search or return test meetings | Stage 4 |
| R23: Meetings list TEST chip and test meta line | Stage 8 |
| R24: Billing and summary exactly like any meeting | Stage 12, Stage 13 |
| R25: Every duration on `VirtualClock` | Stage 7, Stage 11, Stage 13 |
| R26: No new third-party dependency | Stage 3 (internal target only), Stage 17 (check) |
| R27: No script or transcript text logged | Stage 7, Stage 12, Stage 13 |

## Stages

### Stage 1 — Land the in-tree ducking and leveller fix

**Goal:** Commit the uncommitted fix the test call measures: minimal ducking of other apps' audio
and `SystemAudioLeveller` before the mixer.

**Category:** Non-TDD (integration-verified). The code and its unit tests are already written in
the working tree. This stage verifies them on this Mac and lands them as one commit, ahead of
everything that measures them (design §7, §9 step 1).

**Design references:** §4 (remote-call path), §7 (risk "This design measures the uncommitted
ducking and leveller fix"), §9 step 1.

**Touches** (all already modified or untracked in the working tree; nothing else):
- `Packages/MiniWhisperCore/Sources/MWAudio/AVAudioEngineBackend.swift`
- `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingAudioPath.swift`
- `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SystemAudioLeveller.swift` (new)
- `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SystemAudioLevellerTests.swift` (new)
- `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTests.swift` (`remoteTickRaisesAQuietCallBeforeMixing`)
- `Packages/MiniWhisperCore/Tests/MWAudioTests/AVAudioEngineBackendIntegrationTests.swift`
- `CHANGELOG.md`, `README.md`, `CLAUDE.md` (the fix's entries)

**Steps:**
1. `git status` shows exactly the files above as modified or untracked, besides
   `features/feature-v5-Meeting-test-call/`. Stop if anything else is dirty.
2. Run `swift test --filter MWMeetingPipelineTests`. Confirm `SystemAudioLevellerTests` and
   `remoteTickRaisesAQuietCallBeforeMixing` pass.
3. Run `cd Packages/MiniWhisperCore && MW_INTEGRATION=1 swift test --filter AVAudioEngineBackendIntegrationTests`
   on this Mac. Confirm `voiceProcessingDucksOtherAudioOnlyMinimally` passes. The terminal needs
   microphone permission.
4. Run the full core suite (827 tests) and the app tests (243). Confirm green.
5. Commit only the files above.

**Definition of done:**
- The fix is one commit. Its integration test passed on this Mac.
- The core and app suites are green at the baseline counts.

**Risks specific to this stage:** Step 3 needs microphone permission for the terminal. Without it
the test fails and proves nothing. Grant it and re-run; never skip the step.

### Stage 2 — Test-call tag, score record and store support

**Goal:** `TestCallTag` and `TestCallRecord` (schema 1) in `MWMeetings`. Optional `test` on
`Meeting` and `IndexEntry`. `MeetingStore` reads and writes `testcall.json` and copies the tag
into index rows.

**Design references:** §3 R15, R21; §5.1 (`TestCallTag`, `TestCallRecord`, `MeetingStore`);
§5.2; §5.3 `MeetingStore`; §5.7 Files; §5.10.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWMeetings/TestCallModel.swift`:
  - `TestCallTag`;
  - `TestCallRole` (`you`, `a`, `b`);
  - `TestCallLineStatus` (`done`, `skipped`, `stopped`, `notReached`);
  - `TestCallRecord` with nested `Scenario`, `Voice`, `Line`, `Counts`, `Heard` (`op`:
    `match | error | missed`), `RoleScore`, `CrossCredited`, `Latency`.
- edit `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingModel.swift`: `Meeting.test`,
  `IndexEntry.test`, both inits gain `test: TestCallTag? = nil` as the last parameter.
- edit `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingStore.swift`:
  - `File.testCall = "testcall.json"`;
  - `writeTestCall(_:of:)`;
  - `nonisolated readTestCall(_:) throws -> TestCallRecord?`;
  - `entry(for:)` copies `meeting.test`.
- edit `Packages/MiniWhisperCore/Sources/MWTestSupport/MeetingFixtures.swift`: `make(…, test: TestCallTag? = nil)`.
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/TestCallModelTests.swift`.
- edit `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingStoreTests.swift`.
- create `Packages/MiniWhisperCore/Tests/MWMeetingsTests/Fixtures/meeting-v0.5.json` and
  `index-v0.5.json`. They hold today's encoder output for `MeetingFixtures.make()`, written before
  the model changes: the pre-feature shape, with no `test` key.

**Steps (TDD):**
1. Write the two legacy fixtures first, from the unchanged code (encode `MeetingFixtures.make().meeting`
   and its index entry with `MeetingCoding.encoder()`).
2. Write tests in `TestCallModelTests`:
   - `legacyMeetingAndIndexDecodeWithoutATag`: both fixtures decode, `test == nil`.
   - `untaggedMeetingEncodesNoTestKey`: the encoded JSON has no `"test"` key (R21).
   - `taggedMeetingRoundTrips`: the tag survives. A nil `wer` leaves no `wer` key.
   - `recordEncodesTheSchemaOneShape`: a record built like the §5.2 example has these keys:
     - `schema`, `scenario.{id,revision,title}`, `engine` (`"assemblyai_streaming"`), `overlap`;
     - `scoredAt` as ISO 8601, `voices[].{role,character,requested,voice}`;
     - `lines[]`, with `labels` as a JSON **object** keyed by speaker id strings;
     - `roles[]`, `overall`, `crossCredited`, `latency`.
     - A skipped line carries `index`, `role`, `status` and `reference`, and no `counts`.
   - `countsDeriveWER`: `Counts(words: 157, substitutions: 6, deletions: 1, insertions: 3).wer`
     ≈ 0.0637. `words == 0` gives nil, which the UI shows as "—" (R15).

   Expected initial failure: `error: cannot find 'TestCallRecord' in scope`.
3. Write tests in `MeetingStoreTests`:
   - `testCallRoundTripsAs0600`: `writeTestCall` then `readTestCall` returns the record. The file
     mode is `0o600`.
   - `absentTestCallReadsNil`.
   - `undecodableTestCallThrows`: garbage bytes make `readTestCall` throw.
   - `indexRowCarriesTheTag`: `create` of a tagged meeting, then `update` with `wer` set, leaves
     the row's `test.wer` set.
   - `rescanRebuildsTheTag`: delete `index.json`. `index()` still returns the tag from
     `meeting.json`.

   Expected initial failure: `error: value of type 'MeetingStore' has no member 'writeTestCall'`.
4. Run `swift test --filter MWMeetingsTests`. Confirm the build errors. Scaffold the empty types
   and members, then confirm assertion failures.
5. Implement:
   - Every new type is `Codable, Sendable, Equatable` with synthesized coding.
   - `labels` is `[String: Int]`: `JSONEncoder` writes `[Int: Int]` as a flat array.
   - Store writes go through the existing temp-file-and-rename `write(_:to:)` (0600).
6. Run `swift test` and the app tests. `Meeting` and `IndexEntry` feed the app, so it must still
   build. Confirm no regressions.

**Definition of done:**
- Old files decode unchanged, and untagged files gain no `test` key.
- `testcall.json` is 0600, round-trips, reads nil when absent and throws when undecodable.
- Index rows carry the tag, including after a rescan.

**Risks specific to this stage:** None beyond the shared-type change. Every `Meeting(` and
`IndexEntry(` call site (8 + 5) compiles unchanged through the defaulted parameter.

### Stage 3 — `MWTestCall` module, value model, transcript normaliser and word aligner

**Goal:** The new core module, registered and linked. Its shared value types. The normaliser
(R14) and the word-level aligner (R15).

**Category:** Hybrid.
- Non-TDD (scaffolding) for registration, the value model and the voice-listing fixture.
- Full TDD for `TranscriptNormalizer` and `WordAligner`.

It is convention-establishing for the new test target.

**Design references:** §3 R14, R15, R26; §5.1 (`MWTestCall`, `TranscriptNormalizer`,
`WordAligner`, the seams); §5.5 scoring step 1; §5.10; §5.11 rows for the normaliser and aligner.

**Touches:**
- edit `Packages/MiniWhisperCore/Package.swift`:
  - product `.library(name: "MWTestCall", targets: ["MWTestCall"])`;
  - target `MWTestCall`, dependencies `["MWMeetings", "MWConfig", "MWSupport"]`;
  - test target `MWTestCallTests`, dependencies `["MWTestCall", "MWTestSupport", "MWOverlaySim"]`,
    with `resources: [.copy("Fixtures")]`.
- edit `project.yml`: add `- package: MiniWhisperCore` / `product: MWTestCall` to the
  `MiniWhisper` target.
- edit `CLAUDE.md`, module map row:
  `MWTestCall | TestScenario, ScenarioLibrary, VoiceCatalog, TranscriptNormalizer, WordAligner, TestCallConductor, TestCallScorer, TestRunHistory | MWMeetings, MWConfig, MWSupport`.
- create `Packages/MiniWhisperCore/Sources/MWTestCall/TestScenario.swift`:
  - `TestScenario` (id, revision, title, two `VoiceRole`s, ordered `ScenarioLine`s);
  - `VoiceRole` (role `.a`/`.b`, character, requested voice);
  - `ScenarioLine` (role, text);
  - `ScenarioChoice` (`.random`, `.named(String)`);
  - `VoiceLine` (text, voice);
  - `CastVoice` (role, character, requested, voice);
  - `VoiceCasting` (`.ready([TestCallRole: CastVoice])`, `.unavailable`).

  Roles reuse `TestCallRole` from Stage 2.
- create `Packages/MiniWhisperCore/Sources/MWTestCall/TranscriptNormalizer.swift`:
  - `tokens(_:) -> [String]`;
  - `sourced(_:) -> [SourcedToken]`: each token keeps its source word's index and text, for
    `heard`.
- create `Packages/MiniWhisperCore/Sources/MWTestCall/WordAligner.swift`:
  - `align(reference:hypothesis:) -> Alignment`;
  - ops `match | substitute | delete | insert` with indices, and the S, D, I counts.
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/TranscriptNormalizerTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/WordAlignerTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/Fixtures/say-voices.txt`: an excerpt of
  `say -v '?'` captured on this Mac, used in Stage 5. It holds:
  - the six scenario voices (`Daniel en_GB`, `Karen en_AU`, `Moira en_IE`, `Rishi en_IN`,
    `Samantha en_US`, `Tessa en_ZA`);
  - names with spaces and nested parentheses (`Bad News`, `Eddy (English (UK))`,
    `Grandma (German (Germany))`);
  - several non-English voices (`Alice it_IT`, `Alva sv_SE`).

**Steps (TDD):**
1. Non-TDD (scaffolding):
   - Register the three `Package.swift` entries.
   - Create `Fixtures/say-voices.txt` and `TestScenario.swift` with the value types above.
   - Add the `project.yml` product and the CLAUDE.md row.
   - Run `swift build` (exit 0) and the App build-only command (exit 0).
2. Write `TranscriptNormalizerTests`, a `@Test(arguments:)` table of `(input, tokens)`:
   - case: `"The Plan"` → `the plan`;
   - punctuation: `"fail, on staging."` → `fail on staging`;
   - apostrophes inside words: `"it's"`, `"it’s"` (curly) → `it's`; `"'quoted'"` → `quoted`;
   - hyphens and dashes: `"one-line"` → `one line`; `"14:00–16:00"` splits on the en dash;
   - integers: `"40"` → `forty`; `"1,200"` → `one thousand two hundred`;
   - decimals: `"3.2"` → `three point two`;
   - percentages: `"80%"` → `eighty percent`;
   - ordinals: `"14th"` → `fourteenth`;
   - times: `"10:30"` → `ten thirty`; `"9:05"` → `nine oh five`; `"10:00"` → `ten`;
   - currency: `"$40"` → `forty dollars`; `"$3.50"` → `three dollars fifty`;
   - years: `"2026"` → `twenty twenty six`; `"2005"` → `two thousand five`;
   - mixed: one sentence with all of these;
   - `scriptAndTranscriptFormsAgree`: `"the payments migration is at eighty percent"` and
     `"The payments migration is at 80%."` give equal tokens;
   - `sourcedTokensKeepTheirWord`: `"80% done"` → `eighty`/`percent` from source `80%`, `done`
     from `done`.

   Expected initial failure: `error: cannot find 'TranscriptNormalizer' in scope`.
3. Write `WordAlignerTests`:
   - both sides empty → no ops, all counts 0;
   - empty hypothesis → all deletions; empty reference → all insertions;
   - all-match;
   - a single S, a single D, a single I;
   - `webhook` vs `web hook` → 1 S + 1 I, as `substitute(webhook→web)` then `insert(hook)`;
   - `tieBreakingIsStable`: equal-cost inputs give the same op sequence on every run, and the
     sequence the test pins.

   Expected initial failure: `error: cannot find 'WordAligner' in scope`.
4. Run `swift test --filter MWTestCallTests`. Confirm the build errors. Scaffold the empty APIs,
   then confirm assertion failures.
5. Implement:
   - The normaliser lowercases, maps `’` to `'`, and splits on whitespace, `-`, `‐`, `–` and `—`.
   - It spells numbers by the canonical forms in the table (*Planning decisions taken* #7) and
     strips other punctuation, keeping apostrophes inside words.
   - The aligner is Levenshtein DP with unit costs. On a tie the backtrace prefers match or
     substitute, then insert, then delete, read from the end. That gives the pinned order.
6. Run `swift test` and the App build-only command. Confirm no regressions.

**Definition of done:**
- `MWTestCall` builds and the app links it.
- Normaliser and aligner tables are green. CLAUDE.md lists the module.
- No third-party dependency is added (R26).

**Risks specific to this stage:** The normaliser's canonical forms are a contract that the
scenario scripts (Stage 6) and every engine's digit output meet in the middle. The table is the
contract. Changing it later moves every stored WER, so settle it here.

### Stage 4 — Hide test meetings from agents

**Goal:** `AgentMeetings`, a `MeetingReading` decorator, is the only reader the CLI and MCP server
get. Test meetings vanish from `list`, `search`, `transcript`, `summary` and every MCP tool, and
id or prefix lookups fail as for a missing meeting.

**Category:** Hybrid.
- Full TDD for `AgentMeetings` and its CLI and MCP effect.
- Integration-verified remainder: the one-line `AgentCommand.swift` wiring, checked by the App
  build here and by `mini-whisper meetings list|search` in Stage 17.

**Design references:** §3 R22; §5.1 (`AgentMeetings`); §5.3 `AgentMeetings`; §5.7 Agents.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWAgentAccess/AgentMeetings.swift`
- create `Packages/MiniWhisperCore/Tests/MWAgentAccessTests/AgentMeetingsTests.swift`
- edit `App/AgentCommand.swift` (`:41`, `:44`: pass `AgentMeetings(store)`)

**Steps (TDD):**
1. Write `AgentMeetingsTests` over a real temp store: `SeededMeetings()` plus one tagged meeting
   created with `MeetingFixtures.make(…, test: TestCallTag(…))`. Its transcript holds "migration",
   a word the Northwind meeting also has, so an unfiltered search would hit it.
   - `indexHidesTestMeetings`: 3 rows, none tagged.
   - `loadOfATestMeetingThrowsAsForAMissingOne`: the thrown error equals the one
     `store.load(UUID())` throws, `CocoaError(.fileReadNoSuchFile)`.
   - `cliListAndSearchNeverShowATestMeeting`: `MeetingsCLI(reader: AgentMeetings(store), …)` runs
     `list`, `list --json` and `search migration`. Neither the test id nor its title appears.
   - `cliLookupByIDOrPrefixReportsNoMeeting`: `transcript <full id>` and `transcript <8-hex prefix>`
     exit 2 with `no meeting <id>`.
   - `mcpNeverReturnsATestMeeting`: `MCPServer(reader: AgentMeetings(store), …)`.
     - `list_meetings` and `search_meetings` never contain the id.
     - `get_transcript` and `get_summary` with the id return the same tool error as an unknown
       id.

   Expected initial failure: `error: cannot find 'AgentMeetings' in scope`.
2. Run `swift test --filter MWAgentAccessTests`. Confirm the build error. Scaffold a pass-through
   `AgentMeetings`, then confirm assertion failures: the test meeting is listed.
3. Implement `public struct AgentMeetings: MeetingReading`:
   - `index()` returns `base.index().filter { $0.test == nil }`;
   - `load(_:)` loads, then throws `CocoaError(.fileReadNoSuchFile)` when `meeting.test != nil`.
4. Edit `App/AgentCommand.swift` so both constructions take `AgentMeetings(store)`.
5. Run `swift test` and the App build-only command. Confirm no regressions.

**Definition of done:**
- Every CLI command and MCP tool, built over `AgentMeetings`, treats a test meeting as absent.
- `AgentCommand` is the single construction point and uses the decorator.

**Risks specific to this stage:** None.

### Stage 5 — Voice casting and run history

**Goal:** `VoiceCatalog` parses `say -v ?`, filters English voices and casts a scenario with
substitutes. `TestRunHistory` gives the scenario menu's latest WERs and the Earlier runs list.

**Design references:** §3 R2, R5, R19; §5.1 (`VoiceCatalog`, `TestRunHistory`); §5.6 Scenario
voice missing; §5.7 Process launch (allow-list); §5.8 Earlier runs; §5.11 rows.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWTestCall/VoiceCatalog.swift`:
  - `SystemVoice` (name, locale);
  - `static parse(_:)`, `english`, `cast(_:) -> VoiceCasting`;
  - `static isAllowed(_ name:)`, the `^[A-Za-z0-9 ()._'-]+$` allow-list.
- create `Packages/MiniWhisperCore/Sources/MWTestCall/TestRunHistory.swift`:
  - `latestWER(in:revisions:) -> [String: Double]`;
  - `runs(of:in:load:) -> [TestRunHistory.Run]`, where `Run` is meeting id, `startedAt` and
    record.
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/VoiceCatalogTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/TestRunHistoryTests.swift`

**Steps (TDD):**
1. Write `VoiceCatalogTests`, reading `Bundle.module`'s `Fixtures/say-voices.txt`:
   - `parsesNamesWithSpacesAndParentheses`: `Eddy (English (UK))` / `en_GB`, `Bad News` / `en_US`.
   - `englishFilterKeepsOnlyEnLocales`.
   - `castsBothNamedVoicesWhenInstalled`: scenario Daniel / Karen → `.ready`, no substitution.
   - `substitutesAMissingVoiceInCatalogueOrder`: with Karen missing, the first `en_` voice in
     listing order is cast, and never the other role's voice.
   - `substitutesBothWhenBothAreMissing`: two distinct voices.
   - `fewerThanTwoEnglishVoicesIsUnavailable`.
   - `rejectsNamesFailingTheAllowList`: a listed name `Bad;Name` is never cast. `isAllowed` is
     false for it and for `-v`-like names starting with `-`.

   Scenarios are built in the test from Stage 3's value types, not from `ScenarioLibrary`.

   Expected initial failure: `error: cannot find 'VoiceCatalog' in scope`.
2. Write `TestRunHistoryTests`, using `IndexEntry`s with tags:
   - `latestWERIsTheNewestScoredRunOfTheCurrentRevision`: ignores other revisions and `wer == nil`.
   - `runsAreTheSameIDAndRevisionNewestFirst`.
   - `runsAreCappedAtFifty`: 60 entries give 50 runs, and `load` is called 50 times.
   - `runsSkipEntriesWhoseRecordIsMissing`: `load` returns nil or throws.

   Expected initial failure: `error: cannot find 'TestRunHistory' in scope`.
3. Run `swift test --filter MWTestCallTests`. Confirm the build errors, scaffold, and confirm
   assertion failures.
4. Implement:
   - `parse` matches each line with `^(.+?)\s+([a-z]{2,3}_[A-Za-z0-9]+)\s+#`.
   - `cast` uses the requested voice when installed and allowed. Otherwise it takes the first
     installed allowed `en_` voice that is not the other role's.
5. Run `swift test`. Confirm no regressions.

**Definition of done:**
- Casting covers present, one missing, both missing and unavailable.
- Names failing the allow-list are never cast.
- History filters by id and revision, sorts newest first and caps at 50.

**Risks specific to this stage:** None.

### Stage 6 — Scenario catalogue

**Goal:** The 8 bundled scenarios (revision 1) as Swift values, with `ScenarioLibrary.all`,
`scenario(id:)` and `pick(_:using:)`.

**Design references:** §3 R3, R5; §5.1 (`TestScenario`, `ScenarioLibrary`); §5.2 Scenario
catalogue; §5.7 Process launch (no line starts with `-`); §5.11 `ScenarioLibrary` row.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWTestCall/ScenarioLibrary.swift`
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/ScenarioLibraryTests.swift`

**Steps (TDD):**
1. Write `ScenarioLibraryTests`:
   - `eightScenariosWithUniqueIDs`: the ids, titles and voice pairs of the §5.2 table.
   - `everyRevisionIsAtLeastOne`.
   - `twoDistinctVoiceRolesEach`: roles `.a` and `.b`, distinct characters and voices.
   - `tenToFourteenLinesWithFourOfTheUsers`.
   - `referenceTokensAreBetween120And200`: counted with `TranscriptNormalizer.tokens` over all lines.
   - `noLineStartsWithADash`.
   - `scriptsContainNoDigits`: numbers, dates and times are spelled in the normaliser's canonical
     words.
   - `vocativesNameOnlyTheScenariosCharacters`: a capitalised word directly before a comma at a
     sentence start, or after a comma before `?`, `.` or `!` at a sentence end, is one of the
     scenario's two character names. A line therefore never addresses the user.
   - `pickRandomIsUniformAndReproducible`:
     - with `SeededRandom(seed:)` (`MWOverlaySim`), the same seed picks the same sequence;
     - over 8 000 picks, every scenario's count is within 1 000 ± 150.
   - `pickNamedReturnsThatScenario`, and an unknown name falls back to Random.

   Expected initial failure: `error: cannot find 'ScenarioLibrary' in scope`.
2. Run `swift test --filter MWTestCallTests`. Confirm the build error, scaffold `all = []`, and
   confirm assertion failures.
3. Implement and author the 8 scenarios per the §5.2 table:
   - 12 ± 2 lines, 4 of them `.you`, 120–200 tokens;
   - ≥ 3 numbers, dates or times and ≥ 2 proper nouns or terms of art each, matching the table's
     emphasis;
   - characters are the scenario's own.

   The non-testable authoring rules are checked by reading, as a Definition-of-done item.
4. Run `swift test`. Confirm no regressions.

**Definition of done:**
- All library tests are green.
- Each scenario visibly carries its §5.2 emphasis: ≥ 3 numbers, dates or times and ≥ 2 proper
  nouns or terms of art (reviewed by reading).

**Risks specific to this stage:** `say` may mispronounce a term. The listening pass in Stage 17
replaces such words. Revision 1 is unreleased until 0.6.0, so it stays 1.

### Stage 7 — Test-call conductor

**Goal:** `TestCallConductor` drives a script on an injected `Clock`. It plays voice lines, waits
for the user's hand-over, and handles silence, the 30 s cap, Skip, Overlap, Stop, sleep and `say`
failures. It records each line's outcome in `TestCallRun`.

**Design references:** §3 R6–R10, R12, R25, R27; §5.1 (`TestCallConductor`, `SpeechPlaying`,
`UserSpeechSensing`); §5.3 Conductor contract; §5.5 steps 4–7, 8.1; §5.6 (`say` fails, no system
audio, user never speaks); §5.9.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWTestCall/TestCallRun.swift`:
  - `TestCallRun`: lines, casting, `overlap: Bool`;
  - `RunLine`: index, role, status, start, end, overlapped, skip reason;
  - `EndReason` (`.stop`, `.sleep`);
  - `SkipReason` (`.skipped`, `.noSpeech`, `.voiceFailed`);
  - `ConductorEvent`;
  - `Playback` (launch and exit meeting times, `normalExit`);
  - protocols `SpeechPlaying` and `UserSpeechSensing`, both `@MainActor`.
- create `Packages/MiniWhisperCore/Sources/MWTestCall/TestCallConductor.swift` (`@MainActor final class`)
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/TestCallConductorTests.swift`, with
  private fakes: a player whose `play` suspends until the test finishes or fails it, and a sensor
  whose spans and flags the test sets.

**Steps (TDD):**
1. Write `TestCallConductorTests` (`@MainActor`, `VirtualClock`, the fakes, a 6-line test scenario):
   - `voiceLinesPlayInOrderAndTheNextStartsOnExit`: start and end are the `Playback` times.
   - `userLineHandsOverExactly1Point2SecondsAfterTheSpanEnd`: not at +1.1 s, at +1.2 s with
     `isSpeaking == false`. Start is the first span after the prompt; end is the last span's end.
   - `twentySecondsWithoutSpeechSkipsTheLine` (`.noSpeech`).
   - `thirtySecondsOfSpeechHandsOverAndScores`: status `done`.
   - `skipDuringAVoiceStopsThePlayer`: `stop()` called, status `skipped`, and it is not counted
     as a `say` failure.
   - `skipDuringTheUsersTurn`.
   - `overlapStartsTheVoiceAt1Point5SecondsAfterOnset`: the voice launches at onset + 1.5 s. The
     conductor advances only when `say` has exited and the hand-over holds. Both lines are
     `overlapped`.
   - `overlapPicksCeilNOverThreeWithASeededRNG`: same seed, same lines.
   - `endStopMarksTheRunningLineStoppedAndTheRestNotReached`, and the same for `end(.sleep)`.
   - `twoConsecutiveSayFailuresEndTheScript`: `.voicesFailed`, then `.finished`. One failure only
     skips (`.voiceFailed`).
   - `missingSystemAudioAfterAVoiceLineEmitsCaptureMissing`: `lastAudibleSystemAudio` nil or
     before the line's start. The line is still `done`.
   - `finishedAfterTheLastLine`.
   - `pollsEvery100ms`: the conductor sleeps on the clock in 0.1 s steps while waiting.
   - `logsIdsAndReasonsNeverScriptText`: within `Log.withSinks` and a `CapturingLogSink`:
     - lines `test call: line <i> skipped (<reason>)` and `test call: voice substituted <requested>-><actual>`;
     - no line contains any word of the scenario's text (R27).

   Expected initial failure: `error: cannot find 'TestCallConductor' in scope`.
2. Run `swift test --filter TestCallConductorTests`. Confirm the build error, scaffold an
   inactive conductor, and confirm assertion failures.
3. Implement:
   - Constants `handOverPause = 1.2`, `silenceSkip = 20`, `userLineCap = 30`,
     `overlapDelay = 1.5`, `poll = .milliseconds(100)`.
   - `init(scenario:casting:overlap:player:sensor:clock:rng:)` takes `inout some RandomNumberGenerator`
     and picks the overlapped lines there.
   - `run()`, `skip()` and `end(_:)` act on the injected `Clock`. Voice playback runs in a child
     task, so polling continues during it.
4. Run `swift test`. Confirm no regressions.

**Definition of done:**
- Every row of the §5.11 conductor table is a passing test on `VirtualClock`.
- Statuses and times land in `TestCallRun`, and the log carries no script text.

**Risks specific to this stage:** Races between the player's completion and the poll loop. Every
test advances the clock only after `waitUntilSleeping`, and the fake player resumes inside
`advance`, so ordering is deterministic.

### Stage 8 — Meetings list: TEST chip and test meta line

**Goal:** Tagged rows show a TEST chip after the title. Their meta line reads
`HH:MM · N min · Remote call · WER x.x% · <Engine> · $x.xx`, without WER while unscored.

**Category:** Hybrid.
- Full TDD for `MeetingsListModel`.
- Platform-only/UI wiring for the chip in `MeetingsListView`, verified by build and the Stage 17
  manual check.

**Design references:** §3 R23; §5.3 `MeetingsListModel`; §5.4 Meetings list and TEST tag colours.

**Touches:**
- edit `App/Meetings/MeetingsListModel.swift` (`Row` at `:55` gains `isTest`; `row(for:)` `:298`;
  `meta(of:)` `:312`)
- edit `App/Meetings/MeetingsListView.swift` (the chip after the title)
- create `App/TestCall/TestTag.swift`: the TEST chip view and the tag colours (`#7a4fd0`, fill
  `#f1ecfb`, border `#ddd0f5`), reused by later App stages.
- edit `AppTests/MeetingsListModelTests.swift`

**Steps (TDD):**
1. Write tests in `MeetingsListModelTests` (the `entry(...)` helper gains `test:`):
   - `testRowShowsTheChipAndTheWERMeta`: `11:14 · 2 min · Remote call · WER 6.4% · AssemblyAI
     Universal-Streaming · $0.02` and `isTest == true`. No speakers, summary or audio segments.
   - `unscoredTestRowOmitsWER`.
   - `searchStillFindsTestMeetings`.

   Existing rows stay unchanged; the current tests pin them.

   Expected initial failure: `error: value of type 'MeetingsListModel.Row' has no member 'isTest'`.
2. Run the App tests. Confirm the build error, scaffold `isTest = false`, and confirm assertion
   failures.
3. Implement the model, `TestTag`, and the chip in the list row.
4. Run the App tests and `swift test`. Confirm no regressions.

**Definition of done:** The model tests are green. Tagged rows render the chip and the R23 meta.

**Risks specific to this stage:** None.

### Stage 9 — Test-call scorer

**Goal:** `TestCallScorer` turns a run, its scenario and the engine's segments into a
`TestCallRecord`:
- per-line alignment and `heard`;
- WER per role and overall;
- labels, purity, clean and cross-credited counts;
- latency.

**Design references:** §3 R13, R15–R17; §5.1 (`TestCallScorer`); §5.2 (record, `heard`, line
status); §5.5 Scoring algorithm; §5.6 Every line skipped; §5.11 scorer row.

**Touches:**
- create `Packages/MiniWhisperCore/Sources/MWTestCall/TestCallScorer.swift`:
  `score(run:scenario:segments:arrivals:speakers:userSpeaker:engine:scoredAt:) -> TestCallRecord`
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/TestCallScorerTests.swift`
- create `Packages/MiniWhisperCore/Tests/MWTestCallTests/SprintPlanningFixture.swift`: the
  mockup's 12 lines, a run with line 11 skipped, segments with word timings and labels, and
  arrivals. The fixture builder is internal to the test target.

**Steps (TDD):**
1. Write `TestCallScorerTests`:
   - `perfectTranscriptScoresZero`.
   - `mockupCaseMatchesTheAcceptedFigures`:
     - 10 errors in 157 words, overall 6.4%; You 4.2%, Tom 4.8%, Priya 10.6%;
     - Priya purity 87%, 2 of 3 clean;
     - latency median 1.3 s, max 2.9 s at line 6, 11 of 12 lines scored;
     - line 6 `heard` holds `{text: "Cooper Netties", op: error, script: "Kubernetes"}`;
     - line 6 has counts 17 words, 1 S, 1 I, and `segmentStart` 41.2.
   - `overlappingWindowsResolveByTokenMatch`: a token in two windows goes to the earliest whose
     reference holds an unconsumed equal token; otherwise to the nearest unpadded span.
   - `wordsOutsideEveryWindowAreIgnored`, which also covers words during skipped lines.
   - `segmentsWithoutWordTimingsSpreadTokensEvenly`.
   - `skippedStoppedAndNotReachedLinesAreExcludedButKeepTheirReference`.
   - `zeroScoredLinesGivesAnEmptyScore`: overall words 0, WER nil, latency nil.
   - `crossCreditedCounts`: voice words labelled as the user, and the user's words labelled as
     anyone else.
   - `missedScriptWordsAppearAsMissedEntries`.

   Expected initial failure: `error: cannot find 'TestCallScorer' in scope`.
2. Run `swift test --filter TestCallScorerTests`. Confirm the build error, scaffold an empty
   record, and confirm assertion failures.
3. Implement design §5.5 steps 1–6:
   - Windows are `[start − 0.5 s, end + 1.5 s]`.
   - A run of consecutive error transcript words forms one `heard` entry. Its `script` joins the
     script words substituted in that run.
   - `voices` come from the run's casting. `majorityLabelName` comes from `speakers`.
4. Run `swift test`. Confirm no regressions.

**Definition of done:** Every row of the §5.11 scorer table is a passing test, with the
corrected mockup figures (*Planning decisions taken* #18).

**Risks specific to this stage:** The fixture has to be built to land exactly on the figures. Build
it line by line from the mockup's per-line badges (lines 2, 3, 6, 7 and 9 carry the errors; line 9
the label).

### Stage 10 — `say` player and system voices

**Goal:** `SayProcessPlayer` (`SpeechPlaying` over `/usr/bin/say`, no shell) and `SystemVoices`
(`say -v ?` off the main actor), plus proof that the tap hears a `say` process.

**Category:** Hybrid.
- Full TDD for argument building, the voice-name guard, exit mapping and `stop()`, using
  stand-in executables.
- Integration-verified remainder:
  - `cd Packages/MiniWhisperCore && MW_INTEGRATION=1 swift test --filter SystemAudioTapIntegrationTests`;
  - `TEST_RUNNER_MW_INTEGRATION=1 xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test -only-testing:AppTests/SayProcessPlayerIntegrationTests`.

**Design references:** §3 R6, R9; §5.1 (`SayProcessPlayer`, `SystemVoices`); §5.7 Process launch;
§5.8 (`say` out of process); §5.11 integration tests.

**Touches:**
- create `App/TestCall/SayProcessPlayer.swift`: `init(executable: URL = /usr/bin/say, meetingTime:)`,
  `arguments(for:)`, `play(_:)`, `stop()`.
- create `App/TestCall/SystemVoices.swift`: `init(executable:arguments:)`, `load() async -> String`.
- create `AppTests/SayProcessPlayerTests.swift`, holding unit tests plus a
  `SayProcessPlayerIntegrationTests` suite gated by `MW_INTEGRATION`.
- edit `Packages/MiniWhisperCore/Tests/MWAudioTests/SystemAudioTapIntegrationTests.swift`: add
  `tapHearsASayProcess`, the existing `afplay` test pattern with `/usr/bin/say -v Samantha "…"`.

**Steps (TDD):**
1. Write `SayProcessPlayerTests`:
   - `argumentsAreVoiceThenTextWithNoShell`: `["-v", "Daniel", "Then the remaining risk…"]`, and
     the executable is `/usr/bin/say`.
   - `disallowedVoiceNameNeverLaunches`: `play` returns `normalExit == false` and no process runs.
   - `zeroExitIsNormal`: executable `/usr/bin/true`.
   - `nonZeroExitIsAFailure`: executable `/usr/bin/false`.
   - `missingExecutableIsAFailure`.
   - `stopTerminatesTheRunningProcess`: executable `/bin/cat` blocks on its stdin pipe until
     `stop()`. `play` returns `normalExit == false`, with launch ≤ exit.
   - `systemVoicesReturnsTheToolsOutput`: executable `/bin/echo` with arguments `["-v", "?"]` →
     `"-v ?\n"`.

   Expected initial failure: `error: cannot find 'SayProcessPlayer' in scope`.
2. Run the App tests. Confirm the build error, scaffold, and confirm assertion failures.
3. Implement:
   - `Process` with `executableURL` and an argument array; `terminationHandler` resumes a
     continuation.
   - The voice name is checked with `VoiceCatalog.isAllowed` before launch.
   - `SystemVoices.load()` runs in a detached task and reads stdout.
4. Write the gated `SayProcessPlayerIntegrationTests.playsAShortLineWithANormalExit` and
   `tapHearsASayProcess`.
5. Run the App tests, `swift test`, and the two integration commands above on this Mac. The second
   needs System Audio Recording permission for the terminal.

**Definition of done:**
- Unit tests are green.
- Both integration checks pass on this Mac: `say` exits normally, and the tap's peak rises above
  −60 dBFS during `say`.

**Risks specific to this stage:** If `TEST_RUNNER_MW_INTEGRATION` does not reach the hosted test
app, the gated suite is skipped silently. Read the `Test run` line: it must count the integration
test as passed, not skipped. The Stage 17 acceptance run plays `say` for real either way.

### Stage 11 — Controller: test-meeting plumbing

**Goal:** `MeetingController` changes for test meetings. Scoring is not yet included.
- starts with a given engine and a tag;
- exposes `meetingTime`, `userSpeech` and `lastAudibleSystemAudio`;
- records segment arrivals for test meetings;
- ignores Pause and Resume for them;
- emits `.testScore` when a test meeting is opened.

The app's `MeetingControlling` mirror, its stub and the window model's exhaustive switch move
with it.

**Design references:** §3 R4, R11, R17, R20, R25; §5.3 `MeetingController` (all bullets except
`finishTest`), `MeetingControlling`; §5.6 Crash or force-quit, `testcall.json` write fails (the
reopen half).

**Touches:**
- edit `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`:
  - `start(mode:title:engine:test:)`, both new parameters defaulted to nil;
  - `public var meetingTime` (private today at `:319`), `public var userSpeech`;
  - `public private(set) var lastAudibleSystemAudio`, with `checkSystemAudio()` (`:335`) reading
    the peak every tick;
  - `public private(set) var segmentArrivals`, set in `add(_:session:origin:)` before `.segmentAdded`;
  - `pause()` / `resume()` guards;
  - `open(_:)` emits `.testScore`.
- edit `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingEvent.swift`:
  - `TestScoreState` (`.scored(TestCallRecord)`, `.missing`, `.unreadable`);
  - case `testScore(TestScoreState)`.
- create `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTestCallTests.swift`
  (uses `MeetingHarness`)
- edit `App/Meeting/MeetingCoordinator.swift`:
  - `MeetingControlling` gains `start(mode:title:engine:test:)` in place of `start(mode:title:)`,
    plus `meetingTime`, `userSpeech` and `lastAudibleSystemAudio`;
  - the `:199` call passes `engine: nil, test: nil`.
- edit `App/Meeting/MeetingWindowModel.swift`: `apply(_:)` (`:428`) handles `.testScore` and keeps
  it in `private(set) var testScore: TestScoreState?`.
- edit `AppTests/MeetingCoordinatorTests.swift`: `StubController` implements the new members and
  records engine and tag.
- edit `AppTests/MeetingWindowModelTests.swift`

**Steps (TDD):**
1. Write `MeetingControllerTestCallTests`:
   - `givenEngineReplacesTheConfiguredOne`: config `speechmaticsStandard`, given `.assemblyaiPro`
     with an AssemblyAI key. The session opens on AssemblyAI Pro and `meeting.engine` matches.
   - `givenEngineWithoutItsKeyThrowsNoEngineKey`.
   - `tagIsOnTheMeetingBeforeCreate`: `meeting.json` and the index row carry it from Start.
   - `meetingTimeAndUserSpeechAreExposed`: after `advance(by: 2)` `meetingTime == 2`. After a loud
     feed, `userSpeech.isSpeakingNow`.
   - `pauseAndResumeDoNothingForATestMeeting`: state stays `.recording`, no marker.
   - `sleepStillPausesATestMeeting`: `.paused(.sleep)`.
   - `arrivalsAreRecordedAtAppendForTestMeetings`: a segment delivered at meeting second 3 has
     arrival 3, set before `.segmentAdded` is pulled.
   - `ordinaryMeetingsRecordNoArrivals`.
   - `lastAudibleSystemAudioUpdatesOnEveryAudibleTickAfterSettling`: loud system audio at
     second 1, quiet, loud again at second 5. The value is 5. The silence hint never fires.
   - `openEmitsScored`, `openEmitsMissingWithoutFileOrWER`,
     `openEmitsUnreadableForAnUndecodableFileOrAWERWithoutFile`.
   - `openOfAnOrdinaryMeetingEmitsNoTestScore`.

   Expected initial failure: `error: extra arguments at positions #3, #4 in call` and
   `error: type 'MeetingEvent' has no member 'testScore'`.
2. Write `MeetingWindowModelTests.testScoreEventIsKept`. Extend `MeetingCoordinatorTests`'s start
   test: an ordinary start passes `engine == nil, test == nil`.
3. Run `swift test --filter MWMeetingPipelineTests` and the App tests. Confirm the build errors,
   scaffold, and confirm assertion failures.
4. Implement:
   - `checkSystemAudio()` reads `systemPeakSinceLastCall()` once per tick while a tap exists. It
     updates `lastAudibleSystemAudio` from that reading, then runs the unchanged settle-and-hint
     logic on the same reading.
   - The existing `silenceHintAfterSixtySecondsOfOneSidedSpeech` and
     `noSilenceHintWhenSystemAudioArrives` pin the hint.
5. Run `swift test` and the App tests. Confirm no regressions.

**Definition of done:**
- Every §5.11 controller row except `finishTest` is a passing test.
- The app builds against the new protocol, and the stub is updated.

**Risks specific to this stage:** Shared signature. The protocol, the controller conformance and
`StubController` must change together or the app stops compiling. This stage is atomic for that
reason.

### Stage 12 — Score at Stop: `finishTest`

**Goal:** After `stop(summarise: false)`, `finishTest(_:scenario:)` does four things:
1. scores with `TestCallScorer`;
2. writes `testcall.json`;
3. sets the tag's WER and refreshes the index;
4. emits `.testScore(.scored(record))`.

A write error emits `.error` and still the score.

**Design references:** §3 R13, R20, R21, R24, R27; §5.3 `finishTest`; §5.6 (`testcall.json`
write fails, every line skipped); §5.9 scored log line; §5.10 `Package.swift` edge.

**Touches:**
- edit `Packages/MiniWhisperCore/Package.swift`: `MWMeetingPipeline` dependencies gain `"MWTestCall"`.
- edit `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift` (`finishTest`)
- edit `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTestCallTests.swift`
- edit `App/Meeting/MeetingCoordinator.swift`: `MeetingControlling` gains `finishTest(_:scenario:)`,
  and the file imports `MWTestCall`.
- edit `AppTests/MeetingCoordinatorTests.swift` (`StubController.finishTest`)
- edit `CLAUDE.md`: `MWMeetingPipeline`'s depends-on cell gains `MWTestCall`.

**Steps (TDD):**
1. Write tests in `MeetingControllerTestCallTests`:
   - `finishTestWritesTheScoreSetsWERAndRefreshesTheIndex`: start a tagged meeting, deliver
     segments matching a two-line scenario, `stop(summarise: false)`, then `finishTest`.
     - `testcall.json` decodes to the emitted record;
     - `meeting.json` and the index row carry `wer`;
     - the events include `.testScore(.scored(record))`.
   - `stopStillBillsAndSummariseStillRuns`: usage gets one record at Stop. A later `summarise()`
     writes the summary (R24).
   - `writeFailureEmitsAnErrorAndStillTheScore`:
     - a directory pre-created at `testcall.json` makes the rename fail;
     - `.error` is emitted, then `.testScore(.scored)`, and `meeting.test.wer` is still set;
     - a fresh `open` emits `.unreadable`.
   - `everyLineSkippedWritesAZeroLineRecordAndLeavesWERNil`.
   - `finishTestOnAnOrdinaryMeetingDoesNothing`.
   - `scoredLogLineCarriesNoText`: `test call: scored wer=… lines=k/n latency_med=…`, and no script
     or transcript word in any captured line.

   Expected initial failure: `error: value of type 'MeetingController' has no member 'finishTest'`.
2. Run `swift test --filter MWMeetingPipelineTests`. Confirm the build error, scaffold, and
   confirm assertion failures.
3. Implement:
   - Score with the controller's segments, `segmentArrivals`, `registry.labels`,
     `SpeakerRegistry.userID`, `meeting.engine` and `deps.now()`.
   - `try await deps.store.writeTestCall`; on error, emit `.error`.
   - Set `meeting.test.wer` to the overall WER, or nil with zero scored lines. `saveMeeting()`
     refreshes the index.
   - Emit the score. Log the scored line.
4. Run `swift test` and the App tests. Confirm no regressions.

**Definition of done:** The `finishTest` row of the §5.11 controller table passes, and the
write-failure path matches §5.6.

**Risks specific to this stage:** None.

### Stage 13 — Test-call session and coordinator wiring

**Goal:**
- `TestCallSession` owns one meeting's conductor and player, bridges the controller to the
  sensor, and runs the Stop order: conductor end, `stop(false)`, `finishTest`, then `summarise`
  except on quit.
- `MeetingCoordinator` can start a test call, routes Stop and quit through the session, and
  forwards sleep.

**Design references:** §3 R3, R4, R5, R12, R13, R24, R27; §5.1 (`TestCallSession`); §5.3
`MeetingControlling`, `MeetingCoordinator`; §5.5 happy path steps 2–3, 8, Quit, Window closed,
Sleep; §5.9 start log line.

**Touches:**
- create `App/TestCall/TestCallSession.swift`:
  - `TestCallSession`;
  - `TestCallConducting` protocol, plus `extension TestCallConductor: TestCallConducting {}`;
  - `ControllerSpeechSensor: UserSpeechSensing`, mapping `SpeechGate.View.spans` to
    `ClosedRange<Double>`;
  - `TestCallSetup`: choice, engine, overlap, the parsed voice listing.
- edit `App/Meeting/MeetingCoordinator.swift`:
  - `Dependencies.testCalls`: the conductor factory, the voice loader, index and record readers,
    a meeting-time player factory;
  - `Session.test`;
  - `startTestCall(_:)`;
  - `stop(summarise:)` delegates to the session;
  - the event loop (`:290`) forwards `.state(.paused(.sleep))`.
- edit `App/AppDelegate.swift` (`:274`): real factories (`TestCallConductor`, `SayProcessPlayer`,
  `SystemClock`, `SystemVoices`, `store.index`, `store.readTestCall`).
- create `AppTests/TestCallSessionTests.swift`, with a private fake conductor and a logging
  `StubController`.
- edit `AppTests/MeetingCoordinatorTests.swift` (harness `testCalls` dependencies and tests)

**Steps (TDD):**
1. Write `TestCallSessionTests`:
   - `stopRunsEndStopScoreThenSummarise`: the call log reads `end(stop)`, `stop(false)`,
     `finishTest`, `summarise`.
   - `quitPathSkipsTheSummary`: `finish(summarise: false)`.
   - `sleepEndsTheScriptWithSleep`.
   - `sensorReadsTheController`: time, `isSpeaking`, spans as closed ranges, `lastAudibleSystemAudio`.
   - `startLogLineCarriesIdsOnly`: a local `LogSink` under `Log.withSinks` sees
     `test call: start scenario=<id> rev=<n> engine=<raw> overlap=<bool>`, and no script text.
2. Write tests in `MeetingCoordinatorTests`:
   - `startTestCallStartsARemoteMeetingWithTitleEngineAndTag`:
     - `starts` holds `.remote`, `"Test call · Sprint planning"`, the chosen engine;
     - the tag is `sprint-planning`, revision 1, `"Sprint planning"`, `wer: nil`.
   - `startTestCallWithUnavailableVoicesShowsTheVoiceMessage`: no start, and the R5 text in
     `errorMessage`.
   - `stopAndQuitGoThroughTheSession`.
   - `sleepEventReachesTheSession`.
   - `ordinaryMeetingsStopAsBefore`.

   Expected initial failure: `error: cannot find 'TestCallSession' in scope`.
3. Run the App tests. Confirm the build error, scaffold, and confirm assertion failures.
4. Implement:
   - `startTestCall` picks with `SystemRandomNumberGenerator`, casts from the setup's voice
     listing, then calls `controller.start(mode: .remote, title:, engine:, test:)`.
   - On success, the session builds the conductor and calls `run()`.
   - `finish(summarise:)` awaits the run task after `end(.stop)` before reading `result`.
5. Run the App tests and `swift test`. Confirm no regressions.

**Definition of done:**
- The §5.11 App row's Stop order is pinned.
- A test call can be started from the coordinator API. No UI reaches it yet.

**Risks specific to this stage:** None.

### Stage 14 — Script pane during the call

**Goal:** For a live test meeting, the right pane is `ScriptPane` (310 pt) in place of `NotesPane`.
The header shows the TEST chip and a disabled Pause with its tooltip. The source line carries the
labelling note. Every conductor event reaches the pane.

**Category:** Hybrid.
- Full TDD for `TestCallPaneModel`'s script state and the window model's test outputs.
- Platform-only/UI wiring for `ScriptPane` and the header, verified by the App build here and by
  the Stage 16 manual run against `mockup-v5-script-pane.html`.

**Design references:** §3 R9, R11, R12; §5.4 During the call; §5.5 step 7; §5.6 (`say` fails, no
system audio).

**Touches:**
- create `App/TestCall/TestCallPaneModel.swift` (`@Observable`, script half)
- create `App/TestCall/ScriptPane.swift`
- edit `App/Meeting/MeetingWindowModel.swift`:
  - owns `testCall: TestCallPaneModel?`, plus `isTest` from `show(_:)`;
  - `sourceLine` for test meetings;
  - `canPause`.
- edit `App/Meeting/MeetingView.swift`:
  - the recording view picks `ScriptPane` for test meetings (`:140`);
  - the header (`:145–174`) shows `TestTag` and Pause disabled with `.help("Not available in a test call")`.
- edit `App/TestCall/TestCallSession.swift`: conductor events and sleep reach the pane model.
- create `AppTests/TestCallPaneModelTests.swift`
- edit `AppTests/MeetingWindowModelTests.swift`

**Steps (TDD):**
1. Write `TestCallPaneModelTests` (script half):
   - `voiceTurnRingsTheLineAndTagsIt`: "Tom · Daniel voice · speaking", footer "Waits for the
     voice to finish".
   - `userTurnPromptsAndHints`: "Your turn · read this line aloud", "Hands over after a 1.2 s pause".
   - `showsUpToThreeEarlierLinesDimmedWithSkipped`.
   - `showsTheNextThreeAndTheRestCount`: "+ N more lines".
   - `headerCountsTheLine`: "Script · Sprint planning", "6 of 12".
   - `finishedReadsPressStop`: "Script finished · press Stop for the score".
   - `sleepShowsTheR12Message`.
   - `captureMissingShowsTheCaptureWarning`.
   - `voicesFailedShowsTheMessage`: "The test voices could not play."

   In `MeetingWindowModelTests`:
   - `testMeetingCannotPauseAndSaysWhy`;
   - `testSourceLineCarriesTheLabellingNote`;
   - `ordinaryMeetingsUnchanged`.

   Expected initial failure: `error: cannot find 'TestCallPaneModel' in scope`.
2. Run the App tests. Confirm the build error, scaffold, and confirm assertion failures.
3. Implement the model, `ScriptPane` per the accepted mockup (Reduce Motion makes the level bars
   static), and the header changes.
4. Run the App tests and `swift test`. Confirm no regressions.

**Definition of done:** The pane model tests are green, and test meetings show the script pane and
the R11 header.

**Risks specific to this stage:** None.

### Stage 15 — Score pane and Earlier runs

**Goal:** After Stop and on reopen, the right pane is `ScorePane`: the head block, the line list
with badges, and a row that expands and highlights its transcript. It shows the R20 messages when
no score exists. **Earlier runs…** opens a sheet comparing runs of the same scenario revision.

**Category:** Hybrid.
- Full TDD for the score half of `TestCallPaneModel`.
- Platform-only/UI wiring for `ScorePane`, the sheet and the transcript highlight, verified by the
  App build and the Stage 16 manual run against `mockup-v5-pane-score.html`.

**Design references:** §3 R15, R16, R18, R19, R20; §5.4 After Stop and on reopen; §5.8 Earlier
runs on a background task.

**Touches:**
- edit `App/TestCall/TestCallPaneModel.swift` (score half: head, rows, expansion, highlight, runs)
- create `App/TestCall/ScorePane.swift` (`ScorePane`, `EarlierRunsSheet`)
- edit `App/Meeting/MeetingWindowModel.swift`: `.testScore` feeds the pane model; segments
  intersecting a time window, for the highlight.
- edit `App/Meeting/MeetingView.swift`: the stopped test meeting shows `ScorePane`;
  `TranscriptView` highlights paragraphs holding the highlighted segments.
- edit `App/Meeting/MeetingCoordinator.swift`: the pane's run loader, which runs
  `TestRunHistory.runs` with `store.readTestCall` off the main actor.
- edit `AppTests/TestCallPaneModelTests.swift`

**Steps (TDD):**
1. Write the score-half tests, from a record matching the Stage 9 fixture:
   - `headShowsOverallWERAndErrorCount`: "6.4%", "word error rate · 10 errors in 157 words".
   - `roleRowsShowWERLabelAndPurityAmberWhenNotClean`:
     - Priya: "10.6%", "Speaker 2", "87%", amber;
     - a role with N = 0 shows "—".
   - `latencyLine`: "Latency 1.3 s median, 2.9 s max · 11 of 12 lines · cross-credited words: 0".
   - `lineBadges`: ✓ / "2 errors" / "Skipped" / "Stopped" / "Not reached", plus the amber "label"
     badge on line 9.
   - `expandedRowText`:
     - "Script · Priya";
     - "Heard · Speaker 2 · 00:00:41";
     - "2 errors (1 substituted, 1 extra) · final text 2.9 s after the voice ended".
   - `expandingHighlightsSegmentsInTheLinesWindow`: segments intersecting `[start − 0.5, end + 1.5]`.
   - `missingInterruptedUnreadableAndNoLinesMessages`: the three R20 texts. With no record, the
     line list is the library's script without badges.
   - `earlierRunsAreNewestFirstWithThisRunBold`, plus the footer "4 runs of this scenario" and
     the sheet's note text.

   Expected initial failure: `error: value of type 'TestCallPaneModel' has no member 'score'`.
2. Run the App tests. Confirm the build error, scaffold, and confirm assertion failures.
3. Implement the model, `ScorePane`, `EarlierRunsSheet` (columns Run, Engine, WER, You, <A>, <B>,
   Clean, Latency; **Done**) and the transcript highlight.
4. Run the App tests and `swift test`. Confirm no regressions.

**Definition of done:** The score-half tests are green. A reopened test meeting shows its score or
its R20 reason.

**Risks specific to this stage:** None.

### Stage 16 — Setup page and the Test Call… entry point

**Goal:**
- The chooser gains the bottom-left **Test Call…** link and the `TestCallSetupView` page:
  Scenario, Engine and Overlap; **‹ Back**; **Start Test Call**.
- Voices load once per chooser open.
- The link is disabled, with the R5 help text, when fewer than two English voices exist.

This makes the feature reachable.

**Category:** Hybrid.
- Full TDD for `TestCallSetupModel`, the chooser's engine availability and the coordinator's voice
  load.
- Integration-verified remainder, a manual run on this Mac:
  1. New Meeting → **Test Call…** → Sprint planning, the default engine, Overlap off → Start Test
     Call.
  2. Read the lines; Skip one; Stop.
  3. Compare the chooser, setup page, script pane and score pane with the three accepted mockups.

**Design references:** §3 R1, R2, R3, R5, R10; §5.4 Chooser and setup; §5.5 happy path step 1.

**Touches:**
- create `App/TestCall/TestCallSetupModel.swift`
- create `App/TestCall/TestCallSetupView.swift`
- edit `App/Meeting/MeetingWindowModel.swift`:
  - `Chooser` gains `keyedEngines: Set<MeetingEngine>`, computed in its existing `init`;
  - owns `setup: TestCallSetupModel` and `showsTestCallSetup`.
- edit `App/Meeting/MeetingView.swift`: `MeetingChooserView` (`:26`) gets the bottom-left link
  and swaps to the setup page in the same chooser window.
- edit `App/Meeting/MeetingCoordinator.swift`:
  - `MeetingActions.startTestCall`;
  - `openChooser()` loads voices off the main actor and fills scenario WERs from
    `TestRunHistory.latestWER(in: index, revisions:)`, both through the `Dependencies.testCalls`
    readers Stage 13 wired. `AppDelegate.swift` needs no further change.
- create `AppTests/TestCallSetupModelTests.swift`
- edit `AppTests/MeetingCoordinatorTests.swift`

**Steps (TDD):**
1. Write `TestCallSetupModelTests`:
   - `scenarioMenuRows`:
     - "Random · one of 8", a divider, then "<Title> — WER 6.4%" or "<Title> — not run";
     - "<Title> — WER 6.4% · uses Fred for Priya" when a substitute is cast.
   - `engineMenuListsAllFourWithDefaultAndNoKey`.
   - `defaultEngineIsPreselected`.
   - `startIsDisabledWithoutAnyKeyAndShowsTheNoKeyMessage`.
   - `linkIsDisabledWithFewerThanTwoEnglishVoices`: the R5 sentence as help text.
   - `backReturnsToTheChooser`.
   - `startTestCallCarriesChoiceEngineOverlapAndVoices`.

   In `MeetingCoordinatorTests`, `openChooserLoadsVoicesOnceAndScenarioWERs`.

   Expected initial failure: `error: cannot find 'TestCallSetupModel' in scope`.
2. Run the App tests. Confirm the build error, scaffold, and confirm assertion failures.
3. Implement the model, the view per `mockup-v5-chooser-options.html#test-link`, and the wiring.
4. Run the App tests and `swift test`. Confirm no regressions.
5. Do the manual run in the Category bullet above.

**Definition of done:**
- Setup tests are green. A test call runs end to end from the chooser.
- All four accepted mockups match on screen.

**Risks specific to this stage:** None.

### Stage 17 — Documentation and acceptance

**Goal:**
- README "Test call" section and CHANGELOG `Added` entry.
- The design's acceptance run per engine, with the listening pass over all 8 scenarios.

**Category:** Non-TDD (integration-verified). Documentation, plus live runs that need the user's
voice, `say` audio, the tap and real engines. Every check is named below.

**Design references:** §3 R22, R23, R26; §5.10 README and CHANGELOG; §5.11 Acceptance; §7 TTS
mispronunciation (listening pass); §9 Communication.

**Touches:**
- edit `README.md`: "Test call" section covering:
  - what it measures and its cost (~$0.02);
  - that the score is a relative benchmark;
  - that agents never see test calls;
  - how to add voices (System Settings → Accessibility → Spoken Content).
- edit `CHANGELOG.md`: `[Unreleased] ### Added`.
- edit `Packages/MiniWhisperCore/Sources/MWTestCall/ScenarioLibrary.swift`, only if the listening
  pass replaces a word.

**Steps:**
1. Write the README section and the CHANGELOG entry.
2. Acceptance:
   - Run a test call per engine with a key: up to four runs. Across them, cover all 8 scenarios
     by naming them (extra runs reuse the cheapest engine).
   - For each, confirm the Score pane, the list row (TEST chip, WER meta), a search hit in the
     Meetings list, and the Earlier runs sheet.
3. Listening pass during those runs:
   - Any word `say` mispronounces is replaced in `ScenarioLibrary` (revision stays 1, unreleased).
   - Re-run `swift test --filter ScenarioLibraryTests`.
4. Agents: `mini-whisper meetings list` and `mini-whisper meetings search "<a word from a test
   script>"` show no test call. `mini-whisper meetings transcript <8-hex prefix of a test id>`
   prints `no meeting <prefix>` and exits 2.
5. `git diff main -- Package.swift project.yml` adds no third-party package (R26).
6. Run the full core and app suites. Confirm green.

**Definition of done:** README and CHANGELOG are written, and every acceptance check above passed.

**Risks specific to this stage:** Each run costs about $0.02 in engine minutes, plus a summary
when an Anthropic key exists.

## Cross-cutting concerns

- **Security.**
  - `say` runs by absolute path with an argument array, no shell (Stage 10).
  - Script lines never start with `-` (Stage 6). Voice names pass the allow-list before casting
    and again before launch (Stages 5, 10).
  - `testcall.json` is 0600 through the store's rename write (Stage 2).
  - Agents see test meetings through no path: the decorator lands in Stage 4, before any stage can
    create a test meeting (Stages 13, 16).
  - No secret is touched beyond the existing engine key lookup (Stage 11).
- **Performance.**
  - The conductor's 100 ms main-actor poll does constant work (Stage 7).
  - Alignment is O(n·m) on about 15 tokens per line (Stages 3, 9). Scoring runs once, under
    100 ms.
  - The scenario menu reads only `index.json` (Stage 16). Earlier runs load ≤ 50 records off the
    main actor (Stages 5, 15).
- **Observability** (`Log.meeting`, ids and outcomes only, R27):
  - `start` from `TestCallSession` (Stage 13);
  - `line <i> skipped (<reason>)` and `voice substituted` from the conductor (Stage 7);
  - `scored` from the controller (Stage 12).

  Each has a test asserting no script or transcript text.
- **Compatibility / migration.**
  - The optional `test` fields decode absent as nil and encode nil as absent (Stage 2). No
    migration.
  - Every `Meeting(`/`IndexEntry(` call site compiles unchanged through defaulted parameters.
  - Core registration is in Stages 3 and 12; app linkage in Stage 3.
  - The `MeetingControlling` protocol and `StubController` change atomically in Stages 11 and 12.
  - The feature stays unreachable until Stage 16.

## Verification

Once Stage 17 is done, the user confirms the §3 acceptance criteria:
1. New Meeting → **Test Call…** → pick a scenario, an engine, Overlap → **Start Test Call**
   (R1–R5, R10).
2. Voices speak from `say`, each user line hands over after a pause, and Skip, silence and the cap
   behave (R6–R9). Pause is disabled with its tooltip (R11).
3. Stop: the Score pane shows overall and per-role WER, labels, purity, latency and line badges
   (R13–R18). The run bills and summarises like any meeting (R24).
4. Reopen it from the Meetings list: the same pane. **Earlier runs…** lists runs of the revision
   newest first, this one in bold (R19, R23).
5. `mini-whisper meetings list|search|transcript` never return it (R22).
6. Interrupt one run (force-quit during the call) and reopen it: "No score: the test call did not
   finish." (R20).
7. `swift test` and the app tests are green. No third-party dependency was added (R25, R26).

## Risks and open issues

- **Same-module symbol collisions in parallel batches.** Stages 5, 6, 7 and 9 add top-level
  symbols to `MWTestCall` from separate worktrees. A clash would surface only at cherry-pick.
  - Mitigation: each stage adds only the symbols its *Touches* names, and test helpers are
    `private`.
  - The main agent runs `swift build` after each batch lands.
- **Normaliser contract versus engine output.** Engines write numbers as "2 p.m.", "2:00 PM" or
  "14:00".
  - Mitigation: scripts contain no digits (Stage 6), so only the transcript side varies.
  - The Stage 3 table pins the canonical forms. Scripts avoid ambiguous time forms.
- **Scorer fixture precision.** Hitting 87% purity and 1.3 s median exactly needs a deliberate
  fixture.
  - Mitigation: build it per line from the mockup's badges (Stage 9). If a figure cannot be met
    without contradicting R14–R17, recompute the expectation under the requirement and note it in
    the test.
- **Hosted app tests in parallel.** Two `xcodebuild test` runs host apps with one bundle ID.
  - Mitigation: at most one App-test stage per parallel batch (*Execution schedule*). The others
    use the App build-only check.
- **`TEST_RUNNER_` passthrough.** It is unverified in this repo. Stage 10 reads the `Test run`
  line to catch a silent skip. Stage 17 exercises `say` live regardless.
- **Dirty working tree at start.** The tree holds the Stage 1 fix and the feature folder. Stage 1
  verifies the file list before committing.

## Planning decisions taken

1. Stage 1 lands the uncommitted ducking and leveller fix as its own commit before any test-call
   code, per §7 and §9 step 1.
2. `MWTestCall` depends on `MWMeetings`, `MWConfig`, `MWSupport`. The scorer's `engine: MeetingEngine`
   needs `MWConfig`, which `MWMeetings` already pulls in. Design §5.1 corrected in place.
3. `MWTestCallTests` depends on `MWOverlaySim` for `SeededRandom` (the repo's seeded RNG) and
   declares `Fixtures/` resources.
4. `project.yml` gains the `MWTestCall` product in Stage 3, because the app links products
   explicitly. Design §5.10 omitted it; corrected in place.
5. The shared value types (`TestScenario`, `ScenarioLine`, `ScenarioChoice`, `VoiceLine`, `CastVoice`,
   `VoiceCasting`) land in Stage 3. `TestCallRole` and the line status live in `MWMeetings`
   (Stage 2), because the record needs them and `MWMeetings` cannot import `MWTestCall`.
6. The normaliser and aligner ride with the module scaffold (Stage 3), because the scenario tests
   count tokens with the normaliser.
7. The normaliser's canonical forms are pinned by the Stage 3 table:
   - times `H:MM` → hour + minutes ("ten thirty", "nine oh five", ":00" → hour only);
   - currency → "<n> dollars [<cents>]";
   - 4-digit 1100–2099 integers as years ("twenty twenty six", 2000–2009 "two thousand <n>");
   - `’` → `'`; hyphen and dash characters split.
8. Scenario scripts contain no digits, a test-enforced authoring rule. The reference never depends
   on number spelling, and `say` reads exactly the reference.
9. "Lines never name or address the user" is tested as "every vocative is one of the scenario's two
   character names".
10. `ConductorEvent` gains `.captureMissing(index)` and `.voicesFailed`. Design §5.6 requires both
    signals, and §5.3's event list had no producer for them, so the operational section wins.
    Design §5.3 corrected in place.
11. With Overlap, both the selected user line and the voice line overlapping it are recorded
    `overlapped: true`.
12. Conductor and scorer fakes stay `private` in the `MWTestCallTests` files, as `MeetingHarness`
    does in `MWMeetingPipelineTests`. Putting them in `MWTestSupport` would add a `Package.swift`
    edit and serialise Stage 7.
13. `TestRunHistory.latestWER(in:revisions:)` takes the current revisions explicitly. "Current
    revision" had no input, and reading `ScenarioLibrary` would tie Stage 5 to Stage 6.
    `runs(of:in:load:)` returns `Run` (meeting id, `startedAt`, record) for the sheet's Run column
    and bold row.
14. `TestCallScorer.score` gains `scoredAt: Date`, because the record's `scoredAt` had no input.
    The controller passes `deps.now()`.
15. In `heard`, a run of consecutive error transcript words is one entry whose `script` joins the
    substituted script words. This matches the §5.2 example ("Cooper Netties" ← "Kubernetes").
16. Every record line carries `reference`, skipped, stopped and not-reached included. §5.6 makes
    records self-contained, and §5.4 lists every line's text. The §5.2 example corrected in place.
17. `labels` is `[String: Int]` in Swift, because `JSONEncoder` writes `[Int: Int]` as a flat
    array, not the §5.2 object.
18. The scorer fixture uses R14's hyphen split. The mockup's "one-line" is two tokens, giving 157
    words, You 4.2%, overall 6.4% (the mockup shows 156 / 4.3%). The requirement wins over a
    placeholder figure. Design §5.11 and the §5.2 example corrected in place.
19. `AgentMeetings.load` throws `CocoaError(.fileReadNoSuchFile)`, code 260. That is what
    `Data(contentsOf:)` throws for a missing meeting folder, verified on this Mac; the design said
    `.fileNoSuchFile`. Design §5.3 corrected in place.
20. The agent-filter tests seed a real temp `MeetingStore` (`SeededMeetings` plus one tagged
    meeting) in a new `AgentMeetingsTests.swift`. `SeededMeetings` is untouched, so the existing
    CLI and MCP expectations hold.
21. `MeetingFixtures.make` gains `test:` (Stage 2) for every later core test.
22. The controller work splits:
    - plumbing, Stage 11, which needs no `MWTestCall`;
    - `finishTest`, Stage 12, which adds the `MWMeetingPipeline → MWTestCall` edge.
23. Protocol methods cannot have default arguments. The coordinator's one ordinary `start` call
    therefore passes `engine: nil, test: nil` explicitly.
24. App test-call code lives in `App/TestCall/`, and its tests in `AppTests/<Type>Tests.swift`.
25. `TestCallSession` takes a `TestCallConducting` protocol that `TestCallConductor` conforms to.
    AppTests cannot link `VirtualClock`, so they drive the session with a fake conductor.
26. The test-call window state is a separate `TestCallPaneModel` owned by `MeetingWindowModel`
    (633 lines today). The new views are new files.
27. The entry point lands last (Stage 16), after the session, script pane and score pane. No
    half-built test call is reachable between merges.
28. Score-row highlight: transcript segments intersecting the line's scoring window
    `[start − 0.5 s, end + 1.5 s]`. The record stores no segment ids.
29. A scenario menu row with both WER and a substitution reads "<Title> — WER 6.4% · uses <Voice>
    for <Character>".
30. The list meta uses `MeetingEngine.title`, e.g. "AssemblyAI Universal-Streaming". The mockup's
    "AssemblyAI Streaming" is a placeholder.
31. The listening pass is the Stage 17 acceptance run over all 8 scenarios. A replaced word keeps
    revision 1 while it is unreleased.
32. The coordinator casts voices from the listing loaded at chooser open, carried in
    `TestCallSetup`. Stage 13 tests pass it directly.
33. Log line owners:
    - `start` from `TestCallSession` (it knows engine and overlap);
    - `skipped` and `voice substituted` from the conductor;
    - `scored` from the controller.
34. At most one stage per parallel batch runs `xcodebuild … test`. Two hosted test apps with one
    bundle ID count as a shared test resource. The other stages use the App build-only check.
35. Anchors re-resolved and corrected in the design in place:
    - `checkSystemAudio()` `:335`;
    - `pauseOrResume` `:233`;
    - `row(for:)` `:298`;
    - `MCPServer` search `:209–211`.
36. Design §5.4's "same 560 pt card" corrected in place: the chooser fills the 920 × 620 meeting
    window (`MeetingWindowController.swift:14`), and the setup page swaps in there.
37. `SayProcessPlayer` unit tests use `/usr/bin/true`, `/usr/bin/false`, `/bin/cat` and `/bin/echo` as
    stand-in executables. They spawn real trivial processes with no audio and no real sleep.

## Deviations from the design

None — plan matches design v5 exactly.

## Deviations from plan

1. **Stage 1.** `AVAudioEngineBackendIntegrationTests` gained `.serialized`. Run in parallel, its
   three tests open the same microphone at once, and voice processing changes the input format
   under the other engines: one run crashed in `installTap`, another lost
   `deliversABufferWithinOneSecond`. Serial runs passed 3 of 3 before and after the change.
2. **Stage 3.** The aligner breaks ties walking forward from the start over a suffix-cost table,
   preferring match or substitute, then insert, then delete. A backtrace from the end with that
   preference gives `insert(web)`, `substitute(webhook→hook)`, not the pinned
   `substitute(webhook→web)`, `insert(hook)`; the forward walk gives the pinned order.
3. **Stage 3.** `Alignment` is nested as `WordAligner.Alignment`. A top-level `Alignment` would
   clash with SwiftUI's in every App file that imports `MWTestCall`.
4. **Stage 3.** Currency reads `$1` as "one dollar", and a fraction other than two digits as a
   decimal (`$1.5` → "one point five dollars"). The literal `<n> dollars [<cents>]` form would make
   `$1` "one dollars", which no script matches.
5. **Stage 5.** A listed English voice that fails the name allow-list does not count towards R5's
   two English voices, because it can never be cast.
6. **Stage 7.**
   - `RunLine.index` and every `ConductorEvent` line number are 1-based script line numbers, as in
     the record (§5.2), the pane's "6 of 12" and the log.
   - The conductor takes `casting: [TestCallRole: CastVoice]`, the `.ready` payload, so it never
     holds `.unavailable`.
   - Overlap flags record only overlaps that happened: when the user's line ends before its voice
     launches, both flags are cleared and the voice plays alone.
   - Skip and `end` during an overlap end both lines under way and stop `say`.
   - "Two consecutive `say` failures" counts `say` runs; only a normal exit resets the count.
   - Skip reasons log as `skip`, `no speech` and `voice failed`.
   - Deadlines compare with a 1 µs tolerance, because meeting times are sums of floating seconds.
7. **Stage 9.**
   - Labels, purity and cross-credited counts count only transcript tokens aligned to a script
     word (match or substitution); an inserted token carries no label. That is R16's "the role's
     words" and the §5.2 example (line 6: 17 words, 1 S, 1 I → `labels {"2": 17}`). Counting every
     token would give Priya 88%, not the accepted 87%.
   - Clean is not stored on the record. `TestCallScorer.isClean(_:among:)` derives it, and
     `TestCallScorer.window(start:end:)` gives the scoring window, for Stage 15.
8. **Stage 10.**
   - `SayProcessPlayer` gives each process an idle stdin `Pipe`. The stop test plays the text `-`,
     so the `/bin/cat` stand-in blocks on stdin until `stop()`.
   - `tapHearsASayProcess` shares a `firstAudibleLevel(playing:_:)` helper with the existing
     `afplay` test, which now uses it.
   - Both tap integration tests fail on this Mac without System Audio Recording permission for
     the terminal, the existing `afplay` test included. Pending a run with the permission granted.
9. **Stage 11.** After a sleep, `resume()` of a test meeting does nothing, as design §5.3's guard
   reads: the meeting stays `.paused(.sleep)` until Stop. `sleepStillPausesATestMeeting` pins it.
10. **Stage 13.**
    - `FakeConductor`, `FakePlayer` and `CallLog` are internal in `TestCallSessionTests.swift`, not
      private: `MeetingCoordinatorTests`' harness builds its test calls with them, as `StubApps`
      is shared.
    - The R5 sentence lives in `TestCallSetup.voicesUnavailable`, for Stage 16's link help text.
    - `start()` and `startTestCall(_:)` share one private `begin(_:_:)`: the idle guard, ending
      dictation, the start error and `show(meeting)`.
    - `TestCallSession` also has `skip()` (design §5.1) and ignores a second `finish`, so a second
      Stop during the run's last poll cannot score twice.
11. **Stage 14.**
    - `MeetingCoordinator.swift` is edited too: `MeetingActions.skipLine` takes the pane's Skip
      line to `TestCallSession.skip()`, and `startTestCall` attaches the session's pane to the
      window model. `MeetingCoordinatorTests` and `TestCallSessionTests` (`FakeConductor.send`)
      test both.
    - The session creates the pane with its casting. `show(_:)` creates one from the tag's
      library script for a tagged meeting, so `isTest` is `testCall != nil`; the session's pane
      replaces it at start.
    - The TEST chip takes the place of the mode chip, as in the mockup's header.
    - The pane keeps the Notes pane's background (`underPageBackgroundColor`), not the mockup's
      `#f6f6f8`; its notices sit on the text background, as the window's banners do.
    - One remaining line reads "+ 1 more line" (the mockup's "+ 1 more lines" is a placeholder).
    - A stopped test meeting's source line reads "… · speaker names stay as the engine labelled
      them", as in the score mockup.
12. **Stage 15.**
    - Earlier runs load when the score pane appears, not when the sheet opens, so the footer's
      "N runs of this scenario" counts the rows the sheet shows. They still load off the main
      actor and read at most 50 records.
    - The loader is a `MeetingWindowModel` init parameter (with `now`), built by the coordinator's
      `makeModel()`. `MeetingCoordinatorTests.earlierRunsReadTheIndexAndRecordsOffTheMainActor`
      tests it.
    - The pane shows the script until the score arrives, then the score.
    - The pane header reads "Score" with the scenario title at the right, as in the mockup.
    - A user line's breakdown ends "final text X s after you stopped speaking"; the design words
      only the voice case.
    - The Run column reads "Today 11:14" or "9 Nov 16:40", with the year for another year's run.
    - An opened line scrolls its highlighted paragraph into view.

## Execution schedule

Batches run in order; a batch starts only when the previous one has fully landed. Stages inside a *parallel* batch are independent and may be built concurrently; a *serial* batch holds one stage. `/feature-implement` follows this table and demotes any batch it cannot verify to serial.

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1 | serial | lands pre-existing work every later stage builds on and measures |
| 2 | Stage 2 | serial | shared-type change: `Meeting` and `IndexEntry` (Step 4 blast-radius set) |
| 3 | Stage 3 | serial | scaffolding and convention-establishing; edits `Package.swift`, `project.yml` |
| 4 | Stage 4, Stage 5, Stage 6, Stage 7, Stage 8 | parallel | See *Batch 4 evidence* below. |
| 5 | Stage 9, Stage 10 | parallel | See *Batch 5 evidence* below. |
| 6 | Stage 11 | serial | shared signature: `MeetingController.start`, `MeetingControlling`, the `MeetingEvent` exhaustive switch |
| 7 | Stage 12 | serial | `Package.swift` dependency edge and a `MeetingControlling` change |
| 8 | Stage 13 | serial | consumes Stages 9–12 |
| 9 | Stage 14 | serial | shares `MeetingView.swift`, `MeetingWindowModel.swift` and `TestCallSession.swift` with its neighbours |
| 10 | Stage 15 | serial | shares `TestCallPaneModel.swift`, `MeetingView.swift` and `MeetingWindowModel.swift` |
| 11 | Stage 16 | serial | shares `MeetingView.swift`, `MeetingWindowModel.swift` and `MeetingCoordinator.swift`; the entry point lands last |
| 12 | Stage 17 | serial | integration-verified acceptance of everything |

**Batch 4 evidence.**
- *Disjoint files.*
  - Stage 4: `MWAgentAccess/AgentMeetings.swift`, its tests, `App/AgentCommand.swift`.
  - Stage 5: `VoiceCatalog`, `TestRunHistory` and their tests.
  - Stage 6: `ScenarioLibrary` and its tests.
  - Stage 7: `TestCallRun`, `TestCallConductor` and their tests.
  - Stage 8: `MeetingsListModel`, `MeetingsListView`, `App/TestCall/TestTag.swift`,
    `MeetingsListModelTests`.
  - The xcodeproj is generated and git-ignored.
- *No symbol or string-keyed dependency.* Each consumes only Stages 2 and 3. No new type is used
  across the five, and the names are disjoint.
- *No shared registration point.* None edits `Package.swift`, `project.yml` or an exhaustive switch.
- *Same base state.* All are green on Batch 3.
- *Category exclusions.* No scaffolding, shared-signature, migration or dependency stage.
- *Security ordering.* Stage 4 is the protection, and no test meeting can exist before Stage 13.
- *No shared test resource.*
  - Only Stage 8 runs `xcodebuild … test`; Stage 4 uses the App build-only check.
  - Core suites use per-test `TempDirectory` and `VirtualClock`.

**Batch 5 evidence.**
- *Disjoint files.*
  - Stage 9: `TestCallScorer` and its tests and fixture.
  - Stage 10: `App/TestCall/SayProcessPlayer.swift`, `SystemVoices.swift`,
    `AppTests/SayProcessPlayerTests.swift`, `MWAudioTests/SystemAudioTapIntegrationTests.swift`.
- *No symbol or string-keyed dependency.* Both consume only Stages 2–7.
- *No shared registration point.* Neither edits a manifest or a switch.
- *Same base state.* Both are green on Batch 4.
- *Category exclusions.* None applies.
- *Security ordering.* No window opens.
- *No shared test resource.* Only Stage 10 runs `xcodebuild … test`. Its opt-in audio integration
  runs are manual and outside the batch's unit runs.

**Critical path:** Stage 1 → Stage 2 → Stage 3 → Stage 7 → Stage 9 → Stage 11 → Stage 12 → Stage 13 → Stage 14 → Stage 15 → Stage 16 → Stage 17 (12 of 17 stages).

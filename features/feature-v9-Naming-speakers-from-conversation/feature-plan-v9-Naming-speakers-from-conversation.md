# Naming speakers from conversation — Implementation Plan v9

**Status:** Draft
**Date:** 2026-11-22
**Design:** [feature-design-v9-Naming-speakers-from-conversation.md](./feature-design-v9-Naming-speakers-from-conversation.md)

## Overview

v9 suggests speaker names from what is said in a meeting, using Claude Haiku 5.5 over the whole transcript so far: live after a name-bearing turn, once at Stop, and on demand on a stopped or stored meeting. The plan builds bottom-up in 18 stages. The pure `MWNaming` module and its test target come first (Stage 1), then the shared escaping helper (2), the additive data, config, pricing and log changes (3–5), and the pure naming pieces: spotter and trigger (6), transcript and prompt (10), evidence and policy (12). The client seam (7), the registry rules (8) and the Settings card (9) run beside them, and the controller gains the user actions on conversation matches early (11). `MeetingNamingRoute` (13) joins the pure pieces, and the controller then gains live naming (14), and the Stop pass and Suggest names (15). The app surfaces follow (16, 18), with the opt-in replay test (17). The app only starts sending transcripts in Stage 18, once every disclosure surface exists. Every numbered requirement R1–R30 of the design maps to at least one stage below. Each §5 component has a stage that creates it.

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only | integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests, platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a one-line justification.

**Swift's first red.** A stage that introduces a new type or module cannot reach a red assertion first. The test target fails to build, with `error: cannot find 'X' in scope`, `value of type 'Y' has no member 'z'`, `extra argument 'z' in call` or, for a new target, SwiftPM's empty-target error. That build error is the expected initial failure. The stage then scaffolds the minimal empty API and re-confirms red as Swift Testing failures (`✘ Test … recorded an issue … Expectation failed`) before implementing.

**Runners and commands** (all run once before drafting; baselines observed 2026-11-22):

| Layer | Command | Baseline |
|---|---|---|
| Core package tests (Swift Testing) | `cd Packages/MiniWhisperCore && swift test` | exit 0; 18 `✔ Test run with …` lines (one per test target), 1,305 tests in total, 0 `✘` |
| One suite | `cd Packages/MiniWhisperCore && swift test --filter <SuiteOrTarget>` | — |
| App tests (Swift Testing via xcodebuild) | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` | `✔ Test run with 519 tests in 50 suites passed` + `** TEST SUCCEEDED **` |
| App build-only check | same with `build` in place of `test` | `** BUILD SUCCEEDED **` |

Read the `✔/✘ Test run with N tests…` lines, not the XCTest `Executed 0 tests` lines (CLAUDE.md).

**Per-stage regression rule.** A stage touching only `Packages/MiniWhisperCore` runs the full `swift test` plus the app build-only check, because the app imports every core module. A stage touching `App/` or `AppTests/` runs the full app test command too. Only stages that run `xcodebuild … test` launch the app test host, which is the shared resource that keeps app stages out of each other's batches.

**Conventions grounded in the repo.**
- Registration is explicit (CLAUDE.md). A new target goes into `Package.swift` `targets:` and `products:`, and the app's use of a new product goes into `project.yml`. New files inside an existing target or app folder are auto-discovered (SwiftPM folders, xcodegen folder sources).
- Test locations follow `Tests/<Module>Tests/<Type>Tests.swift` with `@Suite struct <Type>Tests`. Siblings: `Tests/MWVoicesTests/VoiceScrubberTests.swift` (a newer module's target), `Tests/MWMeetingPipelineTests/SpeakerRegistryTests.swift`, `Tests/MWMeetingPipelineTests/MeetingControllerVoiceLearningTests.swift`, `Tests/MWTranscriptionTests/AnthropicClientTests.swift`, `Tests/MWUsageTests/PricingTests.swift`, `Tests/MWConfigTests/ConfigCodingTests.swift`, `Tests/MWMeetingsTests/MeetingModelTests.swift`, and `AppTests/SettingsModelTests.swift`, `AppTests/MeetingWindowModelTests.swift`, `AppTests/MeetingCoordinatorTests.swift`.
- Shared fakes live in the library target `Sources/MWTestSupport` (sibling: `FakeSummarizer.swift`, with `hold()`/`release()`). App tests cannot import it and use `AppTests/ManualClock.swift`. Controller tests use `MeetingHarness` (`Tests/MWMeetingPipelineTests/MeetingControllerTests.swift:449`) with `VirtualClock`, and stored meetings come from `harness.seed(_:)` plus `MeetingFixtures` (sibling: `MeetingControllerRegenerateTests.opened`). Log content is checked with `CapturingLogSink` and `Log.withSinks`.
- Integration tests are opt-in via `.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1")` (sibling: `Tests/MWTranscriptionTests/AnthropicIntegrationTests.swift`).

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: Speaker names card, "Suggest names from the conversation" switch, default on, disclosure text | Stage 4, Stage 9, Stage 14, Stage 18 |
| R2: "Apply self-introductions without asking" switch, default off, disabled while R1 is off | Stage 4, Stage 9, Stage 12, Stage 14 |
| R3: No Anthropic key: switches off and locked, key hint, values restored with a key | Stage 9, Stage 14 |
| R4: Switches take effect at once; late reply dropped; shown suggestions stay | Stage 13, Stage 14 |
| R5: Live trigger: armed by a spotted name, fired by another speaker or 20 s | Stage 6, Stage 13, Stage 14 |
| R6: One request in flight; coalesced follow-up; never cancelled | Stage 6, Stage 13, Stage 14 |
| R7: No request without an open speaker, switch, key, when paused, or in a test call | Stage 14, Stage 15 |
| R8: Whole meeting as numbered `S<id>` turns plus the state block | Stage 10, Stage 13 |
| R9: Haiku 5.5, effort medium, 8000 tokens, JSON schema, 60 s, no fallback or retry | Stage 7, Stage 10, Stage 13 |
| R10: Cache breakpoints on the system prompt and the last closed 5-minute block | Stage 7, Stage 10 |
| R11: Stop pass after the in-flight request; ordering with the summary; running line | Stage 15, Stage 18 |
| R12: Kept only when certain, quote verified in the cited turn, name in the quote | Stage 1, Stage 3, Stage 12 |
| R13: Suggestions target open speakers only, re-checked at apply | Stage 8, Stage 12, Stage 14 |
| R14: People spelling for a fold-equal name | Stage 1, Stage 12 |
| R15: The user's name and spellings: dropped remote, the user's own name in a room | Stage 12 |
| R16: Dismissed names and rejected people never suggested again | Stage 3, Stage 12 |
| R17: Standing suggestions persist; same name unchanged; different name replaces | Stage 8, Stage 12 |
| R18: Provisional-name display with the "?" evidence popover and quiet actions | Stage 16 |
| R19: Accept renames, merges, links and teaches like typing the name | Stage 8, Stage 11 |
| R20: Dismiss records `rejectedNames` | Stage 8, Stage 11, Stage 16 |
| R21: That's me withdraws same-name suggestions and stores the alias | Stage 4, Stage 8, Stage 11, Stage 16 |
| R22: Auto-apply of verified self-introductions | Stage 8, Stage 12, Stage 14 |
| R23: "Not <name>" on an auto-applied name reverts and rejects it | Stage 8, Stage 11, Stage 16 |
| R24: "Your name, as misheard" list with add and remove rules | Stage 4, Stage 9 |
| R25: Suggest names on a stopped or stored meeting, its states and wording | Stage 15, Stage 18 |
| R26: One-time notice under the live header with the Meetings Settings… link | Stage 4, Stage 14, Stage 16, Stage 18 |
| R27: Failures: silent single failure, pause on 401/403 or three in a row, reset on success | Stage 7, Stage 13, Stage 14, Stage 16 |
| R28: Haiku pricing with cache and long-prompt rates, naming cost on the meeting, chip and usage | Stage 3, Stage 5, Stage 7, Stage 13, Stage 14, Stage 15, Stage 18 |
| R29: Naming logs carry counts, tokens, durations and status only | Stage 5, Stage 7, Stage 11, Stage 13, Stage 14 |
| R30: Opt-in replay integration test | Stage 17 |

## Stages

### Stage 1 — MWNaming module with NameFold and NameSanitiser
**Goal:** Establish the new pure module and its test target, with the name comparison key and the name sanitiser every later stage uses.
**Design references:** §5 Architecture (`MWNaming`, Registration, `NameFold`, `NameSanitiser`), §5 Security (output handling), §5 Testing strategy
**Touches:** `Packages/MiniWhisperCore/Package.swift`; `Packages/MiniWhisperCore/Sources/MWNaming/NameFold.swift` (create); `Packages/MiniWhisperCore/Sources/MWNaming/NameSanitiser.swift` (create); `Packages/MiniWhisperCore/Tests/MWNamingTests/NameFoldTests.swift` (create); `Packages/MiniWhisperCore/Tests/MWNamingTests/NameSanitiserTests.swift` (create); `project.yml`; `CLAUDE.md` (module map row)

Convention-establishing stage: the `MWNaming` layer gets its target, product and test target here. Its tests follow the `Tests/MWVoicesTests/` pattern: a test target depending on its module plus `MWTestSupport`.

**Steps (TDD):**
1. Write tests: `Tests/MWNamingTests/NameFoldTests.swift` → `@Suite struct NameFoldTests` table tests: `"  Zoë  Smith "` and `"zoe smith"` give one key; case folded; diacritics folded (`"Siân"` = `"sian"`); inner whitespace collapsed. `Tests/MWNamingTests/NameSanitiserTests.swift` → `NameSanitiserTests`: keeps `"Kate"`, `"Mary-Jane O’Neil"`, `"Dr. Ng"` (trimmed); rejects `""`, `"Speaker 4"`, `"Kate2"`, `"@Kate"`, `"'Kate"` (leading punctuation), a 61-letter name, `"Kate <b>"`. Register in `Package.swift`: product `.library(name: "MWNaming", targets: ["MWNaming"])`, `.target(name: "MWNaming", dependencies: ["MWMeetings", "MWSupport", "MWTranscription"])`, `"MWNaming"` added to `MWMeetingPipeline`'s dependencies, `.testTarget(name: "MWNamingTests", dependencies: ["MWNaming", "MWTestSupport"])`. Expected initial failure: SwiftPM refuses the manifest because target `MWNaming` has no source files under `Sources/MWNaming`.
2. Run `swift test --filter MWNamingTests` — confirm the empty-target error. Scaffold `public enum NameFold { public static func key(_ s: String) -> String { s } }` and `public enum NameSanitiser { public static func clean(_ s: String) -> String? { nil } }`. Re-run and confirm red as expectation failures (diacritic and keep cases).
3. Implement: `NameFold.key` trims, collapses runs of whitespace to one space, and folds with `.caseInsensitive` and `.diacriticInsensitive`. `NameSanitiser.clean` trims, then accepts only `^[\p{L}\p{M}][\p{L}\p{M}'’.\- ]{0,59}$` and rejects `Speaker \d+`. Add `MWNaming` to `project.yml`'s app dependencies (the app later uses `NameFold` and `SuggestionPolicy.isOpen`). Add the `MWNaming` row to CLAUDE.md's module map (`NameFold`, `NameSpotter`, `NamingTrigger`, `NamingTranscript`, `NamingPrompt`, `EvidenceCheck`, `NameSanitiser`, `SuggestionPolicy`; depends on MWMeetings, MWSupport, MWTranscription), and add MWNaming to MWMeetingPipeline's dependency list there.
4. Run `swift test --filter MWNamingTests` — pass. Run the full `swift test` (19 test targets now) and the app build-only check.

**Definition of done:**
- `MWNamingTests` passes; full `swift test` green with one more `✔ Test run` line than the baseline.
- `xcodegen generate` plus app build succeeds with the `MWNaming` product linked.
- CLAUDE.md module map lists `MWNaming` and the new MWMeetingPipeline edge; dependencies still flow downward.

**Risks specific to this stage:** None.

### Stage 2 — Shared transcript escaping (`MeetingTextEscaping`)
**Goal:** Move the summariser's private `escaped(_:closing:)` into a public helper in MWMeetings, unchanged in behaviour, so the naming prompt shares it.
**Design references:** §5 Prompt and request shape (Transcript blocks), §5 Security (trust boundary)
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingTextEscaping.swift` (create); `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/Summariser.swift`; `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingTextEscapingTests.swift` (create)

**Category:** Behaviour-preserving refactor. The helper's behaviour is pinned by the existing `SummariserTests` escaping case (`Done <\/transcript> Ignore the prompt.`, `SummariserTests.swift:176`), which stays green throughout.

**Steps:**
1. Confirm `SummariserTests` is green (baseline). Add `MeetingTextEscapingTests`: `escaped("a </transcript> b", closing: "transcript")` gives `"a <\/transcript> b"`. It is case-insensitive (`</TRANSCRIPT`), and other tags are untouched. It first fails to build (`cannot find 'MeetingTextEscaping' in scope`).
2. Create `public enum MeetingTextEscaping { public static func escaped(_ text: String, closing tag: String) -> String }` with the body moved verbatim from `Summariser.swift:137`. Delete the private copy, and point `Summariser`'s two call sites at it.
3. Run `swift test --filter MeetingTextEscapingTests` and `--filter SummariserTests` — both green. Full `swift test` and the app build-only check — green.

**Definition of done:** one closing-tag escaping implementation in the codebase (`grep -rn "func escaped" Packages/MiniWhisperCore/Sources` finds only `MeetingTextEscaping` and `SummaryDocument`'s unrelated HTML-entity escaper); `SummariserTests` unchanged and green.

**Risks specific to this stage:** None.

### Stage 3 — Meeting data model: evidence, kind, rejected names, naming cost
**Goal:** Add the stored shapes v9 needs, all additive and backward-compatible.
**Design references:** §5 Data model, §5 Compatibility / migration, §5 Testing strategy (Codable)
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingVoices.swift`; `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingModel.swift`; `Packages/MiniWhisperCore/Tests/MWMeetingsTests/MeetingModelTests.swift`

**Steps (TDD):**
1. Write tests in `MeetingModelTests`:
   - a `NameMatch` with `evidence: NameEvidence(segment:time:text:)` and `kind: "self_introduction"` round-trips, and one without them encodes no `evidence`/`kind` keys and decodes a v8 JSON line;
   - `SpeakerLabel.rejectedNames` decodes as `[]` when absent, is omitted when empty, and round-trips when set;
   - `Billing.namingCostUSD` decodes as 0 when absent;
   - `Billing` with `namingCostUSD == 0` encodes byte-identically to today's output (compare against a fixed JSON string built from `MeetingCoding.encoder()` for `Billing(engineSeconds: 60, costUSD: 0.4, replacedSummaryCostUSD: 0.03106)`, which still contains `replacedSummaryCostUSD`); a non-zero `namingCostUSD` is written and round-trips;
   - `Meeting.totalCostUSD` adds `namingCostUSD`;
   - `SpeakerLabel.defaultName(3) == "Speaker 3"`.

   Expected initial failure: build errors `extra argument 'evidence' in call`, `value of type 'SpeakerLabel' has no member 'rejectedNames'`, `extra argument 'namingCostUSD' in call`.
2. Run `swift test --filter MeetingModelTests` — confirm the build errors.
3. Implement:
   - `public struct NameEvidence: Codable, Sendable, Equatable { segment: UUID; time: Double; text: String }` in `MeetingVoices.swift`;
   - `NameMatch` gains `evidence: NameEvidence?` and `kind: String?`, with defaulted `nil` init parameters (synthesized Codable omits nil);
   - `SpeakerLabel` gains `rejectedNames: [String]` (defaulted init parameter, a `CodingKeys` case, `decodeIfPresent ?? []`, encoded only when non-empty), plus `public static func defaultName(_ id: Int) -> String`;
   - `Billing` gains `namingCostUSD` (defaulted init parameter, `decodeIfPresent ?? 0`) and a hand-written `encode(to:)` that writes the four existing keys exactly as now and `namingCostUSD` only when non-zero;
   - `Meeting.totalCostUSD` adds it.
4. Run the suite — pass; full `swift test` and app build-only — green (every existing `NameMatch(`, `SpeakerLabel(`, `Billing(` call compiles unchanged).

**Definition of done:** the Codable cases above pass. Existing meeting fixtures (`Tests/MWMeetingsTests/Fixtures/meeting-v0.5.json`, `golden/`) still decode and their tests pass.

**Risks specific to this stage:** A hand-written `Billing` encoder can drift from the synthesized key names. The byte-identity test guards it.

### Stage 4 — Config keys for naming
**Goal:** Add the four config fields with their keys, defaults and round-trip.
**Design references:** §5 Data model (`Config`), R1, R2, R21, R24, R26
**Touches:** `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`; `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`

**Steps (TDD):**
1. Write tests in `ConfigCodingTests` (siblings `meetingKeysAbsentTakeDefaults`, `meetingKeysRoundTrip`, `meetingKeysNeverLandInExtra`):
   - absent keys give `meetingNamingEnabled == true`, `meetingNamingAutoApply == false`, `meetingUserNameAliases == []` and `meetingNamingExplained == false`;
   - all four round-trip under `meeting_naming_enabled`, `meeting_naming_auto_apply`, `meeting_user_name_aliases` and `meeting_naming_explained`;
   - none lands in `extra`;
   - `Config().encoded()` writes all four.

   Expected initial failure: `value of type 'Config' has no member 'meetingNamingEnabled'`.
2. Run `swift test --filter ConfigCodingTests` — confirm.
3. Implement, following `meetingSystemAudioExplained`: the properties beside it (`:130`), `Key` constants (`:218`), entries in `Key.all` (`:240`–`:248`), decodes (`:275`) and encodes (`:352`).
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** the four keys default, decode, encode and stay out of `extra`.

**Risks specific to this stage:** None.

### Stage 5 — Cache token accounting, Haiku pricing and the naming log category
**Goal:** Carry cache tokens in `TokenUsage`, price a naming request, and give naming its own log category.
**Design references:** §5 Architecture (MWUsage / MWSupport), §5 Observability, R28, R29
**Touches:** `Packages/MiniWhisperCore/Sources/MWSupport/TokenUsage.swift`; `Packages/MiniWhisperCore/Sources/MWSupport/Log.swift`; `Packages/MiniWhisperCore/Sources/MWUsage/Pricing.swift`; `Packages/MiniWhisperCore/Tests/MWSupportTests/TokenUsageTests.swift` (create); `Packages/MiniWhisperCore/Tests/MWSupportTests/LogTests.swift`; `Packages/MiniWhisperCore/Tests/MWUsageTests/PricingTests.swift`

**Steps (TDD):**
1. Write tests:
   - `TokenUsageTests`: `TokenUsage(inputTokens: 1, outputTokens: 2)` has zero cache fields, and the fields are settable;
   - `LogTests`: a record through `Log.naming` carries category `"naming"`;
   - `PricingTests`:
     - the four `claude-haiku-5-5_*` rates (0.10, 0.50, 0.50, 2.50);
     - `namingCost` at base rates for input and output;
     - cache read at 0.1× and cache write at 1.25× the input rate;
     - the long rates applying at 100,001 total input tokens (input + cache read + cache write) and not at 100,000;
     - overrides of `claude-haiku-5-5_in` and `_in_long` honoured, the cache multipliers following them;
     - the result rounded to micros like `meetingCost`.

   Expected initial failure: `extra argument 'cacheReadTokens' in call`, `type 'Log' has no member 'naming'`, `type 'Pricing' has no member 'namingCost'`.
2. Run `swift test --filter TokenUsageTests`, `--filter LogTests`, `--filter PricingTests` — confirm.
3. Implement:
   - `TokenUsage.cacheReadTokens` and `cacheWriteTokens` (defaulted 0 init parameters, so all 42 existing constructions compile unchanged);
   - `Log.naming = LogCategory(name: "naming")`, with a doc comment that it carries counts, tokens, durations and status codes only;
   - the four `perMTok` entries;
   - `Pricing.namingCost(_ tokens: TokenUsage, overrides: [String: Double]) -> Double`, every rate through `rate()`.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** pricing maths matches design §5 MWUsage for each listed case; no existing test changes.

**Risks specific to this stage:** None.

### Stage 6 — Name spotter and live trigger
**Goal:** Decide whether a segment names someone, and when a live request should go out, with single flight and one coalesced follow-up.
**Design references:** §5 Architecture (`NameSpotter`, `NamingTrigger`), §5 Performance, R5, R6, §6 (trigger after the answer)
**Touches:** `Packages/MiniWhisperCore/Sources/MWNaming/NameSpotter.swift` (create); `Packages/MiniWhisperCore/Sources/MWNaming/NamingTrigger.swift` (create); `Packages/MiniWhisperCore/Tests/MWNamingTests/NameSpotterTests.swift` (create); `Packages/MiniWhisperCore/Tests/MWNamingTests/NamingTriggerTests.swift` (create)

**Steps (TDD):**
1. Write tests:
   - `NameSpotterTests`:
     - NLTagger finds `"My name is Kate Morgan."` and `"Thanks, Priya, over to you."`;
     - `"We ship on Friday."` has no name;
     - a known name `"Niamh"` matches in `"niamh can you hear me"` and `"NIÁMH?"` (fold-insensitive);
     - `"Dan"` does not match `"Danger ahead"` (word boundary).
   - `NamingTriggerTests`:
     - no fire without arming;
     - a name-bearing segment from S1 arms, and the next segment from S1 does not fire;
     - the first segment from S2 fires;
     - `tick(at: armed + 19.9)` does not fire, while `tick(at: armed + 20)` does;
     - a fire while `inFlight` returns false and `end()` returns true exactly once, even after three such fires;
     - `disarm()` drops both the armed state and a pending follow-up;
     - a name-bearing segment that fires the trigger re-arms it for its own speaker (Planning decision 6).

   Expected initial failure: `cannot find 'NameSpotter' in scope`, `cannot find 'NamingTrigger' in scope`.
2. Run `swift test --filter MWNamingTests` — confirm; scaffold empty types, re-confirm red as expectation failures.
3. Implement `NameSpotter.containsName(_:known:)`: NLTagger with `.nameType`, options `.joinNames`, looking for `.personalName`, created per call (NLTagger is not Sendable). Then a word-boundary match of each `NameFold.key(known)` against the folded text. Implement `NamingTrigger` as a value type per the §5 interface (`segment(speaker:hasName:at:)`, `tick(at:)`, `begin()`, `end() -> Bool`, `disarm()`, `inFlight`) with a 20 s constant.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** all trigger rules of R5–R6 and the testing-strategy list hold; the spotter needs no network or model download.

**Risks specific to this stage:** NLTagger output can differ between macOS releases. Test sentences use unambiguous names, and the known-name path, which carries the People, user and standing names, is asserted independently of NLTagger.

### Stage 7 — Naming client seam and the Anthropic naming request
**Goal:** Define the `NameSuggesting` seam and its request, reply and error types, and send the Haiku 5.5 request with caching and the JSON schema.
**Design references:** §5 Architecture (MWTranscription seam), §5 Prompt and request shape (Output, Usage decoding), §5 Failure and edge cases, R9, R10, R27, R28, R29
**Touches:** `Packages/MiniWhisperCore/Sources/MWTranscription/NameSuggesting.swift` (create); `Packages/MiniWhisperCore/Sources/MWTranscription/AnthropicClient.swift`; `Packages/MiniWhisperCore/Tests/MWTranscriptionTests/AnthropicClientNamingTests.swift` (create); `Packages/MiniWhisperCore/Tests/MWTranscriptionTests/AnthropicClientTests.swift` (one usage-decoding case)

**Steps (TDD):**
1. Write tests with `FakeHTTPTransport` (pattern of `AnthropicClientTests`):
   - `AnthropicClientNamingTests`, request:
     - POST to the messages URL with `anthropic-version: 2026-10-21` and no `anthropic-beta` header;
     - the body has `model == "claude-haiku-5-5"`, `max_tokens == 8000`, `output_config.effort == "medium"`, and `output_config.format.type == "json_schema"` with the request's schema object;
     - no `fallbacks`, `temperature` or `thinking` key;
     - `system` is one text block with `cache_control: {type: "ephemeral"}`;
     - the user content is the transcript blocks then the state block, with `cache_control` only on block `cacheBlocks - 1` (none when `cacheBlocks == 0`);
     - the transport timeout is 60 s.
   - `AnthropicClientNamingTests`, reply:
     - suggestions decode from a reply whose content opens with a `thinking` block and then the `text` block holding the JSON;
     - all four usage fields map into `TokenUsage`;
     - more than 50 suggestions are cut to 50.
   - `AnthropicClientNamingTests`, errors: 401 and 403 give `.unauthorized`; 429 gives `.rateLimited`; 503 gives `.server(503)`; `stop_reason: "refusal"` gives `.refused`; `stop_reason: "max_tokens"` gives `.truncated`; non-JSON text gives `.malformed`; a transport error gives `.transport`.
   - `AnthropicClientNamingTests`, logs: captured log records (`CapturingLogSink`) carry no quote, name or key text.
   - `AnthropicClientTests`: the summary path now also decodes `cache_read_input_tokens` and `cache_creation_input_tokens` (zero when absent).

   Expected initial failure: `cannot find type 'NamingRequest' in scope`, `value of type 'AnthropicClient' has no member 'suggestNames'`.
2. Run `swift test --filter AnthropicClient` — confirm.
3. Implement:
   - in `NameSuggesting.swift`: `NamingRequest`, `RawSuggestion` (Decodable from the schema's six fields), `NamingReply`, and `NamingError` with a user-facing `reason` for each case, plus `protocol NameSuggesting: Sendable`;
   - in `AnthropicClient`: the `namingModel`, `namingEffort`, `namingMaxTokens` and `namingTimeout` constants and `suggestNames(_:)`, sharing the URL, version and header code with `summarise`;
   - text blocks are read by `type`, since Haiku 5.5 runs adaptive thinking by default and a reply may open with `thinking` blocks;
   - `MessagesResponse.Usage` gains the two cache fields, filled into `TokenUsage`;
   - log lines go to `Log.naming`: byte count, HTTP status and the four token counts only.

   The app's `KeyedAnthropicClient` conformance waits for Stage 18, where it is first used.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** request shape, decoding and error mapping as listed; summary tests unchanged and green.

**Risks specific to this stage:** Live API shape drift. The request was checked against the current Claude API reference (structured outputs via `output_config.format`, effort default `medium` on Haiku 5.5, a 512-token cache minimum, cache usage fields), and the opt-in replay (Stage 17) exercises it live.

### Stage 8 — Conversation matches in the registry; Forget keeps them
**Goal:** Give `SpeakerRegistry` the conversation-match rules (suggest, apply, withdraw, revert, dismiss into `rejectedNames`, voice outranking conversation, rename clearing them). Keep them through forget-everyone. Add `SuggestionPolicy.isOpen`.
**Design references:** §5 Architecture (`SpeakerRegistry` extensions, `SuggestionPolicy.isOpen`), §5 Failure and edge cases (Forget everyone), R13, R17, R19–R23
**Touches:** `Packages/MiniWhisperCore/Sources/MWNaming/SuggestionPolicy.swift` (create, `isOpen` only); `Packages/MiniWhisperCore/Tests/MWNamingTests/SuggestionPolicyTests.swift` (create); `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/SpeakerRegistry.swift`; `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/SpeakerRegistryTests.swift`; `Packages/MiniWhisperCore/Sources/MWVoices/VoiceScrubber.swift`; `Packages/MiniWhisperCore/Tests/MWVoicesTests/VoiceScrubberTests.swift`

**Steps (TDD):**
1. Write tests:
   - `SuggestionPolicyTests.isOpen`: true for a default-named unlinked non-user speaker, and for one holding only a conversation match; false for the user, a renamed speaker, a linked one, and one holding a `source == "voice"` match.
   - `SpeakerRegistryTests`, conversation suggest:
     - `suggestFromConversation` keys the match to the speaker's first provider key with `state .suggested`;
     - it replaces an earlier conversation match on that speaker, whatever key it holds;
     - it ignores a closed speaker.
   - `SpeakerRegistryTests`, apply and voice precedence:
     - `applyFromConversation` renames through `rename` (merging onto an existing name), stores the match `.applied` on the survivor, and links no person;
     - voice `suggest` and `apply` drop conversation matches on the target, but voice matches survive a conversation suggest.
   - `SpeakerRegistryTests`, rename:
     - a rename to a non-default name drops the survivor's conversation matches;
     - a merge joins `rejectedNames`, fold-deduped.
   - `SpeakerRegistryTests`, Accept: `accept(key:)` of a conversation match renames and leaves no match.
   - `SpeakerRegistryTests`, dismiss: `dismiss(key:)` of a conversation match appends its name to `rejectedNames` once, fold-deduped; a voice dismiss still rejects the person.
   - `SpeakerRegistryTests`, revert: `revertConversation(key:)` returns an unlinked non-user speaker to `Speaker <id>`, appends to `rejectedNames` and removes the match; it does nothing for the user or a linked speaker.
   - `SpeakerRegistryTests`, withdraw: `withdrawConversation(speaker:)` removes that speaker's conversation match; `withdrawConversation(named:)` removes every suggested conversation match with that fold key and returns the count.
   - `VoiceScrubberTests`: `scrub(people: nil)` keeps `source == "conversation"` matches and `rejectedNames`, while clearing voice matches, links and `rejected`.

   Expected initial failure: `cannot find 'SuggestionPolicy' in scope`, `value of type 'SpeakerRegistry' has no member 'suggestFromConversation'`, then the scrubber assertion failing (conversation matches cleared).
2. Run `swift test --filter SuggestionPolicyTests`, `--filter SpeakerRegistryTests`, `--filter VoiceScrubberTests` — confirm.
3. Implement:
   - `SuggestionPolicy.isOpen(_:)`, using `SpeakerLabel.defaultName`;
   - the registry methods per design §5;
   - `SpeakerRegistry.defaultName` delegating to `SpeakerLabel.defaultName`;
   - `rename` dropping the survivor's conversation matches afterwards when its name is not its default, and joining `rejectedNames` on merge;
   - the voice `suggest` and `apply` first dropping conversation matches on the target;
   - `dismiss` branching on `source`;
   - `VoiceScrubber.scrub(people: nil)` restricted to `source == "voice"` matches (links and `rejected` still cleared). `detach` stays voice-only.
4. Run — pass; full `swift test` (every v8 registry, controller and scrub test unchanged) and app build-only — green.

**Definition of done:** each registry rule in design §5 has a test; v8 behaviour unchanged where no conversation match is present.

**Risks specific to this stage:** `rename`'s new rule runs on every rename. It removes only `source == "conversation"` matches, which no v8 meeting holds, and the full v8 suites stay green.

### Stage 9 — Settings › Meetings: Speaker names card
**Goal:** The card with both switches, the misheard-spellings list and the footnote, backed by `SettingsModel`.
**Design references:** §5 Interfaces (Settings › Meetings: Speaker names card, `SettingsModel` gains), §5 Design language; `DESIGN.md` (Card, SettingRow, `.ds` switch, quiet pills with hover reveal, SettingsFootnote, warning hint, Copy Tone); R1–R3, R24
**Touches:** `App/Settings/SettingsModel.swift`; `App/Settings/MeetingsSection.swift`; `AppTests/SettingsModelTests.swift`

**Category:** Hybrid. Full TDD for `SettingsModel`. The SwiftUI card is the integration-verified remainder, checked by the app build and the manual pass in Verification.

**Steps (TDD):**
1. Write tests in `SettingsModelTests`:
   - `namingEnabled` reads the config default `true` with an Anthropic key, and `false` without one (R3), while the stored value is kept;
   - `setNamingEnabled(false)` writes `meeting_naming_enabled`;
   - `namingAutoApply` is `false` and `autoApplyLocked` is true while naming is off or no key is stored (Planning decision 12);
   - `namingBlocked` follows the key;
   - `addNameAlias` returns false and stores nothing for `""`, `"  "`, `"Speaker 3"`, a fold-duplicate (`"NEVE"` after `"Neve"`) and the user's name (`meetingUserName`, folded); it returns true and appends a trimmed `"Neev"`;
   - `removeNameAlias("Neve")` removes it.

   Expected initial failure: `value of type 'SettingsModel' has no member 'namingEnabled'`.
2. Run the app test command — confirm the build error.
3. Implement the `SettingsModel` members (design §5, using `NameFold.key` for duplicates and `hasKey(.anthropic)`). Build `Card("Speaker names")` between `recording` and `summaryPrompt` in `MeetingsSection` with rows 1–4 and the exact copy from design §5:
   - row 2 is dimmed (opacity 0.5) and disabled while row 1 is off;
   - the inset spellings list has quiet "Remove" pills revealed on hover or focus, kept in the layout when hidden (DESIGN.md Do's);
   - empty list: "None yet." in tertiary;
   - an "Add a spelling" field 180 pt wide, committing on Return and clearing;
   - the footnote, then `summaryKeyHint` in warning style when no key is stored.
4. Run the full app test command — pass, no regressions; full `swift test` unaffected.

**Definition of done:** model rules pass; the card renders in light and dark mode and matches the accepted mockups (`mockup-v9-settings-placement.html#names-card`, `mockup-v9-name-aliases.html#names-card-list`) on the manual pass.

**Risks specific to this stage:** None.

### Stage 10 — Transcript rendering and the naming prompt
**Goal:** Turn segments into numbered turns and 5-minute blocks with the closed-block count. Build the fixed system prompt, the state block and the request.
**Design references:** §5 Architecture (`NamingTranscript`, `NamingPrompt`), §5 Prompt and request shape, §5 Performance (Caching, Long meetings), R8, R10
**Touches:** `Packages/MiniWhisperCore/Sources/MWNaming/NamingTranscript.swift` (create); `Packages/MiniWhisperCore/Sources/MWNaming/NamingPrompt.swift` (create); `Packages/MiniWhisperCore/Tests/MWNamingTests/NamingTranscriptTests.swift` (create); `Packages/MiniWhisperCore/Tests/MWNamingTests/NamingPromptTests.swift` (create)

**Steps (TDD):**
1. Write tests:
   - `NamingTranscriptTests`, turns and blocks:
     - consecutive segments of one speaker form one turn, rendered `T<n> S<id> [mm:ss]: <text>`, with per-segment ids, starts and ranges into the turn text;
     - turns go into blocks by start time at 5-minute boundaries, with `closedBlocks == blocks.count - 1`;
     - the first block opens with `<transcript>` and the last ends with `</transcript>`;
     - a segment text containing `</transcript>` is escaped through `MeetingTextEscaping`.
   - `NamingTranscriptTests`, long meetings: above 400,000 rendered characters the oldest whole turns are dropped and `(earlier turns omitted)` comes first.
   - `NamingTranscriptTests`, cache stability: rendering twice with one segment appended leaves every closed block byte-identical.
   - `NamingPromptTests`:
     - the state block for the design's example (mode, `you: S0 = Niamh; also heard as: Neve, Neev`, open with a dismissed name, suggested, named, people) matches exactly;
     - `you` is omitted without a user label;
     - names in the state block are escaped against `</state>`;
     - `request(_:state:)` carries `system == NamingPrompt.system`, the blocks, `cacheBlocks == closedBlocks`, and a schema that decodes to the design's JSON schema;
     - `system` contains the data rule naming `<transcript>` and `<state>`.

   Expected initial failure: `cannot find 'NamingTranscript' in scope`.
2. Run `swift test --filter MWNamingTests` — confirm; scaffold, re-confirm red.
3. Implement per design §5, returning `Sendable` value types (`Rendered`, `Turn`, `NamingState`, `SpeakerState`) so the route can render off the main actor.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** byte-stable closed blocks; request carries both breakpoint positions; truncation keeps whole turns.

**Risks specific to this stage:** Prompt wording drives accuracy. The text is fixed by design §5 and measured only by the replay (Stage 17).

### Stage 11 — Controller: user actions on conversation matches
**Goal:** Accept, Dismiss, "Not <name>" and That's me on conversation matches, branching on the match's `source`.
**Design references:** §5 Control flow (Accept, Dismiss, Not <name>, That's me, Rename), §5 Interfaces (Controller API), §5 Observability, R19–R21, R23, R29
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`; `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerNamingActionsTests.swift` (create)

**Steps (TDD):**
1. Write tests on stored meetings seeded with conversation matches (`harness.seed`, `controller.open`; sibling `MeetingControllerVoiceLearningTests` for the voice-route cases):
   - Accept: Accept on a conversation suggestion renames the speaker, merges into a speaker already of that name, and leaves no conversation match. With the voice route on (embedder plus sidecar), it links the People entry found by exact name (People spelling `"Kate Morgan"`) and teaches. No `.accepted` line is written to the match log.
   - Dismiss: Dismiss records `rejectedNames` and saves `meeting.json`.
   - Not <name>: "Not <name>" on an applied conversation match returns the speaker to `Speaker <id>` and records `rejectedNames`.
   - That's me, stored and withdrawn: `thatsMe(key:)` appends the name to `meeting_user_name_aliases` once (a second call with a fold-equal name adds nothing) and withdraws every suggested conversation match of that name.
   - That's me, refused cases: it does nothing for a missing key or a suggestion of the user's own name.
   - Voice actions unchanged: the v8 voice tests stay green as written.
   - Logs: `Log.naming` lines for each action carry the action word and counts only.

   Expected initial failure: `value of type 'MeetingController' has no member 'thatsMe'`, then expectation failures where Accept on a conversation match runs the voice path.
2. Run `swift test --filter MeetingControllerNamingActionsTests` — confirm.
3. Implement:
   - `acceptSuggestion` looks up the standing match's `source` first. For `"conversation"` it calls `registry.accept`, then `applyMerge`, then `link(survivor, renamedFrom: before)`, with no `learn(.accepted…)`;
   - `dismissSuggestion` and `rejectMatch` branch the same way: `registry.dismiss` or `registry.revertConversation`, then `applyMerge(nil)`, with no voice `learn`;
   - new `public func thatsMe(key: String) async` per design §5 That's me (config update through `ConfigStore.update`, `withdrawConversation(named:)`, `commitSpeakers`);
   - `Log.naming` action lines.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** each action behaves per design §5 Control flow on stored meetings; v8 voice action tests unchanged.

**Risks specific to this stage:** None.

### Stage 12 — Evidence check and suggestion policy
**Goal:** Verify quotes against the cited turn and turn a reply into suggest/apply actions against the current speakers.
**Design references:** §5 Architecture (`EvidenceCheck`, `SuggestionPolicy`), §5 Policy rules 1–10, §5 Failure and edge cases, R12–R17, R22
**Touches:** `Packages/MiniWhisperCore/Sources/MWNaming/EvidenceCheck.swift` (create); `Packages/MiniWhisperCore/Sources/MWNaming/SuggestionPolicy.swift`; `Packages/MiniWhisperCore/Tests/MWNamingTests/EvidenceCheckTests.swift` (create); `Packages/MiniWhisperCore/Tests/MWNamingTests/SuggestionPolicyTests.swift`

**Steps (TDD):**
1. Write tests:
   - `EvidenceCheckTests`:
     - exact, curly-quote, whitespace and case variants pass;
     - a quote from another turn, a quote without the name, and a paraphrase fail;
     - in a turn spanning three segments the evidence names the segment holding the match's start, its start time, and the original substring, cut to 300 characters at a word boundary.
   - `SuggestionPolicyTests`, rules 1–5:
     - unknown `S9` is dropped;
     - `likely` and an unknown kind are dropped;
     - a sanitiser reject is dropped;
     - an unverified quote is dropped;
     - a closed target is dropped.
   - `SuggestionPolicyTests`, rules 6–7:
     - the People spelling is used;
     - the user's name or an alias is dropped remote and becomes `userName` in a room;
     - a name in `rejectedNames` or a person in `rejected` is dropped.
   - `SuggestionPolicyTests`, rule 8: one speaker with two names drops both; one name for two speakers keeps only the single self-introduction in its own turn, else drops both.
   - `SuggestionPolicyTests`, rule 9: the same name standing emits nothing; a different one emits `.suggest`.
   - `SuggestionPolicyTests`, rule 10, auto-apply: emits `.apply` only when every condition holds, with one test per condition failing alone: `autoApply` off, kind not `self_introduction`, evidence segment's current speaker ≠ target (via `PolicyContext.segmentSpeakers`), name held by another speaker, user name or alias.
   - `SuggestionPolicyTests`, cap: at most 50 raws are processed.

   Expected initial failure: `cannot find 'EvidenceCheck' in scope`, `type 'SuggestionPolicy' has no member 'decide'`.
2. Run `swift test --filter MWNamingTests` — confirm; scaffold, re-confirm red.
3. Implement `EvidenceCheck.verify` with the design's normalisation (lower-case, fold diacritics, map ‘ ’ ‚ ‛ to `'` and “ ” „ to `"`, collapse whitespace, then map back to the original range). Implement `SuggestionPolicy.decide`, `PolicyContext` (with `segmentSpeakers: [UUID: Int]`, Planning decision 4) and `NamingAction` with the matches built as `source: "conversation"`, `person: nil`, `score: nil`, `kind`, `evidence`. Add policy drop counters by rule number for the route's log.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** one test per rule and per auto-apply condition; every kept suggestion carries verified evidence.

**Risks specific to this stage:** Normalisation that maps back to original ranges is the subtle part. Multi-segment and curly-quote tests pin it.

### Stage 13 — `MeetingNamingRoute`
**Goal:** The per-meeting route that decides when and what to ask, sends, verifies and decides against the current context, and counts failures.
**Design references:** §5 Architecture (`MeetingNamingRoute`, Why the split), §5 Control flow (live steps 2–5, 7–8), §5 Failure and edge cases, §5 Observability, R4–R6, R8, R9, R27–R29
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingNamingRoute.swift` (create; also holds `NamingSnapshot`, `NamingScope`, `NamingOutcome`); `Packages/MiniWhisperCore/Sources/MWTestSupport/FakeNameSuggester.swift` (create); `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingNamingRouteTests.swift` (create); `CLAUDE.md` (MWMeetingPipeline row lists `MeetingNamingRoute`)

**Steps (TDD):**
1. Write `MeetingNamingRouteTests` with a new `FakeNameSuggester` (scripted replies or errors, recorded requests, `hold()`/`release()` like `FakeSummarizer`) on `@MainActor`:
   - `segmentsAdded` with a name-bearing segment then another speaker's segment returns true; with the People reader's names and the passed `known` extras, a known name arms the trigger;
   - `run` sends one request built from the snapshot, verifies evidence, then calls `context()` and returns its actions;
   - a nil context returns no actions but still the usage and the `Pricing.namingCost` cost (R4 dropped reply, tokens billed);
   - a fire during a held flight makes `outcome.followUp` true exactly once;
   - `waitIdle()` resolves after the held flight is released;
   - `disarm()` clears an armed trigger and a pending follow-up;
   - a 401 sets `pause` at once (`isPaused`);
   - three failures in a row pause with the third's reason;
   - a success resets the count;
   - manual scope runs while paused;
   - captured `Log.naming` records carry scope, counts, tokens, cost and duration, and no name, quote or transcript text.

   Expected initial failure: `cannot find 'MeetingNamingRoute' in scope`, `cannot find 'FakeNameSuggester' in scope`.
2. Run `swift test --filter MeetingNamingRouteTests` — confirm; scaffold, re-confirm red.
3. Implement the route per design §5:
   - `@MainActor final class`;
   - init takes the client, the People reader (returning non-user People), the clock, the overrides and the trigger constant;
   - `segmentsAdded(_:speakers:known:)` arms at each segment's `end` (Planning decision 5);
   - `tick(at:)`;
   - `run(snapshot:context:)`: `begin()`, then render, build the request and decode in a `nonisolated` helper off the main actor, then verify against the snapshot, `await context()`, `SuggestionPolicy.decide` and `end()`;
   - `isPaused`, `inFlight`, `waitIdle()`, `disarm()`;
   - any non-`NamingError` error maps to `.transport(AnyError(error).description)` (Planning decision 8).

   Add the route to CLAUDE.md's MWMeetingPipeline row.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** single flight, coalescing, pause and reset rules hold on fakes; logs carry no transcript content.

**Risks specific to this stage:** Off-main rendering in Swift 6 strict concurrency. Every rendered type is `Sendable` (Stage 10), and the snapshot is an immutable value.

### Stage 14 — Controller: live naming
**Goal:** Run the route in a live meeting: trigger, R7 guards, apply, billing, cost events, the one-time notice and pause notices.
**Design references:** §5 Control flow (Live meeting steps 1–8), §5 Interfaces (`MeetingEvent.naming`, `NamingEvent`, `NamingResult`), §5 Failure and edge cases, R1–R7, R13, R22, R26–R29
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingEvent.swift`; `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingDependencies.swift`; `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`; `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerTests.swift` (`MeetingHarness` gains a `namer:` parameter); `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerNamingTests.swift` (create); `App/Meeting/MeetingWindowModel.swift` (exhaustive switch: `case .naming: break`, replaced in Stages 16 and 18)

**Steps (TDD):**
1. Write `MeetingControllerNamingTests` with `MeetingHarness(secrets: [.speechmatics, .anthropic], namer: FakeNameSuggester(...))`:
   - Live suggestion: S1 says "I'm Kate" and S2 then speaks. Exactly one request goes out, `registry` shows Kate as a conversation suggestion on S1, `meeting.json` is saved, and `.speakers` is emitted.
   - Auto-apply: with auto-apply on, a self-introduction is applied as the name, with no voice learning.
   - No-request cases: no request in a test call, with `meeting_naming_enabled` off, without an Anthropic key, with every speaker named, or with `namer == nil`.
   - Switch off mid-flight: turning the switch off during a held flight drops the reply (no registry change) but still adds `namingCostUSD` and usage.
   - Billing and cost: each request's cost is added to `meeting.billing.namingCostUSD`, `FakeUsageStore.added` holds a `ProviderUsage` whose `inputTokens` = input + cache read + cache write, and `.cost` events (reply and the next tick) equal engine live cost + naming cost.
   - One-time notice: `.naming(.introduced)` is emitted once when naming is on with a key and the flag is false, and `meeting_naming_explained` is set; a second meeting emits none.
   - Pause notice: three scripted failures emit `.naming(.paused(reason))`, and the next trigger sends nothing.
   - Follow-up: a fire during a held flight sends exactly one follow-up after release.

   Expected initial failure: `extra argument 'namer' in call`, `type 'MeetingEvent' has no member 'naming'`.
2. Run `swift test --filter MeetingControllerNamingTests` — confirm.
3. Implement:
   - `MeetingDependencies.namer: (any NameSuggesting)?`, a defaulted `nil` init parameter. The two construction sites, `AppDelegate.swift:327` and `MeetingHarness`, compile unchanged; the harness passes its fake;
   - `MeetingEvent.naming(NamingEvent)` with `NamingEvent` and `NamingResult` per design §5, and the no-op `case .naming: break` in `MeetingWindowModel.apply`;
   - `start` creates the route when `test == nil` and `namer != nil` (Planning decision 1), then emits the notice and sets the flag through `ConfigStore.update`;
   - `add` calls `segmentsAdded` with user name, aliases and standing suggestion names after the voice route;
   - the ticker calls `tick` and emits `.cost(liveCost + namingCostUSD)`;
   - `startNaming(.live)` checks R7, and `runNaming` builds the snapshot and `context()`. `context()` rereads config and returns the current speakers and `segmentSpeakers`. It is nil when the switch is off (live scope) or the meeting has gone (Planning decision 7);
   - apply per design §5 step 6;
   - the follow-up per step 7;
   - the pause notice per step 8.

   All of this sits under `// MARK: - Naming` in `MeetingController.swift` (Planning decision 11).
4. Run — pass; full `swift test` and the app test command, since an app file changed, — green.

**Definition of done:** live flow, guards, billing and notices per design §5 Control flow; existing controller suites unchanged and green.

**Risks specific to this stage:** Controller test timing. Tests wait on events (`.speakers`, `.naming`) and on `FakeNameSuggester.hold/release`, never on sleeps (CLAUDE.md: a real sleep in a test is a defect).

### Stage 15 — Controller: Stop pass and Suggest names
**Goal:** The Stop pass with its ordering against the summary, the stored-meeting route, and the manual `suggestNames()`.
**Design references:** §5 Control flow (Stop, Stored meeting, Suggest names), §5 Interfaces (Controller API), §7 risk (`stop` overwrites billing), R7, R11, R25, R28
**Touches:** `Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift`; `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/MeetingControllerNamingStopTests.swift` (create)

**Steps (TDD):**
1. Write `MeetingControllerNamingStopTests`:
   - Billing survives Stop: `namingCostUSD` accrued live survives `stop`'s `meeting.billing = billing.totals`.
   - After the in-flight request: Stop with a held live flight emits `.naming(.running)`, waits for the flight, then sends exactly one Stop request over the whole meeting; an armed trigger is dropped.
   - Ordering against the summary: with auto-apply on, `FakeSummarizer` receives its call only after the pass completes and sees the applied name. With auto-apply off, both requests are in flight together (summarizer held, namer held).
   - Skipped passes: the quit path (`stop(summarise: false)`), a paused route, no open speaker and the switch off run no pass.
   - Stop-pass results: `.naming(.finished(.found(n)))` with n > 0, or `.finished(.none)` / `.finished(.failed(reason))` otherwise (Planning decision 2); a failure is logged.
   - Suggest names on a stored meeting: `suggestNames()` runs with the switch off and while paused, and emits `.naming(.running)`, `.cost(billing.costUSD + replacedSummaryCostUSD + namingCostUSD)` and `.naming(.finished(...))`.
   - Suggest names refused cases: nothing is sent on a test meeting, without a key, with no open speaker, or while a request runs.

   Expected initial failure: `value of type 'MeetingController' has no member 'suggestNames'`, then the billing assertion failing (`namingCostUSD == 0` after stop).
2. Run `swift test --filter MeetingControllerNamingStopTests` — confirm.
3. Implement per design §5 Stop steps 2–7:
   - keep and restore `namingCostUSD` around `:542`;
   - `disarm()`, then save and set `.stopped`;
   - the pass, awaited before `summarise()` with auto-apply on, else in a child `Task` held by the controller;
   - `open(id)` creates a manual-scope route (non-test, `namer != nil`);
   - `public func suggestNames() async` with its guards.
4. Run — pass; full `swift test` and app build-only — green.

**Definition of done:** Stop and manual flows per design §5; the summary sees auto-applied names when auto-apply is on.

**Risks specific to this stage:** A concurrent pass may outlive the summary. Stage 18 keeps the coordinator's finishing session alive until `.naming(.finished)` (Planning decision 3).

### Stage 16 — App: transcript suggestions, evidence and live notices
**Goal:** Show conversation suggestions on every paragraph of their speaker, with the "?" evidence popover and That's me. Route the one-time and pause notices to the live header with the Meetings Settings… link.
**Design references:** §5 Interfaces (Transcript: suggestion evidence; Live header notices; Controller API; `MeetingActions`), §5 Design language; `DESIGN.md` (ProvisionalName, quiet pills, dialog card, StatusLine info, `color.line`, `color.text.tertiary`, `type.label`, hover actions kept in layout); R18, R20, R21, R23, R26, R27
**Touches:** `App/Meeting/MeetingWindowModel.swift`; `App/Meeting/TranscriptView.swift`; `App/Meeting/LivePage.swift`; `App/Meeting/MeetingCoordinator.swift` (`MeetingControlling.thatsMe`, `MeetingActions.thatsMe` defaulted, actions wiring); `AppTests/MeetingWindowModelTests.swift`; `AppTests/MeetingCoordinatorTests.swift` (fake controller gains `thatsMe`); `AppTests/TestCallSessionTests.swift` (fake controller gains `thatsMe`)

**Category:** Hybrid. Full TDD for `MeetingWindowModel` and coordinator wiring. The SwiftUI views are the integration-verified remainder (app build plus the manual pass).

**Steps (TDD):**
1. Write tests:
   - `MeetingWindowModelTests`, fallback:
     - `nameState` falls back to the speaker's conversation match for a paragraph whose first key has no match, so a conversation suggestion shows on every paragraph of that speaker;
     - a voice match on the key still wins;
     - an applied conversation match gives `.applied`;
     - no state in a test call.
   - `MeetingWindowModelTests`, That's me and evidence:
     - `showsThatsMe` is true only for a conversation suggestion whose name is not the user's;
     - the evidence card gives the quote and "Said at 04:40 by Dan", with the speaker looked up when shown, falling back to the label's current name, and omitted when the segment is gone.
   - `MeetingWindowModelTests`, notices:
     - `.naming(.introduced)` sets `notice` to the R26 text with `opensMeetingSettings == true`;
     - `.naming(.paused("the Anthropic key was refused"))` sets "Name suggestions paused: the Anthropic key was refused." without the link, latest wins;
     - the existing `theNoticeIsKeptForTheLiveHeader` is updated to read `notice?.text`.
   - `MeetingCoordinatorTests`: `actions.thatsMe("1:S2")` reaches the controller (`"thatsme 1:S2"`).

   Expected initial failure: `value of type 'MeetingWindowModel' has no member 'showsThatsMe'`, `value of type 'MeetingActions' has no member 'thatsMe'`.
2. Run the app test command — confirm the build errors.
3. Implement:
   - in the model: the `nameState` fallback, `showsThatsMe`, the evidence card, `notice: (text: String, opensMeetingSettings: Bool)?`, and the `.naming(.introduced)` / `.naming(.paused)` handling (`.running` and `.finished` stay no-ops until Stage 18);
   - in `MeetingControlling` and `MeetingActions`: `thatsMe` (the closure defaulted like `acceptSuggestion`), wired through `matchAction`;
   - in the two test fakes: `thatsMe` stubs;
   - in `TranscriptView`: the 16 pt "?" circle after the default name (`color.line` border, `color.text.tertiary` glyph, `type.label`), opening a dialog-card popover with the italic quote and the "Said at…" line on hover or keyboard focus and toggling on click;
   - a That's me quiet pill beside Accept, Edit and Dismiss, the narrow layout unchanged;
   - in `LivePage`: the notice's `StatusLine(.info)` gains a small "Meetings Settings…" pill calling `actions.openSettings()` when `opensMeetingSettings`.
4. Run the full app test command — pass; full `swift test` unaffected.

**Definition of done:** model rules pass; the transcript matches the accepted mockup (`mockup-v9-transcript-evidence.html#hover-card`) in light and dark mode and at under 470 pt on the manual pass.

**Risks specific to this stage:** A SwiftUI popover on hover can flicker inside a `LazyVStack`. The hover state is owned per paragraph, like the existing `hovered` state, and the click toggle keeps the popover reachable by mouse and keyboard.

### Stage 17 — Replay test (R30)
**Goal:** The opt-in integration test that replays stored meetings through the live trigger and the Stop pass and prints accuracy and time-to-name.
**Design references:** §5 Testing strategy (Replay), §9 Validation before release, R30
**Touches:** `Packages/MiniWhisperCore/Tests/MWMeetingPipelineTests/NamingReplayTests.swift` (create)

**Category:** Non-TDD (integration-verified). It asserts nothing about accuracy by design and runs only with a live key and stored meetings.

**Steps:**
1. Write `@Suite struct NamingReplayTests` with `.enabled(if: MW_INTEGRATION == "1" && ANTHROPIC_API_KEY != nil && MW_NAMING_REPLAY_DIR != nil)` (pattern of `AnthropicIntegrationTests`). It runs on `@MainActor` and works as follows:
   - read each meeting under the directory through `MeetingStore.index()` / `load(_:)`, read paths only;
   - reset every non-user speaker to its default name, keeping the true names aside;
   - feed segments in time order through `MeetingNamingRoute` (real `AnthropicClient`) and `SpeakerRegistry` on a `VirtualClock`, ticking at segment ends;
   - run the Stop pass;
   - print right, wrong and missing per speaker, first time-to-right-name, totals and cost.

   The key is read from the environment and never printed or logged.
2. Run `swift test --filter NamingReplayTests` without the variables — confirm the suite is skipped and the full `swift test` stays green.
3. Integration check, run by the user in their own shell with the key already exported there: `MW_INTEGRATION=1 MW_NAMING_REPLAY_DIR=~/.config/mini-whisper/meetings swift test --filter NamingReplayTests`. Confirm it prints per-speaker results and totals, and that the directory's files are unchanged (`ls -l` and checksums before and after).

**Definition of done:** skipped by default; prints the report when enabled; writes nothing under the replay directory.

**Risks specific to this stage:** About $0.55 per run (design §5). It runs only when the user opts in.

### Stage 18 — App: Suggest names on a stopped meeting, coordinator wiring, and turning naming on
**Goal:** The stopped meeting's naming status line and Suggest names pill, the naming cost on the chip, key presence, and coordinator handling of naming events. Then pass the keyed Anthropic client as the meeting's namer, so naming runs in the app.
**Design references:** §5 Interfaces (Stopped meeting: Suggest names; Cost chip; Inputs; `MeetingActions`), §5 Security (Disclosure), §9 Rollout plan, `DESIGN.md` (StatusLine progress/info/warning, small pill, Copy Tone); R1, R11, R25, R26, R28
**Touches:** `App/Meeting/MeetingWindowModel.swift`; `App/Meeting/FinishedPage.swift`; `App/Meeting/MeetingCoordinator.swift`; `App/Main/MainWindowModel.swift` (`meetingEntered` hook); `App/AppDelegate.swift` (coordinator `hasKey`, `meetingEntered` and main-window key wiring; `namer:` in `makeMeetings`); `App/KeyedAnthropicClient.swift` (`NameSuggesting` conformance); `AppTests/MeetingWindowModelTests.swift`; `AppTests/MeetingCoordinatorTests.swift`; `AppTests/TestCallSessionTests.swift`; `AppTests/MainWindowModelTests.swift`; `CHANGELOG.md` (`[Unreleased]` entry)

**Category:** Hybrid. Full TDD for the window model, coordinator and main-window hook. The integration-verified remainder is checked by the app build and the manual pass in step 5:
- the `FinishedPage` status line;
- the `NSWindow.didBecomeKeyNotification` observer;
- the one-argument `namer:` wiring, whose behaviour Stages 13–15 already test with fakes.

**Steps (TDD):**
1. Write tests:
   - `MeetingWindowModelTests`, `namingLine` states:
     - `.offer` with "2 speakers have no name." and "1 speaker has no name.";
     - `.needsKey` wording without a key;
     - `.running` after `.naming(.running)`;
     - `.found` with "3 names suggested." and "1 name suggested.", plus "Speaker 2 still has none." when exactly one speaker stays open;
     - `.none` "No new names found." and `.failed` "Names not suggested: <reason>." only after a manual request (`suggestNamesRequested()`), while a Stop-pass `.none` or `.failed` returns to the offer (Planning decision 2);
     - nil in a test call, with no open speaker, or while live;
     - the outcome is cleared by a new request.
   - `MeetingWindowModelTests`, cost: a stopped meeting's `cost` adds `billing.namingCostUSD`.
   - `MeetingCoordinatorTests`:
     - `actions.suggestNames()` marks the model and calls the controller;
     - `anthropicKeyPresent` is set from `hasKey(.anthropic)` when a stopped meeting is shown and on `meetingEntered`;
     - a session stopped off the page stays in `finishing` while the Stop pass runs and is dropped after `.naming(.finished)` once its summary is also done (Planning decision 3);
     - `.naming(.finished)` calls `changed()`.
   - `MainWindowModelTests`: entering `.meeting` calls `meetingEntered`.

   Expected initial failure: `value of type 'MeetingWindowModel' has no member 'namingLine'`.
2. Run the app test command — confirm.
3. Implement:
   - in the model: `NamingLine`, `namingLine`, `anthropicKeyPresent`, `suggestNamesRequested()`, the `.naming(.running)` / `.naming(.finished)` handling, and the cost sum;
   - in `MeetingControlling` and `MeetingActions`: `suggestNames`, with the fakes updated;
   - in the coordinator: a `Dependencies.hasKey` defaulted `{ _ in false }`, `refreshKeyPresence()`, the finishing retention, and `changed()` on `.naming(.finished)`;
   - in `MainWindowModel.Dependencies`: `meetingEntered`;
   - in `AppDelegate`: the `hasKey`, `meetingEntered` and main-window `didBecomeKeyNotification` wiring;
   - in `FinishedPage`: a `StatusLine` above `TranscriptView` in the Transcript tab (`.progress` while running, `.info` for offer and outcomes, `.warning` for failed and needs-key) with a small "Suggest names" pill for offer and failed.
4. Run the full app test command — pass; full `swift test` unaffected. Then turn naming on:
   - conform `KeyedAnthropicClient` to `NameSuggesting`, reading the key at call time and throwing `MissingAPIKey()` without one, like `summarise`;
   - pass the existing instance (`AppDelegate.swift:323`) as `namer:` in `makeMeetings`'s `MeetingDependencies`;
   - add the CHANGELOG `[Unreleased]` entry: speaker names suggested from the conversation by Claude Haiku 5.5, the transcript sent to Anthropic during the meeting, about 3 cents a meeting, opt-out under Settings › Meetings;
   - re-run the full app test command and full `swift test`, both green.
5. Integration check (manual, in the built app with an Anthropic key):
   - start a remote meeting and confirm the one-time notice and its link;
   - speak an introduction and a hand-off and confirm a suggestion with its "?" quote;
   - Accept, Dismiss, That's me and "Not <name>" (auto-apply on);
   - Stop and confirm the Stop pass line and the cost chip;
   - open a stored meeting and run Suggest names;
   - remove the key and confirm the Settings and transcript key hints.

   Check light and dark mode and the narrow transcript.

**Definition of done:**
- every `namingLine` state of the design's table with exact wording;
- stopped cost includes naming;
- the line matches `mockup-v9-suggest-names.html#transcript-line` on the manual pass;
- the app passes the namer;
- the CHANGELOG entry is present;
- the step 5 manual pass is completed.

**Risks specific to this stage:**
- **Stale key presence.** Key presence can go stale if a key changes while the meeting page stays visible. It is refreshed on stop, on every navigation to the meeting page and on main-window key. `suggestNames()` re-checks the Keychain itself, so a stale line never sends without a key.
- **Sending starts here.** It begins only after every disclosure surface (Stages 9 and 16) has landed. The wiring sits in this stage, not in one of its own, so the Suggest names pill never lands inert (Planning decision 1).

## Cross-cutting concerns

- **Security:**
  - Transcript text, People names and aliases enter the request only through `MeetingTextEscaping` inside tagged blocks, under the system prompt's data rule (Stages 2, 10).
  - Output is schema-constrained, then filtered by `NameSanitiser` and `EvidenceCheck` (Stages 1, 12), and names render only through SwiftUI `Text`.
  - The key is read at call time by `KeyedAnthropicClient` (Stage 18), and the client logs no request content or key (Stage 7). The replay test reads it from the user's environment and never prints it (Stage 17).
  - No stage sends data before Stage 18, by which time the Settings disclosure (Stage 9) and the one-time notice (Stage 16) exist.
- **Performance:**
  - `NameSpotter` runs on the main actor once per final segment (Stage 6).
  - Rendering, request building and decoding run off the main actor from an immutable snapshot (Stage 13).
  - Single flight and one coalesced follow-up bound volume (Stages 6, 13).
  - Two cache breakpoints, and the 400,000-character cap keeps prompts at the base rate (Stages 7, 10).
- **Observability:** `Log.naming` (Stage 5) carries counts and figures only:
  - the client logs bytes, status and tokens (Stage 7);
  - the route logs scope, turns, characters, duration, cost, policy counts by rule and pause categories (Stage 13);
  - the controller logs user actions (Stage 11).

  Stages 7, 11, 13 and 14 test log content with `CapturingLogSink`.
- **Compatibility / migration:**
  - Every stored field is optional or defaulted (Stages 3, 4), and `Billing` encodes byte-identically when `namingCostUSD == 0`.
  - Forget-everyone keeps conversation data (Stage 8).
  - Shared signatures gain only defaulted parameters (`TokenUsage`, `NameMatch`, `SpeakerLabel`, `Billing`, `MeetingDependencies`, `MeetingActions`), so no existing call site changes.
  - Each stage leaves the system shippable: naming stays inert in the app until Stage 18.
- **Intermediate states.** Requirements spread over several stages show in the app only once Stage 18 passes the namer.
  - **Before Stage 9:** nothing user-visible changes.
  - **After Stage 9:** the Speaker names card stores its switches and spellings, but no meeting reads them yet.
  - **After Stage 16:** the transcript can render conversation suggestions and naming notices, but none are produced yet.
  - **Stages 11, 14 and 15:** they are exercised only through package tests with fakes.
  - **Bundling decision.** Bundling all of these into one stage was rejected on size. Each intermediate state is inert, never broken. The one surface that would have been broken while inert, the Suggest names pill, lands in the same stage as the wiring.

## Verification

1. `cd Packages/MiniWhisperCore && swift test`: every target green, including `MWNamingTests`, `MeetingNamingRouteTests`, `MeetingControllerNaming*Tests` and the extended registry, scrubber, model, config and pricing suites.
2. App tests: `✔ Test run …` passed and `** TEST SUCCEEDED **`.
3. Replay (R30, Goals 1–2): with the key exported in the user's own shell, `MW_INTEGRATION=1 MW_NAMING_REPLAY_DIR=<the 17 evaluation meetings> swift test --filter NamingReplayTests`. Confirm at least 20 of 35 renamed speakers shown the right name, at most 1 wrong-person suggestion, and the median time-to-name printed (target near 4.2 min).
4. Manual pass in the app (Stage 18 step 5), covering:
   - the four accepted surfaces in light and dark mode: names card, aliases list, transcript evidence, Suggest names line;
   - the narrow transcript;
   - the cost line and Today/Month totals moving by the naming cost (R28);
   - a meeting with naming off sending nothing (R4, R7);
   - a test call showing no naming UI and sending nothing (R7, R25).

## Risks and open issues

| Risk | Mitigation |
|---|---|
| `MeetingController.swift` (1,094 lines) grows by the naming orchestration | Logic lives in `MWNaming` and `MeetingNamingRoute`; the controller holds only orchestration under one `MARK` section (Planning decision 11). Stage 11, 14 and 15 tests target behaviour, not structure. |
| A concurrent Stop pass outlives a session the coordinator would drop, so a reopened copy of the meeting could race on `meeting.json` | The coordinator keeps the finishing session until `.naming(.finished)` (Stage 18, Planning decision 3). |
| NLTagger results differ across macOS versions and make spotter tests flaky | Unambiguous test sentences; known-name matching tested independently (Stage 6). |
| Swift 6 strict concurrency around off-main rendering | `Sendable` value types throughout (Stages 10, 12); the route's `nonisolated` helper takes only the snapshot (Stage 13). |
| The `MeetingWindowModel.notice` type change breaks an existing equality test | Updated in the same stage (Stage 16). |
| New `MeetingEvent` case breaks the app's exhaustive switch | No-op case added in Stage 14 itself; the coordinator's switch already has `default`. |
| New `MeetingControlling` requirements break the two test fakes | The fakes are updated in the stage adding each requirement (Stages 16, 18). |
| Parallel app stages would share the app test host | No batch holds two stages that run `xcodebuild … test`. |
| Haiku 5.5 behaviour or price change | Rates live in `Pricing.perMTok` with overrides (Stage 5); the replay re-measures accuracy (Stage 17). |

## Planning decisions taken

1. **Inert until Stage 18.** `MeetingDependencies.namer` is a defaulted-nil dependency, and the controller creates no route without it. The app passes the keyed client only in Stage 18, after the disclosures (R1 description in Stage 9, R26 notice in Stage 16) exist, so no stage ships sending without disclosure. The wiring, including `KeyedAnthropicClient`'s `NameSuggesting` conformance, shares Stage 18 with the Suggest names line. That line therefore never lands as a dead pill, and no earlier stage touches app code without app tests.
2. **The window decides how to show an outcome.** The controller emits `.naming(.finished(.found | .none | .failed))` for every scope, so the running line always ends. The window shows `.none` and `.failed` only after a manual Suggest names, which the coordinator marks through `suggestNamesRequested()`, and returns to the offer after a Stop pass, as R11 requires. This closes an under-specified end signal without changing `NamingEvent`.
3. **The coordinator keeps a stopped session while its Stop pass runs.** It drops the session after `.naming(.finished)` and calls `changed()` there, so the meeting list and Today/Month totals pick up the naming cost.
4. **`PolicyContext.segmentSpeakers: [UUID: Int]`** carries each segment's current speaker. Policy rule 10 and R22 need the evidence segment's speaker at apply time, which the sketched context had no field for.
5. **The trigger arms at the segment's `end` in meeting seconds.** `segmentsAdded` has no time parameter in the design, and this lets the live path and the replay share one clock basis.
6. **A name-bearing segment that fires the trigger also re-arms it** for its own speaker. This is R5 read literally, since that segment also contains a spotted name, and it captures the answer to that turn. Coalescing bounds the volume.
7. **When `context()` returns nil.** It is nil when the switch is off (live scope only) or the controller no longer holds the snapshot's meeting. A live reply that lands during Stop is applied against the current speakers rather than dropped, which is how "the scope no longer matches" is read here. This keeps paid replies, and the Stop pass sees them as standing state.
8. **Non-`NamingError` errors map to `.transport(description)`** in the route, for example `MissingAPIKey` from `KeyedAnthropicClient` in a race with key removal.
9. **The People reader excludes the user's own People entry**, because the user is passed separately as `you`.
10. **`SpeakerLabel.defaultName(_:)` moves into MWMeetings** (`SpeakerRegistry.defaultName` delegates to it), so `SuggestionPolicy.isOpen` in MWNaming shares the one default-name rule instead of copying it.
11. **Naming orchestration stays in `MeetingController.swift`** under `// MARK: - Naming`, because the state it touches is `private` to that file.
12. **`SettingsModel` gains `autoApplyLocked`** (naming off or no key) for R2's dimmed and disabled row, beside the members design §5 lists.
13. **Key presence refreshes** on stop, on entering the meeting page (a new `MainWindowModel.Dependencies.meetingEntered` hook) and on main-window key. In the unified window, a key added under Settings never makes the window key again.
14. **Route log lines are split between client and route.** The client logs HTTP status and tokens; the route logs duration, cost and policy counts. Only the route knows overrides and outcomes.
15. **Test files:**
    - new `MWNamingTests` files per type;
    - `MeetingNamingRouteTests`, `MeetingControllerNamingTests`, `MeetingControllerNamingStopTests` and `MeetingControllerNamingActionsTests` in `MWMeetingPipelineTests`;
    - `AnthropicClientNamingTests` in `MWTranscriptionTests`;
    - `TokenUsageTests` in `MWSupportTests`.

    All follow the `<Type>Tests.swift` convention.
16. **Design anchor corrected in place:** the known-keys entry is `Config.swift:245`, not `:244`, and the encode is at `:352`.
17. **Parallel batches.** Batches 3, 4, 5 and 9 run in parallel, as the schedule below records; each pair was cleared on all seven independence tests. Stage 17 is kept out of Stage 14's batch because Stage 14 consumes the route and might touch it. Additive, defaulted-parameter fields (`TokenUsage`, `NameMatch`, `SpeakerLabel`, `Billing`) force no call-site edit, so they are not treated as shared-signature changes.

## Deviations from the design

None — plan matches design v9 exactly.

## Execution schedule

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1 | serial | establishes the MWNaming module, its test target and registration every later stage uses |
| 2 | Stage 2 | serial | behaviour-preserving refactor of shared code (category exclusion) |
| 3 | Stage 3, Stage 4, Stage 5, Stage 6 | parallel | Disjoint files: MWMeetings model, `Config.swift`, MWSupport/MWUsage, and new MWNaming files, each with its own tests. No symbol or string-keyed dependency between them; Stage 6 needs only Stage 1's `NameFold`. No shared registration point: no `Package.swift` or `project.yml` edit, and no exhaustive switch. Same base state. Only additive defaulted fields, no shared-signature change. No security ordering. No shared test resource: `swift test` and app build-only in separate worktrees. |
| 4 | Stage 7, Stage 8, Stage 9 | parallel | Disjoint files: MWTranscription files; registry, scrubber and new `SuggestionPolicy.swift`; `App/Settings` plus `SettingsModelTests`. No dependency between them; each needs only Batches 1–3. No shared registration: new files sit in existing targets, auto-discovered. No category exclusion. No security ordering: nothing sends data. Only Stage 9 launches the app test host. |
| 5 | Stage 10, Stage 11 | parallel | Disjoint files: new MWNaming transcript and prompt files; `MeetingController.swift` plus a new controller test file. Stage 11 uses only the registry (Stage 8) and config (Stage 4), not Stage 10's types. No shared registration point. No category exclusion. Separate `TempDirectory` per test. Neither launches the app host. |
| 6 | Stage 12 | serial | consumes `Rendered` and `NamingRequest` from Stages 10 and 7 |
| 7 | Stage 13 | serial | consumes the policy, prompt, trigger and client from Stages 6, 7, 10 and 12 |
| 8 | Stage 14 | serial | consumes the route; adds a `MeetingEvent` case (exhaustive switch site) |
| 9 | Stage 15, Stage 16, Stage 17 | parallel | **Disjoint files:** `MeetingController.swift` plus a new controller test file; `App/Meeting` and `AppTests` files; one new package test file. **No symbol or string-keyed dependency:** Stage 16 needs Stage 14's `.naming` events and Stage 11's `thatsMe`, not Stage 15's `suggestNames`, which arrives in the app in Stage 18. Stage 17 uses only the route, registry and client, which neither sibling changes. **No shared registration:** no manifest, exhaustive switch or shared fixture edited by two of them. **Same base state:** each is green against Batch 8. **Categories:** Stage 17 is integration-verified, not an excluded category. **Security ordering:** nothing sends data, since the app has no namer before Stage 18. **No shared test resource:** only Stage 16 launches the app test host, and Stage 17 is skipped without its variables. |
| 10 | Stage 18 | serial | same app files as Stage 16; consumes Stage 15's controller API; turns sending on only after every disclosure surface has landed (security ordering) |

**Critical path:** Stage 1 → Stage 2 → Stage 5 → Stage 7 → Stage 10 → Stage 12 → Stage 13 → Stage 14 → Stage 15 → Stage 18 (10 of 18 stages).

## Deviations from plan

- **Stage 2.** `Summariser` had two `escaped(_:closing:)` call sites (notes and transcript), not three. The DoD grep also matches `SummaryDocument.escaped(_:)`, a private HTML-entity escaper for the clipboard with different behaviour, so it stays. Stage 2's step and DoD are corrected in place.

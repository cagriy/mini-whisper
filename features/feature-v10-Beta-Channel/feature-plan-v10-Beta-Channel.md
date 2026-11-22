# Beta Channel — Implementation Plan v10

**Status:** Draft
**Date:** 2026-11-22
**Design:** [feature-design-v10-Beta-Channel.md](./feature-design-v10-Beta-Channel.md)

## Overview

v10 adds a Release/Beta update channel. The plan builds it in six stages on `main` (v0.8.1 plus its
appcast commit, no v9 commit), bottom-up. First, in parallel, the `update_channel` key in `MWConfig`
and the beta-aware `scripts/appcast.py`. Then, in parallel, the Sparkle wiring (`UpdateChannelPolicy`,
the updater delegate, the change reset in `AppDelegate.apply`) and the release-pipeline gates with
their CLAUDE.md runbook. Then `SettingsModel`'s channel state, and last the Updates card, the
confirmation Dialog and the CHANGELOG entry, so the control appears only once everything behind it
works. Every component in design §5 *Architecture* has a stage and every §3 requirement is in the
coverage map. Releasing 0.8.2, rebasing v9 and tagging 0.9.0b1 (design §9 steps 4–6) are operator
steps after Stage 6, covered in *Verification*.

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

In Swift, a test naming a type or member that does not exist yet fails to build before any assertion
runs. That build error is the first red; the stage then scaffolds the minimal empty API, re-confirms
red as assertion failures, and implements.

### Commands and observed baseline

Run once on `main` at `b64dd98`, 2026-11-22, before drafting.

| Layer | Command | Observed baseline |
| --- | --- | --- |
| Core package tests | `cd Packages/MiniWhisperCore && swift test` | exit 0; 18 `✔ Test run with … passed` lines, 1305 tests |
| MWConfig suite | `cd Packages/MiniWhisperCore && swift test --filter MWConfigTests` | `✔ Test run with 104 tests in 7 suites passed` |
| Core build | `cd Packages/MiniWhisperCore && swift build` | exit 0 |
| App tests | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test` | `✔ Test run with 519 tests in 50 suites passed`, `** TEST SUCCEEDED **` |
| One app suite | the App tests command plus `-only-testing:AppTests/<Suite>` | `-only-testing:AppTests/WindowFramePolicyTests` → `✔ Test run with 11 tests in 1 suite passed` |
| App build only | the App tests command with `build` in place of `test` | `** BUILD SUCCEEDED **` |
| Appcast script tests | `uv run --no-project --with pytest pytest scripts/tests/` | `14 passed` |
| Workflow step simulation | extract the "Resolve version" body with `uv run --no-project --with pyyaml python -c …` and run it with `bash -e` under a set `GITHUB_REF` and temp `GITHUB_OUTPUT` | today's body: `refs/tags/v0.8.1` → `version=0.8.1`; `refs/heads/main` → `version=0.8.1` |

Swift Testing output is preceded by XCTest's `Executed 0 tests` line; read the `✔/✘ Test run …` line.

**Registration.** A new file in an existing SwiftPM target directory (`Sources/MWConfig`) is
auto-discovered; no `Package.swift` edit. New files under `App/` and `AppTests/` are picked up by
xcodegen's folder sources on the next `xcodegen generate`, which the App tests command runs. No stage
adds a target. The generated `Mini Whisper.xcodeproj` is git-ignored.

**Test locations** (each verified runnable at its path):

- `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift` — extended; the `theme`
  cases (`themeDefaultsToSystemAndIsWritten`, `unknownThemeReadsAsSystemAndSurvivesASave`, …) are the
  pattern, with the file's `decode(_:)` and `saved(_:)` helpers.
- `scripts/tests/test_appcast.py` — extended; `scripts/tests/conftest.py` already puts `scripts/` on
  `sys.path`.
- `AppTests/UpdateChannelPolicyTests.swift` — new; sibling `AppTests/WindowFramePolicyTests.swift`
  (`import MWConfig`, `import Testing`, `@testable import MiniWhisper`, `@Suite struct …Tests`).
- `AppTests/SettingsModelTests.swift` — extended; its `Harness` (a real `ConfigStore` in a temp
  directory, `FakeUpdater` from `AppTests/SettingsFakes.swift`).

The SwiftUI views (`SettingRow`, `GeneralSection`, `MainView`) and the Sparkle and `AppDelegate`
wiring have no host harness (`AppDelegate` returns early under tests); they are verified by build and
the manual checks named in their stages.

**Facts the stages rely on**, read in Sparkle 2.9.6 (`.dd/SourcePackages/checkouts/Sparkle`) and in
this repo:

- `SPUUpdaterDelegate` is `NS_SWIFT_UI_ACTOR`; `allowedChannelsForUpdater:` imports as
  `allowedChannels(for:) -> Set<String>`, and Sparkle calls it while filtering a downloaded appcast
  (`SUAppcastDriver.m`, `filterAppcast:forMacOSAndAllowedChannels:`).
- `SPUStandardUpdaterController` holds its delegates weakly (`SPUStandardUpdaterController.h`), so
  the channel delegate needs a strong owner.
- `startUpdater:` and every check record the allowed channels (`SPUUpdater.m`, `_lastAllowedChannels`).
  `resetUpdateCycle` fires an immediate background check when the current set differs from the
  recorded one, even with automatic checks off, and otherwise reschedules;
  `resetUpdateCycleAfterShortDelay` runs it after 1 s. At launch the recorded set is `[]` (the
  delegate starts on Release), so switching to Beta checks at once, as R6 intends.
- Any non-empty `CFBundleVersion` is valid to Sparkle (`SUHost.m`, `isValidVersion`).
- CI's "Extract release notes" matches `## [<version>]` as a literal prefix (`index($0, heading) == 1`),
  so `## [0.9.0b1]` matches neither `## [0.9.0]` nor `## [0.9.0b10]`; it needs no change.
- `ConfigStore.changes` yields only from an in-app `update`. An out-of-process edit only marks the
  cache stale, and reaches `AppDelegate.apply` with the next in-app write.

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: Updates card rows in order — automatic checks with version line, "Update channel" pill (Release default), Check Now | Stage 5 (`updateChannel`), Stage 6 (row and pill) |
| R2: `update_channel` in `config.json`; absent or unknown reads Release, unknown round-trips; Sparkle's preferences untouched | Stage 1 |
| R3: Beta asks first through the Dialog; Switch to Beta stores `"beta"`, Cancel stores nothing | Stage 5 (model), Stage 6 (Dialog) |
| R4: Release stores at once, no Dialog | Stage 5 (model), Stage 6 (pill) |
| R5: Allowed channels `[]` for Release, `["beta"]` for Beta, for scheduled checks and Check Now | Stage 3 |
| R6: A channel change after launch calls `resetUpdateCycleAfterShortDelay()`; the launch load does not | Stage 3 (fed by Stage 1's key) |
| R7: No downgrade; the row says so | Stage 6 (row description); Sparkle's own version comparison, no code path added (Stage 3); checked in *Verification* step 4 |
| R8: A beta build shows "Version X.Y.ZbN", a Plain "Beta" chip, then the sentence | Stage 3 (`isBeta`), Stage 5 (`isBetaBuild`, injectable `appVersion`), Stage 6 (chip) |
| R9: Release `X.Y.Z`, beta `X.Y.ZbN` (N ≥ 1), one string everywhere; any other tag fails before publishing | Stage 2 (pattern), Stage 4 ("Resolve version" gate) |
| R10: `appcast.py` accepts betas, writes the beta channel element, `--print-channel` | Stage 2 |
| R11: CI per channel — prerelease, Homebrew skipped, beta-channel item | Stage 4; confirmed on the real tags after Stage 6 (*Verification* steps 5 and 7) |
| R12: A CHANGELOG section per beta; the final release consolidates | Stage 4 (convention in CLAUDE.md); applied by the operator at each release |
| R13: 0.8.2 from `main` without v9, then rebase v9, then tag 0.9.0b1 | Stage 1 (gate: no v9 commit on `main`) and every stage (built on `main`); rebase and tag are operator steps after Stage 6 (*Verification* steps 6–7) |
| R14: One `Update channel: <release\|beta>` line per change through `Log.ui`, nothing else | Stage 3 |
| R15: CHANGELOG `[Unreleased]` entry; CLAUDE.md release section | Stage 6 (CHANGELOG), Stage 4 (CLAUDE.md) |

Design §5 components → stages: `UpdateChannel`, `Config.updateChannel` → 1; `appcast.py` → 2;
`UpdateChannelPolicy`, `AppUpdater`, `UpdaterChannelDelegate`, `AppDelegate.apply` → 3; `build.yml` → 4;
`SettingsModel` → 5; Updates card, Beta dialog → 6.

## Stages

### Stage 1 — `update_channel` in `Config`
**Goal:** `Config` reads and writes `update_channel` as a closed `UpdateChannel`, following `theme`'s round-trip rules.
**Design references:** §3 R2, R13; §5 Architecture (`UpdateChannel`, `Config.updateChannel`), Data model, Failure and edge cases, Testing strategy (`ConfigCodingTests`) of feature-design-v10-Beta-Channel.md
**Touches:** `Packages/MiniWhisperCore/Sources/MWConfig/UpdateChannel.swift` (new), `Packages/MiniWhisperCore/Sources/MWConfig/Config.swift`, `Packages/MiniWhisperCore/Tests/MWConfigTests/ConfigCodingTests.swift`

**Steps (TDD):**
0. Gate (R13.1, read-only): `git merge-base --is-ancestor v9-naming HEAD` exits 1, and
   `git log --oneline HEAD..v9-naming | wc -l` prints `32`. `main` carries no v9 commit. If either
   check fails, stop: 0.8.2 must not contain v9.
1. Write test: in `ConfigCodingTests.swift`, after the theme cases:
   - `updateChannelAbsentIsReleaseAndIsWritten` — `decode("{}")` gives `.release`;
     `saved(config)["update_channel"] as? String == "release"`; `String(decoding: try Config().encoded(), as: UTF8.self)`
     contains `"update_channel" : "release"`.
   - `updateChannelRoundTripsEachValue` — `UpdateChannel.allCases.map(\.rawValue) == ["release", "beta"]`;
     each value decodes to its case and saves as itself.
   - `unknownUpdateChannelReadsAsReleaseAndSurvivesASave` — `{"update_channel": "nightly"}` gives
     `.release`, `extra.isEmpty`, and saves `"nightly"`.
   - `settingUpdateChannelClearsTheUnrecognisedValue` — after decoding `"nightly"`, setting each case
     saves that case.
   - `wrongTypedUpdateChannelThrows` — `#expect(throws: (any Error).self) { try decode(#"{"update_channel": 1}"#) }`.
   - `updateChannelNeverLandsInExtra` — `{"update_channel": "beta"}` leaves `extra` empty.

   Expected initial failure: the MWConfigTests target does not build — `cannot find 'UpdateChannel' in scope`
   and `value of type 'Config' has no member 'updateChannel'`.
2. Run `swift test --filter MWConfigTests` — confirm the build error. Scaffold
   `UpdateChannel.swift` with `public enum UpdateChannel: String, Sendable, CaseIterable { case release, beta }`
   (doc comment as `AppTheme.swift`'s) and `public var updateChannel: UpdateChannel = .release` on
   `Config`, with no coding. Re-run — confirm assertion failures: `"beta"` reads `.release`,
   `update_channel` is absent from a new config's JSON, the key lands in `extra`, and the wrong-typed
   value does not throw.
3. Implement in `Config.swift`, mirroring `theme`: `didSet { unrecognisedUpdateChannel = nil }` on
   `updateChannel`; `var unrecognisedUpdateChannel: String?`; `Key.updateChannel = "update_channel"`,
   added to `Key.all`; decode with `let raw: String? = try value(Key.updateChannel)` (a wrong type
   throws), `.release` for absent or unknown, keeping an unknown raw value; encode
   `unrecognisedUpdateChannel ?? updateChannel.rawValue`.
4. Run the MWConfig suite — confirm pass. Run `swift test` and `swift build` in
   `Packages/MiniWhisperCore` — no regressions. Run the app build-only command — the app still
   compiles.

**Definition of done:**
- The six new cases pass; the MWConfig suite and the full core suite are green; `swift build` exits 0;
  the app builds.
- `Config().encoded()` writes `"update_channel" : "release"`, and `Key.all` holds the key.

**Risks specific to this stage:** None.

### Stage 2 — Beta versions and channels in `appcast.py`
**Goal:** `scripts/appcast.py` accepts `X.Y.ZbN`, tags a beta item with `<sparkle:channel>beta</sparkle:channel>`, and prints a version's channel.
**Design references:** §3 R9, R10; §5 Architecture (`appcast.py`), Interfaces (`scripts/appcast.py` CLI), Compatibility (release items byte-identical), Testing strategy (`scripts/tests/test_appcast.py`)
**Touches:** `scripts/appcast.py`, `scripts/tests/test_appcast.py`

**Steps (TDD):**
1. Write a characterization guard first: `TestReleaseItemBytes.test_release_item_matches_the_published_feed`.
   Parse the repo's `appcast.xml` (`Path(__file__).resolve().parents[2]`), take the `0.8.1` item, set
   every whitespace-only `text`/`tail` to `None`, rebuild it with `appcast.build_item` from its own
   version, `edSignature`, `length`, `description` and `pubDate`
   (`email.utils.parsedate_to_datetime`), and assert `ET.tostring(rebuilt) == ET.tostring(published)`.
   It guards against any change to release-item bytes, so it is green before and after this stage
   (prototyped during planning against the unmodified script: equal). Run it once to confirm green.
2. Write test — the behaviour cases:
   - `TestChannel.test_beta_item_carries_the_beta_channel` — inserting `0.9.0b1` writes exactly one
     `{sparkle}channel` child with text `beta`; title, version, short version and enclosure URL
     (`…/download/v0.9.0b1/MiniWhisper-0.9.0b1-arm64.dmg`) use the beta string.
   - `TestChannel.test_release_item_has_no_channel` — `0.8.2` has no `{sparkle}channel` child.
   - `TestChannel.test_beta_insert_keeps_release_items_byte_identical` — insert `0.8.2`, keep its
     `ET.tostring`, insert `0.9.0b1`; the `0.8.2` item is unchanged and the beta item comes first.
   - `TestChannelOf.test_channel_of` — `"release"` for `0.8.2`; `"beta"` for `0.9.0b1` and `1.10.2b12`;
     `ValueError` for `0.9.0-beta.1`, `v0.9.0`, `0.9`, `0.9.0b0`, `0.9.0b`, `0.9.0rc1`.
   - `TestPrintChannel.test_prints_the_channel` (parametrised `0.8.2`→`release`, `0.9.0b1`→`beta`) —
     `appcast.main(["--print-channel", version]) == 0` and `capsys` stdout is the channel and a newline.
   - `TestPrintChannel.test_rejects_other_forms` (parametrised `0.9.0-beta.1`, `v0.9.0`, `0.9`, `0.9.0b0`) —
     `SystemExit` with `code == 2`, and `capsys` stderr names the rejected value. Today's argparse also
     exits 2, for missing arguments, so the stderr check is what makes this red first.
   - `TestValidation.test_malformed_beta_version` — inserting `0.9.0-beta.1` raises `SystemExit`. This
     is green before and after: it guards that widening the pattern still rejects the hyphenated form.
     So is `test_release_item_has_no_channel`.

   Expected initial failure: `AttributeError: module 'appcast' has no attribute 'channel_of'`;
   `--print-channel` exits 2 with argparse's missing-required-arguments / unrecognised-arguments error;
   inserting `0.9.0b1` exits 2 with `version '0.9.0b1' is not X.Y.Z`; the rejection cases fail on
   stderr, which names the missing arguments, not the version.
3. Run `uv run --no-project --with pytest pytest scripts/tests/` — confirm those failures, with the
   guard, the two guard cases above and the 14 existing tests passing.
4. Implement in `scripts/appcast.py`:
   - `VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+(b[1-9]\d*)?")`, used with `fullmatch` (R9's N ≥ 1;
     *Planning decisions* 3).
   - `channel_of(version: str) -> str` — `"beta"` when the `b` group matched, `"release"` otherwise,
     `ValueError` for any other form.
   - `build_item` adds `ET.SubElement(item, sparkle("channel")).text = "beta"` after
     `minimumSystemVersion` for a beta only; a release item is built exactly as today.
   - `main`: a `--print-channel VERSION` option. When given, print `channel_of(...)` and return 0, or
     `parser.error(...)` (exit 2) on `ValueError`. The insert-mode options lose `required=True` and are
     checked with `parser.error` (exit 2) when `--print-channel` is absent. Insert mode validates with
     `VERSION_PATTERN` and says `is not X.Y.Z or X.Y.ZbN`.
   - Module docstring: add the `--print-channel` usage line.
5. Run the script tests — confirm all pass (14 existing, the guard, the new cases).

**Definition of done:**
- Every script test is green; the guard passed before and after the change.
- `python3 scripts/appcast.py --print-channel 0.9.0b1` prints `beta`; `--print-channel 0.9.0-beta.1` exits 2.

**Risks specific to this stage:** the guard depends on `appcast.xml` keeping its `0.8.1` item. If that
item is ever removed, replace the guard with a literal captured from `build_item`.

### Stage 3 — Sparkle channel filter and change reset
**Category:** hybrid — full TDD for the pure `UpdateChannelPolicy`; *integration-verified remainder* for
the `AppUpdater` and `AppDelegate.apply` wiring, which has no host harness (Sparkle, and `AppDelegate`
returning early under tests). The remainder is verified by the app build and the AppTests run, and
exercised end to end by *Verification* step 4 once Stage 6 provides the control.
**Goal:** Sparkle allows only the channels the config names, and a channel change after launch resets the update cycle and logs one line.
**Design references:** §3 R5, R6, R8 (`isBeta`), R14; §5 Architecture (`UpdateChannelPolicy`, `AppUpdater`, `UpdaterChannelDelegate`, `AppDelegate.apply`), Control flow (Launch, Opt in, Opt out, Check Now), Observability, Testing strategy (`UpdateChannelPolicyTests`)
**Touches:** `App/UpdateChannelPolicy.swift` (new), `AppTests/UpdateChannelPolicyTests.swift` (new), `App/AppUpdater.swift`, `App/AppDelegate.swift`

**Steps (TDD for the policy):**
1. Write test: `AppTests/UpdateChannelPolicyTests.swift`, `@Suite struct UpdateChannelPolicyTests`:
   - `sparkleChannelsFollowTheChannel` — `sparkleChannels(for: .release) == []`,
     `sparkleChannels(for: .beta) == ["beta"]`.
   - `isBetaRecognisesBetaVersions` (arguments `"0.9.0b1"`, `"1.10.2b12"`) — true.
   - `isBetaRejectsEverythingElse` (arguments `"0.8.2"`, `"0.9.0-beta.1"`, `"0.9.0b"`, `"0.9.0rc1"`, `""`) — false.
   - `trackerReportsOnlyChangesAfterTheFirst` — a fresh `Tracker`: `apply(.release)` false, `apply(.release)`
     false, `apply(.beta)` true, `apply(.release)` true; a fresh tracker whose first apply is `.beta` returns false.

   Expected initial failure: the AppTests target does not build — `cannot find 'UpdateChannelPolicy' in scope`.
2. Run `xcodegen generate` and the app test command with `-only-testing:AppTests/UpdateChannelPolicyTests` —
   confirm the build error. Scaffold `App/UpdateChannelPolicy.swift` (`import MWConfig`): `enum UpdateChannelPolicy`
   with `sparkleChannels(for:)` returning `[]`, `isBeta(version:)` returning `false`, and
   `struct Tracker { mutating func apply(_ channel: UpdateChannel) -> Bool }` returning `false`.
   Re-run — confirm assertion failures for the `.beta` set, both beta versions and the tracker's two
   `true` cases.
3. Implement: `sparkleChannels` — `[]` or `["beta"]` by a `switch`; `isBeta` —
   `version.wholeMatch(of: /\d+\.\d+\.\d+b\d+/) != nil` (R8's pattern); `Tracker` —
   `private var last: UpdateChannel?`, `apply` returns `last != nil && last != channel` and then stores
   `channel`.
4. Run the focused suite — confirm pass.
5. Wiring (integration-verified remainder):
   - `App/AppUpdater.swift`: `import MWConfig`; `static var channel: UpdateChannel = .release`;
     `private static let channelDelegate = UpdaterChannelDelegate()`, a strong reference because Sparkle
     holds delegates weakly; `start()` passes `updaterDelegate: channelDelegate`;
     `static func channelChanged() { controller?.updater.resetUpdateCycleAfterShortDelay() }`;
     `private final class UpdaterChannelDelegate: NSObject, SPUUpdaterDelegate` with
     `func allowedChannels(for updater: SPUUpdater) -> Set<String> { UpdateChannelPolicy.sparkleChannels(for: AppUpdater.channel) }`.
     The protocol is `NS_SWIFT_UI_ACTOR`, so the witness is main-actor isolated and reads
     `AppUpdater.channel` directly. Amend `AppUpdater`'s doc comment: the channel is the one updater
     setting that comes from `config.json`.
   - `App/AppDelegate.swift`: `private var channelTracker = UpdateChannelPolicy.Tracker()`; in
     `apply(_:)`, after the overlay-style block, `AppUpdater.channel = config.updateChannel`, then
     `if channelTracker.apply(config.updateChannel) { Log.ui.info("Update channel: \(config.updateChannel.rawValue)"); AppUpdater.channelChanged() }`.
6. Run the full app test command — confirm `** TEST SUCCEEDED **` with the baseline 519 plus the new
   cases. Run the core suite — unchanged.

**Definition of done:**
- `UpdateChannelPolicyTests` green; full AppTests green; the app builds.
- The delegate is held by a static `let` and passed to `SPUStandardUpdaterController`. The launch
  `apply` sets `AppUpdater.channel` without logging or resetting (the tracker's first apply).

**Risks specific to this stage:** an unretained delegate would make Sparkle fall back to the default
channel silently, so a beta would never be offered. The static `let` prevents it; *Verification* step
4.2 would catch it.

### Stage 4 — Release pipeline per channel, and its runbook
**Category:** non-TDD (config-only) — a GitHub Actions workflow and documentation. Nothing is
host-assertable beyond the local checks in step 6; R11 is confirmed on the real tags (*Verification*
steps 5 and 7).
**Goal:** a beta tag builds, signs, notarises and publishes a prerelease with a beta-channel item and no Homebrew bump; a malformed tag fails before anything is published; CLAUDE.md documents the process.
**Design references:** §3 R9, R11, R12, R15; §5 Architecture (`build.yml`), Interfaces (`build.yml`), Control flow (Release a beta, Release a release), Failure and edge cases (malformed tag, bad beta), Observability (CI); §9 Rollout
**Touches:** `.github/workflows/build.yml`, `CLAUDE.md`

**Steps:**
1. `build.yml`, "Resolve version": after `version` is computed, on its own line,
   `channel=$(python3 scripts/appcast.py --print-channel "$version")`. A plain assignment, so the step's
   `bash -e` stops on the script's exit 2. Then write `channel=$channel` to `$GITHUB_OUTPUT` and append
   ``Version `$version`, channel `$channel` `` to `$GITHUB_STEP_SUMMARY`.
2. "Create GitHub Release": `prerelease: ${{ steps.version.outputs.channel == 'beta' }}`, replacing the
   `-beta`/`-rc` test.
3. "Update Homebrew tap": its `if:` gains `&& steps.version.outputs.channel == 'release'`.
4. "Publish appcast": unchanged; the script tags the item.
5. CLAUDE.md, *Releases and auto-updates* — add:
   - the beta format: tag `vX.Y.ZbN` (N ≥ 1), with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` both
     `X.Y.ZbN`. Any other suffix (`-beta.1`, `rc1`) fails "Resolve version" before signing; Sparkle
     stops comparing at a `-`;
   - R11's per-channel table (GitHub release, Homebrew cask, appcast item);
   - R12's CHANGELOG convention: a `## [X.Y.ZbN] - YYYY-MM-DD` section per beta with the changes since
     the previous beta, or since the last release for the first; the final `## [X.Y.Z]` lists
     everything since the previous release;
   - pulling a bad beta: remove its `<item>` from `appcast.xml` on `main`, or ship `bN+1`; users already
     on it stay until the next beta or release;
   - the channel is `update_channel` in `config.json`, applied through `AppUpdater`'s delegate — not a
     Sparkle preference;
   - under "Test an update without publishing": a beta item needs `<sparkle:channel>beta</sparkle:channel>`
     and the Beta setting.
6. Verify locally:
   - `uv run --no-project --with pyyaml python -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml'))"` exits 0.
   - Extract the "Resolve version" `run:` body to the scratchpad with the same `yaml` one-liner, and run
     it with `bash -e` from the repo root under `GITHUB_REF=…` and temp `GITHUB_OUTPUT` and
     `GITHUB_STEP_SUMMARY` files: `refs/tags/v0.9.0b1` → `version=0.9.0b1`, `channel=beta`;
     `refs/tags/v0.8.2` → `channel=release`; `refs/heads/main` → `version=0.8.1`, `channel=release`;
     `refs/tags/v0.9.0-beta.1` → non-zero exit and no `channel=` line.
   - `grep -n "prerelease:\|channel == 'release'" .github/workflows/build.yml` shows both gates.
   - The script tests stay green.

**Definition of done:** the three workflow edits are in; the YAML parses; the four simulated refs
behave as listed; CLAUDE.md's release section covers R15's four topics.

**Risks specific to this stage:** None beyond the real-tag check, which only the post-plan release runs can make.

### Stage 5 — Channel choice in `SettingsModel`
**Goal:** Settings holds the channel, asks before Beta, applies Release at once, and knows a beta build.
**Design references:** §3 R1, R3, R4, R8; §5 Architecture (`SettingsModel`), Interfaces (`SettingsModel` behaviour), Failure and edge cases (write fails, navigation away), Testing strategy (`SettingsModelTests`)
**Touches:** `App/Settings/SettingsModel.swift`, `AppTests/SettingsModelTests.swift`

**Steps (TDD):**
1. Write test: extend `SettingsModelTests`. `Harness.model(...)` gains `appVersion: String = "0.8.2"`,
   passed to `SettingsModel.Dependencies(appVersion:)`. New cases under
   `// MARK: - Update channel (design v10 §3 R3, R4, R8)`:
   - `updateChannelStartsFromTheConfig` — with `writeConfig(#"{"update_channel": "beta"}"#)`,
     `model.updateChannel == .beta`; with no config, `.release`.
   - `choosingBetaAsksAndWritesNothing` — `chooseUpdateChannel(.beta)` sets `confirmingBetaChannel`;
     `updateChannel` and the store stay `.release`.
   - `confirmingBetaWritesBetaAndClearsTheQuestion` — then `confirmBetaChannel()`: flag false,
     `updateChannel` and the store `.beta`.
   - `cancellingBetaWritesNothing` — then `cancelBetaChannel()`: flag false, `updateChannel` and the
     store `.release`.
   - `choosingReleaseWritesAtOnce` — from a Beta config, `chooseUpdateChannel(.release)`: no flag, the
     store `.release`.
   - `choosingTheCurrentChannelDoesNothing` — `.release` on Release and `.beta` on Beta: the flag stays
     false and the store is unchanged.
   - `isBetaBuildFollowsTheVersion` — `appVersion: "0.9.0b1"` gives `isBetaBuild` and
     `model.appVersion == "0.9.0b1"`; `"0.8.2"` gives `!isBetaBuild`.
   - `refreshReadsTheUpdateChannel` — `harness.store.update { @Sendable in $0.updateChannel = .beta }`, then
     `model.refresh(from: await harness.store.load())` gives `.beta` (as `refreshReadsTheTheme`).

   Expected initial failure: AppTests does not build — `extra argument 'appVersion' in call` and
   `value of type 'SettingsModel' has no member 'chooseUpdateChannel'` (and the other new members).
2. Run the app test command with `-only-testing:AppTests/SettingsModelTests` — confirm the build
   errors. Scaffold: `Dependencies.appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"`,
   declared after `people`; `appVersion` returns it; `var updateChannel: UpdateChannel { config.updateChannel }`;
   `private(set) var confirmingBetaChannel = false`; empty `chooseUpdateChannel(_:) async`,
   `confirmBetaChannel() async` and `cancelBetaChannel()`; `isBetaBuild` returning `false`. Re-run —
   confirm assertion failures: the flag stays false after choosing Beta, the store stays `.release`
   after confirming, it stays `.beta` after choosing Release, and `isBetaBuild` is false for `0.9.0b1`.
3. Implement under `// MARK: - Updates (design v10)`: `chooseUpdateChannel` returns when the choice
   equals `updateChannel`; `.beta` sets the flag; `.release` calls `write { $0.updateChannel = .release }`.
   `confirmBetaChannel` clears the flag, then `write { $0.updateChannel = .beta }`. `cancelBetaChannel`
   clears the flag. `isBetaBuild` is `UpdateChannelPolicy.isBeta(version: appVersion)`.
4. Run the focused suite — confirm pass. Run the full app test command — no regressions;
   `MainWindowModelTests` builds unchanged through the defaulted `appVersion`.

**Definition of done:**
- The eight new cases pass; full AppTests green.
- The `SettingsModel.Dependencies(...)` calls in `AppDelegate` and `MainWindowModelTests` compile unchanged.

**Risks specific to this stage:** None.

### Stage 6 — Updates card, Beta dialog, CHANGELOG
**Category:** platform-only / UI wiring — SwiftUI views with no host harness. The logic they call is
Stage 5's and already under test. Verified by the app build, the full suites and the manual checks in
step 5.
**Goal:** the Updates card shows the channel pill between the two existing rows, a beta build shows the Beta chip, and choosing Beta opens the Dialog.
**Design references:** §3 R1, R3, R4, R7, R8, R15; §5 Interfaces (Settings › General › Updates, Beta dialog), Design language; `DESIGN.md` — Settings card, Setting row, Segmented pill switch, Chip (Plain), Dialog, "one filled accent button per page or dialog", sentence case; the accepted mockup `mockups/mockup-v10-segmented.html#segmented`
**Touches:** `App/Design/SettingRow.swift`, `App/Settings/GeneralSection.swift`, `App/Main/MainView.swift`, `CHANGELOG.md`

**Steps:**
1. `SettingRow`: add `init(_ title: String, error: String? = nil, @ViewBuilder description: () -> some View, @ViewBuilder control: () -> Content)`.
   It stores the description view type-erased and renders it where the string description goes, with
   `DS.Colors.textSecondary` and the same 414-pt maximum width. The string initialiser and `.full`
   render exactly as today.
2. `GeneralSection`, Updates card:
   - Row 1, release build: the string description, unchanged. Beta build (`model.isBetaBuild`): the
     view-builder initialiser with `HStack(spacing: DS.Space.s3) { Text("Version \(model.appVersion)").textStyle(.meta); Chip("Beta") }`
     above `Text("Checked once a day; an update installs only after you approve it.").textStyle(.meta)`
     (*Planning decisions* 9).
   - Row 2: `SettingRow("Update channel", description: "Release gets tested versions. Beta gets new versions first, and they may have bugs. Switching back to Release keeps an installed beta until the next release.")`
     with `SegmentedPill(selection: settingsBinding(model.updateChannel) { await model.chooseUpdateChannel($0) }, options: [(.release, "Release"), (.beta, "Beta")])`.
   - Row 3: unchanged. Amend the struct's doc comment.
3. `MainView`: a dialog branch after People's confirmation —
   `else if model.settings.confirmingBetaChannel { DSDialog(title: "Switch to beta versions?", message: "Beta versions arrive before each release and may have bugs. You can switch back to Release at any time; an installed beta stays until the next release.", confirmTitle: "Switch to Beta", confirm: { Task { await model.settings.confirmBetaChannel() } }, cancel: model.settings.cancelBetaChannel) }`.
   The existing `.onChange(of: model.navigation.destination)` also calls `model.settings.cancelBetaChannel()`.
4. `CHANGELOG.md` `[Unreleased]`: an `### Added` entry — "Settings → General → Updates: choose Release
   or Beta versions. Beta gets new versions first; switching back to Release keeps an installed beta
   until the next release."
5. Verify:
   - The app build-only and full app test commands are green; the core suite and script tests unchanged.
   - Manual, on the Debug build (quit the installed app first; this uses the real
     `~/.config/mini-whisper/config.json`): Settings › General › Updates shows the three rows in R1's
     order with Release selected. Beta opens the Dialog with R3's exact copy. Cancel, Esc and a scrim
     click each leave Release, and `grep update_channel ~/.config/mini-whisper/config.json` shows
     `"release"`. Switch to Beta stores `"beta"`, and
     `log show --last 5m --predicate 'subsystem == "com.ips.mini-whisper" AND category == "ui"' | grep "Update channel"`
     shows `Update channel: beta`. Release stores `"release"` at once with no Dialog and logs
     `Update channel: release`. With the Dialog open, the status-item menu's "Meetings…" dismisses it
     and nothing is written. End on Release.
   - Beta build: the app build-only command with `MARKETING_VERSION=0.9.0b1 CURRENT_PROJECT_VERSION=0.9.0b1`
     appended; `plutil -extract CFBundleVersion raw ".dd/Build/Products/Debug/Mini Whisper.app/Contents/Info.plist"`
     prints `0.9.0b1` (design §7, first risk). The card shows "Version 0.9.0b1" with the Plain "Beta"
     chip; compare with the accepted mockup in light and dark. Rebuild without the overrides afterwards.

**Definition of done:** builds and suites green; every manual check passes; the config is left on Release.

**Risks specific to this stage:** the mockup flows the chip inline ("Version 0.9.0b1 [Beta]. Checked
once a day…"). SwiftUI `Text` on macOS 14 cannot hold a view, so the two-line layout keeps R8's order
instead. If the visual check finds it wrong, adjust the layout inside the row; the model is unaffected.

## Cross-cutting concerns

- **Security** — no new trust boundary (design §5 Security). The channel is a closed enum (Stage 1),
  and the delegate returns only `[]` or `["beta"]` (Stage 3). A beta build goes through the same
  signing, notarisation, stapling and `sign_update` steps (Stage 4 changes only the prerelease flag
  and the Homebrew gate). No secret is read, added or logged; the Homebrew token is simply unused for
  a beta. The only log line carries the channel name (Stage 3, R14). Pipeline ordering: before
  Stage 4, a beta tag would bump Homebrew and publish a non-prerelease — true today as well, since
  those steps precede the appcast step that rejects it. Stage 2 adds no exposure: its beta item is
  channel-tagged, which every shipped Sparkle client filters out. No tag is pushed until every stage
  has landed (design §9).
- **Performance** — none in practice: one enum read per update check and one cycle reset per change.
- **Observability** — `Update channel: <channel>` through `Log.ui` on a change after launch only
  (Stage 3); CI's resolved version and channel in the "Resolve version" output and the job summary,
  with a malformed tag failing that step visibly (Stage 4).
- **Compatibility / migration** — `update_channel` is additive with no migration; absent reads Release
  (Stage 1). Older builds keep it in `extra`. Release items stay byte-identical, guarded against the
  published feed (Stage 2). Shipped clients (Sparkle ≥ 2.9.6) ignore beta items. The Python legacy app
  does not read the key. `SettingsModel.Dependencies.appVersion` is defaulted, so every existing
  construction site compiles unchanged (Stage 5).
- **Intermediate states** — the user-visible behaviour after each contributing stage:
  - R3/R4/R1/R8 span Stages 5 and 6. After Stage 5, nothing is visible: no view reads the new model
    members. After Stage 6, the feature is complete. They stay separate: Stage 5 is host-tested model
    logic, Stage 6 untestable view wiring.
  - R5/R6 land in Stage 3 alone. Before Stage 6, only a hand-edited `update_channel` can reach them, and
    the feed has no beta item yet, so nothing changes for anyone.
  - R9 spans Stages 2 and 4. Between them, the pipeline accepts a beta appcast item but does not yet
    gate Homebrew or the prerelease flag. No tag is pushed during implementation, so they stay
    separate; Stage 4 also needs Stage 2's CLI.
  - Old and new never compete for the same behaviour, so no atomic swap is needed.

## Verification

Once all stages have landed:

1. `cd Packages/MiniWhisperCore && swift test` — every `✔ Test run …` line passes (baseline 1305 plus Stage 1's cases); `swift build` exits 0.
2. The App tests command — `** TEST SUCCEEDED **` (baseline 519 plus Stages 3 and 5).
3. `uv run --no-project --with pytest pytest scripts/tests/` — all pass (baseline 14 plus Stage 2's).
4. Manual Sparkle channel check (design §5 Testing strategy; before tagging 0.8.2), through CLAUDE.md's
   "Test an update without publishing":
   - Make a DMG, sign it with `sign_update --account mini-whisper <dmg>`, and build a doctored appcast in
     the scratchpad with `scripts/appcast.py`: a default `0.8.3` item and a beta `0.9.0b1` item, enclosure
     URLs pointed at `http://localhost:8000/<dmg>`. Serve it with `python3 -m http.server 8000`, then
     `defaults write com.ips.mini-whisper SUFeedURL http://localhost:8000/appcast.xml` and
     `defaults delete com.ips.mini-whisper SULastCheckTime`. Run the Debug build (0.8.1).
   1. On Release, Check Now offers 0.8.3 only. Choose "Remind Me Later", not "Skip This Version".
   2. Switch to Beta and confirm: within a few seconds Sparkle offers 0.9.0b1 without Check Now (cycle reset).
   3. Back on Release, Check Now offers 0.8.3, never 0.9.0b1 (R5, R7).
   4. Clean up: `defaults delete com.ips.mini-whisper SUFeedURL`, stop the server, leave the setting on Release.
5. Release 0.8.2 (design §9 step 4, operator): `gh release view v0.8.2 --json isPrerelease` → `false`;
   the tap's log has `Update mini-whisper to 0.8.2`; the `0.8.2` item in `appcast.xml` has no
   `sparkle:channel`; CLAUDE.md's `stapler`, `sign_update --verify` and `spctl` checks pass. Pull `main`.
6. Rebase v9 (design §9 step 5): `git rebase main v9-naming`, resolving the conflicts named in design §7;
   run all three suites; fast-forward `main`; refresh the v9 tracker's SHAs.
7. Release 0.9.0b1 (design §9 step 6): `gh release view v0.9.0b1 --json isPrerelease` → `true`; the tap
   has no 0.9.0b1 commit; the item carries `<sparkle:channel>beta</sparkle:channel>`; the same signature
   checks pass. A Beta-channel machine is offered the update and a Release machine is not.

## Risks and open issues

1. **Sparkle delegate lifetime.** An unretained delegate makes the filter silently Release-only.
   Mitigation: static `let` in Stage 3; *Verification* 4.2 fails if it is missing.
2. **Swift 6 isolation of the delegate.** `SPUUpdaterDelegate` is main-actor (`NS_SWIFT_UI_ACTOR`); a
   non-isolated witness would not compile. Mitigation: Stage 3 writes the witness as main-actor and
   reads `AppUpdater.channel` directly, with no `assumeIsolated`.
3. **Beta version line differs from the mockup's inline flow.** Mitigation: a two-line layout in the
   same row (Stage 6), checked against the mockup in both appearances; layout-only to adjust.
4. **External edits of `update_channel` apply late.** An out-of-process edit reaches `apply`, and
   R6's reset, only with the next in-app config write, as for every other key. Mitigation: documented
   in the design (§4) and here; Settings, the path users take, applies at once.
5. **The manual checks touch real state** — `config.json` and Sparkle's `SUFeedURL`/`SULastCheckTime`.
   Mitigation: each check names its clean-up and ends on Release.
6. **The byte-identity guard reads `appcast.xml`.** Mitigation: it pins the `0.8.1` item, a published
   release never removed; Stage 2 names the fallback.
7. **`python3` on the CI runner.** "Resolve version" now needs it. Mitigation: "Publish appcast" already
   runs `python3 scripts/appcast.py` on the same runner, and a missing interpreter fails before signing.
8. **v9 rebase conflicts** (design §7) — post-plan. Mitigation: *Verification* step 6 runs all suites
   before 0.9.0b1 is tagged.

## Planning decisions taken

1. **Stage order.** Data and script first; Sparkle wiring and pipeline next; then the settings model;
   UI last. Each stage lands green, and the control appears only once the wiring behind it works.
2. **One hybrid stage for policy and wiring (Stage 3).** `UpdateChannelPolicy` exists only for that
   wiring. `isBeta` lands there too, and Stage 5 consumes it.
3. **appcast.py pattern `^\d+\.\d+\.\d+(b[1-9]\d*)?$`.** This resolves an internal contradiction:
   §3 R9 says N ≥ 1, while §5 gave `(b\d+)?`, which accepts `b0`. §3 wins, and design §5 was corrected
   in place. `isBeta` keeps R8's `b\d+` verbatim: it is display-only, and a `b0` build cannot be released.
4. **`UpdateChannel` in its own file**, `Sources/MWConfig/UpdateChannel.swift`, as `AppTheme`,
   `EngineName` and `MeetingEngine` are, not inside `Config.swift`. Same module, same interface.
5. **Byte identity guarded against the published 0.8.1 item** rather than a captured literal, so it
   checks bytes that actually shipped (prototyped green during planning).
6. **`--print-channel` mode.** The insert-mode options become conditionally required through
   `parser.error` (still exit 2), so print mode needs no other argument, as design §5 specifies.
7. **CI job summary.** "Resolve version" also appends version and channel to `$GITHUB_STEP_SUMMARY`,
   reading design §5 Observability's "step summary" literally.
8. **Local CI verification** by a YAML parse and by running the "Resolve version" body under simulated
   refs (harness prototyped during planning). R11 itself is checked on the real tags.
9. **Beta version line.** It is laid out in two lines — version and Chip, then the sentence — through
   a new view-builder `SettingRow` initialiser, because SwiftUI `Text` on macOS 14 cannot hold a view.
   Release builds keep today's string. The initialiser is code-level only: no token, variant or rule
   is added to DESIGN.md.
10. **The delegate is retained by `private static let channelDelegate`**, since Sparkle references
    delegates weakly (`SPUStandardUpdaterController.h`). The design was silent on ownership.
11. **No separate docs stage.** The CLAUDE.md runbook rides with the CI stage, which it documents, and
    the CHANGELOG entry with the UI stage, which makes the feature user-visible.
12. **The manual Sparkle check sits in *Verification*,** after Stage 6, because it needs the Settings
    control. Stage 3's wiring is build-verified until then.
13. **Stage 1 opens with a read-only gate** that `main` carries no v9 commit (R13.1).
14. **Design facts corrected in place:**
    - the version anchors are `project.yml:80` and `:83`, not `:82` and `:85`;
    - the `SettingsModelTests` harness uses a real `ConfigStore` in a temp directory, not a config-store fake;
    - `ConfigStore.changes` yields only on an in-app `update`, so an out-of-process edit reaches
      `apply` with the next in-app write (§4 now says so). R6 is still delivered through `apply`.
15. **Schedule cut.** Stages 1 ∥ 2 and 3 ∥ 4; see the table's evidence.

## Deviations from the design

None — plan matches design v10 exactly.

## Deviations from plan

None in behaviour. Implementation notes from `/feature-implement`:

1. Stage 3: `trackerReportsOnlyChangesAfterTheFirst` binds each `apply` result to a local before
   `#expect`, because a mutating call inside `#expect`'s closure does not compile.
2. Stage 6: the first Updates row uses the new view-builder `SettingRow` initialiser for release
   builds too, so the Toggle is written once. A release build still renders the single line
   "Version X. Checked once a day; an update installs only after you approve it."

## Execution schedule

Batches run in order; a batch starts only when the previous one has fully landed. Stages inside a *parallel* batch are independent and may be built concurrently; a *serial* batch holds one stage. `/feature-implement` follows this table and demotes any batch it cannot verify to serial.

| Batch | Stages | Mode | Why this mode |
| --- | --- | --- | --- |
| 1 | Stage 1, Stage 2 | parallel | **Disjoint files:** `MWConfig` sources and `ConfigCodingTests.swift` vs `scripts/appcast.py` and `scripts/tests/test_appcast.py`. **No symbol or string-keyed dependency:** the config value `"beta"` and the Sparkle channel `"beta"` are separate contracts, and neither stage reads the other's. **No shared registration point:** SwiftPM auto-discovers the new file; no `Package.swift` edit. **Same base state:** both are green on `b64dd98`. **Category exclusions:** neither is scaffolding, a shared-signature change, a migration or a dependency. **Security ordering:** no protection is involved. **No shared test resource:** `swift test` temp directories vs pytest's `tmp_path`, each worktree with its own `.build`/`.dd`. |
| 2 | Stage 3, Stage 4 | parallel | **Disjoint files:** `App/UpdateChannelPolicy.swift`, `AppTests/UpdateChannelPolicyTests.swift`, `App/AppUpdater.swift`, `App/AppDelegate.swift` vs `.github/workflows/build.yml`, `CLAUDE.md`; only Stage 3 regenerates the git-ignored project. **No symbol or string-keyed dependency:** each consumes only batch 1 (Stage 3 `Config.updateChannel`, Stage 4 `--print-channel`), never the other's names. **No shared registration point:** none edited. **Same base state:** both are green against batch 1 alone. **Category exclusions:** Stage 4 is config-only, not an excluded category, and Stage 3 changes no shared signature. **Security ordering:** Stage 4's gates guard the pipeline, which Stage 3 does not touch, and no tag is pushed before every stage lands. **No shared test resource:** only Stage 3 runs xcodebuild. |
| 3 | Stage 5 | serial | consumes `UpdateChannelPolicy.isBeta` (Stage 3) and `Config.updateChannel` (Stage 1) |
| 4 | Stage 6 | serial | consumes Stage 5's `SettingsModel` API (`updateChannel`, `chooseUpdateChannel`, `confirmingBetaChannel`, `isBetaBuild`) |

**Critical path:** Stage 1 → Stage 3 → Stage 5 → Stage 6 (4 of 6 stages).

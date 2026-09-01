# Native Swift macOS rewrite — Implementation Plan v1

**Status:** Draft
**Date:** 2026-09-01
**Design:** [feature-design-v1-Native-Swift-macOS-rewrite.md](./feature-design-v1-Native-Swift-macOS-rewrite.md)

## Overview
Mini Whisper is rebuilt from an empty repository as a Swift package (`Packages/MiniWhisperCore`, twelve modules, one Swift Testing target each) plus a thin xcodegen-generated AppKit/SwiftUI app target, replacing the Python app v0.1.8 (`../mini-whisper`, read-only reference) in place. The plan runs in four phases: (A) scaffold, build system, CI and test conventions; (B) the Core modules bottom-up in dependency order — config, hotkeys, audio, streaming, transcription, usage, history, profiles, paste, then the pipeline — each landed test-first against fakes and the Python repo's ported test cases and fixtures; (C) the app target — shell, event tap and platform adapters, overlay/caption, onboarding, Settings, History — each verified by build plus the `AppTests` bundle and a stated manual check; (D) the signed/notarised release pipeline, cask update and the acceptance checklist from design §5.12. Every design requirement F1–F38 and N1–N6 maps to at least one stage (table below); the module list follows design §5.1/§5.2 exactly, and stage order follows §9's rollout (Core with tests first, then app, then beta, then release).

## Development strategy — Test-Driven Development
Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only | integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests, platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a one-line justification.

### Toolchain, runners and observed baseline (greenfield)
The repository contains no manifests or source today, so the conventions below were **established and proven in the scratchpad on 2026-09-01** (Xcode 26.6 / Swift 6.3.3 / xcodegen 2.46.0, the toolchain design §4 names) and are transcribed here verbatim; Stage 1 lands them in the repo.

| Layer | Command (run from repo root unless noted) | Observed output |
|---|---|---|
| Core package tests | `cd Packages/MiniWhisperCore && swift test` | green: `✔ Test run with 1 test in 1 suite passed after 0.001 seconds.` — red (assertion): `✘ Test parsesDefaultPasteHotkey() recorded an issue at HotkeyComboTests.swift:7:9: Expectation failed: (combo.configString → "") == "shift+cmd_r"` then `✘ Test run with 1 test in 1 suite failed after 0.001 seconds with 1 issue.` — red (missing symbol, test target fails to build): `error: cannot find 'HotkeyCombo' in scope` followed by `error: fatalError` |
| One module's suite | `swift test --filter MWHotkeysTests` | same format, filtered |
| Core package build-only | `cd Packages/MiniWhisperCore && swift build` | `Build complete!`, exit 0 |
| App build-only | `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **`, exit 0 |
| App tests (`AppTests` bundle) | `xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' test` | green: `✔ Test run with 1 test in 1 suite passed` + `** TEST SUCCEEDED **`, exit 0 — red: `✘ Test menuOrderMatchesSource() recorded an issue at MenuOrderTests.swift:6:9: Expectation failed: …` + `** TEST FAILED **`, exit 65 |

Baseline before Stage 1: no command can run in the repo (nothing to build). Scratchpad proof baseline: package 1 test / 1 suite green, app 1 test / 1 suite green, both builds exit 0. Stage 1's definition of done records the repo's own baseline (expected: 12 placeholder suites green, `AppTests` 1 suite green).

Swift Testing output is also prefixed by an XCTest line `Executed 0 tests, with 0 failures` — that is the empty XCTest bundle, not the result; read the `✔/✘ Test run with …` line.

### Test conventions (Stage 1 documents these in `CLAUDE.md`)
- Framework: **Swift Testing** (`import Testing`, `@Suite struct <Type>Tests`, `@Test func …`, `#expect`, `#require`, `.enabled(if:)` traits). No XCTest except where an API forces it (none expected).
- Layout: one test target per module — `Packages/MiniWhisperCore/Tests/<Module>Tests/<Type>Tests.swift` (e.g. `Tests/MWHotkeysTests/HotkeyComboTests.swift`). Fakes and helpers shared across test targets live in the library target `Sources/MWTestSupport` (never in a test target, so all test targets can import it). Fixtures live inside the owning test target under `Fixtures/` and are declared with `resources: [.copy("Fixtures")]`, read via `Bundle.module`. Fixtures shared by several test targets (the three WAV files) live under `Sources/MWTestSupport/Fixtures/` and are exposed through `TestFixtures.wav(_:)`.
- Registration is explicit: every new source or test target is added to `Package.swift` (`targets:` + `products:`); every new App source file under `App/` or `AppTests/` is auto-discovered by xcodegen's folder sources on the next `xcodegen generate`.
- App-only tests: `AppTests/<Type>Tests.swift` in the `AppTests` unit-test bundle hosted by the app (`@testable import MiniWhisper`).
- Integration tests (network, TCC, live Keychain) are opt-in via `.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1")` and, for OpenAI, `OPENAI_API_KEY` in the environment; they are skipped otherwise and never run in the CI unit-test job.
- Build-only checks between stages: `swift build` (package) and the `xcodebuild … build` command above (app target has no tests for most of its code).

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| F1: bundle ID, `LSUIElement`, name, version 0.2.0 | Stage 1, Stage 30 |
| F2: config.json / prompt files, defaults, corrupt backup, `daily_usage` migration, unknown keys | Stage 3 |
| F3: Keychain service/accounts, keys never on disk or in logs | Stage 4, Stage 24 |
| F4: new config keys and defaults, `speech_analyzer` engine value | Stage 3 |
| F5: combo grammar and display format | Stage 5 |
| F6: matching, release, safety net, watchdog incl. modifier-trigger bindings | Stage 6, Stage 24 |
| F7: capture mode | Stage 6, Stage 27 |
| F8: two bindings `paste` / `paste_submit` with defaults | Stage 6, Stage 24 |
| F9: press → `starting` → `recording`, on-sound on first buffer, 100 ms tick | Stage 21, Stage 23, Stage 25 |
| F10: 0.3 s hold vs toggle, toggle cap with off-sound | Stage 21 |
| F11: recording gate (0.5 s / RMS 0.005), seconds billed | Stage 21 |
| F12: streamed vs batch, cleanup when effective, paste, sounds, usage refresh | Stage 20 |
| F13: no OpenAI key rule | Stage 20 |
| F14: HTTP error strings, 3 s overlay error | Stage 15, Stage 20, Stage 25 |
| F15: generation guard at three checkpoints, stale billing | Stage 20, Stage 21 |
| F16: press while recording ignored; mic error | Stage 21 |
| F17: profile and paste target resolved at release from frontmost app | Stage 21, Stage 24 |
| F18: one engine, 1024-frame tap, idle stop, sleep/quit stop, flag-gated capture | Stage 8, Stage 24 |
| F19: configuration-change handling | Stage 8, Stage 21, Stage 24 |
| N1: warm press ≤ 50 ms, overlay ≤ one frame, no polling | Stage 21, Stage 25, Stage 31 |
| N2: 16 kHz WAV via linear interpolation; chunked streaming conversion | Stage 7 |
| F20: five engines, message shapes, 60 s buffer cap, terminal gate, drain | Stage 10, Stage 11, Stage 12, Stage 13 |
| F21: 5 s finish, partial discarded, `captionUnavailable` once | Stage 10, Stage 12, Stage 13, Stage 20 |
| F22: transcript assembly and restart heuristic | Stage 9 |
| F23: engine selection and downgrade rules | Stage 14, Stage 21 |
| F24: SpeechAnalyzer usage, asset install, no Speech TCC prompt | Stage 13 |
| F25: paste sequence, submit key, restore-if-unchanged, AX check | Stage 19, Stage 24 |
| F26: effective cleanup and disabled toggle | Stage 18, Stage 20, Stage 28 |
| F27: profiles model and resolution | Stage 18, Stage 28 |
| F28: vocabulary injection | Stage 18, Stage 20 |
| F29: history append/prune/retention 0, History window actions | Stage 17, Stage 20, Stage 29 |
| F30: paste from History | Stage 29 |
| F31: menu order, row formats, `Last:` click | Stage 23 |
| F32: first-launch model dialog; default engine rule | Stage 14, Stage 26 |
| F33: onboarding parity, in-process Continue | Stage 26 |
| F34: sounds, tick, volume, preview | Stage 23, Stage 27 |
| F35: usage/cost, pricing table + `speech_analyzer: 0.0`, discard billing | Stage 16, Stage 20, Stage 21 |
| F36: single instance | Stage 23 |
| F37: overlay/caption placement | Stage 25 |
| F38: `--debug` file log, INFO redaction | Stage 2, Stage 23 |
| N3: macOS 14, arm64, Swift 6 strict concurrency, no third-party deps | Stage 1 |
| N4: hardened runtime, Developer ID, audio-input entitlement | Stage 1, Stage 30 |
| N5: unit tests per Core component via `swift test` | Stage 1, Stages 2–22 |
| N6: Python app can still read the config | Stage 3 |

## Stages

### Stage 1 — Repository scaffold, build system, CI and test conventions
**Category:** Non-TDD (scaffolding) — creates empty modules, manifests, resources and CI; nothing host-assertable yet beyond "the placeholder suites run".
**Goal:** An empty but complete skeleton: `swift test` runs twelve placeholder suites, `xcodegen generate` + `xcodebuild test` runs `AppTests`, CI does both on `macos-26`.
**Design references:** §5.1, §5.12, §9 step 1, N3, N4, N5 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** create `Packages/MiniWhisperCore/Package.swift`; `Sources/{MWSupport,MWConfig,MWHotkeys,MWAudio,MWStreaming,MWTranscription,MWUsage,MWHistory,MWProfiles,MWPaste,MWOverlaySim,MWPipeline,MWTestSupport}/<Module>.swift` (one `public enum <Module>Module {}` marker each); `Tests/<Module>Tests/<Module>PlaceholderTests.swift` (one `@Suite` with one `@Test` asserting the marker exists) for the twelve modules; `project.yml`; `App/main.swift`, `App/AppDelegate.swift` (empty `NSApplicationDelegate`), `App/Info.plist`, `App/MiniWhisper.entitlements`; `App/Resources/{AppIcon.icns,on.mp3,off.mp3,mini-whisper.png,default_prompt.txt,default_transcribe_prompt.txt}` copied from `../mini-whisper/src/mini_whisper/{assets,resources}/`; `AppTests/AppPlaceholderTests.swift`; `.github/workflows/build.yml`; `.gitignore` (add `*.xcodeproj`); `CLAUDE.md`; `README.md`; `CHANGELOG.md`.

**Steps:**
1. Write `Package.swift` (`swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v6]`): one `.target` per module with the dependency edges of §5.2 (MWConfig→MWSupport; MWAudio→MWSupport; MWStreaming→MWAudio, MWConfig, MWSupport; MWTranscription→MWSupport; MWUsage→MWConfig; MWHistory→MWSupport; MWProfiles→MWConfig; MWPaste→MWSupport; MWOverlaySim→none; MWPipeline→all of the above; MWTestSupport→every module except MWPipeline), one `.testTarget` per module (each depending on its module and `MWTestSupport`), one `.library` product per module. Add the marker file and placeholder suite per module.
2. Run `cd Packages/MiniWhisperCore && swift test` — confirm `✔ Test run with 12 tests in 12 suites passed`.
3. Write `project.yml`: app target `MiniWhisper` (`type: application`, `platform: macOS`, `sources: [App]`, `packages: MiniWhisperCore: {path: Packages/MiniWhisperCore}`, dependencies on the twelve products), settings `PRODUCT_NAME: Mini Whisper`, `PRODUCT_MODULE_NAME: MiniWhisper`, `PRODUCT_BUNDLE_IDENTIFIER: com.ips.mini-whisper`, `MARKETING_VERSION: 0.2.0`, `CURRENT_PROJECT_VERSION: 0.2.0`, `MACOSX_DEPLOYMENT_TARGET: "14.0"`, `SWIFT_VERSION: "6.0"`, `SWIFT_STRICT_CONCURRENCY: complete`, `ENABLE_HARDENED_RUNTIME: YES`, `INFOPLIST_FILE: App/Info.plist`, `CODE_SIGN_ENTITLEMENTS: App/MiniWhisper.entitlements`, `CODE_SIGN_IDENTITY: "-"`, `CODE_SIGN_STYLE: Manual`, `DEVELOPMENT_TEAM: XPRCQRLN7Y`; `scheme: {testTargets: [AppTests]}`; test target `AppTests` (`type: bundle.unit-test`, `sources: [AppTests]`, dependency on `MiniWhisper`, settings `TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Mini Whisper.app/Contents/MacOS/Mini Whisper"`, `BUNDLE_LOADER: "$(TEST_HOST)"`, same signing/Swift settings). `App/Info.plist`: `CFBundleName` Mini Whisper, `CFBundleIdentifier $(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleShortVersionString $(MARKETING_VERSION)`, `CFBundleVersion $(CURRENT_PROJECT_VERSION)`, `LSUIElement true`, `LSMinimumSystemVersion $(MACOSX_DEPLOYMENT_TARGET)`, `CFBundleIconFile AppIcon`, and the four usage strings verbatim from `../mini-whisper/setup.py` (`NSMicrophoneUsageDescription`, `NSAccessibilityUsageDescription`, `NSInputMonitoringUsageDescription`, `NSSpeechRecognitionUsageDescription`). Entitlements: `com.apple.security.device.audio-input` only (design §5.8: no `com.apple.security.automation`).
4. `App/main.swift`: `let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()`. `AppTests/AppPlaceholderTests.swift`: `@Suite struct AppPlaceholderTests { @Test func bundleIdentifier() { #expect(Bundle.main.bundleIdentifier == "com.ips.mini-whisper") } }` — with `@testable import MiniWhisper`.
5. Run `xcodegen generate && xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' test` — confirm `** TEST SUCCEEDED **`.
6. `.github/workflows/build.yml`: `on: push (branches: [main], tags: ['v*'])`, `pull_request`, `workflow_dispatch`; job `unit-tests` on `runs-on: macos-26` — `sudo xcode-select -s /Applications/Xcode_26.6.app`, `brew install xcodegen`, `swift test` (working-directory `Packages/MiniWhisperCore`), `xcodegen generate`, the `xcodebuild … test` command; job `build` (needs `unit-tests`) — `xcodebuild -configuration Release build` with `CODE_SIGNING_ALLOWED=NO`, `brew install create-dmg`, DMG named `MiniWhisper-<version>-arm64.dmg` (version from tag `v*` else `MARKETING_VERSION` grepped from `project.yml`) uploaded as an artifact. Signing, notarisation, release and cask update are Stage 30.
7. `CLAUDE.md`: dev commands (the table above), module map (§5.2 rows), test conventions (section above), "Python repo `../mini-whisper` is read-only reference", bundle-ID rule. `README.md`: install via cask, permissions, privacy section stating history is stored locally under `~/.config/mini-whisper/history.jsonl` for `history_retention_days` (default 7, 0 = nothing written) — design §5.8. `CHANGELOG.md`: `## 0.2.0 (unreleased)` header.

**Definition of done:**
- `swift test` → 12 suites green; `swift build` exit 0; `xcodebuild … build` and `… test` exit 0 — these numbers recorded as the repo baseline in `CLAUDE.md`.
- `*.xcodeproj` ignored; resources present under `App/Resources/`; `Info.plist` carries the four usage strings and `LSUIElement`.
- CI workflow parses (`gh workflow view` after the first push, or `actionlint` locally if installed — optional).

**Risks specific to this stage:** `macos-26` runner image drift (design §7) — pin `xcode-select` to 26.6 and `xcodegen` via Homebrew; if the runner lacks Xcode 26.6 the job fails visibly at the `xcode-select` step.

### Stage 2 — MWSupport and MWTestSupport: clock, logging facade, error mapping
**Goal:** The cross-cutting primitives every later stage injects: `Clock`/`Sleeper` protocols with a deterministic `VirtualClock`, the `Log` facade with categories and the `--debug` file sink (F38), and `AnyError` description mapping used by F14's "other failures → the error's description".
**Design references:** §5.2 (`MWSupport` row, `Log`), §5.11, F38 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `Sources/MWSupport/{Clock.swift,Log.swift,FileLogSink.swift,AnyError.swift}`; `Sources/MWTestSupport/{VirtualClock.swift,CapturingLogSink.swift}`; `Tests/MWSupportTests/{LogTests.swift,AnyErrorTests.swift,VirtualClockTests.swift}`.

**Steps (TDD):**
1. Write test: `Tests/MWSupportTests/VirtualClockTests.swift` → `VirtualClockTests.sleepResumesWhenAdvancedPast`, `.cancelledSleepThrows`, `.nowAdvancesMonotonically` covering `protocol Clock: Sendable { var now: TimeInterval { get }; func sleep(for: Duration) async throws }` and `VirtualClock.advance(by:)`. Expected initial failure: `error: cannot find 'VirtualClock' in scope` (test target fails to build); after scaffolding the empty API, `Expectation failed: (clock.now → 0.0) == 1.5`.
2. Run `swift test --filter MWSupportTests` — confirm the failures above.
3. Implement `Clock`, `SystemClock` (ContinuousClock-backed), `VirtualClock` (actor holding pending continuations keyed by wake time; `advance(by:)` resumes those ≤ now in order).
4. Run — confirm pass. `swift test` — no regressions.
5. Write test: `LogTests.debugFileSinkReceivesDebugLines`, `.infoOnlyWhenDebugOff`, `.categoriesAreNamespaced` covering `Log.configure(debug: Bool, sinks: [LogSink])`, `Log.hotkey.info("…")`, categories `hotkey, audio, stream(engine), pipeline, paste, ui, config` (subsystem `com.ips.mini-whisper`), and a `CapturingLogSink` in MWTestSupport. `AnyErrorTests.descriptionPrefersLocalizedDescription`, `.wrapsNSErrorDomainAndCode`. Expected initial failure: `cannot find 'Log' in scope`, then `Expectation failed: (sink.lines.count → 0) == 1`.
6. Run — confirm fail. Implement `Log` (os.Logger per category plus the sink list), `FileLogSink` (appends `<ISO ts> <LEVEL> <category> <message>\n` to a URL, 0600, created on first write), `AnyError`.
7. Run — confirm pass; `swift test` green.

**Definition of done:**
- `VirtualClock` deterministic and cancellation-safe; `Log` writes DEBUG lines to the file sink only when `debug == true`; nothing in MWSupport imports AppKit.
- Suite count in `swift test` grows by the new tests; `swift build` clean.

**Risks specific to this stage:** None.

### Stage 3 — MWConfig: `Config`, `ConfigStore`, `PromptFiles`
**Goal:** Typed, validated, atomically written `config.json` with the Python defaults, corrupt backup, `daily_usage` migration, unknown-key round-trip, clamping, the new F4 keys, and the two prompt files with bundled defaults (F2, F4, N6).
**Design references:** §5.2 (`ConfigStore`, `PromptFiles`), §5.3, §5.9, F2, F4, N6 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python reference `../mini-whisper/src/mini_whisper/config.py` (`DEFAULT_CONFIG`, `load`, `save`, `_migrate_daily_usage`) and `tests/test_config.py` (cases `test_load_creates_defaults`, `test_load_corrupt_json_backs_up`, `test_load_migrates_daily_usage`, `test_load_migration_drops_stale_daily_usage`, `test_get_prompt_returns_bundled_default`).
**Touches:** `Sources/MWConfig/{Config.swift,ConfigStore.swift,PromptFiles.swift,Profile.swift,SubmitKey.swift,EngineName.swift}`; `Tests/MWConfigTests/{ConfigStoreTests.swift,ConfigCodingTests.swift,PromptFilesTests.swift}`; `Sources/MWTestSupport/TempDirectory.swift`.

**Steps (TDD):**
1. Write test: `Tests/MWConfigTests/ConfigCodingTests.swift` → `decodesPythonDefaultsExactly` (the seven Python keys), `decodesNewKeysWithDefaults` (`history_retention_days` 7, `idle_stop_seconds` 60, `toggle_max_seconds` 300, `vocabulary` [], `profiles` [], `speech_model_prompted` false), `preservesUnknownKeysOnRoundTrip`, `clampsBounds` (retention 0–30, idle 10–600, cap 60–1800), `unknownSubmitKeyBecomesEnter`, `duplicateBundleIDKeepsFirstProfile`, `streamingEngineAbsentIsNil`, `speechAnalyzerIsAValidEngine`, `writesTwoSpaceIndentWithTrailingNewline`, `usageDictionaryRoundTrips`. Expected initial failure: `error: cannot find 'Config' in scope`; after scaffolding, `Expectation failed: (config.historyRetentionDays → 0) == 7`.
2. Run `swift test --filter MWConfigTests` — confirm fail.
3. Implement `Config` (struct, `Codable` via a `JSONValue`-preserving container: known keys typed, `extra: [String: JSONValue]` for unknown), `Profile {id, name, bundleIDs, cleanupEnabled, submitKey, cleanupPrompt?}`, `SubmitKey` (`enter | shift_enter | cmd_enter`), `EngineName` (`speech_analyzer | on_device | openai | elevenlabs | speechmatics`), `Config.validated()` applying the clamps; encoder with `.prettyPrinted, .sortedKeys` and 2-space indent plus trailing `\n` (Python `json.dumps(indent=2)` order is insertion order — the Python reader does not care about key order, N6).
4. Run — confirm pass.
5. Write test: `ConfigStoreTests` → `createsDefaultsOnFirstLoad` (file content equals the Python `DEFAULT_CONFIG` plus the F4 keys), `backsUpCorruptJSONAndRestoresDefaults` (`config.json.bak` exists, warning logged via `CapturingLogSink`), `migratesDailyUsageForToday`, `dropsStaleDailyUsage`, `updateWritesAtomically` (temp file + rename: no partial file observable after a thrown mutation), `changesStreamEmitsAfterUpdate`, `externalEditIsPickedUp` (write the file behind the store; `load()` after the `DispatchSource` event reflects it — use a `FileWatcher` protocol with a fake trigger so the test is deterministic). Expected initial failure: `cannot find 'ConfigStore' in scope`, then `Expectation failed: (FileManager.default.fileExists(atPath: bak) → false) == true`.
6. Run — confirm fail. Implement `actor ConfigStore` (`init(directory:, watcher: FileWatcher = DispatchSourceWatcher())`, `load()`, `update(_:)`, `changes: AsyncStream<Config>`), in-memory cache (§5.9).
7. Run — confirm pass.
8. Write test: `PromptFilesTests` → `copiesBundledDefaultsOnFirstRun` (content equals `App/Resources/default_prompt.txt` — pass the bundled URLs into `PromptFiles.init(directory:bundledCleanup:bundledTranscribe:)`), `readsTrimmedContent`, `writeReplacesContent`. Expected initial failure: `cannot find 'PromptFiles' in scope`.
9. Run — confirm fail. Implement `PromptFiles`. Run — confirm pass; `swift test` green.

**Definition of done:**
- A `config.json` written by this store loads in the Python app unchanged (`python3 -c "import json;json.load(open(...))"` on the test output — N6 check in the test itself: re-decode with `JSONSerialization`, assert the seven Python keys are present with Python types).
- All F2/F4 behaviours covered by named tests; `MWConfig` imports only Foundation + MWSupport.

**Risks specific to this stage:** Unknown-key preservation with `Codable` needs a custom container; keep `JSONValue` small (null/bool/number/string/array/object).

### Stage 4 — MWConfig: `KeychainStore`
**Category:** Hybrid — TDD for the query/attribute logic behind a `SecItemAPI` seam; the live login-keychain path is an *integration-verified remainder* (opt-in test below), because `swift test` must not touch the user's keychain unasked (N5).
**Goal:** `SecretStore` protocol and `KeychainStore` reading/writing/deleting the three generic-password accounts under service `mini-whisper` in the login keychain, with per-account in-memory caching invalidated on save/remove (F3, §5.3, §5.9).
**Design references:** §5.2 (`KeychainStore`), §5.3 Keychain, §5.8, §5.9, F3 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `Sources/MWConfig/{SecretStore.swift,KeychainStore.swift,SecItemAPI.swift}`; `Sources/MWTestSupport/{FakeSecretStore.swift,FakeSecItemAPI.swift}`; `Tests/MWConfigTests/{KeychainStoreTests.swift,KeychainIntegrationTests.swift}`.

**Steps (TDD):**
1. Write test: `KeychainStoreTests` → `readQueryUsesServiceAccountAndLoginKeychain` (attributes: `kSecClass=kSecClassGenericPassword`, `kSecAttrService="mini-whisper"`, `kSecAttrAccount="openai-api-key"`, `kSecReturnData=true`, no `kSecUseDataProtectionKeychain`), `accountNamesMatchPython` (`elevenlabs-api-key`, `speechmatics-api-key`), `setUpdatesWhenPresentAddsWhenAbsent` (`errSecItemNotFound` → `SecItemAdd`), `removeDeletesItem`, `cachesAfterFirstRead` (second `secret(for:)` makes no `SecItemCopyMatching` call), `saveInvalidatesCache`, `valueNeverAppearsInLogs` (`CapturingLogSink` contains no key text after set/get). Expected initial failure: `cannot find 'KeychainStore' in scope`; after scaffolding, `Expectation failed: (fake.copyMatchingCalls.count → 0) == 1`.
2. Run — confirm fail.
3. Implement `protocol SecretStore`, `enum KeyAccount`, `protocol SecItemAPI { copyMatching, add, update, delete }`, `SecItemBridge: SecItemAPI` (real Security calls), `final class KeychainStore: SecretStore` (lock-protected cache), `FakeSecretStore` (dictionary) in MWTestSupport.
4. Run — confirm pass; `swift test` green.
5. Integration-verified remainder: `KeychainIntegrationTests.roundTripThroughLoginKeychain` with `.enabled(if: env["MW_INTEGRATION"] == "1")` writes, reads and deletes account `integration-test-key` under service `mini-whisper` through `SecItemBridge`. Verification command: `MW_INTEGRATION=1 swift test --filter KeychainIntegrationTests` → `✔ Test run with 1 test in 1 suite passed`. Run it once on the author's machine and note the result in the stage's commit message.

**Definition of done:**
- All non-integration tests green with the fake; integration test green when run opt-in; no `kSecUseDataProtectionKeychain` anywhere (`grep -r kSecUseDataProtectionKeychain Packages` returns nothing).

**Risks specific to this stage:** The first read of an item the Python app created may show the system "allow access" dialog (§5.3) — that is expected on the author's machine, not a failure.

### Stage 5 — MWHotkeys: `HotkeyCombo`
**Goal:** Parse, config-string and display-string for hotkey combos, identical to `hotkey.py` (`parse_hotkey`, `build_combo_string`, `format_hotkey`, `_VK_TO_CHAR`) (F5).
**Design references:** §5.2 (`HotkeyCombo`), §5.4 Hotkey events, F5, §5.12 `HotkeyComboTests` of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `../mini-whisper/src/mini_whisper/hotkey.py:19-59` (tables) and `:72-160`; `tests/test_hotkey.py` (13 cases).
**Touches:** `Sources/MWHotkeys/{HotkeyCombo.swift,Modifier.swift,Trigger.swift,VirtualKeyTable.swift}`; `Tests/MWHotkeysTests/HotkeyComboTests.swift`.

**Steps (TDD):**
1. Write test: `HotkeyComboTests` porting the 13 Python cases — `parsesModifierPlusKey` (`cmd+shift+space`), `parsesModifierTrigger` (`shift+cmd_r`), `parsesSingleModifierTrigger` (`cmd_r`), `parsesSingleCharKey` (`cmd+a` → vk 0), `parsesTab`, `noTriggerThrows` (`cmd+shift`), `unknownKeyThrows` (`cmd+foo`), `emptyThrows`, `multipleTriggersThrows` (`cmd_r+shift_r`), `configStringRoundTrips` (parameterised over `shift+cmd_r, cmd_r, cmd+space, cmd+shift+space, ctrl+tab`), `displayStringSymbols` (`⌘⇧Space`), `displayModifierTrigger` (`⇧Right ⌘`), `displaySingleModifierTrigger` (`Right ⌘`), `displayCharKey` (`⌘A`), `modifierDisplayOrderMatchesPython` (sorted by the Python `str(Key)` order: `Key.alt`, `Key.cmd`, `Key.ctrl`, `Key.shift` → `⌥⌘⌃⇧`), `vkTableMatchesPython` (spot-check 0→a, 9→v, 50→`` ` ``, 49 absent). Expected initial failure: `error: cannot find 'HotkeyCombo' in scope`; after scaffolding, `Expectation failed: (combo.configString → "") == "shift+cmd_r"`.
2. Run `swift test --filter MWHotkeysTests` — confirm fail.
3. Implement `Modifier` (`cmd, shift, ctrl, alt`), `Trigger` (`.key(name: "space"|"tab"|"enter")`, `.char(Character, vk: UInt16?)`, `.modifier(SidedModifier)` with `cmd_r 54, shift_r 60, alt_r 61, ctrl_r 62`), `VirtualKeyTable` (the 48-entry table), `HotkeyCombo: Codable, Equatable, Sendable` with `parse`, `configString`, `displayString`, `isModifierTrigger`, `canonicalTrigger`.
4. Run — confirm pass; `swift test` green.

**Definition of done:** The two defaults `shift+cmd_r` / `cmd_r` parse and format as in the Python app; error cases throw `HotkeyParseError` with the Python messages (`Unknown key: foo`, `No trigger key found in combo: …`, `Multiple trigger keys in combo: …`).

**Risks specific to this stage:** None.

### Stage 6 — MWHotkeys: `HotkeyMatcher`
**Goal:** The pure state machine for two named bindings over `KeyEvent`s: exact-set matching for modifier triggers, superset matching for key triggers, release on trigger-up or any binding-modifier-up, safety net, watchdog decisions for all active bindings, and capture mode (F6, F7, F8).
**Design references:** §5.2 (`HotkeyMatcher`), §5.4 Hotkey events, F6, F7, F8, §5.12 `HotkeyMatcherTests` of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `hotkey.py:238-378` (`_handle_press`, `_handle_release`, `_tick_watchdog`, capture handlers).
**Touches:** `Sources/MWHotkeys/{KeyEvent.swift,HotkeyMatcher.swift,HotkeyAction.swift,ModifierFlags.swift}`; `Tests/MWHotkeysTests/HotkeyMatcherTests.swift`.

**Steps (TDD):**
1. Write test: `HotkeyMatcherTests` → `modifierTriggerFiresOnExactSet` (`shift+cmd_r`: shift down, cmd_r down → `.pressed(.paste)`), `modifierTriggerDoesNotFireOnSuperset` (`cmd_r` binding with shift also held → nothing; the `shift+cmd_r` vs `cmd_r` non-collision), `keyTriggerFiresOnSuperset` (`cmd+space` fires with `cmd+shift+space`), `releaseOnTriggerUp`, `releaseOnBindingModifierUp`, `safetyNetReleasesWhenModifiersDropped`, `watchdogReleasesKeyTriggerWhenOSFlagsDrop`, `watchdogReleasesModifierTriggerWhenOSFlagsDrop` (the design's fix over `hotkey.py:286`: `cmd_r` active, `watchdogTick(osFlags: [])` → `.released(.paste_submit)`), `watchdogNoopWhileHeld`, `capturePressNonModifierEndsCapture` (`cmd` held + `a` → `.captured(cmd+a)`), `captureReleasingModifierYieldsModifierTrigger` (shift, cmd_r held; cmd_r up → `.captured(shift+cmd_r)`), `captureBareKeyRejectedAndReenters` (`a` alone → `.captureRejected`, still capturing), `captureEscCancels`, `captureIgnoresBindings` (no `.pressed` during capture), `updateBindingResetsState`. Expected initial failure: `cannot find 'HotkeyMatcher' in scope`; after scaffolding, `Expectation failed: (actions → []) == [.pressed(.paste)]`.
2. Run — confirm fail.
3. Implement `KeyEvent` (`.keyDown(vk:chars:)`, `.keyUp(vk:)`, `.flagsChanged(flags:vk:)`), `ModifierFlags` (masks shift `0x20000`, ctrl `0x40000`, cmd `0x100000`, alt `0x80000`), `BindingName` (`paste`, `pasteSubmit`), `HotkeyAction`, `struct HotkeyMatcher { init(bindings: [BindingName: HotkeyCombo]); mutating handle(_:now:) -> [HotkeyAction]; mutating watchdogTick(osFlags:) -> [HotkeyAction]; mutating beginCapture(); mutating cancelCapture(); mutating update(binding:combo:); var needsWatchdog: Bool }`.
4. Run — confirm pass; `swift test` green.

**Definition of done:** Every F6/F7 rule has a named test; the matcher has no timers, threads or imports beyond Foundation (the 100 ms timer is Stage 24's `GlobalKeyListener`).

**Risks specific to this stage:** Sided-modifier canonicalisation: a `flagsChanged` for vk 54 with cmd flag set is a *press* of `cmd_r`, with the flag cleared a *release* — encode this in `KeyEvent` conversion tests here, not in the App.

### Stage 7 — MWAudio: `PCMConverter` and `WAVEncoder`
**Goal:** Stateful chunked float32→int16 linear-interpolation resampler equal to `audio_convert.py`, and 16 kHz mono int16 WAV encoding equal to `recorder.stop()` (N2).
**Design references:** §5.2 (`PCMConverter`, `WAVEncoder`), N2, §5.12 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `streaming/audio_convert.py`, `recorder.py:_resample`, `tests/test_audio_convert.py` (8 cases).
**Touches:** `Sources/MWAudio/{PCMConverter.swift,WAVEncoder.swift}`; `Tests/MWAudioTests/{PCMConverterTests.swift,WAVEncoderTests.swift}`; `Sources/MWTestSupport/SignalFixtures.swift` (sine/ramp generators).

**Steps (TDD):**
1. Write test: `PCMConverterTests` → `singleCallMatchesBatch48kTo24k`, `chunkedMatchesBatch48kTo24k`, `chunkedMatchesBatch44_1kTo16k`, `oddChunkSizesCarryState` (parameterised over `(48000,16000,1024)`, `(44100,24000,333)`, `(48000,24000,1)`), `outputIsInt16LE`, `clipsToFullScale`, `sameRatePassthrough`, `emptyChunkIsNoop`; the batch reference is a Swift port of `np.interp` on the whole signal. Expected initial failure: `cannot find 'PCMConverter' in scope`; after scaffolding, `Expectation failed: (chunked → 0 bytes) == batch (32000 bytes)`.
2. Run `swift test --filter MWAudioTests` — confirm fail.
3. Implement `struct PCMConverter { init(from:to:); mutating convert(_ samples: [Float]) -> Data }` (ratio, `nextOut`, `totalIn`, tail — same state as the Python).
4. Run — confirm pass.
5. Write test: `WAVEncoderTests` → `headerFieldsFor16kMono16bit` (RIFF/WAVE, fmt chunk 16, PCM 1, channels 1, rate 16000, byteRate 32000, blockAlign 2, bits 16, data size), `sampleCountAfterResample` (1 s at 48 kHz → 16000 samples), `emptyInputYieldsHeaderOnly`. Expected initial failure: `cannot find 'WAVEncoder' in scope`.
6. Run — confirm fail. Implement `enum WAVEncoder { static func encode(samples:sampleRate:) -> Data }` using `PCMConverter`. Run — confirm pass; `swift test` green.

**Definition of done:** Chunked and whole-buffer conversions are byte-identical for every parameterised split; WAV header validated field by field.

**Risks specific to this stage:** None.

### Stage 8 — MWAudio: `AudioCaptureEngine`
**Category:** Hybrid — full TDD for the actor's lifecycle/state against a fake backend; the `AVAudioEngineBackend` adapter is a *platform-only remainder* verified by `swift build` plus an opt-in live test.
**Goal:** The single-engine, idle-stop capture lifecycle: `ensureRunning`, flag-gated `beginCapture`, listener attachment, `endCapture → Recording {wav, duration, meanRMS}`, `.live` on the first buffer, idle-stop scheduling via `Clock`, configuration-change and sleep handling, `stop()` (F18, F19).
**Design references:** §5.2 (`AudioCaptureEngine`), §5.5 Warm/Cold press, Idle stop, §5.7 rows 1–4, §5.9, F18, F19 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `Sources/MWAudio/{AudioBackend.swift,AudioCapture.swift,AudioCaptureEngine.swift,AudioEvent.swift,Recording.swift,BufferListener.swift,AVAudioEngineBackend.swift}`; `Sources/MWTestSupport/{FakeAudioBackend.swift,PCMBufferFactory.swift}`; `Tests/MWAudioTests/{AudioCaptureEngineTests.swift,AVAudioEngineBackendIntegrationTests.swift}`.

**Steps (TDD):**
1. Write test: `AudioCaptureEngineTests` → `ensureRunningStartsBackendOnce`, `beginCaptureFlipsFlagWithoutRestart`, `firstBufferEmitsLiveOnce`, `buffersBeforeBeginCaptureAreDropped`, `endCaptureReturnsWavDurationAndMeanRMS` (three 1024-frame buffers at 48 kHz of known RMS → duration 0.064 s, mean RMS, WAV length 2048 bytes + 44), `listenerReceivesBuffersSynchronously` (attached after two buffers → receives only later ones), `idleStopFiresAfterDurationOnVirtualClock` (`scheduleIdleStop(after: .seconds(60))`, `advance(59)` no stop, `advance(1)` → backend stopped + `.stopped` event), `cancelIdleStopPreventsStop`, `beginCaptureCancelsPendingIdleStop`, `configurationChangeDuringCaptureEmitsDeviceChangedAndEndsCapture`, `configurationChangeWhileIdleMarksStoppedSoNextEnsureRunningRestarts`, `sleepStopsImmediately`, `startFailureThrowsBackendError` (→ F16's `Mic error: <reason>` upstream), `tapUses1024FramesAtInputFormat`. Expected initial failure: `cannot find 'AudioCaptureEngine' in scope`; after scaffolding, `Expectation failed: (backend.startCount → 0) == 1`.
2. Run — confirm fail.
3. Implement `protocol AudioBackend: Sendable { func start() throws; func stop(); func installTap(bufferSize: UInt32, handler: @Sendable (AVAudioPCMBuffer) -> Void); var inputFormat: AVAudioFormat; var events: AsyncStream<AudioBackendEvent> }` (`.configurationChanged`, `.systemWillSleep`); `protocol BufferListener: AnyObject, Sendable { func feed(_ buffer: AVAudioPCMBuffer) }` (called on the tap thread, no isolation hop); `actor AudioCaptureEngine` with `ensureRunning()`, `beginCapture()`, `attachListener(_:)`, `endCapture()`, `scheduleIdleStop(after:)`, `cancelIdleStop()`, `stop()`, `events: AsyncStream<AudioEvent>`; `protocol AudioCapture` declaring that same API with `AudioCaptureEngine: AudioCapture` (the pipeline's seam); per-buffer work on the tap thread limited to: flag check, copy samples into a `[Float]`, RMS, forward to listener (capture state guarded by an `OSAllocatedUnfairLock`, never the actor); `FakeAudioBackend` with `deliver(buffer)` / `emit(event)`.
4. Run — confirm pass; `swift test` green.
5. Platform-only remainder: `AVAudioEngineBackend` (AVAudioEngine, tap on bus 0 at `inputNode.inputFormat(forBus: 0)` with 1024 frames, `AVAudioEngineConfigurationChange` and `NSWorkspace.willSleepNotification` observers). Build check: `swift build` exit 0. Live check (opt-in): `AVAudioEngineBackendIntegrationTests.deliversABufferWithinOneSecond` with `.enabled(if: env["MW_INTEGRATION"] == "1")` — command `MW_INTEGRATION=1 swift test --filter AVAudioEngineBackendIntegrationTests` (prompts Terminal for Microphone once).

**Definition of done:**
- All lifecycle rules from F18/F19 and §5.7 rows 1–4 have named tests on the fake; `swift build` clean; the live test passes once on the author's machine.
- No `Task`/actor hop between the tap callback and the listener (documented in a comment; verified by reading the tap closure).

**Risks specific to this stage:** Swift 6 strict concurrency around `AVAudioPCMBuffer` (not `Sendable`) — the listener is invoked synchronously on the tap thread so no `Sendable` crossing is needed; if the compiler still objects, wrap the tap handler in a `@unchecked Sendable` box (design §7 mitigation).

### Stage 9 — MWStreaming: seam types and `TranscriptAssembler`
**Goal:** The engine seam (`StreamingEngine`, `TranscriptSink`, `StreamResult`, `EngineName` reuse) and the compound-transcript assembler with the segment-restart heuristic (F22, F20 interface).
**Design references:** §5.2 (`TranscriptAssembler`, `StreamingEngine` protocol), F22, §5.12 `TranscriptAssemblerTests` of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `streaming/base.py`, `tests/test_streaming_base.py` (9 `CompoundTranscript` cases + 3 `StreamResult` cases).
**Touches:** `Sources/MWStreaming/{StreamingEngine.swift,TranscriptSink.swift,StreamResult.swift,TranscriptAssembler.swift}`; `Sources/MWTestSupport/RecordingSink.swift`; `Tests/MWStreamingTests/TranscriptAssemblerTests.swift`.

**Steps (TDD):**
1. Write test: `TranscriptAssemblerTests` → `partialReplacesPreviousPartial`, `finalAppendsAndClearsPartial`, `multipleFinalsJoined`, `partialRestartKeepsEarlierSentence` (`Hello there my friend.` → `So` → `So what happens next`), `partialRevisionDoesNotDuplicate`, `partialBacktrackDoesNotDuplicate`, `emptyFinalKeepsLivePartial`, `emptyCompound`, `whitespaceSegmentsSkipped`, `restartHeuristicIsCaseInsensitive`; `StreamResultTests.defaults` (`text ""`, `ok false`, usage zeros), `.usageNotShared`. Expected initial failure: `cannot find 'TranscriptAssembler' in scope`; after scaffolding, `Expectation failed: (assembler.text → "") == "hello wor"`.
2. Run `swift test --filter MWStreamingTests` — confirm fail.
3. Implement `struct TranscriptAssembler` (`addPartial`, `addFinal`, `text`, private `isSegmentRestart(old:new:)` — casefold, prefix either way, first-word equality, word-count decrease), `StreamResult {text, ok, usage: StreamUsage{inputTokens, outputTokens, seconds}}`, `protocol TranscriptSink: AnyObject, Sendable { onPartial, onFinal, onEngineError }`, `protocol StreamingEngine: AnyObject, Sendable { var name: EngineName; func start(sink:); func feed(_: AVAudioPCMBuffer); func finish(timeout: Duration) async -> StreamResult }`, `RecordingSink` in MWTestSupport.
4. Run — confirm pass; `swift test` green.

**Definition of done:** All Python `CompoundTranscript` cases ported verbatim; the seam protocols compile under strict concurrency.

**Risks specific to this stage:** None.

### Stage 10 — MWStreaming: `WebSocketEngine` and the fixture replayer
**Goal:** The generic cloud engine skeleton: injectable `WebSocketConnection`, buffer-until-open with the 60 s cap, send/receive tasks, end-of-audio gate, drain window, single-shot failure, 5 s finish timeout, usage accounting (F20, F21).
**Design references:** §5.2 (`WebSocketEngine`, `EngineAdapter`), §5.4 wire protocols (skeleton behaviour), §5.7 rows 5–7, F20, F21, §5.12 `WebSocketEngineTests` of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `streaming/websocket_engine.py:1-255` and `tests/test_websocket_engines.py` (`FakeSocket`, cases 169–260).
**Touches:** `Sources/MWStreaming/{WebSocketConnection.swift,URLSessionWebSocketConnection.swift,EngineAdapter.swift,WebSocketEngine.swift}`; `Sources/MWTestSupport/{FakeWebSocketConnection.swift,FixtureScript.swift,TestAdapter.swift}`; `Tests/MWStreamingTests/WebSocketEngineTests.swift`; `Tests/MWStreamingTests/Fixtures/streaming/{openai_realtime,elevenlabs,speechmatics}.json` copied from `../mini-whisper/tests/fixtures/streaming/` (registered via `resources: [.copy("Fixtures")]` on `MWStreamingTests` in `Package.swift`).

**Steps (TDD):**
1. Write test: `WebSocketEngineTests` (using a minimal `TestAdapter` and `FakeWebSocketConnection` that replays `steps` of `{"await_client": type}` / `{"server": {...}}` / `{"server_error": msg}`) → `feedBeforeOpenBuffersAndFlushesOnOpen`, `preconnectBufferCappedAt60sThenFails` (61 s of 48 kHz buffers before open → `onEngineError` once, `finish` returns `ok == false` fast), `connectFailureReportsErrorOnceAndFinishFailsFast`, `socketErrorReportsErrorOnce`, `finishTimeoutReturnsNotOk` (`VirtualClock`, no terminal event → after 5 s `ok == false`, text `""`), `terminalBeforeEndOfAudioDoesNotComplete` (server "completed" before the client's end message is on the wire → not done; after the end message → done), `drainScoopsTrailingEvents` (adapter `drainAfterComplete = 0.2` → an event 0.1 s after terminal is still applied), `noDrainWhenZero`, `usageSecondsEqualFedSeconds`, `chunksAreConvertedToTargetRate` (24 kHz adapter receives `PCMConverter` output). Expected initial failure: `cannot find 'WebSocketEngine' in scope`; after scaffolding, `Expectation failed: (sink.errors.count → 0) == 1`.
2. Run — confirm fail.
3. Implement `protocol WebSocketConnection { func send(_: WebSocketMessage) async throws; func receive() async throws -> WebSocketMessage; func close() }` (`.text(String) | .binary(Data)`), `URLSessionWebSocketConnection` (ephemeral `URLSession`, headers from the adapter), `protocol EngineAdapter { name, url, headers, targetRate, drainAfterComplete, openMessages(), encodeChunk(Data) -> WebSocketMessage, endMessages(), mutating handle(_: WebSocketMessage, emit: inout AdapterEmitter) throws -> Bool }`, `final class WebSocketEngine<Adapter>: StreamingEngine` (lock-protected queue + `Task`s; `feed` copies samples on the tap thread and enqueues; converter state keyed by input rate).
4. Run — confirm pass; `swift test` green.

**Definition of done:** All ten behaviours named; the three fixture files present under the test target and loadable via `Bundle.module` (used fully in Stage 11).

**Risks specific to this stage:** Timing-sensitive tests must use `VirtualClock` for the 5 s finish and the drain window — no real sleeps in `swift test`.

### Stage 11 — MWStreaming: OpenAI, ElevenLabs and Speechmatics adapters
**Goal:** The three `EngineAdapter`s with the exact message shapes pinned in design §5.4, fixture-driven happy paths, token usage and error mapping (F20).
**Design references:** §5.4 Streaming wire protocols, §5.2 adapter row, F20, §5.12 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `websocket_engine.py:255-434`, `tests/test_websocket_engines.py` cases 260–380.
**Touches:** `Sources/MWStreaming/Adapters/{OpenAIRealtimeAdapter.swift,ElevenLabsAdapter.swift,SpeechmaticsAdapter.swift}`; `Tests/MWStreamingTests/CloudAdapterTests.swift`.

**Steps (TDD):**
1. Write test: `CloudAdapterTests` → `openAIHappyPathFixture` (partials `hello`, `hello world`; finals `hello world`, `again`; usage 12/4; terminal only after commit), `openAISessionUpdateShape` (exact JSON: `session.type = transcription`, `audio.input.format = {type: audio/pcm, rate: 24000}`, model `gpt-live-transcribe`, `turn_detection.type = server_vad`), `openAIChunkAndCommitShapes`, `openAIErrorEventFails`, `elevenLabsHappyPathFixture`, `elevenLabsMessageShapes` (`message_type input_audio_chunk`, `commit false/true`, `sample_rate 16000`, URL query `model_id=scribe_v2_realtime&audio_format=pcm_16000`, header `xi-api-key`), `elevenLabsInputErrorFails`, `speechmaticsHappyPathFixture`, `speechmaticsMessageShapes` (StartRecognition JSON, binary chunks counted, `EndOfStream.last_seq_no == chunks sent`), `speechmaticsErrorFails`, `speechmaticsIgnoresBinaryServerFrames`, `drainConfig` (OpenAI/ElevenLabs 0.2 s, Speechmatics 0). Expected initial failure: `cannot find 'OpenAIRealtimeAdapter' in scope`; after scaffolding, `Expectation failed: (sent.first?.json["type"] → nil) == "session.update"`.
2. Run — confirm fail.
3. Implement the three adapters (JSON via `JSONSerialization`/`Codable`; base64 chunks; Speechmatics sequence counter).
4. Run — confirm pass; `swift test` green.

**Definition of done:** Each adapter's open/chunk/end messages match §5.4 byte-for-byte in the assertions; fixtures replay green.

**Risks specific to this stage:** Provider drift (design §7) — pinned to 2026-09-01; failures degrade to batch by Stage 20.

### Stage 12 — MWStreaming: `SFSpeechEngine` and `SpeechPermission`
**Category:** Hybrid — TDD behind a `SpeechRecognitionAPI` seam (the Python `_SpeechAPI` pattern); the real `SFSpeechRecognizer` adapter is a *platform-only remainder* with an opt-in live test.
**Goal:** On-device recognition engine: pre-start buffer queue, `endAudio` + wait, partial/final callbacks, failure once, finish timeout, seconds usage; permission status/request helper (F20, F21, F23 permission flow).
**Design references:** §5.2 (`SFSpeechEngine`), §4 (no one-minute limit on-device), §5.7 row 8, F20, F21 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `streaming/on_device.py`, `tests/test_on_device.py` (10 cases).
**Touches:** `Sources/MWStreaming/{SpeechRecognitionAPI.swift,SFSpeechEngine.swift,SpeechPermission.swift,SFSpeechRecognitionBridge.swift}`; `Sources/MWTestSupport/{FakeSpeechRecognitionAPI.swift,TestFixtures.swift,Fixtures/wav/{filler_words,self_corrections,filler_and_corrections}.wav}` (WAVs copied from `../mini-whisper/tests/fixtures/wav/`; `resources: [.copy("Fixtures")]` on `MWTestSupport` in `Package.swift`); `Tests/MWStreamingTests/{SFSpeechEngineTests.swift,SFSpeechLiveTests.swift}`.

**Steps (TDD):**
1. Write test: `SFSpeechEngineTests` → `permissionStatusMapsAllFourValues` (notDetermined→undetermined, denied/restricted→denied, authorized), `requestOnlyWhenUndetermined`, `feedForwardsBuffersToRequest`, `feedBeforeStartBuffersAndFlushesOnStart`, `partialAndFinalDriveSinkAndAssembler`, `finishEndsAudioAndReturnsCompoundText`, `finishTimesOutWithoutFinal` (`VirtualClock`), `recogniserErrorFailsEngineOnce`, `unavailableAtStartFailsEngine`, `usageReportsSecondsAndZeroTokens`, `requestSetsOnDeviceAndPartialResults`. Expected initial failure: `cannot find 'SFSpeechEngine' in scope`; after scaffolding, `Expectation failed: (fake.appended.count → 0) == 2`.
2. Run — confirm fail.
3. Implement `protocol SpeechRecognitionAPI { authorizationStatus; requestAuthorization; startTask(onResult:) throws -> RecognitionRequestHandle }`, `SFSpeechRecognitionBridge` (real), `final class SFSpeechEngine: StreamingEngine`, `enum SpeechPermission`.
4. Run — confirm pass; `swift test` green.
5. Platform-only remainder: `SFSpeechLiveTests.transcribesFixtureWavOnDevice` (`.enabled(if: MW_INTEGRATION == "1")`, feeds `TestFixtures.wav("filler_words")` through `SFSpeechRecognitionBridge`, asserts non-empty text). Verification: `swift build` exit 0; `MW_INTEGRATION=1 swift test --filter SFSpeechLiveTests` (prompts for Speech Recognition once).

**Definition of done:** All ten Python cases ported; no `Speech` import outside the bridge file.

**Risks specific to this stage:** None beyond the design's Swift 6 concurrency risk (callbacks arrive on a private queue; the bridge forwards plain `String`/`Bool` values).

### Stage 13 — MWStreaming: `SpeechAnalyzerEngine` and `SpeechModelAssets`
**Category:** Hybrid — TDD behind a `SpeechAnalyzerAPI` seam; the `@available(macOS 26, *)` adapter is a *platform-only remainder* verified by `swift build` on the 26.5 SDK and an opt-in live test on macOS 26.
**Goal:** SpeechAnalyzer engine (volatile → partial, final → final, `finalizeAndFinish`, 5 s finish) and asset status/install helper (F24, F20, F21).
**Design references:** §5.2 (`SpeechAnalyzerEngine`, `SpeechModelAssets`), §4 SpeechAnalyzer symbols (corrected: `AVAudioConverter` into `bestAvailableAudioFormat`, `AnalyzerInput(buffer:)`), §5.7 row 9, F24 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `Sources/MWStreaming/{SpeechAnalyzerAPI.swift,SpeechAnalyzerEngine.swift,SpeechModelAssets.swift,SpeechAnalyzerBridge.swift}`; `Sources/MWTestSupport/FakeSpeechAnalyzerAPI.swift`; `Tests/MWStreamingTests/{SpeechAnalyzerEngineTests.swift,SpeechAnalyzerLiveTests.swift}`.

**Steps (TDD):**
1. Write test: `SpeechAnalyzerEngineTests` → `volatileResultIsPartial`, `finalResultIsFinal`, `feedConvertsToAnalyzerFormatAndYields` (fake converter records input/output formats), `finishFinalizesThroughLastInputAndReturnsText`, `finishTimeoutReturnsNotOk`, `analyzerErrorFailsOnce`, `usageSeconds`; `SpeechModelAssetsTests` → `unavailableBelow26OrWhenTranscriberUnavailable`, `notInstalledWhenRequestNonNil`, `installedWhenRequestNil`, `installingReportsProgress`, `unsupportedLocaleIsUnavailable`. Expected initial failure: `cannot find 'SpeechAnalyzerEngine' in scope`; after scaffolding, `Expectation failed: (sink.partials → []) == ["hel"]`.
2. Run — confirm fail.
3. Implement `protocol SpeechAnalyzerAPI` (`isAvailable`, `supportedLocale(equivalentTo:)`, `installationRequest()`, `bestAudioFormat()`, `makeSession(locale:) -> AnalyzerSession` with `feed(AVAudioPCMBuffer)`, `results: AsyncStream<(text, isFinal)>`, `finish()`), `SpeechAnalyzerBridge` (`@available(macOS 26, *)`: `SpeechTranscriber(locale:transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])`, `SpeechAnalyzer(modules:)`, `AVAudioConverter` to `bestAvailableAudioFormat(compatibleWith:)`, `AsyncStream<AnalyzerInput>` fed with `AnalyzerInput(buffer:)`, `analyzeSequence`, `finalizeAndFinish(through:)`; `AssetInventory.assetInstallationRequest(supporting:)` + `downloadAndInstall()` + `progress`), `SpeechAnalyzerEngine: StreamingEngine`, `enum SpeechModelAssets { status() async -> AssetStatus; install() async throws }`.
4. Run — confirm pass; `swift test` green; `swift build` exit 0 (the bridge compiles only under `#available`/`@available` guards with deployment target 14).
5. Platform-only remainder: `SpeechAnalyzerLiveTests.transcribesFixtureWav` (feeds `TestFixtures.wav("filler_words")`; `.enabled(if: MW_INTEGRATION == "1" && ProcessInfo.processInfo.isOperatingSystemAtLeast(26))`, skips when assets are not installed). Command: `MW_INTEGRATION=1 swift test --filter SpeechAnalyzerLiveTests`.

**Definition of done:** Engine logic fully tested on the fake; live test green on the author's macOS 26 machine after installing assets via the Stage 26 dialog (record in Stage 31's checklist).

**Risks specific to this stage:** SpeechAnalyzer behaviour differences (design §7) — every failure path returns `ok == false` so Stage 20 falls back to batch.

### Stage 14 — MWStreaming: `EngineFactory`
**Goal:** Engine selection and downgrade rules at press time, the default-engine rule, and the per-run notices (F23, F32 default rule).
**Design references:** §5.2 (`EngineFactory`), §5.7 rows 8–10, F23, F32 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `streaming/factory.py`, `tests/test_factory.py` (8 cases).
**Touches:** `Sources/MWStreaming/{EngineFactory.swift,EngineSelection.swift,PlatformInfo.swift,EngineProvider.swift}`; `Sources/MWTestSupport/{FakePlatformInfo.swift,FakeEngineProvider.swift}`; `Tests/MWStreamingTests/EngineFactoryTests.swift`.

**Steps (TDD):**
1. Write test: `EngineFactoryTests` → `disabledReturnsNoEngineForEveryName`, `onDeviceAuthorizedReturnsSFEngine`, `onDeviceDeniedReturnsNoneWithPointerNoticeOncePerRun` (second call → no notice), `onDeviceUndeterminedRequestsOnceAndBatchesThisTime`, `cloudEngineWithKeyReturnsWebSocketEngine` (parameterised over the three), `cloudEngineWithoutKeyDowngradesToOnDeviceDefaultWithNoticeOncePerRun` (`Live transcript: ElevenLabs key missing — using on-device`), `openAIUsesOpenAIKeyAccount`, `unknownEngineNameIsNoEngine`, `speechAnalyzerBelow26UsesSF`, `speechAnalyzerAssetsNotInstalledUsesSF`, `speechAnalyzerUnsupportedLocaleUsesSF`, `speechAnalyzerInstalledUsesAnalyzer`, `absentEngineDefaultsToAnalyzerOn26WhenInstalledElseOnDevice`, `presentEngineValueIsHonoured`. Expected initial failure: `cannot find 'EngineFactory' in scope`; after scaffolding, `Expectation failed: (selection.engine?.name → nil) == .onDevice`.
2. Run — confirm fail.
3. Implement `struct PlatformInfo { osMajor; locale }`, `protocol EngineProvider { func make(config:secrets:) async -> EngineSelection }`, `struct EngineSelection { engine: (any StreamingEngine)?; notice: EngineNotice? }` (`.speechPermissionPointer`, `.cloudKeyMissing(EngineName)`), `struct EngineFactory: EngineProvider` (`init(platform:, speech: SpeechRecognitionAPI, analyzer: SpeechAnalyzerAPI, connectionFactory:)`, once-per-run flags), `static func defaultEngine(platform:assetsInstalled:) -> EngineName`.
4. Run — confirm pass; `swift test` green.

**Definition of done:** Every F23 rule and the F32 default rule has a named test; the factory performs no I/O beyond the injected seams.

**Risks specific to this stage:** None.

### Stage 15 — MWTranscription: `OpenAIClient` and `APIError`
**Goal:** Batch transcription and cleanup over `URLSession` with the exact request shapes, timeouts, ephemeral configuration, usage extraction and F14 status mapping; opt-in integration test on the WAV fixtures.
**Design references:** §5.2 (`OpenAIClient`), §5.4 OpenAI HTTP, §5.8 Network, F12 (models/timeouts), F14 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `transcriber.py`, `cleaner.py`, `tests/test_transcriber.py` (6), `tests/test_cleaner.py` (5), `tests/test_integration.py` gating.
**Touches:** `Sources/MWTranscription/{HTTPTransport.swift,OpenAIClient.swift,APIError.swift,Multipart.swift}`; `Sources/MWTestSupport/{FakeHTTPTransport.swift,FakeTranscriber.swift,FakeCleaner.swift}`; `Tests/MWTranscriptionTests/{OpenAIClientTests.swift,APIErrorTests.swift,OpenAIIntegrationTests.swift}`.

**Steps (TDD):**
1. Write test: `OpenAIClientTests` → `transcribeBuildsMultipartWithFileModelAndFormat` (parts `file` = `audio.wav` `audio/wav`, `model=gpt-4o-mini-transcribe`, `response_format=json`), `transcribeIncludesInstructionsWhenNonEmpty`, `transcribeOmitsInstructionsWhenEmpty`, `transcribeParsesTextAndUsage`, `transcribeMissingUsageIsZero`, `transcribeEmptyWavThrows`, `transcribeTimeoutIs30s`, `cleanSendsSystemPromptAndUserText` (`model gpt-4o-mini`, `temperature 0.3`), `cleanTrimsContent`, `cleanUsesPromptAndCompletionTokens`, `cleanTimeoutIs15s`, `sessionIsEphemeral` (transport records `URLSessionConfiguration.ephemeral` semantics: no cookie storage, no URL cache), `authorizationHeaderNotLogged`; `APIErrorTests` → `401InvalidKeyMessage`, `429RateLimitedMessage`, `otherStatusMessage` (`API error (503).`), `transportErrorUsesDescription`. Expected initial failure: `cannot find 'OpenAIClient' in scope`; after scaffolding, `Expectation failed: (request.parts.map(\.name) → []) == ["file", "model", "response_format"]`.
2. Run `swift test --filter MWTranscriptionTests` — confirm fail.
3. Implement `protocol HTTPTransport { func send(_: URLRequest, timeout: Duration) async throws -> (Data, HTTPURLResponse) }`, `URLSessionTransport` (ephemeral), `Multipart` builder, `protocol Transcriber`, `protocol Cleaner`, `struct OpenAIClient: Transcriber, Cleaner`, `enum APIError: Error { httpStatus(Int), transport(any Error), emptyAudio }` with `userMessage`.
4. Run — confirm pass; `swift test` green.
5. Integration (opt-in): `OpenAIIntegrationTests.transcribesAndCleansEachFixture` (`.enabled(if: MW_INTEGRATION == "1" && OPENAI_API_KEY set)`) asserts non-empty text from both calls for the three WAVs from `TestFixtures.wav(_:)`. Command: `MW_INTEGRATION=1 OPENAI_API_KEY=… swift test --filter OpenAIIntegrationTests`.

**Definition of done:** Request shapes asserted field by field; F14 strings exact; no key text in logs (`CapturingLogSink` assertion).

**Risks specific to this stage:** None.

### Stage 16 — MWUsage: `Pricing` and `UsageStore`
**Goal:** Rate tables (with `speech_analyzer: 0.0`), overrides, `dictationCost`, row formatting, per-day accumulation, month prune, totals (F35).
**Design references:** §5.2 (`Pricing`, `UsageStore`), F35, §5.12 `PricingTests`/`UsageStoreTests` of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `pricing.py`, `config.py:add_usage/usage_totals`, `tests/test_pricing.py` (14), `tests/test_config.py` (usage cases 58–144).
**Touches:** `Sources/MWUsage/{Pricing.swift,UsageStore.swift,ProviderUsage.swift,DayEntry.swift}`; `Sources/MWTestSupport/FakeUsageStore.swift`; `Tests/MWUsageTests/{PricingTests.swift,UsageStoreTests.swift}`.

**Steps (TDD):**
1. Write test: `PricingTests` → `perMinuteRates` (parameterised: openai→`openai_realtime` 0.017, elevenlabs 0.0065, speechmatics 0.0067, on_device 0, speech_analyzer 0), `noEngineNoMinuteCost`, `tokenCostTranscribe`, `tokenCostCombinedModels`, `streamedPlusTokenCost`, `overridePerMinute`, `overridePerMTok`, `overrideLeavesOthers`, `roundedToSixDecimals`, `formatUsageRows` (`Today: 1.2k/340 tok · 3m · $0.12`, `Month: $1.50`), `formatSmallValues`, `formatZero`, `partialMinutesFloor`. Expected initial failure: `cannot find 'Pricing' in scope`; after scaffolding, `Expectation failed: (cost → 0.0) == 0.017`.
2. Run — confirm fail. Implement `enum Pricing` (tables, `rate(_:key:overrides:)`, `dictationCost(engine:seconds:tokensByModel:overrides:)`, `formatUsageRows(today:monthCost:)`). Run — confirm pass.
3. Write test: `UsageStoreTests` (on a `ConfigStore` in a temp dir) → `addAccumulatesIntoToday`, `addDefaultsMissingFields`, `addPrunesPreviousMonthKeepsCurrent`, `totalsSumMonth`, `totalsEmpty`, `concurrentAddsSerialise` (20 parallel adds → exact sum). Expected initial failure: `cannot find 'UsageStore' in scope`.
4. Run — confirm fail. Implement `struct ProviderUsage`, `struct DayEntry`, `actor UsageStore { init(config: ConfigStore, today: () -> Date); add(_:) async throws -> DayEntry; totals() async -> (today, monthCost) }`, `protocol UsageRecording` (for the pipeline), `FakeUsageStore`. Run — confirm pass; `swift test` green.

**Definition of done:** All 14 pricing cases plus the new rate; usage cases ported; month prune on write.

**Risks specific to this stage:** None.

### Stage 17 — MWHistory: `HistoryStore`
**Goal:** JSONL history with append/read/delete/clear/prune/search, retention 0 semantics, corrupt-line tolerance, 0600 mode (F29).
**Design references:** §5.2 (`HistoryStore`), §5.3 history.jsonl, §5.7 rows 15–16, §5.8, F29 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `Sources/MWHistory/{HistoryEntry.swift,HistoryStore.swift}`; `Sources/MWTestSupport/FakeHistoryStore.swift`; `Tests/MWHistoryTests/HistoryStoreTests.swift`.

**Steps (TDD):**
1. Write test: `HistoryStoreTests` → `appendWritesOneJSONLineWithAllFields` (`id, ts (ISO-8601 Z), text, app_name, bundle_id, engine (null for batch), streamed_seconds, cost_usd`), `fileModeIs0600`, `entriesLoadNewestLast`, `deleteRewritesWithoutEntry`, `clearRemovesAllLinesKeepsFile`, `pruneDropsEntriesOlderThanRetention` (7 days, injected `now`), `pruneRunsAfterAppend`, `retentionZeroDeletesFileAndDisablesWrites`, `retentionChangeFromZeroReenablesWrites`, `searchIsCaseInsensitiveSubstring`, `corruptLineIsSkippedLoggedAndDroppedOnNextPrune`. Expected initial failure: `cannot find 'HistoryStore' in scope`; after scaffolding, `Expectation failed: (lines.count → 0) == 1`.
2. Run — confirm fail.
3. Implement `struct HistoryEntry: Codable`, `actor HistoryStore { init(url:, retention: @escaping () -> Int, now: @escaping () -> Date); append; entries; delete(id:); clear; prune; search }`, `protocol HistoryRecording`, `FakeHistoryStore`.
4. Run — confirm pass; `swift test` green.

**Definition of done:** Every F29 storage rule named; nothing outside `~/.config/mini-whisper/history.jsonl` (path injected).

**Risks specific to this stage:** None.

### Stage 18 — MWProfiles: `ProfileResolver`, `PromptComposer`, effective cleanup
**Goal:** Profile lookup (first match, implicit Default), vocabulary injection into both prompts, and the effective-cleanup rule (F26, F27, F28).
**Design references:** §5.2 (`ProfileResolver`, `PromptComposer`), §5.3 profiles, F26, F27, F28 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `Sources/MWProfiles/{ResolvedProfile.swift,ProfileResolver.swift,PromptComposer.swift,EffectiveCleanup.swift}`; `Tests/MWProfilesTests/{ProfileResolverTests.swift,PromptComposerTests.swift}`.

**Steps (TDD):**
1. Write test: `ProfileResolverTests` → `firstProfileContainingBundleIDWins`, `noMatchYieldsImplicitDefault` (top-level `cleanup_enabled`, prompt from `prompt.txt`, submit Enter), `nilBundleIDYieldsDefault`, `profileNullPromptFallsBackToPromptTxt`; `PromptComposerTests` → `emptyVocabularyLeavesPromptsUnchanged`, `vocabularyAppendsToTranscribeInstructions` (`\n\nVocabulary (spell exactly as written): a, b, c`), `vocabularyAppendsToCleanupPrompt` (`\n\nPreserve these terms exactly as written: a, b, c`), `effectiveCleanupRequiresAllThree` (parameterised truth table over global flag, key present, profile flag). Expected initial failure: `cannot find 'ProfileResolver' in scope`; after scaffolding, `Expectation failed: (resolved.name → "") == "Terminal"`.
2. Run — confirm fail.
3. Implement `struct ResolvedProfile { name, cleanupEnabled, submitKey, cleanupPrompt: String, isDefault }`, `struct ProfileResolver { init(config: Config, defaultPrompt: () throws -> String) }`, `struct PromptComposer`, `enum EffectiveCleanup { static func isOn(config:hasOpenAIKey:profile:) -> Bool }`.
4. Run — confirm pass; `swift test` green.

**Definition of done:** All rules named; pure functions only.

**Risks specific to this stage:** None.

### Stage 19 — MWPaste: `Paster`
**Goal:** Snapshot/write/⌘V/submit-key/restore-if-unchanged paste through injected `KeyPoster`, `PasteboardAccess`, `AccessibilityCheck`, `ProcessCheck` and `Clock` (F25, §5.7 rows 12–14).
**Design references:** §5.2 (`Paster`), §5.7 rows 12–14, §5.8, F25 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `paster.py` (vk 9 = V, 36 = Enter, `kCGEventFlagMaskCommand`).
**Touches:** `Sources/MWPaste/{Paster.swift,KeyPoster.swift,PasteboardAccess.swift,SubmitKeyCodes.swift,PasteError.swift}`; `Sources/MWTestSupport/{FakeKeyPoster.swift,FakePasteboard.swift,FakePaster.swift}`; `Tests/MWPasteTests/PasterTests.swift`.

**Steps (TDD):**
1. Write test: `PasterTests` → `postsCmdVDownUpToTargetPid` (vk 9 with command flag, down then up, pid 4242), `submitEnterPosted150msLater` (vk 36, no flags), `submitShiftEnterFlags`, `submitCmdEnterFlags`, `noSubmitWhenNil`, `restoresSnapshotAfter300msWhenUnchanged`, `doesNotRestoreWhenChangeCountMoved`, `restoreTimingCountsFromLastSyntheticEvent`, `accessibilityUntrustedThrowsAndPostsNothing` (`PasteError.accessibilityLost` → message `Accessibility permission lost — re-enable in System Settings`), `deadPidThrowsTargetGone` (`Target app is no longer running`) and restores the snapshot, `writesAllSnapshotItemsAndTypesBack`. Expected initial failure: `cannot find 'Paster' in scope`; after scaffolding, `Expectation failed: (poster.events → []) == [.down(9, cmd), .up(9, cmd)]`.
2. Run — confirm fail.
3. Implement `protocol KeyPoster { func post(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool, pid: pid_t) }`, `protocol PasteboardAccess { snapshot() -> PasteboardSnapshot; write(String) -> Int; var changeCount: Int; restore(PasteboardSnapshot) }`, `protocol AccessibilityCheck`, `protocol ProcessCheck { isRunning(pid) }`, `struct Paster { paste(_ text:, into pid:, submit: SubmitKey?) async throws }`, `protocol Pasting`, `FakePaster`.
4. Run — confirm pass; `swift test` green.

**Definition of done:** All F25 rules named; the 50 ms pre-⌘V delay from the source is replaced by the write-then-post sequence (synchronous pasteboard write, no sleep) — recorded in the test `postsImmediatelyAfterWrite`.

**Risks specific to this stage:** Clipboard restore before a slow target reads it (design §7) — the 300 ms window and change-count check are the mitigation; acceptance in Stage 31 covers Electron and native apps.

### Stage 20 — MWPipeline: `StreamSink` and `ProcessingJob`
**Goal:** The processing half of the state machine as an isolated async unit: the controller's transcript sink (assembly, caption events, `captionUnavailable` once, failed flag) and the job that turns a stopped recording into a delivered dictation — streamed-vs-batch, no-key rule, effective cleanup, staleness at three checkpoints with stale billing, error mapping, paste routing, history append only on delivery, usage refresh (F12, F13, F14, F15, F21, F26, F28, F29, F35).
**Design references:** §5.2 (`DictationController` responsibilities split), §5.5 Processing job (corrected order: stale check → bill → paste → history), §5.7 rows 6–7, 11, 12, F12–F15, F21, F26, F28, F29, F35 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `controller.py:186-320`, `tests/test_controller.py` (cases `test_process_*`, `test_generation_guard_*`, `test_streamed_*`, `test_mid_stream_error_*`, `test_finish_not_ok_*`, `test_empty_compound_*`, `test_cleanup_failure_*`, `test_stale_generation_*`, `test_usage_*`).
**Touches:** `Sources/MWPipeline/{UIEvent.swift,StreamSink.swift,ProcessingJob.swift,ProcessingInput.swift,PasteTarget.swift,Dependencies.swift,SoundPlaying.swift}`; `Sources/MWTestSupport/{FakeStreamingEngine.swift,FakeSoundPlayer.swift,UIEventRecorder.swift}`; `Tests/MWPipelineTests/{StreamSinkTests.swift,ProcessingJobTests.swift}`.

**Steps (TDD):**
1. Write test: `StreamSinkTests` → `partialEmitsCaptionWithFullCompoundText`, `finalEmitsCaption`, `engineErrorSetsFailedAndEmitsUnavailableOnce`, `markUnavailableIsIdempotent`, `eventsAfterFailureAreIgnored`. Expected initial failure: `cannot find 'StreamSink' in scope`; after scaffolding, `Expectation failed: (events → []) == [.caption(text: "hel", partial: true, dimmed: false)]`.
2. Run — confirm fail. Implement `enum UIEvent` (§5.4 list), `final class StreamSink: TranscriptSink` (lock, `TranscriptAssembler`, `emit: @Sendable (UIEvent) -> Void`). Run — confirm pass.
3. Write test: `ProcessingJobTests` (fakes for `Transcriber`, `Cleaner`, `Pasting`, `SecretStore`, `UsageRecording`, `HistoryRecording`, `SoundPlaying`, `FakeStreamingEngine`, `isStale: () -> Bool` closure) → `streamedTranscriptUsedWhenOkNonEmptyAndNotFailed` (no transcriber call), `finishNotOkFallsBackToBatch` (+ `captionUnavailable`), `emptyCompoundFallsBackToBatch`, `sinkFailedFallsBackToBatch`, `noKeyWithStreamedTextPastesRawWithoutCleanup`, `noKeyWithoutStreamedTextEmitsNoAPIKeyError` (`No API key configured`, stream discarded, seconds billed), `emptyBatchTextPlaysOffHidesPastesNothing` (seconds billed), `cleanupRunsWhenEffective`, `cleanupSkippedWhenIneffective`, `vocabularyReachesBothPrompts`, `staleBeforeBatchStopsAndBillsSecondsOnly`, `staleBeforeCleanupStopsAndBillsSecondsOnly`, `staleBeforePasteStopsAndBillsSecondsOnly`, `deliveredDictationBillsTokensAndSecondsAndAppendsHistory`, `historyEntryFieldsMatchTarget` (app name, bundle ID, engine, seconds, cost), `pasteFailureEmitsErrorNoHistory`, `submitKeyOnlyForPasteSubmitBinding`, `http401Message`, `http429Message`, `otherHTTPMessage`, `genericErrorUsesDescription`, `errorsPlayOffSound`, `usageEventCarriesFormattedRows`, `finishTimeoutIs5s`. Expected initial failure: `cannot find 'ProcessingJob' in scope`; after scaffolding, `Expectation failed: (paster.pasted → []) == ["hello world"]`.
4. Run — confirm fail. Implement `struct ProcessingInput { recording, engine, sink, profile, target: PasteTarget, binding, vocabulary }`, `struct Dependencies` (all protocol-typed) with `protocol SoundPlaying { playOn(); playOff(); playTick() }`, `struct ProcessingJob { func run(_: ProcessingInput, isStale: @Sendable () -> Bool, emit: @Sendable (UIEvent) -> Void) async }` with the corrected §5.5 order (finish → choose text → stale? → key rule → batch (stale check first) → cleanup (stale check first) → stale check → bill → paste → history → off → `.result` → `.usage`).
5. Run — confirm pass; `swift test` green.

**Definition of done:** Every F12–F15 branch and each Python `_process` test has a Swift counterpart; the job never touches audio, hotkeys or timers.

**Risks specific to this stage:** None beyond fake fidelity — `FakeStreamingEngine.finish` must honour the injected `VirtualClock` for the timeout test.

### Stage 21 — MWPipeline: `DictationController`
**Goal:** The main-actor state machine: press/release, `starting`/`recording`/`level` events, tick at 100 ms, hold vs toggle, toggle cap, ignore-while-recording, mic error, recording gate with discard billing, engine selection and notices at press, listener attachment, target capture at release, idle-stop scheduling, device change during capture, `abort()` (F9, F10, F11, F15 generation, F16, F17, F18/F19 calls, F23, N1 no polling).
**Design references:** §5.2 (`DictationController`), §5.5 Warm/Cold press, Release, Toggle stop, Idle stop, §5.7 rows 1–4, 10–11, 13, F9–F11, F15–F19, F23, N1, §5.12 `DictationControllerTests` of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `controller.py:101-185`, `tests/test_controller.py` (`test_streamed_press_installs_listener_and_starts_engine`, `test_release_emits_dimmed_caption`, `test_gated_recording_discards_stream_and_records_seconds`, `test_toggle_mode_streams_identically`, `test_abort_stream_finishes_and_discards`, `test_permission_denied_pointer_once_per_run`).
**Touches:** `Sources/MWPipeline/{DictationController.swift,FrontmostAppProviding.swift,ControllerState.swift}`; `Sources/MWTestSupport/{FakeAudioCapture.swift,FakeFrontmostApp.swift,FakeEngineProvider.swift}`; `Tests/MWPipelineTests/DictationControllerTests.swift`.

**Steps (TDD):**
1. Write test: `DictationControllerTests` (`VirtualClock`, `FakeAudioCapture` implementing Stage 8's `AudioCapture`, `FakeEngineProvider`, `UIEventRecorder`) → `pressEmitsStartingBeforeAnyAwait` (first event is `.starting` synchronously), `pressCancelsIdleStopAndBeginsCapture`, `firstBufferEmitsRecordingAndPlaysOn`, `tickPlaysWhenNotLiveWithin100ms` (advance 100 ms before `.live` → tick; then `.live` → on-sound still plays), `noTickWhenLiveBefore100ms`, `levelEventPerBuffer`, `engineSelectedAtPressAndListenerAttachedAfterStart`, `engineNoticeEmittedAsCaptionNotice`, `speechPointerEmittedAsError`, `releaseUnder300msArmsToggle`, `secondPressWhileToggleArmedStops`, `releaseOver300msStopsAndProcesses`, `toggleCapStopsWithOffSoundAtToggleMaxSeconds`, `pressWhileRecordingWithoutToggleIgnored`, `micStartFailureEmitsMicErrorAndSchedulesNoIdleStop`, `gateShortRecordingDiscardsBillsSecondsOffHides`, `gateQuietRecordingDiscards`, `releaseCapturesFrontmostAppAndResolvesProfile`, `releaseEmitsProcessingAndDimmedCaption`, `generationIncrementsPerRelease`, `newPressDuringProcessingMakesJobStale`, `idleStopScheduledFromProcessingTerminus` (rescheduled when the job ends), `idleStopUsesConfiguredSeconds`, `deviceChangedDuringCaptureEndsWithErrorAndBillsSeconds`, `deviceChangedWhileIdleIsIgnoredByController`, `abortFinishesEngineWith500msBillsAndStopsAudio`, `noPollingTimers` (the fake clock records no periodic sleeps — only the tick, cap and idle-stop one-shots). Expected initial failure: `cannot find 'DictationController' in scope`; after scaffolding, `Expectation failed: (events.first → nil) == .starting`.
2. Run — confirm fail.
3. Implement `protocol FrontmostAppProviding { func frontmost() -> PasteTarget? }`, `@MainActor final class DictationController { init(deps:, config: ConfigStore, clock:); hotkeyPressed(_:); hotkeyReleased(_:); abort() async; uiEvents: AsyncStream<UIEvent> }` composing `ProcessingJob`.
4. Run — confirm pass; `swift test` green.

**Definition of done:**
- Every rule in F9–F11, F15–F19, F23 and §5.7 rows 1–4, 10–11, 13 has a named test; the controller uses `Clock` one-shots only (N1: no polling).
- `swift build` clean under strict concurrency.

**Risks specific to this stage:** Ordering of `.starting` relative to the first `await` is what makes N1 achievable — the test `pressEmitsStartingBeforeAnyAwait` guards it; keep `hotkeyPressed` synchronous up to the emit.

### Stage 22 — MWOverlaySim: `ConstellationSimulation` and `CaptionModel`
**Goal:** Deterministic physics and choreography reproducing `overlay.py` numerically plus the accepted Breathing choreography, and the pure caption line model, both host-tested without AppKit (§5.6, F14 overlay error timing, N1 no per-frame allocation as a design property).
**Design references:** §5.6, §5.2 (`ConstellationSimulation`), §5.12 `ConstellationSimulationTests`, §4 accepted mockups of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `overlay.py:11-60` (constants), `:66-95` (seeding), `:302-400` (`_tick`), `:403-441` (caption functions), `tests/test_caption_bar.py` (7 cases).
**Touches:** `Sources/MWOverlaySim/{Constants.swift,SeededRandom.swift,ConstellationSimulation.swift,Frame.swift,OverlayMode.swift,CaptionModel.swift}`; `Tests/MWOverlaySimTests/{ConstellationSimulationTests.swift,CaptionModelTests.swift}`.

**Steps (TDD):**
1. Write test: `ConstellationSimulationTests` (injected `SeededRandom`) → `seeds24DotsTenOnRingWithinJitter` (ring radius 100 ± 10, angular slot ± 15 %), `remaining14InsideDisc`, `dotRadiiBetween2And5`, `showPlacesDotsAtCentreWithZeroVelocity`, `showFadesCardIn120ms`, `startingHomesBreathe` (ring 30 ± 6 with period 1 s), `recordingConvergesToSeededHomesWithoutAudio` (after 3 s, every dot within 10 pt ambient orbit of home), `audioLevelMapping` (rms 0.005 → 0, 0.06 → 1, attack 0.6 / decay 0.08 one-pole), `audioDisplacementScales130`, `processingRotatesHomesAt3RadPerSecond`, `resultCollapsesToCentreThenFadesOut` (260 ms then alpha 1→0 over 120 ms), `errorShakeProfileAndDuration` (`6·sin(60t)·(1 − t/0.45)`, 0.45 s), `errorHidesAfter3s`, `linksUnder120ptWithAlphaFormula`, `maxLinksIs276`, `dtClampedTo50msNoNaN` (feed dt = 5 s), `labelStrings` (`starting…`, `"%.1fs"`, `processing...`), `reduceMotionSkipsSpringFromCentreAndShake`, `frameHasFixedCapacity` (arrays never grow after `show()`). Expected initial failure: `cannot find 'ConstellationSimulation' in scope`; after scaffolding, `Expectation failed: (frame.dots.count → 0) == 24`.
2. Run — confirm fail. Implement `SeededRandom` (SplitMix64 + Box–Muller gaussian), `Constants` (every value from `overlay.py` and §5.6), `struct Frame` (fixed-capacity `dots: [DotState]`, `links: [Link]`, `linkCount`, `cardAlpha`, `offsetX`, `label`, `errorText`), `enum OverlayMode`, `struct ConstellationSimulation { init(rng:, reduceMotion:); mutating show(); mutating set(mode:); mutating step(dt:level:) -> Frame }`.
3. Run — confirm pass.
4. Write test: `CaptionModelTests` (measure closure = 7 pt per character) → `wrapsAgainst448ptUsableWidth`, `keepsOnlyLastSevenLines`, `olderLinesDimCurrentBright` (0.45 / 0.92), `dimmedUsesProcessingAlphas` (0.40 / 0.65), `unavailableKeepsTranscribedText`, `unavailableAloneWhenNothingTranscribed`, `unavailableNotAppendedTwice`. Expected initial failure: `cannot find 'CaptionModel' in scope`.
5. Run — confirm fail. Implement `struct CaptionModel { static func lines(text:dimmed:measure:) -> [CaptionLine]; static func withUnavailable(_:) }`. Run — confirm pass; `swift test` green.

**Definition of done:** Constants match `overlay.py` value for value (listed in a table in `Constants.swift` comments); simulation deterministic under a seed; no AppKit import in MWOverlaySim.

**Risks specific to this stage:** Numerical parity is checked by property tests (convergence, bounds), not by pixel comparison — the visual acceptance is Stage 31.

### Stage 23 — App shell: lifecycle, single instance, permissions, sounds, logging, status item
**Category:** Platform-only / UI wiring — AppKit lifecycle code; the testable slices (`MenuModel` order/labels, `Last:` truncation, `SoundPlayer` volume scaling via a fake `NSSound` seam) are covered in `AppTests`; the rest is verified by build and a manual launch.
**Goal:** A launchable menu-bar app: `AppDelegate` composition root skeleton, `SingleInstanceGuard` (F36), `PermissionMonitor` (mic + AX checks), `SoundPlayer` (F34), `Log` wiring with `--debug` (F38), `StatusItemController` with the F31 menu (rows, `Last:` insertion, `History…`, About, Quit teardown order).
**Design references:** §5.2 (`StatusItemController`, `AppDelegate`, `SingleInstanceGuard`, `PermissionMonitor`, `SoundPlayer`, `Log`), §5.5 Launch, §5.7 rows 17, 20, F31, F34, F36, F38 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `app.py` (menu, `_copy_last`, `_about`, `_quit`), `sounds.py`, `onboarding.py:check_*`.
**Touches:** `App/{AppDelegate.swift,SingleInstanceGuard.swift,PermissionMonitor.swift,SoundPlayer.swift,MenuModel.swift,StatusItemController.swift,AboutPanel.swift,LaunchArguments.swift}`; `AppTests/{MenuModelTests.swift,SoundPlayerTests.swift}`.

**Steps (hybrid — TDD for the testable slices):**
1. Write test: `AppTests/MenuModelTests.swift` → `initialOrder` (`Today: …`, `Month: …`, separator, `History…`, `Settings…`, separator, `About Mini Whisper`, `Quit`), `lastRowInsertedAfterMonthOnFirstResult`, `lastRowTruncatesAt50WithEllipsis`, `usageRowsUseFormatUsageRows`; `SoundPlayerTests` → `volumeClampedAndApplied`, `tickUsesSystemSoundTink`, `playStopsBeforeReplay`. Expected initial failure: `error: cannot find 'MenuModel' in scope` (AppTests fails to build); after scaffolding, `Expectation failed: (model.items.map(\.title) → []) == […]`.
2. Run `xcodegen generate && xcodebuild … test` — confirm fail (`** TEST FAILED **`).
3. Implement `MenuModel` (pure), `StatusItemController` (`NSStatusItem` with `mini-whisper.png` template image, menu built from `MenuModel`, `Last:` click → pasteboard copy + on-sound), `SoundPlayer: SoundPlaying` (`NSSound` for `on.mp3`/`off.mp3` preloaded, `NSSound(named: "Tink")`, volume), `SingleInstanceGuard` (`NSRunningApplication.runningApplications(withBundleIdentifier:)` excluding self → `activate` + `exit(0)` before any window), `PermissionMonitor` (`AVCaptureDevice.authorizationStatus(for: .audio)`, `AXIsProcessTrusted()`), `LaunchArguments` (`--debug` → `Log.configure(debug: true, sinks: [FileLogSink("/tmp/mini-whisper.log")])`), `AppDelegate.applicationDidFinishLaunching` (guard → permissions → placeholder branch for onboarding (Stage 26) → status item; controller wiring comes in Stage 24), About alert with the version from `CFBundleShortVersionString` and the Python message text.
4. Run — confirm `** TEST SUCCEEDED **`; `swift test` unaffected.
5. Manual check: launch the built app (`open ".dd/Build/Products/Debug/Mini Whisper.app"` or from Xcode); menu shows the F31 order; launching a second copy activates the first and exits; `--debug` creates `/tmp/mini-whisper.log`.

**Definition of done:** AppTests green; manual checklist items above ticked; Quit tears down in the source's order (settings close → controller abort → panels → listener → audio stop).

**Risks specific to this stage:** None.

### Stage 24 — App: `GlobalKeyListener`, platform adapters, composition root → first end-to-end dictation
**Category:** Platform-only / UI wiring — CGEventTap, NSWorkspace, CGEvent posting and NSPasteboard adapters cannot run under the host runner; verified by build and a stated manual check. The `KeyEvent` conversion from `CGEvent` fields is a pure function tested in `AppTests`.
**Goal:** Hotkeys work and a batch dictation pastes text: `GlobalKeyListener` (event tap thread, 100 ms watchdog while any binding is active, tap re-enable, AX-loss error once), the adapters (`AVAudioEngineBackend` from Stage 8, `CGEventKeyPoster`, `NSPasteboardAccess`, `AXTrustCheck`, `NSWorkspaceFrontmostApp`, `KeychainStore`), and `AppDelegate` wiring `DictationController` with real dependencies and the two bindings from config (F3, F6, F8, F17, F18, F19, F25 adapters).
**Design references:** §5.2 (`GlobalKeyListener`, App adapters), §5.5 Launch, §5.7 row 13 (tap disabled), §5.9, F6, F8, F17, F18, F25 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `App/{GlobalKeyListener.swift,CGEventConversion.swift,CGEventKeyPoster.swift,NSPasteboardAccess.swift,AXTrustCheck.swift,NSWorkspaceFrontmostApp.swift,AppDelegate.swift (edit),UIEventRouter.swift}`; `AppTests/CGEventConversionTests.swift`.

**Steps (hybrid):**
1. Write test: `AppTests/CGEventConversionTests.swift` → `keyDownCarriesVKAndChars`, `flagsChangedForVK54WithCmdSetIsPress`, `flagsChangedForVK54WithCmdClearIsRelease`, `flagsMaskToModifierFlags`. Expected initial failure: `cannot find 'CGEventConversion' in scope`; after scaffolding, `Expectation failed: (event → nil) == .flagsChanged(flags: [.cmd], vk: 54)`.
2. Run `xcodebuild … test` — confirm fail. Implement `CGEventConversion` (pure). Run — confirm pass.
3. Implement `GlobalKeyListener: KeyEventSource` (dedicated `Thread` with `CFRunLoop`, `CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, .listenOnly, keyDown|keyUp|flagsChanged)`, `HotkeyMatcher` guarded by a lock, `DispatchSourceTimer` 100 ms while `matcher.needsWatchdog`, `kCGEventTapDisabledByTimeout/UserInput` → `CGEvent.tapEnable`, AX untrusted → one `.error` via the router; actions delivered to the main actor), the adapters, `UIEventRouter` (main-actor fan-out of `uiEvents` to status item now, panels in Stage 25), and the `AppDelegate` wiring: `ConfigStore(directory: ~/.config/mini-whisper)`, `KeychainStore`, `AudioCaptureEngine(backend: AVAudioEngineBackend())`, `EngineFactory`, `OpenAIClient`, `UsageStore`, `HistoryStore`, `Paster`, `DictationController`, bindings `paste` ← `hotkey`, `paste_submit` ← `submit_hotkey`, config `changes` → matcher `update(binding:)`.
4. Build check: `xcodebuild … build` → `** BUILD SUCCEEDED **`; `xcodebuild … test` green.
5. Manual check (concrete): with Microphone and Accessibility granted and an OpenAI key in the Keychain from the Python app, hold `shift+cmd_r`, speak, release → text pastes into TextEdit; `cmd_r` variant pastes and presses Enter; `--debug` log shows `press→live` and `transcribe` timings; the Keychain read may show the one-time allow dialog (design §5.3).

**Definition of done:** First end-to-end batch dictation works on the author's machine; both bindings honoured; the event tap recovers after being disabled (verified by `sudo killall -STOP` of the app for 3 s then `-CONT` and pressing the hotkey).

**Risks specific to this stage:** TCC continuity for the unsigned Debug build differs from the Developer ID build — this stage grants TCC to the Debug bundle once; the drop-in TCC claim is verified only in Stage 31 with the notarised build.

### Stage 25 — App: overlay and caption panels
**Category:** Platform-only / UI wiring — panels, `CALayer` drawing and display link; `AppTests` hosts the 600-frame render smoke test and the placement resolver test; visual parity is a manual check.
**Goal:** `OverlayPanelController` and `CaptionPanelController` rendering `ConstellationSimulation` frames at the display refresh rate with no per-frame allocation, caption layers with cursor blink and line animation, and placement on the display holding the frontmost app's focused window (F9 visuals, F14 error display, F37, N1 one-frame show, §5.6).
**Design references:** §5.6, §5.2 (`OverlayPanelController`, `CaptionPanelController`), §5.9 Overlay, F37, N1 of feature-design-v1-Native-Swift-macOS-rewrite.md; accepted mockups `mockups/mockup-v1-overlay-breathing.html`.
**Touches:** `App/Overlay/{OverlayPanel.swift,ConstellationLayer.swift,OverlayPanelController.swift,CaptionPanelController.swift,CaptionLayerStack.swift,DisplayPlacement.swift,DisplayLinkDriver.swift}`; `App/UIEventRouter.swift` (edit); `AppTests/{ConstellationLayerRenderTests.swift,DisplayPlacementTests.swift}`.

**Steps (hybrid):**
1. Write test: `AppTests/ConstellationLayerRenderTests.swift` → `renders600ScriptedFramesWithoutError` (offscreen `CGContext` 300×300, scripted simulation through starting → recording → processing → result), `frameBufferIsReusedAcrossDraws` (the layer's `Frame` storage identity unchanged); `DisplayPlacementTests` → `prefersScreenContainingFocusedWindowCentre`, `fallsBackToMouseScreen`, `fallsBackToMainScreen` (injected AX/mouse/screen providers). Expected initial failure: `cannot find 'ConstellationLayer' in scope`; after scaffolding, `Expectation failed: (drawn → 0) == 600`.
2. Run `xcodebuild … test` — confirm fail.
3. Implement panels per §5.6 (`NSPanel` borderless non-activating, floating, clear, no shadow, ignores mouse, all-spaces/full-screen-auxiliary/stationary, `hidesOnDeactivate = false`), `ConstellationLayer: CALayer` (`draw(in:)` from a preallocated `Frame`, implicit animations disabled, `contentsScale` per screen), `DisplayLinkDriver` (`NSView.displayLink(target:selector:)`, `dt = min(elapsed, 0.05)`), `CaptionLayerStack` (7 `CATextLayer`s, cursor layer with 0.9 s step keyframe opacity, last-line 8→0 translate + alpha over 120 ms, wrap via `NSAttributedString.size()` fed into `CaptionModel`), `DisplayPlacement` (AX focused window → mouse screen → `NSScreen.main`; recomputed on every show; card 300×300 centred, caption at `card.minX − 90`, `card.minY − 14 − 180`), reduce-motion flag from `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`; router maps `.starting/.recording/.level/.caption/.captionUnavailable/.captionNotice/.processing/.result/.error/.idle` to the panels; panels built off-screen at launch (§5.5 Launch).
4. Run — confirm `** TEST SUCCEEDED **`; build clean.
5. Manual check: press the hotkey — card appears within one frame in the Breathing ring, expands on first buffer, reacts to voice, rotates while processing, collapses and fades on result; error text shakes then shows for 3 s; caption shows partials with a blinking cursor (on-device engine); with a second monitor, both panels appear on the display holding the focused window. Allocation check once with Instruments' Allocations template during 10 s of recording — result (no growth per frame) recorded in this stage's commit message and Stage 31's acceptance notes.

**Definition of done:** Smoke and placement tests green; manual checklist ticked; Instruments note recorded.

**Risks specific to this stage:** `CATextLayer` animations and the display link on multiple displays — keep the caption redraw on text change only (design §5.9).

### Stage 26 — App: onboarding, first-run Settings prompt, speech-model dialog
**Category:** Platform-only / UI wiring — window and alert code; the state logic (`OnboardingModel` step advance, `ModelPromptRule`) is tested in `AppTests`.
**Goal:** Parity onboarding wizard (F33) with in-process Continue, first-run Settings auto-open when no OpenAI key, and the F32 model download dialog.
**Design references:** §5.2 (`OnboardingWindowController`), §5.5 Launch, §5.7 row 20, F32, F33 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `onboarding.py` (labels, deep links, 1.5 s poll, unclosable, request order), `app.py:_start_normal` (first-run prompt after 1 s).
**Touches:** `App/Onboarding/{OnboardingModel.swift,OnboardingWindowController.swift,SpeechModelPrompt.swift}`; `App/AppDelegate.swift` (edit); `AppTests/{OnboardingModelTests.swift,SpeechModelPromptTests.swift}`.

**Steps (hybrid):**
1. Write test: `OnboardingModelTests` → `stepsAreMicrophoneThenAccessibility`, `advancesPastGrantedSteps`, `requestsOnlyCurrentStep`, `continueEnabledWhenAllGranted`, `statusLabelTexts` (`Please grant Microphone access.`, `All permissions granted!`), `deepLinks` (the two `x-apple.systempreferences:` URLs); `SpeechModelPromptTests` → `promptsOnlyOn26WhenAvailableNotInstalledAndNotPrompted`, `eitherChoiceSetsPromptedTrue`, `downloadTriggersInstall`. Expected initial failure: `cannot find 'OnboardingModel' in scope`.
2. Run `xcodebuild … test` — confirm fail. Implement the models. Run — confirm pass.
3. Implement `OnboardingWindowController` (460×275, title `Mini Whisper — Setup`, titles/labels/descriptions/SF symbols exactly as `onboarding.py`, `windowShouldClose` → false, 1.5 s `Timer` poll, `Open Settings` buttons, Continue → in-process `startNormal()`), `SpeechModelPrompt` (`NSAlert` `Download the on-device speech model?` Download / Not now → `SpeechModelAssets.install()`; `speech_model_prompted = true`), `AppDelegate` branch: permissions missing → onboarding (activation policy regular while shown) else normal start; after normal start: no OpenAI key → open Settings after 1 s (Settings arrives in Stage 27; until then log only); then the model prompt when the rule fires.
4. Build clean; `xcodebuild … test` green.
5. Manual check: revoke Accessibility in System Settings, relaunch → wizard appears, cannot be closed, advances as grants are made, Continue starts hotkeys without relaunch; on macOS 26 with assets absent the model dialog appears once.

**Definition of done:** Models tested; manual checklist ticked; `speech_model_prompted` persisted.

**Risks specific to this stage:** None.

### Stage 27 — App: Settings window I — General, Hotkeys, Keys, Sound, and the gating view-model
**Category:** Platform-only / UI wiring — SwiftUI views; `SettingsModel` (gating, masking, validation messages, hotkey capture application) is tested in `AppTests`.
**Goal:** The sidebar Settings window per the accepted mockup for the four simpler sections, with invalid states unrepresentable (F7 capture UI, F26 toggle gating groundwork, F34 preview, §5.4 Settings).
**Design references:** §5.4 Settings window, §5.2 (`SettingsWindowController`), §5.10 Keys footnote, F7, F26, F34 of feature-design-v1-Native-Swift-macOS-rewrite.md; accepted mockup `mockups/mockup-v1-settings-sidebar.html`; Python `settings.py` (messages `Enter a new API key to save.`, `Invalid key — must start with 'sk-'.`, capture flow `_start_capture/_on_capture/_cancel_capture`).
**Touches:** `App/Settings/{SettingsModel.swift,SettingsWindowController.swift,SettingsView.swift,GeneralSection.swift,HotkeysSection.swift,KeysSection.swift,SoundSection.swift,HotkeyCaptureField.swift}`; `App/AppDelegate.swift` (edit: open on first run and from the menu); `AppTests/SettingsModelTests.swift`.

**Steps (hybrid):**
1. Write test: `SettingsModelTests` → `cloudEngineRowsDisabledWithoutKeyWithReason`, `speechAnalyzerRowOnlyOn26`, `speechAnalyzerRowStates` (Download model… / progress / Installed), `cleanupToggleDisabledAndShownOffWithoutKeyButStoredValuePreserved`, `openAIKeyMaskedAsSkPrefixAndLast4`, `otherKeysMaskedAsDots`, `saveKeyValidationMessages`, `hotkeyCaptureAppliesAndSavesOnMainActor`, `hotkeyCaptureRejectsBareKeyAndReenters`, `hotkeyCaptureEscRestoresPreviousDisplay`, `idleStopStepperRange10sTo10min`, `toggleCapStepperRange1To30min`, `volumeSliderPreviewsOnOnRelease`. Expected initial failure: `cannot find 'SettingsModel' in scope`.
2. Run `xcodebuild … test` — confirm fail. Implement `@MainActor @Observable final class SettingsModel` over `ConfigStore`, `SecretStore`, `SpeechModelAssets`, the `GlobalKeyListener` capture API (Stage 24) and `SoundPlayer`. Run — confirm pass.
3. Implement the window (780×560, `NavigationSplitView`, sections General/Hotkeys/Keys/Cleanup/Vocabulary/History/Sound with the last three as placeholders until Stage 28), `Form` grouped style, the Keys footnote about the one-time Keychain allow dialog, write-through on every control; menu `Settings…` opens it; first-run auto-open wired.
4. Build clean; `xcodebuild … test` green.
5. Manual check: each control writes through to `config.json` immediately; engine rows disabled until a key is saved; hotkey capture reproduces the source's field behaviour (`Press shortcut...`, modifier-only capture); volume preview plays on release.

**Definition of done:** Gating rules tested; the window matches the accepted mockup's structure; no control can select a key-less cloud engine.

**Risks specific to this stage:** None.

### Stage 28 — App: Settings window II — Cleanup, profiles, Vocabulary, History
**Category:** Platform-only / UI wiring — SwiftUI; `ProfilesEditorModel` (bundle-ID uniqueness, add/remove, Default row) and `VocabularyModel` are tested in `AppTests`.
**Goal:** The remaining Settings sections: cleanup toggle with footnote, two prompt editors with Save Prompt / Open in Editor, profiles table and detail form, vocabulary chips, history retention slider and buttons (F26, F27, F28 editing, F29 retention control).
**Design references:** §5.4 Settings window (Cleanup, Vocabulary, History), §5.3 profiles, F26–F29 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `App/Settings/{CleanupSection.swift,ProfilesEditor.swift,ProfilesEditorModel.swift,VocabularySection.swift,VocabularyModel.swift,HistorySection.swift,AppChooser.swift}`; `AppTests/{ProfilesEditorModelTests.swift,VocabularyModelTests.swift}`.

**Steps (hybrid):**
1. Write test: `ProfilesEditorModelTests` → `addCreatesUUIDProfileWithEnterDefault`, `bundleIDAlreadyInAnotherProfileIsRejected`, `removeDeletesProfile`, `defaultRowIsSyntheticAndUsesPromptTxt`, `nullPromptMeansPromptTxt`, `runningAppsListedByBundleID`; `VocabularyModelTests` → `addTrimsAndDedupes`, `removeByIndex`, `persistsToConfig`. Expected initial failure: `cannot find 'ProfilesEditorModel' in scope`.
2. Run `xcodebuild … test` — confirm fail. Implement the models. Run — confirm pass.
3. Implement the sections: cleanup toggle (disabled + footnote without key), prompt editors backed by `PromptFiles` (`Open in Editor` → `NSWorkspace.shared.open(url)`), profiles table (+/−, detail: app chips with Add… listing `NSWorkspace.shared.runningApplications` or an `NSOpenPanel` on `/Applications` reading the bundle ID, cleanup toggle, submit popup, prompt editor; Default row "everything else"), vocabulary chips + entry, History section (slider 0–30 with label `Off` at 0, `Open History…` (Stage 29), `Clear History` with confirmation).
4. Build clean; `xcodebuild … test` green.
5. Manual check: a Terminal profile with cleanup off and Enter submit; a Slack profile with ⇧Enter; vocabulary terms appear in a `--debug` log dump of the composed prompts (DEBUG only); retention 0 deletes `history.jsonl`.

**Definition of done:** Models tested; every control writes through; a bundle ID belongs to at most one profile.

**Risks specific to this stage:** None.

### Stage 29 — App: History window and paste-from-history
**Category:** Platform-only / UI wiring — SwiftUI list; `HistoryListModel` (day grouping, search, meta line, footer) is tested in `AppTests`.
**Goal:** The History window per the accepted mockup with search, Copy, Paste into <previous app>, Delete, Clear History…, opened from `History…` (F29 window, F30).
**Design references:** §5.4 History window, §5.5 History paste, F29, F30 of feature-design-v1-Native-Swift-macOS-rewrite.md; accepted mockup `mockups/mockup-v1-history-list.html`.
**Touches:** `App/History/{HistoryListModel.swift,HistoryWindowController.swift,HistoryView.swift,AppGlyph.swift}`; `App/StatusItemController.swift` (edit: `History…` action); `App/Settings/HistorySection.swift` (edit: `Open History…`); `AppTests/HistoryListModelTests.swift`.

**Steps (hybrid):**
1. Write test: `HistoryListModelTests` → `groupsByDayNewestFirst`, `searchFiltersCaseInsensitive`, `metaLineFormat` (`HH:mm · App · Engine[+ cleanup] · 6.2s · $0.001`), `footerText` (`Keeping 7 days · 12 dictations`), `pasteEnabledOnlyWhenTargetRunning`, `glyphLettersAndHashedColourStable`, `pasteUsesPreviousAppPidAndNoSubmit`. Expected initial failure: `cannot find 'HistoryListModel' in scope`.
2. Run `xcodebuild … test` — confirm fail. Implement the model. Run — confirm pass.
3. Implement the window (680×480, toolbar search, day-grouped `List`, row layout per mockup, hover/selection actions, footer, confirmation sheet), `previousApp` captured on show, `Paste` → hide window → `previousApp.activate()` → 150 ms → `paster.paste(text, into: pid, submit: nil)`; `History…` menu item and `Open History…` wired.
4. Build clean; `xcodebuild … test` green.
5. Manual check: dictate twice, open History, search, copy, paste into TextEdit from History, delete one, clear with confirmation.

**Definition of done:** Model tested; window matches the accepted mockup's structure; paste-from-history restores the clipboard (Stage 19 behaviour) and posts no submit key.

**Risks specific to this stage:** None.

### Stage 30 — Release pipeline, docs and cask
**Category:** Non-TDD (config-only | integration-verified) — CI YAML, scripts and docs; verified by a `workflow_dispatch` run with signing on.
**Goal:** Tagged builds are signed (Developer ID, hardened runtime, entitlements), notarised, packaged as `MiniWhisper-<version>-arm64.dmg`, released on GitHub, and the cask updated (`version`, `sha256`, `url`, `homepage`, `depends_on macos: ">= :sonoma"`); CHANGELOG and README finalised (F1 version, N4, §5.10, §9 steps 2–3).
**Design references:** §5.1 (`scripts/`, workflow), §5.8, §5.10, §9, N4 of feature-design-v1-Native-Swift-macOS-rewrite.md; Python `.github/workflows/build.yml` (certificate import, notarytool, create-dmg, release, tap update steps — reused shape).
**Touches:** `.github/workflows/build.yml` (edit), `scripts/{make-dmg.sh,update-cask.sh}`, `CHANGELOG.md`, `README.md`, `project.yml` (edit: Release configuration signing settings left to CI overrides).

**Steps:**
1. Extend the `build` job: version from tag (`v0.2.0-beta.1` → `0.2.0-beta.1`; `MARKETING_VERSION` override on the `xcodebuild` command), Release build with `CODE_SIGN_IDENTITY="Developer ID Application"`, `DEVELOPMENT_TEAM=XPRCQRLN7Y`, `CODE_SIGN_STYLE=Manual`, `OTHER_CODE_SIGN_FLAGS="--timestamp"`, `ENABLE_HARDENED_RUNTIME=YES` (entitlements from `App/MiniWhisper.entitlements`), certificate import steps as in the Python workflow, `codesign --verify --verbose=2` + `codesign -d --entitlements - ` assertion that `com.apple.security.device.audio-input` is present and `com.apple.security.automation` absent, `scripts/make-dmg.sh` (create-dmg with the Python workflow's geometry), `xcrun notarytool submit --wait` + `stapler staple`, `softprops/action-gh-release@v2` (`prerelease` when the tag contains `-beta`/`-rc`), `scripts/update-cask.sh` (skipped for `-beta`/`-rc`; `sed` for `version`, `sha256`, `url` → `cagriy/mini-whisper-swift`, `homepage`, `depends_on macos: ">= :sonoma"`; commit and push to `cagriy/homebrew-tap`). Secrets referenced by name only: `DEVELOPER_ID_APPLICATION_P12`, `DEVELOPER_ID_APPLICATION_PASSWORD`, `APPLE_ID`, `APPLE_ID_PASSWORD`, `APPLE_TEAM_ID`, `HOMEBREW_TAP_TOKEN` (already exist in the Python repo's org secrets per its workflow; must be added to this repo by the user).
2. `CHANGELOG.md` 0.2.0 entry: parity, latency change (idle-stop engine, mic indicator while running), the five fixes, history/vocabulary/profiles, SpeechAnalyzer engine; rollback note linking the 0.1.8 DMG. `README.md`: install/upgrade, privacy section (history), permissions, engines.
3. Verification: `gh workflow run build.yml -f sign=true` on `main` (no tag) → job green, DMG artifact notarised (`spctl -a -t open --context context:primary-signature -v <dmg>` on the downloaded artifact prints `accepted`), `codesign -dr - "/Volumes/Mini Whisper/Mini Whisper.app"` shows `identifier "com.ips.mini-whisper"` and `certificate leaf[subject.OU] = XPRCQRLN7Y`.

**Definition of done:** Signed, notarised DMG produced by CI from `main`; cask script dry-run (`bash -n`) passes; docs updated.

**Risks specific to this stage:** Secrets must be configured on the new repo before the run — the workflow fails at certificate import otherwise (visible, not silent).

### Stage 31 — Acceptance over 0.1.8 and release
**Category:** Non-TDD (integration-verified) — the manual acceptance checklist from design §5.12 executed on the notarised beta, then the release tag.
**Goal:** Prove the drop-in upgrade and the latency/behaviour goals on the author's machine, then ship `v0.2.0` (§9 steps 2–4, N1 measured, F3/F36 continuity).
**Design references:** §5.12 Manual acceptance checklist, §7 risk table, §9, §5.10 of feature-design-v1-Native-Swift-macOS-rewrite.md
**Touches:** `CHANGELOG.md` (edit: acceptance notes), git tags `v0.2.0-beta.1` then `v0.2.0` (created by the user — never by this plan's executor without instruction).

**Steps:**
1. Tag `v0.2.0-beta.1` → CI produces the pre-release DMG (no cask update). Install over the running 0.1.8 (`brew`-installed) at `/Applications/Mini Whisper.app`.
2. Checklist (each item ticked in the CHANGELOG acceptance notes): (a) no TCC re-prompt for Microphone/Accessibility; onboarding does not appear; (b) existing hotkeys, prompts, engine choice, volume, usage rows and all three Keychain keys are honoured (Keychain allow dialog at most once); (c) warm press latency from `--debug` log `press→live` ≤ 50 ms and overlay visible within one frame (screen recording at 60 fps, count frames); (d) each engine's live caption: on-device, SpeechAnalyzer (after download), OpenAI, ElevenLabs, Speechmatics; key removal out-of-band → notice once; (e) profiles in Terminal (cleanup off, Enter) and Slack (⇧Enter); (f) History paste into the previous app; (g) clipboard restored after paste in TextEdit and an Electron app (Slack/VS Code); (h) second-monitor placement follows the focused window; (i) sleep/wake then dictate; (j) switch input device mid-dictation → `Audio device changed`, next press works; (k) second launch activates the first; (l) toggle cap at `toggle_max_seconds`; (m) discarded dictation adds no tokens (compare `usage` before/after); (n) `config.json` written by 0.2.0 loads in 0.1.8 (`uv run mini-whisper` from `../mini-whisper` reads it and shows the engine popup's first item for `speech_analyzer`); (o) Instruments allocation note from Stage 25 attached.
3. Fix-forward any failure as an ordinary bug before tagging `v0.2.0` (re-run the affected stage's tests; re-tag `-beta.2`).
4. Tag `v0.2.0` → release job updates the cask; `brew upgrade mini-whisper` on a second machine or a fresh user account installs 0.2.0.

**Definition of done:** All checklist items ticked in the CHANGELOG notes; `v0.2.0` released; cask points at `cagriy/mini-whisper-swift` with `>= :sonoma`.

**Risks specific to this stage:** TCC not carrying over despite the matching designated requirement (design §7) — onboarding appears once; acceptable per the design, but recorded in release notes if it happens.

## Cross-cutting concerns
- **Security** — Secrets only via `SecretStore` (Stage 4); `Log` never receives key or transcript text at INFO (asserted in Stages 4, 15 with `CapturingLogSink`; DEBUG-only prompt dumps in Stage 28's manual check); ephemeral `URLSession` (Stage 15) and TLS to the three vendors only (URLs pinned in Stages 11, 15); synthetic key events only to the resolved pid after `AXIsProcessTrusted()` (Stage 19, adapter Stage 24); history file 0600 and retention 0 leaves no file (Stage 17); hardened runtime, Developer ID, audio-input entitlement only (Stages 1, 30). No stage exposes a paste path before the AX check exists (the check lands in Stage 19 before any App adapter in Stage 24).
- **Performance** — `.starting` emitted before the first `await` (Stage 21 test); flag-flip capture and 1024-frame tap (Stage 8); config/secrets cached in memory (Stages 3, 4); preallocated `Frame` and reuse asserted (Stages 22, 25); caption redraw on change only (Stage 25); no polling timers in the controller (Stage 21 test); Instruments allocation note (Stage 25/31).
- **Observability** — `Log` categories and levels (Stage 2), timings `press→live`, `finish`, `transcribe`, `clean` logged at INFO in Stages 21 and 20, engine selection/downgrade reasons (Stage 14 via the controller), billing summary (Stage 20); `--debug` file sink (Stage 23); About shows the version (Stage 23).
- **Compatibility / migration** — `config.json` superset with unknown-key round-trip and the `daily_usage` migration (Stage 3, N6 assertion); Keychain service/accounts unchanged (Stage 4); bundle ID, Team ID and install path unchanged (Stages 1, 30); cask `depends_on` raised to Sonoma and repo switched by the release job (Stage 30); rollback to 0.1.8 documented (Stage 30/31). Between stages the repo is always buildable and green; the app becomes functional at Stage 24 and gains surfaces incrementally after.

## Verification
After Stage 31: (1) `cd Packages/MiniWhisperCore && swift test` and `xcodebuild … test` green on `main` and in CI; (2) the acceptance checklist in Stage 31 ticked in `CHANGELOG.md`; (3) F1–F38/N1–N6 walked once against the installed 0.2.0: identity (`codesign -dr`), config/Keychain continuity, hotkeys (both bindings, modifier-only capture), warm-press latency from the debug log, gate/toggle/cap behaviours, each engine's caption and batch fallback, HTTP error strings (temporarily invalid key → `Invalid API key — please update in Settings.`), profiles, vocabulary, history window actions, menu order and `Last:`, onboarding after revoking a permission, sounds/volume, single instance, overlay placement, `--debug` log; (4) `brew upgrade mini-whisper` on a clean account installs 0.2.0 from the updated cask.

## Risks and open issues
- **Swift 6 strict concurrency at the audio/Speech boundaries** — mitigated by keeping the tap→listener path synchronous (Stage 8), plain-value bridges for Speech callbacks (Stages 12, 13) and lock-protected engine state (Stage 10); if the compiler still rejects a pattern, an `@unchecked Sendable` wrapper with a documented invariant is the fallback.
- **Timing tests** — every duration (0.3 s hold, 100 ms tick, 5 s finish, 0.2 s drain, 60 s idle, 300 ms restore, cap) runs on `VirtualClock`; a real sleep in any test is a defect to fix in that stage.
- **SpeechAnalyzer live behaviour** — untestable on the host below macOS 26; the opt-in live test (Stage 13) and Stage 31 (d) are the only real checks; every failure path degrades to SFSpeech/batch.
- **CI secrets and runner availability** — Stage 30's `workflow_dispatch` proves the pipeline before any tag; failures are loud at the certificate step or `xcode-select`.
- **Debug-build TCC vs. Developer-ID TCC** — Stages 23–29 grant TCC to the ad-hoc-signed Debug bundle; the drop-in claim is only proven in Stage 31 with the notarised build.
- **Behavioural drift in rarely hit guards** — the coverage map plus the ported Python test names (Stages 5, 7, 9, 11, 12, 14, 15, 16, 20, 21, 22) are the checklist; any Python test without a Swift counterpart at the end of Stage 22 is a gap to close before Stage 23.

## Planning decisions taken
1. **Test convention (greenfield):** Swift Testing, one test target per module under `Tests/<Module>Tests/<Type>Tests.swift`, shared fakes in a library target `Sources/MWTestSupport`, fixtures inside the owning test target's `Fixtures/` (WAVs shared by several targets under `Sources/MWTestSupport/Fixtures/`) via `Bundle.module` — the design's `Tests/Fixtures/` location is not a SwiftPM resource root, so the files move; `AppTests/` for app-only tests. Proven in the scratchpad; established in Stage 1.
2. **xcodegen target naming:** app target `MiniWhisper` with `PRODUCT_NAME "Mini Whisper"`, `PRODUCT_MODULE_NAME MiniWhisper`, and explicit `TEST_HOST`/`BUNDLE_LOADER` on `AppTests` — without the override xcodegen derives a `MiniWhisper.app` test host that does not exist (observed failure in the scratchpad).
3. **Design fact correction — `AnalyzerInputConverter` does not exist** in the macOS 26.5 SDK (Speech swiftinterface checked 2026-09-01); the design's §4 and §5.2 now read `AVAudioConverter` into `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` wrapped as `AnalyzerInput(buffer:)`. `SpeechAnalyzer` is an actor, not a class — no behavioural impact.
4. **Design under-specification closed — listener attachment:** §5.2/§5.5 had `beginCapture(listener: engine)` before any step produced the engine; the interface is now `beginCapture()` + `attachListener(_:)` after `engine.start(sink)`; buffers captured before attachment are recorded but not streamed (the source's behaviour). Corrected in the design in place.
5. **Design internal contradiction resolved — processing order:** §5.5 listed "bill, append history, stale check, paste"; F15 (stale jobs bill streamed seconds only) and F29/§5.12 (history only on delivery) are §3 requirements and win: the order is stale check → bill → paste → append history. Corrected in §5.5 in place.
6. **Pipeline split:** `ProcessingJob` (Stage 20) is landed before `DictationController` (Stage 21) so the network/paste half is tested in isolation with an injected staleness check; the design's single cohesive state machine is preserved at the controller level.
7. **Seams for platform APIs:** `AudioBackend`, `SecItemAPI`, `SpeechRecognitionAPI`, `SpeechAnalyzerAPI`, `HTTPTransport`, `WebSocketConnection`, `KeyPoster`/`PasteboardAccess`/`AccessibilityCheck`/`ProcessCheck`, `FrontmostAppProviding` — each a protocol with a fake in MWTestSupport so N5 holds; the real adapters live next to their module (MWAudio, MWConfig, MWStreaming, MWTranscription, MWPaste) or in `App/` when they need AppKit.
8. **Opt-in integration tests** gated by `MW_INTEGRATION=1` (Keychain, live mic, SFSpeech, SpeechAnalyzer, OpenAI with `OPENAI_API_KEY`), mirroring the source's `-m integration` gating; the OpenAI fixture test asserts non-empty transcribe+clean output and does not port the source's LLM-judge scoring (the design asks only for transcribe + clean of the three fixtures).
9. **`CaptionModel` placed in MWOverlaySim** (pure line/alpha/unavailable logic with an injected measurer) so the caption rules from `overlay.py` are host-tested; the `CATextLayer` stack in `App/` consumes it.
10. **CI in two steps:** Stage 1 lands test + unsigned build; Stage 30 adds signing, notarisation, release and cask update, verified by `workflow_dispatch` before any tag.
11. **Stage order** follows the design's §9 (Core with tests → app → beta → release) with modules in dependency order; app surfaces are staged so a runnable, dictating app exists at Stage 24 and each later stage adds one surface.

## Deviations from the design
None — plan matches design v1 exactly (the three in-place corrections above are factual/contradiction fixes recorded under *Planning decisions taken*, not deviations).

# Remembered corrections — Design v2

**Status:** Draft
**Date:** 2026-09-05
**Storm:** [feature-storm-v2-Remembered-corrections.md](./feature-storm-v2-Remembered-corrections.md)

## 1. Summary

Mini Whisper users dictate the same names, acronyms and project terms into many apps, and the recognizer gets some of them wrong every time. Today the only recourse is a flat vocabulary list that reaches the batch transcription request and the cleanup prompt and never the streaming recognizer. This feature lets the user correct a misheard phrase once, from the menu bar's last dictation or from a History row, and remember it as a rule scoped to the destination app or to all apps. A rule is applied deterministically to every future transcript in scope, once, after optional cleanup and before paste, on every engine and path. The rule's correct spelling, the phrase that was heard, and any further sounds-like variants are sent to the configured recognizer as hints where the engine has a documented hint mechanism, so the recognizer is steered toward a form the rule already knows. Settings → Vocabulary gains a corrections table, a tally of phrases the user keeps correcting, and a per-engine report of what was sent. The feature is verified by request-contract tests and by a before/after measurement on a user-provided audio set per hint-capable engine.

## 2. Goals and non-goals

- **Goals:**
  - A remembered rule replaces exact whole-phrase matches of its Heard phrase or any Sounds-like variant in the next dictation delivered within its scope, identically for streamed, batch, cleanup-on, cleanup-off and key-free paths.
  - A rule scoped to This app never changes a dictation delivered to a different app; an All-apps rule changes dictations delivered anywhere.
  - Every rule is visible and editable in Settings → Vocabulary; disable and delete take effect from the next recording.
  - Correct spelling, Heard phrase and Sounds-like variants reach SFSpeechRecognizer, SpeechAnalyzer, OpenAI Realtime, Speechmatics, the batch transcription prompt and the cleanup prompt, proven by request-contract tests; Speechmatics receives the variants as `sounds_like`.
  - The batch transcription request uses the documented `prompt` field, carrying the transcription instructions file plus the resolved terms.
  - A fixed, user-provided audio set is run hints-off and hints-on per hint-capable engine before completion, with target-term hits and false corrections recorded in the feature folder; the result decides SpeechAnalyzer's hint label.
  - Correcting without remembering produces the corrected text for copying and increments only the tally.
- **Non-goals:**
  - ElevenLabs keyterms and their 20 % premium billing (deferred; ElevenLabs users get the local rule and a "not sent in this version" report line).
  - Creating a rule in Settings without a dictation; the tally's Remember… seeds the correction window instead.
  - Pasting corrected text back into the original app; profile-scoped rules; a Correct affordance on the overlay; per-rule firing counts; applying rules to the live caption; export or import of rules.
  - Custom language models (`SFCustomLanguageModelData`) for SFSpeechRecognizer; switching the SpeechAnalyzer module to DictationTranscriber.
  - Automatic sounds-like without a visible field; regex, wildcard, fuzzy or cascading rules; rewriting past History entries; background monitoring of edits in other apps; model training; voice editing.

## 3. Requirements

Rules and storage

- R1. `config.json` gains a top-level `corrections` array. Each rule has `id` (UUID string), `heard` (string), `write` (string), `sounds_like` (array of strings, default empty), `bundle_id` (string or `null`; `null` means All apps), `enabled` (boolean, default `true`). A config without the key decodes to no rules.
- R2. `config.json` gains a top-level `correction_tally` array of `{heard, count, last}` (display spelling, integer, ISO-8601 UTC). Absent means empty. At most 200 entries.
- R3. Both keys are known keys: they never land in `Config.extra`, they round-trip through save, and every other key survives a rules edit. The Python app round-trips them untouched (verified: `config.py:59-81` loads and dumps the whole dict).
- R4. Validation on load and save: `heard`, `write` and each `sounds_like` value are trimmed and whitespace-collapsed; rules with an empty `heard` or `write` are dropped; two rules with the same scope and the same normalised `heard` keep the first; empty `sounds_like` values are dropped.
- R5. Saving from the correction window or Settings rejects, with a visible message: an empty Heard or Write; a Write identical to Heard (case-sensitive compare, so case-only fixes are allowed); a Heard already remembered in the same scope (comparison excludes the rule being edited).
- R6. A rule's `heard` and `sounds_like` are normalised with Unicode NFC, trimmed, and internal whitespace runs collapsed to one space; `write` is stored exactly as typed after trimming.

Matching

- R7. A rule matches literal whole phrases: the match may not begin or end inside a run of letters, marks, digits or underscore; whitespace between the phrase's words matches any whitespace run; matching is case-insensitive; punctuation inside the phrase is literal.
- R8. Heard and every Sounds-like variant are match targets of the same rule; the replacement is always `write` verbatim.
- R9. All applicable rules are applied in one pass over the original text. Overlapping candidates resolve to the longest match, then the app-scoped rule over the global rule, then stored order. Replaced text is never rescanned, so no rule chain can cascade.
- R10. For the same normalised variant, an app-scoped rule for the delivery app suppresses the global rule.
- R11. Disabled rules take part in nothing: not matching, not hints, not the cleanup prompt.

Pipeline

- R12. A recording captures one immutable `CorrectionSnapshot` (rules plus vocabulary) from the config loaded at press, together with the frontmost app at press. Edits during a recording affect the next one.
- R13. Streaming hints are resolved for the press-time app against the snapshot. Batch-prompt terms, cleanup terms and the final rule set are resolved for the release-time app against the same snapshot.
- R14. Rules are applied exactly once, to the final text, after cleanup when cleanup ran and to the raw text otherwise, before the paste, the history entry and the `.result` event. The pasted text, the History entry and the menu's Last row all show the corrected text.
- R15. The live caption is never changed by rules.
- R16. The `.result` UI event carries the delivered text and the delivery app's name and bundle ID.

Hints

- R17. The resolved hint list for a bundle ID is, in order: for each enabled app-scoped rule in stored order its `write`, `heard`, then `sounds_like`; the same for global rules; then the manual vocabulary. Duplicates by normalised key are removed keeping the first spelling. Disabled rules and rules for other apps contribute nothing.
- R18. SFSpeechRecognizer receives the first 100 hints as `contextualStrings`; the rest are skipped and reported.
- R19. SpeechAnalyzer receives the first 100 hints via `AnalysisContext.contextualStrings[.general]` set on the analyzer before analysis starts, with SpeechTranscriber unchanged. Its Settings label is decided by the measurement (R33).
- R20. OpenAI Realtime receives every hint as `session.audio.input.transcription.keywords`, with `<`, `>`, CR and LF removed from each; a hint empty after removal is skipped and reported. The field is absent when there are no hints.
- R21. Speechmatics receives `transcription_config.additional_vocab`: one entry per enabled rule `{content: write, sounds_like: [heard, sounds_like…]}` and one `{content: term}` per vocabulary term, app rules first, then global, then vocabulary, up to 1000 entries. An entry whose `content` exceeds 6 words or contains a word over 4000 characters is skipped and reported; a `sounds_like` value that would be is dropped from its entry. The field is absent when empty.
- R22. ElevenLabs receives no hints; the report says so.
- R23. The batch transcription request sends the multipart field `prompt`, equal to the transcription instructions file followed by `\n\nVocabulary (spell exactly as written): a, b, c` when there are terms; the field is omitted when both are empty. The field `instructions` is no longer sent.
- R24. The cleanup prompt appends `\n\nPreserve these terms exactly as written: …` listing every `write` and vocabulary term, and `\n\nKnown corrections — replace the exact phrase on the left with the spelling on the right:` followed by one `"variant" → "write"` line per variant, for the rules applicable to the release app. Both are omitted when empty.
- R25. Empty hints leave every engine's existing request shape byte-for-byte unchanged.
- R26. No log line, at any level, contains a hint term, a rule phrase or a transcript.

Correction window

- R27. "Correct Last Dictation…" appears in the menu directly under the Last row once a dictation has been delivered, and opens the correction window with that dictation's text and app. It works when history retention is 0.
- R28. Each History row gains "Correct…", which opens the same window with that entry's text, app name and bundle ID.
- R29. Selecting text in the transcript snaps outward to whole words, trims surrounding whitespace, and sets Heard; Write and Sounds like are reset to Heard on every new selection.
- R30. Scope defaults to This app when the source has a bundle ID and shows the app name; with no bundle ID the This app option is disabled and All apps is selected.
- R31. The preview shows the transcript with the draft rule applied; the impact line shows how many stored history entries in scope contain a match, with up to three snippets; when retention is 0 it reads "History is off — no preview".
- R32. Copy writes the previewed text to the pasteboard and never pastes or submits. Cancel writes nothing. Save validates (R5), persists the rule with `ConfigStore.update`, and only then shows the confirmation state offering Copy and Done. A failed write shows its error and keeps the draft. With the Remember toggle off, Save is disabled and nothing is persisted. Copy or Save increments the tally for the Heard phrase at most once per window.

Settings

- R33. Settings → Vocabulary shows, below the existing terms: a Corrections group with a read-only table (Heard, Write, Scope, Enabled), a − button, and a detail form for the selected rule (Heard, Write, Sounds like, Scope popup, Enabled switch); an Often corrected group listing the top five tally phrases with counts and, for phrases with no enabled rule, a Remember… button; a Recognition hints group with one row per engine (sent count, cap, skipped terms with reasons, or "not sent in this version"), where SpeechAnalyzer's row reads as measured (R37).
- R34. Detail-form edits commit on Return (text) or immediately (popup, switch), persist through `ConfigStore.update`, and show R5's messages in place without writing.
- R35. Remember… opens the correction window with the tallied phrase as its transcript, fully selected, scope All apps.
- R36. A rule saved from the correction window while Settings is open appears in the table without reopening Settings, via the existing AppDelegate config-change consumer.

Measurement

- R37. An opt-in test suite runs when `MW_INTEGRATION=1` and `MW_HINT_AUDIO_DIR` names a directory holding `manifest.json` and WAV clips. For each available engine (SFSpeechRecognizer; SpeechAnalyzer on macOS 26 with the model installed; OpenAI Realtime and batch with `OPENAI_API_KEY`; Speechmatics with `SPEECHMATICS_API_KEY`) it transcribes every clip hints-off and hints-on, counts target terms recognised before rules, counts rule firings on control clips, and writes `features/feature-v2-Remembered-corrections/measurements/<engine>-<YYYY-MM-DD>.md`. No audio is written anywhere.
- R38. SpeechAnalyzer's hint label is "supported" when hints-on recognises more target terms than hints-off across the set and produces no more false corrections; otherwise the AnalysisContext path is removed and the label is "unavailable". The label is a constant in code mirrored by the README.

Documentation

- R39. README and CHANGELOG describe per-engine hint support, the `prompt` field change, local storage of rules and tally, scope semantics, and that hints are probabilistic while rules are deterministic.

Non-functional

- N1. Bundle ID `com.ips.mini-whisper`, macOS 14 target, Swift 6 strict concurrency, no third-party dependencies.
- N2. Every timing in the pipeline stays on the injected clock; no test sleeps.
- N3. Rule application adds no network call and completes in well under a millisecond for a dictation-sized text with hundreds of rules.
- N4. Settings never gains a second consumer of `ConfigStore.changes`.
- N5. TDD: each behaviour gets a failing test before its implementation.

## 4. Background and context

- Vocabulary today: `Config.vocabulary` (`Packages/MiniWhisperCore/Sources/MWConfig/Config.swift:109`) is appended by `PromptComposer.transcribeInstructions` and `cleanupPrompt` (`MWProfiles/PromptComposer.swift:3-8`) and used only at `MWPipeline/ProcessingJob.swift:71-73` (batch) and `:101-103` (cleanup). No streaming engine receives it: `EngineFactory.make` takes `config` and `secrets` only (`MWStreaming/EngineFactory.swift:37`), the SF bridge sets two request properties (`SFSpeechRecognitionBridge.swift:26-27`), the analyzer bridge builds `SpeechAnalyzer(modules:)` with no context (`SpeechAnalyzerBridge.swift:120`), and the adapters' open messages carry no vocabulary (`OpenAIRealtimeAdapter.swift:23-37`, `SpeechmaticsAdapter.swift:20-33`).
- Batch request: `OpenAIClient.transcribe` adds a multipart field named `instructions` (`MWTranscription/OpenAIClient.swift:39`), as the Python original did (`../mini-whisper/src/mini_whisper/transcriber.py:38-39`). OpenAI's speech-to-text guide documents `prompt` as the field that improves recognition of names and vocabulary and lists `gpt-4o-mini-transcribe` as supporting it; `instructions` is not a documented parameter. The existing test pins the wrong name (`Tests/MWTranscriptionTests/OpenAIClientTests.swift:98`).
- Press and release: `DictationController.startStream` loads config and asks the provider for an engine (`MWPipeline/DictationController.swift:122-144`); `stop` captures the frontmost app, reloads config, resolves the profile and builds `ProcessingInput` (`:181-233`). `ProcessingJob.run` applies cleanup, bills, pastes, appends history and emits `.result(finalText)` (`ProcessingJob.swift:93-169`). `UIEvent.result` carries a `String` (`UIEvent.swift:11`), consumed at `App/UIEventRouter.swift:68` and stored by `MenuModel.setLast` (`App/MenuModel.swift:56`).
- History already stores the delivery app: `HistoryEntry.appName` and `bundleID` (`MWHistory/HistoryEntry.swift:18-19`), written from `input.target` (`ProcessingJob.swift:153-156`). `HistoryListModel.Row` exposes only text and meta today (`App/History/HistoryListModel.swift:29-34`).
- Settings patterns: `SettingsModel` owns child models and writes through `ConfigStore.update` (`App/Settings/SettingsModel.swift:119-120, 414-423`); `ProfilesEditorModel` is the table-plus-detail-form pattern with validation (`App/Settings/ProfilesEditorModel.swift:118-130`); `VocabularySection` is the pane being extended (`App/Settings/VocabularySection.swift`). AppDelegate is the only consumer of `configStore.changes` (`App/AppDelegate.swift:192-196`).
- Speech SDK, verified in Xcode 26.6's `Speech.swiftinterface`: `SFSpeechRecognitionRequest.contextualStrings` exists; `AnalysisContext.contextualStrings: [ContextualStringsTag: [String]]` with `.general` exists and is set on a `SpeechAnalyzer` via its `analysisContext:` initialiser parameter or `setContext(_:)`. Apple documents the property as consumed by DictationTranscriber with a 100-phrase limit; `SpeechTranscriber` has no vocabulary option of its own. `SFCustomLanguageModelData` exists but is out of scope.
- Provider docs, verified 2026-09-05: OpenAI Realtime transcription sessions accept `keywords` (no `<`, `>`, CR, LF) beside `prompt` and `languages`; Speechmatics `additional_vocab` entries carry `content` and optional `sounds_like`, up to 1000 per job, entries over 6 words dropped server-side with a `validation_warning`.
- Prior decision: the v1 design deferred "automatic or edit-driven vocabulary learning" by name (`features/feature-v1-Native-Swift-macOS-rewrite/feature-storm-v1-Native-Swift-macOS-rewrite.md`, §3). This feature is that follow-up. The storm for this feature is linked above; its §7 questions are all closed here.

## 5. Design

### 5.1 Architecture / components

**New module `MWCorrections`** (SwiftPM target and product, depends on `MWConfig` only; registered in `Package.swift`, added to the CLAUDE.md module map). Pure value types and functions, no I/O, every component unit-testable alone.

| Component | Responsibility | Public interface |
|---|---|---|
| `ResolvedRule` | One enabled rule as it applies to one delivery app | `struct { rule: CorrectionRule; variants: [String]; isAppScoped: Bool }` — `variants` are the normalised `heard` plus each normalised `sounds_like`, deduped, with any variant suppressed by an app-scoped rule (R10) already removed; the replacement is `rule.write` |
| `CorrectionResolver` | Rules applicable to a bundle ID with scope precedence | `init(rules: [CorrectionRule])`; `func rules(for bundleID: String?) -> [ResolvedRule]` — enabled rules whose `bundleID` is nil or equal, app rules first, with a global rule's variant dropped when an app rule owns the same key |
| `PhraseMatcher` | One compiled pattern per variant | `init(variant: String) throws`; `func matches(in: String) -> [Range<String.Index>]` |
| `CorrectionApplier` | Single-pass replacement (R7–R11) | `init(rules: [ResolvedRule])` (compiles matchers once); `func apply(to text: String) -> Application` where `Application { text: String; replacements: Int }` |
| `CorrectionValidator` | R5 | `static func validate(_ draft: CorrectionRule, against existing: [CorrectionRule], excluding id: String?) -> ValidationError?` with cases `.emptyHeard`, `.emptyWrite`, `.noChange`, `.duplicate(existingWrite: String, scope: String)` and a `message` |
| `CorrectionSnapshot` | The per-recording immutable value (R12) | `struct { rules: [CorrectionRule]; vocabulary: [String] }`, `init(config: Config)` |
| `RecognitionHints` | What engines receive | `struct { terms: [String]; rules: [HintRule]; vocabulary: [String] }` where `HintRule { write: String; soundsLike: [String] }` — `terms` per R17; `rules` in R17's resolver order (app-scoped first, then global), each carrying its `write` and the deduped `[heard] + sounds_like` with the write itself excluded; `vocabulary` the manual terms in stored order; `static let none`. An ordered array rather than a `[String: [String]]` dictionary because R21 fixes the entry order of `additional_vocab` and R24 the order of the cleanup pairs, and Swift dictionaries have no order |
| `HintResolver` | R17 | `static func resolve(_ snapshot: CorrectionSnapshot, bundleID: String?) -> RecognitionHints` |
| `HintSerializer` | Per-engine caps and filters (R18–R22) | `static func contextualStrings(_: RecognitionHints) -> Capped` (100); `static func openAIKeywords(_:) -> Capped` (character filter); `static func speechmaticsVocab(_:) -> CappedEntries` (1000, 6 words, 4000 chars); `Capped { sent: [String]; skipped: [(term: String, reason: SkipReason)] }` |
| `HintReport` | Settings rows (R33) | `static func report(rules: [CorrectionRule], vocabulary: [String], support: HintSupport) -> [HintReport.Row]` where `Row { engine: EngineName?; label: String; sent: Int; cap: Int?; skipped: [(String, SkipReason)]; state: .supported / .measured / .unavailable(String) / .notSent(String) / .prompt }`; computed over every enabled rule regardless of scope (worst case for caps) |
| `HintSupport` | R38 | `enum { case supported, unavailable(reason: String) }`; `static let speechAnalyzer: HintSupport` — starts as `.unavailable(reason: "effect not yet measured")` and the measurement stage sets its final value before release |
| `CorrectionTally` | R2 | `static func incremented(_ tally: [CorrectionTallyEntry], heard: String, now: Date) -> [CorrectionTallyEntry]` (cap 200; evict lowest count, then oldest `last`); `static func top(_ tally:, limit: 5, rules: [CorrectionRule]) -> [TallyRow]` where `TallyRow { heard, count, hasRule }` |
| `ImpactPreview` | R31 | `struct Entry { text: String; bundleID: String? }`; `static func compute(rule: CorrectionRule, over: [Entry]) -> Result` where `Result { matching: Int; total: Int; snippets: [String] }` — scope filter by `rule.bundleID`, snippets are ±30 characters around the first match of up to three entries |
| `PromptSections` | Text for R23/R24 | `static func vocabularyLine(terms: [String]) -> String?`; `static func cleanupBlocks(hints: RecognitionHints, rules: [ResolvedRule]) -> [String]` |

**`MWConfig` (modified).** `CorrectionRule` and `CorrectionTallyEntry` live here because `Config` encodes them. `Config` gains `corrections: [CorrectionRule]`, `correctionTally: [CorrectionTallyEntry]`, the two keys in `Key.all`, decode-with-defaults like `Profile`, and R4 in `validated()`. `PhraseKey` — the normalisation shared by matching, validation, dedupe and the tally, `static func normalised(_ s: String) -> String` (trim, NFC, collapse whitespace) and `static func key(_ s: String) -> String` (normalised, lowercased) — lives here too rather than in `MWCorrections`: `Config.validated()` implements R4 and R6, and `MWConfig` cannot import `MWCorrections` without inverting the module dependency. `MWCorrections` uses it through its `MWConfig` dependency.

**`MWStreaming` (modified; gains a dependency on `MWCorrections`).** `RecognitionOptions.contextualStrings: [String]` (default `[]`). `SpeechRecognitionAPI` unchanged; `SFSpeechRecognitionBridge` sets `request.contextualStrings` when non-empty. `SpeechAnalyzerAPI.makeSession(locale:contextualStrings:)`; the bridge's `Session` builds an `AnalysisContext` and calls `setContext` inside the analysis task before `analyzeSequence` when the list is non-empty. `SFSpeechEngine(api:clock:hints:)` and `SpeechAnalyzerEngine(api:locale:clock:hints:)` take `RecognitionHints` (default `.none`) and serialise through `HintSerializer` at start, logging sent and skipped counts. `OpenAIRealtimeAdapter(apiKey:hints:)` and `SpeechmaticsAdapter(apiKey:hints:)` add their fields to `openMessages()`. `ElevenLabsAdapter` unchanged. `EngineProvider.make(config:secrets:hints:)`; `EngineFactory` forwards `hints` to every engine it builds. `EngineNotice` unchanged.

**`MWTranscription` (modified).** `Transcriber.transcribe(wav:prompt:)`; `OpenAIClient` adds the multipart field `prompt` when non-empty and no longer adds `instructions`.

**`MWProfiles` (modified; gains a dependency on `MWCorrections`).** `PromptComposer.transcribePrompt(base:terms:)` and `cleanupPrompt(base:hints:rules:)` per R23/R24, built from `PromptSections`.

**`MWPipeline` (modified; gains a dependency on `MWCorrections`).** `RecordingSession` gains `startTarget: PasteTarget?` and `snapshot: CorrectionSnapshot?`. `ProcessingInput` gains `snapshot: CorrectionSnapshot`. `UIEvent.result(DeliveredDictation)` with `DeliveredDictation { text: String; appName: String; bundleID: String?; engine: EngineName?; deliveredAt: Date }`. `DictationController` captures the frontmost app at press, builds the snapshot and hints in `startStream`, passes hints to the provider, and fills `ProcessingInput.snapshot` at release. `ProcessingJob` composes prompts from the snapshot, applies the rules per R14 and emits the new event.

**`MWTestSupport` (modified).** `FakeTranscriber` records `prompt`; `FakeEngineProvider` records the hints it was given; `FakeSpeechAnalyzerAPI` records `contextualStrings` per session; `FakeSpeechRecognitionAPI` already records `RecognitionOptions`.

**App (modified and new).**

- `App/Correction/CorrectionSource.swift` — `struct CorrectionSource { text: String; appName: String?; bundleID: String?; preselectAll: Bool }` with initialisers from `DeliveredDictation`, `HistoryEntry` and a tally phrase.
- `App/Correction/CorrectionModel.swift` — `@MainActor @Observable final class` owning the window's rules (5.4).
- `App/Correction/CorrectionView.swift`, `CorrectionWindowController.swift` — SwiftUI view hosted like History (`NSHostingView`, activation policy toggling, `EditMenu.ensure()`), 560×520, one instance reused; `show(source:)` replaces the model.
- `App/MenuModel.swift` — `lastDictation: DeliveredDictation?`, `.correctLast` action, row "Correct Last Dictation…" inserted at index 3 after the Last row; `lastText` derived.
- `App/StatusItemController.swift` — `setLast(_ dictation: DeliveredDictation)`, `onCorrectLast` callback.
- `App/UIEventRouter.swift` — `.result(let dictation)` → `statusItem.setLast(dictation)`.
- `App/History/HistoryListModel.swift` — `Row` gains `appName`, `bundleID`; `Dependencies.correct: @MainActor (CorrectionSource) -> Void`; `func correct(_ row: Row)`. `HistoryView` adds the "Correct…" bordered mini button between Paste and Copy.
- `App/Settings/CorrectionsEditorModel.swift`, `CorrectionsEditor.swift` — the table + detail form (5.3), the Often corrected group and the Recognition hints group; `SettingsModel` owns `let corrections: CorrectionsEditorModel` and gains `func refresh(from config: Config)`; `VocabularyModel` gains `func replace(terms: [String])`; `VocabularySection` composes the four groups; `SettingsModel.Dependencies.openCorrection: @MainActor (CorrectionSource) -> Void`.
- `App/AppDelegate.swift` — composition: `correctionWindow`, `openCorrection(_:)`, `onCorrectLast` and history `correct` closures, `apply(config)` also calls `settings?.model.refresh(from: config)`.

**Tests.** New `Tests/MWCorrectionsTests/` (one file per component) plus the opt-in `Tests/MWStreamingTests/HintMeasurementTests.swift`; extensions to the existing suites named in 5.10.

### 5.2 Data model

`config.json` additions (every other key unchanged; the Python app round-trips these as unknown keys):

```json
{
  "corrections": [
    {"id": "b2e7…", "heard": "eefa", "write": "Aoife", "sounds_like": ["eefa", "eva"],
     "bundle_id": "com.tinyspeck.slackmacgap", "enabled": true},
    {"id": "9c10…", "heard": "get hub", "write": "GitHub", "sounds_like": ["get hub"],
     "bundle_id": null, "enabled": true}
  ],
  "correction_tally": [
    {"heard": "eefa", "count": 4, "last": "2026-09-05T16:07:00Z"},
    {"heard": "speech matics", "count": 3, "last": "2026-09-04T09:12:41Z"}
  ]
}
```

- `CorrectionRule: Equatable, Sendable, Codable` with `CodingKeys` mapping `soundsLike = "sounds_like"`, `bundleID = "bundle_id"`; decoding supplies `id` (new UUID), `sounds_like` (`[]`) and `enabled` (`true`) when absent, and throws only when `heard` or `write` is missing. `bundle_id` is written as an explicit `null` for global rules, matching how `HistoryEntry` writes optional fields.
- `CorrectionTallyEntry: Equatable, Sendable, Codable` with `last` written as `2026-09-05T16:07:00Z` (the `history.jsonl` timestamp format, produced by MWConfig's own `ISO8601DateFormatter` with `.withInternetDateTime`, since MWHistory's formatter is internal to that module); a malformed `last` decodes as `Date.distantPast` rather than failing the config.
- Tally key is `PhraseKey.key(heard)`; `heard` keeps the first-seen spelling. Cap 200 (R2). Eviction on insert: lowest `count`, then oldest `last`.
- Rule order in the array is the stored order that R9 and R17 use; Settings never reorders.
- Lifetime: rules and tally live as long as the config; deleting the key or the rule removes it. History entries are never rewritten.
- No migration: absent keys mean empty. An older build of this app preserves both keys through `Config.extra`.

### 5.3 Interfaces

**Matching (`PhraseMatcher`).** Pattern for a normalised variant `w1 w2 … wn`: `(?<![\p{L}\p{M}\p{N}_])` + `escaped(w1)\s+escaped(w2)…` + `(?![\p{L}\p{M}\p{N}_])`, compiled with `NSRegularExpression` options `[.caseInsensitive]`, tokens escaped with `NSRegularExpression.escapedPattern(for:)`. The applier first normalises the input to NFC (`precomposedStringWithCanonicalMapping`), then matches and splices on that form; the output is NFC. Recognizer output is already NFC in practice, so this changes nothing visible. `CorrectionApplier.apply` collects `(range, ruleIndex, isAppScoped, length)` for every variant of every rule, sorts by `range.lowerBound`, then longer first, then app before global, then rule index, sweeps left to right accepting non-overlapping candidates, and splices `write` for each accepted range.

**Pipeline.**

```swift
// MWStreaming
public protocol EngineProvider: Sendable {
    func make(config: Config, secrets: any SecretStore, hints: RecognitionHints) async -> EngineSelection
}
public struct RecognitionOptions { var requiresOnDeviceRecognition: Bool; var shouldReportPartialResults: Bool; var contextualStrings: [String] = [] }
public protocol SpeechAnalyzerAPI { …; func makeSession(locale: Locale, contextualStrings: [String]) async throws -> any AnalyzerSession }
// MWTranscription
public protocol Transcriber: Sendable { func transcribe(wav: Data, prompt: String) async throws -> (String, TokenUsage) }
// MWProfiles
public struct PromptComposer {  // existing declaration kind, unchanged
    static func transcribePrompt(base: String, terms: [String]) -> String
    static func cleanupPrompt(base: String, hints: RecognitionHints, rules: [ResolvedRule]) -> String
}
// MWPipeline
public struct DeliveredDictation: Sendable, Equatable { public var text: String; public var appName: String; public var bundleID: String?; public var engine: EngineName?; public var deliveredAt: Date }
public enum UIEvent { …; case result(DeliveredDictation); … }
public struct ProcessingInput { …; public var snapshot: CorrectionSnapshot }
```

**Wire shapes (additions only; everything else as design v1 §5.4).**

- SFSpeechRecognizer: `request.contextualStrings = ["Aoife", "eefa", "eva", "GitHub", "get hub", "xcodegen", …]` (first 100).
- SpeechAnalyzer: `let context = AnalysisContext(); context.contextualStrings = [.general: strings]; try await analyzer.setContext(context)` before `analyzeSequence`; a thrown error is logged at info level and analysis proceeds without hints.
- OpenAI Realtime open message: `"transcription": {"model": "gpt-live-transcribe", "keywords": ["Aoife", "eefa", "eva", "GitHub", …]}` — `keywords` present only when non-empty.
- Speechmatics `StartRecognition`: `"transcription_config": {"language": "en", "enable_partials": true, "additional_vocab": [{"content": "Aoife", "sounds_like": ["eefa", "eva"]}, {"content": "GitHub", "sounds_like": ["get hub"]}, {"content": "xcodegen"}]}` — `additional_vocab` present only when non-empty.
- Batch: multipart parts `file`, `model`, `response_format`, `prompt` (when non-empty). `prompt` = `<transcribe_prompt.txt>` + `\n\nVocabulary (spell exactly as written): Aoife, eefa, eva, GitHub, get hub, xcodegen`.
- Cleanup system prompt = profile prompt + `\n\nPreserve these terms exactly as written: Aoife, GitHub, xcodegen, Mini Whisper` + `\n\nKnown corrections — replace the exact phrase on the left with the spelling on the right:\n"eefa" → "Aoife"\n"eva" → "Aoife"\n"get hub" → "GitHub"`.

**UI surfaces** — as the accepted mockups: [Correction Window](./mockups/mockup-v2-correction-window.html) ([artifact](https://claude.ai/code/artifact/8848024e-217a-4862-ac40-786966591235)) and [Vocabulary — Detail Form](./mockups/mockup-v2-vocab-detail-form.html) ([artifact](https://claude.ai/code/artifact/e39399f3-51b6-420e-956d-b74038256122)).

- Correction window, 560×520, title "Correct Dictation": source line (`AppGlyph`, app name, `HH:mm` of delivery, engine label; the engine label comes from `HistoryListModel.engineLabel`, made an internal shared helper), a selectable transcript box (`NSTextView` in an `NSViewRepresentable`, read-only, selection reported to the model), two-column grid Heard (read-only) / Write / Sounds like (comma-separated) / Scope segmented control "This app · <App>" | "All apps", "Remember this correction" toggle (on), Preview box with replaced ranges highlighted, impact line with up to three snippets, footer Copy corrected text (leading) · Cancel · Save. Validation replaces the impact line with a red sentence; Copy is never disabled. Confirmation state: tick, "Remembered for <Slack | All apps>", explanatory sentence, Copy corrected text and Done. With the Remember toggle off, Save is disabled and Copy and Cancel remain; nothing is persisted. No bundle ID: This app disabled, All apps selected, help text explains why. History off: impact line reads "History is off — no preview of past dictations."
- Menu: `[Today, Month, Last: "…", Correct Last Dictation…, separator, History..., Settings..., separator, About Mini Whisper, Quit]`; both Last and Correct Last Dictation… are absent until the first delivered dictation.
- History row hover actions: Paste into <App> · Correct… · Copy · Delete.
- Vocabulary pane: existing chips and entry field with the footnote "Terms are sent to the recognizer as hints and kept as written by the cleanup prompt."; Corrections group: table (Heard, Write, Scope, Enabled) 130 pt high, − button, detail form rows Heard, Write, Sounds like (text fields committing on Return), Scope popup listing All apps, the rule's current app, the running apps from `AppListing.runningApps()` and "Choose from Applications…" via `AppChooser`, exactly as the profiles editor's Add… menu does, Enabled switch, red error line, footnote "Rules are created from a dictation: Correct Last Dictation… in the menu bar, or Correct… on a History row."; Often corrected group: five rows `phrase · ×count · remembered | Remember…`, footnote; Recognition hints group: rows per 5.1 `HintReport` with a green/amber/grey dot, footnote "Counts include every rule regardless of app. A hint makes a spelling more likely; the rule makes it certain."

**Measurement manifest** (`$MW_HINT_AUDIO_DIR/manifest.json`):

```json
{
  "rules": [{"heard": "eefa", "write": "Aoife", "sounds_like": ["eefa", "eva"]}],
  "vocabulary": ["xcodegen"],
  "clips": [
    {"file": "aoife-1.wav", "targets": ["Aoife"]},
    {"file": "plain-1.wav", "targets": [], "control": true}
  ]
}
```

Report per engine: one row per clip (hints-off transcript hit count, hints-on hit count, rule firings after apply), totals, and the verdict line for SpeechAnalyzer.

### 5.4 Control flow

**Press.** `hotkeyPressed` records `startTarget = deps.frontmost.frontmost()` in the new `RecordingSession` (synchronous, before `.starting`). `startStream` loads config, builds `snapshot = CorrectionSnapshot(config:)` and `hints = HintResolver.resolve(snapshot, bundleID: startTarget?.bundleID)`, stores the snapshot on the session, and calls `deps.engines.make(config:secrets:hints:)`. The factory hands `hints` to `SFSpeechEngine`, `SpeechAnalyzerEngine`, `OpenAIRealtimeAdapter` or `SpeechmaticsAdapter`; each serialises them at `start` and logs sent and skipped counts.

**Release.** `stop` proceeds as today; `ProcessingInput.snapshot = session.snapshot ?? CorrectionSnapshot(config: config)` (the fallback covers a release that lands before `startStream` ran).

**Processing.** In `ProcessingJob.run`: `releaseHints = HintResolver.resolve(input.snapshot, bundleID: input.target.bundleID)` and `rules = CorrectionResolver(rules: input.snapshot.rules).rules(for: input.target.bundleID)`. Batch uses `PromptComposer.transcribePrompt(base:terms: releaseHints.terms)`. Cleanup uses `PromptComposer.cleanupPrompt(base:hints:rules:)`. After the cleanup block, before checkpoint 3: `finalText = CorrectionApplier(rules: rules).apply(to: finalText).text`, logged as `corrections: N replacement(s) from M rule(s)` when N > 0. Paste, history and `.result(DeliveredDictation(text: finalText, appName: input.target.name, bundleID: input.target.bundleID, engine: engineName, deliveredAt: Date()))` follow unchanged (`Date()` as the history entry already uses at `ProcessingJob.swift:153`).

**Correct last.** `.result` → `UIEventRouter` → `StatusItemController.setLast(dictation)` → `MenuModel` inserts or updates the Last and Correct Last rows. Clicking Correct Last calls `onCorrectLast` → `AppDelegate.openCorrection(CorrectionSource(dictation))` → `CorrectionWindowController.show(source:)` creates a `CorrectionModel(source:config: await store.load(), deps:)` and orders the window front (activation policy regular, `EditMenu.ensure()`).

**Correct from History.** `HistoryView` Correct… → `HistoryListModel.correct(row)` → `deps.correct(CorrectionSource(text: row.text, appName: row.appName, bundleID: row.bundleID))` → same window.

**In the window.** Selection change → snap (5.5) → `heard`, `write = heard`, `soundsLike = heard`. Any draft change → `draftRule` → `preview = CorrectionApplier(rules: [draftRule]).apply(to: transcript)`; `error = CorrectionValidator.validate(draftRule, against: config.corrections, excluding: nil)`; impact task cancelled and restarted: `entries = await deps.historyEntries()` (nil when retention is 0) → `ImpactPreview.compute`. Copy → `deps.pasteboard.write(preview.text)`, `tallyOnce()`. Save → if `error` show it; else `try await store.update { $0.corrections.append(draftRule); if !tallied { $0.correctionTally = CorrectionTally.incremented(...) } }` → `saved = true` → confirmation state. `tallyOnce()` outside Save runs its own `store.update` on the tally only. Cancel → close, no write. Done → close.

**Settings.** `CorrectionsEditorModel` mirrors `ProfilesEditorModel`: `rows` from `rules`, `selection`, `edit(id) { mutate }` → validate → persist via `store.update { $0.corrections = rules }` or set `error`. Remove → persist. Enabled switch → persist. `tallyRows = CorrectionTally.top(config.correctionTally, limit: 5, rules:)`; Remember… → `deps.openCorrection(CorrectionSource(phrase:))`. `hintRows = HintReport.report(rules:vocabulary:support: HintSupport.speechAnalyzer)`. `AppDelegate.apply(config)` → `settings?.model.refresh(from: config)` → `SettingsModel.config = config; vocabulary.replace(terms:); corrections.refresh(config)`.

**Measurement.** `HintMeasurementTests` reads the manifest, builds `CorrectionSnapshot` from it, and for each available engine runs every clip twice: once with `RecognitionHints.none`, once with `HintResolver.resolve(snapshot, bundleID: nil)`; audio is fed from `AVAudioFile` as in `SpeechAnalyzerLiveTests`; batch runs through `OpenAIClient.transcribe(wav:prompt:)`. It writes the markdown report and, for SpeechAnalyzer, prints the verdict the implementer applies to `HintSupport.speechAnalyzer` and the README.

### 5.5 Failure and edge cases

- **Selection snapping.** Expand the selection's start backwards and end forwards while the adjacent character is a letter, mark, digit or underscore; then trim whitespace. An empty or whitespace-only selection leaves Heard empty and Save reports "Select the misheard phrase first."
- **Validation messages.** Empty Heard: "Select the misheard phrase first."; empty Write: "Enter the spelling to write."; no change: "Nothing to remember — Write is the same as Heard."; duplicate: "‘eefa’ is already remembered for Slack as ‘Aoife’." Case-only fixes pass.
- **Save failure.** `ConfigStore.update` throws before it updates its cache or yields a change, so the previous rules stay in effect; the window shows `AnyError(error).description` under the form, keeps the draft, and does not enter the confirmation state. Settings edits behave the same and keep the unsaved field value.
- **No bundle ID.** Scope is forced to All apps; Save with This app is impossible.
- **History off.** The window still opens from the menu (the last dictation is in memory); the impact line shows the fixed sentence; Correct… from History is moot because there are no rows.
- **App switch between press and release.** Streaming hints were for the press app and cannot be withdrawn; batch terms, cleanup pairs and the applied rules follow the release app; a previous app's rules do not fire.
- **Config edited mid-recording.** Ignored for that recording (snapshot); applies from the next press.
- **Release before `startStream`.** Snapshot built from the release config; no hints were sent because no engine started.
- **Overlaps.** "get hub actions" with rules `get hub → GitHub` and `get hub actions → GitHub Actions`: the longer wins. Same-length app and global candidates: app wins. Equal length and scope: stored order.
- **Inside a longer word.** `chari` does not match `charity`; `mark` does not match `bookmark`.
- **Possessives and punctuation.** `eefa's` matches `eefa` (apostrophe is a boundary) → `Aoife's`. A Heard containing punctuation (`e-mail`) matches literally.
- **Hint caps.** SF and SpeechAnalyzer: first 100 in resolver order, so app-scoped rules are never the ones dropped; the report lists the skipped terms. Speechmatics: entries over 6 words skipped with reason; a `sounds_like` over 6 words is dropped from its entry silently in the payload but listed in the report. OpenAI: characters stripped; a term that becomes empty is skipped and reported.
- **AnalysisContext rejected.** `setContext` throwing is logged and analysis continues without hints; the engine never fails for hints.
- **Empty hints.** Every request shape is unchanged; the existing adapter fixture tests keep passing untouched.
- **Batch `prompt` and an empty instructions file.** `prompt` = the vocabulary line alone; both empty → no `prompt` part.
- **Cleanup off or no key.** Rules still apply to the raw text; the cleanup blocks are simply never composed.
- **Stale job.** Checkpoints unchanged; a stale job applies no rules because it never reaches that line.
- **Tally overflow.** 201st distinct phrase evicts the lowest-count, then oldest entry. Correcting the same phrase twice in one window counts once.
- **Remember… from the tally.** Window opens with the phrase as the whole transcript, preselected; scope All apps; the impact preview counts entries containing the phrase across all apps.
- **Rule whose Write equals another rule's Heard.** Both apply in one pass over the original text; no chain.
- **Disabled rule.** Excluded from matching, hints, cleanup blocks, the tally's `hasRule`, and the report counts.
- **Settings open while the window saves.** The AppDelegate consumer refreshes the table; the Settings model's own pending text field edits are not overwritten because refresh replaces model state, not the SwiftUI drafts, which recommit on Return.
- **Two writers of config.json.** The Python app and this app already race on `usage`; the new keys add no new exposure. A lost rule edit is visible in the table and can be redone.

### 5.6 Security

- Rules, variants and vocabulary are user-typed data in a user-owned file; they are not secrets, and they are never logged (R26). Log lines carry counts only.
- Everything sent to a provider is encoded by `JSONEncoder` (WebSocket adapters) or as a multipart text part (`prompt`); no string concatenation into JSON. OpenAI keywords have the four forbidden characters removed before encoding.
- Regex construction escapes every token with `NSRegularExpression.escapedPattern(for:)`; a phrase can never become a pattern. Pattern compilation failures are impossible for escaped literals but are handled by dropping the variant and logging a count.
- The cleanup prompt embeds phrases as quoted data under a fixed heading; a user could write "ignore previous instructions" as a Write term and it would reach the cleanup model exactly as a vocabulary term already can. Same trust model as `prompt.txt`.
- No hint ever appears in a URL (ElevenLabs is out of scope), so nothing new reaches HTTP logs.
- The correction window reads history entries into memory for the impact preview and writes only to the pasteboard (Copy) and `config.json` (Save). It never posts key events.
- Keychain access is unchanged; the measurement suite reads provider keys from the environment exactly as the existing integration tests do and never writes them anywhere.

### 5.7 Performance

- `HintResolver` and `CorrectionResolver` are O(rules) at press and release; `CorrectionApplier` compiles one regex per variant once per job and scans a dictation-sized string; hundreds of rules stay well under a millisecond.
- The impact preview runs `HistoryStore.entries()` (already in memory, bounded by retention to thousands of lines at most) through one applier on a background task, cancelled on the next draft change.
- Press latency: one extra `frontmost()` call (already made at release today) and the resolver; no I/O added on the press path.
- Hint serialisation caps bound payload sizes (100, 1000 entries); config growth is bounded by the tally cap and by the user's own rule count.

### 5.8 Observability

- `Log.pipeline` info: `corrections: N replacement(s) from M rule(s)` after application when N > 0; `Log.stream(<engine>)` info: `hints: N sent, K skipped` at engine start; `Log.config` error on a failed rule or tally write; `Log.ui` error when the impact preview or Copy fails. No phrases, ever.
- User-visible: the Settings Recognition hints group is the live report of what each engine gets; the correction window's validation line and error line; the confirmation state.
- The measurement reports under `features/feature-v2-Remembered-corrections/measurements/` are the record of the hint effect per engine.

### 5.9 Compatibility / migration

- Two new `config.json` keys with empty defaults; no migration. Older builds of this app carry them in `extra`; the Python app carries them as unknown dict keys.
- The batch request changes from `instructions` to `prompt`. Users with a customised `transcribe_prompt.txt` see its text reach the model for the first time; the README's release note says so.
- `UIEvent.result` changes its payload; the only consumers are `UIEventRouter` and the pipeline tests.
- `Transcriber.transcribe` renames its parameter; conformers are `OpenAIClient`, `KeyedOpenAIClient`, `FakeTranscriber` and two test-local stubs.
- `EngineProvider.make` and `SpeechAnalyzerAPI.makeSession` gain a parameter; conformers are `EngineFactory`, `FakeEngineProvider`, `SpeechAnalyzerBridge`, `FakeSpeechAnalyzerAPI`.
- Rollback: disabling or deleting rules restores today's output; removing the keys from `config.json` is safe.

### 5.10 Testing strategy

Every component below is tested without the rest of the feature running; every duration stays on `VirtualClock`.

- **MWConfig** (`ConfigCodingTests`): decode a config with rules and tally into typed values; defaults for missing `id`, `sounds_like`, `enabled`; round-trip; both keys absent from `extra`; R4 validation (empties dropped, duplicates keep first); unrelated keys survive a rules edit through `ConfigStore.update`; explicit `null` bundle_id.
- **MWCorrections** (`Tests/MWCorrectionsTests/`): `PhraseKey` (NFC, whitespace, case); `CorrectionResolver` (scope filter, app-over-global for the same key, disabled excluded, stored order); `PhraseMatcher` (word boundaries, Unicode letters, inside-word non-match, whitespace runs, punctuation literal, case-insensitive, possessive); `CorrectionApplier` (single replacement, multiple, overlap longest-wins, same-length app-wins, stored-order tie, no cascade, case-only fix, empty rules → identity, replacements count); `CorrectionValidator` (each error, case-only allowed, exclude-self on edit); `HintResolver` (order, dedupe keeping first spelling, pronunciations map, disabled and other-app excluded, empty → `.none`); `HintSerializer` (SF cap 100 with skipped list, OpenAI character stripping and empty skip, Speechmatics 1000 cap, 6-word skip, 4000-char skip, sounds_like drop, order preserved); `HintReport` (rows, counts, states, ElevenLabs not-sent, SpeechAnalyzer state from constant); `CorrectionTally` (increment, first spelling kept, cap 200 eviction order, top-5 ordering, `hasRule` across heard and variants); `ImpactPreview` (scope filter, counts, three snippets, nil entries); `PromptSections` (exact strings, omission when empty).
- **MWProfiles** (`PromptComposerTests`): `transcribePrompt` and `cleanupPrompt` exact output with and without terms, pairs and vocabulary.
- **MWTranscription** (`OpenAIClientTests`): multipart parts are `file, model, response_format, prompt`; `prompt` omitted when empty; `instructions` never present; value verbatim.
- **MWStreaming**: `SFSpeechEngineTests` — request options carry the capped contextual strings, empty hints leave `contextualStrings` empty; `SpeechAnalyzerEngineTests` — fake API receives the strings per session, empty → `[]`, a throwing `setContext` stand-in leaves the engine running; `CloudAdapterTests` — OpenAI `session.update` with `keywords` (exact JSON) and unchanged without; Speechmatics `StartRecognition` with `additional_vocab` (exact JSON, sounds_like arrays, vocabulary entries) and unchanged without; ElevenLabs unchanged with hints; `EngineFactoryTests` — hints reach each engine type (observable through the fakes and adapter open messages).
- **MWPipeline**: `DictationControllerTests` — frontmost captured at press before `.starting` completes; snapshot taken at press and unchanged by a config edit before release; provider receives hints resolved for the press app; release with a different frontmost app passes the release target and the press snapshot into `ProcessingInput`; release before `startStream` falls back to the release config. `ProcessingJobTests` — corrected text reaches paster, history and `.result` on the streamed path with cleanup off and no key; on the batch path; on the cleanup path (rule applied to the cleaner's output); nil bundle ID applies global rules only; app switch excludes the previous app's rules; no matching rule → identity; `.result` carries name and bundle ID; transcribe prompt and cleanup prompt contain the resolved terms and pairs; stale checkpoints unchanged.
- **App** (`AppTests`): `MenuModelTests` — Correct Last row absent then inserted at index 3, single instance, `lastDictation` stored; `CorrectionModelTests` — snapping (partial word, whitespace, empty), prefill and reset on reselect, preview, each validation message, scope default with and without bundle ID, Save persists exactly one rule with the chosen scope and increments the tally once, Copy writes the preview and increments the tally once, Copy then Save counts once, Cancel writes nothing, save failure keeps the draft and shows the error, impact with entries in and out of scope, history off; `CorrectionsEditorModelTests` — rows, edit persists, validation blocks the write and shows the message, disable, delete, tally rows and `hasRule`, hint rows, `refresh(config)`; `HistoryListModelTests` — Correct… passes the row's text, app name and bundle ID; `SettingsModelTests` — `refresh(from:)` updates vocabulary and corrections.
- **Integration (opt-in)**: `HintMeasurementTests` (5.4) gated on `MW_INTEGRATION=1` and `MW_HINT_AUDIO_DIR`; `OpenAIIntegrationTests` updated to the `prompt` parameter so a live run also proves the server accepts the request.
- **Manual (Stage 5 of the plan)**: menu → window → Save → next dictation to the same app is corrected; a dictation to another app is not; History Correct…; disable and delete; Settings refresh while the window saves; keyboard navigation; history off; on-device engine without a cloud key with cleanup off.

## 6. Alternatives considered

- Rules only, no engine hints — rejected: hints are the half that reduces the mistake at source; the rule alone hides it.
- Global-only or profile-scoped rules — rejected: a fix for Slack would rewrite Terminal; most apps have no profile, and History already stores bundle IDs.
- Hints carrying the correct spelling only — rejected in favour of Write plus Heard plus variants: steering the recognizer to a known form is what lets the deterministic rule fire; the cost is hint slots.
- Automatic sounds-like derived silently from Heard — rejected: an explicit, prefilled, editable field keeps what is sent visible.
- Switching the SpeechAnalyzer engine to DictationTranscriber — rejected: the only documented hint route on macOS 26, but it changes the recognizer module for every macOS 26 user; the measurement decides whether the undocumented AnalysisContext path is kept instead.
- Custom language models for SFSpeechRecognizer — rejected for this version: a model preparation step, a model file and X-SAMPA pronunciations for a personal list of terms that contextual strings already cover.
- Keeping the undocumented `instructions` field beside `prompt` — rejected: it may be ignored or rejected, and the documented field carries the same text.
- Committing the measurement audio to the repo — rejected: voice recordings would sit in git history; an untracked folder plus a committed numeric report keeps reproducibility where it matters.
- Sheet on History plus a window from the menu — rejected: two hosts for one view; one reusable window mirrors Settings and History.
- Vocabulary pane as an inline-editable table or as a Terms/Corrections segmented view — rejected (mockups `mockup-v2-vocab-inline-table.html`, `mockup-v2-vocab-segmented.html`): the detail form reuses the profiles editor pattern one-for-one.
- Informational-only tally — rejected: Remember… seeding the correction window costs one dictation less and adds no new entry form.
- Taking the selection exactly as dragged — rejected: a partial-word rule can never match; snapping outward makes every saved rule fireable.
- Placing the matching and hint code in `MWProfiles` — rejected: profiles resolve prompts; corrections are a distinct, larger responsibility, and a module with only `MWConfig` beneath it is testable without the pipeline.

## 7. Risks and issues

- **Ordinary-word collision** (medium likelihood, medium impact): a rule like `mark → Marc` rewrites correct text. Mitigated by whole-phrase matching, per-app scope, the impact preview before saving, and the Enabled switch.
- **SpeechAnalyzer hints have no effect** (high likelihood given Apple's docs, low impact): macOS 26 users get the local rule only. Mitigated by the measurement deciding the label, removing the dead path if so, and the README stating it.
- **Batch `prompt` changes output for existing users** (certain, low impact): `transcribe_prompt.txt` starts reaching the model. Mitigated by the release note and the unchanged default file text, which only asks for accurate punctuation.
- **Provider contract drift** (low likelihood per release, medium impact): field names or caps change. Mitigated by exact-JSON contract tests and the Settings report showing skipped hints.
- **Inconclusive measurement** (medium likelihood): a small clip set shows no clear gain on some engine. Mitigated by recording raw counts and shipping per-engine statements rather than a blanket claim; cloud runs cost the user's own credits and are opt-in.
- **Slot pressure on SFSpeechRecognizer** (low likelihood): three hints per rule reach 100 at about 30 rules plus vocabulary. Mitigated by app-first ordering and the report listing what was dropped; custom language models remain the recorded follow-up.
- **Selection UX in SwiftUI** (medium likelihood, low impact): a read-only selectable `NSTextView` bridged into SwiftUI needs care to report selection changes. Mitigated by keeping snapping and all rules in `CorrectionModel`, tested without the view.
- **Two apps writing `config.json`** (existing): the Python app and this app can race. No new exposure; a lost edit is visible and redoable.

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

- Single release, no feature flag: rules and hints are inert until the user remembers a correction, and manual vocabulary behaviour is unchanged except for reaching engines it never reached.
- Implementation order for `/feature-plan`: (1) `MWConfig` rule and tally coding and validation; (2) `MWCorrections` module registered in `Package.swift` and CLAUDE.md, component by component; (3) `MWProfiles` prompt composition and `MWTranscription` `prompt` field; (4) `MWPipeline` snapshot, hints, application and `DeliveredDictation`; (5) `MWStreaming` engine and adapter hints; (6) App: menu, History action, correction window, Settings; (7) measurement suite, run it, set `HintSupport.speechAnalyzer` and remove the AnalysisContext path if unavailable; (8) README and CHANGELOG.
- Verification before release: full core and app test suites green; the measurement reports committed under `measurements/`; the manual flows in 5.10 exercised on the built app.
- Rollback: disable or delete rules in Settings, or remove the two keys from `config.json`; the batch `prompt` field is the documented one and needs no rollback.
- Communication: CHANGELOG entry under Unreleased naming per-engine support, the `prompt` change and the new config keys; README Privacy section gains one line on rules and tally being stored locally in `config.json`.

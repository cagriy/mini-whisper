# Remembered corrections — implementation plan

Date: 2026-09-05
Status: Superseded. This early sketch became
`features/feature-v2-Remembered-corrections/`, which shipped in v0.3.0.
Selected by the user: improvement 2 from the dictation review.

## Outcome and scope

The user corrects a recurring name or technical phrase once, remembers the pair,
and subsequent dictations benefit from both recognition hints and an explicit
local correction rule. Existing manual vocabulary continues to work.

This plan implements explicit learning, editable app-scoped/global rules, supported
streaming vocabulary hints, and consistent batch/cleanup handling. Background
monitoring of edits in other apps, project-folder detection, language-model
training, and general voice editing are future work.

## User flow

1. Choose **Correct last dictation…** from the menu, or **Correct…** on a History row.
2. Select the mistaken word/phrase in the displayed transcript and enter its correct
   spelling. Show a preview of the corrected transcript. The action edits a phrase,
   not a general-purpose rewrite.
3. Choose **Remember this correction**, with **This app** selected by default when
   the original app has a bundle ID. **All apps** is an explicit alternative. With
   no bundle ID, require an explicit global choice to remember a rule.
4. Saving remembers the pair and offers **Copy corrected text**. It does not try to
   overwrite an earlier paste or submit a message. Cancel saves nothing. Correcting
   without remembering only produces the corrected text for this operation.
5. Settings → Vocabulary shows the existing terms and a corrections table: Heard,
   Write, Scope, and Enabled. Rules can be edited, disabled, or deleted.

The dialog explains that a remembered rule replaces exact phrase matches in future
dictations within its scope. A recognition hint is probabilistic; the local rule
is deterministic. Existing historical entries remain as originally delivered.
The last delivered transcript and app identity are kept in memory, including when
history is off; saving an explicit rule stores only the phrase pair and scope,
not a new transcript or audio recording.

## Behavior decisions

- Persist `corrections` alongside the existing `vocabulary` array in Config. Each
  record has a stable ID, source phrase, replacement, optional bundle ID (nil means
  global), and enabled flag. Old configurations default to no corrections.
- Trim and normalize Unicode for matching; preserve the replacement's chosen
  spelling and case. Reject empty phrases and exact no-ops; allow case-only fixes.
  Reject conflicting duplicates within one scope with a visible validation error.
- Match literal whole phrases with Unicode-aware boundaries, case-insensitively,
  allowing whitespace variations between words. Escape punctuation as literal data.
  Do not match inside longer words/identifiers or perform fuzzy replacement.
- Resolve a source phrase's app rule before its global rule. For overlapping
  different phrases, prefer the longest match, then stable stored order. Apply one
  pass over the input; inserted text is never rescanned, so chains cannot cascade.
- Apply local rules once to the final transcript after optional cleanup and before
  paste/history. Test identical behavior for streamed, batch, cleanup-off, and
  key-free paths. Do not mutate volatile captions with replacement rules.
- Feed correct spellings, not mistaken spellings, as recognition vocabulary.
  Supply applicable source→replacement pairs to cleanup as delimited data.
  Never interpret either phrase as a cleanup instruction or regex.
- Keep a single immutable vocabulary/correction snapshot per recording, captured
  with the starting app before asynchronous engine selection. Global plus starting
  app hints go to streaming. Paste target and cleanup profile remain resolved at
  release. Batch hints and final corrections use the release app against that same
  snapshot; switching apps excludes the previous app's replacement rules. Starting
  app hints already sent to a recognizer cannot be withdrawn retroactively.
- Edits while recording affect the next recording. Resolve nil app IDs to global
  rules only. Keep ordinary profile selection, hotkeys, and submit behavior intact.
- Persist before reporting success. On write failure, retain the user's draft,
  display the error, and keep the previously persisted rules in effect. Route
  Settings refresh through the existing AppDelegate config-change consumer; do
  not add competing consumers to ConfigStore's single AsyncStream.

## Recognition capability plan

Verified against official documentation on 2026-09-05. Recheck limits when coding.
Do not change the selected engine or model to obtain hint support.

| Path | Implementation | Constraints / verification |
| --- | --- | --- |
| SFSpeechRecognizer | Extend RecognitionOptions and SFSpeechEngine; set request.contextualStrings in the native bridge. | Up to 100 short phrases; preserve on-device requirement. [Apple](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings) |
| SpeechAnalyzer + current SpeechTranscriber | Retain engine; support local final corrections and optional cleanup vocabulary. | Apple's AnalysisContext hint documentation describes DictationTranscriber. Verify the installed SDK and native behavior before claiming support for SpeechTranscriber; absent evidence, show recognition hints as unavailable for this engine. [Apple](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings) |
| OpenAI Realtime, gpt-live-transcribe | Add keywords in session.audio.input.transcription. | Exclude invalid keyword characters and line breaks from the provider payload, preserving stored terms. Keep existing session behavior. [OpenAI](https://developers.openai.com/api/docs/guides/realtime-transcription) |
| Speechmatics | Add transcription_config.additional_vocab content entries. | Up to 1000 phrases; apply documented length limits. Do not assume a misrecognition is a pronunciation and automatically send it as sounds_like. [Speechmatics](https://docs.speechmatics.com/speech-to-text/features/custom-dictionary) |
| ElevenLabs Scribe v2 Realtime | Optional keyterms via URLComponents and repeated query items. | Maximum 50 keyterms, 20 characters each. Default paid recognition hints off; retain local correction support. Show cost effect beside the option and account for it per recording. [Limits](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/keyterm-prompting), [20% premium](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime) |
| Batch OpenAI, gpt-4o-mini-transcribe | Compose applicable vocabulary into the documented prompt multipart field. | Existing code writes instructions; add a request-contract regression test and use the documented prompt field for this model. Keep the existing model. [OpenAI](https://developers.openai.com/api/docs/guides/speech-to-text) |
| Cleanup | Extend PromptComposer with applicable vocabulary and correction pairs. | Honor cleanup-off and key-free operation. Local rules must not depend on a network request. |

Create a deterministic provider hint resolver: app-specific replacements first,
then global replacements, then existing manual vocabulary; deduplicate while
preserving display spelling and stable order. Enforce each provider's own limits
at serialization, not by destroying saved terms. Report unsupported/skipped hints
in Settings without showing repeated recording-time alerts. Empty hints preserve
existing streaming payloads. URLs containing keyterms must never be logged.

## Implementation stages — mandatory TDD

For every behavior below: write a focused test, run and record the expected failure,
implement only after observing it, then run the focused test and surrounding suite.
An unrelated compiler failure or environment error does not establish the required
behavioral red. Record commands and red/green results in an implementation log.

### 0. Establish the baseline

Run current core and AppTests suites before edits. Record test counts, failures,
and skipped integration tests. Confirm the Xcode scheme and native SDK. Inspect
SpeechTranscriber hint support and confirm provider request contracts above.
Baseline results are not yet collected; this document is a plan only.

### 1. Persist and resolve correction rules

Files: MWConfig/Config.swift, new MWConfig/CorrectionRule.swift; new resolver and
matching types in MWProfiles; MWConfigTests and MWProfilesTests.

First red: decode a config with a remembered pair and assert it is available as an
active typed correction and selected by the resolver. A JSON round-trip alone is
insufficient: Config already preserves unknown keys. After minimal type scaffolding,
observe a failing behavioral assertion before implementing decoding/resolution.
Then test persistence round-trip, legacy config preservation, stable IDs, unknown top-level keys,
validation, case-only fixes, Unicode, duplicates, app/global precedence, disabled
rules, whitespace, punctuation, overlapping phrases, and non-cascading replacement.
Add persistence-error tests and verify unrelated config fields survive updates.

### 2. Carry context and apply corrections in the pipeline

Files: MWPipeline/ControllerState.swift, DictationController.swift,
ProcessingInput.swift, ProcessingJob.swift; MWProfiles/PromptComposer.swift;
MWPipelineTests and MWProfilesTests.

First red: with cleanup disabled and a fake stream returning a remembered mistaken
phrase, expect the corrected text to reach the paster and history. Then cover
batch fallback, no key, no matching rule, empty configuration, staleness, and
paste-submit. Test capture-time snapshots, settings changes during recording,
app switching, and nil bundle IDs with fakes and VirtualClock.

### 3. Connect hints to recognizers and actual requests

Files: MWStreaming/EngineProvider.swift, EngineFactory.swift, SFSpeechEngine.swift,
SpeechRecognitionAPI.swift, SFSpeechRecognitionBridge.swift, cloud Adapters;
MWTranscription/OpenAIClient.swift; corresponding fakes and test suites.

First reds, separately: fake native request receives contextualStrings; serialized
OpenAI session contains keywords; Speechmatics session contains additional_vocab;
batch multipart contains prompt with the resolved terms. Test empty hints, caps,
invalid characters, deterministic order, downgrade paths, and exact serialization.
Keep the SpeechAnalyzer protocol unchanged unless support is positively established.

For optional ElevenLabs hints, first prove the opt-out omits keyterms and opt-in
encodes them correctly, including Unicode and reserved URL characters. Extend the
recording's usage metadata and MWUsage/Pricing as necessary so the 20% premium
applies only when nonempty keyterms were actually sent, including failed/discarded
streams and configured pricing overrides. Test this before enabling the UI option;
record whether an override is the base rate (apply the premium once).

### 4. Build correction entry and management

Files: App/MenuModel.swift, StatusItemController.swift, UIEventRouter.swift,
AppDelegate.swift; App/History; App/Settings/VocabularyModel.swift,
VocabularySection.swift, SettingsModel.swift; new correction editor model/view.

First reds in AppTests: Correct last is unavailable until a delivered result;
opening its editor uses that result's app identity; remembering persists precisely
the selected phrase pair and scope; cancel writes nothing. Test preview selection,
case-only edits, no-history operation, Copy without remembering, nil bundle IDs,
validation and save failures, edit/disable/delete, and Settings reflecting changes
made through the correction dialog. Model tests precede view wiring.

Add a metadata-bearing last-result value/event instead of inferring the old app
from the currently focused window. Reuse it for menu actions; history rows use
their recorded app identity. Use the existing pasteboard seam for Copy and never
invoke the paste-submit path from the editor.

### 5. Verify finished behavior and document it

Run all core tests and the app test suite/build, inspect the complete diff, and
exercise menu → correction dialog → remember → next dictation → disable/delete.
Verify History entry correction, keyboard navigation, long phrases, scope labels,
save-error presentation, and history-off behavior in the built UI. Test a native
on-device dictation without a cloud key and with cleanup off.

Use a small repeatable audio set with names, acronyms, accents, and ordinary-word
negative controls. Compare hints off/on using identical audio and engine settings;
measure correct target-term recognition and false corrections separately. Fakes
prove wiring, not speech accuracy. Live provider checks are opt-in with configured
credentials; report any missing live evidence and do not claim universal accuracy.

Update README and CHANGELOG with actual per-engine support, local storage behavior,
scope semantics, and paid hint behavior. A native SpeechTranscriber engine without
verified hint support must remain accurately labeled.

## Commands and completion evidence

Run from repository root unless specified:

```sh
# Baseline and final core regression run
swift test --package-path Packages/MiniWhisperCore

# Per-change red/green examples; narrow to a test name where appropriate
swift test --package-path Packages/MiniWhisperCore --filter MWConfigTests
swift test --package-path Packages/MiniWhisperCore --filter MWProfilesTests
swift test --package-path Packages/MiniWhisperCore --filter MWStreamingTests
swift test --package-path Packages/MiniWhisperCore --filter MWPipelineTests
swift test --package-path Packages/MiniWhisperCore --filter MWTranscriptionTests
swift test --package-path Packages/MiniWhisperCore --filter MWUsageTests

# Regenerate for new App source files, then run the actual app tests/build
xcodegen generate
xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd test
xcodebuild -project "Mini Whisper.xcodeproj" -scheme MiniWhisper -destination 'platform=macOS' -derivedDataPath .dd build
git diff --check
git diff --stat
git status --short
```

Use Swift Testing's final test-run summary, not the preceding empty XCTest summary.
For each implemented stage, record the observed failing test, green test result,
and regression coverage. The final report includes build results, manual flows
actually exercised, native/provider checks performed or skipped, and limitations.
Review new untracked files as well as tracked diffs. No stage is complete solely
because its code compiles.

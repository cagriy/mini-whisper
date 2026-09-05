# Remembered corrections — Brainstorm v2

**Status:** Draft
**Date:** 2026-09-05

## 1. Summary
Mini Whisper users dictate the same names, acronyms and project terms into many apps, and the recognizer gets some of them wrong every time. Today the only recourse is a hand-maintained vocabulary list that reaches the batch transcription instructions and the cleanup prompt but never the streaming recognizer, and that cannot express "when you hear X, write Y". This feature lets the user correct a misheard phrase once, from the menu's last dictation or from a History row, and remember the pair as a rule scoped to the app it was dictated into or to all apps. Remembered rules are applied deterministically to every future transcript in scope, on every engine and path, and their correct spellings are fed to the configured recognizer as hints where the engine supports them. It is the follow-up the v1 storm deferred as "automatic or edit-driven vocabulary learning", selected from the 2026-09-05 dictation improvements review, and now is the moment because v1 has shipped (v0.2.0) with the profiles, history and vocabulary the feature builds on.

## 2. Goals
- A phrase the user corrected and remembered is replaced in the next dictation delivered within its scope, whether the transcript came from a streamed engine, batch fallback, with cleanup on or off, and with no cloud key configured.
- A rule scoped to This app never changes a dictation delivered to a different app; a rule scoped to All apps changes dictations delivered anywhere.
- Every remembered rule is visible in Settings → Vocabulary and can be edited, disabled or deleted there, with the change taking effect from the next recording.
- On each hint-capable engine (SFSpeechRecognizer, OpenAI Realtime, Speechmatics, batch OpenAI transcription, cleanup), the request actually sent carries the resolved terms, proven by a request-contract test.
- Before the feature is called complete, a fixed audio set of names, acronyms and ordinary-word controls is run with hints off and on per hint-capable engine, and the recognition delta and false-correction count are recorded.
- Correcting without remembering produces the corrected text for copying and stores nothing beyond the tally of corrections made.

## 3. Scope (in / out)
- **In scope:**
  - **Correct last dictation…** in the menu bar menu, available once a result has been delivered, and **Correct…** on each History row.
  - A correction dialog: select the mistaken phrase in the delivered transcript, type the correct spelling, preview the corrected transcript. Phrase edit only, not a general rewrite.
  - **Remember this correction** with scope **This app** (default when the dictation's destination has a bundle ID) or **All apps** (explicit). With no bundle ID, remembering requires the explicit global choice.
  - **Copy corrected text** after saving or after a one-off correction. Cancel saves nothing. The corrected text is never pasted or submitted on the user's behalf.
  - Persisted correction rules with Heard, Write, Sounds like (optional), Scope and Enabled, stored alongside the existing vocabulary in the shared config file. Old configs default to no rules.
  - Deterministic local replacement: literal whole phrases, case-insensitive with Unicode-aware boundaries, whitespace-tolerant, applied once to the final transcript after optional cleanup and before paste and history. Never applied to the live caption. Historical entries stay as delivered.
  - Settings → Vocabulary: the existing term chips plus a corrections table (Heard, Write, Sounds like, Scope, Enabled) with edit, disable and delete, and validation errors shown in place.
  - **Rule impact preview:** before saving, the dialog shows how many History entries the Heard phrase would have changed, with examples. Unavailable when history is off.
  - **Misheard-terms tally:** each correction made in the dialog, remembered or not, increments a count for its Heard phrase; Settings → Vocabulary shows the top phrases and nudges the user to remember recurring one-offs. No per-rule firing counts.
  - Recognition hints from correct spellings plus manual vocabulary: SFSpeechRecognizer contextual strings; OpenAI Realtime transcription keywords; Speechmatics custom dictionary entries with an explicit **Sounds like** field, prefilled from Heard and editable, sent only to Speechmatics; the documented prompt field of the batch OpenAI transcription request; source→replacement pairs and terms in the cleanup prompt as delimited data.
  - SpeechAnalyzer hints only if the installed SDK's transcriber is shown to accept them; otherwise Settings labels hints as unavailable for that engine and the local rule still applies.
  - Settings reports which hints an engine skipped or does not support, without recording-time alerts.
  - Per-engine caps and character rules enforced when the request is built, never by deleting stored terms.
  - Existing manual vocabulary keeps working unchanged.
  - README and CHANGELOG describe per-engine support, local storage, scope semantics and the probabilistic nature of hints.
- **Out of scope / deferred:**
  - ElevenLabs keyterms and the 20% premium they carry, including per-recording billing of that premium.
  - Creating a Heard → Write rule directly in Settings without a dictation.
  - Pasting corrected text back into the original app.
  - Profile-scoped rules (rules attached to a cleanup profile rather than a bundle ID).
  - A Correct affordance on the result overlay.
  - Per-rule firing counts and last-used dates in the table.
  - Applying rules to the live caption while recording.
  - Export or import of rules as a shareable file, and team term packs.
  - Automatic sounds-like derived silently from the Heard phrase.
  - Background monitoring of edits the user makes in other apps.
  - Project-folder or website detection as a scope.
  - Language-model training or fine-tuning on the user's corrections.
  - Voice editing of existing text.
  - Regex, wildcard or fuzzy rules; rules that chain or cascade.
  - Rewriting past History entries when a rule is added.

## 4. High-level technical direction
- The shared `config.json` remains readable and writable by the Python app: the Python app round-trips the whole file as a dict, so a new top-level key is safe, and this app must keep preserving keys it does not know.
- Bundle ID `com.ips.mini-whisper`, macOS 14 deployment target, Swift 6 strict concurrency and no third-party runtime dependencies, as for every feature.
- Rules are applied exactly once, to the final transcript, after optional cleanup and before paste and history; identical behaviour on streamed, batch, cleanup-off and key-free paths. Inserted text is never rescanned.
- The live caption is never mutated by rules.
- A single immutable vocabulary-and-rules snapshot per recording, captured with the starting app; hints for the starting app go to streaming, final corrections use the release app against that same snapshot. Edits during a recording affect the next one.
- App-scoped rules win over global rules for the same phrase; longer matches win over shorter; stored order breaks ties.
- Hints carry correct spellings, never mistaken ones (except Speechmatics sounds-like, which is explicit per rule). Neither phrase is ever interpreted as a cleanup instruction or a regex.
- Provider limits (SFSpeechRecognizer 100 short phrases; Speechmatics 1000 entries, 6 words each; OpenAI keyword character rules) are enforced at serialization; stored terms are never destroyed to fit.
- Secrets stay in the Keychain. Requests or URLs carrying hint terms are never logged.
- Persistence completes before success is reported; on write failure the draft is retained, the error shown, and the previously persisted rules stay in effect.
- Settings refresh flows through the existing config-change consumer; no competing consumers on the config store's stream.
- The measurement in §2 uses a small user-provided audio set; live provider runs are opt-in with configured credentials and their cost is the user's.
- Every duration and timing in the pipeline is tested on the virtual clock; TDD with an observed failing test before each implementation step.

## 5. Alternatives considered
- Rules only, no engine hints — rejected because hints are the half that reduces corrections at source; the local rule alone leaves the recognizer making the same mistake and only hides it.
- Global-only scope — rejected because a fix for a name misheard in Slack would also rewrite the same word in Terminal, and every dictation already knows its destination app, so scoping costs nothing new.
- Profile-scoped rules (attach rules to a cleanup profile) — rejected because most apps have no profile, so their rules would fall to Default, and a bundle-ID scope mirrors what History already stores.
- Automatic sounds-like from the Heard phrase on Speechmatics — rejected in favour of an explicit, prefilled, editable field: a misrecognition is often but not always a pronunciation, and the user should see and control what is sent.

## 6. Risks
- An ordinary word matching a rule (mark → Marc) silently rewrites correct text. Impact: wrong output the user may not notice. Mitigated by whole-phrase matching, per-app scope, the impact preview and the Enabled toggle.
- The default engine on macOS 26 (SpeechAnalyzer) may accept no hints. Impact: users on the newest OS get the local rule only, and the README must say so rather than imply parity.
- Provider hint contracts drift (field names, caps, character rules). Impact: hints silently dropped or requests rejected. Mitigated by request-contract tests and Settings reporting skipped hints.
- The before/after measurement may show no significant recognition gain on some engines. Impact: the feature ships with documented limits per engine instead of a blanket accuracy claim; cloud runs cost money.
- A user with history off still accumulates a tally of corrected phrases and stored rules. Impact: user-typed phrases persist on disk when transcripts do not; documented as vocabulary-like data.
- Two apps writing the same `config.json` (this app and the Python app) could race on the new key. Impact: a lost rule edit; same exposure as every existing key.

## 7. Open questions for design
- Whether the installed SDK's SpeechTranscriber accepts contextual hints, verified against the native API before any label is written; if not, how Settings labels the engine.
- How the last delivered result carries its app identity (name and bundle ID) to the menu action without inferring it from the currently focused window, including when history is off.
- The exact matching engine: Unicode boundary definition, whitespace tolerance, punctuation handling, and the precedence rule for overlapping phrases.
- Validation rules for a rule: empty phrases, exact no-ops, case-only fixes (allowed), duplicates within one scope, and how conflicts are shown in the dialog and the table.
- Where the misheard-terms tally is stored and how it is bounded (user leaned toward a small per-phrase count kept with config, but did not commit).
- How the impact preview is computed and presented when History holds many entries, and its wording when history is off.
- The shape of the measurement harness: audio set format, per-engine on/off runs, how results are recorded in the repo.
- Per-provider hint serialization: ordering, deduplication with manual vocabulary, cap handling, invalid-character stripping, and the exact request fields for each engine.
- How the dialog selects a phrase (text selection versus word tap) and previews the corrected transcript.
- Whether a remembered rule also appears as a manual vocabulary chip or stays only in the table (user leaned toward separate table, resolver merges).

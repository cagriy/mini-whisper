# Persistent Speaker Recognition — Brainstorm v8

**Status:** Draft
**Date:** 2026-11-20

## 1. Summary

Meeting speakers are numbered afresh in every meeting, and a name given to "Speaker 2" is forgotten when the meeting ends; only the user is recognised, and only in remote calls. This feature makes Mini Whisper remember the people the user names and name them in later meetings. It has two opt-in routes, chosen by the meeting engine: Speechmatics voice identifiers under the two Speechmatics engines, and a bundled local voice model (WeSpeaker) under the two AssemblyAI engines. Recognised names appear in the transcript as applied names or as suggestions, depending on how sure the match is, and the user stays in control through accept, dismiss and the existing rename. It is for anyone who meets the same people repeatedly, and it follows up what v4 deferred as "automatic speaker recognition across meetings".

## 2. Goals

- A person named in one meeting is named, or suggested by name, in a later meeting under the same provider without the user typing the name again.
- No name is written into a summary, an export or an MCP result unless it was applied as a sure match or accepted by the user.
- Both routes are off until the user turns them on, and with both off the app behaves exactly as it does today.
- The user can see everyone the app remembers and forget one person or everyone from one place.
- On the local route no voice data leaves the Mac.
- The app credits WeSpeaker and every other bundled third-party component in a credits window.

## 3. Scope (in / out)

- **In scope:**
  - Two toggles under Settings › Meetings › Engine, both off by default: Speechmatics voice identifiers under the Speechmatics engines, the local voice model under the AssemblyAI engines. Layout is settled at mockup.
  - Recognition in remote and in-room meetings, including recognising the user in the room.
  - Learning on every rename while a toggle is on; the rename popover says the voice will be remembered. A rename learns the voice during the meeting or after Stop.
  - Each meeting keeps its speakers' voice data (vectors or identifiers, never audio) until the meeting is deleted or the data is removed from the People list.
  - Local-model names by confidence: a sure match is applied as a normal name with "Not Alice" on hover; a less sure match is a marked suggestion with visible accept and dismiss; anything weaker stays "Speaker N".
  - Speechmatics names by history, since it returns no score: a person's first match is a suggestion; once accepted, that person's later matches are applied with "Not Alice" on hover.
  - A manual rename always wins. Clicking a name still opens the rename popover, which is the edit path.
  - An unaccepted suggestion stays "Speaker N" in summaries, exports and MCP results. Accepting it later updates the transcript and exports; the summary changes on Regenerate, as with a manual rename today.
  - One "Cautious to Eager" slider under the toggle, and an Advanced section with each raw number as its own slider: sure threshold, suggestion threshold, margin, minimum speech, buffer length, Speechmatics sensitivity. Sensible defaults.
  - A People list in Settings: view each remembered person, which engines know them and when last heard; rename; merge two people; forget one; forget everyone.
  - One store for both routes at `~/.config/mini-whisper/voices.json`. A person is learned separately by each provider.
  - Turning a toggle off stops matching and learning and keeps the People list.
  - A local log of each match's score and what the user did with it. Recorded only.
  - A credits window listing WeSpeaker (CC-BY-4.0, naming WeSpeaker, pyannote and Fluid Inference) and Sparkle.
  - The name-suggestion display built so that a second source can supply suggestions.
- **Out of scope / deferred:**
  - Naming speakers from what is said (introductions, a question to a name and its answer). Separate feature, v9, built on this version's suggestion display.
  - Enrolling voices from existing meetings' `audio.m4a`.
  - Back-filling earlier meetings when a person is named later.
  - People carrying over between providers, and cross-checking Speechmatics matches with the local model.
  - Reading the active speaker's name from the call app's window.
  - Agents naming speakers through MCP. The MCP server stays read-only.
  - A "Who is this?" review of recurring unnamed voices with audio clips. Future consideration.
  - Thresholds that tune themselves from the match log. Future development; the log is recorded from v8.
  - Recognition in test calls: a test call neither recognises nor learns voices, and recognition is not scored.

## 4. High-level technical direction

- Hard rules from the repository guide: no new third-party dependency (Sparkle remains the only one, and the core package stays dependency-free), macOS 14 deployment target, arm64, Swift 6 strict concurrency, every duration tested on a virtual clock. Settings live in `config.json`.
- The local model is `wespeaker_v2.mlmodelc` from FluidInference, about 8 MB, bundled as a resource and loaded with Core ML directly. No wrapper library.
- Measured on 2026-11-20 on macOS 26.6.1 with macOS synthetic voices:
  - Loads with plain `MLModel` in 0.1 to 0.6 s; 15 to 23 ms per call.
  - Same voice, different sentence: 0.88 to 0.92 cosine similarity. Different voices: 0.08 to 0.66.
  - The model takes one 10-second clip per call with three speaker masks. Only the first waveform row is read.
  - A short clip padded with silence does not separate voices (0.85 to 0.95 against other voices). Filled with the speaker's own speech it does (0.82 to 0.89 against itself, at most 0.56 against others). The window must be filled with real speech from that speaker.
  - Not yet run on macOS 14 or on real meeting audio.
- The provider keeps deciding who spoke when; the local model only answers whose voice a label is.
- On the local route, audio is used to compute vectors and then discarded. Vectors and the match log stay on the Mac.
- Speechmatics, from its documentation:
  - A match arrives as the enrolled name in the `speaker` field, with no score.
  - `speaker_sensitivity` is the only tuning; its range and default are undocumented.
  - Identifiers can be requested mid-session or at the end.
  - At most 50 identifiers per session, and fewer is recommended.
  - Identifiers are tied to the model that made them, and to the account and project; mismatched ones are ignored with a warning.
  - Whether `standard` and `enhanced` share identifiers is not stated.
- The voice store is a plain file beside `config.json`, chosen over an encrypted file, one file per person and the Keychain, because meeting audio of the same people already sits unencrypted in the same folder.
- New surfaces follow `DESIGN.md`.

## 5. Alternatives considered

- The local model under all four engines, with no Speechmatics identifiers — rejected because the brief wants the provider's own route under Speechmatics, which names a known voice from its first word. It would have given one behaviour, one store, and no dependence on Speechmatics model updates.
- Cross-checking each Speechmatics match with the local model to obtain a score — rejected as the most work; trusting a person's matches after their first accepted one gives a safety check without a second engine running.
- Context-based naming inside this version, at Stop or live — rejected because it shares only the suggestion display; it needs its own Claude call, prompt, cost line and ordering against the summary. It becomes v9.
- Always suggesting, or always applying, every match — rejected for confidence tiers: always suggesting costs a click per person per meeting, and always applying writes wrong names unprompted.

## 6. Risks

- Thresholds are unvalidated on real meeting audio. Only synthetic voices were measured, and published error rates are for clean interviews. Impact: wrong names applied, or known people left as "Speaker N", until defaults are calibrated on real recordings.
- A wrongly applied name can reach a summary or export before the user notices. Impact: a misattributed record. Limited by the strict sure tier and by suggestions never leaving the transcript view.
- Speechmatics identifiers stop working when Speechmatics updates its model or the account or project changes. Impact: everyone learned under Speechmatics is silently forgotten and must be named again.
- Speechmatics matches carry no score, so a bad identifier is caught only by the user at the first suggestion. Impact: later matches of that person are applied on trust.
- A voice learned on a call may not match in a room, and overlapping talk on one microphone blurs voices. Impact: in-room recognition is weaker than remote.
- Voice vectors and identifiers are biometric data about other people, kept in a plain file, and unnamed speakers' data stays with each meeting. Impact: a privacy exposure the user must be told about and able to clear.
- Diarization errors pass through: two people under one label give a blurred voice that matches nobody, or teaches a wrong voice on rename.
- Two different people with the same name collide in the People list.

## 7. Open questions for design

- Default values for the sure threshold, suggestion threshold, margin, minimum speech and buffer length, and how the "Cautious to Eager" slider maps onto them.
- Layout of the two toggles under the engine rows, the slider and the Advanced section, and what a toggle shows when its provider is not the active engine. Settle at mockup.
- How an applied name, a suggestion, and the accept, dismiss and "Not Alice" controls look in the live and finished transcript. Settle at mockup. (User leaned toward controls on hover for sure matches and visible ones for suggestions.)
- Where the People list and the credits window sit, and how they are reached.
- How the user's own voice is learned for in-room recognition: from the microphone in remote calls, from a rename in the room, or both.
- Which people are sent to Speechmatics when more than 50 identifiers are known, and how many identifiers are kept per person.
- What the app shows when Speechmatics ignores stored identifiers, and how those people are re-learned.
- Whether Speechmatics Standard and Enhanced share identifiers, and what happens on switching between them.
- How a 10-second window is filled from a speaker's turns, and how much speech is needed before the first match.
- What "Not Alice" and a rename onto another name do to stored voices: which vectors are removed, moved or added, and how many are kept per person.
- How people are identified in the store, given two people can share a name, and what merge does to their voices.
- The shape of the per-meeting voice data and of the match log, and when each is deleted.
- The wording that tells the user what is stored and where when a toggle is turned on.
- How recognition is kept off in test calls.
- Verification on macOS 14.

# Realtime streaming dictation — Brainstorm v1

**Status:** Draft
**Date:** 2026-09-01

## 1. Summary

Mini Whisper currently transcribes only after the user releases the hotkey: the whole recording is POSTed to the batch transcription endpoint, optionally cleaned up, then pasted. This feature makes dictation live — as the user speaks, transcribed text streams into a text area under the recording animation in the overlay, giving immediate feedback that the words are being heard correctly. The user chooses between two streaming engines in Settings: OpenAI's Realtime API (default) or Apple's on-device speech recognition. In both cases the compound streamed transcript is the final raw transcript — it goes straight to the cleanup model (if enabled) and is pasted, replacing the batch transcription call entirely when streaming is enabled.

## 2. Goals

- Transcribed text appears in the overlay, under the recording animation, while the user is still speaking (within ~1s of the words being said).
- The user can choose the streaming engine in Settings: Realtime API (default) or on-device; the option can be disabled entirely, restoring today's batch behaviour exactly.
- When streaming is enabled, only one transcription pass happens per dictation — the compound streamed transcript feeds cleanup (if enabled) and paste, with no additional batch call.
- A dictation never fails because of streaming: a realtime connection failure mid-recording falls back to the existing batch pipeline using the locally accumulated audio.
- Daily token-usage figures shown in the menu bar include realtime-session tokens.

## 3. Scope (in / out)

- **In scope:**
  - Settings: streaming toggle (on by default) and engine picker (Realtime API default / on-device).
  - Live text area under the recording animation in the overlay, active while recording when streaming is enabled.
  - Realtime API engine: audio streamed over WebSocket to OpenAI's realtime transcription mode; partial text displayed live; compound transcript → cleanup (if enabled) → paste.
  - On-device engine: Apple speech recognition partials displayed live; its compound transcript is likewise authoritative (fully offline, zero transcription cost); requires the macOS Speech Recognition permission, acquired when the engine is selected.
  - Fallback to the existing batch pipeline when the realtime connection fails or drops mid-recording (the recorder keeps accumulating audio locally regardless).
  - Realtime-session token usage counted into the daily usage totals.
- **Out of scope / deferred:**
  - Type-at-cursor streaming (partials typed directly into the active app).
  - Scratchpad confirm-before-paste (editable overlay text with explicit confirm).
  - Local dictation history (saved, searchable transcripts).
  - Live translation mode.
  - Voice editing commands ("scratch that", "new line", "send it").
  - Stream-response-only cut (streaming just the batch response after release) — superseded by full live streaming.

## 4. High-level technical direction

- Streaming engine one: OpenAI Realtime API transcription-only WebSocket mode (`intent=transcription`) with `gpt-4o-mini-transcribe` — verified available; partial text arrives as delta events. Same API key as today.
- Streaming engine two: Apple on-device speech recognition via pyobjc (consistent with the app's no-NIB, programmatic PyObjC approach); adds the Speech Recognition permission to the permission surface.
- The recorder's existing live tap must feed the streaming engine incrementally while continuing to accumulate audio locally for the batch fallback.
- The overlay remains the single recording UI; the text area extends it rather than adding a separate window (exact shape/size is a design/mockup decision).
- Cleanup behaviour is unchanged: it runs once, on the compound transcript, after recording completes.
- Existing behaviours preserved when streaming is disabled: batch pipeline, minimum-duration and silence gates, generation-based stale-result discard.
- Deliberately NOT detailed design — that lives in /feature-design.

## 5. Alternatives considered

- **On-device hybrid as the only approach** (local partials for display, batch API for final text) — rejected as the sole approach; instead both engines are offered, with the user choosing. The display-only variant of the on-device engine was also rejected: the user chose full finality (offline, free) over preserving batch-level accuracy.
- **Stream-response-only smaller cut** (stream the transcription response after release, no text while speaking) — rejected: does not deliver live feedback while speaking, which is the core of the feature.
- **Type-at-cursor streaming** (bold idea, weighed) — deferred: pasting revisions/corrections into arbitrary apps is fragile; the overlay text area delivers the feedback value without that risk.

## 6. Risks

- **On-by-default changes existing users' pipeline**: every current user is silently switched from batch HTTP to a realtime WebSocket session, with a different pricing model and new failure modes. Impact: surprise cost changes or behaviour regressions for users who never touched Settings.
- **On-device accuracy below the app's current bar**: users selecting the on-device engine get final text noticeably worse than `gpt-4o-mini-transcribe`. Impact: perceived quality regression attributed to the app rather than the engine choice.
- **Realtime transcript fidelity vs batch**: the realtime path segments audio by server-side turn detection; compound text may differ from what a single batch call over the same audio would produce (e.g. mid-utterance splits). Impact: occasional quality differences users notice after enabling streaming.
- **New permission friction**: the on-device engine's Speech Recognition permission adds a consent step outside the current onboarding flow. Impact: a confusing dead-end if the permission is denied and the app doesn't explain the fallback.

## 7. Open questions for design

- Overlay text-area shape, size, and behaviour (scrolling for long dictations, what shows during the post-release processing state) — to be settled via the design mockup step.
- How the recorder's hardware-rate float32 buffers are converted incrementally to the WebSocket's expected PCM16 format without disturbing the batch-fallback accumulation.
- Realtime session lifecycle: connect per dictation vs pre-connected/warm session, and how connection latency at hotkey press is hidden.
- Behaviour when the on-device engine completes but cleanup is enabled and the network is unreachable (user leaned toward: paste the raw transcript rather than fail, but didn't commit).
- How realtime usage events map onto the existing input/output token daily totals.
- Where the Speech Recognition permission request lives (on engine selection in Settings vs onboarding) and what happens on denial.

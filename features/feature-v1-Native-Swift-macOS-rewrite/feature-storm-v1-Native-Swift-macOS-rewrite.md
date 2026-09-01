# Native Swift macOS rewrite — Brainstorm v1

**Status:** Draft
**Date:** 2026-09-01

## 1. Summary
Mini Whisper (Python/PyObjC, v0.1.8, in `../mini-whisper`) is a menu-bar dictation app: hold or tap a hotkey, speak, and the transcript is pasted into the focused app, optionally cleaned by GPT-4o-mini, with a live caption bar fed by one of four streaming engines. We are rebuilding it as a native Swift macOS app that replaces the Python app in place — same bundle ID, config files, Keychain items, Homebrew cask and release pipeline — so existing users upgrade without noticing anything except speed. The rewrite is not a line-by-line port: it reproduces every user-visible behaviour of the source (with special care for the overlay animations and the edge cases catalogued during grounding), adopts a different audio-engine lifecycle because the source repo's own analysis (`docs/speed-improvements.md`) shows the ~0.5 s press→record delay is architectural and none of its six fixes were ever applied, corrects a set of latent defects that "feature-identical" would otherwise carry over, and adds two compounding-value capabilities the user adopted during the storm: local dictation history with a vocabulary list, and per-app cleanup profiles. The source repo is read-only for this work; everything targets `mini-whisper-swift`.

## 2. Goals
- A user of the Python app installs the Swift build through the existing cask and keeps their hotkeys, prompts, engine choice, volume, usage data, pricing overrides and all three Keychain keys with no manual step.
- Every capability of v0.1.8 works identically from the user's point of view: both hotkeys with hold/toggle semantics and modifier-as-trigger capture; batch transcription (`gpt-4o-mini-transcribe`) and optional cleanup (`gpt-4o-mini`); live transcript via on-device, OpenAI Realtime, ElevenLabs and Speechmatics with batch fallback; caption bar; on/off sounds with volume; onboarding for Microphone and Accessibility; `Today`/`Month` usage rows and `Last:` re-copy; `--debug` file logging.
- Warm press→visible-recording latency is under ~50 ms (source: ~470 ms, 2–5 s after mic idle), measured on the same machine, without a permanent orange microphone indicator.
- The overlay reproduces the source physics numerically (24 dots, 10 on a jittered ring; spring k=30, damping 10; ambient orbit 10 pt at 1.2 rad/s; audio amplitude 130 with floor 0.005 / ceiling 0.06 and attack 0.6 / decay 0.08; connection lines under 120 pt; processing rotation 3 rad/s; 300 pt card at 0.7 alpha; 480 pt caption, 7 lines, 0.9 s cursor blink) and adds native show/hide and mode transitions.
- With no OpenAI key, a dictation using an on-device engine still pastes text; the Settings UI makes it impossible to select a cloud engine without its key or to enable cleanup without an OpenAI key.
- The five agreed defect fixes are verifiably in place: clipboard restored after paste; overlay and caption centred on the display holding the focused window; discarded (interrupted) dictations do not add cost or tokens (streamed minutes still count); a second launch activates the running instance and exits; a tap-armed recording stops automatically at a configurable ceiling.
- History and vocabulary work end to end: delivered dictations are retained for 0–30 days (default 7; 0 = nothing written), searchable, copyable and re-pasteable from a History window, and a user-maintained vocabulary list reaches both the transcription instructions and the cleanup prompt.
- Per-app profiles work end to end: a profile bound to one or more bundle IDs selects cleanup prompt, cleanup on/off and submit-key behaviour (Enter / Shift+Enter / Cmd+Enter); a Default profile applies elsewhere.

## 3. Scope (in / out)
- **In scope:**
  - Drop-in identity: bundle ID `com.ips.mini-whisper`, `~/.config/mini-whisper/{config.json,prompt.txt,transcribe_prompt.txt}`, Keychain service `mini-whisper` with accounts `openai-api-key`, `elevenlabs-api-key`, `speechmatics-api-key`; existing `usage`, `pricing_overrides` and legacy `daily_usage` handled as the source does.
  - Full v0.1.8 parity as listed in §2, including the source's edge-case behaviour where not explicitly changed: 0.3 s hold threshold; 0.5 s / RMS 0.005 recording gate; 401/429/other HTTP messages; 5 s streaming finish timeout with partial text discarded; 60 s pre-connect buffer cap; engine-restart heuristic for on-device partials; Speech permission requested on first on-device dictation with the one-per-run pointer when denied; corrupt config backed up to `config.json.bak`; menu structure and labels; onboarding wizard steps and deep links; quit teardown order.
  - Idle-stop audio-engine lifecycle and an event-driven (non-polling) UI path from hotkey to overlay.
  - macOS 14 minimum. SpeechAnalyzer as an additional engine on macOS 26+ and the default there; SFSpeechRecognizer the default below 26; users who explicitly chose another engine keep it.
  - Settings redesign so invalid states are unrepresentable (engine needs its key, cleanup needs OpenAI key), plus the new controls: retention slider, vocabulary list, profiles, toggle cap. Appearance is decided by `/feature-design` mockups.
  - Defect fixes: clipboard restore; overlay follows active display; no billing for discarded dictations; single-instance guard; toggle-mode safety cap (configurable, default 5 min).
  - Key-free operation: on-device transcript pasted raw when no OpenAI key; key-less batch path still errors with a pointer to Settings.
  - Local history (0–30 days, default 7) with History window (search, copy, re-paste, clear) opened from the menu bar; `Last:` row retained.
  - Manual vocabulary list injected into transcription instructions and cleanup prompt.
  - Per-app profiles: cleanup prompt, cleanup on/off, submit-key behaviour; Default profile.
  - Overlay: same physics plus native polish; `/feature-design` presents 3–4 overlay alternatives.
  - Engineering parity: unit tests (TDD), and a GitHub Actions pipeline equivalent to the source's (tests → build → Developer ID sign → DMG → notarise → GitHub Release on `v*` tags → update `cagriy/homebrew-tap` cask `mini-whisper`). Version continues at 0.2.0.
  - Repository: private GitHub repo `cagriy/mini-whisper-swift` initialised from this folder (no push until asked).
- **Out of scope / deferred:**
  - Toggle-mode visual indicator — the overlay persisting after release is already the cue; reproduce as-is.
  - Caption feedback for silent batch fallback when a cloud engine lacks a key — superseded by the Settings gating (state cannot be selected).
  - Pricing overrides UI — `pricing_overrides` stays a hand-edited JSON key.
  - Per-app transcription instructions and built-in profile presets (Terminal/Slack/IDE) — v2 candidates.
  - Automatic or edit-driven vocabulary learning — manual list only in v1.
  - Live typing of the transcript into the target app; clipboard-free Accessibility text insertion; Shortcuts action / CLI service — deferred as separate features.
  - Any change to the Python source repo.

## 4. High-level technical direction
- Native Swift application, no bundled interpreter or runtime; distributed as a signed, notarised, Apple-Silicon DMG exactly as today. Bundle ID must stay `com.ips.mini-whisper`.
- Must read and write the existing config/prompt files and Keychain items unchanged in location and naming; new settings are added as new keys with defaults so the file remains readable by the Python app.
- Audio engine is started once on first use and stopped only after an idle period; device/route changes (AirPods, USB mics) must be survived without a restart of the app. The orange mic indicator may show only while the engine runs.
- No polling anywhere on the hotkey→overlay path; the overlay must be pre-built and warm at first press; sounds pre-loaded.
- Latency budget: warm press→visible-recording < ~50 ms; release→paste bounded by the network paths already in the source (30 s transcribe, 15 s cleanup, 5 s stream finish).
- Overlay rendering must hold 60 fps without per-frame heap churn; physics constants and the audio-level mapping are fixed by the source values in §2.
- Global hotkeys must support modifier-only triggers (`cmd_r`, `shift+cmd_r`) with exact-set matching for modifier triggers and superset matching for key triggers, key-capture mode, and recovery from missed key-up events; the app needs only Microphone, Accessibility and (on first on-device use) Speech Recognition permissions — no Automation/System Events.
- Paste targets the frontmost application's pid (as the source does since 0.1.7); clipboard contents are restored after the paste lands.
- Streaming engines speak the wire protocols pinned in the source (`gpt-live-transcribe` at 24 kHz PCM with server VAD; ElevenLabs `scribe_v2_realtime` at 16 kHz; Speechmatics EU RT v2 at 16 kHz binary frames); the Python repo's JSON fixtures may be copied into this repo's tests.
- History and vocabulary are stored locally only; nothing is sent anywhere beyond the engines the user already selected. Retention 0 must write nothing.
- macOS 14 deployment target; SpeechAnalyzer usage gated at runtime by availability.
- Tests exist for the non-UI pipeline (config, pricing, hotkey parsing/matching, transcript assembly, engine adapters against fixtures, profiles, history retention); UI behaviour verified manually with the user.
- Deliberately NOT detailed design — UI framework choice per surface, rendering technology, storage format and concurrency model live in `/feature-design`.

## 5. Alternatives considered
- Keep per-press audio-engine start/stop (true feature parity including latency) — rejected because the source's own measurements attribute ~470 ms per press (2–5 s after idle) to it and the user wants the latency addressed; the persistent-engine variant was rejected for its permanent orange mic indicator.
- New bundle identity with first-run import, or a clean break — rejected because a drop-in replacement costs users nothing and keeps the cask, permissions and Keychain continuity.
- macOS 13 floor (identical to today) or macOS 26 only — rejected: 13 forfeits modern frameworks for a shrinking audience; 26-only drops every user not yet upgraded. macOS 14 with runtime-gated SpeechAnalyzer keeps both.
- On-device-only v1, cloud streaming engines in v2 — rejected: the protocols and fixtures already exist and the user wants parity in one release.
- Wave 2 ideas weighed and deferred: live typing into the target app, clipboard-free Accessibility insertion, and a Shortcuts/CLI dictation service — each changes the core interaction and deserves its own storm. Edit-driven or fully automatic vocabulary learning — rejected for v1 in favour of a manual list (no silent learning, simpler).

## 6. Risks
- TCC continuity: Accessibility and Microphone grants are keyed to the bundle ID but validated against the code signature; a new binary under the same ID may still re-prompt, so "upgrade in place with nothing to do" could fail on first launch. Impact: onboarding reappears for existing users; must be verified early.
- Latency target depends on the idle-stop lifecycle behaving well across device changes and sleep/wake; a regression here reintroduces the exact complaint the rewrite is meant to remove.
- Behavioural drift while "not porting function by function": the source has many small guards (generation checks, finish timeouts, pre-connect caps, segment-restart heuristic). Missing one shows up as a rare paste of stale or truncated text. Mitigation is the grounding inventory and fixture tests.
- Provider protocol drift (ElevenLabs/Speechmatics/OpenAI Realtime schemas pinned 2026-09-01) — same risk the source carries; live captions degrade to batch fallback, dictation unaffected.
- History changes the README's privacy promise ("nothing stored locally"); the default of 7 days must be communicated clearly and retention 0 must be honoured exactly.
- Config compatibility: new keys written by the Swift app must not break the Python app if a user rolls back via the cask.
- SpeechAnalyzer is a new API with limited field history; making it the default on macOS 26 risks accuracy or availability surprises. Fallback to SFSpeechRecognizer must be automatic.

## 7. Open questions for design
- UI framework per surface: SwiftUI vs AppKit for Settings, History, onboarding, and the overlay/caption windows (user has no stated preference; programmatic UI is fine).
- Overlay rendering path that holds 60 fps with zero per-frame allocation (Core Animation layers, Metal, SwiftUI Canvas) — and the 3–4 visual alternatives to mock up.
- Idle-stop timeout value and behaviour on sleep/wake and audio-route change; whether the first press after idle should show the overlay before the engine is ready.
- Whether Accessibility/Microphone TCC grants carry over to the new binary under the same bundle ID and Team ID, and what onboarding does if not.
- Verify whether the "1-minute SFSpeechRecognizer limit" applies to on-device recognition at all; if it does, how live transcript survives dictations up to the toggle cap.
- Runtime handling when a selected engine's key is removed from the Keychain out-of-band (Settings prevents the state, the Keychain does not).
- History storage format and location (inside `~/.config/mini-whisper/` or Application Support), and how retention pruning runs.
- Profile matching rules for the frontmost app (bundle ID exact match; what wins when several profiles list the same ID) and how submit-key variants are posted.
- Clipboard restore timing — how the app knows the paste has landed before restoring (source uses fixed 50/150 ms sleeps).
- Toggle-cap default (user accepted 5 min as a working assumption) and where it surfaces in Settings.
- Project layout (Xcode project vs SwiftPM executable), Swift 6 strict-concurrency stance, and test framework; how much of the Python repo's fixture set is copied over.
- CI: reuse the source workflow shape with `xcodebuild`, or a leaner pipeline; how the `APP_VERSION` is derived without `pyproject.toml`.

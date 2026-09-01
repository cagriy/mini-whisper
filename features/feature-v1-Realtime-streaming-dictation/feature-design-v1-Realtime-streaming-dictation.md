# Realtime Streaming Dictation — Design v1

**Status:** Draft
**Date:** 2026-09-01
**Storm:** [feature-storm-v1-Realtime-streaming-dictation.md](./feature-storm-v1-Realtime-streaming-dictation.md)

## 1. Summary

Mini Whisper currently transcribes only after hotkey release: the full WAV is POSTed to OpenAI's batch endpoint, optionally cleaned up, then pasted. This feature makes dictation live. While the user speaks, a streaming engine transcribes incrementally and the partial text renders in a caption bar under the recording dots. The compound streamed transcript is the final raw transcript — it feeds the cleanup model (when enabled) and is pasted, replacing the batch transcription call. Four engines are supported: Apple on-device speech recognition (default, free, offline), OpenAI Realtime, ElevenLabs Scribe v2 Realtime, and Speechmatics Real-Time. Streaming is on by default; disabling it restores today's batch behaviour exactly. Usage reporting is extended with streamed minutes and real dollar costs (today and month-to-date).

## 2. Goals and non-goals

- **Goals:**
  - Partial transcript visible in the overlay within ~1s of speech, for all four engines.
  - Engine selectable in Settings; on-device is the default; streaming toggle on by default.
  - One transcription pass per dictation when streaming succeeds; compound transcript → cleanup (if enabled) → paste.
  - A dictation never fails because of streaming: any engine-unavailable condition (missing key, denied permission, connection failure, mid-stream drop) falls back to the existing batch pipeline using the locally accumulated audio.
  - Menu bar shows tokens, streamed minutes, and dollar cost today plus month-to-date dollar cost.
- **Non-goals:**
  - Type-at-cursor streaming, scratchpad confirm-before-paste, dictation history, translation mode, voice editing commands (all deferred by the storm).
  - Changing cleanup: it remains a single GPT-4o-mini chat call over the complete transcript.
  - Live cost alerts or budgets — display only.

## 3. Requirements

Functional:

1. `config.json` gains `streaming_enabled` (bool, default `true`) and `streaming_engine` (string, one of `on_device` (default), `openai`, `elevenlabs`, `speechmatics`).
2. With `streaming_enabled: false`, behaviour is byte-for-byte today's pipeline: no caption bar, batch transcribe → clean → paste, unchanged gates (`MIN_RECORDING_SECONDS`, `SILENCE_RMS_THRESHOLD`, generation discard).
3. With streaming enabled, hotkey press starts recording AND the selected engine's streaming session; partial text events update the caption bar while recording.
4. The caption bar (per accepted mockup): detached 480×≥92pt black 70%-alpha rounded (r16) window below the unchanged 300×300 dots card; last ~3 lines visible, older lines dimmed, blinking cursor on the partial line; during processing the text stays visible, dimmed, cursor removed; hidden when streaming is disabled or the overlay hides.
5. On hotkey release: the engine session is finalised; the compound transcript (joined finalised segments + trailing partial) becomes the raw transcript; cleanup (if enabled) runs on it; result is pasted (with Enter when the submit hotkey was used).
6. Fallback: if the streaming engine is unavailable or errors at any point before finalisation completes (no API key for the chosen cloud engine, Speech permission denied, websocket connect/mid-stream failure, on-device recogniser error, empty compound transcript), the dictation completes via the existing batch path (`transcriber.transcribe`) using the recorder's accumulated WAV. The caption bar shows `⚠ live transcript unavailable` for the remainder of that dictation.
7. On-device engine requests the macOS Speech Recognition permission on first use (first dictation with `on_device` selected and authorization not determined). If denied, that dictation and subsequent ones fall back per R6; the overlay error surface shows a one-line pointer to System Settings once per app run.
8. Offline behaviour with cleanup enabled is unchanged from today: cleanup failure (network unreachable, HTTP error) surfaces the existing error overlay and pastes nothing — including after an on-device streamed dictation.
9. Usage: every dictation records provider-attributed usage — OpenAI tokens (batch transcribe, cleanup, and OpenAI realtime tokens when reported) and streamed minutes per engine. Config stores per-day entries for the current month; older months are pruned.
10. Cost: dollar cost is computed per dictation from `pricing.py` constants (per-minute rates for streaming engines, per-token rates for batch/cleanup; on-device = $0). Config keys `pricing_overrides` (optional dict) override individual constants without a UI.
11. Menu bar shows two rows: `Today: <in>/<out> tok · <N>m · $<x.xx>` and `Month: $<y.yy>`, updated after each dictation.
12. Settings gains a "Live Streaming" section per the accepted mockup: `Enable Live Transcript` checkbox, `Engine` popup (labels: `On-device (free, offline)`, `OpenAI`, `ElevenLabs`, `Speechmatics`), and ElevenLabs / Speechmatics API-key fields with Save buttons; keys are stored in the macOS Keychain, never on disk.
13. Selecting a cloud engine whose key is missing is allowed; the miss surfaces at dictation time via R6 fallback (batch still requires the OpenAI key, which the app already mandates).
14. Toggle mode (tap to start, tap to stop) streams identically to push-to-talk.

Non-functional:

15. Audio capture must remain lossless for fallback: the recorder keeps accumulating frames locally regardless of streaming state.
16. The streaming worker must never block the audio tap callback; per-buffer hand-off is a non-blocking queue put.
17. No new required accounts: OpenAI remains the only mandatory key; ElevenLabs/Speechmatics keys are optional.
18. Caption-bar updates land on the main thread (AppKit requirement) via the existing `ui_queue` poll loop, at its 100ms cadence.

## 4. Background and context

- Pipeline orchestration: `src/mini_whisper/controller.py:99-142` (`Controller._process`: transcribe → clean → paste, generation discard at `controller.py:132`).
- Audio: `src/mini_whisper/recorder.py:78-91` — the `AVAudioEngine` tap already delivers `AVAudioPCMBuffer`s at hardware rate (44.1/48kHz float32) on the audio thread; frames accumulate under a lock; WAV is produced at stop (`recorder.py:110-141`) with linear-interpolation resampling to 16kHz.
- Overlay: `src/mini_whisper/overlay.py:183-228` — borderless floating 300×300 `NSWindow`, black 0.7-alpha rounded card, 60fps `NSTimer`, modes `recording`/`processing`/`error`.
- UI events: `src/mini_whisper/app.py:121-147` — `ui_queue` polled every 100ms on the main thread; event kinds `recording`, `processing`, `idle`, `result`, `usage`, `error`.
- Settings: `src/mini_whisper/settings.py:165-` — programmatic AppKit window (480×645); existing checkbox pattern `settings.py:344-355`, button target pattern `settings.py:103-114`, API-key save `settings.py:489`.
- Config: `src/mini_whisper/config.py:33-38` (flat `DEFAULT_CONFIG`), Keychain access `config.py:77-90` (service `mini-whisper`), daily usage with today-only pruning `config.py:112-122`.
- Batch clients: `src/mini_whisper/transcriber.py:13-55`, `src/mini_whisper/cleaner.py:12-48` (both `httpx`, module-level clients).
- Storm: [feature-storm-v1-Realtime-streaming-dictation.md](./feature-storm-v1-Realtime-streaming-dictation.md). Accepted mockup: [Caption Bar](./mockups/mockup-v1-caption-bar.html) ([artifact](https://claude.ai/code/artifact/5d1d4d9a-506b-485c-ad8f-ec0927df7961)).
- External surfaces (verified 2026-09-01): OpenAI Realtime transcription session — `wss://api.openai.com/v1/realtime`, `session.update` with `session.type: "transcription"`, `audio/pcm` @ 24kHz, model `gpt-live-transcribe`, client events `input_audio_buffer.append`/`.commit`, server events `conversation.item.input_audio_transcription.delta`/`.completed`. ElevenLabs Scribe v2 Realtime websocket (partial + committed transcripts). Speechmatics Real-Time v2 websocket (`StartRecognition`, binary `AddAudio`, `AddPartialTranscript`/`AddTranscript`). Apple `Speech.framework` via `pyobjc-framework-Speech` (12.2.2): `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest.appendAudioPCMBuffer_` accepts the tap's buffers directly, `requiresOnDeviceRecognition`, partials via `shouldReportPartialResults`.

## 5. Design

### Architecture / components

New package `src/mini_whisper/streaming/` plus small changes to existing modules. Each engine is a class implementing one protocol, so engines are unit-testable with a fake sink and the controller is testable with a fake engine.

- **`streaming/base.py` — `StreamingEngine` protocol + shared types.** Responsibility: define the seam.
  ```python
  class TranscriptSink(Protocol):
      def on_partial(self, text: str) -> None: ...   # full current-segment text, replaces previous partial
      def on_final(self, text: str) -> None: ...     # a segment is finalised, append to compound
      def on_engine_error(self, exc: Exception) -> None: ...

  class StreamingEngine(Protocol):
      name: str                                       # "on_device" | "openai" | "elevenlabs" | "speechmatics"
      def start(self, sink: TranscriptSink) -> None: ...      # begin session (async internally; never blocks caller)
      def feed(self, pcm_buffer) -> None: ...                 # AVAudioPCMBuffer from the tap; non-blocking
      def finish(self, timeout: float = 5.0) -> "StreamResult": ...  # flush, close, return compound result

  @dataclass
  class StreamResult:
      text: str                 # compound transcript (finalised segments + trailing partial)
      ok: bool                  # False → caller must fall back to batch
      usage: dict               # {"input_tokens": int, "output_tokens": int, "seconds": float}
  ```
  `feed()` before the session is open buffers internally and flushes on open, so connect latency loses no audio and no partials are dropped — merely delayed.
- **`streaming/audio_convert.py` — incremental PCM converter.** Responsibility: hardware-rate float32 → target-rate int16 little-endian bytes, statefully (carries fractional resample position across buffers so chunk boundaries don't click). Reuses the linear-interpolation approach of `recorder.py:37-45`, generalised to stateful chunked operation. Pure function of (numpy array, state) → (bytes, state); unit-tested against the batch resampler on identical input.
- **`streaming/websocket_engine.py` — shared cloud-engine skeleton.** Responsibility: own the background thread + `websockets` (new dependency `websockets>=17`) event loop, the buffer-until-open queue, reconnect-free error propagation (one failure → `on_engine_error`, no mid-dictation retries), and the finish handshake with timeout. Subclasses supply: URL + headers, session-open message(s), per-chunk encode (base64 JSON append vs binary frame), end-of-audio message, and event parsing into `on_partial`/`on_final`/usage.
  - **`OpenAIRealtimeEngine`**: `wss://api.openai.com/v1/realtime`, `Authorization: Bearer <openai key>`; sends `session.update` (`session.type: "transcription"`, `audio/pcm` 24kHz, model `gpt-live-transcribe`, server VAD on); feeds `input_audio_buffer.append` (base64); on finish sends `input_audio_buffer.commit`; maps `…transcription.delta` → `on_partial` (accumulated per segment), `…transcription.completed` → `on_final`; collects token usage from usage-bearing events when present, else zeros (cost comes from minutes regardless).
  - **`ElevenLabsEngine`**: Scribe v2 Realtime websocket; 16kHz PCM16; partial events → `on_partial`, committed events → `on_final`.
  - **`SpeechmaticsEngine`**: RT v2 websocket; `StartRecognition` (raw PCM16, sample rate declared), binary `AddAudio` frames, `EndOfStream`; `AddPartialTranscript` → `on_partial`, `AddTranscript` → `on_final`.
  - The event names each subclass parses are the ones pinned in §4 (OpenAI delta/completed; ElevenLabs partial/committed; Speechmatics `AddPartialTranscript`/`AddTranscript`); the per-provider fixture tests in §5 *Testing strategy* encode the full message shapes, so any schema drift fails one provider's fixtures without touching the others.
- **`streaming/on_device.py` — `OnDeviceEngine`.** Responsibility: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = True`, `SFSpeechAudioBufferRecognitionRequest` (`shouldReportPartialResults = True`); `feed()` calls `appendAudioPCMBuffer_` directly (no conversion needed); result handler maps partial results → `on_partial` and final result → `on_final`; `finish()` calls `endAudio()` and waits (≤ timeout) for the final callback. Also owns `ensure_authorized()` → `"authorized" | "denied" | "undetermined"` using `SFSpeechRecognizer.authorizationStatus()` / `requestAuthorization_`. Usage reports seconds only; tokens zero.
- **`streaming/factory.py`** — `make_engine(cfg, api_keys) -> StreamingEngine | None`; returns `None` (→ batch path) when streaming is disabled, the engine's key is missing, or Speech permission is denied; the `None` reason is logged and surfaced per R6/R7.
- **`pricing.py`** — module constants (editable defaults, overridable via `cfg["pricing_overrides"]`):
  ```python
  PER_MINUTE = {"openai_realtime": 0.017, "elevenlabs": 0.0065, "speechmatics": 0.0067, "on_device": 0.0}
  PER_MTOK   = {"gpt-4o-mini-transcribe_in": 1.25, "gpt-4o-mini-transcribe_out": 5.00,
                "gpt-4o-mini_in": 0.15, "gpt-4o-mini_out": 0.60}
  def dictation_cost(engine_name, seconds, token_usage_by_model) -> float
  ```
- **`overlay.py` — `CaptionBarWindow`** (new class in the same module, same conventions as `DotsOverlayWindow`): borderless floating 480×92 `NSWindow`, black 0.7-alpha, radius 16, positioned 14pt below the dots window and horizontally centred on it; `set_text(text, partial: bool, dimmed: bool)` renders the last 3 wrapped lines (older lines at 0.45 alpha, current at 0.92, blinking cursor glyph appended when `partial`); `show_unavailable()` renders the `⚠ live transcript unavailable` line. Redraw piggybacks on text updates (no 60fps timer of its own).
- **`controller.py` changes**: `_stop_and_process` gains the streaming finish; a new `_stream_worker` owns engine lifecycle (see Control flow). New `UIEvent` kinds: `caption` (text payload, partial/dim encoded as prefix-free fields — extend `UIEvent` with `partial: bool = False`, `dimmed: bool = False`), `caption_unavailable`. Existing kinds untouched.
- **`recorder.py` change**: an optional `buffer_listener` callable set/cleared by the controller; `_tap_block` invokes it (non-blocking, exception-swallowed) after appending frames, at `recorder.py:78-91`. Recording accumulation is unchanged.
- **`app.py` changes**: `_poll_ui_events` handles `caption`/`caption_unavailable` by driving `CaptionBarWindow`; hides it on `idle`/`result`/`error`; menu gains the second usage row (`Month: $…`) and the first row's new format (R11).
- **`config.py` changes**: new defaults (R1); `add_usage(provider_usage)` replacing `add_daily_usage`'s today-only pruning with current-month retention (R9); Keychain usernames `elevenlabs-api-key`, `speechmatics-api-key` alongside the existing `openai-api-key`.
- **`settings.py` changes**: "Live Streaming" section per mockup (R12), reusing the existing checkbox/button/field patterns; engine popup is an `NSPopUpButton` following the same target/action pattern.
- **`onboarding.py`**: untouched (permission is requested on first use, R7).

### Data model

`config.json` additions:

```json
{
  "streaming_enabled": true,
  "streaming_engine": "on_device",
  "pricing_overrides": {},
  "usage": {
    "2026-09-01": {"input_tokens": 1200, "output_tokens": 3400,
                    "streamed_seconds": {"on_device": 540, "elevenlabs": 180},
                    "cost_usd": 0.08}
  }
}
```

- `usage` replaces `daily_usage`; on first load, an existing `daily_usage` entry for today is migrated into `usage` (tokens copied, seconds/cost zero) and the old key removed. Entries whose date falls outside the current calendar month are pruned on write. Today = sum of today's entry; month-to-date = sum over all entries (all are in the current month by construction).
- API keys: Keychain service `mini-whisper`, usernames `openai-api-key` (existing), `elevenlabs-api-key`, `speechmatics-api-key`. Never on disk. `.gitignore` untouched (nothing new lands in the repo).

### Interfaces

- UI surface exactly per the accepted mockup [Caption Bar](./mockups/mockup-v1-caption-bar.html): unchanged dots card; detached caption bar below; settings "Live Streaming" section; two menu usage rows.
- `UIEvent` gains fields `partial: bool = False`, `dimmed: bool = False` (defaulted, so existing constructors are unaffected) and the two new kinds above.
- `Controller.__init__` unchanged externally. `Recorder` gains `set_buffer_listener(fn | None)`.
- Menu format (R11): token counts keep the existing `_fmt_tokens` style (`app.py:26-30`); minutes rendered as integer minutes (`12m`); dollars as `$x.xx` (two decimals, `<$0.01` renders `$0.00`).
- The `usage` UIEvent's payload changes from the current `"<in> / <out>"` string (`controller.py:142`, parsed at `app.py:143-145`) to the two pre-formatted menu rows (`text` = today row, new field `text2` = month row); `_poll_ui_events` assigns them directly instead of parsing.

### Control flow

Happy path (streaming enabled, engine available):

1. Hotkey press → `Controller.on_hotkey_press`: play "on", `recorder.start()`, then `engine = make_engine(...)`; if non-None: `recorder.set_buffer_listener(engine.feed)`, `engine.start(sink)` (returns immediately; connection proceeds on the engine's thread; `feed` buffers until open). `UIEvent("recording")` as today.
2. While recording: tap thread → `engine.feed(buffer)` → engine thread converts/sends; server events → sink callbacks → `ui_queue.put(UIEvent("caption", text=compound_tail, partial=True))`. The sink maintains the compound transcript: `finalised segments joined + current partial`; every callback emits the current tail.
3. Hotkey release → `_stop_and_process`: `recorder.set_buffer_listener(None)`, capture `duration`/`audio`/`avg_rms` as today (`controller.py:73-75`). Gates (R2) run unchanged; if gated out, `engine.finish(timeout=0.5)` result is discarded, the streamed seconds are still recorded via `config.add_usage` (the provider billed them), and the bar hides via `idle`.
4. `UIEvent("processing")`; caption bar re-emitted dimmed (`UIEvent("caption", text, partial=False, dimmed=True)`). Worker thread: `result = engine.finish()`.
   - `result.ok and result.text.strip()` → raw transcript = `result.text`; skip batch transcribe.
   - else → `UIEvent("caption_unavailable")`, raw transcript from `transcribe(audio, ...)` (existing batch call).
5. Cleanup (if enabled) → paste → sounds → `result`/`usage` events, all as today, including the generation-staleness discard (`controller.py:132`) which now also discards the streamed result.
6. Usage recorded via `config.add_usage(...)` with tokens per model + `seconds = duration` attributed to the engine (streamed path) or tokens only (batch path). Menu rows update via the `usage` event carrying the formatted strings.

Alternative flows:

- **Streaming disabled / engine None**: steps 1–4 collapse to today's exact flow; no caption events are emitted.
- **Engine error mid-recording** (`on_engine_error`): sink marks the stream failed, emits `caption_unavailable`; recording continues untouched; release takes the batch branch of step 4. `finish()` on a failed engine returns `ok=False` immediately.
- **First on-device use, permission undetermined**: `make_engine` triggers `requestAuthorization_` and returns `None` for this dictation (batch path); the grant applies from the next dictation. Denied → `None` thereafter + one-per-run overlay error pointer (R7).
- **Toggle mode**: identical — press/release semantics wrap the same start/stop calls.
- **Quit mid-recording**: `_quit` (`app.py:194-203`) additionally calls `controller.abort_stream()` → `engine.finish(timeout=0.5)` discarded; caption window cleaned up with the overlay.

### Failure and edge cases

| Case | Behaviour |
|---|---|
| Cloud engine key missing | `make_engine` → None → batch path; caption bar shows unavailable line (R6) |
| Websocket connect fails / drops mid-stream | `on_engine_error` → unavailable line; batch fallback at release |
| `finish()` timeout (server never sends final) | `ok=False` with whatever partial text discarded → batch fallback (never paste a possibly-truncated stream silently) |
| Compound transcript empty but audio passed gates | Batch fallback (guards against engine that connected but produced nothing) |
| Batch fallback itself fails | Existing error handling (`controller.py:144-157`) — overlay error, nothing pasted |
| Cleanup fails (offline included, any engine) | Existing error handling — overlay error, nothing pasted (R8) |
| Speech permission denied | Batch path + one-per-run pointer to System Settings (R7) |
| On-device recogniser unavailable (locale unsupported) | `on_engine_error` at start → batch path |
| Stale generation (new recording started during processing) | Streamed result discarded exactly like batch results today (`controller.py:131-136`) |
| Config `usage` from a previous month | Pruned on next write; menu shows fresh zeros |
| Sub-minimum / silent recording | Gates fire before any transcript is used; engine result discarded; no usage recorded beyond seconds already streamed (recorded as cost — audio was billed by the provider) |

### Security

- All three API keys live in the macOS Keychain (existing `keyring` pattern, `config.py:77-90`); never logged, never on disk, never echoed to the UI (key fields display placeholder dots once set).
- Websocket connections are TLS (`wss://`) to the providers' official endpoints only; endpoint URLs are module constants, not user-configurable (no SSRF surface).
- Transcript text is untrusted content: it is pasted via the existing `pbcopy` path (`paster.py`), never interpolated into shell commands or AppleScript beyond what today's paste already does.
- No new trust boundary beyond the two added providers; the user opts into each by supplying its key.

### Performance

- Tap callback budget: the listener call adds one non-blocking queue put (<10µs); conversion and network run on the engine thread. The audio thread never waits on the network.
- Caption updates coalesce naturally through the 100ms `ui_queue` poll; the bar redraws only on text change (no per-frame timer), keeping overlay CPU where it is today.
- Buffer-until-open bounds memory: at 48kHz float32, 10s of pre-connect audio ≈ 1.9MB — capped at 60s, after which the engine declares failure (a connect that slow is a failure anyway).
- `finish()` timeout 5s keeps worst-case added latency bounded; batch fallback then costs what it costs today.

### Observability

- Existing logging conventions: engine lifecycle at INFO (start, open, finish, fallback reason), per-event at DEBUG. Fallbacks always log the concrete reason (`no key`, `permission denied`, `connect failed: …`, `finish timeout`).
- User-visible: the caption bar's unavailable line, the existing error overlay for terminal failures, and the cost rows (which double as "is it billing what I think" observability).

### Compatibility / migration

- Config migration (R9/Data model) is one-shot and lossless for today's tokens; absent new keys default via `DEFAULT_CONFIG`, so existing installs upgrade silently.
- Streaming off reproduces today's behaviour exactly (R2) — the feature flag is its own rollback.
- New dependencies: `websockets>=17`, `pyobjc-framework-Speech>=12`. py2app: `Info.plist` in `setup.py` gains `NSSpeechRecognitionUsageDescription` (required for the Speech permission prompt).

### Testing strategy

The repo has an existing pytest suite (`tests/`, run via `uv run pytest`; 49 tests passing at design time, plus API-gated integration tests marked `integration`), with shared fixtures in `tests/conftest.py`. This feature extends it, TDD per plan stage. All new tests run without network, microphone, or permissions:

- `audio_convert`: chunked output equals whole-buffer batch resample on the same input; format is int16 LE at target rate; state carries across odd chunk sizes.
- `StreamResult` sinks / compound assembly: partial-replace + final-append semantics; empty-compound and error paths flip `ok`.
- `websocket_engine` subclasses: message encode/parse tested pure (given a fake socket transcript of provider events → expected sink calls and finish result), one fixture file per provider.
- `OnDeviceEngine`: authorization gate logic behind a stubbed `SFSpeechRecognizer` interface (the pyobjc calls are wrapped thinly so the wrapper is fake-able).
- `factory`: engine selection matrix (toggle off / key missing / permission states) → engine class or None with reason.
- `pricing`: cost table maths including overrides, zero-cost on-device, rounding.
- `config`: migration from `daily_usage`, month pruning, month-to-date summation.
- `controller`: with a fake engine + fake transcribe/clean/paste — happy streamed path skips batch; each fallback row of the table above takes the batch branch; gates and generation discard unchanged (`tests/test_controller.py` already characterises the current pipeline; those tests stay green and are extended).
- UI (caption window, settings section, menu rows): manual verification per acceptance criteria — AppKit windows aren't unit-tested in this codebase.

Acceptance: dictate with each engine (keys present) and see live text; pull the network mid-dictation and see the unavailable line plus a correct batch paste; deny Speech permission and see fallback plus the pointer; check the menu rows after known-length dictations against `pricing.py` rates; toggle streaming off and observe today's exact behaviour.

## 6. Alternatives considered

- **OpenAI-only realtime engine (the storm's original shape)** — rejected after live pricing/accuracy research: `gpt-live-transcribe` is ~2.5× the cost of ElevenLabs/Speechmatics with lower measured accuracy; user chose a four-engine lineup with on-device default.
- **ElevenLabs-only (best price/quality)** — rejected: forces every streaming user to create a second account; kept as one option among four instead.
- **On-device as display-only with batch producing the final text** — rejected by the user in the storm: full finality (offline, free) won over preserving batch-level accuracy.
- **Stream-response-only cut** (stream the batch response after release) — rejected in the storm: no text while speaking.
- **Caption text inside a grown dots card** (extended-card / unified-wide mockups) — rejected by the user in the mockup round in favour of the detached caption bar ([extended-card](./mockups/mockup-v1-extended-card.html), [unified-wide](./mockups/mockup-v1-unified-wide.html)).
- **One monolithic streaming module** — rejected for the engine-protocol decomposition: four engines with three wire protocols share only lifecycle, and per-engine classes keep each protocol's parsing unit-testable against fixture transcripts.

## 7. Risks and issues

- **Provider protocol drift** (medium likelihood, medium impact): ElevenLabs/Speechmatics message schemas are pinned at implementation time and can change. Mitigation: per-provider subclass isolates drift to one file; fixture-based tests fail loudly on schema assumptions; batch fallback keeps dictation working while a fix ships.
- **Realtime transcript fidelity vs batch** (medium/low): server VAD segmentation can split mid-utterance; compound text may differ from a batch pass. Mitigation: cleanup smooths most seams; engines are user-switchable; fallback exists.
- **On-device accuracy below the app's bar** (high likelihood for jargon, low impact): user-chosen trade-off, recorded in the storm; engine picker makes it reversible per-user.
- **On-by-default behaviour change** (low, since default engine is free on-device): existing users see a new caption bar and a new permission prompt on first dictation after upgrade. Mitigation: the prompt is the standard macOS one; disabling the toggle restores everything.
- **Pricing constants rot** (certain over time, low impact): costs shown drift from provider invoices. Mitigation: constants in one file, `pricing_overrides` config escape hatch, release-note reminder.
- **`websockets` + py2app bundling** (low): pure-Python package, no compiled deps — expected to bundle cleanly; verified during the build stage of the plan.

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

Single-project, single release. Ship behind the `streaming_enabled` config default (on); the toggle is the rollback (R2 guarantees today's behaviour when off). Stage order in the plan: config/pricing → audio converter → engine protocol + on-device → cloud engines → controller wiring + fallback → caption bar UI → settings + menu → py2app plist/deps. Release notes call out: new caption bar, engine picker with on-device default, the Speech permission prompt, optional ElevenLabs/Speechmatics keys, and the new cost rows.

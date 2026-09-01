# Realtime Streaming Dictation — Implementation Plan v1

**Status:** Draft
**Date:** 2026-09-01
**Design:** [feature-design-v1-Realtime-streaming-dictation.md](./feature-design-v1-Realtime-streaming-dictation.md)

## Overview

This plan lands live streaming dictation in eleven stages, following the design's rollout order (§9): data/pricing foundations first, then the four streaming engines behind the `StreamingEngine` protocol, then the controller pipeline swap with batch fallback, then the two UI surfaces (caption bar, settings/menu), and finally py2app packaging. Every stage leaves the app fully working: streaming stays inert until Stage 8 wires the controller, and `streaming_enabled: false` reproduces today's pipeline throughout (design R2). Stages map 1:1 to design components (§5); the coverage table below ties every requirement to its delivering stage(s).

## Development strategy — Test-Driven Development

Every behavior-changing stage in this plan follows the TDD cycle:

1. **Write the test first.** Add the test(s) that describe the new behavior.
2. **Run the test and confirm it fails.** Capture the failure to prove the test exercises the new behavior.
3. **Write the implementation.** The minimum code needed to satisfy the test.
4. **Run the test and confirm it passes.** Plus the surrounding suite, to catch regressions.

Stages that fit a sanctioned non-red-first category — non-TDD (scaffolding | config-only | integration-verified), behaviour-preserving refactor/deletion, characterization/guard tests, platform-only/UI wiring, external prerequisite (gated) — are labeled with that category and a one-line justification.

**Test runner:** `uv run pytest -q` (pytest ≥9, `testpaths = ["tests"]` in `pyproject.toml`; integration tests are marker-gated and skip without `OPENAI_API_KEY`).
**Baseline (executed 2026-09-01):** `uv run pytest -q` → **49 passed, 1 skipped in 1.00s**.
**Build-only check for UI stages (executed, exit 0):** `uv run python -c "import mini_whisper.overlay, mini_whisper.settings, mini_whisper.app"` — overlay/settings/app have no unit tests, so this import check plus a manual dictation is the between-stage guard for them.
Test conventions: flat `tests/test_<module>.py` files (siblings: `tests/test_config.py`, `tests/test_controller.py`), shared fixtures in `tests/conftest.py` (`tmp_config_dir` redirects config paths), data fixtures under `tests/fixtures/` (existing sibling: `tests/fixtures/wav/`).

## Requirements coverage map

| Design req | Delivered by stage(s) |
| --- | --- |
| R1: config keys `streaming_enabled` / `streaming_engine` | Stage 1 |
| R2: streaming off = byte-for-byte today's pipeline | Stage 8 (guarded by existing `tests/test_controller.py` staying green + explicit off-toggle test) |
| R3: press starts engine session; partials while recording | Stage 8 (events), Stage 9 (display) |
| R4: caption bar per accepted mockup | Stage 9 |
| R5: release finalises; compound → cleanup → paste | Stage 8 |
| R6: any engine failure falls back to batch | Stage 7 (factory `None` paths), Stage 8 (mid-stream/finish/empty fallback) |
| R7: Speech permission on first on-device use; denial fallback + one-per-run pointer | Stage 4 (authorization wrapper), Stage 7 (factory gate), Stage 8 (pointer surfacing) |
| R8: offline cleanup failure behaviour unchanged | Stage 8 |
| R9: provider-attributed usage, current-month retention | Stage 1 (store/migration), Stage 8 (per-dictation recording) |
| R10: dollar cost from `pricing.py` + `pricing_overrides` | Stage 2 (maths), Stage 8 (wiring) |
| R11: two menu rows (today / month) | Stage 2 (row formatting), Stage 10 (menu wiring) |
| R12: Settings "Live Streaming" section; keys in Keychain | Stage 1 (Keychain accessors), Stage 10 (UI) |
| R13: cloud engine selectable without key; miss surfaces at dictation time | Stage 7 (factory), Stage 10 (settings allows selection) |
| R14: toggle mode streams identically | Stage 8 |
| R15 (NF): recorder accumulation lossless regardless of streaming | Stage 7 (listener is post-append, exception-swallowed), Stage 8 |
| R16 (NF): tap callback never blocks on streaming | Stage 3 (buffer-until-open queue), Stage 7 (non-blocking listener) |
| R17 (NF): no new required accounts | Stage 7 (factory treats cloud keys as optional), Stage 10 |
| R18 (NF): caption updates on main thread via `ui_queue` | Stage 8 (events through queue), Stage 9 (rendering in poll loop) |

## Stages

### Stage 1 — Config data model and usage store
**Goal:** `config.json` gains the streaming defaults and the month-retained, provider-attributed `usage` store (with one-shot `daily_usage` migration), plus Keychain accessors for the two new API keys.
**Design references:** §3 R1/R9, §5 Data model, §5 `config.py` changes.
**Touches:** `src/mini_whisper/config.py`, `src/mini_whisper/controller.py` (line 129 call site), `src/mini_whisper/app.py` (line 47 startup read), `tests/test_config.py`, `tests/test_controller.py` (fixture mock rename).

**Steps (TDD):**
1. Write tests in `tests/test_config.py` (using the existing `tmp_config_dir` fixture): new defaults present in `DEFAULT_CONFIG` (`streaming_enabled` True, `streaming_engine` `"on_device"`, `pricing_overrides` {}); `add_usage({"input_tokens":…, "output_tokens":…, "streamed_seconds": {engine: s}, "cost_usd":…})` accumulates into today's entry under `usage`; entries from a previous month are pruned on write while same-month days are retained; `load()` migrates an existing `daily_usage` today-entry into `usage` (tokens copied, seconds/cost zero, old key removed); `usage_totals()` returns today's entry plus month-to-date `cost_usd` sum; thread-safety mirroring `test_add_daily_usage_thread_safety`; `get_streaming_api_key`/`set_streaming_api_key` route to Keychain usernames `elevenlabs-api-key`/`speechmatics-api-key` (patch `keyring`). Expected initial failure: `ImportError: cannot import name 'add_usage' from 'mini_whisper.config'`.
2. Run `uv run pytest tests/test_config.py -q` — confirm the import error / `AttributeError` failures.
3. Implement in `config.py`: new `DEFAULT_CONFIG` keys; `add_usage(provider_usage: dict) -> dict` replacing `add_daily_usage` (current-month retention instead of today-only); migration inside `load()`; `usage_totals()`; keychain accessors. Update `controller.py:129` to call `add_usage` with a provider-usage dict (tokens only for now) and `app.py:47` to read today's totals via `usage_totals()` (menu format unchanged until Stage 10). Update the `tests/test_controller.py` fixture mock from `add_daily_usage` to `add_usage`, and migrate the four `test_add_daily_usage_*` tests to the new API (same observable totals).
4. Run `uv run pytest -q` — confirm all pass, no regressions vs the 49-test baseline.

**Definition of done:**
- `add_daily_usage` and `get_daily_usage` are gone; every caller and test uses `add_usage`/`usage_totals`.
- A config written by v0.1.7 loads cleanly and its today tokens survive migration.
- Full suite green.

**Risks specific to this stage:** The old-API test migration and the store swap must land atomically (old and new store cannot coexist) — this stage is deliberately one unit.

### Stage 2 — Pricing module and usage-row formatting
**Goal:** `pricing.py` computes per-dictation dollar cost from constants (with `pricing_overrides`) and formats the two menu rows.
**Design references:** §3 R10/R11, §5 `pricing.py`, §5 Interfaces (menu format).
**Touches:** `src/mini_whisper/pricing.py` (new), `tests/test_pricing.py` (new).

**Steps (TDD):**
1. Write `tests/test_pricing.py`: `dictation_cost` for each engine's per-minute rate; per-Mtok maths for batch/cleanup tokens; on-device = $0; overrides dict replaces individual constants; rounding; `format_usage_rows(today, month_cost)` renders `Today: <in>/<out> tok · <N>m · $<x.xx>` and `Month: $<y.yy>` with the `_fmt_tokens`-style k-abbreviation, integer minutes, two-decimal dollars (`<$0.01` → `$0.00`). Expected initial failure: `ModuleNotFoundError: No module named 'mini_whisper.pricing'`.
2. Run `uv run pytest tests/test_pricing.py -q` — confirm the module-not-found failure.
3. Implement `pricing.py`: `PER_MINUTE`, `PER_MTOK` constants per design §5; `dictation_cost(engine_name, seconds, token_usage_by_model, overrides=None)`; `format_usage_rows(...)` (pure, shared by controller and app without circular imports).
4. Run `uv run pytest -q` — confirm pass, no regressions.

**Definition of done:** cost and row-formatting maths fully unit-tested, including overrides and zero-cost on-device.

**Risks specific to this stage:** None.

### Stage 3 — Streaming foundations: protocol, transcript assembly, audio converter
**Goal:** the `streaming/` package exists with the engine seam (`StreamingEngine`/`TranscriptSink`/`StreamResult`), a compound-transcript assembler, and the stateful hardware-rate→PCM16 converter.
**Design references:** §5 `streaming/base.py`, `streaming/audio_convert.py`; §3 R16.
**Touches:** `src/mini_whisper/streaming/__init__.py` (new), `src/mini_whisper/streaming/base.py` (new), `src/mini_whisper/streaming/audio_convert.py` (new), `tests/test_streaming_base.py` (new), `tests/test_audio_convert.py` (new).

**Steps (TDD):**
1. Write `tests/test_audio_convert.py`: chunked conversion of a synthetic float32 signal equals the whole-buffer path built from `recorder._resample` (int16 LE at target rate) within ±1 LSB; fractional resample state carries across odd chunk sizes (no dropped/duplicated samples at boundaries); 48kHz→24kHz and 44.1kHz→16kHz cases. Write `tests/test_streaming_base.py`: `CompoundTranscript` partial-replace + final-append semantics (`text` = finalised segments joined + trailing partial); `StreamResult` defaults; empty-compound handling. Expected initial failure: `ModuleNotFoundError: No module named 'mini_whisper.streaming'`.
2. Run both files — confirm module-not-found.
3. Implement `streaming/base.py` (protocols + `StreamResult` dataclass + `CompoundTranscript` assembler as specified in design §5) and `streaming/audio_convert.py` (pure `(np.ndarray, state) -> (bytes, state)` stateful linear-interpolation converter generalising `recorder.py:37-45`).
4. Run `uv run pytest -q` — confirm pass, no regressions.

**Definition of done:** converter parity with the batch resampler proven; assembler semantics pinned; package importable.

**Risks specific to this stage:** None.

### Stage 4 — On-device engine (Apple Speech framework)
**Goal:** `OnDeviceEngine` streams partials/finals from `SFSpeechRecognizer` (on-device only) behind a fake-able thin wrapper, with `ensure_authorized()` gating.
**Design references:** §3 R7, §5 `streaming/on_device.py`, §5 Compatibility (new dependency).
**Touches:** `pyproject.toml` (+`pyobjc-framework-Speech>=12`, via `uv add pyobjc-framework-speech`), `uv.lock`, `src/mini_whisper/streaming/on_device.py` (new), `tests/test_on_device.py` (new).

**Steps (TDD):**
1. Add the dependency first (`uv add "pyobjc-framework-speech>=12"`) — non-TDD (config-only) sub-step so the import exists.
2. Write `tests/test_on_device.py` against a stubbed wrapper interface (`_SpeechAPI` thin class wrapping the pyobjc calls, replaceable in tests): `ensure_authorized()` maps `authorizationStatus` values to `"authorized" | "denied" | "undetermined"` and triggers `requestAuthorization_` only when undetermined; `feed()` forwards buffers to `appendAudioPCMBuffer_`; recogniser partial/final callbacks drive `on_partial`/`on_final`; `finish()` calls `endAudio()` and returns `ok=False` after timeout or recogniser error, `ok=True` with compound text on final; usage reports `seconds` with zero tokens. Expected initial failure: `ModuleNotFoundError: No module named 'mini_whisper.streaming.on_device'`.
3. Run — confirm failure.
4. Implement `streaming/on_device.py` per design §5: `requiresOnDeviceRecognition = True`, `shouldReportPartialResults = True`, `feed()` appends the tap's `AVAudioPCMBuffer` directly (no conversion), all `Speech` calls behind the thin wrapper.
5. Run `uv run pytest -q` — confirm pass, no regressions.

**Definition of done:** engine logic (auth matrix, lifecycle, timeout, compound result) unit-tested with the wrapper faked; `uv run python -c "import Speech"` succeeds.

**Risks specific to this stage:** pyobjc callback threading is only exercisable live — covered by the Stage 8/9 manual acceptance pass.

### Stage 5 — Websocket engine skeleton and OpenAI Realtime engine
**Goal:** the shared cloud-engine skeleton (background thread + `websockets` loop, buffer-until-open with 60s cap, error propagation, finish handshake with timeout) plus the first concrete subclass, `OpenAIRealtimeEngine`.
**Design references:** §5 `streaming/websocket_engine.py`, §4 external surfaces, §5 Performance.
**Touches:** `pyproject.toml` (+`websockets>=17`, via `uv add`), `uv.lock`, `src/mini_whisper/streaming/websocket_engine.py` (new), `tests/test_websocket_engines.py` (new), `tests/fixtures/streaming/openai_realtime.json` (new), `tests/conftest.py` + `tests/test_on_device.py` (FakeSink hoisted to conftest, see Deviations).

**Steps (TDD):**
1. Add the dependency (`uv add "websockets>=17"`) — non-TDD (config-only) sub-step.
2. Write tests in `tests/test_websocket_engines.py` with a fake socket (no network): skeleton — `feed()` before open buffers and flushes on open; buffered pre-connect audio capped at 60s then engine fails; one socket error → `on_engine_error` once, `finish()` → `ok=False` immediately; finish timeout → `ok=False`. OpenAI subclass, driven by a fixture transcript of server events (`tests/fixtures/streaming/openai_realtime.json`): session-open sends `session.update` with `session.type: "transcription"`, `audio/pcm` @ 24kHz, model `gpt-live-transcribe`; chunks sent as base64 `input_audio_buffer.append`; finish sends `input_audio_buffer.commit`; `conversation.item.input_audio_transcription.delta` accumulates into `on_partial`, `.completed` → `on_final`; token usage collected when present, else zeros. Expected initial failure: `ModuleNotFoundError: No module named 'mini_whisper.streaming.websocket_engine'`.
3. Run — confirm failure.
4. Implement skeleton + `OpenAIRealtimeEngine` per design §5 (24kHz PCM16 via the Stage 3 converter; endpoint URL a module constant).
5. Run `uv run pytest -q` — confirm pass, no regressions.

**Definition of done:** skeleton lifecycle and OpenAI encode/parse fully covered by fixture-driven tests; no test opens a network connection.

**Risks specific to this stage:** provider schema drift (design §7) — fixtures pin the assumed shapes so drift fails loudly here, and live verification happens in the Stage 11 acceptance pass.

### Stage 6 — ElevenLabs and Speechmatics engines
**Goal:** the remaining two cloud subclasses, each parsing its provider's wire protocol from a fixture transcript.
**Design references:** §5 engine subclasses, §4 external surfaces.
**Touches:** `src/mini_whisper/streaming/websocket_engine.py`, `tests/test_websocket_engines.py`, `tests/fixtures/streaming/elevenlabs.json` (new), `tests/fixtures/streaming/speechmatics.json` (new).

**Steps (TDD):**
1. Write fixture-driven tests: `ElevenLabsEngine` — 16kHz PCM16, partial events → `on_partial`, committed events → `on_final`; `SpeechmaticsEngine` — `StartRecognition` on open (raw PCM16, sample rate declared), binary `AddAudio` frames, `EndOfStream` on finish, `AddPartialTranscript` → `on_partial`, `AddTranscript` → `on_final`. Expected initial failure: `ImportError: cannot import name 'ElevenLabsEngine'`.
2. Run — confirm failure.
3. Implement both subclasses (URL/headers, open message, per-chunk encode, end-of-audio message, event parsing — everything else inherited from the skeleton).
4. Run `uv run pytest -q` — confirm pass, no regressions.

**Definition of done:** one fixture file per provider; all three cloud engines share the skeleton with only protocol-specific overrides.

**Risks specific to this stage:** same schema-drift risk as Stage 5, isolated per subclass by design.

### Stage 7 — Engine factory and recorder buffer listener
**Goal:** `make_engine()` implements the full selection/gate matrix, and `Recorder` can hand tap buffers to a listener without touching accumulation.
**Design references:** §5 `streaming/factory.py`, §5 `recorder.py` change; §3 R6/R7/R13/R15/R16/R17.
**Touches:** `src/mini_whisper/streaming/factory.py` (new), `src/mini_whisper/recorder.py`, `tests/test_factory.py` (new), `tests/test_recorder_listener.py` (new).

**Steps (TDD):**
1. Write `tests/test_factory.py`: matrix over (streaming toggle, engine name, key present/absent for each cloud engine, Speech authorization state stubbed) → expected engine class or `None` with a machine-readable reason (`disabled`, `no_key`, `permission_denied`, `permission_undetermined` — the last also triggering `requestAuthorization_` once); OpenAI engine uses the existing `openai-api-key`. Write `tests/test_recorder_listener.py`: `set_buffer_listener(fn)` — `_tap_block` invokes the listener after appending frames; a raising listener is swallowed and accumulation is unaffected; `set_buffer_listener(None)` clears (fake the pcm buffer, drive `_tap_block` directly like the recorder's state allows with `_recording` forced). Expected initial failure: `ModuleNotFoundError: No module named 'mini_whisper.streaming.factory'` and `AttributeError: 'Recorder' object has no attribute 'set_buffer_listener'`.
2. Run — confirm both failures. (`tests/test_recorder_listener.py` constructs no real `Recorder` — it stubs `AVAudioEngine` via `monkeypatch`, mirroring the MagicMock pattern of `tests/test_controller.py`.)
3. Implement `factory.py` (`make_engine(cfg, api_keys) -> StreamingEngine | None`, reason logged) and the `recorder.py` listener (checked inside the existing lock, called after append, exception-swallowed, non-blocking).
4. Run `uv run pytest -q` — confirm pass, no regressions.

**Definition of done:** every row of the selection matrix tested; recorder accumulation provably unchanged with a live or raising listener.

**Risks specific to this stage:** None.

### Stage 8 — Controller streamed pipeline and batch fallback
**Goal:** the controller runs the full streamed dictation cycle — engine start on press, caption events while recording, finish on release, compound transcript → cleanup → paste — with batch fallback on every failure path and per-dictation usage/cost recording.
**Design references:** §5 `controller.py` changes, §5 Control flow, §5 Failure and edge cases; §3 R2/R3/R5/R6/R7/R8/R9/R10/R14/R18.
**Touches:** `src/mini_whisper/controller.py`, `tests/test_controller.py`.

**Steps (TDD):**
1. Write tests in `tests/test_controller.py` with a fake engine (implements the Stage 3 protocol) alongside the existing mocks: happy streamed path — press installs the buffer listener and starts the engine, sink callbacks emit `caption` UIEvents (with `partial`/`dimmed` fields), release finishes the engine, `transcribe` is **not** called, compound text feeds `clean` and `paste`; `make_engine` → `None` → today's exact flow, zero caption events (R2 also guarded by every pre-existing controller test passing unmodified); mid-stream `on_engine_error` → `caption_unavailable` + batch branch; `finish()` `ok=False` / empty compound → batch branch; cleanup failure after a streamed dictation → error event, nothing pasted (R8); gates fire before transcript use, engine finished with 0.5s timeout, streamed seconds still recorded; stale generation discards streamed results; toggle mode streams identically; `abort_stream()` finishes and discards; usage recorded via `config.add_usage` with `pricing.dictation_cost` wired in; permission-denied pointer event emitted once per run (R7). Expected initial failure: `AttributeError` on the new `UIEvent` fields / `TypeError: UIEvent.__init__() got an unexpected keyword argument 'partial'`.
2. Run `uv run pytest tests/test_controller.py -q` — confirm the expected failures and that all pre-existing tests still pass.
3. Implement: extend `UIEvent` (`partial: bool = False`, `dimmed: bool = False`, `text2: str = ""`); new kinds `caption`/`caption_unavailable`; engine lifecycle in `on_hotkey_press`/`_stop_and_process`/`_process` per design control flow; sink using `CompoundTranscript`; `abort_stream()`; usage + cost recording.
4. Run `uv run pytest -q` — confirm pass; whole suite green (this is the R2 characterisation guard).

**Definition of done:**
- Every row of the design's failure/edge table has a test taking the batch branch.
- All pre-existing controller tests pass without modification of their assertions (streaming-off path byte-identical).
- `uv run python -c "import mini_whisper.app …"` build check still exit 0.

**Risks specific to this stage:** largest stage of the plan; kept atomic because the streamed path and its fallback cannot be reviewed separately without shipping a state where streaming succeeds but failure paths are undefined. Threading (worker vs sink callbacks) reviewed carefully against the non-blocking requirement (R16).

### Stage 9 — Caption bar window and app event wiring
**Goal:** the detached caption bar renders live/dimmed/unavailable text below the dots card, driven by `caption` events in the poll loop.
**Design references:** §3 R4/R18, §5 `overlay.py — CaptionBarWindow`, §5 `app.py` changes; accepted mockup [caption-bar](./mockups/mockup-v1-caption-bar.html).
**Category:** Platform-only / UI wiring — AppKit windows have no unit tests in this codebase (per design §5 Testing strategy); verified by build check + manual acceptance.
**Touches:** `src/mini_whisper/overlay.py` (new `CaptionBarWindow` class), `src/mini_whisper/app.py` (`_poll_ui_events`, `_quit`).

**Steps:**
1. Implement `CaptionBarWindow` following `DotsOverlayWindow`'s conventions (borderless 480×92 floating `NSWindow`, black 0.7-alpha, radius 16, 14pt below the dots window, horizontally centred on it): `set_text(text, partial, dimmed)` rendering last 3 wrapped lines (older 0.45 alpha, current 0.92, blinking cursor when `partial`), `show_unavailable()`, `hide()`, `cleanup()`; redraw only on text change (no timer).
2. Wire `app.py:_poll_ui_events`: `caption` → `set_text`, `caption_unavailable` → `show_unavailable`, hide on `idle`/`result`/`error`; `_quit` calls `controller.abort_stream()` and cleans the caption window up with the overlay.
3. Run `uv run pytest -q` (no regressions) and the build check `uv run python -c "import mini_whisper.overlay, mini_whisper.settings, mini_whisper.app"` (exit 0).
4. Manual verification (`uv run mini-whisper`): live text within ~1s while speaking (on-device engine); dimmed text with cursor removed during processing; unavailable line on a forced engine failure; bar hidden when streaming disabled.

**Definition of done:** manual checklist above passes; suite and import check green.

**Risks specific to this stage:** text layout/wrapping fidelity vs the mockup is judged by eye; spacing constants kept as module constants for easy adjustment.

### Stage 10 — Settings "Live Streaming" section and menu usage rows
**Goal:** the streaming toggle, engine popup, and cloud key fields appear in Settings; the menu shows the two usage/cost rows.
**Design references:** §3 R11/R12/R13, §5 `settings.py`/`app.py` changes, §5 Interfaces; accepted mockup.
**Category:** Hybrid — the `usage`-event payload change is host-testable TDD; the AppKit settings section and menu rows are platform-only/UI wiring (no unit tests for AppKit in this codebase), integration-verified remainder via the manual checklist below.
**Touches:** `src/mini_whisper/settings.py`, `src/mini_whisper/app.py`, `src/mini_whisper/controller.py` (usage event payload), `tests/test_controller.py`.

**Steps:**
1. Write test (TDD portion): the `usage` UIEvent now carries `text` = today row and `text2` = month row, both produced by `pricing.format_usage_rows` (assert against known usage totals). Expected initial failure: assertion mismatch — payload still the legacy `"<in> / <out>"` string.
2. Run — confirm failure; implement in `controller.py`; app's `_poll_ui_events` assigns `usage_item.title = event.text` and the new month item's title from `event.text2` (no parsing). Remove the now-unused `_fmt_tokens` from `app.py` (its k-abbreviation style lives on in `pricing.format_usage_rows`) and the legacy `" / "` split. Run — confirm pass + suite green.
3. Implement the Settings section per mockup, reusing existing patterns (`_add_section_label`, checkbox `settings.py:344-355`, `_ButtonTarget` `settings.py:103-114`, key-save flow `settings.py:489`): `Enable Live Transcript` checkbox, `Engine` `NSPopUpButton` (`On-device (free, offline)`, `OpenAI`, `ElevenLabs`, `Speechmatics`), ElevenLabs/Speechmatics key fields with Save buttons storing via the Stage 1 Keychain accessors (placeholder dots once set, never echoed). Window height extended as needed.
4. Add the second menu row (`Month: $…`) in `app.py.__init__`, initial values from `config.usage_totals()` + `pricing.format_usage_rows`.
5. Run `uv run pytest -q` + import build check. Manual verification: settings round-trip of toggle/engine/keys (keys land in Keychain, not on disk); a cloud engine selectable with no key saved (R13); menu rows update after a dictation.

**Definition of done:** usage-event payload unit-tested; manual checklist passes; selecting each engine persists to `config.json`.

**Risks specific to this stage:** settings window vertical layout is hand-computed y-offsets — verify no control overlap at the new height.

### Stage 11 — Packaging: py2app plist and bundled dependencies
**Goal:** the built .app bundles the new dependencies and carries the Speech permission string.
**Design references:** §5 Compatibility / migration, §7 bundling risk, §9.
**Category:** Non-TDD (config-only + integration-verified) — build configuration; verified by building the bundle.
**Touches:** `setup.py` (plist + `includes`), `README.md`/`CHANGELOG.md` release-note bullets (per design §9).

**Steps:**
1. Add `NSSpeechRecognitionUsageDescription` to the py2app plist; add `Speech` and `websockets` to `OPTIONS["includes"]`.
2. Integration verification: run the documented build (`mv pyproject.toml pyproject.toml.bak && python setup.py py2app && mv pyproject.toml.bak pyproject.toml`) and confirm the bundle launches, the Speech prompt appears on first on-device dictation, and a cloud engine connects.
3. Acceptance pass (design §5 Testing strategy, acceptance paragraph): dictate with each engine (keys present) → live text; pull the network mid-dictation → unavailable line + correct batch paste; deny Speech permission → fallback + pointer; check menu rows against `pricing.py` rates for known-length dictations; toggle streaming off → today's exact behaviour.
4. Update `CHANGELOG.md` release notes: caption bar, engine picker (on-device default), Speech permission prompt, optional ElevenLabs/Speechmatics keys, cost rows.

**Definition of done:** local py2app bundle passes the acceptance pass; release notes drafted.

**Risks specific to this stage:** `websockets`/`Speech` bundling under py2app is unverified until this build runs (design §7) — if py2app misses submodules, add explicit `packages` entries.

## Cross-cutting concerns

- **Security** — all three API keys live only in the Keychain via the existing `keyring` pattern (Stage 1 accessors, Stage 10 UI never echoes them); websocket endpoints are module constants (`wss://` only, no user-configurable URLs — no SSRF surface, Stages 5–6); transcript text stays untrusted and flows only through the existing `pbcopy` paste path (Stage 8); keys never appear in logs at any stage.
- **Performance** — tap callback adds one non-blocking listener call (Stage 7) and the engines do conversion/network on their own thread (Stages 3–6); pre-connect buffering capped at 60s (Stage 5); `finish()` timeout 5s bounds added latency (Stages 4–6, exercised in Stage 8); caption redraw only on text change (Stage 9).
- **Observability** — engine lifecycle at INFO with concrete fallback reasons (`no_key`, `permission_denied`, `connect failed`, `finish timeout`), per-event at DEBUG (Stages 4–8); cost rows double as billing observability (Stage 10).
- **Compatibility / migration** — `daily_usage` → `usage` migration is one-shot and lossless for tokens (Stage 1); absent keys default via `DEFAULT_CONFIG` so existing installs upgrade silently; `streaming_enabled: false` is the rollback at every stage; the system stays fully working between stages because nothing calls the streaming package until Stage 8, and Stage 8 lands the fallback in the same commit as the streamed path.

## Verification

After Stage 11: run the acceptance pass from design §5 end-to-end on the built .app — live captions with each of the four engines, batch fallback on forced network loss with a correct paste, Speech-denial fallback with the System Settings pointer, menu cost rows matching `pricing.py` rates for known-length dictations, and byte-for-byte legacy behaviour with streaming toggled off. `uv run pytest -q` green throughout (baseline 49 tests grown by the new suites).

## Risks and open issues

- **Provider wire-protocol drift between design verification (2026-09-01) and implementation** — fixtures in Stages 5–6 pin the assumed schemas; if the live acceptance pass (Stage 11) disagrees, only the affected subclass and its fixture change. Mitigation: batch fallback keeps dictation working regardless.
- **pyobjc Speech callback threading** is not host-testable — the wrapper isolates it; mitigated by the Stage 9/11 manual passes and the 5s finish timeout guaranteeing the pipeline never hangs.
- **py2app bundling of `websockets`/`Speech`** unverified until Stage 11's build — mitigation in that stage (explicit `packages` entries if needed).
- **Stage 8 size** — the largest review unit; mitigated by Stages 3–7 having already tested every component it composes, leaving Stage 8 as wiring plus fallback branches.

## Planning decisions taken

1. **Corrected a design grounding error in place:** the design claimed the repo has no test suite; `tests/` exists (pytest, 49 passing via `uv run pytest`, `conftest.py` fixtures, controller characterisation tests already present). Design §5 Testing strategy updated accordingly; new tests extend the existing suite and conventions instead of establishing them.
2. Usage-row formatting (`format_usage_rows`) lives in `pricing.py` so `controller.py` and `app.py` share it without circular imports — the design specified the row format but not its owner.
3. New dependencies are added in the stage that first imports them (`pyobjc-framework-speech` in Stage 4, `websockets` in Stage 5) rather than all upfront; py2app registration deferred to Stage 11.
4. `usage_totals()` added to `config.py` for the app's startup menu read (design specified the store and the event payload but not the startup read path); Stage 1 keeps the legacy menu format until Stage 10 swaps it.
5. The compound-transcript assembler is a concrete `CompoundTranscript` class in `streaming/base.py` (design described the sink's semantics but not where the state lives), so Stage 8's controller sink stays thin and the semantics are unit-tested once.
6. Stage order regrouped from design §9 only in splitting "cloud engines" into two stages (skeleton+OpenAI, then ElevenLabs+Speechmatics) and pairing the factory with the recorder listener — staging-order choices the plan owns.

## Deviations from the design

None — plan matches design v1 exactly.

## Deviations from plan

- **Stage 5** additionally touched `tests/conftest.py` and `tests/test_on_device.py`: the recording `FakeSink` test double, needed identically by the on-device and websocket engine tests, was hoisted into `tests/conftest.py` instead of being duplicated per file.
- **Stage 5** hardened the skeleton's finish handshake beyond the stage wording: terminal events are honoured only after the end-of-audio message is on the wire, followed by a short subclass-tunable drain window (`drain_after_complete`, 0.2s for OpenAI) — a server-VAD `completed` racing the commit would otherwise end the recv loop and drop the trailing segment.

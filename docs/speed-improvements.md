# Speed Improvements: Press-to-Record Latency

Analysis of the hotkey→record latency in Mini Whisper and whether a native Swift
rewrite would help (May 2026). The primary complaint: a noticeable delay after
tapping the hotkey until recording actually starts.

## Verdict

**A Swift rewrite would *not* significantly reduce the press→record delay.** That
latency lives almost entirely inside Apple's CoreAudio/AVFoundation frameworks,
which Swift and Python-via-pyobjc call *identically*. The cause is architectural,
not language choice, and is fixable in Python. The Python/pyobjc overhead on the
hot path is microseconds — roughly **six orders of magnitude** below the ~470 ms
system cost that dominates.

A direct measurement on this machine: `AVAudioEngine.startAndReturnError_()` takes
**~430–480 ms per call**, consistently (5 cycles: 432/472/478/468/469 ms).

## Where the delay actually is

The path on every press:
`pynput` event tap → `Controller.on_hotkey_press` → `play_sound("on")` →
`recorder.start()` → `engine.startAndReturnError_()`.

| Segment | Latency per press | Python's fault? |
|---|---|---|
| Event capture (`pynput` / CGEventTap) | < 0.5 ms | No — same `CGEventTapCreate` a Swift app uses |
| **`AVAudioEngine` start** (`recorder.py:105`) | **~470 ms measured; 2–5 s if mic idle** | No — pure CoreAudio/HAL system cost |
| First-buffer delivery (`buf_size=4096`, `recorder.py:71`) | ~85 ms before first samples arrive | No — buffer-size choice, language-agnostic |
| Overlay appears (100 ms poll timer, `app.py:104`) | +0–100 ms (avg ~50 ms) *perceived* | Yes — self-imposed design, fixable in Python |
| 60 fps overlay draw while recording (`overlay.py:130-144`) | ~7.6 ms/frame typ., ~17 ms worst (budget is 16.7 ms) | Yes — fixable in Python |

### The root cause

`recorder.stop()` calls `engine.stop()` after **every** recording
(`recorder.py:121`), tearing down the CoreAudio I/O unit. So
`engine.startAndReturnError_()` re-activates the audio hardware on **every single
press**.

The module docstring (`recorder.py:1-8`, `:75`) claims `prepare()` makes start
"near-instant" — **this is false.** Per Apple's docs, `stop()` *releases* the
resources `prepare()` allocated, so `prepare()` only ever benefits the very first
press; every press after the first re-warms the hardware from scratch. When the
mic has gone idle (~60 s), macOS powers it down and the next start costs **2–5 s**
(worse over Bluetooth) — the "swallows the first words" effect.

## Where Swift *would* genuinely help (but not for this)

- **App launch time & memory footprint** — compiled binary vs. a bundled Python runtime.
- **Overlay smoothness** — native Core Animation / `CAShapeLayer` / Metal would
  render the dots off the GIL with no per-frame object churn. A rendering win, not
  a press→record win, and also reachable in Python.
- **GIL elimination** generally.

None of these is "the delay until recording starts." Rewriting to fix *this*
problem would port the same `AVAudioEngine` calls and inherit the same ~470 ms.

## Recommendations & Expected Improvement

Baseline today (per press, common case): **~470 ms** start cost + **~50 ms** avg
overlay lag ≈ **~0.5 s of dead time** before recording is visibly underway
(seconds if the mic was idle).

| # | Change | File(s) | Expected improvement | Effort | Risk |
|---|---|---|---|---|---|
| 1 | **Keep the engine running** (start once at init, never `stop()` between recordings; capture already gated by the `_recording` flag) | `recorder.py:105,121` | **~470 ms → ~0 ms** per press (boolean flip). Eliminates the 2–5 s idle cold-start for back-to-back use. **Single biggest win.** | Low | Med (orange dot — see trade-off) |
| 2 | **Show overlay immediately** via main-thread dispatch instead of the 100 ms poll | `controller.py:56`, `app.py:104,121-130` | **−50 ms avg (−100 ms worst)** perceived lag → ~1 frame (~16 ms) | Low | Low |
| 3 | **Reorder** `recorder.start()` before `play_sound("on")`; pre-warm `NSSound` + overlay window at startup | `controller.py:53-54`, `sounds.py`, `app.py` | Removes first-press disk-read/window-alloc hit (~3–15 ms one-time) and starts capture marginally sooner every press | Low | Low |
| 4 | **Reduce `buf_size`** 4096 → ~1024 | `recorder.py:71` | First-sample/overlay reactivity **~85 ms → ~21 ms** | Low | Low (slightly more CPU) |
| 5 | **Lighten overlay draw** — batch lines into one `NSBezierPath`, drop to 30 fps, or go `CALayer`-backed | `overlay.py:41,130-144` | Per-frame draw **~7.6 ms → < 2 ms**; stops blowing the frame budget while recording | Med | Low |
| 6 | **Fix misleading docstring** (`prepare()` does not make start near-instant) | `recorder.py:1-8,75` | Documentation accuracy only | Trivial | None |

**Combined effect of #1–#4:** press→visible-recording drops from **~0.5 s (or
several seconds when idle) to well under ~50 ms** — without a rewrite.

## The one real trade-off

Fix #1 keeps the macOS **orange microphone indicator lit** the whole time the
engine runs, and the current design *deliberately* avoids that (the `recorder.py:75`
comment — "no orange mic dot yet" — is the evidence). Options:

- **(a) Idle-stop hybrid (recommended)** — keep the engine running after first use,
  `stop()` only after ~60 s of inactivity. The dot appears only during active
  dictation sessions; rapid back-to-back presses are instant; only the first press
  after a long idle pays the cold-start.
- **(b) Persistent engine** — accept a permanent orange dot for absolute-zero latency.
- **(c) Warm-on-focus** — start the engine when the app gains focus, stop on blur.

A continuously-running engine should also handle
`AVAudioEngineConfigurationChangeNotification` for device/route switches (AirPods,
USB mics) — the current code reads the hardware format once at init
(`recorder.py:65`) and doesn't really handle this either way.

## Methodology

Findings produced by a multi-agent review: five parallel analysts dissected each
segment of the critical path against the code; an external-research pass pinned the
CoreAudio facts (Apple docs + forums); twelve adversarial verifiers (correctness,
CoreAudio-domain, and pro-Swift-rewrite lenses) stress-tested the four core claims.
The ~470 ms figure was measured directly via pyobjc on this machine.

"""Incremental PCM converter: hardware-rate float32 → target-rate int16 LE bytes.

Same linear-interpolation resampling as recorder._resample, generalised to
stateful chunked operation: the fractional resample position carries across
chunks, so boundaries introduce no dropped or duplicated samples. Pure
function of (numpy array, state) → (bytes, state).
"""

import numpy as np


def make_state(orig_sr: float, target_sr: float) -> dict:
    return {
        "ratio": float(orig_sr) / float(target_sr),  # input samples per output sample
        "next_out": 0,  # next global output-sample index to emit
        "total_in": 0,  # global input samples consumed so far
        "tail": np.empty(0, dtype=np.float32),  # input tail still needed for interpolation
    }


def convert(samples: np.ndarray, state: dict) -> tuple[bytes, dict]:
    """Convert one chunk; returns (int16 LE bytes, new state)."""
    ratio = state["ratio"]
    tail = state["tail"]
    base = state["total_in"] - len(tail)  # global index of buf[0]
    buf = np.concatenate([tail, samples]) if len(tail) else np.asarray(samples)
    total_in = state["total_in"] + len(samples)

    next_out = state["next_out"]
    # Output j sits at input position j*ratio; emit while fully determined by seen input
    j_max = int(np.floor((total_in - 1) / ratio)) if total_in else -1

    out = b""
    if j_max >= next_out:
        js = np.arange(next_out, j_max + 1)
        positions = js * ratio - base
        values = np.interp(positions, np.arange(len(buf)), buf)
        out = (np.clip(values, -1.0, 1.0) * 32767).astype("<i2").tobytes()
        next_out = j_max + 1

    keep_from = min(max(int(np.floor(next_out * ratio)) - base, 0), len(buf))
    new_state = {
        "ratio": ratio,
        "next_out": next_out,
        "total_in": total_in,
        "tail": buf[keep_from:],
    }
    return out, new_state

"""Tests for mini_whisper/streaming/audio_convert.py."""

import numpy as np
import pytest

from mini_whisper.recorder import _resample
from mini_whisper.streaming.audio_convert import convert, make_state


def _batch_bytes(audio: np.ndarray, orig_sr: float, target_sr: float) -> bytes:
    """Whole-buffer reference path: recorder resample + int16 conversion."""
    resampled = _resample(audio, orig_sr, target_sr)
    clipped = np.clip(resampled, -1.0, 1.0)
    return (clipped * 32767).astype(np.int16).tobytes()


def _signal(n: int, sr: float) -> np.ndarray:
    rng = np.random.default_rng(42)
    t = np.arange(n) / sr
    sine = 0.6 * np.sin(2 * np.pi * 440.0 * t)
    noise = 0.05 * rng.standard_normal(n)
    return (sine + noise).astype(np.float32)


def _convert_chunked(audio: np.ndarray, orig_sr: float, target_sr: float,
                     chunk_sizes: list[int]) -> bytes:
    state = make_state(orig_sr, target_sr)
    out = b""
    pos = 0
    i = 0
    while pos < len(audio):
        size = chunk_sizes[i % len(chunk_sizes)]
        chunk_bytes, state = convert(audio[pos:pos + size], state)
        out += chunk_bytes
        pos += size
        i += 1
    return out


def _assert_parity(chunked: bytes, batch: bytes):
    a = np.frombuffer(chunked, dtype=np.int16)
    b = np.frombuffer(batch, dtype=np.int16)
    assert len(a) == len(b)
    assert np.max(np.abs(a.astype(np.int32) - b.astype(np.int32))) <= 1


def test_single_call_matches_batch_48k_to_24k():
    audio = _signal(48000, 48000.0)
    state = make_state(48000.0, 24000.0)
    out, _ = convert(audio, state)
    _assert_parity(out, _batch_bytes(audio, 48000.0, 24000.0))


def test_chunked_matches_batch_48k_to_24k():
    audio = _signal(48000, 48000.0)
    chunked = _convert_chunked(audio, 48000.0, 24000.0, [4096])
    _assert_parity(chunked, _batch_bytes(audio, 48000.0, 24000.0))


def test_chunked_matches_batch_44_1k_to_16k():
    audio = _signal(44100, 44100.0)
    chunked = _convert_chunked(audio, 44100.0, 16000.0, [4096])
    _assert_parity(chunked, _batch_bytes(audio, 44100.0, 16000.0))


@pytest.mark.parametrize("orig_sr,target_sr,n", [
    (48000.0, 24000.0, 48000),
    (44100.0, 16000.0, 44100),
])
def test_odd_chunk_sizes_carry_state(orig_sr, target_sr, n):
    """Fractional resample position survives odd chunk boundaries: no drops/dups."""
    audio = _signal(n, orig_sr)
    chunked = _convert_chunked(audio, orig_sr, target_sr, [7, 333, 1024, 1, 4095, 250])
    _assert_parity(chunked, _batch_bytes(audio, orig_sr, target_sr))


def test_output_is_int16_le():
    audio = np.full(4800, 0.5, dtype=np.float32)
    out, _ = convert(audio, make_state(48000.0, 24000.0))
    samples = np.frombuffer(out, dtype="<i2")
    assert len(samples) > 0
    assert np.all(np.abs(samples.astype(np.int32) - 16383) <= 1)


def test_clipping():
    audio = np.full(4800, 1.5, dtype=np.float32)
    out, _ = convert(audio, make_state(48000.0, 24000.0))
    samples = np.frombuffer(out, dtype="<i2")
    assert np.all(samples == 32767)


def test_same_rate_passthrough():
    audio = _signal(16000, 16000.0)
    chunked = _convert_chunked(audio, 16000.0, 16000.0, [1000])
    _assert_parity(chunked, _batch_bytes(audio, 16000.0, 16000.0))


def test_empty_chunk_is_noop():
    state = make_state(48000.0, 24000.0)
    out, state = convert(np.empty(0, dtype=np.float32), state)
    assert out == b""
    audio = _signal(4800, 48000.0)
    out2, _ = convert(audio, state)
    assert len(out2) > 0

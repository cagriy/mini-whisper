"""Tests for mini_whisper/pricing.py."""

import pytest

from mini_whisper.pricing import PER_MINUTE, PER_MTOK, dictation_cost, format_usage_rows


# ---------------------------------------------------------------------------
# dictation_cost: per-minute streaming rates
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("engine,rate_key", [
    ("openai", "openai_realtime"),
    ("elevenlabs", "elevenlabs"),
    ("speechmatics", "speechmatics"),
    ("on_device", "on_device"),
])
def test_per_minute_rate(engine, rate_key):
    assert dictation_cost(engine, 60.0, {}) == pytest.approx(PER_MINUTE[rate_key])


def test_on_device_is_free():
    assert dictation_cost("on_device", 600.0, {}) == 0.0


def test_no_engine_no_minute_cost():
    assert dictation_cost(None, 60.0, {}) == 0.0


# ---------------------------------------------------------------------------
# dictation_cost: per-Mtok maths
# ---------------------------------------------------------------------------

def test_token_cost_transcribe():
    usage = {"gpt-4o-mini-transcribe": {"input_tokens": 1_000_000, "output_tokens": 0}}
    assert dictation_cost(None, 0.0, usage) == pytest.approx(PER_MTOK["gpt-4o-mini-transcribe_in"])


def test_token_cost_combined_models():
    usage = {
        "gpt-4o-mini-transcribe": {"input_tokens": 2_000_000, "output_tokens": 1_000_000},
        "gpt-4o-mini": {"input_tokens": 1_000_000, "output_tokens": 500_000},
    }
    expected = (2 * 1.25) + (1 * 5.00) + (1 * 0.15) + (0.5 * 0.60)
    assert dictation_cost(None, 0.0, usage) == pytest.approx(expected)


def test_streamed_plus_token_cost():
    usage = {"gpt-4o-mini": {"input_tokens": 1_000_000, "output_tokens": 0}}
    expected = 2 * PER_MINUTE["elevenlabs"] + PER_MTOK["gpt-4o-mini_in"]
    assert dictation_cost("elevenlabs", 120.0, usage) == pytest.approx(expected)


# ---------------------------------------------------------------------------
# dictation_cost: overrides and rounding
# ---------------------------------------------------------------------------

def test_override_per_minute_rate():
    assert dictation_cost("elevenlabs", 60.0, {}, overrides={"elevenlabs": 0.01}) == pytest.approx(0.01)


def test_override_per_mtok_rate():
    usage = {"gpt-4o-mini": {"input_tokens": 1_000_000, "output_tokens": 0}}
    cost = dictation_cost(None, 0.0, usage, overrides={"gpt-4o-mini_in": 0.30})
    assert cost == pytest.approx(0.30)


def test_override_leaves_other_constants():
    cost = dictation_cost("speechmatics", 60.0, {}, overrides={"elevenlabs": 9.99})
    assert cost == pytest.approx(PER_MINUTE["speechmatics"])


def test_cost_rounded_to_six_decimals():
    # 90s of elevenlabs = 1.5 min * 0.0065 = 0.00975 exactly
    assert dictation_cost("elevenlabs", 90.0, {}) == 0.00975


# ---------------------------------------------------------------------------
# format_usage_rows
# ---------------------------------------------------------------------------

def test_format_usage_rows():
    today = {"input_tokens": 1200, "output_tokens": 3400,
             "streamed_seconds": {"on_device": 540, "elevenlabs": 180},
             "cost_usd": 0.08}
    today_row, month_row = format_usage_rows(today, 0.15)
    assert today_row == "Today: 1.2k/3.4k tok · 12m · $0.08"
    assert month_row == "Month: $0.15"


def test_format_usage_rows_small_values():
    today = {"input_tokens": 500, "output_tokens": 40,
             "streamed_seconds": {}, "cost_usd": 0.004}
    today_row, month_row = format_usage_rows(today, 0.004)
    assert today_row == "Today: 500/40 tok · 0m · $0.00"
    assert month_row == "Month: $0.00"


def test_format_usage_rows_zero():
    today = {"input_tokens": 0, "output_tokens": 0, "streamed_seconds": {}, "cost_usd": 0.0}
    today_row, month_row = format_usage_rows(today, 0.0)
    assert today_row == "Today: 0/0 tok · 0m · $0.00"
    assert month_row == "Month: $0.00"


def test_format_usage_rows_partial_minutes_floor():
    today = {"input_tokens": 0, "output_tokens": 0,
             "streamed_seconds": {"on_device": 119.0}, "cost_usd": 0.0}
    today_row, _ = format_usage_rows(today, 0.0)
    assert " 1m " in today_row

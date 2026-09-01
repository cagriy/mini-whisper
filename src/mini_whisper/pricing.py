"""Dictation cost maths and menu usage-row formatting.

Rates are editable defaults; individual constants can be overridden via the
`pricing_overrides` dict in config.json. Pure module — shared by controller
and app without circular imports.
"""

PER_MINUTE = {
    "openai_realtime": 0.017,
    "elevenlabs": 0.0065,
    "speechmatics": 0.0067,
    "on_device": 0.0,
}

PER_MTOK = {
    "gpt-4o-mini-transcribe_in": 1.25,
    "gpt-4o-mini-transcribe_out": 5.00,
    "gpt-4o-mini_in": 0.15,
    "gpt-4o-mini_out": 0.60,
}

# Engine names (StreamingEngine.name) that differ from their rate-table key
_ENGINE_RATE_KEYS = {"openai": "openai_realtime"}


def _rate(table: dict, key: str, overrides: dict | None) -> float:
    if overrides and key in overrides:
        return float(overrides[key])
    return table.get(key, 0.0)


def dictation_cost(
    engine_name: str | None,
    seconds: float,
    token_usage_by_model: dict,
    overrides: dict | None = None,
) -> float:
    """Dollar cost of one dictation.

    engine_name: streaming engine billed for `seconds` of audio (None = batch only).
    token_usage_by_model: {model: {"input_tokens": n, "output_tokens": n}}.
    """
    cost = 0.0
    if engine_name is not None:
        rate_key = _ENGINE_RATE_KEYS.get(engine_name, engine_name)
        cost += (seconds / 60.0) * _rate(PER_MINUTE, rate_key, overrides)
    for model, tokens in token_usage_by_model.items():
        cost += (tokens.get("input_tokens", 0) / 1_000_000) * _rate(PER_MTOK, f"{model}_in", overrides)
        cost += (tokens.get("output_tokens", 0) / 1_000_000) * _rate(PER_MTOK, f"{model}_out", overrides)
    return round(cost, 6)


def _fmt_tokens(n) -> str:
    n = int(n)
    return f"{n / 1000:.1f}k" if n >= 1000 else str(n)


def format_usage_rows(today: dict, month_cost: float) -> tuple[str, str]:
    """Render the two menu rows from today's usage entry and month-to-date cost."""
    minutes = int(sum(today.get("streamed_seconds", {}).values()) // 60)
    today_row = (
        f"Today: {_fmt_tokens(today.get('input_tokens', 0))}/"
        f"{_fmt_tokens(today.get('output_tokens', 0))} tok"
        f" · {minutes}m · ${today.get('cost_usd', 0.0):.2f}"
    )
    month_row = f"Month: ${month_cost:.2f}"
    return today_row, month_row

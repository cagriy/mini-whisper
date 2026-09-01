"""Streaming engine selection: config + API keys + Speech permission gate.

Returns the engine for one dictation, or None with a machine-readable
fallback reason ("disabled" | "no_key" | "permission_denied" |
"permission_undetermined" | "unknown_engine") so the controller can take
the batch path and surface the reason (design §5, R6/R7/R13).
"""

import logging

from mini_whisper.streaming.base import StreamingEngine
from mini_whisper.streaming.on_device import OnDeviceEngine, ensure_authorized
from mini_whisper.streaming.websocket_engine import (
    ElevenLabsEngine,
    OpenAIRealtimeEngine,
    SpeechmaticsEngine,
)

logger = logging.getLogger(__name__)

_CLOUD_ENGINES = {
    "openai": OpenAIRealtimeEngine,
    "elevenlabs": ElevenLabsEngine,
    "speechmatics": SpeechmaticsEngine,
}


def make_engine(cfg: dict, api_keys: dict) -> tuple[StreamingEngine | None, str | None]:
    """Select the streaming engine for one dictation.

    api_keys maps engine name -> API key (None/absent when not configured);
    "openai" carries the app's existing OpenAI key. Returns (engine, None)
    or (None, reason).
    """
    if not cfg.get("streaming_enabled", True):
        return None, "disabled"
    name = cfg.get("streaming_engine", "on_device")
    if name == "on_device":
        status = ensure_authorized()
        if status != "authorized":
            reason = f"permission_{status}"
            logger.info("streaming fallback: %s", reason)
            return None, reason
        return OnDeviceEngine(), None
    engine_cls = _CLOUD_ENGINES.get(name)
    if engine_cls is None:
        logger.info("streaming fallback: unknown engine %r", name)
        return None, "unknown_engine"
    key = api_keys.get(name)
    if not key:
        logger.info("streaming fallback: no key for %s", name)
        return None, "no_key"
    return engine_cls(key), None

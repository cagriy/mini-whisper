"""Streaming engine seam: protocols, result type, and compound-transcript assembly."""

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable


@runtime_checkable
class TranscriptSink(Protocol):
    def on_partial(self, text: str) -> None:
        """Full current-segment text; replaces the previous partial."""
        ...

    def on_final(self, text: str) -> None:
        """A segment is finalised; append to the compound transcript."""
        ...

    def on_engine_error(self, exc: Exception) -> None: ...


@runtime_checkable
class StreamingEngine(Protocol):
    name: str  # "on_device" | "openai" | "elevenlabs" | "speechmatics"

    def start(self, sink: TranscriptSink) -> None:
        """Begin the session (async internally; never blocks the caller)."""
        ...

    def feed(self, pcm_buffer) -> None:
        """AVAudioPCMBuffer from the tap; non-blocking."""
        ...

    def finish(self, timeout: float = 5.0) -> "StreamResult":
        """Flush, close, and return the compound result."""
        ...


def _zero_usage() -> dict:
    return {"input_tokens": 0, "output_tokens": 0, "seconds": 0.0}


@dataclass
class StreamResult:
    text: str = ""  # compound transcript (finalised segments + trailing partial)
    ok: bool = False  # False → caller must fall back to batch
    usage: dict = field(default_factory=_zero_usage)


class CompoundTranscript:
    """Assembles finalised segments plus the trailing partial into one text."""

    def __init__(self):
        self._finals: list[str] = []
        self._partial: str = ""

    def add_partial(self, text: str):
        self._partial = text

    def add_final(self, text: str):
        segment = text.strip()
        if segment:
            self._finals.append(segment)
        self._partial = ""

    @property
    def text(self) -> str:
        parts = list(self._finals)
        partial = self._partial.strip()
        if partial:
            parts.append(partial)
        return " ".join(parts)

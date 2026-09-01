"""Pipeline controller: record → transcribe → clean → paste.

Orchestrates all components and communicates with the UI via a queue.
With streaming enabled, a StreamingEngine transcribes live while recording
(caption events) and its compound transcript replaces the batch transcribe
call; every engine failure falls back to the batch pipeline (design §5).
"""

import logging
import queue
import threading
import time
from dataclasses import dataclass

import httpx

from mini_whisper import config, pricing
from mini_whisper.recorder import Recorder
from mini_whisper.sounds import play as play_sound
from mini_whisper.streaming.base import CompoundTranscript
from mini_whisper.streaming.factory import make_engine
from mini_whisper.transcriber import transcribe
from mini_whisper.cleaner import clean
from mini_whisper.paster import paste

logger = logging.getLogger(__name__)

MIN_RECORDING_SECONDS = 0.5
SILENCE_RMS_THRESHOLD = 0.005
HOLD_THRESHOLD_SECONDS = 0.3

SPEECH_PERMISSION_POINTER = (
    "Live transcript off: enable Speech Recognition in "
    "System Settings → Privacy & Security."
)


@dataclass
class UIEvent:
    """Event sent from controller to UI via queue."""

    kind: str  # "recording", "recording_toggle", "processing", "idle",
    #            "result", "usage", "error", "caption", "caption_unavailable"
    text: str = ""
    partial: bool = False  # caption: live text, cursor shown
    dimmed: bool = False  # caption: processing, text dimmed
    text2: str = ""  # usage: month row (Stage 10)


class _StreamSink:
    """TranscriptSink assembling the compound transcript into caption events.

    Callbacks arrive on engine threads; everything UI-bound goes through
    ui_queue only (R18).
    """

    def __init__(self, ui_queue: queue.Queue):
        self._queue = ui_queue
        self.compound = CompoundTranscript()
        self.failed = False
        self._unavailable_sent = False
        self._lock = threading.Lock()

    def on_partial(self, text: str) -> None:
        if self.failed:
            return
        self.compound.add_partial(text)
        self._queue.put(UIEvent("caption", self.compound.text, partial=True))

    def on_final(self, text: str) -> None:
        if self.failed:
            return
        self.compound.add_final(text)
        self._queue.put(UIEvent("caption", self.compound.text, partial=True))

    def on_engine_error(self, exc: Exception) -> None:
        self.failed = True
        self.mark_unavailable()

    def mark_unavailable(self) -> None:
        """Emit the caption_unavailable event, at most once per dictation."""
        with self._lock:
            if self._unavailable_sent:
                return
            self._unavailable_sent = True
        self._queue.put(UIEvent("caption_unavailable"))


class Controller:
    def __init__(self):
        self.recorder = Recorder()
        self.ui_queue: queue.Queue[UIEvent] = queue.Queue()
        self._worker: threading.Thread | None = None
        self._press_time: float = 0.0
        self._toggle_active: bool = False
        self._generation: int = 0
        self._engine = None
        self._sink: _StreamSink | None = None
        self._permission_pointer_shown = False  # one per app run (R7)

    def on_hotkey_press(self, hotkey_name: str):
        """Called when a hotkey is pressed — start or stop recording."""
        if self.recorder.is_recording:
            if self._toggle_active:
                self._stop_and_process(hotkey_name)  # second tap → stop
            return
        self._toggle_active = False
        try:
            play_sound("on")
            self.recorder.start()
            self._press_time = time.monotonic()
            self.ui_queue.put(UIEvent("recording"))
        except Exception as e:
            logger.exception("Failed to start recording")
            self.ui_queue.put(UIEvent("error", f"Mic error: {e}"))
            return
        self._start_stream()

    def on_hotkey_release(self, hotkey_name: str):
        """Called when a hotkey is released — stop (hold mode) or arm toggle."""
        if not self.recorder.is_recording or self._toggle_active:
            return
        if time.monotonic() - self._press_time < HOLD_THRESHOLD_SECONDS:
            self._toggle_active = True  # quick tap → toggle mode
            self.ui_queue.put(UIEvent("recording_toggle"))
            return
        self._stop_and_process(hotkey_name)  # long hold → push-to-talk

    # -- streaming session lifecycle ------------------------------------------

    def _start_stream(self):
        """Select and start the streaming engine; never breaks the dictation."""
        try:
            cfg = config.load()
            engine, reason = make_engine(cfg, self._streaming_keys(cfg))
            if engine is None:
                if reason == "permission_denied" and not self._permission_pointer_shown:
                    self._permission_pointer_shown = True
                    self.ui_queue.put(UIEvent("error", SPEECH_PERMISSION_POINTER))
                return
            sink = _StreamSink(self.ui_queue)
            self._engine, self._sink = engine, sink
            self.recorder.set_buffer_listener(engine.feed)
            engine.start(sink)
        except Exception:
            logger.exception("Failed to start streaming — batch fallback")

    @staticmethod
    def _streaming_keys(cfg: dict) -> dict:
        """API keys for make_engine — only the selected engine's key is read."""
        name = cfg.get("streaming_engine", "on_device")
        if name == "openai":
            return {"openai": config.get_api_key()}
        if name in config.STREAMING_KEY_USERNAMES:
            return {name: config.get_streaming_api_key(name)}
        return {}

    def abort_stream(self):
        """Finish and discard any live streaming session (app quit)."""
        engine, self._engine = self._engine, None
        self._sink = None
        if engine is not None:
            self.recorder.set_buffer_listener(None)
            self._discard_stream(engine)

    def _discard_stream(self, engine):
        """Finish an engine whose text is unwanted; billed seconds still count."""
        if engine is None:
            return
        try:
            result = engine.finish(timeout=0.5)
        except Exception:
            logger.exception("Engine finish failed during discard")
            return
        self._record_stream_usage(engine.name, result.usage.get("seconds", 0.0))

    def _record_stream_usage(self, engine_name: str, seconds: float):
        """Record streamed seconds (and their cost) with no dictation result."""
        if seconds <= 0:
            return
        overrides = config.load().get("pricing_overrides")
        cost = pricing.dictation_cost(engine_name, seconds, {}, overrides)
        config.add_usage(
            {"streamed_seconds": {engine_name: seconds}, "cost_usd": cost}
        )

    # -- stop / process ---------------------------------------------------------

    def _stop_and_process(self, hotkey_name: str):
        """Stop recording, validate, and kick off processing."""
        duration = self.recorder.duration_seconds()
        self.recorder.set_buffer_listener(None)
        audio = self.recorder.stop()
        avg_rms = self.recorder.average_rms
        self._toggle_active = False
        engine, sink = self._engine, self._sink
        self._engine, self._sink = None, None

        if duration < MIN_RECORDING_SECONDS or avg_rms < SILENCE_RMS_THRESHOLD:
            self._discard_stream(engine)
            play_sound("off")
            self.ui_queue.put(UIEvent("idle"))
            return

        self.ui_queue.put(UIEvent("processing"))
        if engine is not None and sink is not None and not sink.failed:
            # Caption stays visible, dimmed, while processing (R4)
            self.ui_queue.put(
                UIEvent("caption", sink.compound.text, partial=False, dimmed=True)
            )

        submit = hotkey_name == "paste_submit"
        self._generation += 1
        gen = self._generation

        self._worker = threading.Thread(
            target=self._process, args=(audio, submit, gen, engine, sink), daemon=True
        )
        self._worker.start()

    def _process(self, audio, submit: bool = False, generation: int = 0,
                 engine=None, sink: _StreamSink | None = None):
        """Background worker: finish stream (or transcribe) → clean → paste."""
        try:
            api_key = config.get_api_key()
            if not api_key:
                self._discard_stream(engine)
                self.ui_queue.put(UIEvent("error", "No API key configured"))
                return

            raw_text = None
            transcribe_usage = {"input_tokens": 0, "output_tokens": 0}
            stream_tokens = {"input_tokens": 0, "output_tokens": 0}
            stream_seconds = 0.0
            if engine is not None:
                result = engine.finish()
                stream_seconds = result.usage.get("seconds", 0.0)
                if result.ok and result.text.strip() and not sink.failed:
                    raw_text = result.text.strip()
                    stream_tokens["input_tokens"] = result.usage.get("input_tokens", 0)
                    stream_tokens["output_tokens"] = result.usage.get("output_tokens", 0)
                    logger.info("%s: streamed transcript used", engine.name)
                else:
                    sink.mark_unavailable()
                    logger.info("%s: streamed transcript unusable — batch fallback",
                                engine.name)

            # Transcribe (batch path: streaming off, unavailable, or failed)
            if raw_text is None:
                transcribe_instructions = config.get_transcribe_prompt()
                raw_text, transcribe_usage = transcribe(audio, api_key, transcribe_instructions)
                logger.debug("Transcription raw: %s", raw_text)
            if not raw_text.strip():
                if engine is not None:
                    self._record_stream_usage(engine.name, stream_seconds)
                play_sound("off")
                self.ui_queue.put(UIEvent("idle"))
                return

            # Clean (if enabled)
            cfg = config.load()
            clean_usage = {"input_tokens": 0, "output_tokens": 0}
            token_usage_by_model = {}
            if transcribe_usage["input_tokens"] or transcribe_usage["output_tokens"]:
                token_usage_by_model["gpt-4o-mini-transcribe"] = transcribe_usage
            if cfg.get("cleanup_enabled", True):
                prompt = config.get_prompt()
                final_text, clean_usage = clean(raw_text, api_key, prompt)
                token_usage_by_model["gpt-4o-mini"] = clean_usage
            else:
                final_text = raw_text
            logger.debug("Final text: %s", final_text)

            # Track provider-attributed usage and dollar cost (R9/R10)
            total_in = (transcribe_usage["input_tokens"] + clean_usage["input_tokens"]
                        + stream_tokens["input_tokens"])
            total_out = (transcribe_usage["output_tokens"] + clean_usage["output_tokens"]
                         + stream_tokens["output_tokens"])
            engine_name = engine.name if engine is not None else None
            cost = pricing.dictation_cost(
                engine_name, stream_seconds, token_usage_by_model,
                cfg.get("pricing_overrides"),
            )
            provider_usage = {"input_tokens": total_in, "output_tokens": total_out,
                              "cost_usd": cost}
            if engine_name is not None and stream_seconds > 0:
                provider_usage["streamed_seconds"] = {engine_name: stream_seconds}
            totals = config.add_usage(provider_usage)

            # Discard if a newer recording has started since we began processing
            if generation != self._generation:
                logger.debug("Stale worker (gen %d, current %d) — discarding result", generation, self._generation)
                play_sound("off")
                self.ui_queue.put(UIEvent("idle"))
                return

            # Paste into active app
            paste(final_text, submit=submit)
            play_sound("off")
            self.ui_queue.put(UIEvent("result", final_text))
            self.ui_queue.put(UIEvent("usage", f"{totals['input_tokens']} / {totals['output_tokens']}"))

        except httpx.HTTPStatusError as e:
            logger.exception("API request failed")
            if e.response.status_code == 401:
                msg = "Invalid API key — please update in Settings."
            elif e.response.status_code == 429:
                msg = "Rate limited — please wait and try again."
            else:
                msg = f"API error ({e.response.status_code})."
            play_sound("off")
            self.ui_queue.put(UIEvent("error", msg))
        except Exception as e:
            logger.exception("Processing failed")
            play_sound("off")
            self.ui_queue.put(UIEvent("error", str(e)))

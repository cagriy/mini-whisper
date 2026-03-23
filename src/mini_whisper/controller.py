"""Pipeline controller: record → transcribe → clean → paste.

Orchestrates all components and communicates with the UI via a queue.
"""

import logging
import queue
import threading
import time
from dataclasses import dataclass

import httpx

from mini_whisper import config
from mini_whisper.recorder import Recorder
from mini_whisper.sounds import play as play_sound
from mini_whisper.transcriber import transcribe
from mini_whisper.paster import paste

logger = logging.getLogger(__name__)

MIN_RECORDING_SECONDS = 0.5
SILENCE_RMS_THRESHOLD = 0.005
HOLD_THRESHOLD_SECONDS = 0.3


@dataclass
class UIEvent:
    """Event sent from controller to UI via queue."""

    kind: str  # "recording", "recording_toggle", "processing", "idle", "result", "error"
    text: str = ""


class Controller:
    def __init__(self):
        self.recorder = Recorder()
        self.ui_queue: queue.Queue[UIEvent] = queue.Queue()
        self._worker: threading.Thread | None = None
        self._press_time: float = 0.0
        self._toggle_active: bool = False

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

    def on_hotkey_release(self, hotkey_name: str):
        """Called when a hotkey is released — stop (hold mode) or arm toggle."""
        if not self.recorder.is_recording or self._toggle_active:
            return
        if time.monotonic() - self._press_time < HOLD_THRESHOLD_SECONDS:
            self._toggle_active = True  # quick tap → toggle mode
            self.ui_queue.put(UIEvent("recording_toggle"))
            return
        self._stop_and_process(hotkey_name)  # long hold → push-to-talk

    def _stop_and_process(self, hotkey_name: str):
        """Stop recording, validate, and kick off processing."""
        duration = self.recorder.duration_seconds()
        audio = self.recorder.stop()
        avg_rms = self.recorder.average_rms
        self._toggle_active = False

        if duration < MIN_RECORDING_SECONDS:
            play_sound("off")
            self.ui_queue.put(UIEvent("idle"))
            return

        if avg_rms < SILENCE_RMS_THRESHOLD:
            play_sound("off")
            self.ui_queue.put(UIEvent("idle"))
            return

        self.ui_queue.put(UIEvent("processing"))

        submit = hotkey_name == "paste_submit"

        self._worker = threading.Thread(
            target=self._process, args=(audio, submit), daemon=True
        )
        self._worker.start()

    def _process(self, audio, submit: bool = False):
        """Background worker: transcribe → paste."""
        try:
            api_key = config.get_api_key()
            if not api_key:
                self.ui_queue.put(UIEvent("error", "No API key configured"))
                return

            # Transcribe (with cleanup prompt if enabled)
            cfg = config.load()
            prompt = config.get_prompt() if cfg.get("cleanup_enabled", True) else ""
            final_text = transcribe(audio, api_key, prompt)
            logger.debug("Transcribed: %s", final_text)
            if not final_text.strip():
                play_sound("off")
                self.ui_queue.put(UIEvent("idle"))
                return

            # Paste into active app
            paste(final_text, submit=submit)
            play_sound("off")
            self.ui_queue.put(UIEvent("result", final_text))

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

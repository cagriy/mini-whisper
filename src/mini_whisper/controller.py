"""Pipeline controller: record → transcribe → clean → paste.

Orchestrates all components and communicates with the UI via a queue.
"""

import logging
import queue
import threading
from dataclasses import dataclass

from mini_whisper import config
from mini_whisper.recorder import Recorder
from mini_whisper.transcriber import transcribe
from mini_whisper.cleaner import clean
from mini_whisper.paster import paste

logger = logging.getLogger(__name__)

MIN_RECORDING_SECONDS = 0.5


@dataclass
class UIEvent:
    """Event sent from controller to UI via queue."""

    kind: str  # "recording", "processing", "idle", "result", "error"
    text: str = ""


class Controller:
    def __init__(self):
        self.recorder = Recorder()
        self.ui_queue: queue.Queue[UIEvent] = queue.Queue()
        self._worker: threading.Thread | None = None
        self._submit_after_paste: bool = False

    def on_hotkey_press(self, hotkey_name: str):
        """Called when a hotkey is pressed — start recording."""
        if self.recorder.is_recording:
            return
        self._submit_after_paste = hotkey_name == "paste_submit"
        try:
            self.recorder.start()
            self.ui_queue.put(UIEvent("recording"))
        except Exception as e:
            logger.exception("Failed to start recording")
            self.ui_queue.put(UIEvent("error", f"Mic error: {e}"))

    def on_hotkey_release(self, hotkey_name: str):
        """Called when a hotkey is released — stop and process."""
        if not self.recorder.is_recording:
            return

        duration = self.recorder.duration_seconds()
        audio = self.recorder.stop()

        if duration < MIN_RECORDING_SECONDS:
            self.ui_queue.put(UIEvent("idle"))
            return

        self.ui_queue.put(UIEvent("processing"))

        # Capture flag before spawning thread
        submit = self._submit_after_paste

        # Process in background thread
        self._worker = threading.Thread(
            target=self._process, args=(audio, submit), daemon=True
        )
        self._worker.start()

    def _process(self, audio, submit: bool = False):
        """Background worker: transcribe → clean → paste."""
        try:
            api_key = config.get_api_key()
            if not api_key:
                self.ui_queue.put(UIEvent("error", "No API key configured"))
                return

            # Transcribe
            raw_text = transcribe(audio, api_key)
            if not raw_text.strip():
                self.ui_queue.put(UIEvent("idle"))
                return

            # Clean (if enabled)
            cfg = config.load()
            if cfg.get("cleanup_enabled", True):
                prompt = config.get_prompt()
                final_text = clean(raw_text, api_key, prompt)
            else:
                final_text = raw_text

            # Paste into active app
            paste(final_text, submit=submit)
            self.ui_queue.put(UIEvent("result", final_text))

        except Exception as e:
            logger.exception("Processing failed")
            self.ui_queue.put(UIEvent("error", str(e)))

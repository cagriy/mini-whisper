"""Audio recorder using sounddevice.

Records microphone input at 16kHz mono int16 (optimal for Whisper API).
Thread-safe: start() and stop() may be called from different threads.
"""

import io
import threading

import numpy as np
import sounddevice as sd
import soundfile as sf

SAMPLE_RATE = 16000
CHANNELS = 1
DTYPE = "int16"


class Recorder:
    def __init__(self):
        self._frames: list[np.ndarray] = []
        self._stream: sd.InputStream | None = None
        self._lock = threading.Lock()
        self._recording = False

    def _callback(self, indata, frames, time, status):
        """Called by sounddevice for each audio block."""
        if self._recording:
            self._frames.append(indata.copy())

    def start(self):
        """Begin capturing audio from the default microphone."""
        with self._lock:
            self._frames = []
            self._recording = True
            self._stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=CHANNELS,
                dtype=DTYPE,
                callback=self._callback,
            )
            self._stream.start()

    def stop(self) -> io.BytesIO:
        """Stop recording and return audio as a WAV BytesIO buffer."""
        with self._lock:
            self._recording = False
            if self._stream is not None:
                self._stream.stop()
                self._stream.close()
                self._stream = None

            if not self._frames:
                buf = io.BytesIO()
                buf.name = "audio.wav"
                return buf

            audio = np.concatenate(self._frames, axis=0)
            self._frames = []

        buf = io.BytesIO()
        buf.name = "audio.wav"
        sf.write(buf, audio, SAMPLE_RATE, format="WAV", subtype="PCM_16")
        buf.seek(0)
        return buf

    @property
    def is_recording(self) -> bool:
        return self._recording

    def duration_seconds(self) -> float:
        """Approximate duration of recorded audio so far."""
        with self._lock:
            if not self._frames:
                return 0.0
            total_samples = sum(f.shape[0] for f in self._frames)
            return total_samples / SAMPLE_RATE

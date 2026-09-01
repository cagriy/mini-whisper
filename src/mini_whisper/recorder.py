"""Audio recorder using AVAudioEngine for near-instant recording start.

Uses macOS AVAudioEngine with prepare() to preallocate hardware resources
at init time. On hotkey press, startAndReturnError_() is near-instant
since the engine is already prepared.

Hardware captures at native rate (44.1/48kHz) and we resample to 16kHz
at stop time for Whisper API compatibility.

Thread-safe: start() and stop() may be called from different threads.
"""

import io
import logging
import threading

import AVFoundation
import numpy as np
import soundfile as sf

logger = logging.getLogger(__name__)

TARGET_SAMPLE_RATE = 16000


# -- Helpers ---------------------------------------------------------------


def _buffer_to_numpy(pcm_buffer) -> np.ndarray:
    """Extract float32 audio data from an AVAudioPCMBuffer via floatChannelData."""
    frame_len = pcm_buffer.frameLength()
    channel0 = pcm_buffer.floatChannelData()[0]
    raw = channel0.as_buffer(frame_len)
    return np.frombuffer(raw, dtype=np.float32).copy()


def _resample(audio: np.ndarray, orig_sr: float, target_sr: float) -> np.ndarray:
    """Resample audio via linear interpolation (sufficient for speech→Whisper)."""
    if orig_sr == target_sr:
        return audio
    duration = len(audio) / orig_sr
    target_len = int(duration * target_sr)
    x_orig = np.linspace(0, duration, len(audio), endpoint=False)
    x_target = np.linspace(0, duration, target_len, endpoint=False)
    return np.interp(x_target, x_orig, audio)


# -- Recorder --------------------------------------------------------------


class Recorder:
    def __init__(self):
        self._frames: list[np.ndarray] = []
        self._lock = threading.Lock()
        self._recording = False
        self._buffer_listener = None
        self._current_level: float = 0.0
        self._rms_sum: float = 0.0
        self._rms_count: int = 0
        self._avg_rms: float = 0.0

        self._engine = AVFoundation.AVAudioEngine.alloc().init()
        input_node = self._engine.inputNode()

        # Hardware format — typically 44100 or 48000 Hz
        hw_format = input_node.inputFormatForBus_(0)
        self._hw_sample_rate = hw_format.sampleRate()
        logger.info("Hardware sample rate: %s Hz", self._hw_sample_rate)

        # Install tap at hardware rate to avoid internal resampling
        buf_size = 4096
        input_node.installTapOnBus_bufferSize_format_block_(
            0, buf_size, hw_format, self._tap_block
        )

        # Preallocate hardware resources — no orange mic dot yet
        self._engine.prepare()

    def set_buffer_listener(self, fn) -> None:
        """Install (or clear with None) a non-blocking per-tap-buffer callable.

        The listener receives each raw AVAudioPCMBuffer after it has been
        appended to the local accumulation; exceptions are swallowed so
        streaming can never affect the fallback recording (R15/R16).
        """
        self._buffer_listener = fn

    def _tap_block(self, pcm_buffer, when):
        """Callback from AVAudioEngine's input tap (runs on audio thread)."""
        with self._lock:
            if not self._recording:
                return
            try:
                data = _buffer_to_numpy(pcm_buffer)
                self._frames.append(data)
                rms = float(np.sqrt(np.mean(data**2)))
                self._current_level = rms
                self._rms_sum += rms
                self._rms_count += 1
            except Exception:
                logger.exception("Error reading audio buffer")
            listener = self._buffer_listener
            if listener is not None:
                try:
                    listener(pcm_buffer)
                except Exception:
                    logger.exception("Buffer listener raised")

    def start(self):
        """Begin capturing audio from the default microphone.

        Raises:
            RuntimeError: If AVAudioEngine fails to start.
        """
        with self._lock:
            self._frames = []
            self._current_level = 0.0
            self._rms_sum = 0.0
            self._rms_count = 0
            self._recording = True
            success, error = self._engine.startAndReturnError_(None)
            if not success:
                self._recording = False
                raise RuntimeError(f"AVAudioEngine start failed: {error}")

    def stop(self) -> io.BytesIO:
        """Stop recording and return audio as a WAV BytesIO buffer."""
        with self._lock:
            self._recording = False
            self._current_level = 0.0
            self._avg_rms = self._rms_sum / self._rms_count if self._rms_count else 0.0
            frames = self._frames
            self._frames = []

        # Stop engine OUTSIDE the lock: engine.stop() may block until the current
        # _tap_block invocation finishes, and _tap_block also acquires the lock.
        self._engine.stop()

        if not frames:
            buf = io.BytesIO()
            buf.name = "audio.wav"
            return buf

        audio = np.concatenate(frames)

        # Resample from hardware rate to 16kHz
        audio = _resample(audio, self._hw_sample_rate, TARGET_SAMPLE_RATE)

        # Convert float32 [-1,1] to int16
        audio = np.clip(audio, -1.0, 1.0)
        audio_int16 = (audio * 32767).astype(np.int16)

        buf = io.BytesIO()
        buf.name = "audio.wav"
        sf.write(buf, audio_int16, TARGET_SAMPLE_RATE, format="WAV", subtype="PCM_16")
        buf.seek(0)
        return buf

    def close(self):
        """Release the audio tap. Call once at app shutdown."""
        self._engine.inputNode().removeTapOnBus_(0)

    @property
    def average_rms(self) -> float:
        return self._avg_rms

    @property
    def audio_level(self) -> float:
        return self._current_level

    @property
    def is_recording(self) -> bool:
        return self._recording

    def duration_seconds(self) -> float:
        """Approximate duration of recorded audio so far."""
        with self._lock:
            if not self._frames:
                return 0.0
            total_samples = sum(f.shape[0] for f in self._frames)
            return total_samples / self._hw_sample_rate

"""Shared cloud streaming-engine skeleton over websockets, plus subclasses.

The skeleton owns the background thread + asyncio loop, the buffer-until-open
queue (capped at MAX_PRECONNECT_SECONDS of audio), single-shot error
propagation, and the finish handshake with timeout. Subclasses supply only:
name, target_rate, _url(), _headers(), _open_messages(), _encode_chunk(),
_end_messages(), and _handle_event() (design §5).
"""

import asyncio
import base64
import json
import logging
import queue
import threading

import websockets

from mini_whisper.recorder import _buffer_to_numpy
from mini_whisper.streaming.audio_convert import convert, make_state
from mini_whisper.streaming.base import CompoundTranscript, StreamResult

logger = logging.getLogger(__name__)

MAX_PRECONNECT_SECONDS = 60.0

OPENAI_REALTIME_URL = "wss://api.openai.com/v1/realtime"
OPENAI_REALTIME_MODEL = "gpt-live-transcribe"
ELEVENLABS_REALTIME_URL = (
    "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
    "?model_id=scribe_v2_realtime&audio_format=pcm_16000"
)
SPEECHMATICS_REALTIME_URL = "wss://eu.rt.speechmatics.com/v2"


class WebSocketEngine:
    """Base class for the cloud streaming engines. Not an engine by itself."""

    name = ""
    target_rate = 16000
    # Quiet window (s) to scoop straggler events after the terminal one; for
    # providers whose terminal event may race trailing transcript events.
    drain_after_complete = 0.0

    def __init__(self, api_key: str, connect=None):
        self._api_key = api_key
        # Injection seam for tests: async callable returning a websocket-like
        # object with async send/recv/close.
        self._connect = connect or self._default_connect
        self._sink = None
        self._compound = CompoundTranscript()
        self._queue: queue.Queue = queue.Queue()  # (samples, rate) | None = end
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._open = threading.Event()
        self._finishing = threading.Event()
        self._end_sent = threading.Event()  # end-of-audio message on the wire
        self._done = threading.Event()  # terminal event received, or failed
        self._failed = threading.Event()
        self._fail_lock = threading.Lock()
        self._buffered_seconds = 0.0  # audio queued while not yet open
        self._fed_seconds = 0.0
        self._input_tokens = 0
        self._output_tokens = 0

    # -- public lifecycle (StreamingEngine protocol) -------------------------

    def start(self, sink) -> None:
        self._sink = sink
        self._thread = threading.Thread(
            target=self._thread_main, name=f"stream-{self.name}", daemon=True
        )
        self._thread.start()

    def feed(self, pcm_buffer) -> None:
        if self._failed.is_set() or self._finishing.is_set():
            return
        try:
            samples, rate = self._extract(pcm_buffer)
        except Exception:
            logger.exception("%s: buffer extraction failed", self.name)
            return
        self._fed_seconds += len(samples) / rate
        if not self._open.is_set():
            self._buffered_seconds += len(samples) / rate
            if self._buffered_seconds > MAX_PRECONNECT_SECONDS:
                self._fail(RuntimeError(
                    f"{self.name}: connection not open after "
                    f"{MAX_PRECONNECT_SECONDS:.0f}s of buffered audio"
                ))
                return
        self._queue.put_nowait((samples, rate))

    def finish(self, timeout: float = 5.0) -> StreamResult:
        self._finishing.set()
        self._queue.put_nowait(None)
        finished = self._done.wait(timeout)
        if not finished:
            logger.info("%s: finish timeout after %.1fs", self.name, timeout)
            self._failed.set()
        self._stop_loop()
        usage = {
            "input_tokens": self._input_tokens,
            "output_tokens": self._output_tokens,
            "seconds": self._fed_seconds,
        }
        if self._failed.is_set():
            return StreamResult(text="", ok=False, usage=usage)
        logger.info("%s: session finished", self.name)
        return StreamResult(text=self._compound.text, ok=True, usage=usage)

    # -- engine thread --------------------------------------------------------

    def _thread_main(self) -> None:
        try:
            asyncio.run(self._run())
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            self._fail(exc)

    async def _run(self) -> None:
        self._loop = asyncio.get_running_loop()
        try:
            ws = await self._connect()
        except Exception as exc:
            self._fail(exc)
            return
        self._open.set()
        logger.info("%s: websocket open", self.name)
        try:
            for message in self._open_messages():
                await ws.send(message)
            recv_task = asyncio.create_task(self._recv_loop(ws))
            try:
                await self._send_loop(ws)
                await recv_task
            finally:
                if not recv_task.done():
                    recv_task.cancel()
        except Exception as exc:
            self._fail(exc)
        finally:
            try:
                await ws.close()
            except Exception:
                pass

    async def _send_loop(self, ws) -> None:
        loop = asyncio.get_running_loop()
        state = None
        state_rate = None
        try:
            while not self._failed.is_set():
                item = await loop.run_in_executor(None, self._queue.get)
                if item is None:
                    for message in self._end_messages():
                        await ws.send(message)
                    self._end_sent.set()
                    return
                samples, rate = item
                if state is None or rate != state_rate:
                    state = make_state(rate, self.target_rate)
                    state_rate = rate
                pcm, state = convert(samples, state)
                if pcm:
                    await ws.send(self._encode_chunk(pcm))
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self._fail(exc)

    async def _recv_loop(self, ws) -> None:
        while True:
            try:
                raw = await ws.recv()
                complete = self._handle_event(raw)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self._fail(exc)
                return
            # Terminal only once our end-of-audio message is on the wire; a
            # server-VAD "completed" processed earlier must not end the loop.
            if complete and self._end_sent.is_set():
                if self.drain_after_complete:
                    await self._drain(ws, self.drain_after_complete)
                self._done.set()
                return

    async def _drain(self, ws, quiet: float) -> None:
        """Scoop events still in flight until the socket is quiet."""
        while True:
            try:
                raw = await asyncio.wait_for(ws.recv(), quiet)
            except (TimeoutError, asyncio.TimeoutError):
                return
            except asyncio.CancelledError:
                raise
            except Exception:
                return
            try:
                self._handle_event(raw)
            except Exception:
                return

    def _stop_loop(self) -> None:
        loop = self._loop
        if loop is None or not loop.is_running():
            return

        def _cancel_all():
            for task in asyncio.all_tasks():
                task.cancel()

        loop.call_soon_threadsafe(_cancel_all)

    async def _default_connect(self):
        return await websockets.connect(self._url(), additional_headers=self._headers())

    # -- helpers for subclasses ----------------------------------------------

    @staticmethod
    def _extract(pcm_buffer):
        """AVAudioPCMBuffer → (float32 samples copy, hardware sample rate)."""
        return _buffer_to_numpy(pcm_buffer), float(pcm_buffer.format().sampleRate())

    def _emit_partial(self, text: str) -> None:
        self._compound.add_partial(text)
        if self._sink is not None:
            self._sink.on_partial(text)

    def _emit_final(self, text: str) -> None:
        self._compound.add_final(text)
        if self._sink is not None:
            self._sink.on_final(text)

    def _add_tokens(self, input_tokens, output_tokens) -> None:
        self._input_tokens += int(input_tokens or 0)
        self._output_tokens += int(output_tokens or 0)

    def _fail(self, exc: Exception) -> None:
        with self._fail_lock:
            if self._failed.is_set():
                return
            self._failed.set()
        logger.info("%s: engine failed: %s", self.name, exc)
        self._done.set()
        if self._sink is not None:
            try:
                self._sink.on_engine_error(exc)
            except Exception:
                logger.exception("sink.on_engine_error raised")

    # -- protocol hooks (subclass responsibilities) ---------------------------

    def _url(self) -> str:
        raise NotImplementedError

    def _headers(self) -> dict:
        raise NotImplementedError

    def _open_messages(self) -> list:
        raise NotImplementedError

    def _encode_chunk(self, pcm: bytes):
        raise NotImplementedError

    def _end_messages(self) -> list:
        raise NotImplementedError

    def _handle_event(self, raw) -> bool:
        """Parse one server message; return True when the stream is complete."""
        raise NotImplementedError


class OpenAIRealtimeEngine(WebSocketEngine):
    """OpenAI Realtime transcription session (design §4, pinned 2026-09-01)."""

    name = "openai"
    target_rate = 24000
    # Server VAD can complete a mid-stream segment concurrently with our
    # commit; drain briefly so the post-commit segment is never dropped.
    drain_after_complete = 0.2

    def __init__(self, api_key: str, connect=None):
        super().__init__(api_key, connect=connect)
        self._delta_acc = ""  # deltas accumulate per segment

    def _url(self) -> str:
        return OPENAI_REALTIME_URL

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self._api_key}"}

    def _open_messages(self) -> list:
        return [json.dumps({
            "type": "session.update",
            "session": {
                "type": "transcription",
                "audio": {
                    "input": {
                        "format": {"type": "audio/pcm", "rate": self.target_rate},
                        "transcription": {"model": OPENAI_REALTIME_MODEL},
                        "turn_detection": {"type": "server_vad"},
                    }
                },
            },
        })]

    def _encode_chunk(self, pcm: bytes) -> str:
        return json.dumps({
            "type": "input_audio_buffer.append",
            "audio": base64.b64encode(pcm).decode("ascii"),
        })

    def _end_messages(self) -> list:
        return [json.dumps({"type": "input_audio_buffer.commit"})]

    def _handle_event(self, raw) -> bool:
        event = json.loads(raw)
        etype = event.get("type", "")
        if etype == "conversation.item.input_audio_transcription.delta":
            self._delta_acc += event.get("delta", "")
            self._emit_partial(self._delta_acc)
        elif etype == "conversation.item.input_audio_transcription.completed":
            self._delta_acc = ""
            self._emit_final(event.get("transcript", ""))
            usage = event.get("usage") or {}
            self._add_tokens(usage.get("input_tokens"), usage.get("output_tokens"))
            return True
        elif etype == "error":
            raise RuntimeError(f"openai realtime error: {event.get('error')}")
        return False


class ElevenLabsEngine(WebSocketEngine):
    """ElevenLabs Scribe v2 Realtime websocket (design §4)."""

    name = "elevenlabs"
    target_rate = 16000
    # A VAD-committed segment can race our committing chunk, same as OpenAI.
    drain_after_complete = 0.2

    def _url(self) -> str:
        return ELEVENLABS_REALTIME_URL

    def _headers(self) -> dict:
        return {"xi-api-key": self._api_key}

    def _open_messages(self) -> list:
        return []  # session config travels in the URL query parameters

    def _encode_chunk(self, pcm: bytes) -> str:
        return json.dumps({
            "message_type": "input_audio_chunk",
            "audio_base_64": base64.b64encode(pcm).decode("ascii"),
            "commit": False,
            "sample_rate": self.target_rate,
        })

    def _end_messages(self) -> list:
        return [json.dumps({
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": True,
            "sample_rate": self.target_rate,
        })]

    def _handle_event(self, raw) -> bool:
        event = json.loads(raw)
        mtype = event.get("message_type", "")
        if mtype in ("partial_transcript", "final_transcript"):
            # final_transcript is settled but not yet committed: still partial
            self._emit_partial(event.get("text", ""))
        elif mtype == "committed_transcript":
            self._emit_final(event.get("text", ""))
            return True
        elif mtype == "input_error":
            raise RuntimeError(f"elevenlabs error: {event}")
        return False


class SpeechmaticsEngine(WebSocketEngine):
    """Speechmatics Real-Time v2 websocket (design §4)."""

    name = "speechmatics"
    target_rate = 16000
    # EndOfTranscript is a hard terminal: nothing follows it, no drain needed.

    def __init__(self, api_key: str, connect=None):
        super().__init__(api_key, connect=connect)
        self._seq_no = 0  # binary AddAudio frames sent, for EndOfStream

    def _url(self) -> str:
        return SPEECHMATICS_REALTIME_URL

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self._api_key}"}

    def _open_messages(self) -> list:
        return [json.dumps({
            "message": "StartRecognition",
            "audio_format": {
                "type": "raw",
                "encoding": "pcm_s16le",
                "sample_rate": self.target_rate,
            },
            "transcription_config": {"language": "en", "enable_partials": True},
        })]

    def _encode_chunk(self, pcm: bytes) -> bytes:
        self._seq_no += 1
        return pcm  # binary AddAudio frame

    def _end_messages(self) -> list:
        return [json.dumps({"message": "EndOfStream", "last_seq_no": self._seq_no})]

    def _handle_event(self, raw) -> bool:
        if isinstance(raw, (bytes, bytearray)):
            return False
        event = json.loads(raw)
        mtype = event.get("message", "")
        if mtype == "AddPartialTranscript":
            self._emit_partial(event.get("metadata", {}).get("transcript", ""))
        elif mtype == "AddTranscript":
            self._emit_final(event.get("metadata", {}).get("transcript", ""))
        elif mtype == "EndOfTranscript":
            return True
        elif mtype == "Error":
            raise RuntimeError(
                f"speechmatics error: {event.get('type')}: {event.get('reason')}"
            )
        return False

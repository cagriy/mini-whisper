"""Tests for mini_whisper/streaming/websocket_engine.py — no network.

Engines are driven by FakeSocket, a scripted websocket built from fixture
transcripts of provider events (tests/fixtures/streaming/*.json). Fixture
steps, in order:
  {"await_client": "<type>"}  recv blocks until the client has sent a
                              message of that type ("__binary__" for binary
                              frames; JSON "type"/"message"/"message_type");
                              a dict matches as a key/value subset instead
  {"server": {...}}           deliver this JSON event to the engine
  {"server_binary_ok": true}  (unused placeholder for binary server frames)
  {"server_error": "msg"}     recv raises RuntimeError(msg)
"""

import asyncio
import base64
import json
import threading
import time
from pathlib import Path

import numpy as np
import pytest

from mini_whisper.streaming.audio_convert import convert, make_state
from mini_whisper.streaming.websocket_engine import (
    MAX_PRECONNECT_SECONDS,
    ElevenLabsEngine,
    OpenAIRealtimeEngine,
    SpeechmaticsEngine,
)

from .conftest import FakeSink

FIXTURES = Path(__file__).parent / "fixtures" / "streaming"


def load_steps(name: str) -> list[dict]:
    return json.loads((FIXTURES / name).read_text())["steps"]


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

class FakeBuffer:
    """Stands in for AVAudioPCMBuffer: float32 samples at a hardware rate."""

    def __init__(self, samples, rate: float):
        self._samples = np.asarray(samples, dtype=np.float32)
        self._rate = float(rate)

    def frameLength(self):
        return len(self._samples)

    def floatChannelData(self):
        data = self._samples.tobytes()

        class _Channel:
            def as_buffer(self, n):
                return data

        return [_Channel()]

    def format(self):
        rate = self._rate

        class _Format:
            def sampleRate(self):
                return rate

        return _Format()


def message_type(message) -> str:
    if isinstance(message, (bytes, bytearray)):
        return "__binary__"
    data = json.loads(message)
    return data.get("type") or data.get("message") or data.get("message_type") or ""


def message_matches(message, want) -> bool:
    if isinstance(want, str):
        return message_type(message) == want
    if isinstance(message, (bytes, bytearray)):
        return False
    data = json.loads(message)
    return all(data.get(key) == value for key, value in want.items())


class FakeSocket:
    """Scripted websocket: server events are gated on client sends."""

    def __init__(self, steps):
        self._steps = list(steps)
        self.sent = []
        self.closed = False
        self._cond = None  # created lazily in the engine's event loop
        self._cursor = 0  # sent-messages consumed by await_client steps

    def _condition(self):
        if self._cond is None:
            self._cond = asyncio.Condition()
        return self._cond

    async def send(self, message):
        cond = self._condition()
        async with cond:
            self.sent.append(message)
            cond.notify_all()

    async def recv(self):
        cond = self._condition()
        async with cond:
            while True:
                while self._steps and "await_client" in self._steps[0]:
                    if self._consume_await(self._steps[0]["await_client"]):
                        self._steps.pop(0)
                    else:
                        await cond.wait()
                if not self._steps:
                    await cond.wait()  # script exhausted: block until cancelled
                    continue
                step = self._steps.pop(0)
                if "server_error" in step:
                    raise RuntimeError(step["server_error"])
                return json.dumps(step["server"])

    def _consume_await(self, want) -> bool:
        for i in range(self._cursor, len(self.sent)):
            if message_matches(self.sent[i], want):
                self._cursor = i + 1
                return True
        return False

    async def close(self):
        self.closed = True


def ready_connect(sock):
    async def _connect():
        return sock

    return _connect


def gated_connect(sock, gate: threading.Event, poll: float = 0.005):
    async def _connect():
        while not gate.is_set():
            await asyncio.sleep(poll)
        return sock

    return _connect


def wait_for(predicate, timeout=2.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.005)
    return False


# ---------------------------------------------------------------------------
# Skeleton lifecycle (via the OpenAI subclass)
# ---------------------------------------------------------------------------

def test_feed_before_open_buffers_and_flushes_on_open():
    sock = FakeSocket(load_steps("openai_realtime.json"))
    gate = threading.Event()
    engine = OpenAIRealtimeEngine("sk-test", connect=gated_connect(sock, gate))
    sink = FakeSink()
    engine.start(sink)

    chunk1 = np.linspace(-0.5, 0.5, 4800, dtype=np.float32)
    chunk2 = np.linspace(0.5, -0.5, 4800, dtype=np.float32)
    engine.feed(FakeBuffer(chunk1, 48000))
    engine.feed(FakeBuffer(chunk2, 48000))
    assert sock.sent == []  # nothing on the wire before open

    gate.set()
    result = engine.finish(timeout=5.0)

    assert result.ok is True
    types = [message_type(m) for m in sock.sent]
    assert types == [
        "session.update",
        "input_audio_buffer.append",
        "input_audio_buffer.append",
        "input_audio_buffer.commit",
    ]
    # Appended audio is the stateful 48k→24k conversion of the fed chunks
    state = make_state(48000, 24000)
    expected1, state = convert(chunk1, state)
    expected2, state = convert(chunk2, state)
    sent_pcm = [base64.b64decode(json.loads(m)["audio"]) for m in sock.sent[1:3]]
    assert sent_pcm == [expected1, expected2]


def test_preconnect_buffer_capped_then_engine_fails():
    sock = FakeSocket([])
    engine = OpenAIRealtimeEngine("sk-test", connect=gated_connect(sock, threading.Event()))
    sink = FakeSink()
    engine.start(sink)

    # rate 1.0 → one sample = one second of audio
    engine.feed(FakeBuffer(np.zeros(int(MAX_PRECONNECT_SECONDS)), 1.0))
    assert sink.errors == []
    engine.feed(FakeBuffer(np.zeros(2), 1.0))

    assert len(sink.errors) == 1
    result = engine.finish(timeout=5.0)
    assert result.ok is False


def test_connect_failure_reports_error_once_and_finish_fails_fast():
    async def _connect():
        raise RuntimeError("connection refused")

    engine = OpenAIRealtimeEngine("sk-test", connect=_connect)
    sink = FakeSink()
    engine.start(sink)

    assert wait_for(lambda: len(sink.errors) == 1)
    started = time.monotonic()
    result = engine.finish(timeout=5.0)
    assert time.monotonic() - started < 1.0
    assert result.ok is False
    assert len(sink.errors) == 1


def test_socket_error_reports_error_once_and_finish_fails_fast():
    steps = [{"await_client": "session.update"}, {"server_error": "boom"}]
    engine = OpenAIRealtimeEngine("sk-test", connect=ready_connect(FakeSocket(steps)))
    sink = FakeSink()
    engine.start(sink)

    assert wait_for(lambda: len(sink.errors) == 1)
    started = time.monotonic()
    result = engine.finish(timeout=5.0)
    assert time.monotonic() - started < 1.0
    assert result.ok is False
    assert len(sink.errors) == 1


def test_finish_timeout_returns_not_ok():
    # Server never sends a terminal event → finish must time out to ok=False
    engine = OpenAIRealtimeEngine("sk-test", connect=ready_connect(FakeSocket([])))
    engine.start(FakeSink())
    result = engine.finish(timeout=0.2)
    assert result.ok is False
    assert result.text == ""


# ---------------------------------------------------------------------------
# OpenAI Realtime protocol (fixture-driven)
# ---------------------------------------------------------------------------

def test_openai_happy_path_fixture():
    sock = FakeSocket(load_steps("openai_realtime.json"))
    engine = OpenAIRealtimeEngine("sk-test", connect=ready_connect(sock))
    sink = FakeSink()
    engine.start(sink)

    engine.feed(FakeBuffer(np.zeros(4800, dtype=np.float32), 48000))
    result = engine.finish(timeout=5.0)

    assert result.ok is True
    assert result.text == "hello world again"
    assert sink.partials == ["hello", "hello world", "again"]
    assert sink.finals == ["hello world", "again"]
    # Usage from usage-bearing events; absent usage counts zero
    assert result.usage["input_tokens"] == 12
    assert result.usage["output_tokens"] == 4
    assert result.usage["seconds"] == pytest.approx(0.1)


def test_openai_session_update_shape():
    sock = FakeSocket(load_steps("openai_realtime.json"))
    engine = OpenAIRealtimeEngine("sk-test", connect=ready_connect(sock))
    engine.start(FakeSink())
    engine.feed(FakeBuffer(np.zeros(2400, dtype=np.float32), 24000))
    engine.finish(timeout=5.0)

    session_update = json.loads(sock.sent[0])
    session = session_update["session"]
    assert session["type"] == "transcription"
    audio_input = session["audio"]["input"]
    assert audio_input["format"] == {"type": "audio/pcm", "rate": 24000}
    assert audio_input["transcription"]["model"] == "gpt-live-transcribe"


# ---------------------------------------------------------------------------
# ElevenLabs Scribe v2 Realtime protocol (fixture-driven)
# ---------------------------------------------------------------------------

def test_elevenlabs_happy_path_fixture():
    sock = FakeSocket(load_steps("elevenlabs.json"))
    engine = ElevenLabsEngine("xi-test", connect=ready_connect(sock))
    sink = FakeSink()
    engine.start(sink)

    chunk = np.linspace(-0.5, 0.5, 4800, dtype=np.float32)
    engine.feed(FakeBuffer(chunk, 48000))
    result = engine.finish(timeout=5.0)

    assert result.ok is True
    assert result.text == "hello world again"
    # partial and (settled, uncommitted) final transcripts both replace the partial
    assert sink.partials == ["hello", "hello world", "hello world", "again"]
    assert sink.finals == ["hello world", "again"]
    assert result.usage["input_tokens"] == 0
    assert result.usage["output_tokens"] == 0
    assert result.usage["seconds"] == pytest.approx(0.1)


def test_elevenlabs_message_shapes():
    sock = FakeSocket(load_steps("elevenlabs.json"))
    engine = ElevenLabsEngine("xi-test", connect=ready_connect(sock))
    engine.start(FakeSink())

    chunk = np.linspace(-0.5, 0.5, 4800, dtype=np.float32)
    engine.feed(FakeBuffer(chunk, 48000))
    engine.finish(timeout=5.0)

    messages = [json.loads(m) for m in sock.sent]
    # 16kHz PCM16 chunk, base64, not committed
    first = messages[0]
    assert first["message_type"] == "input_audio_chunk"
    assert first["commit"] is False
    assert first["sample_rate"] == 16000
    expected, _ = convert(chunk, make_state(48000, 16000))
    assert base64.b64decode(first["audio_base_64"]) == expected
    # finish sends an empty committing chunk
    last = messages[-1]
    assert last["message_type"] == "input_audio_chunk"
    assert last["commit"] is True
    assert last["audio_base_64"] == ""


# ---------------------------------------------------------------------------
# Speechmatics Real-Time v2 protocol (fixture-driven)
# ---------------------------------------------------------------------------

def test_speechmatics_happy_path_fixture():
    sock = FakeSocket(load_steps("speechmatics.json"))
    engine = SpeechmaticsEngine("sm-test", connect=ready_connect(sock))
    sink = FakeSink()
    engine.start(sink)

    chunk = np.linspace(-0.5, 0.5, 4800, dtype=np.float32)
    engine.feed(FakeBuffer(chunk, 48000))
    result = engine.finish(timeout=5.0)

    assert result.ok is True
    assert result.text == "hello world again"
    assert sink.partials == ["hello", "hello world", "again"]
    assert sink.finals == ["hello world ", "again"]
    assert result.usage["input_tokens"] == 0
    assert result.usage["output_tokens"] == 0
    assert result.usage["seconds"] == pytest.approx(0.1)


def test_speechmatics_message_shapes():
    sock = FakeSocket(load_steps("speechmatics.json"))
    engine = SpeechmaticsEngine("sm-test", connect=ready_connect(sock))
    engine.start(FakeSink())

    chunk = np.linspace(-0.5, 0.5, 4800, dtype=np.float32)
    engine.feed(FakeBuffer(chunk, 48000))
    engine.finish(timeout=5.0)

    start = json.loads(sock.sent[0])
    assert start["message"] == "StartRecognition"
    assert start["audio_format"] == {
        "type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000,
    }
    assert start["transcription_config"]["enable_partials"] is True
    # audio goes as raw binary AddAudio frames
    binaries = [m for m in sock.sent if isinstance(m, (bytes, bytearray))]
    expected, _ = convert(chunk, make_state(48000, 16000))
    assert binaries == [expected]
    # EndOfStream declares how many audio frames were sent
    end = json.loads(sock.sent[-1])
    assert end == {"message": "EndOfStream", "last_seq_no": 1}

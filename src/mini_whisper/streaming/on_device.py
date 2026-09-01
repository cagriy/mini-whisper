"""On-device streaming engine backed by Apple's Speech framework.

All pyobjc Speech calls live behind the thin _SpeechAPI wrapper so engine
logic is unit-testable with the framework faked (design §5).
"""

import logging
import threading
import time

import Speech

from mini_whisper.streaming.base import CompoundTranscript, StreamResult

logger = logging.getLogger(__name__)

# SFSpeechRecognizerAuthorizationStatus: NotDetermined=0, Denied=1, Restricted=2, Authorized=3
_STATUS_MAP = {0: "undetermined", 1: "denied", 2: "denied", 3: "authorized"}


class _SpeechAPI:
    """Thin wrapper over the pyobjc Speech framework, replaceable in tests."""

    def authorization_status(self) -> int:
        return int(Speech.SFSpeechRecognizer.authorizationStatus())

    def request_authorization(self) -> None:
        # Fire-and-forget: the grant applies from the next dictation (R7).
        Speech.SFSpeechRecognizer.requestAuthorization_(lambda status: None)

    def start_task(self, on_result):
        """Start an on-device recognition session.

        on_result(text: str, is_final: bool, error) is invoked with plain
        Python values for every recogniser callback. Returns the request
        object (append buffers to it; endAudio() flushes). Raises
        RuntimeError when the recogniser is unavailable.
        """
        recognizer = Speech.SFSpeechRecognizer.alloc().init()
        if recognizer is None or not recognizer.isAvailable():
            raise RuntimeError("on-device speech recogniser unavailable")
        request = Speech.SFSpeechAudioBufferRecognitionRequest.alloc().init()
        request.setRequiresOnDeviceRecognition_(True)
        request.setShouldReportPartialResults_(True)

        def handler(result, error):
            if error is not None:
                on_result("", False, error)
            else:
                on_result(
                    str(result.bestTranscription().formattedString()),
                    bool(result.isFinal()),
                    None,
                )

        recognizer.recognitionTaskWithRequest_resultHandler_(request, handler)
        return request


def ensure_authorized(api: _SpeechAPI | None = None) -> str:
    """Return "authorized" | "denied" | "undetermined" for Speech recognition.

    Triggers the system permission prompt when not yet determined.
    """
    api = api or _SpeechAPI()
    status = _STATUS_MAP.get(api.authorization_status(), "denied")
    if status == "undetermined":
        api.request_authorization()
    return status


class OnDeviceEngine:
    name = "on_device"

    def __init__(self, api: _SpeechAPI | None = None):
        self._api = api or _SpeechAPI()
        self._transcript = CompoundTranscript()
        self._done = threading.Event()
        self._failed = False
        self._request = None
        self._sink = None
        self._pre_start: list = []
        self._started_at: float | None = None

    def start(self, sink) -> None:
        self._sink = sink
        self._started_at = time.monotonic()
        try:
            self._request = self._api.start_task(self._on_result)
        except Exception as exc:
            self._fail(exc)
            return
        logger.info("on_device engine started")
        pending, self._pre_start = self._pre_start, []
        for buf in pending:
            self.feed(buf)

    def feed(self, pcm_buffer) -> None:
        if self._failed:
            return
        request = self._request
        if request is None:
            # Session not open yet: buffer and flush on start.
            self._pre_start.append(pcm_buffer)
            return
        try:
            request.appendAudioPCMBuffer_(pcm_buffer)
        except Exception:
            logger.exception("appendAudioPCMBuffer failed")

    def finish(self, timeout: float = 5.0) -> StreamResult:
        seconds = time.monotonic() - self._started_at if self._started_at else 0.0
        usage = {"input_tokens": 0, "output_tokens": 0, "seconds": seconds}
        request = self._request
        if request is not None and not self._failed:
            try:
                request.endAudio()
            except Exception:
                logger.exception("endAudio failed")
        finished = self._done.wait(timeout)
        if self._failed or not finished:
            if not finished:
                logger.info("on_device finish timeout after %.1fs", timeout)
            return StreamResult(text="", ok=False, usage=usage)
        logger.info("on_device engine finished")
        return StreamResult(text=self._transcript.text, ok=True, usage=usage)

    # -- recogniser callback (plain-Python values via _SpeechAPI) -----------

    def _on_result(self, text: str, is_final: bool, error) -> None:
        if error is not None:
            self._fail(error if isinstance(error, Exception) else RuntimeError(str(error)))
            return
        if is_final:
            self._transcript.add_final(text)
            if self._sink is not None:
                self._sink.on_final(text)
            self._done.set()
        else:
            self._transcript.add_partial(text)
            if self._sink is not None:
                self._sink.on_partial(text)

    def _fail(self, exc: Exception) -> None:
        if self._failed:
            return
        self._failed = True
        logger.info("on_device engine failed: %s", exc)
        self._done.set()
        if self._sink is not None:
            try:
                self._sink.on_engine_error(exc)
            except Exception:
                logger.exception("sink.on_engine_error raised")

"""OpenAI audio transcription using gpt-4o-mini-transcribe."""

import io
import logging

import httpx

logger = logging.getLogger(__name__)

TRANSCRIPTION_URL = "https://api.openai.com/v1/audio/transcriptions"
TIMEOUT = 30.0


def transcribe(audio: io.BytesIO, api_key: str, prompt: str = "") -> str:
    """Send audio to OpenAI transcription API and return transcript text.

    Args:
        audio: WAV audio as BytesIO buffer (must have .name attribute).
        api_key: OpenAI API key.
        prompt: Optional prompt to guide transcription style and cleanup.

    Returns:
        Transcribed text string.

    Raises:
        httpx.HTTPStatusError: On API errors.
        ValueError: If audio buffer is empty.
    """
    audio.seek(0)
    data = audio.read()
    if len(data) == 0:
        raise ValueError("Audio buffer is empty")
    audio.seek(0)

    request_data = {
        "model": "gpt-4o-mini-transcribe",
        "response_format": "json",
    }
    if prompt:
        request_data["prompt"] = prompt

    logger.info("Transcribe request: model=%s, prompt=%r", request_data.get("model"), request_data.get("prompt", ""))
    response = httpx.post(
        TRANSCRIPTION_URL,
        headers={"Authorization": f"Bearer {api_key}"},
        files={"file": ("audio.wav", audio, "audio/wav")},
        data=request_data,
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    return response.json().get("text", "")

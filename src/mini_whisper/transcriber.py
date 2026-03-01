"""Whisper API client for speech-to-text transcription."""

import io

import httpx

WHISPER_URL = "https://api.openai.com/v1/audio/transcriptions"
TIMEOUT = 30.0
NO_SPEECH_THRESHOLD = 0.7


def transcribe(audio: io.BytesIO, api_key: str) -> str:
    """Send audio to OpenAI Whisper API and return transcript text.

    Args:
        audio: WAV audio as BytesIO buffer (must have .name attribute).
        api_key: OpenAI API key.

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

    response = httpx.post(
        WHISPER_URL,
        headers={"Authorization": f"Bearer {api_key}"},
        files={"file": ("audio.wav", audio, "audio/wav")},
        data={"model": "whisper-1", "response_format": "verbose_json"},
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    result = response.json()

    segments = result.get("segments", [])
    if segments and all(
        s.get("no_speech_prob", 0) > NO_SPEECH_THRESHOLD for s in segments
    ):
        return ""

    return result["text"]

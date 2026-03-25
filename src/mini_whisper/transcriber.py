"""OpenAI transcription API client using gpt-4o-mini-transcribe."""

import io

import httpx

TRANSCRIPTIONS_URL = "https://api.openai.com/v1/audio/transcriptions"
TIMEOUT = 30.0

_client = httpx.Client()


def transcribe(audio: io.BytesIO, api_key: str, instructions: str = "") -> tuple[str, dict]:
    """Send audio to OpenAI transcription API and return transcript text.

    Args:
        audio: WAV audio as BytesIO buffer (must have .name attribute).
        api_key: OpenAI API key.
        instructions: Optional instructions to guide the transcription.

    Returns:
        Tuple of (transcribed text, usage dict with input_tokens/output_tokens).

    Raises:
        httpx.HTTPStatusError: On API errors.
        ValueError: If audio buffer is empty.
    """
    audio.seek(0)
    data = audio.read()
    if len(data) == 0:
        raise ValueError("Audio buffer is empty")
    audio.seek(0)

    payload = {
        "model": "gpt-4o-mini-transcribe",
        "response_format": "json",
    }
    if instructions:
        payload["instructions"] = instructions

    response = _client.post(
        TRANSCRIPTIONS_URL,
        headers={"Authorization": f"Bearer {api_key}"},
        files={"file": ("audio.wav", audio, "audio/wav")},
        data=payload,
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    result = response.json()

    usage = result.get("usage", {})
    return result["text"], {
        "input_tokens": usage.get("input_tokens", 0),
        "output_tokens": usage.get("output_tokens", 0),
    }

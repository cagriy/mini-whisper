"""LLM text cleanup using GPT-4o-mini."""

import httpx

CHAT_URL = "https://api.openai.com/v1/chat/completions"
MODEL = "gpt-4o-mini"
TIMEOUT = 15.0

_client = httpx.Client()


def clean(text: str, api_key: str, prompt: str) -> tuple[str, dict]:
    """Clean up raw transcript using GPT-4o-mini.

    Args:
        text: Raw transcript from Whisper.
        api_key: OpenAI API key.
        prompt: System prompt for cleanup instructions.

    Returns:
        Tuple of (cleaned text, usage dict with input_tokens/output_tokens).

    Raises:
        httpx.HTTPStatusError: On API errors.
    """
    response = _client.post(
        CHAT_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": MODEL,
            "messages": [
                {"role": "system", "content": prompt},
                {"role": "user", "content": text},
            ],
            "temperature": 0.3,
        },
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    result = response.json()
    usage = result.get("usage", {})
    return result["choices"][0]["message"]["content"].strip(), {
        "input_tokens": usage.get("prompt_tokens", 0),
        "output_tokens": usage.get("completion_tokens", 0),
    }

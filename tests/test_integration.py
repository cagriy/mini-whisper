"""Integration tests: real OpenAI API pipeline with LLM-as-judge eval framework.

Requires OPENAI_API_KEY env var. Run with:
    OPENAI_API_KEY=sk-... pytest tests/ -v -s -m integration
"""

import io
import json
import os
from pathlib import Path

import httpx
import pytest

from mini_whisper.cleaner import CHAT_URL, clean
from mini_whisper.transcriber import transcribe

FIXTURES_DIR = Path(__file__).parent / "fixtures" / "wav"
BUNDLED_PROMPT = Path(__file__).parent.parent / "src" / "mini_whisper" / "resources" / "default_prompt.txt"

SCORE_THRESHOLD = 7.0

JUDGE_PROMPT = """You are evaluating a text cleanup system. You will be given a raw transcript and its cleaned version.

Score the cleanup from 1 to 10 based on these criteria:
- Filler word removal (um, uh, like, you know, so, basically)
- False start / self-correction removal (only corrected version kept)
- Meaning preservation (nothing important lost or added)
- Grammar and punctuation correctness

Respond with ONLY a JSON object with no markdown:
{"score": <1-10>, "reason": "<one sentence explanation>"}"""


@pytest.fixture()
def api_key():
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        pytest.skip("OPENAI_API_KEY not set")
    return key


def judge(raw: str, cleaned: str, api_key: str) -> tuple[float, str]:
    """Score a cleanup using GPT-4o-mini as a judge. Returns (score, reason)."""
    client = httpx.Client()
    response = client.post(
        CHAT_URL,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={
            "model": "gpt-4o-mini",
            "messages": [
                {"role": "system", "content": JUDGE_PROMPT},
                {"role": "user", "content": f"Raw transcript:\n{raw}\n\nCleaned version:\n{cleaned}"},
            ],
            "temperature": 0.0,
        },
        timeout=15.0,
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"].strip()
    data = json.loads(content)
    return float(data["score"]), data["reason"]


@pytest.mark.integration
def test_pipeline_eval(api_key):
    """Transcribe + clean all WAV fixtures, score with LLM judge, assert average >= threshold."""
    wav_files = sorted(FIXTURES_DIR.glob("*.wav"))
    assert len(wav_files) > 0, f"No WAV files found in {FIXTURES_DIR}"

    prompt = BUNDLED_PROMPT.read_text(encoding="utf-8")

    results = []
    for wav_path in wav_files:
        audio = io.BytesIO(wav_path.read_bytes())
        audio.name = wav_path.name

        raw_text, _ = transcribe(audio, api_key)
        assert raw_text.strip(), f"Empty transcription for {wav_path.name}"

        cleaned_text, _ = clean(raw_text, api_key, prompt)
        assert cleaned_text.strip(), f"Empty cleaned text for {wav_path.name}"

        score, reason = judge(raw_text, cleaned_text, api_key)
        results.append({
            "file": wav_path.name,
            "raw": raw_text,
            "cleaned": cleaned_text,
            "score": score,
            "reason": reason,
        })

    print("\n--- Eval scorecard ---")
    for r in results:
        print(f"  {r['file']}: {r['score']:.1f}/10 — {r['reason']}")
        print(f"    raw:     {r['raw']}")
        print(f"    cleaned: {r['cleaned']}")

    avg_score = sum(r["score"] for r in results) / len(results)
    print(f"\n  Average: {avg_score:.1f}/10  (threshold: {SCORE_THRESHOLD})")

    assert avg_score >= SCORE_THRESHOLD, (
        f"Average score {avg_score:.1f} is below threshold {SCORE_THRESHOLD}.\n"
        + "\n".join(f"  {r['file']}: {r['score']:.1f}/10 — {r['reason']}" for r in results)
    )


@pytest.mark.integration
def test_transcribe_invalid_key():
    """Real API rejects invalid credentials with 401."""
    audio = io.BytesIO(b"\x00" * 100)
    audio.name = "audio.wav"
    with pytest.raises(Exception):
        transcribe(audio, "sk-invalid-key-for-testing")

# Transcription Engine Options

Comparison of transcription backends for mini-whisper (March 2026).

## Current Setup

OpenAI Whisper API (`whisper-1`, based on large-v2) → optional GPT-4o-mini cleanup → paste.
Typical end-to-end latency: 2.0–4.5s for 5-10s of audio.

## Options

### 1. OpenAI Whisper API (Current)

- **Latency**: 1.5–3.0s transcription + 0.5–1.5s cleanup
- **Quality**: Excellent (~3% WER English, large-v2)
- **Cost**: ~$0.006/dictation
- **Pros**: Simple HTTP POST, no local resources needed
- **Cons**: Network dependent, slowest option, per-request cost

### 2. mlx-whisper (Local, Apple Silicon)

- **Model**: `mlx-community/whisper-large-v3-turbo` (809M params)
- **Latency**: 300–800ms transcription (+ cleanup if enabled)
- **Quality**: Same as whisper-1 API (large-v3-turbo ≈ large-v2 accuracy)
- **Cost**: ~$0.0001/dictation (only GPT-4o-mini cleanup)
- **Memory**: ~6GB unified memory
- **First run**: ~1.6GB model download
- **Dependencies**: `mlx`, `mlx-whisper`
- **Pros**: Best accuracy, simple Python API, no permission prompts, offline capable
- **Cons**: Large model download, high memory usage, Apple Silicon only

**Recommendation: Best overall choice for local transcription today.**

### 3. SFSpeechRecognizer (Apple, On-Device)

- **Latency**: ~200–500ms batch, ~50–200ms streaming (partial results during recording)
- **Quality**: Good but weaker (~8-15% WER, Siri-level)
- **Cost**: Free
- **Memory**: Minimal
- **Dependencies**: `pyobjc-framework-Speech`
- **Pros**: Zero model download, streaming mode gives near-instant results, tiny footprint
- **Cons**: Lower accuracy (especially technical terms, accents), 1-min per-request limit,
  requires speech recognition permission prompt, complex ObjC callback patterns via PyObjC

Streaming integration would feed `AVAudioPCMBuffer` from the existing `_tap_block` directly
into `SFSpeechAudioBufferRecognitionRequest.appendAudioPCMBuffer_()`.

### 4. SpeechAnalyzer (Apple, macOS Tahoe / macOS 26)

- **Latency**: ~150–400ms (estimated, claimed 2.2x faster than Whisper large-v3-turbo)
- **Quality**: Comparable to Whisper (Apple's claim)
- **Cost**: Free
- **Memory**: Minimal
- **Availability**: macOS 26+ only (not widely deployed as of March 2026)
- **Pros**: Best of both worlds if claims hold — fast, accurate, no model download, no limits
- **Cons**: Requires macOS Tahoe, Swift async API is hard to bridge via PyObjC,
  PyObjC bindings may not be ready yet

**Watch for the future — not ready to adopt today.**

## Comparison Table

| Engine              | Latency (5-10s audio) | WER (English) | Model Size | Memory | Offline |
|---------------------|----------------------|---------------|------------|--------|---------|
| Whisper API         | 1.5–3.0s             | ~3%           | N/A        | Low    | No      |
| mlx-whisper (turbo) | 300–800ms            | ~3%           | 1.6GB      | ~6GB   | Yes     |
| SFSpeechRecognizer  | 50–500ms             | ~8-15%        | Built-in   | Low    | Yes     |
| SpeechAnalyzer      | 150–400ms (est.)     | ~3-5% (claim) | Built-in   | Low    | Yes     |

## Other Local Whisper Implementations

| Implementation          | Backend              | Speed (Apple Silicon) |
|-------------------------|----------------------|-----------------------|
| mlx-whisper             | Apple MLX (GPU)      | Fastest               |
| lightning-whisper-mlx   | MLX + quantization   | Fast (4-bit)          |
| whisper.cpp             | C++ / CoreML / Metal | Fast                  |
| faster-whisper          | CTranslate2 (CPU)    | Moderate              |
| openai/whisper          | PyTorch              | Slowest               |

## Whisper Model Quality Tiers

| Model           | Params | English WER | Speed Factor | Notes                      |
|-----------------|--------|-------------|--------------|----------------------------|
| tiny.en         | 39M    | ~5.6%       | ~10x         | Not recommended             |
| base.en         | 74M    | ~4.2%       | ~7x          |                             |
| small.en        | 244M   | ~3.4%       | ~4x          |                             |
| medium.en       | 769M   | ~3.0%       | ~2x          |                             |
| large-v2        | 1550M  | ~2.7%       | 1x           | = whisper-1 API             |
| large-v3        | 1550M  | ~2.5%       | 1x           | Best accuracy               |
| large-v3-turbo  | 809M   | ~2.7%       | ~8x          | Best speed/accuracy balance |

## Whisper API Language Support

The `language` parameter accepts a single ISO-639-1 code (e.g., `en`). No multi-language
parameter — either specify one language or omit for auto-detection across all 57+ supported
languages. Specifying the language improves accuracy and latency.

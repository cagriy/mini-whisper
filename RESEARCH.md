# Mini-Whisper: Research Notes

## Goal
Build a simple macOS-only dictation app that:
1. Records dictation via a global hotkey
2. Sends audio to STT for transcription
3. Sends transcript to an LLM to clean up (remove filler words, self-corrections, grammar fixes)
4. Pastes the cleaned text into the active application

## Competitive Research

### Superwhisper (Commercial, macOS)
- macOS dictation app using whisper.cpp for local STT
- Hotkey-activated (Option+Space default)
- Processes audio locally (offline-capable)
- Auto-pastes cleaned text into active app
- $8.49/month
- Has an open-source alternative: OpenSuperWhisper

### Wispr Flow (Commercial, Multi-platform)
- AI-powered voice-to-text dictation
- Cloud-based (AWS/Baseten infrastructure)
- Uses custom transformer models + Llama for transcript enhancement
- Auto-removes filler words (um, uh, like), stutters, repetitions
- Applies correct punctuation and capitalization
- <700ms end-to-end latency
- NOT open source, paid plans
- Works across macOS, Windows, iOS, Android

### Whisper-Flow (Open Source Framework)
- GitHub: https://github.com/dimastatz/whisper-flow
- Real-time audio transcription framework
- FastAPI + WebSocket + OpenAI Whisper
- ~275ms median latency on M1 MacBook
- Python-based

## Our Approach: Keep It Simple
Unlike Superwhisper/Wispr Flow, we only need:
- Record → Transcribe (API) → Clean (LLM) → Paste
- No local model inference, no real-time streaming, no personal dictionary
- Menu bar app with a single hotkey
- Cloud APIs for both STT and cleanup

## Proposed Tech Stack
- **Language**: Python (managed with `uv`)
- **Audio recording**: `sounddevice` (records to numpy array → WAV)
- **Menu bar app**: `rumps` (macOS statusbar apps)
- **Global hotkeys**: `pynput`
- **Speech-to-Text**: OpenAI Whisper API
- **LLM cleanup**: OpenAI GPT or Claude API
- **Paste mechanism**: `pbcopy` + simulate Cmd+V via pynput
- **Config**: `.env` file for API keys

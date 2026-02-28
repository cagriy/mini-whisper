# Mini-Whisper: Implementation Plan

## Overview

A macOS menu bar dictation app: press a hotkey, speak, release — transcribed and cleaned text is pasted into the active application.

**Flow:** Hotkey hold → Record audio → Whisper API (STT) → LLM cleanup → Paste into active app

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  macOS Menu Bar                   │
│              (rumps — PyObjC-based)               │
│                                                   │
│  ┌─────────┐  ┌──────────┐  ┌─────────────────┐  │
│  │ Status   │  │ Settings │  │ Quit            │  │
│  │ Icon     │  │ Menu     │  │                 │  │
│  └─────────┘  └──────────┘  └─────────────────┘  │
└──────────┬───────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────┐
│              Core Controller                      │
│  Orchestrates the record→transcribe→paste flow    │
│                                                   │
│  ┌──────────┐  ┌───────────┐  ┌──────────────┐   │
│  │ Hotkey   │  │ Audio     │  │ Paste        │   │
│  │ Listener │  │ Recorder  │  │ Manager      │   │
│  │ (pynput) │  │(sounddev) │  │(pbcopy+pynput│   │
│  └──────────┘  └───────────┘  └──────────────┘   │
│                      │                            │
│              ┌───────▼────────┐                   │
│              │  API Clients   │                   │
│              │ Whisper + LLM  │                   │
│              └────────────────┘                   │
└──────────────────────────────────────────────────┘
```

---

## Tech Stack

| Component         | Library/Tool        | Why                                        |
|-------------------|--------------------|--------------------------------------------|
| Menu bar UI       | `rumps`            | Simplest macOS menu bar framework for Python|
| Global hotkey     | `pynput`           | Global keyboard listener, macOS compatible  |
| Audio recording   | `sounddevice`      | Low-latency, numpy-based audio capture      |
| Audio encoding    | `soundfile`        | Write numpy arrays to WAV files             |
| STT               | OpenAI Whisper API | Cloud-based, fast, accurate                 |
| LLM cleanup       | OpenAI GPT-4o-mini | Remove filler words, fix grammar (same API key) |
| Clipboard         | `subprocess` (pbcopy) | Native macOS clipboard                   |
| Paste simulation  | `pynput`           | Simulate Cmd+V keystroke                    |
| Config            | JSON file          | `~/.config/mini-whisper/` for settings + prompt |
| Secret storage    | `keyring`          | macOS Keychain for API key (no plaintext on disk) |
| HTTP client       | `httpx`            | Async-capable HTTP for API calls            |
| Packaging         | `py2app`           | Native macOS .app bundles (best with rumps) |
| Package manager   | `uv`               | Fast Python package management              |

---

## Project Structure

```
mini-whisper/
├── RESEARCH.md
├── PLAN.md
├── pyproject.toml
├── setup.py                    # py2app configuration
├── .gitignore
├── src/
│   └── mini_whisper/
│       ├── __init__.py
│       ├── app.py              # Entry point — rumps app setup
│       ├── controller.py       # Orchestrates record→transcribe→paste
│       ├── recorder.py         # Audio recording via sounddevice
│       ├── transcriber.py      # Whisper API client
│       ├── cleaner.py          # LLM cleanup client
│       ├── paster.py           # Clipboard + paste simulation
│       ├── hotkey.py           # Global hotkey listener (pynput)
│       ├── config.py           # Settings management (~/.config/mini-whisper/)
│       └── resources/
│           ├── default_prompt.txt  # Default cleanup prompt (bundled)

│           ├── icon.png        # Menu bar icon (idle)
│           ├── icon_rec.png    # Menu bar icon (recording)
│           └── icon_proc.png   # Menu bar icon (processing)
└── tests/
    ├── test_recorder.py
    ├── test_transcriber.py
    ├── test_cleaner.py
    └── test_paster.py
```

---

## Implementation Phases

### Phase 1: Project Scaffold

**Goal:** Runnable project with `uv`, basic menu bar app visible in the status bar.

**Steps:**
1. Initialize `uv` project with `pyproject.toml`
2. Add dependencies: `rumps`, `pynput`, `sounddevice`, `soundfile`, `httpx`, `keyring`
3. Create `src/mini_whisper/` package structure
4. Implement `app.py` — minimal rumps app with an icon, "Quit" menu item
5. Verify it runs: `uv run python -m mini_whisper`
6. Create `.gitignore`

**Deliverable:** A menu bar icon appears; clicking shows a dropdown with "Quit".

---

### Phase 2: Audio Recording

**Goal:** Record audio from the microphone into a WAV buffer.

**Steps:**
1. Implement `recorder.py`:
   - Use `sounddevice.InputStream` in callback mode
   - Settings: 16 kHz sample rate, mono, 16-bit PCM (`int16`)
   - `start()` — begins capturing audio frames into a list
   - `stop()` — stops capture, returns a WAV file as `io.BytesIO`
   - Use `soundfile.write()` to encode numpy array → WAV in memory
2. Implement `config.py`:
   - Config directory: `~/.config/mini-whisper/`
   - `config.json` — stores hotkey combo and cleanup enabled flag (no secrets)
   - `prompt.txt` — stores the LLM cleanup prompt (editable by user)
   - **API key stored in macOS Keychain** via `keyring`:
     - Service: `"mini-whisper"`, username: `"openai-api-key"`
     - `keyring.set_password("mini-whisper", "openai-api-key", key)`
     - `keyring.get_password("mini-whisper", "openai-api-key")`
     - No plaintext API key on disk — Keychain handles encryption and access control
   - On first run, create directory and copy default prompt from bundled resources
   - `load()` / `save()` methods for config.json
   - `get_api_key()` / `set_api_key()` methods wrapping keyring
3. Write `test_recorder.py` — test start/stop cycle, verify WAV output is valid

**Audio format rationale:**
- 16 kHz: Whisper internally resamples to 16 kHz, so recording at this rate avoids wasted bandwidth
- Mono: Speech is single-channel; stereo doubles file size for zero benefit
- WAV/PCM: Lossless, no encoding overhead, Whisper API accepts it directly
- Typical 10-second recording ≈ 320 KB (very small, fast to upload)

**Deliverable:** Can record audio and get a valid WAV `BytesIO` object back.

---

### Phase 3: Whisper API Transcription

**Goal:** Send recorded audio to OpenAI Whisper API, receive transcript.

**Steps:**
1. Implement `transcriber.py`:
   - `transcribe(audio: BytesIO) -> str`
   - POST to `https://api.openai.com/v1/audio/transcriptions`
   - Model: `whisper-1`
   - Send WAV file as multipart form data
   - Use `httpx` for the HTTP call
   - Return the transcript text
   - Handle errors: API errors, empty audio, timeout
2. Write `test_transcriber.py` — mock API response, verify parsing

**Deliverable:** Given a WAV buffer, returns a transcript string.

---

### Phase 4: LLM Text Cleanup

**Goal:** Clean up raw transcript — remove filler words, fix grammar, preserve meaning.

**Steps:**
1. Implement `cleaner.py`:
   - `clean(text: str) -> str`
   - Uses OpenAI GPT-4o-mini (same API key as Whisper — single key for everything)
   - Reads cleanup prompt from `~/.config/mini-whisper/prompt.txt`
   - Default prompt (bundled as `resources/default_prompt.txt`):
     ```
     You are a transcript cleaner. Clean up the following dictated text:
     - Remove filler words (um, uh, like, you know, so, basically)
     - Remove false starts and self-corrections (keep only the corrected version)
     - Fix grammar and punctuation
     - Preserve the speaker's intended meaning exactly
     - Do NOT add, rephrase, or summarize — only clean
     - Return ONLY the cleaned text, nothing else
     ```
   - User can edit `prompt.txt` to customize cleanup behavior (e.g., domain-specific terms, tone)
   - Use `httpx` for API calls (raw HTTP, no SDK dependency)
2. Make cleanup **optional** — toggle in menu bar (default: enabled)
3. Write `test_cleaner.py` — mock API, verify filler removal

**Deliverable:** `"Um so I was like thinking we should uh move the meeting"` → `"I was thinking we should move the meeting."`

---

### Phase 5: Paste into Active Application

**Goal:** Place text on clipboard and simulate Cmd+V in the previously active app.

**Steps:**
1. Implement `paster.py`:
   - `paste(text: str) -> None`
   - Step 1: Save current clipboard contents (optional, for restore later)
   - Step 2: Copy text to clipboard via `subprocess.run(["pbcopy"], input=text.encode())`
   - Step 3: Small delay (50ms) to ensure clipboard is ready
   - Step 4: Simulate Cmd+V using `pynput.keyboard.Controller`
   - Step 5: Restore previous clipboard contents after a short delay (optional)
2. **Important UX detail:** The menu bar app steals focus when clicked. But since we use a hotkey (not a menu click) to trigger recording, the previously active app remains focused. The paste targets whatever app was active when the hotkey was pressed.
3. Write `test_paster.py` — verify clipboard contents after paste call

**Deliverable:** Text appears in whatever application is currently focused.

---

### Phase 6: Global Hotkey

**Goal:** Register a global hotkey that triggers the record→transcribe→paste pipeline.

**Steps:**
1. Implement `hotkey.py`:
   - Use `pynput.keyboard.Listener` for key events
   - Default hotkey: **Cmd+Shift+Space** (avoids conflicts; Ctrl/Alt unreliable on macOS with pynput)
   - **Push-to-talk mode:** Hold hotkey = recording, release = stop and process
   - **Toggle mode (alternative):** Press once to start, press again to stop
   - Start with push-to-talk as default, configurable via settings
   - Run listener in a **background thread** (rumps owns the main thread)
   - Communicate with controller via `threading.Event` or `queue.Queue`
2. **Threading model:**
   ```
   Main thread:     rumps event loop (PyObjC NSRunLoop)
   Thread 2:        pynput keyboard listener
   Thread 3:        Recording + API calls (spawned per dictation)
   ```
   - Use `rumps.Timer` or `objc` dispatch to safely update UI from background threads
   - Never call rumps UI methods directly from pynput thread
3. **Known macOS pynput limitations:**
   - Cmd+Shift combos work; Ctrl and Alt modifiers are unreliable
   - App (or Terminal) must have Accessibility + Input Monitoring permissions
4. Write integration test — simulate key press, verify controller is triggered

**Deliverable:** Hold Cmd+Shift+Space → records; release → transcribes and pastes.

---

### Phase 7: Controller — Tie It All Together

**Goal:** Orchestrate the full pipeline and update menu bar UI state.

**Steps:**
1. Implement `controller.py`:
   - `on_hotkey_press()`:
     1. Update menu bar icon to "recording" state (red dot)
     2. Call `recorder.start()`
   - `on_hotkey_release()`:
     1. Call `recorder.stop()` → get WAV `BytesIO`
     2. Update icon to "processing" state (spinner/yellow)
     3. Call `transcriber.transcribe(audio)` → raw text
     4. Call `cleaner.clean(raw_text)` → cleaned text (if LLM configured)
     5. Call `paster.paste(cleaned_text)`
     6. Update icon back to "idle" state
     7. Show notification with cleaned text (optional, via `rumps.notification`)
   - Handle errors at each step — show notification on failure, reset icon
   - Run steps 2-6 in a background thread (don't block rumps main loop)
2. Wire everything in `app.py`:
   - Create rumps app with menu items: status, settings, history (later), quit
   - Initialize controller, hotkey listener
   - Start pynput listener thread on app launch

**Deliverable:** Complete end-to-end flow works: hotkey → record → transcribe → clean → paste.

---

### Phase 8: Menu Bar UX Polish

**Goal:** Make the app pleasant to use day-to-day.

**Steps:**
1. **Menu layout:**
   ```
   🎙 Mini Whisper
   ─────────────────────────────
   Status: Idle
   Last: "I was thinking we should..."
   ─────────────────────────────
   Set API Key...              → rumps.Window text input dialog
   Change Hotkey...            → key capture mode (see below)
   Edit Cleanup Prompt...      → opens ~/.config/mini-whisper/prompt.txt in default editor
   ☑ Enable Text Cleanup       → toggle on/off
   ─────────────────────────────
   About Mini Whisper
   Quit
   ```
2. **"Set API Key..." flow:**
   - Opens `rumps.Window` with a text input field
   - Pre-fills current key (masked, e.g. `sk-...xxxx`)
   - On submit, saves to **macOS Keychain** via `keyring.set_password()`
   - Validates key format (starts with `sk-`)
   - No plaintext key ever written to disk
3. **"Change Hotkey..." flow (key capture):**
   - Click menu item → menu bar title changes to "Press shortcut..."
   - App enters key capture mode: next key combo pressed is captured
   - Display the captured combo (e.g. "⌘⇧Space") and confirm
   - Save to `config.json`, restart hotkey listener with new combo
   - Timeout after 5 seconds if no key pressed → cancel
   - Must use Cmd or Shift modifiers (Ctrl/Alt unreliable on macOS)
4. **"Edit Cleanup Prompt..." flow:**
   - Opens `~/.config/mini-whisper/prompt.txt` in the default text editor
   - `subprocess.run(["open", prompt_path])`
   - Prompt is re-read on every dictation, so changes take effect immediately
5. **"Enable Text Cleanup" toggle:**
   - Checkbox menu item (rumps supports `state` attribute on menu items)
   - When off, raw Whisper output is pasted directly (faster, no extra API call)
   - State persisted in `config.json`
2. **Visual feedback:**
   - Icon changes: idle (microphone), recording (red dot), processing (hourglass/spinner)
   - Icons should be template images (monochrome, adapts to light/dark menu bar)
   - 16x16 or 18x18 PNG, black on transparent background
3. **Sound feedback (optional):**
   - Short beep on record start/stop (using `NSSound` or `afplay`)
4. **Notifications:**
   - Show macOS notification with transcribed text on completion
   - Show error notification on failure
5. **Error handling:**
   - No API key configured → show alert on first use with setup instructions
   - Network failure → notification + icon reset
   - Empty recording (< 0.5s) → ignore, don't call API

**Deliverable:** Polished, intuitive menu bar experience.

---

### Phase 9: App Bundling with py2app

**Goal:** Package as a standalone `Mini Whisper.app` that runs from /Applications.

**Steps:**
1. Create `setup.py` for py2app:
   ```python
   from setuptools import setup

   APP = ['src/mini_whisper/app.py']
   DATA_FILES = []
   OPTIONS = {
       'argv_emulation': False,
       'iconfile': 'src/mini_whisper/resources/app_icon.icns',
       'plist': {
           'CFBundleName': 'Mini Whisper',
           'CFBundleIdentifier': 'com.cagri.mini-whisper',
           'CFBundleVersion': '0.1.0',
           'CFBundleShortVersionString': '0.1.0',
           'LSUIElement': True,  # Hide from Dock (menu bar only)
           'NSMicrophoneUsageDescription': 'Mini Whisper needs microphone access to record your dictation.',
           'NSAccessibilityUsageDescription': 'Mini Whisper needs accessibility access to detect hotkeys and paste text.',
       },
       'packages': ['mini_whisper'],
       'includes': ['rumps', 'pynput', 'sounddevice', 'soundfile', 'httpx', 'keyring'],
   }

   setup(
       app=APP,
       data_files=DATA_FILES,
       options={'py2app': OPTIONS},
       setup_requires=['py2app'],
   )
   ```
2. **Key `Info.plist` entries:**
   - `LSUIElement: true` — hides the app from the Dock (agent app, menu bar only)
   - `NSMicrophoneUsageDescription` — required for microphone permission prompt
   - `NSAccessibilityUsageDescription` — shown when requesting accessibility access
3. **Build command:** `uv run python setup.py py2app`
4. **Code signing:**
   - Ad-hoc signing is automatic on Apple Silicon and sufficient for personal use
   - No Apple Developer account needed for personal use
   - For distribution: would need proper signing + notarization (out of scope for v1)
5. **Entitlements file** (`entitlements.plist`) for hardened runtime:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.security.device.audio-input</key>
       <true/>
       <key>com.apple.security.automation</key>
       <true/>
   </dict>
   </plist>
   ```
6. **Test the bundle:**
   - Launch from Finder
   - Verify macOS permission prompts appear (Microphone, Accessibility)
   - Verify hotkey works after granting permissions
   - Verify paste works into TextEdit, browser, etc.

**Deliverable:** `Mini Whisper.app` in `dist/` that can be dragged to /Applications.

---

### Phase 10: First-Run Experience

**Goal:** Smooth onboarding — user can set up entirely from the menu bar.

**Steps:**
1. **Config directory:** `~/.config/mini-whisper/`
   - `config.json` — hotkey combo, cleanup toggle (no secrets)
   - `prompt.txt` — editable cleanup prompt
   - API key → macOS Keychain (via `keyring`)
   - Created automatically on first launch
2. **`config.json` structure:**
   ```json
   {
     "hotkey": "cmd+shift+space",
     "cleanup_enabled": true
   }
   ```
3. **First-run flow:**
   - Detect missing/empty API key in `config.json`
   - Show `rumps.alert()`: "Welcome to Mini Whisper! Enter your OpenAI API key to get started."
   - Immediately open the "Set API Key..." dialog (`rumps.Window`)
   - After key is entered, show brief instructions about permissions
4. **Permission guidance:**
   - If hotkey listener fails (no Accessibility permission), show alert:
     "Please grant Accessibility access: System Settings → Privacy & Security → Accessibility → Enable Mini Whisper"
   - If microphone recording fails, show similar alert for Microphone permission
   - Include a "Open System Settings" button that runs `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
5. **Subsequent launches:**
   - If API key exists, start silently (no dialogs)
   - All settings remain editable from the menu bar at any time

**Deliverable:** New users go from launch → API key entry → first dictation without touching terminal or config files.

---

## macOS Permissions Summary

| Permission        | Why                              | Where to Grant                                    |
|-------------------|----------------------------------|---------------------------------------------------|
| Microphone        | Record audio for dictation       | System Settings → Privacy → Microphone            |
| Accessibility     | Global hotkey + paste simulation | System Settings → Privacy → Accessibility         |
| Input Monitoring  | Detect key press/release         | System Settings → Privacy → Input Monitoring      |

- All three prompts appear automatically on first use
- User must manually toggle the permission ON after the prompt
- Permissions are granted to `Mini Whisper.app` (not Python or Terminal)

---

## Threading Model

```
┌─────────────────────────────────────────────┐
│ Main Thread (rumps / PyObjC NSRunLoop)       │
│  - Menu bar UI updates                      │
│  - rumps callbacks                          │
│  - Must dispatch UI updates here via Timer  │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│ Thread: Hotkey Listener (pynput)            │
│  - Runs continuously                        │
│  - Posts events to queue                    │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│ Thread: Worker (per dictation)              │
│  - Spawned on hotkey release                │
│  - Records → Transcribes → Cleans → Pastes │
│  - Updates UI via main thread dispatch      │
└─────────────────────────────────────────────┘
```

**Thread safety rules:**
- UI updates (icon, menu text) must happen on main thread → use `rumps.Timer` with 0-interval or `objc.callAfter`
- pynput listener callbacks must be lightweight → post to `queue.Queue`, don't do work
- API calls happen on worker thread → never block main or listener threads

---

## API Cost Estimate (per dictation)

| Step           | API              | Cost (approx)           |
|----------------|------------------|-------------------------|
| Transcription  | Whisper API      | ~$0.006/min of audio    |
| LLM cleanup    | GPT-4o-mini      | ~$0.0001 per transcript |
| **Total**      |                  | **~$0.006 per dictation** |

At 50 dictations/day: ~$0.30/day, ~$9/month — significantly cheaper than Superwhisper ($8.49/mo) and with more flexibility.

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| pynput threading conflicts with rumps | App hangs/crashes | Use queue-based decoupling, test thoroughly |
| Accessibility permission not granted | Hotkey doesn't work | Clear first-run dialog, detect and re-prompt |
| py2app fails to bundle sounddevice | App crashes on launch | Test bundle early (Phase 9 can start after Phase 2) |
| Whisper API latency (1-3s) | Sluggish UX | Show processing indicator, consider async streaming |
| macOS 15.4+ clipboard privacy changes | Paste may require extra consent | Monitor Apple docs, use NSPasteboard API if needed |

---

## Out of Scope (v1)

- Local Whisper inference (whisper.cpp) — cloud API is simpler for v1
- Real-time streaming transcription — batch is fine for short dictations
- Custom vocabulary / personal dictionary
- Multiple language support (English only for v1)
- Windows/Linux support
- App Store distribution
- History/log of past transcriptions (maybe v2)

---

## Development Order Summary

| Phase | What                          | Depends On | Effort |
|-------|-------------------------------|------------|--------|
| 1     | Project scaffold + menu bar   | —          | Small  |
| 2     | Audio recording               | Phase 1    | Small  |
| 3     | Whisper API transcription     | Phase 1    | Small  |
| 4     | LLM text cleanup              | Phase 1    | Small  |
| 5     | Paste into active app         | Phase 1    | Small  |
| 6     | Global hotkey                 | Phase 1    | Medium |
| 7     | Controller (wire everything)  | 2,3,4,5,6  | Medium |
| 8     | UX polish                     | Phase 7    | Medium |
| 9     | App bundling (py2app)         | Phase 7    | Medium |
| 10    | Config & first-run            | Phase 9    | Small  |

Phases 2–6 are independent of each other and can be developed in any order or in parallel.

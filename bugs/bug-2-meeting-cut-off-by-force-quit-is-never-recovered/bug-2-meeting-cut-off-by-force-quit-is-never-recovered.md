# Bug 2: A meeting cut off by a force-quit or crash is never recovered

- **Severity:** medium — only after an abnormal exit. The transcript survives; the audio is unopenable, the meeting shows no end or duration, and its transcription cost is never recorded.
- **Filed:** 2026-11-24

## Description

Mini Whisper 0.9.0b3. Observed on 2026-11-24 after the hang in bug 1: the app was force-quit about ten minutes into a live remote meeting. The next launch repaired nothing.

State of the meeting folder afterwards:

- `audio.m4a` (5.3 MB) is unfinalised. `afinfo` reports `AudioFileOpenURL failed`.
- `meeting.json` has `endedAt` null and `durationSeconds` 0.
- `segments.jsonl` holds 144 segments, the last ending at 613.6 s.
- `billing` has `engineSeconds` 0 and `costUSD` 0. Only the naming cost, saved as it went, is present.
- No summary.

## Expected behaviour

On launch, a meeting left unfinished gets an end time, a duration and its billing, and is marked as interrupted. Its audio is playable: either repaired, or written in a form that survives an abrupt exit.

## Steps to reproduce

Not run. They follow from the code and from the one occurrence.

1. Start a meeting and let a few segments arrive.
2. Kill the app (`kill -9`, Force Quit, or a crash).
3. Relaunch and open the meeting.

## Screenshots

_None provided._

## Triage

**Summary of understanding:** Everything that closes a meeting happens in `MeetingController.stop()`. An exit that skips it leaves the audio without its header and the meeting without an end, duration or engine billing, and no code looks for such a meeting afterwards.

**Probable affected area:** Confident, from reading the code:

- `MeetingController.stop()` (`Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift:546`) is the only place that finalises the audio (:572), sets `endedAt` and `durationSeconds` (:577–578), writes engine billing (:581) and adds the day's usage (:588).
- `AACFileWriter` (`Packages/MiniWhisperCore/Sources/MWAudio/AACFileWriter.swift:16`) writes AAC through `AVAudioFile`. The header is written at `finish()` (:67), on close or release.
- A normal quit while recording goes through `applicationShouldTerminate` (`App/AppDelegate.swift:610`, `App/QuitPolicy.swift`), so only abnormal exits are affected.
- No launch-time code reads a meeting with `endedAt == nil`. The only similar check is for unfinished test calls (`MeetingController.swift:1146`).

**Initial hypothesis:** A missing feature, not a regression: there is no recovery pass and no crash-tolerant audio format. Segments are persisted as they arrive, which is why the transcript survives.

**Missing information that would help reproduce:**
- How the unfinished meeting appears in the app after relaunch. Not checked.
- Whether the audio is recoverable from the bytes on disk. Not attempted; the file was left untouched.

**Suggested next steps:**
- Add a launch pass over meetings with no `endedAt`: take the end and duration from the last segment, rebuild billing from the recorded time, and mark the meeting as interrupted.
- Make the audio survive an abrupt exit: a container readable without a final header, or a repair step in the same launch pass. Neither is verified.
- Record engine usage during the meeting, not only at stop, so the cost reaches the day's usage whatever happens.

Related: bug 1, the hang that led to the force-quit.

---
Filed via `/bug-submit` on 2026-11-24. To resolve, move this folder into `bugs/archive/`.

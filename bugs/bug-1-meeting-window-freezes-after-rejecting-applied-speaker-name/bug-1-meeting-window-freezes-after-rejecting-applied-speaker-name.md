# Bug 1: Meeting window freezes after "Not <name>" on an applied speaker name

- **Severity:** high — the app hangs mid-meeting and must be force-quit; the rest of the meeting is lost and its audio cannot be opened. Seen once.
- **Filed:** 2026-11-24

## Description

Reported: "the last session frozen (this happened when I selected "Not X" for a name suggestion."

Mini Whisper 0.9.0b3, live remote meeting on AssemblyAI, 2026-11-24.

- 09:30:47Z: meeting starts.
- 09:34:44Z: a voice match applies a person's name to a speaker (score 0.80). The speaker has one provider key and no linked person.
- 09:41:01Z: the user clicks "Not <name>" on that speaker. The match log records `rejected`, and `meeting.json` is saved with the name back to `Speaker N`.
- 09:40:55–09:42:32Z: macOS records 90 s of CPU over 97 s and a footprint rising from 185 MB to 408 MB.
- The window never responds again. The transcript stops at 10 m 13 s (144 segments). The app is force-quit.

The name was an applied one, not a suggestion: the "Not <name>" pill is shown only beside applied names.

After the force-quit:

- `audio.m4a` (5.3 MB) is unfinalised. `afinfo` reports `AudioFileOpenURL failed`.
- The meeting has no `endedAt` and a duration of 0.

## Expected behaviour

The name reverts to `Speaker N` and the meeting carries on recording and transcribing.

## Steps to reproduce

Not reproduced. 14 harness runs replayed the meeting into the live page and removed the applied name: scrolled to the bottom, with and without a partial in flight, pointer resting on the pill, a synthetic click, five window widths, and the finished page as a control. None hung.

The one occurrence:

1. Record a remote meeting with several speakers for about ten minutes.
2. Let a voice match apply a name to a speaker with one provider key and no linked person.
3. Click "Not <name>" beside that speaker.

## Screenshots

_None provided._

## Triage

**Summary of understanding:** Rejecting an applied name completes in the controller, then the main thread never leaves one SwiftUI layout pass of the transcript list. `MeetingController` is on the main actor, so recording and transcription stall with it. The root cause in code is not identified.

**Probable affected area:** `App/Meeting/TranscriptView.swift`, likely: the `LazyVStack` at :74, the paragraph header `HStack` at :167, `rejectAction` at :307, `besideName()` at :463, `.textSelection(.enabled)` at :137. The controller path ran to completion and is unlikely: `MeetingController.rejectMatch` (`MeetingController.swift:750`) → `SpeakerRegistry.detach` (`SpeakerRegistry.swift:178`, the branch that returns nil) → `applyMerge(nil)` (:1002) → `commitSpeakers` (:1009), which saves and emits `.speakers` (:1024).

**Initial hypothesis:** A layout cycle in the lazy stack, started when the pill leaves the header row. Evidence:

- The CPU report's 27 main-thread samples sit in `NSRunLoop.flushObservers` → `GraphHost.flushTransactions` → `LazySubviewPlacements.placeSubviews` / `LazyStack.place`. They also show `LazyLayoutCacheItem.AllItemsPhaseMutation`, `EventBindingManager.enqueueHoverUpdateIfNeeded`, and `SelectionOverlay.updateNSView` → `NSTextField invalidateIntrinsicContentSize`. No app frame appears.
- The pill is not height-neutral. Removing it moves the paragraph 0.5 pt and the transcript height 1 pt. `besideName()` pads a 24 pt control by −3 pt to fit an 18 pt line.
- `.speakers` changes neither the row count nor the partial, so no `scrollTo` follows.

Unverified: a reading of SwiftUI's disassembly that `flushObservers` loops while each pass queues another.

**Missing information that would help reproduce:**
- Whether it recurs with the window key in the active app. The harness window was never key.
- Whether a transcript list that has been live for ten minutes matters. The harness built its list fresh.
- The real name's rendered width, and the elapsed and cost tickers, neither of which the harness had.

**Suggested next steps:**
- Run the harness with its window key: `AppTests/TranscriptHangHarness.swift` in the worktree `.claude/worktrees/agent-ad318199245f2f411`, enabled by `TEST_RUNNER_MWHANG`.
- Candidate fixes, none verifiable without a reproduction: fix the header row's height at `TranscriptView.swift:167` so a name change cannot alter row height (recommended); enable text selection only when the transcript is editable; replace `LazyVStack` with `VStack`.
- Split out a second bug: a meeting left unfinished by a force-quit or crash is never recovered. Its audio stays unopenable and it has no end time. That holds whatever caused the hang.

Source of the samples: `/Library/Logs/DiagnosticReports/Mini Whisper_2026-11-24-094233_*.cpu_resource.diag`.

---
Filed via `/bug-submit` on 2026-11-24. To resolve, move this folder into `bugs/archive/`.

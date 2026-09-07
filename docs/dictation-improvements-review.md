# Dictation improvements review

Date: 2026-09-05
Status: Improvement 2 selected by the user for implementation planning on 2026-09-05.

## Current product

Mini Whisper is a native macOS menu-bar dictation app. A held or tapped hotkey
captures audio, a selected engine provides live transcription, optional cleanup
processes the result, and synthetic paste delivers it to the app selected at
release. A second binding also submits. Streaming failures can fall back to batch
transcription. The app already includes per-app cleanup profiles, manual
vocabulary, local searchable history, clipboard restoration, and on-device engines.

The review covers the controller, processing job, capture lifecycle, engine
selection and adapters, paste implementation, history, settings, prompts, and
relevant tests and design documents. Findings describe source behavior, not a
live usability test or measured frequency of failures. No application code was changed.

## 1. Recover work without repeating it

**User benefit:** A network failure, lost paste destination, or second recording
does not require remembering and speaking an entire thought again.

**Evidence:** `ProcessingJob.run` returns on cleanup and paste errors, and appends
history only after paste returns successfully. Its staleness checkpoints discard
pending results when a new press supersedes them. Existing tests explicitly cover
no history on paste failure and discarding stale jobs. History stores final text,
not raw transcripts or recoverable audio. `UIEventRouter` updates the menu's Last
item only on a successful result.

**Proposed first version:** Keep a recoverable draft before cleanup and delivery.
Offer Copy, Paste original, and Retry cleanup. Preserve superseded results in a
small pending list without automatically pasting them later. Use the current
destination when the user explicitly retrieves a draft. A failed transcription
needs captured audio to retry; default to a bounded, temporary in-memory buffer.
Persistent audio recovery would be a separate user choice. Respect history-off
and retention settings; distinguish temporary recovery from saved history.

**Acceptance:** After a simulated cleanup error, paste error, or overlapping next
dictation, the available transcript is retrievable without recording again.
Retries do not repeat successful transcription or duplicate delivery. Pending
dictations do not submit themselves into a changed destination.

**Scope:** Medium. Extend the processing state and recovery UI; retain the useful
staleness protection against unwanted late pastes.

## 2. Remember corrections and improve recognition before cleanup

**User benefit:** Repeated corrections to names, acronyms, and project terminology
become less frequent without maintaining a vocabulary file manually.

**Evidence:** `VocabularyModel` supports manual addition and removal only.
`PromptComposer` appends terms to batch instructions and cleanup prompts.
`EngineFactory` does not pass vocabulary into streaming engines, and the speech
bridges and cloud adapters do not configure vocabulary hints. Consequently, the
existing list does not guide the streaming recognizer itself.

**Proposed first version:** An explicit Correct last dictation action with a
Remember this correction choice. Store original and corrected forms, editable
and removable in Settings; allow project or app scope. Feed supported vocabulary
hints into the selected recognition engine. Prefer recognition hints and scoped
corrections to unconditional global string replacement. Automatic observation of
edits in other apps can follow if the user wants it and compatibility permits.

**Acceptance:** A remembered proper name reaches the actual configured recognizer
where supported, works without cloud cleanup on supported on-device paths, can be
removed, and does not unexpectedly replace ordinary words in other contexts.
Evaluate a small user-provided set of recurring mistakes before claiming accuracy
improvements; hints cannot guarantee correct recognition.

**Feasibility:** Apple's legacy recognizer exposes
[contextualStrings](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings).
Other engines need capability-specific verification. The existing native bridge
does not set that property.

**Scope:** Medium for explicit corrections and supported hints; larger for reliable
automatic learning from arbitrary applications.

## 3. Edit existing text by speaking

**User benefit:** Dictation handles the revision step that otherwise sends the user
back to the keyboard: shortening, restructuring, and targeted corrections.

**Evidence:** `BindingName` has only paste and paste-submit actions.
`ProcessingInput` carries a recording and app target, but no selected text or edit
intent. The default cleanup prompt forbids rephrasing and summarization, which is
appropriate for dictation but cannot implement a distinct editing workflow.

**Proposed first version:** Select text, invoke an edit binding, and speak an
instruction such as "make this shorter", "turn this into three bullets", or
"change Friday to Monday". Show the proposed replacement with Apply and Cancel.
Bind application to the original selection and detect intervening edits. Preserve
the original for undo. Ordinary dictation keeps its current meaning.

**Acceptance:** A revision affects only the selected text, preserves unrelated
content, and can be reversed. A changed selection/document prevents an automatic
replacement. Unsupported applications receive a copyable result.

**Feasibility:** macOS exposes
[selected text](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute)
and selection ranges through Accessibility. Reading and replacing reliably must
be verified in the user's actual applications; API existence is not universal
application compatibility.

**Scope:** Larger. The edit generation can reuse existing infrastructure, but safe
replacement and undo need a dedicated transaction and application testing.

## Alternatives to discuss if the first three do not fit

### 4. Format for the actual writing destination

Profiles currently resolve only by bundle ID, so different websites inside one
browser share a profile. Add a quick per-dictation format choice, then supported
site/field rules: a short chat message, a structured issue, or a literal technical
prompt. Selected surrounding text could provide names and punctuation context
when explicitly enabled. Avoid assuming the entire browser is one writing task.
First validate how often the user switches between these destinations.

### 5. Build one thought across several recordings

An explicit draft mode accumulates several short recordings while the user pauses,
reads, or changes windows; the microphone can stop between segments. Allow spoken
revisions, then insert the combined draft once. This differs from existing toggle
mode, which keeps one recording active until stopped, and from recovery, which
rescues work after failure. The current generation logic supersedes pending work;
draft mode would require separate ordered segment ownership.

## Additional reliability finding

`DictationController.startStream` attaches the audio listener after asynchronous
configuration and engine selection. The source explicitly says earlier captured
buffers are recorded but not streamed. `ProcessingJob` can accept a nonempty
stream result without comparing it with the complete recording. This creates a
plausible path to missing the start of speech. Reproduce with a delayed engine
setup and known leading audio before asserting a real-world defect. A replayable
buffer from hotkey press until listener attachment is a candidate fix.

## User agreement

- Asked what dictation is used for and what prompts keyboard editing afterward.
- Presented recovery, remembered corrections, and voice editing for feedback.
- The user selected improvement 2 (remembered corrections) for implementation
  planning and required TDD with an observed failure first and final verification.
- See [the implementation plan](remembered-corrections-plan.md). Other candidates
  remain unapproved; the current requested work is planning improvement 2.

The review is complete when at least three significant improvements have been
explicitly accepted by the user, with rejected candidates refined or replaced.

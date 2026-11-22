# Naming speakers from conversation — Brainstorm v9

**Status:** Draft
**Date:** 2026-11-21

## 1. Summary
v8 names meeting speakers by voice, but only people already known. A new person stays "Speaker N" until the user renames them, and afterwards it is hard to remember who said what. v9 suggests names from what is said in the meeting (introductions, hand-offs, a question to a name and its answer), using Claude Haiku 5.5. A request goes out after each turn that contains a name. Each request sends the transcript, limited to the last X minutes the user chooses in Settings or the whole meeting (the default). One more request covers the whole meeting at Stop, and stored meetings get the same request on demand. Suggestions appear in v8's existing suggestion display with the line they came from, so the user can confirm or fix them during the meeting. The v8 storm deferred this as "Naming speakers from what is said". An evaluation on the user's 17 stored meetings (2026-11-20/21) ruled out the on-device Apple model and keyword patterns, and measured this approach: in a replay, 20 of 35 renamed speakers were shown the right name at some point, with a median of 4.2 minutes into the meeting.

## 2. Goals
- During a meeting, an unnamed speaker gets a suggested name soon after someone states or uses it. The replay's median was 4.2 minutes, with 11 of 20 within 5 minutes.
- On the evaluation meetings, at least as many speakers are named correctly as in the stateless replay (20 of 35). Wrong-person suggestions stay at or below 1 in 35.
- A suggested name never disappears unless the user acts on it or a different name replaces it.
- Every suggestion shows a quoted line from the transcript that supports it.
- The user's own name, misheard, is suggested for another speaker at most once: after one "That's me", that spelling is not suggested again in any meeting.
- Naming from conversation costs about 5 cents a meeting at the default "Whole meeting". The cost appears on the meeting's existing cost line.

## 3. Scope (in / out)
- **In scope:**
  - **Live requests:** a request after each turn that contains a name.
  - **Settings › Meetings:**
    - A switch for naming from conversation, on by default, enabled only when an Anthropic key exists (as for the summary).
    - A slider for how much transcript each live request sends, from the last X minutes up to "Whole meeting". Whole meeting is the right end and the default.
    - A switch to apply verified self-introductions automatically, off by default. Off means every name from conversation is a suggestion.
  - **Suggestions:**
    - They reuse v8's display (Accept, Edit, Dismiss) and show the quoted line they came from.
    - They persist until the user acts. A later request may replace a suggestion with a different name, but a suggestion never vanishes on its own.
    - They only fill gaps. A speaker named by the user, or named or suggested by voice, is never given a suggestion from conversation.
  - **State passed forward:** each request carries:
    - the names already suggested, accepted and dismissed;
    - the user's name and its learned misspellings;
    - the names in Settings › People, so suggestions are spelt as saved.
  - **"That's me":** an action on a suggestion that records the name as a misheard spelling of the user's name, kept across meetings. That spelling is never suggested for another speaker again. It means "that name is mine", not "this speaker is me".
  - **Accepting a suggestion counts as naming the speaker yourself.** With Remember voices on, v8 learns that person's voice.
  - **Stop pass:** after Stop, one request over the whole meeting suggests names still missing.
  - **Stored meetings:** a "Suggest names" action runs that whole-meeting request on demand.
- **Out of scope / deferred:**
  - Naming only at Stop. Rejected: it gives the user no chance to fix names while they still remember who spoke.
  - Sending People names to the transcription engine as vocabulary hints (the user chose Claude only).
  - A "name whoever is speaking now" hotkey.
  - Reading attendee names from the calendar invite.
  - Claude suggesting that two speaker labels be merged as one person. Accepting the same name on both already merges them in v8.
  - A write tool on the MCP server or meetings CLI for naming speakers.
  - Test-call scenarios that score naming.
  - Auto-applying names from anything other than a verified self-introduction.

## 4. High-level technical direction
- **Model:** Claude Haiku 5.5 through the existing raw-HTTP Anthropic client. `MiniWhisperCore` stays dependency-free, and Sparkle remains the only third-party runtime dependency.
- **Key:** the Anthropic key is read only from the Keychain. The feature is unavailable without it, with the same hint the summary shows.
- **Privacy:** the transcript and People names go to Anthropic several times a meeting, not only at Stop. The Settings footnote must say so.
- **Prompt injection:** transcript text is data, never instructions, as the summary's prompt already requires. A suggestion is accepted only when its quoted evidence appears verbatim in the cited turn and contains the name. In the eval, 14% of quotes failed this check.
- **Meeting safety:** requests never block, slow or interrupt recording or transcription. A failed or slow request costs only a suggestion.
- **Speaker labels:** all four meeting engines (Speechmatics standard and enhanced, AssemblyAI streaming and Pro) label speakers live. That is the input this feature depends on.
- **Data model:** suggestions fit v8's `NameMatch` with a non-voice `source`. That source must survive storage, merging and the existing accept, dismiss and detach rules.
- **Cost:** naming requests bill to the meeting's cost line through the existing per-meeting billing.
- **Platform:** macOS 14 target. No on-device model is involved: the Apple model was measured unusable for this task, with 18% precision.
- **Settings slider:** follows the existing Cautious–Eager voice slider's behaviour, which tracks a drag and writes once the drag ends, and the design language in DESIGN.md.

## 5. Alternatives considered
- **Per-mention role votes** (option 1): Haiku labels each name mention as a self-introduction, an address to the next or previous speaker, or talked about, and Swift tallies votes. Rejected: it named only 11 of 35 renamed speakers, against 20 for whole-transcript requests, though it cost about $0.004 a meeting and never showed a wrong name.
- **One request at Stop only:** rejected even though it was the most accurate (16 of 35 named correctly, none wrong). It leaves no chance to fix names during the meeting, while the user still remembers who said what. Kept as an addition at Stop.
- **The on-device Apple model, or keyword patterns alone:** rejected. The Apple model reached 18% precision on real transcripts. Patterns were precise but found only 15% of names.
- **Stateless requests, as replayed:** rejected. 28 speakers had a name appear and then vanish on the next request. Suggestions now persist and carry state forward.

## 6. Risks
- **Cost grows with meeting length.** At Whole meeting the replay averaged 5 cents a meeting and reached 24 cents for a 98-minute meeting, with no prompt caching. Frequent long meetings make this a visible monthly cost.
- **Wrong names stay visible.** A wrong suggestion persists until dismissed, and an auto-applied wrong self-introduction persists until "Not <name>". If the user accepts it without noticing, v8 learns a voice under the wrong name.
- **Data exposure.** Transcripts and the People list leave the Mac more often than with the summary alone. A user who accepted the summary may not expect live sending.
- **A misheard name.** The user's own name, misheard, was the only wrong-person suggestion in every run. Until "That's me" has learned the user's variants, early meetings will show it.
- **A short window loses context.** It can drop evidence for names stated early. Passing state forward reduces this, but coverage at small windows is unmeasured.
- **Names absent from the transcript.** Names never spoken, or misheard beyond recognition, cannot be suggested. 12 of 35 names never appeared in the user's spelling, so People names only partly help.

## 7. Open questions for design
- The slider's stops and its smallest window. (The user wants "Whole meeting" at the right end, as the default.)
- Which turns trigger a live request, how requests are throttled or merged when names come quickly, and what happens to a request still in flight when the next turn arrives.
- The Stop pass's order relative to the summary, and whether the summary uses names accepted from it.
- How Dismiss and "not offered again" work for a suggestion with no linked person. v8's `reject` does nothing for a nil person.
- How a suggestion is matched to an existing person in People when accepted, so voice learning adds to that person rather than creating a duplicate.
- The wording and placement of "That's me", where the learned misspellings are kept, and how a wrongly added one is removed.
- How the quoted line appears on a suggestion in the narrow and wide transcript layouts.
- Cost levers: prompt caching across successive requests, effort level, and output limits. All are untested.
- How "Suggest names" on a stored meeting behaves when the meeting already has suggestions or applied names.
- What the user sees when requests fail (no network, invalid key, rate limit): silent, or a quiet note.

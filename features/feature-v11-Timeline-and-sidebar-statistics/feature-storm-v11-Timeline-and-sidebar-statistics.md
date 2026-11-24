# Timeline and sidebar statistics — Brainstorm v11

**Status:** Draft
**Date:** 2026-11-24

## 1. Summary

Mini Whisper gains two surfaces that show its user their own history: a Timeline page, an all-time scrolling infographic of meetings, dictation and spend, and a foldable stats block in the sidebar above the usage table. Both read from a new numbers-only record, because today only meeting figures reach back in time: dictation history lasts 7 days and cost resets at the month end. The basis is `docs/statistics-findings.md`, whose five open decisions are closed here. Every day before the record ships is lost for dictation and cost, which is the reason to build it now.

## 2. Goals

- A Timeline page, reached from a sidebar row and ⌘3, shows lifetime meeting figures on first open after the update, built from the meetings already stored.
- Dictation and cost figures accumulate from the day v11 ships and survive the pruning of dictation text and the month end.
- A lifetime total or milestone never falls when a meeting is deleted.
- The sidebar block shows the last 30 days and one lifetime line, folds to leave only the usage table, and remembers its fold state across launches.
- No text, title or name is written to the statistics files, and nothing is sent off the Mac.
- The user can erase the record with one control in Settings.

## 3. Scope (in / out)

- **In scope:**
  - **The record.** Per-day and per-meeting rows kept for life, per-dictation rows kept for 13 months, numbers only, backfilled once from stored meetings, the current month's usage and the dictation retention window.
  - **Counting rules.** A deleted meeting's numbers stay in lifetime totals. Recordings under a minute are neither counted as meetings nor shown. Test calls are left out. Clearing dictation history leaves the dictation numbers.
  - **Timeline page.** All-time, in themed panels: lifetime strip, year calendar with a year stepper, weekly rhythm, talk share, spend, people, dictation payoff, records and milestones. Then a word cloud of most-used words and topics, a dated strand of milestones, and a folded quality section at the foot.
  - **Page behaviour.** A panel appears only once it has data. A record opens its meeting while that meeting exists. Figures count up and charts draw in when the page opens, with Reduce Motion honoured.
  - **Quality section.** Test-call accuracy, transcript lost to dropouts and reconnects, plus the new timings below, each shown once it has data.
  - **Capture ahead.** Timing of the wait from key release to pasted text, live transcript delay and summary wait, and a count of dictation attempts that were not delivered.
  - **Sidebar block.** Above the usage table: the last 30 days and one lifetime line, with the trend as a small bar graph. Unfolded on first launch, then remembered. Folded, only the usage table remains. Hidden while Settings is open. Clicking it opens Timeline.
  - **Navigation.** A Timeline row between Dictations and Settings, with ⌘3.
  - **Settings.** A typing speed for time saved, 40 words a minute by default. A Reset statistics control; after a reset the record rebuilds from what is still stored.
- **Out of scope / deferred:**
  - Year in review panel, until a calendar year of rows exists.
  - A page-wide range switch (all time, this year, a past year).
  - Opening a day's meetings from the year calendar.
  - Copy as Image and any other sharing of the infographic.
  - Announcing a milestone or record on the meeting's own page.
  - A statistics command and MCP tool for the user's AI assistant.
  - Month-on-month deltas on the Timeline page.
  - Showing recordings under a minute as false starts.
  - The word cloud and quality figures in the sidebar.
  - App-use counts (launches, searches, versions used), goals or targets, and checking estimates against provider invoices.

## 4. High-level technical direction

- **No new dependency.** Sparkle stays the only third-party runtime dependency and `MiniWhisperCore` stays dependency-free. Charts come from Apple frameworks or are drawn by hand.
- **Platform.** macOS 14, arm64, Swift 6 with complete strict concurrency. Non-UI logic lives in the core package and is tested with Swift Testing; every duration is tested on a virtual clock.
- **Storage.** The record lives under `~/.config/mini-whisper/`, mode 0600, and never leaves the Mac. No analytics.
- **Numbers only.** No text, title or name enters the record. Anything that names a person or quotes words (people, word cloud) is computed from kept meetings and never copied, so deleting a meeting or forgetting a person removes it.
- **Costs.** Stored costs are summed, never recomputed from current prices. Every cost shown is labelled an estimate.
- **Local time.** Meeting times are stored as instants; weekday-by-hour figures need the local time the meeting happened in.
- **App state.** Fold state and typing speed belong in `config.json`, the one home for app state.
- **Design language.** Every colour, size and type style comes from `DS`. No shadows inside a window. The page is a centred scrolling column under a display-serif title. New components (charts, word cloud, stats block) are recorded in DESIGN.md.
- **Motion.** DESIGN.md limits motion to the dictation overlay, the pulse bars and the test-call level bars. The Timeline page's count-up and draw-in is a deliberate, recorded exception that honours Reduce Motion.
- **Sidebar.** 248 px wide with the usage table pinned to the foot. The block may grow upward but never crowds the nav rows.
- **Public repository.** No figure measured on a real Mac appears in docs, mockups or fixtures.

## 5. Alternatives considered

- **Build from stored files only, with no new capture** — rejected because dictation would cover 7 days, cost the current month, and deleting a meeting would lower every total.
- **Lifetime rows only, without per-dictation rows** — rejected because typical and longest dictation and the wait to pasted text need a row per dictation.
- **A chronological page, one band per month** — rejected in favour of themed panels closed by a milestone strand, which read as an infographic and keep the chronology.
- **Thin panels shown with a since-date note** — rejected; a panel stays hidden until it has data, so the page never shows an empty chart.

## 6. Risks

- **Thin launch.** Dictation, spend and timing panels stay hidden for days or weeks after the update, so the page opens as a meetings page. Users may read it as incomplete.
- **Attribution quality.** Talk share and People are only as good as speaker separation and naming, which are still in beta. A wrong attribution shows as a confident figure.
- **Breadth of capture.** The record needs write points in dictation, meetings, summaries and naming. A missed or doubled write, or a backfill that overlaps live rows, corrupts totals that can never be rebuilt once the source is pruned.
- **Word cloud.** It reads every kept transcript, so it may be slow to open, and it puts words from private meetings on screen. Stop words differ by language.
- **Estimated spend read as invoiced.** A lifetime cost figure carries more weight than a monthly one; the estimate label has to hold.
- **Motion.** An exception to the design language can look out of place beside the static pages around it.
- **Size.** A record, a page of eleven sections, a sidebar block and two settings is the largest feature since the unified window. It may need to ship in stages.
- **Reset is final.** After a reset, numbers of meetings already deleted cannot be rebuilt.

## 7. Open questions for design

- Row shapes, file layout and write points for the three kinds of row, and how appends survive a crash.
- How the backfill stays idempotent and avoids overlapping rows written live.
- Whether the findings doc's retention proposals stand: 13 months per dictation, 90 days for single-request waits.
- How the first-use date is established for existing users.
- How the day's cost is split by purpose from v11 on, and how the unsplit current month is seeded.
- When derived meeting figures (words, talk share, pace) are computed: once into the meeting row, or on open.
- How many figures the sidebar block shows, which lifetime line, and the form of the bar graph. (User: decide at the mockup; the block may grow upward unless it blocks the nav rows.)
- The block's fold control: how it is unfolded when only the usage table remains, and how a fold click is told from a click that opens Timeline.
- Panel order, chart type and the exact figures inside each panel, including which of the findings doc's other marked figures (questions asked, speaking pace, back-to-back meetings, cost per recorded hour) find a place.
- Whether charts use Swift Charts or are hand-drawn from `DS` tokens.
- The threshold at which each panel "has data".
- The word cloud's source (transcripts, summary headings or both), its stop words and languages, and whether a cache is allowed given that words are never stored in the record.
- How each new timing is measured, and what the quality section shows per engine.
- What animates, for how long, and whether it replays on every open.
- Where the typing speed and Reset statistics sit in Settings, the bounds of the speed, and the reset's confirmation.
- How a record whose meeting was deleted is shown, given no title is stored.
- Which people the People panel lists: named people only, or unnamed speakers too.
- Week start, and whether "last 30 days" includes today.

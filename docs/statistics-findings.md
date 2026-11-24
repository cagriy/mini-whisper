# Statistics findings

Date: 2026-11-24
Status: Findings and proposals. Nothing is implemented. Five decisions are open.

## Scope

Which figures Mini Whisper could show its user in infographics, whether the app
holds each one today, and how long each should be kept. Long-term figures such
as total meetings, hours recorded and annual cost are in scope.

The review covers every file the app writes under `~/.config/mini-whisper/` and
the code that writes them, at 0.9.0b3 (`adc3af2`). No application code, config
or data was changed. Values measured on the reviewing Mac are left out of this
file because the repository is public.

## Findings

1. **Meetings are ready. Dictation and cost are not.** A meeting keeps every
   number for as long as it exists. Dictation history lasts 7 days and daily
   usage lasts to the month end, so no dictation or cost figure can reach a
   year.
2. **Deleting a meeting lowers every total.** Counts are read from the meeting
   folders. A lifetime figure needs a record that deletion cannot touch.
3. **Most of the interesting figures need no new capture.** 19 of the 33 marked
   † below compute from files already stored: talk share, speaking pace,
   questions asked, weekly rhythm, records.
4. **Three things are never recorded.** Dictations that were not delivered, the
   wait from key release to pasted text, and the date of first use.
5. **Keep numbers for life and content only with its source.** One numbers-only
   row per day and per meeting gives annual and lifetime totals in under 1 MB a
   year. Names and words stay in the meeting.

## What the app loses today

- **Daily usage past the month.** `UsageStore.add` drops every day outside the
  current calendar month on each write.
- **Dictation numbers with the text.** `history.jsonl` is the only
  per-dictation record and is pruned at `history_retention_days`: 7 by default,
  30 at most, 0 for none.
- **A meeting's numbers with the meeting.** `MeetingStore.delete` removes the
  folder and its index row.
- **The split of a day's cost.** A `DayUsage` holds one cost and one token pair
  for dictation, meetings, summaries and naming together.

## Metrics

81 metrics: 19 ready, 30 derivable, 17 short-lived, 15 not captured.

Available:

- **Ready**: a stored field. Can be shown today.
- **Derivable**: computed from stored files. No new capture.
- **Short-lived**: stored, then pruned within days or at the month end.
- **Not captured**: dropped at runtime or never observed.

Keep is the recommended retention, defined in the next section. † marks an
interesting figure.

### Meetings

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Meetings recorded | Ready | Lifetime | `meetings/index.json · rows` | Test calls excluded. A deleted meeting drops out of the count. |
| Hours recorded | Ready | Lifetime | `meeting.json · durationSeconds` | Pauses excluded. |
| Meetings and hours per week, month and year | Derivable | Lifetime | `meeting.json · startedAt, durationSeconds` | Bars by month, or a year calendar shaded by hours. |
| Typical and longest meeting | Derivable | Lifetime | `meeting.json · durationSeconds` |  |
| Recordings under a minute † | Derivable | Lifetime | `meeting.json · durationSeconds` | False starts. They pull every average down unless set apart. |
| Weekly rhythm: weekday by hour † | Derivable | Lifetime | `meeting.json · startedAt` | A heatmap of when meetings start. |
| Busiest day † | Derivable | Lifetime | `meeting.json · startedAt, durationSeconds` | Most meetings and most hours in one day. |
| Back-to-back meetings † | Derivable | Lifetime | `meeting.json · startedAt, endedAt` | One starting within five minutes of the last ending. |
| Share of the working week in meetings † | Derivable | Lifetime | `meeting.json · durationSeconds` | Hours recorded against a 40-hour week. |
| Earliest start and latest finish † | Derivable | Lifetime | `meeting.json · startedAt, endedAt` |  |
| Meeting app | Ready | Lifetime | `meeting.json · app` | Share by app, such as Zoom or Teams. |
| Remote or in-room | Ready | Lifetime | `meeting.json · mode` |  |
| Transcription engine | Ready | Lifetime | `meeting.json · engine` |  |
| Stopped by silence | Ready | Lifetime | `meeting.json · silenceStopSeconds` | Meetings the app ended after a quiet spell. |
| Paused time | Ready | Lifetime | `meeting.json · markers[paused, sleep]` | Manual pauses and sleep. |
| Audio kept on disk | Ready | Current value | `index.json · audioBytes` |  |

### Conversation

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Words transcribed † | Derivable | Lifetime | `segments.jsonl · words[]` | Also as pages, at 250 words a page. |
| Speech against silence | Derivable | Lifetime | `segments.jsonl · start, end` | Seconds of speech within recorded time. |
| Your share of the talking † | Derivable | Lifetime | `segments.jsonl · speaker; speakers[].isUser` | Overall and per meeting. Depends on your voice being attributed to you. |
| Your words spoken | Derivable | Lifetime | `segments.jsonl · words[], speaker` |  |
| Speaking pace † | Derivable | Lifetime | `segments.jsonl · words[].s, e` | Words a minute. Yours for life; other speakers only while the meeting is kept. |
| Longest uninterrupted turn † | Derivable | Lifetime | `segments.jsonl · start, end` |  |
| Questions asked † | Derivable | Lifetime | `segments.jsonl · text` | Segments ending in a question mark. Relies on the engine's punctuation. |
| Speaker changes per minute † | Derivable | Lifetime | `segments.jsonl · speaker` | How fast the conversation moves. |
| Reading time against meeting time † | Derivable | Lifetime | `segments.jsonl · words[]` | Time to read the transcripts at 238 words a minute. |
| Most-used words and topics † | Derivable | With its source | `segments.jsonl · text; summary headings` | Needs the transcript text. |
| Speakers per meeting | Ready | Lifetime | `index.json · speakerCount` | Voices the engine separated. One person can be split in two. |

### People

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| People the app knows | Ready | Current value | `voices.json · people[]` |  |
| People you meet most † | Derivable | With its source | `meeting.json · speakers[].person` | Meetings and hours per person. Names never enter the long-term files. |
| Time heard per person | Derivable | With its source | `segments.jsonl; meetings/<id>/voices.json` |  |
| New people per month | Derivable | With its source | `voices.json · people[].createdAt` |  |
| Speakers named | Derivable | Lifetime | `meeting.json · speakers[].name` | Named speakers against Speaker N labels. |
| Names applied automatically | Ready | Lifetime | `meeting.json · speakers[].matches` | By voice or from the conversation. |
| Suggestions accepted and dismissed | Short-lived | Lifetime | `voice-matches.jsonl · event` | Voice verdicts sit in a log capped at 2 MB. Conversation verdicts reach a log line only. |

### Notes and summaries

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Summaries written | Ready | Lifetime | `meeting.json · summary` |  |
| Summaries regenerated | Not captured | Lifetime | `meeting.json · billing.replacedSummaryCostUSD` | Only the cost of replaced summaries is kept. |
| Notes taken | Derivable | Lifetime | `notes.jsonl · rows` |  |
| Transcript fixes | Derivable | Lifetime | `segments.jsonl · edited, pinned` | Edited text and reassigned speakers. |
| Titles you wrote | Ready | Lifetime | `meeting.json · titleByUser` | Against titles taken from the summary. |
| Meetings reopened, searched and copied † | Not captured | Lifetime |  | Whether transcripts get used after the call. |
| Meetings read by your AI assistant † | Not captured | Lifetime | `log · cli: <command>, mcp: tools/call <tool>` | CLI and MCP calls reach a log line, by command name. |

### Dictation

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Dictations delivered | Short-lived | Lifetime | `history.jsonl · rows` | History holds 7 days by default. Day totals carry no count. |
| Words dictated | Short-lived | Lifetime | `history.jsonl · text` | Keep the count, not the text. |
| Time spent speaking | Short-lived | Lifetime | `history.jsonl · streamed_seconds` | Day totals mix dictation with meeting audio. A batch-only dictation records 0 s. |
| Dictation pace † | Short-lived | Lifetime | `history.jsonl · text, streamed_seconds` | Words a minute while dictating. |
| Time saved against typing † | Short-lived | Lifetime | `history.jsonl · text, streamed_seconds` | Words ÷ typing speed, minus speaking time. |
| Apps dictated into | Short-lived | Lifetime | `history.jsonl · app_name, bundle_id` |  |
| When you dictate: weekday by hour † | Short-lived | Lifetime | `history.jsonl · ts` |  |
| Days used and streaks † | Short-lived | Lifetime | `config.json · usage keys` | Day totals reset each month, so a streak cannot cross a month end. |
| Typical and longest dictation | Short-lived | 13 months | `history.jsonl · text` |  |
| On-device against cloud | Short-lived | Lifetime | `history.jsonl · engine` |  |
| Attempts not delivered | Not captured | Lifetime |  | Too short, silent, cancelled or failed. Counts for life, detail for 13 months. |
| Wait from key release to pasted text † | Not captured | 13 months |  | The press time is held in memory. Nothing after it is timed. |
| How each dictation was made | Not captured | Lifetime |  | Cleanup on or off, paste or paste-and-submit, hold or toggle, profile. |
| Corrections applied for you † | Not captured | Lifetime | `log · corrections: N replacement(s)` | Counted per dictation in a log line, then dropped. |
| Corrections and vocabulary you taught | Ready | Current value | `config.json · corrections, vocabulary` |  |
| Phrases you corrected most | Ready | Current value | `config.json · correction_tally` | Up to 200 phrases. |

### Cost

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Spend today and this month | Ready | Current value | `config.json · usage[day].cost_usd` |  |
| Spend per month, per year and in total | Short-lived | Lifetime | `config.json · usage; meeting.json · billing` | Days outside the current month are dropped on every write. Meetings keep their own cost while they exist. |
| Spend by purpose | Derivable | Lifetime | `meeting.json · billing, summary.costUSD` | Split per meeting. A day total is one figure, so dictation is not separable there. |
| Spend by provider | Short-lived | Lifetime | `config.json · usage[day].streamed_seconds` | Audio seconds are split by engine. Tokens are one pair for every model. |
| Cost per recorded hour † | Derivable | Lifetime | `meeting.json · billing, durationSeconds` |  |
| Cost per dictation and per 1,000 words | Short-lived | Lifetime | `history.jsonl · cost_usd, text` |  |
| Costliest meeting and costliest day † | Derivable | Lifetime | `index.json · costUSD; config.json · usage` |  |
| On-device minutes that cost nothing † | Short-lived | Lifetime | `config.json · usage[day].streamed_seconds` | And what a cloud engine would have charged for them. |
| Tokens in and out | Short-lived | Lifetime | `config.json · usage[day].input_tokens, output_tokens` |  |
| Estimate against the invoice † | Not captured | Lifetime | Provider dashboards | Providers bill separately. Nothing reconciles the two. |

### Quality

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Transcript accuracy from test calls | Ready | With its source | `testcall.json; meeting.json · test.wer` | Word error rate and speaker separation, per engine. |
| Transcript lost to dropouts | Ready | Lifetime | `meeting.json · markers[gap]` | Gaps from reconnects and device changes. |
| Reconnects per meeting | Derivable | Lifetime | `segments.jsonl · session` |  |
| Live transcript delay † | Not captured | Lifetime |  | Measured in test calls only. Arrival times in real meetings stay in memory. |
| Summary and naming wait | Not captured | 90 days |  | Naming reply time reaches a log line. Summaries are not timed. |

### Records and milestones

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Using Mini Whisper since † | Not captured | Lifetime | `meeting.json · earliest startedAt` | No first-use date is stored. The oldest kept meeting is a floor. |
| Lifetime totals † | Short-lived | Lifetime | All of the above | Meetings, hours, words, dictations and spend. Only the meeting half survives today. |
| Personal records † | Derivable | Lifetime | `meeting.json; segments.jsonl` | Longest meeting, most speakers, busiest day, most words in a day. |
| Milestones † | Derivable | Lifetime | Lifetime counters | 100th meeting, 100 hours, a million words. Each needs a counter that deleting cannot lower. |
| Year in review † | Not captured | Lifetime |  | One page per calendar year, built from every lifetime row. |

### App use

| Metric | Available | Keep | Stored today | Note |
|---|---|---|---|---|
| Launches and days opened | Not captured | Lifetime | `log · Mini Whisper launched` | A launch reaches a log line. No quit is logged. |
| Searches run | Not captured | Lifetime |  |  |
| Versions used | Not captured | Lifetime | `UserDefaults · SULastCheckTime` | Sparkle keeps the last check time only. |
| Features switched on | Ready | Current value | `config.json` | Voice recognition, naming, cleanup, streaming. |

## Recommended retention

| Keep | Applies to | Why this long | Form |
|---|---|---|---|
| Lifetime | Counts, seconds, words and cost | Annual and lifetime totals, records and milestones all sum from them. | One numbers-only row per day and one per meeting |
| 13 months | Each dictation attempt: app, seconds, words, outcome, wait. No text. | A full year plus the month it is compared with. The day row carries the totals after that. | One row per attempt |
| With its source | Anything that names a person or quotes words: people met, time per person, top words | Deleting a meeting or forgetting a person must remove it. | Computed on demand, never copied |
| 90 days | Waits and failures of single requests | Enough to see a change. The daily median goes in the day row. | One row per request |
| Current value | Settings, lists, disk use | A state, not a history. | Already in `config.json` |

## Suggested shape

Three append-only files under `~/.config/mini-whisper/stats/`, mode 0600, never
sent off the Mac. Sizes are estimates.

| File | One row holds | Kept | Size |
|---|---|---|---|
| `days.jsonl` | Meetings, recorded seconds, words; dictations delivered and not, words, seconds; cost by purpose; seconds by engine; tokens; counts by app and by hour | Lifetime | About 0.5 KB a day, under 200 KB a year |
| `meetings.jsonl` | Start with UTC offset, duration, speech seconds, words, the user's words and seconds, speakers, questions, notes, cost split, app, mode, engine, gaps | Lifetime, past deletion of the meeting | About 0.4 KB a meeting |
| `dictations.jsonl` | Time, app, engine, seconds, words, outcome, wait to paste, cost | 13 months | About 0.15 KB each. 50 a day is 2.7 MB a year. |

- **Numbers only.** No text, title or name enters these files, the rule the
  logs already follow.
- **Sum stored costs.** Each cost is fixed at the price of its day. Recomputing
  from current prices would rewrite history.
- **Store the UTC offset.** Meeting times are stored as instants. A
  weekday-by-hour chart needs the local time the meeting happened in.
- **Leave test calls out.** They carry a `test` tag.
- **Backfill once.** Existing meetings seed `meetings.jsonl` and the meeting
  half of `days.jsonl`. Usage seeds the current month's cost. Dictation seeds
  the retention window. Anything older is gone.

## Infographics these feed

| Infographic | Shows | Built from | Today |
|---|---|---|---|
| Lifetime strip | Meetings, hours, words, dictations and spend since first use | Day rows | Short-lived: meeting half only |
| Year calendar | One cell a day, shaded by hours recorded and dictations made | Day rows | Derivable: meetings only |
| Weekly rhythm | Weekday by hour, for meetings and for dictation | Meeting rows, day rows | Derivable: meetings only |
| Talk share | The user against everyone else, overall and per meeting | Meeting rows | Derivable |
| Spend | Monthly bars split by purpose, with a year total | Day rows | Short-lived: this month only |
| People | Who the user met most, by meetings and by hours | Meetings and the People list | Derivable while meetings are kept |
| Dictation payoff | Words dictated, time saved against typing, top apps | Day rows, dictation rows | Short-lived: 7 days |
| Records and milestones | Longest meeting, busiest day, longest streak, round numbers reached | Meeting rows, day rows | Derivable: meetings only |
| Year in review | A calendar year's totals, records and people on one page | All three files | Not captured: needs a year of rows |

## Open decisions

Each is a yes or no, with the recommended answer.

1. Keep a deleted meeting's numbers in lifetime totals? **Yes**, numbers only.
   The hours were recorded and paid for.
2. Count recordings under a minute as meetings? **No.** Show them apart as
   false starts.
3. Keep dictation numbers after the text is pruned? **Yes**: 13 months per
   dictation, for life per day.
4. Assume 40 words a minute of typing for time saved? **Yes**, as a default the
   user can change.
5. Offer a Reset statistics control? **Yes.** The files are the user's and hold
   their working pattern.

## Engineering figures

Outside the user-facing lens, from the same review:

- **Speed is not measured.** The only stored timing is transcript latency in a
  test call. `RecordingSession.pressedAt` is held, and nothing after it is
  timed.
- **The detailed figures go to info log lines, which macOS does not persist.**
  Naming latency and tokens, voice model load time, reconnects and batch
  fallbacks are logged at info level. Warning and error lines are kept. A
  `--debug` launch writes every line to `/tmp/mini-whisper.log`.
- **Failures leave no stored trace.** `history.jsonl` records delivered
  dictations only.
- **Nothing leaves the Mac.** There is no analytics, MetricKit, signpost or
  Sparkle profiling. The install base is visible only through GitHub download
  counts.

## Method and limits

- Availability is read from the Swift sources and the files the app writes.
- Every cost is the app's list-price estimate (`Pricing.swift`,
  `pricing_overrides`). An infographic should label it as estimated.
- Talk share and speaker counts are as good as the speaker separation behind
  them.
- Sizes and retention periods are proposals.

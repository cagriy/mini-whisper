# Unified Window and Design Language — Design v6

**Status:** Draft
**Date:** 2026-11-13
**Storm:** [feature-storm-v6-Unified-window-and-design-language.md](./feature-storm-v6-Unified-window-and-design-language.md)

## 1. Summary

Mini Whisper's UI is six fixed-size windows in stock styling, and its meeting summaries are four fixed sections in two small columns. v6 replaces the Meetings, History, Settings and Meeting windows with one resizable main window: a sidebar (search, Start Meeting, Meetings, Dictations, Settings, usage) and pages for the meeting list, the dictation list, search results, settings, and a meeting from chooser through recording to its summary. It gives every window except the dictation overlay one design language, recorded in `DESIGN.md`, in light and dark with a Theme setting. Summaries become topic-based documents shown in a reading column, and gain Regenerate and Copy. It is for the person who uses Mini Whisper daily for dictation and meetings.

## 2. Goals and non-goals

- **Goals:**
  - One main window reaches meetings, dictations, search and settings; the Meetings, History, Settings and Meeting windows are gone.
  - A meeting is chosen, recorded and read on a page of that window, and a recording can be returned to from any page.
  - Main, Correction, Onboarding and About follow the language in `DESIGN.md`, in light and dark, selectable with a Theme setting.
  - New summaries have topic sections, nested bullets and a closing Next Steps, shown as one reading column; old four-section summaries still display.
  - A finished meeting's summary can be regenerated and copied.
  - One search covers meetings and dictations.
  - Usage for today and the month, by tokens, audio time and cost, is visible in the window.
- **Non-goals:**
  - Restyling the dictation overlay; it keeps the v3 visual system and ignores the Theme setting.
  - Editing summary text in place; an Ask-anything chat; calendar integration; folders; sharing, accounts, People or Companies pages.
  - A second window for a meeting, or side-by-side reading.
  - Changing the app's shape: it stays an `LSUIElement` menu-bar app whose Dock icon shows only while a window is open.
  - A collapsible sidebar, or a resizable Correction, Onboarding or About window.
  - Any release from `main` while v6 is in progress.
  - Work in another repository: none is needed. The Homebrew tap, the appcast and the `python-legacy` branch are untouched.

## 3. Requirements

**Main window**

- R1. One main window exists, resizable, 1080×720 by default and never smaller than 900×600. The Meetings, History, Settings and Meeting windows and their controllers no longer exist.
- R2. The sidebar shows, top to bottom: a search field, Start Meeting, Meetings, Dictations, Settings, and a usage table. Settings' nine sections appear beneath Settings only while a Settings page is shown.
- R3. While a meeting is starting, recording, paused or stopping, Start Meeting is replaced in place by a recording pill showing the meeting's title and elapsed time (or `Paused`); clicking it shows the live meeting page.
- R4. Menu rows open the window at a destination: `Meetings…` → Meetings, `Dictations…` (renamed from `History...`) → Dictations, `Settings...` → Settings, `Start Meeting…` → the chooser page, `Show Meeting…` → the live meeting page. `Stop Meeting` stops without opening or moving the window.
- R5. Keyboard: ⌘1 Meetings, ⌘2 Dictations, ⌘, Settings, ⌘F focuses search, ⌘N Start Meeting, ⌘[ back from a meeting page, ⌘W hides the window. Esc in the search field clears it.
- R6. Closing the window hides it; a recording continues. The window's frame is stored in `config.json` and restored when the window is first shown after launch, if it still lies on a connected display.
- R7. The Dock icon is shown while any titled app window is visible and hidden when none is.
- R8. Settings → General has Theme: System, Light, Dark, stored in `config.json`. It applies to the main, Correction, Onboarding and About windows and to their dialogs, alerts and panels. The dictation overlay looks the same under every value.

**Meeting pages**

- R9. Start Meeting (⌘N) and `Start Meeting…` show the chooser as a page; its Test Call setup is a second step of that page. Cancel returns to the page the chooser was opened from. ⌘N while a meeting is active shows the live meeting page. The meeting hotkey behaves as today: it shows the chooser when no meeting is active and stops a recording or paused one.
- R10. The live meeting page shows title, mode, capture state, elapsed time, running cost, Pause/Resume and Stop, the transcript, and the Notes pane with its composer; a test call shows the Script pane in place of Notes. Navigating to another page or closing the window does not affect the recording.
- R11. At Stop the live page becomes that meeting's finished page. A finished page offers Summary, Transcript and Notes; it opens on Summary, or on Transcript for a test call, where the Score pane sits beside the transcript.
- R12. One meeting is on screen at a time. A meeting cannot be deleted while it is recording, while it is shown on the meeting page, or while its summary is being written.
- R13. Behaviours that carry over unchanged: transcript editing and speaker reassignment after Stop, speaker rename with merge confirmation, title rename in place, notes with Enter / Shift+Enter, export of transcript, summary or both, the silence hint, the reconnecting chip, pause on sleep, the quit confirmation, dictation lock-out during a meeting.

**Summary**

- R14. The bundled default summary prompt is the text in §5.3. An existing `summary_prompt.txt` whose content equals the previously shipped default is replaced by it at launch; any other content is left untouched.
- R15. A summary is displayed from its Markdown as headings (three levels), paragraphs, nested unordered and ordered list items, rules and code blocks, with bold, italic, strikethrough and inline code. Links and images are shown as plain text. Anything else is shown as paragraph text. Four-section summaries render through the same path.
- R16. Regenerate is offered on a finished meeting that has a summary. It asks for confirmation naming the current summary's cost. The current summary stays on screen while the new one is written and stays if the request fails, is declined or has no key, with the reason shown. A new summary replaces the stored one, is recorded in usage, and the replaced summary's cost stays in the meeting's total.
- R17. Copy summary puts the meeting title and the summary on the pasteboard as Markdown plain text, HTML and RTF.
- R18. A Meetings row shows, under the title: the summary's topic headings joined by ` · `; or the first sentence when the summary is a four-section one or has no headings; or the first transcript line in italics when there is no summary.

**Search, dictations, usage, settings**

- R19. Typing in the search field shows one results page with matching meetings (with up to two labelled snippets each) and matching dictations. A meeting result opens the meeting; a dictation result opens Dictations at that row. Clearing the field returns to the page shown before the search. The Meetings and Dictations pages have no search fields of their own.
- R20. The Dictations page lists stored dictations by day with Paste into *app*, Correct…, Copy and Delete per row, the retention line and Clear…. Paste targets the app that was frontmost most recently before Mini Whisper, and hides the main window before pasting.
- R21. The sidebar's usage table has rows Today and Month and columns tokens in/out, audio time and cost, covering dictations, meetings and summaries. The menu's `Month:` row shows the same three figures as its `Today:` row. Audio time of an hour or more reads `2h 14m`.
- R22. Settings keeps its nine sections with their controls, order, bindings and texts. The History section is titled Dictations. Its `Open History…` button and the Meetings section's `Open Meetings…` button are removed. Esc while a hotkey field is capturing restores the previous combo; leaving the Hotkeys section, leaving Settings or hiding the window does the same.

**Design language and small windows**

- R23. Every colour, type style, radius and component used by the main, Correction, Onboarding and About windows is a token or component recorded in `DESIGN.md`, with a light and a dark value for each colour.
- R24. Correction keeps its fields, order and behaviour at 560 points wide and as tall as its content. Onboarding keeps its behaviour at 460×330 and cannot be closed before both permissions are granted. About is a 300×300 window instead of an alert, with the same text.

**Non-functional**

- R25. macOS 14 deployment target, arm64, Swift 6 strict concurrency. No dependency is added; `MiniWhisperCore` imports nothing new.
- R26. Parsing, excerpting, search, navigation, usage formatting, frame restoration and session lifetime are in core modules or host-testable models, each with tests. Every duration is tested on a virtual clock: `VirtualClock` in core suites, and in `AppTests`, which cannot link `MWTestSupport`, a manual `MWSupport.Clock` fake as the existing app suites use.
- R27. No summary, transcript, dictation or search text is written to a log.
- R28. No release is cut from `main` until v6 is complete.

## 4. Background and context

**The six windows.** `AppDelegate` owns one controller per window (`App/AppDelegate.swift:33-46`) and opens each from a menu callback (`App/AppDelegate.swift:58-68`, `App/StatusItemController.swift:94-109`):

| Window | Controller | Size | Notes |
|---|---|---|---|
| Meeting | `App/Meeting/MeetingWindowController.swift:13-18` | 920×620 | chooser, live and stopped states of `MeetingView` (`App/Meeting/MeetingView.swift:8-22`) |
| Meetings | `App/Meetings/MeetingsWindowController.swift:13-18` | 680×480 | `MeetingsListView` |
| History | `App/History/HistoryWindowController.swift:17-22` | 680×480 | captures the paste target at `show()` (`:36-38`) |
| Settings | `App/Settings/SettingsWindowController.swift:13-18` | 780×560 | Esc cancels hotkey capture via `SettingsWindow.cancelOperation` (`:27`, `:48-54`) |
| Correction | `App/Correction/CorrectionWindowController.swift:15-20` | 560×520 | stays |
| Onboarding | `App/Onboarding/OnboardingWindowController.swift` | 460×275 | AppKit-built view; stays |

About is an `NSAlert` (`App/AboutPanel.swift:6-22`). Every controller sets the activation policy to `.regular` on show and `.accessory` on close without regard to other open windows. No window is resizable; every root view has a fixed `.frame`.

**Meetings.** `MeetingCoordinator` runs one `MeetingController` per window through `MeetingWindowPresenting` (`App/Meeting/MeetingCoordinator.swift:35-40`), keeping the chooser-or-live session in `current` and stopped ones with open windows in `ended` (`:112-114`). The list asks `isOpen` to block deletion (`:208-210`, `App/Meetings/MeetingsListModel.swift:153-155`). The stopped window shows the summary above the transcript in a two-column grid of `## ` sections (`App/Meeting/MeetingView.swift:250-320`, `App/Meeting/MeetingWindowModel.swift:213-232`), with links stripped (`MeetingView.swift:303-319`).

**Summary.** The prompt file is copied from the bundle on first read and re-read on demand (`Packages/MiniWhisperCore/Sources/MWConfig/PromptFiles.swift:34-36`, `:54-62`). One default has ever shipped (`App/Resources/default_summary_prompt.txt:1`, added in `e64ed39`). `MeetingController.summarise()` does nothing once a summary exists (`Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingController.swift:608-609`). `SummaryState` has four cases (`Packages/MiniWhisperCore/Sources/MWMeetingPipeline/MeetingEvent.swift:20-27`). A meeting's total cost is `billing.costUSD + summary.costUSD` in two places (`Packages/MiniWhisperCore/Sources/MWMeetings/MeetingStore.swift:233`, `App/Meeting/MeetingWindowModel.swift:360-363`). The index excerpt is the first sentence of the first non-heading line (`MeetingStore.swift:236`, `:256-263`), which for a topic-based summary would be a bullet.

**Search.** Meetings search is a debounced `MeetingSearch` over every stored meeting, loaded per query (`App/Meetings/MeetingsListModel.swift:254-296`, `Packages/MiniWhisperCore/Sources/MWMeetings/MeetingSearch.swift:41-66`). Dictation search is a substring filter in `HistoryStore.search` (`Packages/MiniWhisperCore/Sources/MWHistory/HistoryStore.swift:60-64`).

**Usage.** Dictations, meetings and summaries all write into one per-day entry (`Packages/MiniWhisperCore/Sources/MWPipeline/ProcessingJob.swift:245`, `MeetingController.swift:449`, `:626`). `UsageStore` keeps every day of the current month and returns today's entry and the month's cost (`Packages/MiniWhisperCore/Sources/MWUsage/UsageStore.swift:24-50`). The menu rows are formatted by `Pricing.formatUsageRows` (`Packages/MiniWhisperCore/Sources/MWUsage/Pricing.swift:104-112`) and reach the menu as strings (`Packages/MiniWhisperCore/Sources/MWPipeline/UIEvent.swift:14`, `App/UIEventRouter.swift:77-78`).

**Appearance.** Nothing in `App/` sets an appearance. The overlay draws with fixed colours only (`App/Overlay/CardChrome.swift:80`, `App/Overlay/StyleLayer.swift:195-197`).

**Prior designs.** The meeting windows come from `features/feature-v4-Meeting-transcripts/feature-design-v4-Meeting-transcripts.md`, the test call from `features/feature-v5-Meeting-test-call/feature-design-v5-Meeting-test-call.md`, History and Settings from v1, Correction from v2. Their accepted mockups are superseded in appearance by this design and remain the record of each surface's behaviour.

**References.** The user's three screenshots are in [`./references/`](./references/). They are a model for structure and feel; nothing of their branding, icons, names or copy is used.

## 5. Design

### 5.1 Architecture / components

Dependencies still flow downwards; nothing depends on `MWPipeline` or `MWMeetingPipeline`.

**Core (`Packages/MiniWhisperCore`)**

| Component | Module | Responsibility | Depends on |
|---|---|---|---|
| `SummaryDocument` | `MWMeetings` (new file) | Parses summary Markdown into blocks; yields topics, the index excerpt, inline attributed text, and the HTML and Markdown for Copy | Foundation |
| `SearchExcerpt` | `MWMeetings` (extracted from `MeetingSearch`) | The excerpt-around-a-match rule, public so dictation results use it too | Foundation |
| `Meeting.totalCostUSD`, `Billing.replacedSummaryCostUSD` | `MWMeetings` | The one definition of a meeting's total cost | — |
| `SummaryState.rewriting`, `.kept`; `MeetingController.regenerateSummary()` | `MWMeetingPipeline` | Regenerate | `Summariser` |
| `PromptFiles.migrateSummaryPrompt()` | `MWConfig` | Replaces an unmodified legacy prompt file | — |
| `AppTheme`, `WindowFrame`, `Config.theme`, `Config.mainWindowFrame` | `MWConfig` | Two new config values | — |
| `UsageTotals`, `UsageTable`, `Pricing.usageTable`, `Pricing.formatUsageRows(_:)` | `MWUsage` | Month totals and the two renderings of usage | `MWConfig` |

No new target is added, so `Package.swift` is unchanged.

**App (`App/`)**

| Component | File | Responsibility | Depends on |
|---|---|---|---|
| `DS` tokens | `App/Design/DS.swift` | Colours (`Color(light:dark:)` over `NSColor(name:dynamicProvider:)`), fonts, radii, spacing — the values in `DESIGN.md` | AppKit, SwiftUI |
| Components | `App/Design/*.swift` | `PillButtonStyle` (primary, secondary, quiet; regular, small), `DSFieldStyle`, `DSToggleStyle`, `SegmentedPill`, `Chip`, `Tile`, `Card`, `SettingRow`, `StatusLine`, `PageColumn`, `DSDialog`, `CloudPulseMark` | `DS` |
| `MainNavigationModel` | `App/Main/MainNavigationModel.swift` | Destination, origin, search-return rule, shortcuts' targets | — |
| `MainWindowModel` | `App/Main/MainWindowModel.swift` | Owns navigation, the page models, the usage table and the live-meeting reference | page models |
| `MainWindowController`, `MainWindow` | `App/Main/MainWindowController.swift` | The `NSWindow`: style, minimum size, show/hide, frame save/restore, Esc routing | `MainWindowModel`, `WindowFramePolicy`, `WindowActivation` |
| `WindowFramePolicy` | `App/Main/WindowFramePolicy.swift` | Pure function: saved frame + screens → frame to use | — |
| `WindowActivation` | `App/WindowActivation.swift` | Activation policy from the count of visible titled windows | AppKit |
| `ThemeApplier` | `App/ThemeApplier.swift` | `AppTheme` → `NSApp.appearance` | AppKit |
| `FrontAppTracker` | `App/FrontAppTracker.swift` | The last frontmost app that is not Mini Whisper | `NSWorkspace` |
| `SearchModel` | `App/Search/SearchModel.swift` | Debounced search over meetings and dictations, with a per-search cache | `MeetingReading`, `HistoryStore`, `Clock` |
| `MainView`, `SidebarView`, `RecordingPill`, `UsageTableView` | `App/Main/` | The shell | models, components |
| `MeetingsPage`, `DictationsPage`, `SearchPage`, `SettingsPage`, `MeetingPage` (`ChooserPage`, `LivePage`, `FinishedPage`) | beside their models | Projections of the existing models | models, components |
| `SummaryView`, `SummaryRichText`, `RichPasteboardWriting` | `App/Meeting/` | Renders blocks; builds RTF; writes three pasteboard types | `SummaryDocument` |
| `AboutWindowController`, `AboutView`; `OnboardingView` | `App/`, `App/Onboarding/` | Small windows | components |

**Modified:** `MeetingCoordinator` (pages instead of windows, §5.5), `MeetingWindowModel` (tab, chips, summary notice, copy state), `MeetingsListModel` (search removed, row fields), `HistoryListModel` (query removed, tracker, reveal), `SettingsModel` (Theme, two dependencies removed, section title), `MenuModel` / `StatusItemController` (row rename, usage), `UIEventRouter`, `AppDelegate` (composition), every view under `App/Settings`, `App/Correction`, `App/TestCall` (restyled with components).

**Removed:** `MeetingWindowController`, `MeetingsWindowController`, `HistoryWindowController`, `SettingsWindowController` (its `EditMenu` moves to `App/EditMenu.swift`), `AboutPanel`, `MeetingWindowPresenting`, `SummaryPanelView`'s grid, `MeetingWindowModel.sections(of:)` and `SummarySection`, `MeetingStore.firstSentence`.

Splitting stops at the page level: each page stays one model plus one view, as today. A separate module for the design system would add a target with no logic to test in isolation; the tokens and components are plain SwiftUI and stay in the app target.

### 5.2 Data model

**`config.json`** — two keys, both added to `Config.Key.all` (`Packages/MiniWhisperCore/Sources/MWConfig/Config.swift:176-207`):

| Key | Type | Default | Rules |
|---|---|---|---|
| `theme` | `"system"` \| `"light"` \| `"dark"` | `"system"`, written back | An unrecognised value is kept verbatim for round-tripping and treated as `system`, as `overlay_style` is |
| `main_window_frame` | `{"x": n, "y": n, "width": n, "height": n}`, screen points | absent | Absent or with a non-finite number means "no saved frame" |

**`meeting.json`** — `Billing` gains `replacedSummaryCostUSD: Double`, the summed cost of summaries a Regenerate replaced. `Billing.init(from:)` is written out so the key decodes as `0` when absent; the other three keys decode as before. It is always encoded. `Meeting.currentSchema` stays `1`: older builds ignore the key.

`Meeting.totalCostUSD = billing.costUSD + billing.replacedSummaryCostUSD + (summary?.costUSD ?? 0)` replaces the sum at `MeetingStore.swift:233`.

**`index.json`** — no schema change. `IndexEntry.excerpt` is now `SummaryDocument.excerpt(ofSummary:)` when the meeting has a summary, and the first segment's text otherwise (unchanged). Existing entries keep the excerpt they have until their meeting is next updated; for four-section summaries the old and new rules give the same text.

**`summary_prompt.txt`** — see §5.3.

**In memory only:** navigation state, the Settings section, the selected tab of a meeting page, the search cache.

### 5.3 Summary prompt and its migration

`App/Resources/default_summary_prompt.txt` becomes:

```
You write up a meeting for the person who attended it, as notes organised by topic.

Give each topic the meeting covered its own section, in the order the topics came up. A section starts with a `## ` heading that names the topic in two to five words. Under it, write short bullets with what was said: facts, figures, decisions and their reasons. Put detail and examples in a second level of bullets, indented two spaces. Three to seven topics suit most meetings; a short one may have one or two.

End with a `## Next Steps` section: one bullet per action, starting with the owner's name in bold when the transcript names one, and the deadline when one was given. When no action was agreed, write one bullet that says so.

Use only `## ` headings, `- ` bullets and `**bold**`. No title, no introduction and no closing remark. Use the speaker names exactly as given. Do not invent names, decisions, owners or dates; when something was discussed but not settled, say so in its topic. The attendee's own notes are provided separately and may be used as hints about what mattered, never as transcript. Answer in the language of the transcript.
```

`Summariser` is unchanged: it appends its data rule to whatever the file holds (`Packages/MiniWhisperCore/Sources/MWMeetingPipeline/Summariser.swift:20-24`, `:47-48`).

`PromptFiles.legacySummaryDefaults: [String]` holds the one text shipped before v6, exactly as `App/Resources/default_summary_prompt.txt:1` reads at `e64ed39`. `PromptFiles.migrateSummaryPrompt() throws -> Bool`:

1. `summary_prompt.txt` does not exist → return `false`. The next read copies the new default, as today.
2. Its content, trimmed of whitespace and newlines, equals a trimmed entry of `legacySummaryDefaults` → write the bundled default over it, return `true`.
3. Otherwise → return `false`; the file is not opened for writing.

`AppDelegate.startNormal()` calls it once, straight after constructing `PromptFiles` and before any controller is built. A thrown error is logged as a warning and startup continues. *Restore Default* in Settings writes the new default through the existing `restoreDefaultSummaryPrompt()` (`PromptFiles.swift:50-52`).

### 5.4 `SummaryDocument`

```swift
public struct SummaryDocument: Sendable, Equatable {
    public enum Block: Sendable, Equatable {
        case heading(level: Int, text: String)                 // level 1...3
        case paragraph(String)
        case item(depth: Int, ordinal: Int?, text: String)     // depth 0...3; ordinal set for ordered items
        case rule
        case code(String)
    }
    public let blocks: [Block]
    public init(markdown: String)

    public var topics: [String]
    public var isFourSection: Bool
    public static func excerpt(ofSummary markdown: String) -> String
    public static func inline(_ text: String) -> AttributedString
    public func html(title: String) -> String
    public static func markdown(title: String, summary: String) -> String
}
```

**Parsing** is line-based. Line endings are normalised to `\n`; trailing whitespace is dropped. For each line, the first matching rule wins:

1. Inside a fenced block: a line whose trimmed text starts with ```` ``` ```` closes it; any other line is appended verbatim. An unclosed fence runs to the end.
2. Trimmed text starts with ```` ``` ```` → opens a fenced block (`.code`).
3. `^ {0,3}(#{1,6})\s+(.*?)\s*#*$` → `.heading(level: min(count, 3), text)`.
4. `^ {0,3}([-*_])(\s*\1){2,}\s*$` → `.rule`.
5. `^(\s*)[-*+]\s+(.*)$` → unordered `.item`; `^(\s*)(\d{1,9})[.)]\s+(.*)$` → ordered `.item` with that ordinal.
6. Blank → ends the open paragraph.
7. Any other line → text. If the previous block is an `.item`, no blank line intervened and the line starts with whitespace, it is appended to that item's text after a `\n`. Otherwise it joins the open paragraph with a space, or opens one. A leading `> ` is removed first.

Item depth uses an indent stack, where a tab counts as four columns: pop while the top is greater than the item's indent; push the indent if it differs from the top; `depth = min(stack.count - 1, 3)`. A heading, paragraph, rule or code block clears the stack; a blank line does not.

Tables and HTML fall under rule 7 and are shown as paragraph text.

**Inline.** `inline(_:)` parses with `AttributedString(markdown:options:)` using `.inlineOnlyPreservingWhitespace`, then removes the `link` and `imageURL` attributes from every run. If parsing throws, the text is returned as written. This is today's rule (`App/Meeting/MeetingView.swift:303-319`) moved into core.

**Derived values.**

- `topics`: the plain text of every top-level heading — one whose level is the smallest level number present in the document — except one equal to `Next Steps` ignoring case.
- `isFourSection`: there is at least one top-level heading, every top-level heading is one of `Summary`, `Decisions`, `Action items`, `Open questions` ignoring case, and `Summary` is among them.
- `excerpt(ofSummary:)`: if `isFourSection` or `topics` is empty → the first sentence (up to the first `.`, `!` or `?` followed by whitespace, else the whole text) of the first paragraph or item, as plain text. Otherwise → `topics` joined by ` · `.
- `html(title:)`: `<h1>` for the title; `<h2>` for top-level headings and `<h3>`, `<h4>` for the next two levels present; `<p>`; nested `<ul>` / `<ol>` by depth, with a `\n` inside an item as `<br>`; `<hr>`; `<pre>`. Inline bold, italic, strikethrough and code become `<strong>`, `<em>`, `<s>`, `<code>`. Every text node has `&`, `<`, `>` and `"` escaped. No `<a>`, `<img>`, attribute or script is ever emitted.
- `markdown(title:summary:)`: `"# " + title + "\n\n" + summary` with the summary trimmed. The stored text is used verbatim, not re-serialised.

`SearchExcerpt.around(_ needle: String, in text: String, context: Int) -> String?` is `MeetingSearch`'s private `excerpt` (`MeetingSearch.swift:76-90`) made public with the context as a parameter; `MeetingSearch` calls it with `40`.

### 5.5 Meetings as pages: `MeetingCoordinator`

`MeetingWindowPresenting` and `Dependencies.makeWindow` are replaced by two closures:

```swift
var present: @MainActor (MeetingWindowModel, MeetingActions) -> Void   // show as the meeting page; bring the window forward
var dismiss: @MainActor () -> Void                                      // return to the page the meeting page was opened from
```

`Session` loses `window`. The coordinator holds:

| Slot | Holds |
|---|---|
| `current` | The chooser, or the meeting it started, until released |
| `opened` | A stored meeting opened from the list or search |
| `finishing` | Stopped sessions kept alive off screen while their summary is being written |
| `shown` | Which of `current` / `opened` is on the meeting page; `nil` when it is not showing |

"Release" a stopped session means: move it to `finishing` if its model's summary state is `.writing` or `.rewriting`, or if the coordinator's `stop()` for it has not yet returned, otherwise drop it. The second condition is needed because `MeetingController.stop` emits `.state(.stopped)` before `summarise()` emits `.summary(.writing)` (`MeetingController.swift:451-452`), so at `.state(.stopped)` the model cannot yet show `.writing`. When `stop()` returns, a session still in `finishing` whose summary state is neither `.writing` nor `.rewriting` (Stop without a summary, as at quit) is dropped.

| Entry point | Behaviour |
|---|---|
| `openChooser()` | `current` active → `show()`. `current` idle → present it. Otherwise release a stopped `current`, release `opened`, create a chooser session, present it |
| `toggle()` | Unchanged: no session or stopped → `openChooser()`; recording or paused → `stop()`; idle, starting, stopping → nothing |
| `show()` | Present `current` when it is active |
| `open(id)` | A session in any slot holds `id` → present it (from `finishing` it becomes `opened`). Otherwise release `opened`, drop an idle chooser, create a session, `controller.open(id)`, present it as `opened` |
| `pageLeft()` | Called by navigation when the destination stops being the meeting page. `shown` idle and not starting → drop it. `shown` active → keep it as `current`. `shown` stopped → release it. Then `shown = nil` |
| `.state(.stopped)` for `current` while `shown !== current` | Release `current` |
| A summary event of `.ready`, `.failed`, `.none` or `.kept` for a session in `finishing` | Drop it |
| `isOpen(id)` | A session in `current`, `opened` or `finishing` holds `id` |
| `retitle(id,to:)`, `start()`, `startTestCall(_:)`, `stop(summarise:)`, `needsQuitConfirmation`, `isActive` | Unchanged |

Hiding the window calls nothing: the page and its session stay as they are. `liveModel: MeetingWindowModel?` returns `current`'s model while `current` is active, for the recording pill.

`MeetingActions` loses `backToMeetings` and `closed`; `cancel` and the new `back` both call `dismiss`; it gains `copySummary` and `regenerate`. `openSettings` selects the Meetings section.

`MeetingControlling` gains `func regenerateSummary() async`.

### 5.6 Regenerate

`SummaryState` gains two cases:

```swift
case rewriting(Summary)              // a new summary is being written; this one is still current
case kept(Summary, reason: String)   // regeneration did not produce one; this one is still current
```

`MeetingController.regenerateSummary()`:

1. Requires `state == .stopped`, no summary request in flight, and `meeting.summary != nil`; otherwise returns.
2. No segments → emit `.kept(current, nothingTranscribed)`. No Anthropic key → emit `.kept(current, noSummaryKey)`.
3. Emit `.rewriting(current)` and run `Summariser` exactly as `summarise()` does.
4. `.ready(new)` → `billing.replacedSummaryCostUSD += current.costUSD`; `summary = new`; save; add `new`'s tokens and cost to usage; emit `.ready(new)`.
5. `.declined(category)` → emit `.kept(current, "Summary declined (category)")`. `.empty` → `.kept(current, nothingTranscribed)`. A thrown error → log a warning with the reason and emit `.kept(current, reason)`.

`summarise()` keeps its contract and shares the request code. Nothing is written to disk on any `.kept` path.

Every site that switches on `SummaryState` handles the new cases:

| Site | Change |
|---|---|
| `MeetingWindowModel.summaryPanel` (`:370-382`) | `.rewriting` and `.kept` yield `.ready` with a notice (below) |
| `MeetingWindowModel.costText` (`:360-363`) | Uses the current summary of `.ready`, `.rewriting` or `.kept` |
| `MeetingWindowModel.apply` (`:550-552`) | On `.ready(new)` arriving while the state is `.rewriting(old)`, `cost += old.costUSD` |
| `MeetingWindowModel.show` (`:461`) | `cost = billing.costUSD + billing.replacedSummaryCostUSD` |
| `MeetingCoordinator.forwardEvents` (`:386`) | Unchanged call to `changed`, plus the `finishing` rule of §5.5 |
| `SummaryPanelView` (`App/Meeting/MeetingView.swift:250-320`) | Removed; `FinishedPage`'s Summary tab renders `SummaryPanel` (§5.9) |
| `MeetingController.open` (`:588`) | Unchanged: emits `.ready` |

`SummaryPanel.ready` becomes `ready(blocks: [SummaryDocument.Block], meta: String, notice: Notice?)` with `Notice` = `.rewriting` or `.failed(String)`. The model parses the document once per summary event.

It applies to test calls and to meetings whose transcript exceeds the 600,000-character limit; the latter keep the `partial` mark in the meta line.

### 5.7 Navigation: `MainNavigationModel`

```swift
enum Destination: Hashable { case meetings, dictations, settings, search, meeting }
```

| State | Meaning |
|---|---|
| `destination` | The page shown; starts at `.meetings` |
| `origin` | Where `back()` goes from `.meeting`: the destination before it; never `.meeting`. A search origin keeps its query |
| `beforeSearch` | The last destination that was neither `.search` nor `.meeting` |
| `query` | The search text, shared with `SearchModel` |

| Action | Rule |
|---|---|
| `go(_:)` | Sets `destination`. Leaving `.meeting` calls `meetingPageLeft` (→ `coordinator.pageLeft()`). Leaving `.settings` calls `settingsLeft` (→ `settings.cancelCapture()`). Clears `query` unless going to `.search` |
| `showMeeting()` | Used by `present`. If `destination` is not `.meeting`, `origin = destination == .search ? .search : destination`. Sets `destination = .meeting` |
| `back()` | `go(origin)` without clearing `query` when `origin` is `.search` |
| `query` set to non-empty | `destination = .search` (through the leaving rules) |
| `query` set to empty while `destination == .search` | `go(beforeSearch)` |
| `revealDictation(id)` | `go(.dictations)`, then `history.reveal(id)` |

The back pill is labelled with the origin: `Meetings`, `Dictations`, `Results` or `Settings`. The Settings section lives in `SettingsModel.selection`; changing it away from `.hotkeys` calls `cancelCapture()`.

Entering `.meetings` reloads the meetings model; `.dictations` reloads the dictations model; `.settings` calls `refreshKeys()`. Showing the window does the same for the current destination.

### 5.8 Main window, theme, activation

**Window.** Style `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`, transparent title bar, title `Mini Whisper` hidden, `minSize` 900×600, `isReleasedWhenClosed = false`. The sidebar is 248 points wide and fixed; the traffic lights sit over it. `MainWindow.cancelOperation` calls `settings.cancelCapture()` when a hotkey field is capturing and does nothing otherwise.

`MainWindowController` and its models are created at the end of `AppDelegate.startNormal()` and shown on demand. `firstRunSettings` (`App/AppDelegate.swift:379-385`) shows it at Settings. `GlobalKeyListener`'s capture actions go to its `SettingsModel` (`App/AppDelegate.swift:184-187`). Quit hides it, which saves the frame. `show(_ destination:)` applies `EditMenu.ensure()`, navigates, restores the frame on the first show, and orders the window front through `WindowActivation`. `hide()` saves the frame and orders out; `windowWillClose` does the same and calls `settings.cancelCapture()`.

**Frame.** `WindowFramePolicy.frame(saved:screens:)`: with a saved frame that intersects some screen's `visibleFrame` by at least 100×100 points, return it with its size raised to 900×600 and clamped to that screen's `visibleFrame`; otherwise return 1080×720 centred on the main screen's `visibleFrame`. The frame is written with `ConfigStore.update` on hide, on close and at quit, only when it differs from the stored value.

**Theme.** `ThemeApplier.apply(_:)` sets `NSApp.appearance` to `nil`, `.aqua` or `.darkAqua`. `AppDelegate.apply(_:)` calls it on every config change. `applicationDidFinishLaunching` creates the one `ConfigStore` first, applies the theme, and only then calls `showOnboarding()` or `startNormal()`, which receives that store. `ConfigStore.load()` writes only what `startNormal`'s first load writes today — defaults when there is no file, the corrupt-file backup, the `daily_usage` migration (`ConfigStore.swift:75-120`) — so loading before onboarding moves those writes earlier and adds none. `SettingsModel.setTheme(_:)` writes the key. The overlay panels draw fixed colours and are unaffected.

**Activation.** `WindowActivation.shown(_:)` sets `.regular`, activates the app and orders the window front. `WindowActivation.closed()` runs on the next main-queue turn and sets `.accessory` when no titled window is visible. The main, Correction, About and Onboarding controllers use it in place of their own policy calls, and so do the two other places that set `.accessory` unconditionally today — the end of a Sparkle update session (`App/AppUpdater.swift:57-59`) and the speech-model prompt (`App/Onboarding/SpeechModelPrompt.swift:55`) — or either would hide the Dock icon while the main window is open (R7).

**Shortcuts** are SwiftUI keyboard shortcuts on the sidebar's controls and on the back pill, plus two hidden buttons for ⌘F and ⌘W. Esc in the search field sets the query to empty. No menu-bar menu is added beyond the existing Edit menu.

### 5.9 Interfaces: the surfaces

The accepted mockups are the specification of appearance. Where a number below and a mockup disagree, the mockup wins.

- Main window at rest — [mockup-v6-overview.html](./mockups/mockup-v6-overview.html#overview) · https://claude.ai/artifact/73WyfAtW3rW3g2SrR4MntB
- Starting and recording — [mockup-v6-recording.html](./mockups/mockup-v6-recording.html#recording) · https://claude.ai/artifact/D3o6hXbz4baDQKXyvE94UE
- Correction, Onboarding, About — [mockup-v6-windows.html](./mockups/mockup-v6-windows.html#windows) · https://claude.ai/artifact/DGmZLpnKHAbyfkGFmtNXuw

**Sidebar.** Search pill (placeholder `Search`, `⌘F` hint). Start Meeting as the one filled pill, or the recording pill: four bars that pulse while the state is `.recording` and rest when paused or under Reduce Motion, the title (`Starting…` while empty), and the elapsed time as `mm:ss` under an hour and `h:mm:ss` from one hour, or `Paused`. Then Meetings, Dictations, Settings with a chevron; the nine sections as text rows beneath Settings while `destination == .settings`. The usage table is pinned to the foot.

**Usage table.** Header row `Tokens in/out`, `Audio`, `Cost`; rows `Today` and `Month`; numeric cells right-aligned in tabular figures. Cells come from `UsageTable` (§5.11).

**Page column.** Every non-meeting page is a centred column, 736 points at most, opening with a display-serif title.

**Meetings.** Title `Meetings`; a line `N meetings · X MB audio` with a `Show in Finder` link; then day groups. A row: a tile by mode (remote: accent-soft with the display symbol; in the room: teal-soft with the people symbol); the title, with the TEST chip for a test call; the sub line per R18, the transcript case in italics inside curly quotes; a meta line; the start time `HH:mm` at the right. Meta is `duration · mode · N speakers · cost`, with ` · No summary` when there is none; for a test call `duration · WER x.x% · engine · cost`, the WER only once scored. Audio size leaves the meta line; it stays in the Export menu's `Delete audio (N MB)`. Open, Export ▾ and Delete sit at the right of the meta line, in the layout at all times and visible on hover or keyboard focus. Double-click or Return opens. The context menu keeps Open, Rename…, Delete…. Delete is disabled with the help text `This meeting is recording, on screen, or its summary is being written` when `isOpen`. Before the first meeting the page shows the cloud-and-pulse mark, `No meetings yet`, today's explanation naming the hotkey, and Start Meeting.

**Finished meeting.** A top bar: the back pill; then Copy summary, Regenerate and Export ▾. The title in the display serif, renamed in place as today. Chips: `EEE d MMM · HH:mm–HH:mm`, duration, mode, up to three speaker names then `+N`, and `cost total`; the TEST chip beside the title for a test call. A pill switch `Summary · Transcript · Notes · N` (the count only when above zero). The selected tab is model state, set to Summary — Transcript for a test call — when the meeting first becomes stopped on that model.

- *Summary* shows, by `summaryPanel`: `.writing` → a status line with the bars and `Writing the summary…`; `.message` → a warning status line with the text and a Summarise button when allowed; `.ready` → the blocks in a 640-point column and the meta line beneath a hairline. With notice `.rewriting` a status line `Writing a new summary. This one stays until it arrives.` precedes the blocks; with `.failed(reason)` a warning status line `Not regenerated: reason` does.
- Blocks: top-level headings at `type.heading` (16/24, semibold) whatever their `#` count, the next level present at `type.heading.2` and the one after at `type.heading.3`; paragraphs and items at `type.reading`; items indented 20 points per depth with a `•` or the ordinal; second-level and deeper items in secondary text; rules as a hairline; code in `type.mono` on a card.
- *Transcript* is today's transcript in a 640-point column: paragraphs, note and marker lines, the rename popover, double-click editing and the reassign menu. Its source line is today's, with ` · double-click a paragraph to edit it, click a name to rename the speaker` appended when the meeting is not a test call. For a test call the column shares the page with the Score pane (310 points) and a selected score line highlights its paragraphs.
- *Notes* lists the notes by time, read-only.
- Copy summary is enabled whenever a summary is on screen and reads `Copied` for 1.5 seconds after a copy. Regenerate is enabled in `.ready` and `.kept`. Both are disabled otherwise.
- Regenerate opens a `DSDialog`: `Regenerate the summary?` / `The current summary cost $X. It stays until the new one arrives, and stays if the request fails.` / Cancel, Regenerate (filled). `$X` is `Pricing.dollars(summary.costUSD)`.

**Chooser and Test Call setup.** As drawn: title `Start a meeting`, the explanation, two mode cards with a radio mark, description and price, the system-audio note before the first remote meeting, the engine line whose link opens Settings → Meetings, then Test Call… (quiet), Cancel and Start (filled). With no engine key the reason replaces the engine line and Start and Test Call… are disabled. Test Call setup has a Back pill, the title with the TEST chip, the description, one card with Scenario, Engine and Overlap rows, Cancel and Start Test Call.

**Live meeting.** A one-line header: the title at `type.title.compact`, renamed in place; the mode chip or TEST chip; the capture chip with a green dot while recording, and a grey dot and the text `Paused` while paused; a warning chip while reconnecting; then elapsed time, `cost so far`, Pause/Resume, and Stop with a small square in the recording colour. Error and silence-hint lines sit under the header, the latter with Open Privacy Settings…. Below: the transcript, and a 280-point Notes pane with its composer, or the 310-point Script pane for a test call. Pause is disabled in a test call with today's help text. `ScriptPane` and `ScorePane` keep their content and behaviour and are restyled with the components: a pane header, the current line on an accent-soft card labelled `Your line — read it aloud`, chips for the per-voice rates, the display serif for the word error rate.

**Dictations.** Title `Dictations`; a line `Keeping N days · N dictations` (or `History off · …`) with a `Clear…` link in the recording colour that opens a `DSDialog`. Rows by day: the app tile, the text clamped to two lines, a meta line, and Paste into *app* (accent label), Correct…, Copy, Delete (recording-colour label) at the right of the meta line, visible on hover, focus or selection. `reveal(id)` selects a row and scrolls it into view.

**Search results.** Title `Results for “query”`. Group `Meetings · N`: tile, title, up to two snippets with their label (`Speaker · time`, `Note · time`, `Summary`), a meta line `day · duration · mode`, the start time. Group `Dictations · N`: app tile, text, `day HH:mm · app`. Every occurrence of the query in a snippet or text is highlighted with the accent-soft fill. A dictation longer than 200 characters is shown as `SearchExcerpt.around(query, in: text, context: 90)`. No match: `No matches for “query”`. Rows open on click or Return.

**Settings.** Each section is a page: a display-serif title, then cards. The mapping from today's panes is mechanical: a label-and-control pair becomes a `SettingRow` (name and description left, control right); a `SettingsFootnote` becomes the description of the row above it; a `Divider()` or heading starts a new card, the heading becoming the card's group label; an editor, list or preview spans the card's width. A row with no footnote today has no description, with two exceptions taken from the mockup: Live transcript reads `Show the words in the overlay while you speak.`, and Check Now sits in a row titled `Check for an update now`. General's cards are labelled Dictation, Appearance (new, holding the Theme pill switch) and Updates; Meetings' are Engine, Recording, Summary, Storage, and Command line and agents; a section with one card has no label. Radio lists keep a filled accent ring for the selected row. `SettingsModel.Section.history` is titled `Dictations` (`App/Settings/SettingsModel.swift:83`); `Open History…` (`App/Settings/HistorySection.swift:35`) and `Open Meetings…` (`App/Settings/MeetingsSection.swift:133`) are removed with their `SettingsModel` dependencies. General and Meetings are drawn in the overview mockup; the other seven follow the same mapping.

**Small windows.** Standard title bars. Correction: the fields of today in today's order with sentence-case labels, Scope as a pill switch, Save as the filled pill; the window is 560 wide and sized to its content at each `show`. Onboarding: a serif title `Mini Whisper needs two permissions`; the explanation `Microphone access is needed to transcribe speech, and Accessibility access allows pasting the transcribed text into other apps.`; one card with a row per permission showing `Granted` with a tick or `Not granted yet` with Open Settings; today's status line; and Continue, enabled once both are granted. It is a SwiftUI view over the existing `OnboardingModel`; the controller keeps its 1.5-second poll and its unclosable window. About: the cloud-and-pulse mark on an accent tile, `Mini Whisper` in the serif, the version, and the three lines of `App/AboutPanel.swift:15-18`; it closes with the window's close button and has no OK button. `CloudPulseMark` is a SwiftUI `Shape` drawn from the two paths of the `i-cloud` symbol in the overview mockup.

**Dialogs.** In-window confirmations use `DSDialog` (a scrim and a 380-point card; Return triggers the filled button, Esc and a click on the scrim cancel): regenerate, delete meeting, delete audio, clear dictations (the Dictations page's Clear… and Settings → Dictations' Clear History, `App/Settings/HistorySection.swift:38`, each keeping its texts), merge speakers. Alerts without a window stay `NSAlert`: quit during a meeting, the speech-model prompt, export errors, and the save and open panels.

**Menu.** `MenuItem.Action.history` becomes `.dictations` with the title `Dictations…` (`App/MenuModel.swift:49`, `App/StatusItemController.swift:103`). All other rows keep their titles and order.

### 5.10 Design language

- The language is recorded in [`../../DESIGN.md`](../../DESIGN.md) and rendered at [`../../design/specimen.html`](../../design/specimen.html) · https://claude.ai/artifact/65QtsskqtXey1zqK4jwDkT.
- All 60 values, components and rules accepted in the mockups are recorded as `pending v6`: the palette (canvas, sidebar, card, hover, line, three text levels, accent with on-accent and soft, recording with soft, ok, warn, teal with soft, test text and fill, three speaker colours, each light and dark); the type styles `type.display`, `type.title`, `type.title.compact` (the live meeting title), `type.title.dialog`, `type.heading`, `type.heading.2`, `type.heading.3`, `type.reading`, `type.rowtitle`, `type.body`, `type.meta`, `type.mono`; `radius.field` 8, `radius.row` 10, `radius.card` 14; `shadow.dialog`; the canonical Pill button, Rounded field, Settings card, Day-grouped row list, Sidebar and Status line, and the Segmented pill switch, Dialog and Tile components; and the theme, density, grid, max-width, responsive, iconography, motion, copy and do/don't rules. Decision 5 (light and dark with a Theme setting) is also `pending v6`.
- `DS` is the only place these values appear in code. Display type is `Font.system(size:weight:design: .serif)`, which is New York on macOS; nothing is bundled.
- `AppGlyph.palette` (`App/History/AppGlyph.swift:16-25`) keeps its eight literal colours in both themes. `SpeakerColor` takes the user's colour from the accent and the other three from `color.speaker.1–3`. `TestTag` takes its colours from `color.test.*`.
- `DESIGN.md` records no drift.

### 5.11 Usage

```swift
public struct UsageTotals: Equatable, Sendable { public var today: DayEntry; public var month: DayEntry }
public struct UsageTable: Equatable, Sendable {
    public struct Row: Equatable, Sendable { public var tokens, audio, cost: String }
    public var today, month: Row
}
```

`UsageRecording.totals()` returns `UsageTotals`. `month` is the sum over the stored days of the current month: tokens added, `streamedSeconds` merged per engine, costs added. `FakeUsageStore` follows.

`Pricing.usageTable(_:)` formats a row as: tokens `in/out` with today's `tokens` rule (`1.2k/340`); audio as whole minutes of all streamed seconds, `Nm` under an hour and `Hh Mm` from one hour; cost with `Pricing.dollars`. `Pricing.formatUsageRows(_:)` builds the menu strings from the same cells: `Today: 1.2k/340 tok · 3m · $0.12` and `Month: 48.6k/9.1k tok · 2h 14m · $1.50`.

`UIEvent.usage` carries `UsageTotals` instead of two strings (`UIEvent.swift:14`, emitted at `ProcessingJob.swift:188-190`). `UIEventRouter` and `AppDelegate.meetingChanged` pass the totals to `StatusItemController.setUsage(_:)` and to `MainWindowModel.usage`. `MenuModel.setUsage` keeps one overload taking `UsageTotals`. The sites that change are `ProcessingJob.swift:188-190`, `UIEventRouter.swift:77-78`, `AppDelegate.swift:172-173` and `:372-373`, `StatusItemController.swift:53-60`, `MenuModel.swift:42` and `:69-77`, and `FakeUsageStore`.

### 5.12 Search: `SearchModel`

`@MainActor @Observable`, with dependencies `library: any MeetingReading`, `history: HistoryStore`, `clock`, `now`, `calendar`.

1. `query` changes → cancel the pending task. Empty after trimming → clear the results and the cache.
2. Otherwise sleep 150 ms on the clock, then off the main actor: load every indexed meeting not yet in the cache, storing each with its segments' `words` emptied; run `MeetingSearch().search(query, in: cached)`; run `history.search(query)`.
3. Publish `meetings: [MeetingHit]` newest first and `dictations: [DictationHit]` newest first, unless the task was cancelled.

Snippet labels are built as `MeetingsListModel.label(of:in:)` does today (`App/Meetings/MeetingsListModel.swift:284-296`), which moves here. `invalidate()` empties the cache and re-runs the current query; `AppDelegate.meetingChanged` and every dictation delete or clear call it.

`MeetingsListModel` loses `query`, `hits`, `Snippet`, `Row.snippets`, the search task and the match-count footer. `HistoryListModel` loses `query` and always lists `history.search("")`.

### 5.13 Dictations: paste target

`FrontAppTracker` is `@MainActor @Observable`. It starts with `NSWorkspace.shared.frontmostApplication` when that is not Mini Whisper, and on every `NSWorkspace.didActivateApplicationNotification` for another process stores that app as `previousApp`. `HistoryListModel.previousApp` becomes a read of `deps.previousApp()`; `pasteTitle`, `canPaste` and `paste(_:)` are otherwise unchanged (`App/History/HistoryListModel.swift:83-90`, `:127-137`). `deps.hide` hides the main window.

### 5.14 Control flow

**Open from the menu.** Menu row → `AppDelegate` → `main.show(destination)` → `EditMenu.ensure()` → `navigation.go` → frame restored on first show → `WindowActivation.shown`.

**Record a meeting.** Start Meeting → `coordinator.openChooser()` → `present` → `navigation.showMeeting()`. Start → `coordinator.start()` → controller events → the model's state leaves `.idle` → `MeetingPage` shows `LivePage`; `changed()` sets the menu rows and `main.liveMeeting`, so the pill replaces Start Meeting. The user opens Dictations → `go(.dictations)` → `pageLeft()` keeps `current`. The pill → `coordinator.show()` → `present`. Stop → `.state(.stopped)` → `FinishedPage` on Summary with `Writing the summary…` → `.summary(.ready)` → blocks. Back → `dismiss` → `back()` → `pageLeft()` releases the session; the list reloads.

**Stop with the window hidden.** Hotkey → `toggle()` → `stop()`. The page is still the meeting page, so `shown === current` and the session stays; the window is not shown. Stop while on another page: `shown` is `nil`, so `current` is released into `finishing`, the summary is written, and the session is dropped when it arrives.

**Regenerate.** Regenerate → `DSDialog` → Regenerate → `actions.regenerate` → §5.6. The notice line shows until `.ready` or `.kept`.

**Copy.** Copy summary → `SummaryDocument.markdown(title:summary:)`, `document.html(title:)`, `SummaryRichText.rtf(title:blocks:)` → `RichPasteboardWriting.write(markdown:html:rtf:)` clears the pasteboard and sets `.string`, `.html` and `.rtf` → the model sets `justCopied` and clears it after 1.5 s on its clock.

**Search.** Typing → `navigation.query` → `.search` → `SearchModel`. Clicking a meeting → `coordinator.open(id)` → `showMeeting()` with `origin = .search`. Back → results, query intact. Clearing the field → `beforeSearch`.

**Paste a dictation.** Paste into *app* → hide the main window → activate the target → 150 ms on the clock → paste to its pid, as today.

### 5.15 Failure and edge cases

| Case | Behaviour |
|---|---|
| Saved frame on a disconnected display, or smaller than the minimum | Default frame, or the saved frame raised to 900×600 and clamped to the screen |
| `main_window_frame` malformed | Treated as absent |
| Config write of the frame fails | Logged as a warning; the next show uses the last stored frame |
| `theme` unrecognised | System appearance; the raw value survives a save |
| Prompt migration cannot read or write | Warning logged; the old file stays; summaries use it |
| Edited prompt yields no headings | Blocks render as paragraphs and items; the row shows the first sentence |
| Summary with unclosed fence, tables, HTML, images | Code block to the end; plain paragraph text; image syntax as its text |
| Regenerate with no Anthropic key, declined, failed, or nothing transcribed | `.kept`: the old summary stays; `Not regenerated: reason`; nothing is saved or billed |
| Regenerate or Summarise pressed twice | The second call returns: a request is in flight |
| Leaving a finished page while its summary is written | The session moves to `finishing`; the summary is saved; the list reloads; reopening the meeting meanwhile presents the same session |
| Delete of a meeting held by a session | Disabled in the list |
| `open(id)` throws | The list or results page shows the error line it shows today; the page does not change |
| Start fails | The chooser stays with the error text, as today |
| Chooser open when a stored meeting is opened | The chooser session is dropped |
| Start Meeting or ⌘N during a meeting | The live page is shown |
| Paste target has quit | Paste is disabled, as today |
| Search load of a meeting fails | That meeting is skipped; the rest are searched |
| Query changes during a search | The running task is cancelled; its results are not published |
| Window hidden while a hotkey field captures | Capture is cancelled and the previous combo restored |
| A dictation is revealed that retention has since removed | Dictations opens with no selection |
| Usage for a month with no entries | Cells read `0/0`, `0m`, `$0.00` |
| Reduce Motion | The recording pill's bars do not animate |

### 5.16 Security

- A summary is model output over untrusted speech. Links and images are never active in the window. The HTML put on the pasteboard is built from escaped text nodes with a fixed tag set and carries no link, image, attribute or script; the RTF is text with fonts and indents only.
- The summariser's data rule and tag escaping are unchanged (`Summariser.swift:20-24`, `:104-106`). The new prompt adds no instruction that weakens them.
- No secret is involved. Key handling stays in Settings → Keys and the Keychain.
- The search query, summary text, transcript text and dictation text are never logged.
- `main_window_frame` is numeric data read from a user-writable file; non-finite values are rejected and the size is clamped before it reaches AppKit.
- The MCP server and CLI stay read-only; they see the new `excerpt` and `costUSD` values through the unchanged `IndexEntry`.

### 5.17 Performance

- `SummaryDocument` parses in one pass, once per summary event; the model keeps the blocks and their inline attributed text. A summary is at most 16,000 output tokens (`Packages/MiniWhisperCore/Sources/MWTranscription/AnthropicClient.swift:29`). Blocks render in a `LazyVStack`.
- The transcript reduction and its in-order fast path are untouched (`App/Meeting/MeetingWindowModel.swift:597-725`).
- Search loads each meeting from disk once per search session instead of once per query, off the main actor. The cache drops word timings, so it holds text only, and is emptied when the query is cleared.
- The meetings list no longer loads meetings at all; it reads the index.
- The frame is written to `config.json` at hide, close and quit only, never during a live resize.
- `FrontAppTracker` handles one notification per app switch.

### 5.18 Observability

`Log.ui.info`: main window shown with its destination; hidden; theme applied (value only); frame restored or defaulted. `Log.ui.warning`: frame write failed; prompt migration failed. `Log.ui.info`: summary prompt migrated. `Log.meeting.info`: regenerate started; regenerate result (`ready`, `kept` with the reason). `Log.meeting.warning`: search skipped N meetings. User-visible: the status lines of §5.9 and the existing error lines. No flag and no staged rollout: the feature ships whole in one release.

### 5.19 Compatibility / migration

- `config.json`: two additive keys. A build without them preserves them as unknown keys.
- `meeting.json`: one additive key; old files decode with `0`.
- `index.json`: unchanged shape.
- `summary_prompt.txt`: §5.3. On the developer's Mac the installed file equals the legacy default, so it migrates.
- Stored four-section summaries display through `SummaryDocument`; their list rows keep the first sentence.
- `~/.config/mini-whisper/`, the bundle ID, the Keychain items and Sparkle's preferences are untouched.
- `README.md`, `CHANGELOG.md` (`[Unreleased]`) and the layout and module map in `CLAUDE.md` are updated in the same change. `DESIGN.md` and `design/specimen.html` are committed.

### 5.20 Testing strategy

Swift Testing throughout; core suites under `Packages/MiniWhisperCore/Tests/<Module>Tests`, app suites under `AppTests`. No test sleeps.

| Component | Suite | What is verified, in isolation |
|---|---|---|
| `SummaryDocument` | `MWMeetingsTests/SummaryDocumentTests` | Each parsing rule; indent-stack depths for 2- and 4-space and tab nesting; continuation lines; unclosed fence; `topics`; `isFourSection`; `excerpt` for topic, four-section, heading-less and empty input; `inline` strips links and images; `html` escapes `<&>"`, nests lists, emits no `<a>`; `markdown(title:summary:)`. Fixtures: a topic summary added to `MeetingFixtures`, the existing four-section one |
| `SearchExcerpt` | `MWMeetingsTests/MeetingSearchTests` | Existing cases pass through the extracted type; a 90-character context case |
| `MeetingStore` | `MWMeetingsTests/MeetingStoreTests` | Index excerpt for both summary formats and none; `costUSD` includes `replacedSummaryCostUSD`; a `meeting.json` without the key decodes |
| `MeetingController` | `MWMeetingPipelineTests/MeetingControllerTests` | `regenerateSummary` per branch of §5.6 with `FakeSummarizer`: events in order, what is saved, usage added once, replaced cost accumulated, nothing saved on `.kept`; a second call while in flight returns |
| `PromptFiles` | `MWConfigTests/PromptFilesTests` | The three migration outcomes; whitespace-insensitive match; edited file's bytes unchanged |
| `Config` | `MWConfigTests/ConfigCodingTests` | `theme` and `main_window_frame` round-trip; unknown theme preserved; malformed frame reads as absent |
| `UsageStore`, `Pricing` | `MWUsageTests` | Month totals across days and engines; table cells and menu rows at 0, 59 and 134 minutes |
| `MainNavigationModel` | `AppTests/MainNavigationModelTests` | Every row of §5.7, including search from a meeting page and back from results |
| `MeetingCoordinator` | `AppTests/MeetingCoordinatorTests` | Every row of §5.5 with a fake controller and recorded `present` / `dismiss` calls; the existing 26 tests are ported from window fakes to these |
| `MeetingWindowModel` | `AppTests/MeetingWindowModelTests` | Summary panel for all six states; cost after a regenerate; initial tab; chips; pill elapsed text; `justCopied` on a manual `Clock` fake (AppTests cannot link `VirtualClock`) |
| `SearchModel` | `AppTests/SearchModelTests` | Debounce on a manual `Clock` fake; cancellation; cache reuse and invalidation; labels; ordering; long-dictation excerpt |
| `MeetingsListModel`, `HistoryListModel` | existing suites | Row fields and meta strings; search tests removed (10 references in `MeetingsListModelTests`, 2 in `HistoryListModelTests`); paste with a fake tracker; `reveal` |
| `WindowFramePolicy` | `AppTests/WindowFramePolicyTests` | On-screen, off-screen, too small, larger than the screen |
| `MenuModel`, `SettingsModel` | existing suites | Renamed row; usage rows; `setTheme`; section title; removed dependencies |
| `SummaryRichText` | `AppTests/SummaryRichTextTests` | String content and indents of the attributed text; RTF data is non-empty and re-reads to the same string |
| `DS` | `AppTests/DSTests` | A colour resolves to its light and dark value under each appearance |

Acceptance is checked by hand on a built app, in both themes: each requirement R1–R24, plus the carried-over behaviours of R13 and a remote test call end to end. `ThemeApplier`, `WindowActivation` and `FrontAppTracker` are thin AppKit adapters and are covered there.

## 6. Alternatives considered

- **Summary above the transcript with notes beside it, as today** — rejected: the summary is the thing read, and a single column is what the reference and the accepted mockup show.
- **Settings replacing the sidebar's contents, as in the reference** — rejected: Meetings, Dictations and the recording pill would disappear while in Settings.
- **A global search plus per-list filter fields** — rejected by the user in favour of one field.
- **Foundation's full Markdown parsing (`AttributedString` with presentation intents) for the block structure** — rejected: its intent mapping is thinly documented, it drops rules, and its output is tied to the OS release, while the grammar to support is small and fully testable as a line parser.
- **A new `MWSummary` module** — rejected: `MeetingStore` needs the excerpt, and a target for one type adds registration without a seam.
- **Theme applied per window** — rejected: alerts, popovers and panels would keep the system appearance; app-wide is safe because the overlay draws fixed colours.
- **`setFrameAutosaveName` for the window frame** — rejected: it stores in `UserDefaults`, and app state lives in `config.json`.
- **Keeping the main window open after a paste from Dictations** — rejected: handing focus to the target without hiding is unproven on macOS 14, and the hide-then-paste path is the shipped one.
- **Native `.alert` / `.confirmationDialog` for in-window confirmations** — rejected: the accepted mockup draws the dialog in the language; `NSAlert` stays where there is no window.
- **`mockup-v6-overview.html`, `mockup-v6-recording.html`, `mockup-v6-windows.html`** are companions, each accepted; no mockup alternative was rejected.

## 7. Risks and issues

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Regressions in accepted behaviour as four windows become pages (paste target, recording while hidden, hotkey capture, delete-while-open, ⌘C/⌘V) | Medium / high | Each is a requirement (R6, R12, R13, R20, R22) with a model test in §5.20 and a line in the hand check; `EditMenu.ensure()` runs on every show |
| The coordinator's session lifetime is new logic | Medium / high | One table (§5.5), one test per row, existing tests ported rather than rewritten |
| The model ignores the prompt's structure | Medium / low | The parser accepts any Markdown; the row falls back to the first sentence; four-section output is detected |
| Mixed formats in one library | Certain / low | Both render; Regenerate converts one meeting at the usual summary cost |
| Stock controls (pickers, steppers, text views) sit unevenly in the custom language, mostly in the less-visited Settings sections | Medium / low | Components wrap the common ones; the hand check covers all nine sections in both themes |
| A popover or sheet ignores the forced appearance | Low / low | `NSApp.appearance` is app-wide; checked by hand for the rename popover, dialogs, export panels and alerts |
| The custom dialog is weaker than `NSAlert` for keyboard and VoiceOver | Medium / medium | `DSDialog` defines Return, Esc and focus on the filled button, and carries an accessibility label and modal trait; six call sites only |
| Search memory grows with the library | Low / low | The cache holds text only and lives for one search session |
| Resemblance to the reference product | Low / medium | Own palette from the app icon, system type, own mark, no reference asset or copy; recorded as decision 6 in `DESIGN.md` |
| Release freeze: fixes wait, and a release from a branch has CI commit the appcast to `main` | Medium / medium | An urgent fix is cut from a branch off `v0.6.2`; `main` is pulled before the next commit, as `CLAUDE.md` already requires after any release |
| `MeetingCoordinatorTests`, `MeetingsListModelTests`, `MeetingWindowModelTests` and `MenuModelTests` change together | Certain / medium | The plan stages core, then components, then shell, then pages, keeping the suite green at each stage |

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

- All work lands on `main` in stages; no release is cut until every stage is in. An urgent fix ships from a branch off the `v0.6.2` tag.
- Order of work, each stage leaving the app working: (1) core — `SummaryDocument`, excerpt, total cost, regenerate, prompt and migration, config keys, usage totals; (2) `DS` and components; (3) main window, navigation, Meetings, Dictations, Settings pages, menu wiring, removal of the three list windows; (4) meeting pages and the coordinator, removal of the meeting window; (5) search; (6) Theme, Correction, Onboarding, About; (7) documentation and the `[Unreleased]` changelog entry.
- No feature flag. Between stages 3 and 4 the meeting window coexists with the main window; that state is never released.
- The release is `0.7.0`: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, the changelog section, the tag. The workflow is unchanged.
- Rollback is a revert of the release commit and a patch release; data written by v6 (`theme`, `main_window_frame`, `replacedSummaryCostUSD`, topic summaries, the migrated prompt) is read safely by 0.6.2, which ignores the new keys and shows a topic summary as headed sections.
- After release, `/design-language-update` is run so the `pending v6` entries in `DESIGN.md` become active.

# DESIGN.md

Notes outside the marked region are yours: /design-language-update reads them as decisions that outrank the code, and never edits them.

<!-- design-language:start -->
<!-- Managed by /design-language-update. Edits inside this region are overwritten on the next run; write overrides above or below it. -->
## Design language — Mini Whisper

| Field | Value |
|---|---|
| Classification | partial |
| Platforms | macOS |
| Updated | 2026-11-13 16:32 UTC |
| Specimen | https://claude.ai/artifact/65QtsskqtXey1zqK4jwDkT |

### Visual Theme & Atmosphere

Warm neutral surfaces with a sky-blue accent taken from the app icon, serif display titles over SF Pro, pill controls, cards with hairline rows, and no shadow inside a window.
Source: user · pending v6

### Color Palette & Roles

| Token | Light | Dark | Role | Group | Source |
|---|---|---|---|---|---|
| color.accent | #2A6FC9 | #7DB8F0 | Primary button, links, switches, the user's speaker name | brand | user · pending v6 |
| color.accent.on | #FFFFFF | #10202F | Text on the accent | brand | user · pending v6 |
| color.accent.soft | #E3EEFB | #2A3948 | Tinted tiles, focus ring, highlights | brand | user · pending v6 |
| color.canvas | #FBFAF7 | #262522 | Content background | surface | user · pending v6 |
| color.sidebar | #F2F0EA | #1E1D1B | Sidebar and side panes | surface | user · pending v6 |
| color.card | #FFFFFF | #2F2E2A | Cards, dialogs and fields | surface | user · pending v6 |
| color.hover | #ECE9E2 | #39372F | Hovered and selected rows | surface | user · pending v6 |
| color.line | #E1DDD3 | #46443D | Borders and dividers | surface | user · pending v6 |
| color.text | #23221F | #F1EEE7 | Primary text | text | user · pending v6 |
| color.text.secondary | #6B675E | #B4AFA4 | Descriptions and secondary lines | text | user · pending v6 |
| color.text.tertiary | #969084 | #878278 | Meta lines and day headers | text | user · pending v6 |
| color.recording | #D2452D | #F07A62 | Recording mark, Stop, destructive labels | feedback | user · pending v6 |
| color.recording.soft | #FBE9E5 | #45261F | Recording pill fill | feedback | user · pending v6 |
| color.ok | #2F8A5B | #7FC79E | Granted and success | feedback | user · pending v6 |
| color.warn | #A56A00 | #E2B45E | Warnings and missing keys | feedback | user · pending v6 |
| color.test.text | #7A4FD0 | #B79CF0 | TEST chip text | feedback | user · pending v6 |
| color.test.fill | #F1ECFB | #3A3150 | TEST chip fill | feedback | user · pending v6 |
| color.test.border | #DDD0F5 | — | TEST chip border | feedback | code: App/TestCall/TestTag.swift:7 |
| color.error.text | #A11717 | — | Error words in a test-call score | feedback | code: App/TestCall/ScorePane.swift:173 |
| color.teal | #1A808F | #6CC5D1 | In-room meeting tile mark | other | user · pending v6 |
| color.teal.soft | #DDF0F1 | #1F3B3E | In-room meeting tile fill | other | user · pending v6 |
| color.speaker.1 | #7A4FD0 | #B79CF0 | Speaker name, first of three in rotation | other | user · pending v6 |
| color.speaker.2 | #1A808F | #6CC5D1 | Speaker name, second | other | user · pending v6 |
| color.speaker.3 | #B3661C | #E0A565 | Speaker name, third | other | user · pending v6 |
| color.glyph.1 | #3B70D9 | — | App tile; remote-meeting tile | other | code: App/History/AppGlyph.swift:17 |
| color.glyph.2 | #4A9E5C | — | App tile | other | code: App/History/AppGlyph.swift:18 |
| color.glyph.3 | #D97033 | — | App tile | other | code: App/History/AppGlyph.swift:19 |
| color.glyph.4 | #9E4DAD | — | App tile | other | code: App/History/AppGlyph.swift:20 |
| color.glyph.5 | #CC475C | — | App tile | other | code: App/History/AppGlyph.swift:21 |
| color.glyph.6 | #298799 | — | App tile; in-room meeting tile | other | code: App/History/AppGlyph.swift:22 |
| color.glyph.7 | #736BB8 | — | App tile | other | code: App/History/AppGlyph.swift:23 |
| color.glyph.8 | #5C5C66 | — | App tile | other | code: App/History/AppGlyph.swift:24 |

### Typography Rules

| Token | Family | Weight | Size / line height | Treatment | Source |
|---|---|---|---|---|---|
| type.display | New York | 500 | 28px / 34px | Page and meeting titles | user · pending v6 |
| type.title | New York | 500 | 22px / 28px | Small-window and empty-state titles | user · pending v6 |
| type.title.compact | New York | 500 | 20px / 26px | Live meeting title | user · pending v6 |
| type.title.dialog | New York | 500 | 18px / 24px | Dialog titles | user · pending v6 |
| type.heading | SF Pro Text | 600 | 16px / 24px | Summary topic headings | user · pending v6 |
| type.heading.2 | SF Pro Text | 600 | 15px / 22px | Second-level summary headings | user · pending v6 |
| type.heading.3 | SF Pro Text | 600 | 14px / 20px | Third-level summary headings | user · pending v6 |
| type.reading | SF Pro Text | 400 | 15px / 24px | Summary text | user · pending v6 |
| type.rowtitle | SF Pro Text | 500 | 14px / 20px | List row titles | user · pending v6 |
| type.body | SF Pro Text | 400 | 13px / 18px | Controls, settings rows, dictation text | user · pending v6 |
| type.meta | SF Pro Text | 400 | 12px / 16px | Meta lines and descriptions | user · pending v6 |
| type.mono | SF Mono | 400 | 12px / 18px | Commands to copy and prompt text | user · pending v6 |
| type.headline | SF Pro Text | 600 | 13px / 16px | Card and meeting titles | code: App/Meeting/MeetingView.swift:96 |
| type.callout | SF Pro Text | 400 | 12px / 15px | Notes, banners, secondary lines | code: App/Meeting/MeetingView.swift:54 |
| type.caption | SF Pro Text | 400 | 10px / 13px | Footnotes, in the secondary colour | code: App/Settings/SettingsView.swift:60 |
| type.label | SF Pro Text | 600 | 11px / 14px | Chips; uppercase pane and day headers | code: App/Meeting/MeetingView.swift:701 |

### Layout Principles

- Density: comfortable with 30px controls and 24px small controls — user · pending v6
- Grid: spacing in steps of 4 — user · pending v6
- Max width: 736px page column and 640px reading column, centred — user · pending v6

| Spacing token | Value | Source |
|---|---|---|
| space.1 | 2px | code: App/Meetings/MeetingsListView.swift:98 |
| space.2 | 4px | code: App/Meetings/MeetingsListView.swift:131 |
| space.3 | 6px | code: App/History/HistoryView.swift:27 |
| space.4 | 8px | code: App/Meeting/MeetingView.swift:428 |
| space.5 | 10px | code: App/Meeting/MeetingView.swift:164 |
| space.6 | 12px | code: App/History/HistoryView.swift:125 |
| space.7 | 14px | code: App/History/HistoryView.swift:45 |
| space.8 | 18px | code: App/Meeting/MeetingView.swift:202 |
| space.9 | 24px | code: App/Settings/SettingsView.swift:48 |
| space.10 | 28px | code: App/Meeting/MeetingView.swift:85 |

| Radius token | Value | Source |
|---|---|---|
| radius.small | 6px | code: App/Correction/CorrectionView.swift:72 |
| radius.field | 8px | user · pending v6 |
| radius.tile | 8px | code: App/History/HistoryView.swift:126 |
| radius.row | 10px | user · pending v6 |
| radius.card | 14px | user · pending v6 |
| radius.large | 14px | code: App/Meetings/MeetingsListView.swift:190 |
| radius.pill | 999px | code: App/Meeting/MeetingView.swift:705 |

### Depth & Elevation

| Token | Value | Use | Source |
|---|---|---|---|
| shadow.dialog | 0 14px 36px rgba(35,34,31,0.18) | Dialogs and menus only | user · pending v6 |

### Component Stylings

| Category | Canonical | Variants | Tokens | Source |
|---|---|---|---|---|
| button | Pill button | Primary filled, Secondary outlined, Quiet, Small | radius=radius.pill; bg=color.accent; fg=color.accent.on | user · pending v6 |
| input | Rounded field | Search pill, Text area | radius=radius.field; border=color.line; bg=color.card | user · pending v6 |
| card | Settings card | Mode card, Dialog | radius=radius.card; bg=color.card; border=color.line | user · pending v6 |
| table | Day-grouped row list | Meeting row, Dictation row, Search result | radius=radius.row | user · pending v6 |
| nav | Sidebar | Settings sections | bg=color.sidebar; border=color.line | user · pending v6 |
| alert | Status line | Warning line, Info note | radius=radius.row; bg=color.accent.soft | user · pending v6 |
| other | Segmented pill switch | — | radius=radius.pill; bg=color.sidebar; border=color.line | user · pending v6 |
| other | Dialog | — | radius=radius.card; bg=color.card; shadow=shadow.dialog | user · pending v6 |
| other | Tile | Remote, In the room, App | radius=radius.field; bg=color.accent.soft; fg=color.accent | user · pending v6 |
| other | Chip | Dot, Test tag | radius=radius.pill | code: App/Meeting/MeetingView.swift:690 |
| other | App glyph tile | — | radius=radius.tile | code: App/History/AppGlyph.swift:5 |
| other | Pane header | — | — | code: App/Meeting/MeetingView.swift:672 |

### Responsive Behavior

- Main window: resizable, 1080 by 720 by default, 900 by 600 at least — user · pending v6
- Small windows: Correction, Onboarding and About keep a standard title bar and a fixed size — user · pending v6
- Windows are fixed-size and cannot be resized — code: App/Settings/SettingsWindowController.swift:15
- Each task has its own window: Settings, History, Meetings, Meeting, Correction — code: App/AppDelegate.swift:361

### Iconography & Motion

- Set: SF Symbols in outline, plus the cloud-and-pulse mark of the app icon for empty states and About — user · pending v6
- Recording: the recording pill's four bars pulse while a meeting records and rest when it is paused or Reduce Motion is on — user · pending v6
- SF Symbols in outline style, one per settings section and per row state — code: App/Settings/SettingsModel.swift:90
- An app is shown as a rounded tile with its initials, coloured by a hash of its bundle ID — code: App/History/AppGlyph.swift:5
- Motion lives in the dictation overlay and the test-call level bars, and honours Reduce Motion — code: App/TestCall/ScriptPane.swift:149

### Copy Tone

- Labels: field labels and group headings in sentence case, never small capitals — user · pending v6
- Plain and direct; sentence case in text, title case for menu commands — code: App/MenuModel.swift:47
- An action that opens something ends in an ellipsis — code: App/MenuModel.swift:48
- Footnotes explain a setting's consequence in one or two sentences — code: App/Settings/MeetingsSection.swift:87
- An error states what happened and where to fix it — code: App/Meeting/MeetingWindowModel.swift:185

### Do's and Don'ts

- Do: one filled accent button per page or dialog, every other button outlined or quiet — user · pending v6
- Do: running text in the 640px reading column — user · pending v6
- Do: keep hover actions in the layout when hidden, so a row never rewraps — code: App/History/HistoryView.swift:141
- Do: colour the label, not the button, for accent and destructive row actions — code: App/History/HistoryView.swift:159
- Do: derive the language from the v6 reference screenshots without copying their branding, icons, names or copy — user: 2026-11-13
- Don't: shadows inside a window, only dialogs and menus lift — user · pending v6
- Don't: bundled fonts, display type is the system serif — user · pending v6
- Don't: restyle the dictation overlay; it keeps its own visual system — user: 2026-11-13
- Don't: make links in model-written text clickable — code: App/Meeting/MeetingView.swift:303

### Decisions

| # | Decision | By | Date | Status |
|---|---|---|---|---|
| 1 | Visual theme summarised as stock macOS: system colours, system font, compact controls | skill | 2026-11-13 | superseded by 8 |
| 2 | System semantic colours (text background, separator, control background, accent) carry surfaces and text; they have no literal value and are not tokens | skill | 2026-11-13 | superseded by 9 |
| 3 | Canonical button and input come from the accepted v6 mockup | user | 2026-11-13 | superseded by 43 |
| 4 | Until then the most-used variants stand: system push button and system text field | skill | 2026-11-13 | superseded by 43 |
| 5 | Light and dark are both designed, with a Theme setting: System, Light, Dark | user | 2026-11-13 | pending v6 |
| 6 | The language is derived from the v6 reference screenshots, not copied; Mini Whisper keeps its own character | user | 2026-11-13 | active |
| 7 | The dictation overlay keeps its own visual system and is outside this language | user | 2026-11-13 | active |
| 8 | Theme: warm neutral surfaces, sky-blue accent from the app icon, serif display titles over SF Pro, pill controls, cards with hairline rows, no shadow inside a window | user | 2026-11-13 | pending v6 |
| 9 | color.canvas is #FBFAF7 light, #262522 dark | user | 2026-11-13 | pending v6 |
| 10 | color.sidebar is #F2F0EA light, #1E1D1B dark | user | 2026-11-13 | pending v6 |
| 11 | color.card is #FFFFFF light, #2F2E2A dark | user | 2026-11-13 | pending v6 |
| 12 | color.hover is #ECE9E2 light, #39372F dark | user | 2026-11-13 | pending v6 |
| 13 | color.line is #E1DDD3 light, #46443D dark | user | 2026-11-13 | pending v6 |
| 14 | color.text is #23221F light, #F1EEE7 dark | user | 2026-11-13 | pending v6 |
| 15 | color.text.secondary is #6B675E light, #B4AFA4 dark | user | 2026-11-13 | pending v6 |
| 16 | color.text.tertiary is #969084 light, #878278 dark | user | 2026-11-13 | pending v6 |
| 17 | color.accent is #2A6FC9 light, #7DB8F0 dark | user | 2026-11-13 | pending v6 |
| 18 | color.accent.on is #FFFFFF light, #10202F dark | user | 2026-11-13 | pending v6 |
| 19 | color.accent.soft is #E3EEFB light, #2A3948 dark | user | 2026-11-13 | pending v6 |
| 20 | color.recording is #D2452D light, #F07A62 dark | user | 2026-11-13 | pending v6 |
| 21 | color.recording.soft is #FBE9E5 light, #45261F dark | user | 2026-11-13 | pending v6 |
| 22 | color.ok is #2F8A5B light, #7FC79E dark | user | 2026-11-13 | pending v6 |
| 23 | color.warn is #A56A00 light, #E2B45E dark | user | 2026-11-13 | pending v6 |
| 24 | color.teal is #1A808F light, #6CC5D1 dark | user | 2026-11-13 | pending v6 |
| 25 | color.teal.soft is #DDF0F1 light, #1F3B3E dark | user | 2026-11-13 | pending v6 |
| 26 | color.test.text is #7A4FD0 light, #B79CF0 dark | user | 2026-11-13 | pending v6 |
| 27 | color.test.fill is #F1ECFB light, #3A3150 dark | user | 2026-11-13 | pending v6 |
| 28 | color.speaker.1 is #7A4FD0 light, #B79CF0 dark | user | 2026-11-13 | pending v6 |
| 29 | color.speaker.2 is #1A808F light, #6CC5D1 dark | user | 2026-11-13 | pending v6 |
| 30 | color.speaker.3 is #B3661C light, #E0A565 dark | user | 2026-11-13 | pending v6 |
| 31 | type.display is New York 500 at 28px / 34px | user | 2026-11-13 | pending v6 |
| 32 | type.title is New York 500 at 22px / 28px | user | 2026-11-13 | pending v6 |
| 33 | type.heading is SF Pro Text 600 at 16px / 24px | user | 2026-11-13 | pending v6 |
| 34 | type.reading is SF Pro Text 400 at 15px / 24px | user | 2026-11-13 | pending v6 |
| 35 | type.rowtitle is SF Pro Text 500 at 14px / 20px | user | 2026-11-13 | pending v6 |
| 36 | type.body is SF Pro Text 400 at 13px / 18px | user | 2026-11-13 | pending v6 |
| 37 | type.meta is SF Pro Text 400 at 12px / 16px | user | 2026-11-13 | pending v6 |
| 38 | type.mono is SF Mono 400 at 12px / 18px | user | 2026-11-13 | pending v6 |
| 39 | radius.field is 8px | user | 2026-11-13 | pending v6 |
| 40 | radius.row is 10px | user | 2026-11-13 | pending v6 |
| 41 | radius.card is 14px | user | 2026-11-13 | pending v6 |
| 42 | shadow.dialog is 0 14px 36px rgba(35,34,31,0.18), for dialogs and menus only | user | 2026-11-13 | pending v6 |
| 43 | Canonical button is the Pill button | user | 2026-11-13 | pending v6 |
| 44 | Canonical input is the Rounded field | user | 2026-11-13 | pending v6 |
| 45 | Canonical card is the Settings card | user | 2026-11-13 | pending v6 |
| 46 | Canonical table is the Day-grouped row list | user | 2026-11-13 | pending v6 |
| 47 | Canonical nav is the Sidebar | user | 2026-11-13 | pending v6 |
| 48 | Canonical alert is the Status line | user | 2026-11-13 | pending v6 |
| 49 | Density is comfortable with 30px controls and 24px small controls | user | 2026-11-13 | pending v6 |
| 50 | Spacing moves in steps of 4 | user | 2026-11-13 | pending v6 |
| 51 | Max width is a 736px page column and a 640px reading column, centred | user | 2026-11-13 | pending v6 |
| 52 | The main window is resizable, 1080 by 720 by default, 900 by 600 at least | user | 2026-11-13 | pending v6 |
| 53 | Correction, Onboarding and About keep a standard title bar and a fixed size | user | 2026-11-13 | pending v6 |
| 54 | Icons are SF Symbols in outline, plus the cloud-and-pulse mark of the app icon for empty states and About | user | 2026-11-13 | pending v6 |
| 55 | The recording pill's four bars pulse while a meeting records and rest when it is paused or Reduce Motion is on | user | 2026-11-13 | pending v6 |
| 56 | Field labels and group headings are in sentence case, never small capitals | user | 2026-11-13 | pending v6 |
| 57 | One filled accent button per page or dialog; every other button outlined or quiet | user | 2026-11-13 | pending v6 |
| 58 | Running text sits in the 640px reading column | user | 2026-11-13 | pending v6 |
| 59 | No shadows inside a window; only dialogs and menus lift | user | 2026-11-13 | pending v6 |
| 60 | No bundled fonts; display type is the system serif | user | 2026-11-13 | pending v6 |
| 61 | type.title.compact is New York 500 at 20px / 26px | user | 2026-11-13 | pending v6 |
| 62 | type.title.dialog is New York 500 at 18px / 24px | user | 2026-11-13 | pending v6 |
| 63 | type.heading.2 is SF Pro Text 600 at 15px / 22px | user | 2026-11-13 | pending v6 |
| 64 | type.heading.3 is SF Pro Text 600 at 14px / 20px | user | 2026-11-13 | pending v6 |
| 65 | Segmented pill switch is a component | user | 2026-11-13 | pending v6 |
| 66 | Dialog is a component: a card over a scrim, for in-window confirmations | user | 2026-11-13 | pending v6 |
| 67 | Tile is a component: a rounded square carrying a symbol or initials | user | 2026-11-13 | pending v6 |

### Drift

None.
<!-- design-language:end -->

# DESIGN.md

Notes outside the marked region are yours: /design-language-update reads them as decisions that outrank the code, and never edits them.

<!-- design-language:start -->
<!-- Managed by /design-language-update. Edits inside this region are overwritten on the next run; write overrides above or below it. -->
## Design language — Mini Whisper

| Field | Value |
|---|---|
| Classification | established |
| Platforms | macOS |
| Updated | 2026-11-14 14:50 UTC |
| Specimen | https://claude.ai/artifact/3iQhWG4jNhvrqA4EXTwHGh |

### Visual Theme & Atmosphere

Warm neutral surfaces with a sky-blue accent taken from the app icon, serif display titles over SF Pro, pill controls, cards with hairline rows, and no shadow inside a window.
Source: user: 2026-11-13

### Color Palette & Roles

| Token | Light | Dark | Role | Group | Source |
|---|---|---|---|---|---|
| color.accent | #2A6FC9 | #7DB8F0 | Primary button, links, switches, the user's speaker name | brand | user: 2026-11-13 |
| color.accent.on | #FFFFFF | #10202F | Text on the accent | brand | user: 2026-11-13 |
| color.accent.soft | #E3EEFB | #2A3948 | Tinted tiles, focus ring, highlights | brand | user: 2026-11-13 |
| color.canvas | #FBFAF7 | #262522 | Content background and text fields | surface | user: 2026-11-13 |
| color.sidebar | #F2F0EA | #1E1D1B | Sidebar and side panes | surface | user: 2026-11-13 |
| color.card | #FFFFFF | #2F2E2A | Cards, dialogs and the search pill | surface | user: 2026-11-13 |
| color.hover | #ECE9E2 | #39372F | Hovered and selected rows | surface | user: 2026-11-13 |
| color.line | #E1DDD3 | #46443D | Borders and dividers | surface | user: 2026-11-13 |
| color.scrim | rgba(20,19,17,0.36) | — | Dims the window behind a dialog | surface | code: App/Design/DS.swift:39 |
| color.text | #23221F | #F1EEE7 | Primary text | text | user: 2026-11-13 |
| color.text.secondary | #6B675E | #B4AFA4 | Descriptions and secondary lines | text | user: 2026-11-13 |
| color.text.tertiary | #969084 | #878278 | Meta lines and day headers | text | user: 2026-11-13 |
| color.recording | #D2452D | #F07A62 | Recording mark, Stop, destructive labels, errors | feedback | user: 2026-11-13 |
| color.recording.soft | #FBE9E5 | #45261F | Recording pill fill | feedback | user: 2026-11-13 |
| color.ok | #2F8A5B | #7FC79E | Granted and success | feedback | user: 2026-11-13 |
| color.warn | #A56A00 | #E2B45E | Warnings and missing keys | feedback | user: 2026-11-13 |
| color.test.text | #7A4FD0 | #B79CF0 | TEST chip text | feedback | user: 2026-11-13 |
| color.test.fill | #F1ECFB | #3A3150 | TEST chip fill | feedback | user: 2026-11-13 |
| color.teal | #1A808F | #6CC5D1 | In-room meeting tile mark | other | user: 2026-11-13 |
| color.teal.soft | #DDF0F1 | #1F3B3E | In-room meeting tile fill | other | user: 2026-11-13 |
| color.speaker.1 | #7A4FD0 | #B79CF0 | Speaker name, first of three in rotation | other | user: 2026-11-13 |
| color.speaker.2 | #1A808F | #6CC5D1 | Speaker name, second | other | user: 2026-11-13 |
| color.speaker.3 | #B3661C | #E0A565 | Speaker name, third | other | user: 2026-11-13 |
| color.white | #FFFFFF | — | Switch knob and app-tile initials, white in both themes | other | code: App/Design/DS.swift:36 |
| color.glyph.1 | #3B70D9 | — | App tile | other | code: App/History/AppGlyph.swift:17 |
| color.glyph.2 | #4A9E5C | — | App tile | other | code: App/History/AppGlyph.swift:18 |
| color.glyph.3 | #D97033 | — | App tile | other | code: App/History/AppGlyph.swift:19 |
| color.glyph.4 | #9E4DAD | — | App tile | other | code: App/History/AppGlyph.swift:20 |
| color.glyph.5 | #CC475C | — | App tile | other | code: App/History/AppGlyph.swift:21 |
| color.glyph.6 | #298799 | — | App tile | other | code: App/History/AppGlyph.swift:22 |
| color.glyph.7 | #736BB8 | — | App tile | other | code: App/History/AppGlyph.swift:23 |
| color.glyph.8 | #5C5C66 | — | App tile | other | code: App/History/AppGlyph.swift:24 |

### Typography Rules

| Token | Family | Weight | Size / line height | Treatment | Source |
|---|---|---|---|---|---|
| type.display | New York | 500 | 28px / 34px | Page and meeting titles | user: 2026-11-13 |
| type.score | New York | 500 | 34px / 40px | A test call's word error rate | code: App/Design/DS.swift:103 |
| type.title | New York | 500 | 22px / 28px | Small-window and empty-state titles | user: 2026-11-13 |
| type.title.compact | New York | 500 | 20px / 26px | Live meeting title | user: 2026-11-13 |
| type.title.dialog | New York | 500 | 18px / 24px | Dialog titles | user: 2026-11-13 |
| type.heading | SF Pro Text | 600 | 16px / 24px | Summary topic headings | user: 2026-11-13 |
| type.heading.2 | SF Pro Text | 600 | 15px / 22px | Second-level summary headings | user: 2026-11-13 |
| type.heading.3 | SF Pro Text | 600 | 14px / 20px | Third-level summary headings | user: 2026-11-13 |
| type.reading | SF Pro Text | 400 | 15px / 24px | Summary text | user: 2026-11-13 |
| type.transcript | SF Pro Text | 400 | 14px / 22px | Transcript paragraphs and notes | code: App/Design/DS.swift:101 |
| type.rowtitle | SF Pro Text | 500 | 14px / 20px | List row titles | user: 2026-11-13 |
| type.body | SF Pro Text | 400 | 13px / 18px | Controls, settings rows, dictation text | user: 2026-11-13 |
| type.meta | SF Pro Text | 400 | 12px / 16px | Meta lines, descriptions, day and pane headers | user: 2026-11-13 |
| type.mono | SF Mono | 400 | 12px / 18px | Commands to copy and prompt text | user: 2026-11-13 |
| type.label | SF Pro Text | 600 | 11px / 14px | Chips | code: App/Design/DS.swift:109 |
| type.usage | SF Pro Text | 400 | 11px / 16px | The usage table's figures | code: App/Design/DS.swift:111 |
| type.usage.header | SF Pro Text | 400 | 10px / 16px | The usage table's column headers | code: App/Design/DS.swift:113 |

### Layout Principles

- Density: comfortable with 30px controls and 24px small controls — user: 2026-11-13
- Grid: spacing on a 2px scale, space.1 to space.10 — user: 2026-11-14
- Max width: 736px page column and 640px reading column, centred — user: 2026-11-13
- Hairline: 1px borders and dividers in color.line, counted inside a box's padding — code: App/Design/DS.swift:75

| Spacing token | Value | Source |
|---|---|---|
| space.1 | 2px | code: App/Design/DS.swift:61 |
| space.2 | 4px | code: App/Design/DS.swift:62 |
| space.3 | 6px | code: App/Design/DS.swift:63 |
| space.4 | 8px | code: App/Design/DS.swift:64 |
| space.5 | 10px | code: App/Design/DS.swift:65 |
| space.6 | 12px | code: App/Design/DS.swift:66 |
| space.7 | 14px | code: App/Design/DS.swift:67 |
| space.8 | 18px | code: App/Design/DS.swift:68 |
| space.9 | 24px | code: App/Design/DS.swift:69 |
| space.10 | 28px | code: App/Design/DS.swift:70 |

| Radius token | Value | Source |
|---|---|---|
| radius.small | 6px | code: App/Design/DS.swift:48 |
| radius.field | 8px | user: 2026-11-13 |
| radius.row | 10px | user: 2026-11-13 |
| radius.card | 14px | user: 2026-11-13 |
| radius.mark | 16px | code: App/Design/DS.swift:56 |
| radius.pill | 999px | code: App/Design/PillButtonStyle.swift:62 |

### Depth & Elevation

| Token | Value | Use | Source |
|---|---|---|---|
| shadow.dialog | 0 14px 36px rgba(35,34,31,0.18) | Dialogs and menus only | user: 2026-11-13 |
| shadow.dialog.dark | 0 14px 36px rgba(0,0,0,0.45) | shadow.dialog in the dark appearance | code: App/Design/DS.swift:41 |
| shadow.knob | 0 1px 2px rgba(0,0,0,0.25) | Switch knob; part of the control, not a lift | skill: decision 70 |

### Component Stylings

| Category | Canonical | Variants | Tokens | Source |
|---|---|---|---|---|
| button | Pill button | Primary filled, Secondary outlined, Quiet, Small | radius=radius.pill; bg=color.accent; fg=color.accent.on | user: 2026-11-13 |
| input | Rounded field | Line, Text area, Search pill | radius=radius.field; border=color.line; bg=color.canvas; focus=color.accent; ring=color.accent.soft | skill: decision 71 |
| card | Settings card | Mode card, Dialog | radius=radius.card; bg=color.card; border=color.line | user: 2026-11-13 |
| table | Day-grouped row list | Meeting row, Dictation row, Search result | radius=radius.row; hover=color.hover; header=color.text.tertiary | user: 2026-11-13 |
| nav | Sidebar | Settings sections | bg=color.sidebar; border=color.line; selected=color.hover | user: 2026-11-13 |
| alert | Status line | Progress, Info, Warning, Error | radius=radius.row; bg=color.accent.soft | user: 2026-11-13 |
| other | Segmented pill switch | — | radius=radius.pill; bg=color.sidebar; border=color.line | user: 2026-11-13 |
| other | Dialog | — | radius=radius.card; bg=color.card; shadow=shadow.dialog; scrim=color.scrim | user: 2026-11-13 |
| other | Tile | Remote, In the room, App, App mark | radius=radius.field; bg=color.accent.soft; fg=color.accent | user: 2026-11-13 |
| other | Chip | Plain, Active, Inactive, Warning, Test | radius=radius.pill; border=color.line; fg=color.text.secondary | code: App/Design/Chip.swift:5 |
| other | Switch | — | radius=radius.pill; on=color.accent; off=color.line; knob=color.white; shadow=shadow.knob | code: App/Design/DSToggleStyle.swift:5 |
| other | Radio row | — | ring=color.accent; idle=color.text.tertiary | code: App/Design/RadioRow.swift:6 |
| other | Stepper pill | — | radius=radius.pill; border=color.line; fg=color.text.secondary | code: App/Design/StepperPill.swift:5 |
| other | Pill menu | — | radius=radius.pill; border=color.line | code: App/Design/PillMenu.swift:6 |
| other | Setting row | Row, Full width | border=color.line | code: App/Design/SettingRow.swift:4 |
| other | Pane header | — | fg=color.text.secondary; border=color.line | code: App/Meeting/SpeakerColor.swift:15 |
| other | Recording pill | — | radius=radius.pill; bg=color.recording.soft; bars=color.recording | code: App/Main/RecordingPill.swift:5 |
| other | Usage table | — | fg=color.text.secondary; header=color.text.tertiary; border=color.line | code: App/Main/UsageTableView.swift:5 |

### Responsive Behavior

- Main window: resizable, 1080 by 720 by default, 900 by 600 at least — user: 2026-11-13
- Small windows: Correction, Onboarding and About keep a standard title bar and a fixed size — user: 2026-11-13
- One main window holds search, Meetings, Dictations, Settings and each meeting as pages; its size and place persist — code: App/Main/WindowFramePolicy.swift:14
- A page is a centred, scrolling column under its display-serif title — code: App/Design/PageColumn.swift:4

### Iconography & Motion

- Set: SF Symbols in outline, plus the cloud-and-pulse mark of the app icon for empty states and About — user: 2026-11-13
- Recording: the recording pill's four bars pulse while a meeting records and rest when it is paused or Reduce Motion is on — user: 2026-11-13
- SF Symbols in outline style, one per settings section — code: App/Settings/SettingsModel.swift:88
- An app is shown as a rounded tile with its initials, coloured by a hash of its bundle ID — code: App/History/AppGlyph.swift:5
- Motion lives in the dictation overlay, the pulse bars and the test-call level bars, and honours Reduce Motion — code: App/Design/StatusLine.swift:84

### Copy Tone

- Labels: field labels and group headings in sentence case, never small capitals — user: 2026-11-13
- Plain and direct; sentence case in text, title case for menu commands — code: App/MenuModel.swift:42
- An action that opens something ends in an ellipsis — code: App/MenuModel.swift:42
- Footnotes explain a setting's consequence in one or two sentences — code: App/Settings/MeetingsSection.swift:38
- An error states what happened and where to fix it — code: App/Meeting/MeetingWindowModel.swift:197

### Do's and Don'ts

- Do: one filled accent button per page or dialog, every other button outlined or quiet — user: 2026-11-13
- Do: running text in the 640px reading column — user: 2026-11-13
- Do: keep hover actions in the layout when hidden, so a row never rewraps — code: App/History/DictationsPage.swift:54
- Do: colour the label, not the button, for accent and destructive row actions — code: App/Design/PillButtonStyle.swift:21
- Do: take every colour, size and type style from DS, whose values appear nowhere else — code: App/Design/DS.swift:4
- Do: derive the language from the v6 reference screenshots without copying their branding, icons, names or copy — user: 2026-11-13
- Don't: shadows inside a window, only dialogs and menus lift — user: 2026-11-13
- Don't: bundled fonts, display type is the system serif — user: 2026-11-13
- Don't: restyle the dictation overlay; it keeps its own visual system — user: 2026-11-13
- Don't: make links in model-written text clickable — code: Packages/MiniWhisperCore/Sources/MWMeetings/SummaryDocument.swift:129

### Decisions

| # | Decision | By | Date | Status |
|---|---|---|---|---|
| 1 | Visual theme summarised as stock macOS: system colours, system font, compact controls | skill | 2026-11-13 | superseded by 8 |
| 2 | System semantic colours (text background, separator, control background, accent) carry surfaces and text; they have no literal value and are not tokens | skill | 2026-11-13 | superseded by 9 |
| 3 | Canonical button and input come from the accepted v6 mockup | user | 2026-11-13 | superseded by 43 |
| 4 | Until then the most-used variants stand: system push button and system text field | skill | 2026-11-13 | superseded by 43 |
| 5 | Light and dark are both designed, with a Theme setting: System, Light, Dark | user | 2026-11-13 | active |
| 6 | The language is derived from the v6 reference screenshots, not copied; Mini Whisper keeps its own character | user | 2026-11-13 | active |
| 7 | The dictation overlay keeps its own visual system and is outside this language | user | 2026-11-13 | active |
| 8 | Theme: warm neutral surfaces, sky-blue accent from the app icon, serif display titles over SF Pro, pill controls, cards with hairline rows, no shadow inside a window | user | 2026-11-13 | active |
| 9 | color.canvas is #FBFAF7 light, #262522 dark | user | 2026-11-13 | active |
| 10 | color.sidebar is #F2F0EA light, #1E1D1B dark | user | 2026-11-13 | active |
| 11 | color.card is #FFFFFF light, #2F2E2A dark | user | 2026-11-13 | active |
| 12 | color.hover is #ECE9E2 light, #39372F dark | user | 2026-11-13 | active |
| 13 | color.line is #E1DDD3 light, #46443D dark | user | 2026-11-13 | active |
| 14 | color.text is #23221F light, #F1EEE7 dark | user | 2026-11-13 | active |
| 15 | color.text.secondary is #6B675E light, #B4AFA4 dark | user | 2026-11-13 | active |
| 16 | color.text.tertiary is #969084 light, #878278 dark | user | 2026-11-13 | active |
| 17 | color.accent is #2A6FC9 light, #7DB8F0 dark | user | 2026-11-13 | active |
| 18 | color.accent.on is #FFFFFF light, #10202F dark | user | 2026-11-13 | active |
| 19 | color.accent.soft is #E3EEFB light, #2A3948 dark | user | 2026-11-13 | active |
| 20 | color.recording is #D2452D light, #F07A62 dark | user | 2026-11-13 | active |
| 21 | color.recording.soft is #FBE9E5 light, #45261F dark | user | 2026-11-13 | active |
| 22 | color.ok is #2F8A5B light, #7FC79E dark | user | 2026-11-13 | active |
| 23 | color.warn is #A56A00 light, #E2B45E dark | user | 2026-11-13 | active |
| 24 | color.teal is #1A808F light, #6CC5D1 dark | user | 2026-11-13 | active |
| 25 | color.teal.soft is #DDF0F1 light, #1F3B3E dark | user | 2026-11-13 | active |
| 26 | color.test.text is #7A4FD0 light, #B79CF0 dark | user | 2026-11-13 | active |
| 27 | color.test.fill is #F1ECFB light, #3A3150 dark | user | 2026-11-13 | active |
| 28 | color.speaker.1 is #7A4FD0 light, #B79CF0 dark | user | 2026-11-13 | active |
| 29 | color.speaker.2 is #1A808F light, #6CC5D1 dark | user | 2026-11-13 | active |
| 30 | color.speaker.3 is #B3661C light, #E0A565 dark | user | 2026-11-13 | active |
| 31 | type.display is New York 500 at 28px / 34px | user | 2026-11-13 | active |
| 32 | type.title is New York 500 at 22px / 28px | user | 2026-11-13 | active |
| 33 | type.heading is SF Pro Text 600 at 16px / 24px | user | 2026-11-13 | active |
| 34 | type.reading is SF Pro Text 400 at 15px / 24px | user | 2026-11-13 | active |
| 35 | type.rowtitle is SF Pro Text 500 at 14px / 20px | user | 2026-11-13 | active |
| 36 | type.body is SF Pro Text 400 at 13px / 18px | user | 2026-11-13 | active |
| 37 | type.meta is SF Pro Text 400 at 12px / 16px | user | 2026-11-13 | active |
| 38 | type.mono is SF Mono 400 at 12px / 18px | user | 2026-11-13 | active |
| 39 | radius.field is 8px | user | 2026-11-13 | active |
| 40 | radius.row is 10px | user | 2026-11-13 | active |
| 41 | radius.card is 14px | user | 2026-11-13 | active |
| 42 | shadow.dialog is 0 14px 36px rgba(35,34,31,0.18), for dialogs and menus only | user | 2026-11-13 | active |
| 43 | Canonical button is the Pill button | user | 2026-11-13 | active |
| 44 | Canonical input is the Rounded field | user | 2026-11-13 | active |
| 45 | Canonical card is the Settings card | user | 2026-11-13 | active |
| 46 | Canonical table is the Day-grouped row list | user | 2026-11-13 | active |
| 47 | Canonical nav is the Sidebar | user | 2026-11-13 | active |
| 48 | Canonical alert is the Status line | user | 2026-11-13 | active |
| 49 | Density is comfortable with 30px controls and 24px small controls | user | 2026-11-13 | active |
| 50 | Spacing moves in steps of 4 | user | 2026-11-13 | superseded by 68 |
| 51 | Max width is a 736px page column and a 640px reading column, centred | user | 2026-11-13 | active |
| 52 | The main window is resizable, 1080 by 720 by default, 900 by 600 at least | user | 2026-11-13 | active |
| 53 | Correction, Onboarding and About keep a standard title bar and a fixed size | user | 2026-11-13 | active |
| 54 | Icons are SF Symbols in outline, plus the cloud-and-pulse mark of the app icon for empty states and About | user | 2026-11-13 | active |
| 55 | The recording pill's four bars pulse while a meeting records and rest when it is paused or Reduce Motion is on | user | 2026-11-13 | active |
| 56 | Field labels and group headings are in sentence case, never small capitals | user | 2026-11-13 | active |
| 57 | One filled accent button per page or dialog; every other button outlined or quiet | user | 2026-11-13 | active |
| 58 | Running text sits in the 640px reading column | user | 2026-11-13 | active |
| 59 | No shadows inside a window; only dialogs and menus lift | user | 2026-11-13 | active |
| 60 | No bundled fonts; display type is the system serif | user | 2026-11-13 | active |
| 61 | type.title.compact is New York 500 at 20px / 26px | user | 2026-11-13 | active |
| 62 | type.title.dialog is New York 500 at 18px / 24px | user | 2026-11-13 | active |
| 63 | type.heading.2 is SF Pro Text 600 at 15px / 22px | user | 2026-11-13 | active |
| 64 | type.heading.3 is SF Pro Text 600 at 14px / 20px | user | 2026-11-13 | active |
| 65 | Segmented pill switch is a component | user | 2026-11-13 | active |
| 66 | Dialog is a component: a card over a scrim, for in-window confirmations | user | 2026-11-13 | active |
| 67 | Tile is a component: a rounded square carrying a symbol or initials | user | 2026-11-13 | active |
| 68 | Spacing moves on a 2px scale: 2, 4, 6, 8, 10, 12, 14, 18, 24 and 28px, as the code and the accepted v6 mockups do | user | 2026-11-14 | active |
| 69 | Decisions 8, 43 and 56 stand over the test call's Earlier runs sheet; the sheet is drift to fix | user | 2026-11-14 | active |
| 70 | The switch knob's 1px shadow belongs to the control, as in the accepted v6 mockup; decision 59 governs surfaces, not it | skill | 2026-11-14 | active |
| 71 | The Rounded field fills with color.canvas and the Search pill with color.card, as the accepted v6 mockup and the code do; the earlier record gave color.card | skill | 2026-11-14 | active |

### Drift

- Earlier runs sheet: decisions 8, 43 and 56 call for the palette and type scale, pill buttons and sentence case; App/TestCall/ScorePane.swift:233 draws system fonts and colours (lines 280–281), uppercase column headers (line 251) and a system Done button — user: 2026-11-14
<!-- design-language:end -->

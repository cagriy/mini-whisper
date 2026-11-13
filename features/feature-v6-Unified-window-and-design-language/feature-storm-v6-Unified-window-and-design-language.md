# Unified window and design language — Brainstorm v6

**Status:** Draft
**Date:** 2026-11-13

## 1. Summary

Mini Whisper's UI is six separate fixed-size windows in stock system styling, reached one at a time from the menu-bar menu, and its meeting summaries are four fixed sections set in two small columns. v6 gives the app one resizable main window — a sidebar with Meetings, Dictations and Settings, with meetings opening as pages inside it — a design language of its own modelled on the attached reference screenshots (warm dark surfaces, serif display titles, pill controls, a centred reading column), and topic-based summaries that read as a document. It is for the person who uses Mini Whisper daily for dictation and meetings. It comes now because meetings (v4) and test calls (v5) turned a menu-bar utility into an app with content worth browsing, and the window-per-task shell no longer fits.

## 2. Goals

- Meetings, dictation history and settings are all reachable inside one main window; the separate Meetings, History and Settings windows no longer exist.
- A meeting — choosing its mode, recording it, reading it afterwards — is a page of the main window, and a recording in progress can be returned to from anywhere in that window.
- Every window except the dictation overlay (main, Correction, Onboarding, About) follows one documented design language, in light and dark appearance.
- A newly written summary has sections named after the meeting's topics, nested bullets and a closing Next Steps, and is displayed as a single reading column with visible heading and nesting hierarchy.
- A finished meeting's summary can be regenerated and copied from its page.
- One search finds matches in both meetings and dictations.

## 3. Scope (in / out)

- **In scope:**
  - **Main window.** Resizable, opened from the menu bar. Sidebar destinations: Meetings (home; the day-grouped list), Dictations (today's History list with its paste, correct, copy and delete actions), Settings (the nine existing sections as a second level).
  - **Meeting pages.** The mode chooser including Test Call setup, the live meeting with its notes, script and score panes, and the finished meeting with summary, transcript and notes. One meeting on screen at a time. A recording indicator in the sidebar returns to the live meeting.
  - **Status-bar menu.** Stays. Its Meetings…, History… and Settings… rows open the main window at that destination; Start, Stop and Show Meeting act on the window's meeting page. Usage rows unchanged.
  - **Design language.** Defined, documented, in light and dark, applied to the main window, the Correction window, Onboarding and About.
  - **Summary format.** A new default prompt producing topic-based summaries; a renderer for headings, nested bullets, bold and paragraphs; existing four-section summaries still display. The new default reaches existing installs whose prompt is unmodified.
  - **Summary actions.** Regenerate summary and Copy summary on a finished meeting. Summary text is read-only.
  - **Global search.** One search across meetings and dictations.
- **Out of scope / deferred:**
  - Restyling the dictation overlay (card, caption, animation styles); it keeps the v3 visual system.
  - Editing summary text in place.
  - An Ask-anything chat over meetings. Agents keep the MCP server and CLI.
  - A calendar "Coming up" card and starting a meeting from a calendar event.
  - Folders for meetings.
  - Sharing, spaces, teams, accounts and plans; People and Companies pages; recipes.
  - Opening a meeting in a second window, and side-by-side reading.
  - Changing the app's shape: a Dock app that launches into its window, or a hotkey-summoned launcher panel.
  - Any release from `main` while v6 is in progress.

## 4. High-level technical direction

- Platform rules are unchanged: macOS 14 deployment target, arm64, Swift 6 with complete strict concurrency, bundle ID `com.ips.mini-whisper`.
- Native SwiftUI/AppKit only. Sparkle remains the one third-party runtime dependency; no UI, Markdown or font library is added, and `MiniWhisperCore` stays dependency-free.
- Mini Whisper stays a menu-bar app (`LSUIElement`): the Dock icon shows only while a window is open, as today.
- Non-UI logic the feature adds (summary parsing, search across stores, navigation state) lives in core modules or host-testable models, written test-first with Swift Testing.
- Behaviours that must survive the move into one window: pasting a dictation from history into the app that was frontmost before the window took focus; a recording continuing when the window is closed or navigated away from; Esc restoring a hotkey being captured; a meeting not being deletable while it is open; ⌘C/⌘V working in text fields.
- The summary is model output: links stay inert, and the renderer must cope with whatever Markdown an edited prompt produces, including the four-section summaries already on disk.
- `~/.config/mini-whisper/summary_prompt.txt` stays user-editable and is never silently overwritten once edited. A stored summary changes only through an explicit Regenerate.
- Regenerate goes through the existing summary pipeline and its cost accounting.
- The reference is a model for structure and feel, not a source: no reference branding, icons, names or copy.
- UI choices are settled on HTML mockups in `/feature-design`, checked in both appearances; the accepted language is recorded in `DESIGN.md`.
- App state lives in `config.json`, Sparkle's preferences being the one stated exception; anything the window remembers has to respect that rule.
- Delivery: no release is cut from `main` until v6 is complete, so intermediate commits may mix old and new UI. An urgent fix ships from a branch off the last release tag.

## 5. Alternatives considered

- **A window for content only** (Meetings and Dictations, or Meetings alone) with Settings kept as a separate restyled window — rejected because the aim is one window for the whole app.
- **The live meeting in its own window, and "Open in new window" for finished meetings** — rejected because one window is simpler to manage; side-by-side reading is deferred.
- **Keeping the four fixed summary sections, or adding fixed Decisions / Next Steps / Open questions closers after the topic sections** — rejected because the reference's topic-based document is the preferred format.
- **Changing the app's shape** to a Dock app or a hotkey-summoned launcher panel — rejected; Mini Whisper stays a menu-bar app with a normal window.

## 6. Risks

- **Scope under a release freeze.** The freeze lasts as long as the redesign does. Fixes and unrelated improvements wait or go out from a branch, and the release workflow commits the appcast to `main`, which a branch release has not been exercised against.
- **Regressions in accepted behaviour.** Six windows collapse into one; flows that depend on window focus and lifetime (paste from history, hide-while-recording, hotkey capture, delete-while-open) can break daily dictation and meeting use.
- **Format depends on the model.** Topic headings vary by meeting, long meetings produce long documents, and there is no guaranteed Decisions or Open questions list. Meeting-list excerpts that relied on the opening Summary paragraph lose their source.
- **Mixed formats in one library.** Installs with an edited prompt keep the old format until the default is restored, and existing meetings keep old summaries until regenerated, each at the usual summary cost.
- **Resemblance.** A language that tracks a commercial product too closely makes the app read as a clone; it needs its own palette, type and naming.
- **Two appearances on stock controls.** Light and dark double the palette and review work, and a custom language on macOS 14 SwiftUI can clash with system controls in the less-visited Settings panes.

## 7. Open questions for design

- The design language itself: palette in light and dark, type scale (including whether display titles are serif and whether system fonts suffice or a font is bundled), radii, spacing, and the canonical components. (user's reference: warm dark surfaces, serif titles, pill controls)
- Sidebar structure: order and grouping of destinations, how Settings' nine sections nest, where Start Meeting sits, what the recording indicator shows, back navigation, keyboard shortcuts.
- The finished-meeting page: summary as the page with transcript and notes one switch away, or summary above the transcript with notes beside it as today. (user's reference is summary-first in a single column, but they didn't commit)
- What a Meetings row shows now that summaries have no opening paragraph to excerpt. (the reference shows title, people and time)
- The wording of the new default prompt, and how it reaches an install whose `summary_prompt.txt` is unmodified without touching an edited one.
- The Markdown subset the renderer supports and what it does with anything outside it.
- Regenerate: confirmation, how the cost is shown, what remains if it fails or is declined, and whether it applies to test calls and truncated transcripts.
- Copy summary: what goes on the pasteboard (Markdown, rich text, or both).
- Global search: its entry point, how results are grouped and opened, and whether the per-list search fields on Meetings and Dictations stay.
- Window behaviour: default and minimum size, what is remembered between launches and where it is stored, what closing the window does during a recording, and how history paste finds its target app when the window stays open.
- Whether the Today and Month usage shown in the menu also appears in the window. (user not asked)
- How Correction, Onboarding and About adopt the language given their size and one-off use.

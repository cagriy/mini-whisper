# Beta Channel — Design v10

**Status:** Draft
**Date:** 2026-11-22

## 1. Summary

Mini Whisper updates through Sparkle from one feed, so every user gets every version. v10 adds an update channel: **Release** (the default) or **Beta**, chosen in Settings › General › Updates.

- **Release users** see only release versions.
- **Beta users** see release versions and betas.

The feed stays one `appcast.xml`. A beta item carries Sparkle's `<sparkle:channel>beta</sparkle:channel>`, and the app tells Sparkle which channels it allows. The release pipeline learns a beta version format (`0.9.0b1`), marks beta GitHub releases as prereleases and keeps betas out of Homebrew.

The rollout is fixed:

1. Ship 0.8.1 plus this feature as **0.8.2** to everyone.
2. Then ship the parked v9 speaker-naming work as **0.9.0b1**, to Beta users only.

## 2. Goals and non-goals

- **Goals:**
  - A user can opt into betas, and only opted-in users are offered one.
  - Release stays the default; nothing changes for a user who never touches the setting.
  - A beta is built, signed, notarised, published and documented by the same pipeline as a release, triggered by a beta tag.
  - Sparkle orders the versions correctly: 0.8.2 < 0.9.0b1 < 0.9.0b2 < 0.9.0.
  - 0.8.2 contains this feature and nothing from v9. 0.9.0b1 is 0.8.2 plus v9, offered to Beta users only.
- **Non-goals:**
  - **Downgrades.** A beta user who switches back to Release keeps the beta until a newer release ships. Sparkle never downgrades.
  - **Release candidates or other channels.** `b` is the only pre-release suffix.
  - **Betas through Homebrew.** The cask tracks releases only.
  - **A separate beta feed or a second `SUFeedURL`.**
  - **A hotfix process for 0.8.x after 0.9.0b1.** It would need a branch from `v0.8.2`, and is decided when needed.
  - **Treating a hand-installed beta as opted in.** Only the setting decides.

## 3. Requirements

1. **R1 Update channel row.** Settings › General › Updates shows, in order:
   1. "Automatically check for updates" (with the version line);
   2. "Update channel", with a segmented pill offering Release and Beta, Release selected by default;
   3. "Check for an update now".
2. **R2 Storage.** The channel lives in `config.json` under `update_channel`, with the values `"release"` or `"beta"`.
   - An absent key reads as Release.
   - An unrecognised value reads as Release and is written back unchanged on the next save, as `theme` does.
   - Sparkle's own preferences are not touched.
3. **R3 Beta needs confirmation.** Choosing Beta while on Release opens the in-window Dialog:
   - Title: "Switch to beta versions?"
   - Message: "Beta versions arrive before each release and may have bugs. You can switch back to Release at any time; an installed beta stays until the next release."
   - Buttons: Cancel, and primary "Switch to Beta".

   Switch to Beta stores `"beta"`. Cancel stores nothing and the pill shows Release.
4. **R4 Release is immediate.** Choosing Release while on Beta stores `"release"` at once, with no dialog.
5. **R5 Channel filter.** Sparkle's allowed channels follow the stored channel:
   - Release allows the default channel only (the empty set).
   - Beta allows `{"beta"}`; the default channel is always included.

   This applies to scheduled checks and to Check Now.
6. **R6 Change takes effect.** When the stored channel changes after launch, the updater calls `resetUpdateCycleAfterShortDelay()`, so a newly allowed beta is found without waiting for the daily check. This applies in either direction, whether the change came from Settings or from `config.json` edited elsewhere. Loading the config at launch does not reset the cycle.
7. **R7 No downgrade.** A beta user who switches to Release keeps the installed beta. The next default-channel item newer than it, such as 0.9.0 after 0.9.0b2, is offered as usual. The row description states this.
8. **R8 Beta build marker.** When the running version is a beta (matches `^\d+\.\d+\.\d+b\d+$`), the version line reads "Version 0.9.0b1", then a Plain Chip "Beta", then the existing "Checked once a day; an update installs only after you approve it." Release builds are unchanged.
9. **R9 Version format.**
   - A release is `X.Y.Z`. A beta is `X.Y.ZbN` (N ≥ 1).
   - The same string is used for the tag (`vX.Y.ZbN`), `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` (so `CFBundleShortVersionString` and `CFBundleVersion`), the DMG name, the GitHub release, the appcast item and the CHANGELOG heading.
   - A tag in any other form (for example `v0.9.0-beta.1`) fails the release build before anything is published.
10. **R10 Appcast items.** `scripts/appcast.py`:
    - accepts `X.Y.Z` and `X.Y.ZbN`;
    - writes `<sparkle:channel>beta</sparkle:channel>` into a beta item and no channel element into a release item;
    - prints a version's channel (`release` or `beta`) with `--print-channel <version>` and exits non-zero for any other form.
11. **R11 CI per channel.**

    | | Release tag | Beta tag |
    |---|---|---|
    | GitHub release | not a prerelease | prerelease |
    | Homebrew cask | updated | not touched |
    | Appcast item | default channel | beta channel |

    Build, signing, notarisation, stapling, `sign_update` and release notes are identical for both.
12. **R12 Release notes.**
    - Each beta has its own CHANGELOG section (`## [0.9.0b1] - YYYY-MM-DD`) listing what changed since the previous beta, or since the last release for the first beta.
    - The final release's section (`## [0.9.0]`) lists everything since the previous release, so Release users get complete notes.
13. **R13 Rollout order.**
    1. 0.8.2 is built from `main` at 0.8.1 plus this feature only.
    2. The v9 commits, parked on branch `v9-naming`, are then rebased onto `main`.
    3. 0.9.0b1 is tagged from that rebased `main`.
14. **R14 Logging.** A channel change logs one line, `Update channel: <release|beta>`, through `Log.ui`. Nothing else is logged.
15. **R15 Documentation.**
    - `CHANGELOG.md` `[Unreleased]` gains the 0.8.2 entry for the channel setting.
    - CLAUDE.md's *Releases and auto-updates* section documents the beta tag format, the per-channel CI behaviour, the CHANGELOG convention and how to pull a bad beta.

## 4. Background and context

- **No storm.** This feature was designed cold, after an exploratory exchange in this conversation.
- **Updater client.** `App/AppUpdater.swift`:
  - `AppUpdater.start()` (`:12`) creates `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, …)` (`:15`). There is no updater delegate today.
  - `SparkleUpdateChecking` (`:59`) adapts it to the Settings seam `UpdateChecking` (`App/Settings/SettingsModel.swift:22`).
  - `AppDelegate` starts the updater at launch (`App/AppDelegate.swift:58`).
- **Feed.** `SUFeedURL` is `https://raw.githubusercontent.com/cagriy/mini-whisper/main/appcast.xml` (`App/Info.plist:40`). Sparkle has been 2.9.6 since it was added (`92f9569`), so every shipped client understands `<sparkle:channel>` and ignores items in channels it does not allow (`SPUUpdaterDelegate.h:95–113`).
- **Version comparison.** Sparkle's `SUStandardVersionComparator` stops splitting a version at the first `-` (`SUStandardVersionComparator.m`, `splitVersionString`). So `0.9.0-beta.1`, `0.9.0-beta.2` and `0.9.0` would all compare equal.
  - `0.9.0b1` splits into `0 . 9 . 0 b 1`.
  - When one version has an extra string part, the shorter one is newer, so `0.9.0 > 0.9.0b2 > 0.9.0b1 > 0.8.2`.
  - Sparkle compares `CFBundleVersion`, which tracks `MARKETING_VERSION` (`project.yml:80`, `:83`).
- **Settings.**
  - The Updates card is `App/Settings/GeneralSection.swift:63`. It has two rows today: automatic checks with the version line, then Check Now.
  - `SettingsModel` writes config through `write(_:)` (`SettingsModel.swift:825`), as `setTheme` does (`:672`).
  - In-window confirmations are `DSDialog` branches in `App/Main/MainView.swift` (`:77`, People's pending confirmation; `:85`, Clear History).
  - `SegmentedPill` (`App/Design/SegmentedPill.swift:4`) already carries Theme.
  - `Chip` (`App/Design/Chip.swift:5`) defaults to its `.plain` kind (`init(_ text:, _ kind: = .plain, …)`).
  - `ConfigStore.update` yields every saved config on `changes` (`Packages/MiniWhisperCore/Sources/MWConfig/ConfigStore.swift:64`, `:72`), so a write from Settings reaches `AppDelegate.apply`. An out-of-process edit only marks the store's cache stale; it reaches `changes`, and so `apply`, with the next in-app `update`.
  - `MainView` clears its meeting dialog when the destination changes (`App/Main/MainView.swift:23`).
- **Config.** `Config.theme` keeps an unrecognised raw value for round-trip (`Packages/MiniWhisperCore/Sources/MWConfig/Config.swift:113`, decode `:293`, encode `:342`). This is the pattern for `update_channel`.
  - `Key.all` (`:240`) keeps known keys out of `extra`.
  - `AppDelegate.apply(_:)` (`App/AppDelegate.swift:512`) is the single config-change consumer, run at start (`:105`) and on every change.
- **Release pipeline.** `.github/workflows/build.yml`:
  - "Resolve version" (`:66`) takes the version from the tag.
  - "Create GitHub Release" already sets `prerelease` for `-beta`/`-rc` tags (`:287`). That never matches the `b` format.
  - "Update Homebrew tap" (`:289`) and "Publish appcast" (`:310`) run for every tag, so a beta tag today would reach every Sparkle user and every Homebrew user.
- **Appcast script.** `scripts/appcast.py` rejects any version but `X.Y.Z` (`main`) and writes no channel element (`build_item`). Its tests are in `scripts/tests/test_appcast.py`.
- **Repository state.** `main` was reset to `origin/main` (v0.8.1 plus its appcast commit) after the 32 unpushed v9 commits were parked on branch `v9-naming`, at the user's request in this design. `DESIGN.md` on `main` was reconciled to the same region hash v9 recorded (`67ecf8d`).

## 5. Design

### Architecture / components

| Component | Where | Responsibility | Interface |
|---|---|---|---|
| `UpdateChannel` | `MWConfig/Config.swift` | The stored channel | `public enum UpdateChannel: String, Sendable, CaseIterable { case release, beta }` |
| `Config.updateChannel` | `MWConfig/Config.swift` | Reads and writes `update_channel` | `public var updateChannel: UpdateChannel = .release`; keeps `unrecognisedUpdateChannel: String?` like `theme` |
| `UpdateChannelPolicy` | `App/UpdateChannelPolicy.swift` (new) | Pure rules, no Sparkle import | `static func sparkleChannels(for: UpdateChannel) -> Set<String>`; `static func isBeta(version: String) -> Bool`; `struct Tracker { mutating func apply(_ channel: UpdateChannel) -> Bool }`, which is false on the first apply and true only when the channel differs from the last applied one |
| `AppUpdater` | `App/AppUpdater.swift` | Sparkle wiring | `static var channel: UpdateChannel` (default `.release`); `static func channelChanged()`, which calls `controller?.updater.resetUpdateCycleAfterShortDelay()`; `start()` passes the delegate below |
| `UpdaterChannelDelegate` | `App/AppUpdater.swift` (private) | Sparkle's channel filter | `NSObject, SPUUpdaterDelegate`; `func allowedChannels(for updater: SPUUpdater) -> Set<String>` returns `UpdateChannelPolicy.sparkleChannels(for: AppUpdater.channel)` |
| `AppDelegate.apply(_:)` | `App/AppDelegate.swift` | Applies a loaded or changed config | Sets `AppUpdater.channel`. When `channelTracker.apply(config.updateChannel)` is true, logs and calls `AppUpdater.channelChanged()` |
| `SettingsModel` | `App/Settings/SettingsModel.swift` | Settings state | `var updateChannel: UpdateChannel` (from `config`); `private(set) var confirmingBetaChannel = false`; `func chooseUpdateChannel(_:) async`; `func confirmBetaChannel() async`; `func cancelBetaChannel()`; `var isBetaBuild: Bool` |
| Updates card | `App/Settings/GeneralSection.swift` | The surface | Row order and controls per R1 and R8 |
| Beta dialog | `App/Main/MainView.swift` | The confirmation | A `DSDialog` branch on `model.settings.confirmingBetaChannel` |
| `appcast.py` | `scripts/appcast.py` | Feed items | Version pattern `^\d+\.\d+\.\d+(b[1-9]\d*)?$` (R9: N ≥ 1); `channel_of(version) -> str`; beta channel element in `build_item`; `--print-channel` |
| `build.yml` | `.github/workflows/build.yml` | Release pipeline | Channel output from "Resolve version"; `prerelease` and the Homebrew gate on it |

Why the split:

- The channel rules and the change-detection rule are pure, so they are unit-tested in `AppTests` without Sparkle.
- `AppUpdater` stays the thin Sparkle wiring it is today.
- `AppDelegate.apply` remains the single path every config change takes, so a channel edited outside Settings behaves exactly like one changed in Settings.

### Data model

- **`config.json`:** `update_channel`, a string, `"release"` by default.
  - It is written on every save, like `theme`.
  - It is decoded leniently: an absent key gives `.release`. An unknown string gives `.release` while the raw value is kept and re-encoded.
  - A value of the wrong JSON type throws, as every other key does.
  - The key is added to `Key.all`.
- **Appcast items:** an optional `<sparkle:channel>beta</sparkle:channel>` child, present only on beta items.
- **No migration.** An absent key is Release, which is today's behaviour.

### Interfaces

**Settings › General › Updates** — accepted mockup: [Segmented update channel](./mockups/mockup-v10-segmented.html#segmented) ([artifact](https://claude.ai/artifact/S7tb8eASSvUkE6yc6qymkJ#segmented)).

- **Row 1, "Automatically check for updates"**, unchanged. Its description starts "Version <CFBundleShortVersionString>".
  - On a beta build, a `Chip("Beta")` (Plain kind) follows the version.
  - Then the existing sentence: "Checked once a day; an update installs only after you approve it."
- **Row 2, "Update channel"**, with a `SegmentedPill` of `(.release, "Release")` and `(.beta, "Beta")`. Description: "Release gets tested versions. Beta gets new versions first, and they may have bugs. Switching back to Release keeps an installed beta until the next release."
  - The pill's binding reads `model.updateChannel`.
  - Its setter calls `model.chooseUpdateChannel(_:)`. The pill shows the stored value, so a pending confirmation leaves it on Release.
- **Row 3, "Check for an update now"**, unchanged.
- **Beta dialog:** `DSDialog(title: "Switch to beta versions?", message: "Beta versions arrive before each release and may have bugs. You can switch back to Release at any time; an installed beta stays until the next release.", confirmTitle: "Switch to Beta", confirm: { Task { await model.settings.confirmBetaChannel() } }, cancel: model.settings.cancelBetaChannel)`.
  - It is shown from `MainView`'s dialog chain while `model.settings.confirmingBetaChannel` is true.
  - The scrim blocks the sidebar. Navigation that still happens (a menu or hotkey) cancels it: `MainView`'s existing `.onChange(of: model.navigation.destination)` also calls `model.settings.cancelBetaChannel()`.

**`SettingsModel` behaviour:**

- `chooseUpdateChannel(.beta)` while `updateChannel == .release`: sets `confirmingBetaChannel = true` and writes nothing.
- `chooseUpdateChannel(.release)`: writes `updateChannel = .release` at once.
- Choosing the current value: does nothing.
- `confirmBetaChannel()`: clears the flag, then writes `.beta`.
- `cancelBetaChannel()`: clears the flag.
- `isBetaBuild`: `UpdateChannelPolicy.isBeta(version: appVersion)`.
- `appVersion`: becomes injectable through `SettingsModel.Dependencies.appVersion: String`, defaulting to the bundle's `CFBundleShortVersionString`, so tests set it. Its construction sites (`AppDelegate`, and the `SettingsModelTests` and `MainWindowModelTests` dependencies) compile unchanged through the default.

**`scripts/appcast.py` CLI:**

- `--print-channel <version>` prints `release` or `beta` and exits 0. It exits 2 with argparse's usage error for any other form, and needs no other argument.
- The existing insert mode accepts beta versions and derives the channel itself.

**`build.yml`:**

- **"Resolve version":** after computing `version`, run `channel=$(python3 scripts/appcast.py --print-channel "$version")` and write `channel=$channel` to `$GITHUB_OUTPUT`. A malformed tag fails here.
- **"Create GitHub Release":** `prerelease: ${{ steps.version.outputs.channel == 'beta' }}`.
- **"Update Homebrew tap":** its `if:` gains `&& steps.version.outputs.channel == 'release'`.
- **"Publish appcast":** unchanged. The script tags the item.

### Design language

- **References.** The surface follows `../../DESIGN.md` (region `67ecf8d`) and its specimen ([design/specimen.html](../../design/specimen.html), [artifact](https://claude.ai/artifact/WwtdFm3B6EEUxCKMZ3b4PB)).
- **Reused parts:** Settings card with hairline rows, `SettingRow`, `SegmentedPill`, the `.ds` switch, the small pill button, `DSDialog`, and `Chip` (Plain).
- **No language deltas:** the accepted mockup adds no token, variant or rule.
- **No drift** touches this surface.

### Control flow

**Launch:**

1. `AppUpdater.start()` runs at `applicationDidFinishLaunching`. `AppUpdater.channel` is `.release`.
2. `startNormal` loads the config and calls `apply(config)`. That sets `AppUpdater.channel`, and `channelTracker.apply` returns false (first apply), so there is no cycle reset.
3. Sparkle consults `allowedChannels(for:)` while it filters the downloaded appcast. That is after a network fetch, by which point `startNormal` has applied the local config. The first-run onboarding path never applied a config, so it stays Release, which is the right value for a new user.

**Opt in:**

1. The user taps Beta, and `chooseUpdateChannel(.beta)` sets `confirmingBetaChannel`.
2. `MainView` shows the Dialog.
3. Switch to Beta calls `confirmBetaChannel()`, which writes `update_channel: "beta"`.
4. `ConfigStore.changes` delivers the change to `AppDelegate.apply`, and the tracker reports a change.
5. `apply` logs "Update channel: beta" and calls `AppUpdater.channelChanged()`, which runs `resetUpdateCycleAfterShortDelay()`.
6. Sparkle checks in the background. When the feed has a beta newer than the running version, its standard update window appears; otherwise nothing shows.

**Opt out:** `chooseUpdateChannel(.release)` writes `"release"`. Then `apply` logs and resets the cycle, and Sparkle allows only the default channel from then on. An installed beta stays.

**Check Now:** unchanged. It uses the same delegate, so it honours the channel.

**Release a beta** (operator):

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to `X.Y.ZbN`.
2. Add a `## [X.Y.ZbN] - date` CHANGELOG section.
3. Commit `Release vX.Y.ZbN` and push the tag `vX.Y.ZbN`.
4. CI then resolves `channel=beta`; builds, signs, notarises and staples; makes a prerelease GitHub release; skips Homebrew; and commits an appcast item tagged `beta` to `main`.

**Release a release:** as today. `channel=release` gives a normal GitHub release, a Homebrew bump and a default-channel item.

### Failure and edge cases

| Case | Behaviour |
|---|---|
| `update_channel` absent | Release |
| `update_channel` unknown string (e.g. a newer build's `"nightly"`) | Read as Release; the raw value is preserved on save |
| `update_channel` of the wrong type | `Config` decoding throws, as for any other key (existing corrupt-config handling) |
| Config write fails on confirm or opt out | `write(_:)` logs `Could not save settings` and reloads, as for every other setting. The pill shows the stored value and the channel does not change |
| Navigation away from Settings while the dialog is open (menu or hotkey) | Dialog cancelled through `MainView`'s destination change; nothing written |
| Beta user switches to Release | Stays on the beta. Offered the next release newer than it; an older 0.8.x hotfix is not offered |
| Release user on 0.8.1 (no delegate) when a beta item is in the feed | Sparkle 2.9.6 allows only the default channel and ignores the beta item |
| Hand-installed beta with Release selected | Treated as Release: offered the next newer release, never another beta |
| Tag `v0.9.0-beta.1` or other malformed form | `--print-channel` fails in "Resolve version"; the build stops before signing or publishing |
| Bad beta published | Remove its `<item>` from `appcast.xml` on `main`, or ship `bN+1`. Users already on it stay until the next beta or release |
| Two betas of one version (b1, b2) | `b2 > b1` by Sparkle's numeric comparison |
| Final release after betas | `0.9.0 > 0.9.0bN`, so beta users get it, and Release users on 0.8.2 get it |

### Security

- **No new trust boundary.** Beta builds go through the same signing (Developer ID), notarisation, stapling and EdDSA `sign_update` as releases, and Sparkle verifies the signature exactly as for releases.
- **Fixed channel values.** The channel is a closed enum; `allowedChannels` returns only `[]` or `["beta"]`.
- **The feed is unchanged:** fetched over HTTPS from the same URL, and signed per item.
- **No new secrets** or keys. The Homebrew token is simply not used for betas.
- **Logging** carries only the channel name (R14).

### Performance

Not applicable in practice. The channel is one enum read per update check, plus one cycle reset per user change. `appcast.py` adds one element per beta item.

### Observability

- **Channel changes:** `Log.ui.info("Update channel: \(channel.rawValue)")` on each change after launch, following the existing `Overlay style:` line.
- **CI:** the step summary shows the resolved channel through the "Resolve version" output. A malformed tag fails that step visibly.

### Compatibility / migration

- **`config.json`:** additive key, no migration. Older builds ignore it; it stays under their `extra` passthrough.
- **Appcast:**
  - Older clients ignore beta items: every shipped Sparkle client is 2.9.6.
  - `appcast.py` still produces byte-identical release items.
- **Homebrew:** the cask keeps `auto_updates true`. A Homebrew user who opts into Beta is updated in place by Sparkle, and `brew upgrade` leaves the app alone, as today.
- **Python legacy app:** frozen, and does not read this key.

### Testing strategy

- **`ConfigCodingTests`** (MWConfig, sibling cases for `theme`):
  - absent key → `.release`;
  - `"beta"` round-trips;
  - an unknown string reads `.release` and re-encodes unchanged;
  - `Config().encoded()` writes `update_channel: "release"`;
  - the key never lands in `extra`.
- **`UpdateChannelPolicyTests`** (new, `AppTests`):
  - `sparkleChannels(.release) == []` and `sparkleChannels(.beta) == ["beta"]`;
  - `isBeta` is true for `0.9.0b1` and `1.10.2b12`, and false for `0.8.2`, `0.9.0-beta.1`, `0.9.0b`, `0.9.0rc1` and `""`;
  - `Tracker`: the first apply is false, the same value again is false, a different value is true, and back again is true.
- **`SettingsModelTests`** (with `FakeUpdater` and the harness's `ConfigStore` in a temp directory):
  - choosing Beta sets `confirmingBetaChannel` and writes nothing;
  - confirm writes `"beta"` and clears the flag;
  - cancel writes nothing;
  - choosing Release writes at once with no flag;
  - choosing the current value is a no-op;
  - `isBetaBuild` follows an injected `appVersion`;
  - `cancelBetaChannel()` after `chooseUpdateChannel(.beta)` leaves `updateChannel == .release`.
- **`scripts/tests/test_appcast.py`:**
  - a beta version inserts with `<sparkle:channel>beta</sparkle:channel>`;
  - a release version has no channel element;
  - `--print-channel` prints `release` and `beta`, and exits 2 for `0.9.0-beta.1`, `v0.9.0` and `0.9`;
  - an existing release item is byte-identical to today's output.
- **Sparkle wiring** (manual, before tagging 0.8.2), using CLAUDE.md's "Test an update without publishing" procedure. Serve a doctored appcast with a default `0.8.3` item and a beta `0.9.0b1` item, both pointing at a locally signed DMG. Then check:
  1. On Release, Check Now offers 0.8.3 only.
  2. After switching to Beta and confirming, Sparkle offers 0.9.0b1 shortly after (cycle reset).
  3. Back on Release, 0.9.0b1 is no longer offered.
  4. Clean up the `defaults` overrides.
- **CI**, verified on the real tags:
  - `v0.8.2` makes a normal release, a Homebrew bump and an item with no channel element.
  - `v0.9.0b1` makes a prerelease, no tap commit and a `beta`-channel item.
  - Check with `gh release view`, the tap's log and `appcast.xml`, plus CLAUDE.md's stapler, `sign_update` and `spctl` checks.

## 6. Alternatives considered

- **Hyphenated beta versions (`0.9.0-beta.1`).** Rejected: Sparkle stops comparing at the dash, so every beta and the final release would compare equal.
- **A separate display string ("0.9.0 Beta 1") with `CFBundleVersion` `0.9.0b1`.** Rejected by the user in favour of one string everywhere, which keeps the pipeline deriving everything from the tag.
- **A second feed (`appcast-beta.xml`) with a runtime `SUFeedURL` switch.** Rejected: Sparkle 2 channels do this within one signed feed, and every shipped client already honours them.
- **Release branch `release/0.8` from `v0.8.1` for 0.8.2.** Rejected by the user in favour of parking v9 on a branch and building on `main`. History stays linear, and the CI's appcast commit lands on the same `main`.
- **A Beta switch** ([switch](./mockups/mockup-v10-channel-control.html#switch), [artifact](https://claude.ai/artifact/L5cmj5wgqJYFo6b1jbB6qA#switch)). Not chosen: "Release" never appears as a word, and the channel reads as an on/off feature.
- **Radio rows** ([radio-rows](./mockups/mockup-v10-channel-control.html#radio-rows), [artifact](https://claude.ai/artifact/L5cmj5wgqJYFo6b1jbB6qA#radio-rows)). Not chosen: two extra lines in a short card.
- **No confirmation for Beta.** Rejected by the user; switching to Beta asks first.
- **A visible "Check Now" on switching, or waiting for the next daily check.** Rejected for Sparkle's own `resetUpdateCycleAfterShortDelay`, which checks in the background, shows a window only when a beta exists, and cancels on a quick switch back.
- **A reinstall-the-release link for users leaving Beta.** Rejected: the description explains it, and a link to the latest DMG adds a control and a URL to keep current.
- **Beta builds defaulting to the Beta channel.** Rejected by the user: only the setting decides.

## 7. Risks and issues

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| A non-numeric `CFBundleVersion` (`0.9.0b1`) trips a tool | Low / high: a failed beta release | Apple validates the numeric form only for App Store submission; Developer ID signing, notarisation and Gatekeeper do not check it. Before tagging 0.9.0b1, build locally with `MARKETING_VERSION=0.9.0b1 CURRENT_PROJECT_VERSION=0.9.0b1` and check the built `Info.plist`. The first beta tag is watched through every CI step; a failure stops before publishing |
| A beta tag reaches Release users or Homebrew through a pipeline mistake | Low / high | Channel derived in one place (`--print-channel`) with tests. The Homebrew step is gated, the appcast item is tagged by the script, and the `v0.9.0b1` run is checked against R11 before announcing |
| Rebasing `v9-naming` onto 0.8.2 conflicts | Certain / low | Expected conflicts are adjacent key additions in `Config.swift` (`Key` constants, `Key.all`, decode, encode), `SettingsModel.swift`, `CHANGELOG.md` and `project.yml`. Resolve, then run the full core and app suites before tagging 0.9.0b1 |
| v9's recorded commit SHAs (tracker, plan) go stale after the rebase | Certain / low | The v9 tracker's stage list is documentation; refresh its SHAs in the docs commit after the rebase |
| A Beta user is stuck on a bad beta | Medium / medium | Pull the item from `appcast.xml` and ship `bN+1` quickly; the dialog and row copy set expectations |
| A Homebrew user who opts into Beta sees the brew version lag | Low / low | Expected with `auto_updates true`; Sparkle owns the update |
| Settings opened during onboarding shows Release before the config loads | Low / none | Onboarding has no config yet, so Release is the true value |

## 8. Open questions

None — all decisions closed.

## 9. Rollout plan

1. **Done in design:** the 32 unpushed v9 commits are parked on `v9-naming`, and `main` is reset to `origin/main` (v0.8.1 plus its appcast commit).
2. **Build v10 on `main`** via `/feature-plan` and `/feature-implement`. That covers app, config, script, CI, CHANGELOG `[Unreleased]` and CLAUDE.md.
3. **Verify locally:** the full core and app suites, the appcast pytest, and the manual Sparkle channel test (Testing strategy).
4. **Release 0.8.2.** Set the version to `0.8.2`, move `[Unreleased]` to `## [0.8.2]`, commit `Release v0.8.2` and push `main` and the tag. Verify R11's release column. Pull `main` afterwards (CI's appcast commit).
5. **Rebase v9:**
   1. `git rebase main v9-naming`, resolving the conflicts named in §7;
   2. run the full suites;
   3. fast-forward `main` to the rebased branch;
   4. refresh the v9 tracker's SHAs in a docs commit.
6. **Release 0.9.0b1:**
   1. Set both versions to `0.9.0b1`.
   2. Move v9's `[Unreleased]` entries to `## [0.9.0b1]`.
   3. Commit `Release v0.9.0b1` and push the tag.
   4. Verify R11's beta column, then confirm on a Beta-channel machine that the update is offered, and on a Release machine that it is not.
7. **Later betas and 0.9.0:**
   - Each beta follows step 6 with its own CHANGELOG section (R12).
   - 0.9.0 is a normal release whose section consolidates every beta's entries.
8. **Rollback:**
   - **Bad beta:** remove its appcast item, or ship the next beta.
   - **Channel feature:** `update_channel` is additive, and a build without the delegate simply ignores beta items.
9. **Communication:**
   - **0.8.2 CHANGELOG:** "Settings → General → Updates: choose Release or Beta versions."
   - **Each beta:** a prerelease on GitHub with its notes.

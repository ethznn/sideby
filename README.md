# Sideby

English | [한국어](README.ko.md)

**Back to your work, in one action.**

Keep code and reference material together as **Checkout**, then switch to **PR review** when a review comes in. Sideby groups the desktops on your Mac and external displays into named workspaces, so you can return without switching every screen yourself. It also works with a single display.

[Sideby 0.12.0](docs/releases/0.12.0.md) adds desktop names, a quick matrix you open by holding a shortcut, and a menu that stays with you while switching.

<p align="center">
  <a href="https://github.com/ethznn/sideby/releases/download/v0.12.0/sideby-promo-v2-21s-en.mp4">
    <img src="./docs/images/sideby-brand-film-en.gif" width="720" alt="Animated Sideby preview: Where was I? Hold the shortcut, choose a workspace, and return all three displays to the work you left." />
  </a>
</p>

**[▶ Watch the film · 21 seconds · Sound on](https://github.com/ethznn/sideby/releases/download/v0.12.0/sideby-promo-v2-21s-en.mp4)** · [Still image](docs/images/sideby-brand-film-en.png)

**21-second brand film — Interrupted. Never lost.:** [English MP4](https://github.com/ethznn/sideby/releases/download/v0.12.0/sideby-promo-v2-21s-en.mp4) · [한국어 MP4](https://github.com/ethznn/sideby/releases/download/v0.12.0/sideby-promo-v2-21s-ko.mp4) · 9:16 for Shorts and Reels: [English](https://github.com/ethznn/sideby/releases/download/v0.12.0/sideby-promo-v2-21s-vertical-en.mp4) · [한국어](https://github.com/ethznn/sideby/releases/download/v0.12.0/sideby-promo-v2-21s-vertical-ko.mp4). From “Where was I?” to three displays returning to the work you left at once. Sideby screens are captured from the actual app with sample data; the desktops on the displays are illustrations. Original score.

[Download Sideby](https://github.com/ethznn/sideby/releases) · macOS 14 or later · English and Korean

<details>
<summary>See the 10-second switching demo</summary>

<p align="center">
  <img src="./docs/images/sideby-readme-loop-en.gif" width="720" alt="Illustrated demo: a MacBook and two external displays switch from Checkout to PR review and back with Option-Shift-Tab." />
</p>

Checkout → PR review → Checkout, using the same `⌥⇧Tab` shortcut. The MacBook, two external displays and their contents are fictional; transitions illustrate the workflow, not measured hardware performance. [View the still image](docs/images/sideby-readme-loop-en.png).

</details>

## What you can do

- **Switch a whole task.** Choose a workspace’s **Go** button to move its assigned desktops on the selected displays.
- **Return with the same shortcut.** Press `⌥⇧Tab` to return to the previous workspace. Press it again to switch back.
- **Arrange work from the menu.** Open Sideby in the menu bar to see the matrix immediately. Rename workspaces, change assignments, or rebuild from the current desktop order there. The matrix stays open as you switch.

<p align="center">
  <img src="./docs/images/sideby-context-capture-en.png" width="680" alt="Sideby’s dark menu with display selection and a matrix: Checkout.swift and Checkout API assigned to Checkout; PR #42 and its preview assigned to PR review." />
</p>

*Actual Sideby interface rendered with sample workspaces and display data.*

## Make the matrix yours

Columns are workspaces. Rows are displays. Each cell shows that display’s assigned desktop, including a content label when one is available.

| Action | Result |
| --- | --- |
| Edit the name at the top of a column | Rename that workspace. Use **Go** below it to switch. |
| Drag a cell to an empty cell in the same display row | Move the desktop assignment. |
| Drag a cell onto an occupied cell in the same row | Swap the two assignments. |
| Hold Option and drag to an empty cell in the same row | Keep the original assignment and use that desktop in another workspace too. |
| Drag a display’s name or up/down icon | Reorder display rows. |
| Open a cell’s menu | Assign a desktop without dragging, or give that desktop a name. The same desktop shares its name across workspaces. |

Desktop changes are detected automatically. To start over, choose **Rebuild from current desktops…** at the top of the menu or Workspaces & Displays settings. Sideby confirms how many workspaces it will create, then replaces the selected displays’ names and assignments in current desktop order. This also replaces custom swaps and shared-desktop assignments. Other displays’ assignments are kept separately. Immediately after rebuilding, **Undo** in the completion message restores the previous configuration when its desktops are still available. The menu has no permanent restore button.

New names use available app/window content from each display’s desktops, including desktops you are not currently viewing. These are suggestions, not native macOS Space names; Sideby falls back to a desktop number when metadata is unavailable. Workspace names you edit are preserved during routine updates; an explicit rebuild creates fresh workspace names. Custom **desktop names** are separate: they stay attached to the same desktop through reordering, restarting and rebuilding. Choose **Use automatic name** in its cell menu to return to content suggestions. These names appear only in Sideby, not Mission Control.

Display connection changes are checked automatically. Disconnected display choices and assignments are retained for reconnection; you can continue working with the selected displays that are currently available.

<details>
<summary>See the full Workspaces & Displays settings</summary>

The same matrix is available in **All settings → Workspaces & Displays**. Input, Permissions, and General settings have their own panes.

<p align="center">
  <img src="./docs/images/sideby-settings-workspaces-en.png" width="720" alt="Light Workspaces & Displays settings with a display diagram, rebuild action, and the same editable workspace matrix." />
</p>

</details>

## Your first round trip

1. **Install and allow access.** Download the DMG from [GitHub Releases](https://github.com/ethznn/sideby/releases), move Sideby to Applications, and open it. Follow the guide for Accessibility and Screen Switching access.
2. **Choose your displays.** Click the display diagram or checkboxes. One display is enough; a round trip needs two different desktop arrangements. The guide points you to Mission Control if more desktops are needed.
3. **Name your workspaces.** Read the desktop arrangement, name two workspaces, and check which content belongs to each display.
4. **Go there, then come back.** Follow the guide’s buttons to visit the other workspace and return. Finish with **Open Sideby menu**. You can use shortcuts or gestures afterward.

You can continue the guide later. Its completion is based on a successful round trip; a skipped step or a failed move does not count.

<details>
<summary>See workspace preparation and the completed round trip</summary>

<p align="center">
  <img src="./docs/images/sideby-onboarding-workspaces-en.png" width="640" alt="Onboarding workspace preparation with editable Checkout and PR review names and content labels for both displays." />
</p>

<p align="center">
  <img src="./docs/images/sideby-onboarding-roundtrip-en.png" width="640" alt="Completed round-trip guide with the Option-Shift-Tab hint and Open Sideby menu button." />
</p>

These are production views rendered with sample data, including a simulated completed guide.

</details>

## Shortcuts and gestures

| Input | Action |
| --- | --- |
| Hold `⌥⇧Space` | Show the quick matrix; click a workspace to switch. Release the keys or press Escape to close it. |
| `⌥⇧Tab` | Return to the previous workspace; repeat to alternate between the last two. |
| `⌥⇧1` … `⌥⇧9`, `⌥⇧0` | Go to workspace positions 1–10. |
| `⌥⇧<` / `⌥⇧>` | Previous / next workspace. |
| Option + Shift + horizontal swipe | Switch with the default gesture. |

For numbered, previous/next and return shortcuts, release Option and Shift to execute the move. For the held matrix, keep the shortcut pressed while clicking a workspace. Change or disable its shortcut in **Settings → Input**, where you can also configure gestures.

## When your setup changes

Sideby reads the live desktop layout and checks requested moves. Routine additions, removals, and reordered desktops are reflected automatically while the matrix is open and checked before switching. Saved workspaces follow the same surviving desktops across an app restart; reordering desktops does not reset custom workspace assignments. Workspaces that only use disconnected displays are hidden from the everyday matrix and do not take a shortcut position.

If an older version’s assignments already point at the wrong desktops, use **Rebuild from current desktops…** once to start again in the current order. Older versions did not save enough identity information to recover a desktop’s previous position after the fact.

If a move is incomplete, Sideby can retry the displays that have not reached the destination. If a required desktop is missing or its layout cannot be read, check the assignment in the menu, or rebuild to start over. The previous setup stays saved if a desktop needed for restoration is missing.

Workspaces refer to existing macOS desktops. Sideby does not reopen documents or restore window contents and positions. Deleting a workspace removes its Sideby assignments, never the macOS desktops themselves.

## Privacy and platform notes

Sideby uses Accessibility for its configured global gesture and, when available, app/window title suggestions. Screen Switching access allows it to send the requested desktop-switch commands. Some command paths also need System Events Automation. Switching and desktop discovery do not request Screen Recording permission.

Global keyboard registrations cover `Option + Shift + number / < / > / Tab` and the configurable held-matrix shortcut (default `⌥⇧Space`). Sideby checks release of the held shortcut to dismiss its matrix; it does not save typed input. Runtime desktop discovery uses read-only macOS layout queries. Numeric runtime Space IDs, window IDs, raw input events, and screenshots are not saved. Minimal desktop identity bookmarks are stored locally so assignments can follow the same desktops after a restart.

Workspace names and assignments, custom desktop names, the previous setup saved before a rebuild, display choices and row order, remembered display names, input preferences, and guide progress stay locally on your Mac. A content suggestion used as a workspace name becomes part of that saved name.

The direct-distribution app uses private SkyLight APIs with App Sandbox off; it is not targeting the Mac App Store. Updates are delivered through Sparkle 2, with user-approved installation.

## Development

Open `Package.swift` in Xcode with a Swift 6 toolchain, or run:

```bash
swift test
swift build --product SidebyApp
swift build --product SidebyDevApp
```

`SidebyApp` is the product. `SidebyDevApp` is a local probe and API test harness. To build an app bundle for manual verification, check the published [Sparkle feed](https://github.com/ethznn/sideby/releases/latest/download/appcast.xml) and run `scripts/build_app_bundle.sh` with `SIDEBY_BUILD_NUMBER` set to the latest `sparkle:version` plus one. Do not use the script’s default build number after a public release exists.

Native screenshots use isolated sample data and can be regenerated without real external displays. See [README media](docs/media/README.md) for the capture command and asset details. Film production sources are maintained locally; MP4s are distributed as GitHub Release attachments.

### Architecture

- `SidebyApp`: menu bar, windows, product onboarding, and application coordination.
- `SidebyCore`: pure Swift workspace, gesture, settings, and recovery rules.
- `SidebySystem`: macOS input, display, layout, and command adapters.
- `SidebyUI`: reusable SwiftUI views and view models.
- `SidebyDevApp` / `SidebyDevSupport`: local probes and diagnostics.

Space switching goes through `ContextSwitchEngine` and `SpaceCommandExecutor`. SwiftUI owns reusable interfaces; AppKit handles menu bar, window, and system integration.

See [Development](docs/DEVELOPMENT.md) and [Decisions](docs/DECISIONS.md) for implementation and distribution details.

## Contributing, security, and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request, and run `swift test` for code changes. Discuss changes involving permissions, input, switching, packaging, or distribution in an issue first.

Report vulnerabilities through the process in [SECURITY.md](SECURITY.md), not a public issue. Sideby is released under the [MIT License](LICENSE).

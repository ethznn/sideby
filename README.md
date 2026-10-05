# Sideby

English | [한국어](README.ko.md)

[Website](https://ethznn.github.io/sideby/) · [Download](https://github.com/ethznn/sideby/releases/latest)

**Move your Spaces together.**

Connect the Spaces you already use across your displays. When your environment changes, see what is open and adjust the matching cell in Settings. No names or separate saves are required.

<p align="center">
  <img src="./docs/images/sideby-connections-film-en.gif" width="880" alt="Sideby switches three displays together, connects a Space by dropping it into a blank column, and shows dragging to move and Option-dragging to copy." />
</p>

*22.5-second motion graphic with fictional data. Illustrated workflow, not an app capture or a switching benchmark.*

[Still image](docs/images/sideby-connections-film-en.png) · [Preview with playback controls](docs/media/preview.html)

*Sideby 1.0.0 · [What’s new](docs/releases/1.0.0.md).*

## See and connect in one window

<p align="center">
  <img src="./docs/images/sideby-connections-settings-en.png" width="880" alt="Actual Settings with Spaces by display above the connection table, including move, swap, and Option-copy controls." />
</p>

*Actual app view with fictional data.*

1. Open **Sideby in the menu bar → Settings**. It opens directly to **Space connections**.
2. Review the Spaces above the table. Available app/window titles, Space positions, and **On screen** markers show what is open. Start with **Connect in current order**.
3. Drag a Space into a cell for the same display below. You can also click a Space, then a cell. Changes are remembered immediately. Use **Undo connection change** or `⌘Z` to undo the last change.

Spaces in the same column switch together. You can also click a cell to choose directly.

- **Create a connection:** Drop a Space into a blank cell in the **Add connection** column. The + button scrolls to this column.
- **Move or swap:** Drag between cells for the same display. Move into an empty cell or swap two occupied cells.
- **Copy:** **Hold ⌥ Option when dropping** to keep the source cell. Dragging from the Space list also keeps the list intact.
- **Undo:** **Undo connection change** restores both cells in one step.

Right-click a column heading to reorder or remove its connection. Removing a connection keeps the actual desktops and app windows.

Click the **arrow** beside a column heading to move your screens. Editing a cell or dragging a desktop does not switch screens. Displays excluded from switching remain where they are.

## Get started

1. Download the DMG from [GitHub Releases](https://github.com/ethznn/sideby/releases), move Sideby to Applications, and open it.
2. Allow Accessibility and Screen Switching access in the guide.
3. Choose **Connect in current order**, then start using Sideby. Naming, saving, and switching practice are not required.

Existing connections, names, and numbered shortcuts are kept. No recreation or deletion is required. If you have an unsaved draft in an older editor, finish it before changing connections here.

## Daily use

Hold `⌥⇧Space` to open the switcher with your current connection in view. **Click anywhere in a column** to move the connected desktops together. Choose **Edit connections** only when you need to change them; the panel shows **Spaces on your displays** above the connection table. Drag a card to a cell for the same display, or click the card and then the cell. Edits are immediate, and **Back to switching** returns within the same panel. **Settings** shows the same list and connection table. The menu-bar table still allows direct cell editing.

| Input | Action |
| --- | --- |
| Hold `⌥⇧Space` | Open the switcher near the pointer. Click a column to move. |
| `⌥⇧Tab` | Return to the last connection you visited. |
| `⌥⇧1` … `⌥⇧9`, `⌥⇧0` | Move to the connection assigned that number. Deleting another connection keeps existing numbers. |
| `⌥⇧<` / `⌥⇧>` | Move to the previous / next connection. |
| Option + Shift + horizontal swipe | Move displays together with the default gesture. |

Numbered, previous/next, and return shortcuts execute when Option and Shift are released. The held connection table closes on key release. Choosing **Edit connections** keeps it open so you can release the keys; dismiss it with Escape or the close button. Configure inputs in **Settings → Input**.

## When your environment changes

Connections follow the same surviving desktops when their order changes. A missing desktop is marked **Choose again**; Sideby never substitutes another desktop at the same position. New desktops appear in the upper list for you to connect. Disconnected displays keep their connections; use **Show disconnected displays** to see them.

**Space** refers to a macOS workspace, including regular desktops and full-screen apps. **Space · position 3** means its position in that display’s list, not a Mission Control name such as “Desktop 3.” Available app/window names are shown first.

Refresh rereads desktops and available app/window titles. Custom desktop names take priority. These labels do not rename Mission Control desktops. If writing settings fails, Sideby reports the problem and keeps the existing connections.

Sideby connects and switches existing Spaces. It does not create or delete desktops, launch apps, put them into full screen, or restore window positions.

## Privacy and platform notes

Sideby uses Accessibility for its configured global gesture and available app/window title suggestions. Screen Switching access allows the requested desktop-switch commands; some paths also need System Events Automation. Switching and desktop discovery do not request Screen Recording permission.

Setup names, desktop connection bookmarks, custom desktop names, display choices, shortcut assignments, undo data, migration backups, input preferences, and guide progress stay locally on your Mac. Runtime numeric Space IDs, window IDs, raw input events, and screenshots are not saved. Sideby does not save typed input from its global shortcut handling.

The direct-distribution app uses private SkyLight APIs with App Sandbox off. Updates use Sparkle 2, with user-approved installation.

## Development

Open `Package.swift` in Xcode with a Swift 6 toolchain, or run:

```bash
swift test
swift build --product SidebyApp
swift build --product SidebyDevApp
```

`SidebyApp` is the product; `SidebyDevApp` is a local probe. Before a local app bundle build, read the published [Sparkle feed](https://github.com/ethznn/sideby/releases/latest/download/appcast.xml) and set `SIDEBY_BUILD_NUMBER` to the latest `sparkle:version` plus one when running `scripts/build_app_bundle.sh`.

See [Development](docs/DEVELOPMENT.md), [Decisions](docs/DECISIONS.md), and [README media](docs/media/README.md). Native documentation views use isolated sample data. The repository contains GIF previews and still images; full MP4 exports stay local.

## Contributing, security, and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. Report vulnerabilities through [SECURITY.md](SECURITY.md). Sideby is released under the [MIT License](LICENSE).

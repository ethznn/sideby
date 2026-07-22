# Sideby

[English](README.md) | [한국어](README.ko.md)

Sideby is a native macOS menu bar app that lets multiple displays move together as one work Context.

Choose the displays that belong together, capture their current Spaces, and switch the whole setup with a gesture, shortcut, button, or direct Context selection. Sideby stays focused on this workflow instead of trying to replace Mission Control or become a full window manager.

## Preview

<p align="center">
  <img src="./docs/images/sideby-demo-en.gif" width="720" alt="Sideby switching a multi-display workspace between Contexts" />
</p>

## Why Sideby

A single task often spans several displays: code on one screen, references on another, and communication on a third. Moving to the next task should move that workspace as a set instead of making you switch each display separately.

Sideby turns those per-display Spaces into named Contexts. It keeps the scope intentionally small and reports permission or Space limitations clearly when macOS cannot complete a requested move safely.

## How It Works

1. **Choose displays.** Select the displays that should move together.
2. **Capture a Context.** Build named Contexts from the current Space arrangement, then adjust membership in the matrix when needed.
3. **Switch together.** Use a gesture, shortcut, Previous/Next button, or direct Context selection to move the workspace.

## Features

### Contexts

- Capture the current multi-display Space arrangement instantly, with a walk-based fallback when the layout query is unavailable.
- Capture every discovered Space without a fixed Context-count limit.
- Add empty Contexts, then arrange display Space membership in the Context matrix.
- Delete Contexts without removing physical macOS Spaces. Empty Contexts are removed immediately; mapped Contexts require confirmation.
- Prevent deletion below the smallest live Space count among the selected displays and fail closed when the live layout cannot be trusted.
- Preserve gaps when displays start at different Space positions, so membership does not have to be contiguous.

### Switching

- Move selected displays to the previous or next captured Context using per-display target Space indexes.
- Activate a named Context directly from the matrix.
- Align selected displays with the Context represented by the reference display.
- Fall back to general movement when external Space changes make Context matching unsafe.
- See a compact center-screen Context HUD after a successful move.
- Press `1...9`, `0`, `<`, or `>` with `Option + Shift`, then release both modifiers to switch Contexts.

### Customization

- Choose Move Targets for general previous/next Space movement.
- Drag display Space positions to adjust captured membership.
- Reorder display rows and resize the display-name column.
- Use the default `Option + Shift + horizontal swipe`, the fixed Context keyboard layer, or inline controls.
- Add names and best-effort visible app/window suggestions to captured Spaces.

### Native macOS Experience

- Menu bar-only interface with a resizable popover and no persistent Dock icon.
- Clear onboarding and diagnostics for Accessibility and Screen Switching access.
- English and Korean interface copy.
- Signed in-app update checks, downloads, and user-approved installation through Sparkle 2.

## Install & Quick Start

Sideby requires macOS 14 or later.

Download the latest signed and notarized DMG from [GitHub Releases](https://github.com/ethznn/sideby/releases), move Sideby to Applications, and open it. Sideby stays in the menu bar; use its menu bar item to reopen the controls.

On first launch, macOS asks for the permissions needed to detect the configured gesture and send the requested Space switch command:

- **Accessibility** for global gesture detection.
- **Screen Switching access** for the previous/next Space command.
- **System Events Automation** when the current command path requires it.

Sideby does not request Screen Recording for switching, Context Capture, or Align Displays.

To build from source, install Xcode with a Swift 6 toolchain, then run:

```bash
swift test
scripts/build_app_bundle.sh
open "dist/Sideby.app"
```

If macOS still reports a rebuilt local app as denied, remove the old Sideby entry from System Settings and add the rebuilt app again.

## Privacy & Platform Notes

Sideby uses Accessibility to detect the configured gesture while its master toggle is on or during an explicitly active onboarding gesture test. It also uses Accessibility to send a Space command after an allowed switching or capture request and to make best-effort visible app/window name suggestions during Context Capture. While the app is running, macOS global hot-key registration listens only for the fixed `Option + Shift + number / < / >` combinations so Sideby can explain when its master toggle is off. Sideby does not inspect or store other typed input.

Sideby reads the current per-display Space layout at runtime when macOS makes it available. It does not store private Space IDs, hidden Mission Control state, typed input, raw input events, screenshots, app bundle IDs, or window IDs.

The following user configuration stays local on the Mac:

- Context names and definitions
- Display membership and captured per-display Space indexes
- Display row order
- Shortcut and input settings
- User-authored labels

Deleting a Context removes only Sideby's saved mapping. It never deletes a macOS Space.

The current direct-distribution build runs with App Sandbox off. Context Capture and Align Displays use a read-only SkyLight layout query when available, with a public-command fallback for capture. Sideby is therefore not targeting Mac App Store distribution.

## Development

Open the Swift package directly in Xcode:

```bash
xed Package.swift
```

Use `SidebyApp` for the product app and `SidebyDevApp` for local probes and macOS API experiments.

```bash
swift test
swift build --product SidebyApp
swift build --product SidebyDevApp
scripts/build_app_bundle.sh
scripts/build_dev_app_bundle.sh
```

`SidebyDevApp` is a local test harness, not the release bundle. The product bundle uses `Resources/AppIcon.icns`.

## Architecture

Sideby is split into small SwiftPM modules:

```text
Sources/
  SidebyApp/        product app, menu bar, panels, onboarding
  SidebyDevApp/     local probes and diagnostics
  SidebyDevSupport/ probe helpers used by SidebyDevApp
  SidebyCore/       domain models, gesture logic, settings, diagnostics
  SidebySystem/     macOS API adapters
  SidebyUI/         reusable SwiftUI views and view models
Tests/
  SidebyCoreTests/
  SidebySystemTests/
  SidebyUITests/
```

Important boundaries:

- Space switching goes through `ContextSwitchEngine` and `SpaceCommandExecutor`.
- Global input and macOS adapters stay in `SidebySystem`.
- Gesture interpretation and Context rules stay in pure Swift under `SidebyCore`.
- SwiftUI owns reusable UI while AppKit adapters handle menu bar, window, and system integration.

See [Development](docs/DEVELOPMENT.md) for setup and release notes, and [Decisions](docs/DECISIONS.md) for the technical boundaries that protect users.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request, and run `swift test` for code changes.

For changes involving permissions, input, switching, packaging, or distribution, open an issue first so the trade-offs are explicit.

## Security

Please do not report security vulnerabilities through public issues. See [SECURITY.md](SECURITY.md) for the reporting process.

## License

Sideby is released under the [MIT License](LICENSE).

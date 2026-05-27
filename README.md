# Sideby

[English](README.md) | [한국어](README.ko.md)

Sideby is a native macOS menu bar utility for people who work across multiple displays and want to switch a whole work context together. Its product slogan is "Side by Side."

Sideby does not replace Mission Control and is not a full window manager. It focuses on a narrow workflow: choose the displays that should move together, turn Sideby on, then use a gesture or optional shortcut to move to the previous or next macOS Space.

## Why Sideby Exists

Sideby started from a simple way of organizing work: keep one context spread across multiple displays, with each screen holding a useful part of the same task. When the context changes, those screens should move together instead of being switched one display at a time.

The goal is to make a multi-display setup feel like one workspace that can move as a set. Sideby keeps the scope small, uses public macOS APIs, and explains permission or Space limitations clearly instead of pretending that macOS exposes perfect control over every display.

## Status

Sideby is pre-1.0 software. The V1 app shell, onboarding flow, menu bar settings (`메뉴바 설정`), main settings (`메인 설정`), display targeting, input pipeline, diagnostics, and local bundle scripts are in active development.

The current release strategy is direct distribution with App Sandbox off. Sideby must continue to use public macOS APIs only; it does not depend on private Mission Control or Spaces APIs.

## Features

- Menu bar app for quick control across multiple displays.
- Move Targets for selecting which displays should switch together.
- Previous/Next Screen Switching through public macOS keyboard-command paths.
- Default input habit: `Option + Shift + horizontal swipe`.
- Optional Previous/Next keyboard shortcuts from main settings (`메인 설정`).
- First-run onboarding for Accessibility and Screen Switching access.
- Diagnostics for permission, display, and switching limitations.
- Display Spaces labels and best-effort visible app/window suggestions.
- English and Korean UI copy.

## Requirements

- macOS 14 or later.
- Xcode with a Swift 6 toolchain.
- Accessibility permission for global input detection.
- Screen Switching access for posting the requested Space switch command.
- System Events Automation permission when the current V1 command path needs it.

Sideby does not request Screen Recording for V1 Screen Switching.

## Quick Start

Clone the repository, run the tests, then build the local product bundle:

```bash
swift test
scripts/build_app_bundle.sh
open "dist/Sideby.app"
```

After opening the app, grant the requested Accessibility and Screen Switching permissions in macOS system settings (`macOS 시스템 설정`). If you rebuild the bundle and macOS still reports a permission as denied, remove the old Sideby entry from `macOS 시스템 설정` and add the rebuilt app again.

For development and macOS API experiments, build the dev app:

```bash
scripts/build_dev_app_bundle.sh
open "dist/SidebyDevApp.app"
```

`SidebyDevApp` is a local test harness. It is not the release bundle.

## Development

Open the Swift package directly in Xcode:

```bash
xed Package.swift
```

Use the `SidebyApp` scheme for the product app and `SidebyDevApp` for the local dev harness.

Common commands:

```bash
swift test
swift build --product SidebyApp
swift build --product SidebyDevApp
scripts/build_app_bundle.sh
scripts/build_dev_app_bundle.sh
```

The product bundle uses `Resources/AppIcon.icns`. When replacing source artwork, regenerate the icon before building:

```bash
swift scripts/generate_app_icon.swift <source-png> Resources/AppIcon.icns
scripts/build_app_bundle.sh
```

## Architecture

The repository is split into small SwiftPM modules:

```text
Sources/
  SidebyApp/       product app, menu bar, panels, onboarding
  SidebyDevApp/    local probes and diagnostics
  SidebyCore/      domain models, gesture logic, settings, diagnostics
  SidebySystem/    macOS API adapters
  SidebyUI/        reusable SwiftUI views and view models
Tests/
  SidebyCoreTests/
  SidebySystemTests/
  SidebyUITests/
```

Important boundaries:

- Space switching goes through `ContextSwitchEngine` and `SpaceCommandExecutor`.
- Global input adapters stay in `SidebySystem`.
- Gesture interpretation stays in pure Swift domain logic under `SidebyCore`.
- SwiftUI owns reusable UI, while AppKit adapters handle menu bar, window, and system integration details.

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for setup notes and [docs/DECISIONS.md](docs/DECISIONS.md) for the small set of technical boundaries that protect users.

## Privacy

Sideby uses Accessibility permission to detect the configured gesture while Sideby is on. It uses Screen Switching access to send the requested previous/next Space command after the user acts.

Sideby does not store typed input, raw input events, screenshots, private Space IDs, app bundle IDs, window IDs, or hidden Mission Control state. Display Spaces labels are user-authored and stored locally.

## Documentation

- [Development](docs/DEVELOPMENT.md)
- [Decisions](docs/DECISIONS.md)

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request.

For code changes, run `swift test` before submitting. For permission, input, switching, packaging, or release-sensitive changes, open an issue first so the tradeoffs can be discussed.

## Security

Please do not report security vulnerabilities through public issues. See [SECURITY.md](SECURITY.md) for the reporting process.

## License

Sideby is released under the [MIT License](LICENSE).

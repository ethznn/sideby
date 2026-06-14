# Development

This file keeps only the practical setup notes needed to work on Sideby.

## Requirements

- macOS 14 or later.
- Xcode with a Swift 6 toolchain.

## Commands

Run tests:

```bash
swift test
```

Build local app bundles:

```bash
scripts/build_app_bundle.sh
scripts/build_dev_app_bundle.sh
```

`build_app_bundle.sh` defaults to a release build. Override with `SIDEBY_BUILD_CONFIGURATION=debug` when you need a faster local product build. `build_dev_app_bundle.sh` defaults to debug.

Build the release DMG:

```bash
scripts/build_release_dmg.sh
```

Open the package in Xcode:

```bash
xed Package.swift
```

Use `SidebyApp` for the product app and `SidebyDevApp` for local probes. Probe-only helpers live in `SidebyDevSupport` so the product app does not carry command-line experiment runners.

## Repository Shape

```text
Sources/
  SidebyApp/       product app
  SidebyDevApp/    local development harness
  SidebyDevSupport/ local probe helpers
  SidebyCore/      domain models and pure logic
  SidebySystem/    macOS system adapters
  SidebyUI/        reusable SwiftUI views
Tests/
  SidebyCoreTests/
  SidebySystemTests/
  SidebyUITests/
```

## Pull Requests

- Keep changes focused.
- Add or update tests for logic changes.
- Run `swift test` before opening a pull request.
- For macOS permission, global input, synthetic input, bundle signing, or distribution changes, open an issue first so the tradeoffs are clear.

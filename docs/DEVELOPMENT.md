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

Open the package in Xcode:

```bash
xed Package.swift
```

Use `SidebyApp` for the product app and `SidebyDevApp` for local probes.

## Repository Shape

```text
Sources/
  SidebyApp/       product app
  SidebyDevApp/    local development harness
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

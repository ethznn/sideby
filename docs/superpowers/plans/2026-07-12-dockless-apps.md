# Dockless Sideby Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep both Sideby product and Dev apps out of the Dock and Command-Tab for app-bundle and direct executable launches while preserving their menu-bar and window behavior.

**Architecture:** A shared SidebySystem helper applies AppKit's `.accessory` activation policy at runtime from both SwiftUI entry points. Both bundle-generation scripts also emit `LSUIElement = true`, preventing a Dock icon before Swift startup. A reusable verification script checks the generated bundle property.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, Bash, macOS `plutil`, Swift Package Manager.

## Global Constraints

- Support macOS 14 or later.
- Hide both `Sideby.app` and `SidebyDevApp.app` from the Dock and Command-Tab.
- Preserve all existing menu-bar, onboarding, settings-window, Dev-window, floating-panel, HUD, and Quit behavior.
- Preserve the existing Direct Space Jump research changes without editing them.
- Do not change Space switching, settings models, permissions, sandbox, signing, or release/notarization behavior.
- Do not create commits unless the user explicitly requests them.

---

### Task 1: Shared Runtime Accessory Policy

**Files:**
- Create: `Sources/SidebySystem/ApplicationPresentation/MenuBarOnlyApplicationPresentation.swift`
- Create: `Tests/SidebySystemTests/ApplicationPresentationTests.swift`
- Modify: `Sources/SidebyApp/SidebyApp.swift:16-21`
- Modify: `Sources/SidebyDevApp/SidebyDevApp.swift:15-20`

**Interfaces:**
- Consumes: AppKit `NSApplication` and `NSApplication.ActivationPolicy`.
- Produces: `MenuBarOnlyApplicationPresentation.activationPolicy` and `MenuBarOnlyApplicationPresentation.apply(to:) -> Bool`.

- [ ] **Step 1: Write the failing runtime-policy tests**

```swift
import AppKit
import XCTest
@testable import SidebySystem

final class ApplicationPresentationTests: XCTestCase {
    func testMenuBarOnlyPresentationUsesAccessoryActivationPolicy() {
        XCTAssertEqual(MenuBarOnlyApplicationPresentation.activationPolicy, .accessory)
    }

    @MainActor
    func testMenuBarOnlyPresentationAppliesAccessoryActivationPolicy() {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        defer { application.setActivationPolicy(originalPolicy) }

        XCTAssertTrue(MenuBarOnlyApplicationPresentation.apply(to: application))
        XCTAssertEqual(application.activationPolicy(), .accessory)
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter ApplicationPresentationTests`

Expected: compilation fails because `MenuBarOnlyApplicationPresentation` does not exist.

- [ ] **Step 3: Add the minimal shared policy implementation**

```swift
import AppKit

public enum MenuBarOnlyApplicationPresentation {
    public static let activationPolicy: NSApplication.ActivationPolicy = .accessory

    @MainActor
    @discardableResult
    public static func apply(to application: NSApplication = .shared) -> Bool {
        application.setActivationPolicy(activationPolicy)
    }
}
```

- [ ] **Step 4: Apply the policy from both app initializers**

Add this as the first statement in both `SidebyApp.init()` and `SidebyDevApp.init()`:

```swift
MenuBarOnlyApplicationPresentation.apply()
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run: `swift test --filter ApplicationPresentationTests`

Expected: 2 tests pass with 0 failures.

### Task 2: Agent-App Bundle Configuration

**Files:**
- Create: `scripts/verify_menu_bar_only_bundle.sh`
- Modify: `scripts/build_app_bundle.sh:67-74`
- Modify: `scripts/build_dev_app_bundle.sh:50-54`

**Interfaces:**
- Consumes: one `.app` bundle path as `$1`.
- Produces: exit `0` only when `Contents/Info.plist` contains Boolean `LSUIElement = true`; otherwise prints an error and exits nonzero.

- [ ] **Step 1: Add the reusable bundle assertion**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:?usage: verify_menu_bar_only_bundle.sh <app-bundle>}"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: missing Info.plist at $INFO_PLIST" >&2
  exit 1
fi

VALUE="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST" 2>/dev/null || true)"
if [[ "$VALUE" != "true" ]]; then
  echo "error: LSUIElement is not true in $INFO_PLIST" >&2
  exit 1
fi

echo "$APP_DIR: LSUIElement=true"
```

- [ ] **Step 2: Run the assertion against the current product bundle and verify RED**

Run: `bash scripts/verify_menu_bar_only_bundle.sh dist/Sideby.app`

Expected: exit `1` with `LSUIElement is not true`.

- [ ] **Step 3: Emit `LSUIElement` from both build scripts**

Add the following immediately after `LSMinimumSystemVersion` in both generated plist dictionaries:

```xml
  <key>LSUIElement</key>
  <true/>
```

- [ ] **Step 4: Build both bundles**

Run: `bash scripts/build_app_bundle.sh`

Expected: product build and code-sign verification complete with exit `0`.

Run: `bash scripts/build_dev_app_bundle.sh`

Expected: Dev build and signing complete with exit `0`.

- [ ] **Step 5: Verify both generated bundle settings**

Run: `bash scripts/verify_menu_bar_only_bundle.sh dist/Sideby.app`

Expected: `dist/Sideby.app: LSUIElement=true`.

Run: `bash scripts/verify_menu_bar_only_bundle.sh dist/SidebyDevApp.app`

Expected: `dist/SidebyDevApp.app: LSUIElement=true`.

### Task 3: Regression and Runtime Verification

**Files:**
- Verify only; no additional source files.

**Interfaces:**
- Consumes: completed Task 1 and Task 2 artifacts.
- Produces: evidence that tests, builds, signatures, launch behavior, and release comparison are correct.

- [ ] **Step 1: Run the full test suite**

Run: `swift test`

Expected: all tests pass with 0 failures.

- [ ] **Step 2: Validate scripts and source formatting**

Run: `bash -n scripts/build_app_bundle.sh scripts/build_dev_app_bundle.sh scripts/verify_menu_bar_only_bundle.sh`

Expected: exit `0` with no output.

Run: `git diff --check`

Expected: exit `0` with no output.

- [ ] **Step 3: Re-verify both signatures**

Run: `codesign --verify --deep --strict --verbose=2 dist/Sideby.app`

Run: `codesign --verify --deep --strict --verbose=2 dist/SidebyDevApp.app`

Expected: both bundles are valid on disk and satisfy their designated requirements.

- [ ] **Step 4: Replace running copies and launch both new bundles**

Terminate only existing Sideby and SidebyDevApp processes, then run:

```bash
open dist/Sideby.app
open dist/SidebyDevApp.app
```

Expected: both processes run, both menu-bar items are available, and no Dock or Command-Tab items appear.

- [ ] **Step 5: Compare against the GitHub release baseline**

Run: `git diff --stat v0.5.0`

Run: `git diff --name-status v0.5.0`

Expected: the final report separates Dockless-app implementation files from the preserved Direct Space Jump research files and design/plan documents.

# Context Activation Guard and Matrix Axis Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent direct Context movement whenever Sideby is unavailable and label the Context matrix's top-left cell with directional row and column axes.

**Architecture:** A pure `SidebyCore` policy provides one availability decision to both the model and SwiftUI button. A small `SidebyUI` axis-role contract makes the top-trailing Context and bottom-leading Display placement explicit, while `ContextsView` renders those roles with existing localized strings.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager, macOS 14+.

## Global Constraints

- Sideby off, active switching, and active Context capture must all disable direct Context activation.
- The model must block off-state activation independently of the UI and publish the existing Sideby-off diagnostic.
- The top-left matrix cell must show `Contexts →` / `컨텍스트 →` at top-trailing and `Displays ↓` / `디스플레이 ↓` at bottom-leading.
- Existing Context editing, drag-and-drop, display-column resizing, Space switching, Dock settings, and Direct Space Jump research must remain unchanged.
- Reuse existing localized strings; add no new user-facing copy.
- Do not create commits unless the user explicitly requests them.

---

### Task 1: Direct Context Activation Availability

**Files:**
- Create: `Sources/SidebyCore/Contexts/ContextActivationAvailability.swift`
- Create: `Tests/SidebyCoreTests/ContextActivationAvailabilityTests.swift`
- Modify: `Sources/SidebyApp/SidebyApp.swift:730-747`
- Modify: `Sources/SidebyApp/SidebyApp.swift:4160-4182`

**Interfaces:**
- Consumes: `isSidebyEnabled: Bool`, `isSwitching: Bool`, and `isCapturing: Bool`.
- Produces: `ContextActivationAvailability.canActivate(isSidebyEnabled:isSwitching:isCapturing:) -> Bool` and `SidebyAppModel.canActivateContext: Bool`.

- [ ] **Step 1: Write the failing availability tests**

```swift
import XCTest
@testable import SidebyCore

final class ContextActivationAvailabilityTests: XCTestCase {
    func testContextActivationRequiresEnabledIdleState() {
        XCTAssertTrue(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: true,
                isSwitching: false,
                isCapturing: false
            )
        )
        XCTAssertFalse(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: false,
                isSwitching: false,
                isCapturing: false
            )
        )
        XCTAssertFalse(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: true,
                isSwitching: true,
                isCapturing: false
            )
        )
        XCTAssertFalse(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: true,
                isSwitching: false,
                isCapturing: true
            )
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter ContextActivationAvailabilityTests`

Expected: compilation fails because `ContextActivationAvailability` does not exist.

- [ ] **Step 3: Add the minimal policy implementation**

```swift
public enum ContextActivationAvailability: Sendable {
    public static func canActivate(
        isSidebyEnabled: Bool,
        isSwitching: Bool,
        isCapturing: Bool
    ) -> Bool {
        isSidebyEnabled && !isSwitching && !isCapturing
    }
}
```

- [ ] **Step 4: Apply the policy to the model and button**

Add to `SidebyAppModel`:

```swift
var canActivateContext: Bool {
    ContextActivationAvailability.canActivate(
        isSidebyEnabled: isEnabled,
        isSwitching: isSwitching,
        isCapturing: contextCaptureSession != nil
    )
}
```

At the beginning of `activateContext(contextID:)`, before computing the intent:

```swift
guard isEnabled else {
    diagnostics = [
        DiagnosticState(
            severity: .warning,
            title: strings.sidebyOffTitle,
            message: strings.sidebyOffMessage,
            actionLabel: nil
        )
    ]
    lastSwitchResult = strings.sidebyOffReason
    return
}
guard canActivateContext else {
    return
}
```

Remove the now-redundant `contextCaptureSession == nil, !isSwitching` guard later in the method. Add to `goToContextButton` after accessibility modifiers:

```swift
.disabled(!model.canActivateContext)
.pointingHandCursor(model.canActivateContext)
```

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run: `swift test --filter ContextActivationAvailabilityTests`

Expected: 1 test passes with 0 failures.

### Task 2: Directional Matrix Axis Header

**Files:**
- Modify: `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift:1-70`
- Modify: `Tests/SidebyUITests/AppShellTests.swift:130-200`
- Modify: `Sources/SidebyApp/SidebyApp.swift:4069-4075`

**Interfaces:**
- Produces: `FloatingMenuContextMatrixAxis`, `FloatingMenuContextMatrixAxisHeaderContent.topTrailing`, and `FloatingMenuContextMatrixAxisHeaderContent.bottomLeading`.
- Consumes: existing `SBSStrings.contextPlanner` and `SBSStrings.displays` values.

- [ ] **Step 1: Write the failing axis-role test**

Add to `AppShellTests`:

```swift
func testContextMatrixAxisHeaderPlacesContextsAcrossAndDisplaysDown() {
    XCTAssertEqual(FloatingMenuContextMatrixAxisHeaderContent.topTrailing, .contexts)
    XCTAssertEqual(FloatingMenuContextMatrixAxisHeaderContent.bottomLeading, .displays)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter AppShellTests/testContextMatrixAxisHeaderPlacesContextsAcrossAndDisplaysDown`

Expected: compilation fails because the axis-header content types do not exist.

- [ ] **Step 3: Add the axis-role contract**

Add near the other Context matrix menu policies in `FloatingMenuPanelLayout.swift`:

```swift
public enum FloatingMenuContextMatrixAxis: Equatable, Sendable {
    case contexts
    case displays
}

public enum FloatingMenuContextMatrixAxisHeaderContent: Sendable {
    public static let topTrailing: FloatingMenuContextMatrixAxis = .contexts
    public static let bottomLeading: FloatingMenuContextMatrixAxis = .displays
}
```

- [ ] **Step 4: Render the directional top-left cell**

Replace the existing single `Text(model.strings.displays)` header in `displayColumn(rows:)` with:

```swift
matrixAxisHeader(strings: model.strings)
```

Add to `ContextsView`:

```swift
private func matrixAxisHeader(strings: SBSStrings) -> some View {
    ZStack {
        Text("\(axisLabel(FloatingMenuContextMatrixAxisHeaderContent.topTrailing, strings: strings)) →")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

        Text("\(axisLabel(FloatingMenuContextMatrixAxisHeaderContent.bottomLeading, strings: strings)) ↓")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
    .font(.caption2.weight(.semibold))
    .foregroundStyle(.secondary)
    .frame(width: displayColumnWidth, height: headerHeight)
}

private func axisLabel(
    _ axis: FloatingMenuContextMatrixAxis,
    strings: SBSStrings
) -> String {
    switch axis {
    case .contexts:
        strings.contextPlanner
    case .displays:
        strings.displays
    }
}
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run: `swift test --filter AppShellTests/testContextMatrixAxisHeaderPlacesContextsAcrossAndDisplaysDown`

Expected: 1 test passes with 0 failures.

### Task 3: Full Verification and Relaunch

**Files:**
- Verify only; no additional source files.

**Interfaces:**
- Consumes: completed activation policy and axis header.
- Produces: regression, build, and runtime evidence.

- [ ] **Step 1: Run the full test suite**

Run: `swift test`

Expected: all tests pass with 0 failures.

- [ ] **Step 2: Check the working diff**

Run: `git diff --check`

Expected: exit `0` with no output.

- [ ] **Step 3: Rebuild and relaunch the product app**

Run: `bash scripts/build_app_bundle.sh`

Expected: product build and code-sign verification complete with exit `0`.

Terminate only the currently running `dist/Sideby.app` process, then run:

```bash
open dist/Sideby.app
```

Expected: the new process runs as a `UIElement`; the disabled-button behavior and directional header are ready for manual inspection.

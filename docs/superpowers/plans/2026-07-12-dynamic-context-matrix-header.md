# Dynamic Context Matrix Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Context matrix's oversized fixed header height with the tallest naturally rendered Context header height.

**Architecture:** Context headers report their rendered heights through a SwiftUI preference key that reduces values with `max`. `ContextsView` stores that measured value and applies it only to the frozen axis header and resize handle, while Context headers retain intrinsic height.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Preserve `Contexts →` / `컨텍스트 →` at the top-trailing corner and `Displays ↓` / `디스플레이 ↓` at the bottom-leading corner.
- Keep Display names and Space cells row-aligned.
- Do not introduce compact or regular fixed header-height constants.
- Preserve all unrelated uncommitted workspace changes.
- Do not create commits because the target files already contain overlapping uncommitted user work; leave the scoped diff available for review.

---

### Task 1: Tallest Header Height Reduction

**Files:**
- Modify: `Tests/SidebyUITests/AppShellTests.swift`
- Modify: `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift`

**Interfaces:**
- Produces: `FloatingMenuContextMatrixHeaderHeightPreferenceKey: PreferenceKey`
- Produces: `defaultValue: CGFloat == 0`
- Produces: `reduce(value:inout CGFloat,nextValue:() -> CGFloat)` retaining the maximum reported height

- [ ] **Step 1: Replace the fixed-height test with a failing maximum-reduction test**

```swift
func testContextMatrixHeaderHeightPreferenceKeepsTallestHeader() {
    var height = FloatingMenuContextMatrixHeaderHeightPreferenceKey.defaultValue

    FloatingMenuContextMatrixHeaderHeightPreferenceKey.reduce(value: &height) { 44 }
    FloatingMenuContextMatrixHeaderHeightPreferenceKey.reduce(value: &height) { 52 }
    FloatingMenuContextMatrixHeaderHeightPreferenceKey.reduce(value: &height) { 48 }

    XCTAssertEqual(height, 52)
}
```

Delete `testCompactContextMatrixUsesShortHeaderAfterMovingGoIntoTitleRow`, because fixed `68` and `82` heights are no longer part of the layout contract.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter AppShellTests/testContextMatrixHeaderHeightPreferenceKeepsTallestHeader
```

Expected: compilation fails because `FloatingMenuContextMatrixHeaderHeightPreferenceKey` does not exist.

- [ ] **Step 3: Add the maximum-reducing SwiftUI preference key**

Add `import SwiftUI` to `FloatingMenuPanelLayout.swift`, then add:

```swift
public struct FloatingMenuContextMatrixHeaderHeightPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

Delete `FloatingMenuContextMatrixLayout.headerHeight(isCompact:)`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
swift test --filter AppShellTests/testContextMatrixHeaderHeightPreferenceKeepsTallestHeader
```

Expected: one selected test passes with zero failures.

---

### Task 2: Intrinsic Context Header Layout

**Files:**
- Modify: `Sources/SidebyApp/SidebyApp.swift`

**Interfaces:**
- Consumes: `FloatingMenuContextMatrixHeaderHeightPreferenceKey`
- Produces: `ContextsView.contextHeaderHeight: CGFloat`
- Produces: natural-height `contextHeader(_:)`

- [ ] **Step 1: Store and consume the measured header height**

Add view state:

```swift
@State private var contextHeaderHeight: CGFloat = 0
```

Attach preference consumption to the matrix `HStack`:

```swift
.onPreferenceChange(FloatingMenuContextMatrixHeaderHeightPreferenceKey.self) { height in
    guard abs(contextHeaderHeight - height) > 0.5 else { return }
    contextHeaderHeight = height
}
```

- [ ] **Step 2: Report each Context header's intrinsic height**

Replace the fixed header frame with a width-only frame and measurement background:

```swift
.frame(width: contextColumnWidth, alignment: .topLeading)
.background {
    GeometryReader { proxy in
        Color.clear.preference(
            key: FloatingMenuContextMatrixHeaderHeightPreferenceKey.self,
            value: proxy.size.height
        )
    }
}
```

- [ ] **Step 3: Synchronize only the frozen axis header and resize handle**

Apply the optional measured height to the axis header:

```swift
.frame(
    width: displayColumnWidth,
    height: contextHeaderHeight > 0 ? contextHeaderHeight : nil
)
```

Replace the resize-handle calculation's fixed header value with `contextHeaderHeight`:

```swift
let height = contextHeaderHeight
    + CGFloat(rowCount) * rowHeight
    + CGFloat(rowGaps) * 8
```

Delete the `ContextsView.headerHeight` computed property.

- [ ] **Step 4: Compile and run the focused UI tests**

Run:

```bash
swift test --filter AppShellTests
```

Expected: all `AppShellTests` pass with zero failures.

---

### Task 3: Full Verification and Relaunch

**Files:**
- Verify: `Sources/SidebyApp/SidebyApp.swift`
- Verify: `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift`
- Verify: `Tests/SidebyUITests/AppShellTests.swift`
- Verify: `dist/Sideby.app`

**Interfaces:**
- Consumes: completed dynamic-header implementation
- Produces: verified and running menu-bar-only `Sideby.app`

- [ ] **Step 1: Check patch formatting and run the full test suite**

Run:

```bash
git diff --check
swift test -q
```

Expected: no whitespace errors; all tests pass with zero failures.

- [ ] **Step 2: Build and verify the app bundle**

Run:

```bash
bash scripts/build_app_bundle.sh
bash scripts/verify_menu_bar_only_bundle.sh dist/Sideby.app
codesign --verify --deep --strict --verbose=2 dist/Sideby.app
```

Expected: build exits successfully, `LSUIElement=true`, and code signing verification succeeds.

- [ ] **Step 3: Relaunch the product build**

Terminate the currently running `io.github.ethznn.sideby` product process, open `dist/Sideby.app`, and confirm through `lsappinfo` that its application type remains `UIElement`.

- [ ] **Step 4: Inspect the compact matrix**

Open the menu-bar panel and confirm:

- the Context title/action row and name field determine header height naturally;
- the axis labels occupy the same measured height;
- the first Space row starts directly below the header gap;
- Display names and Space cells remain horizontally aligned.

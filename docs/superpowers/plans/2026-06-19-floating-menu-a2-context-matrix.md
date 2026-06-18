# Floating Menu A2 Context Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the floating menu use the A2 design: a polished responsive Move Targets display map above an always-visible, name-forward Context Matrix.

**Architecture:** Keep the current single-column floating menu. Add a small public SidebyUI layout helper for display-map fitting so the geometry can be tested outside SwiftUI, then wire it into the private `DisplayArrangementView`. Refine existing matrix layout constants and header rendering without changing Context semantics or drag payloads.

**Tech Stack:** Swift 6, SwiftUI, XCTest, SidebyCore display models, SidebyUI layout helpers.

---

### Task 1: Add a Tested Display Arrangement Fit Helper

**Files:**
- Modify: `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift`
- Modify: `Tests/SidebyUITests/AppShellTests.swift`

- [ ] **Step 1: Write failing layout tests**

Add these tests near the existing floating menu layout tests in `Tests/SidebyUITests/AppShellTests.swift`:

```swift
func testDisplayArrangementLayoutFitsSideBySideDisplaysInsideStage() {
    let placements = FloatingMenuDisplayArrangementLayout.placements(
        for: [
            FloatingMenuDisplayLayoutInput(
                displayID: "built-in",
                frame: DisplayFrame(x: 0, y: 0, width: 1728, height: 1117)
            ),
            FloatingMenuDisplayLayoutInput(
                displayID: "external",
                frame: DisplayFrame(x: 1728, y: -80, width: 2560, height: 1440)
            )
        ],
        in: CGSize(width: 660, height: FloatingMenuDisplayArrangementLayout.stageHeight)
    )

    XCTAssertEqual(placements.map(\.displayID), ["built-in", "external"])
    XCTAssertTrue(placements.allSatisfy { $0.frame.minX >= 0 })
    XCTAssertTrue(placements.allSatisfy { $0.frame.minY >= 0 })
    XCTAssertTrue(placements.allSatisfy { $0.frame.maxX <= 660 })
    XCTAssertTrue(placements.allSatisfy { $0.frame.maxY <= FloatingMenuDisplayArrangementLayout.stageHeight })
    XCTAssertGreaterThan(placements[1].frame.width, placements[0].frame.width)
}

func testDisplayArrangementLayoutCentersStackedDisplays() {
    let placements = FloatingMenuDisplayArrangementLayout.placements(
        for: [
            FloatingMenuDisplayLayoutInput(
                displayID: "top",
                frame: DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
            ),
            FloatingMenuDisplayLayoutInput(
                displayID: "bottom",
                frame: DisplayFrame(x: 240, y: 1080, width: 1440, height: 900)
            )
        ],
        in: CGSize(width: 520, height: FloatingMenuDisplayArrangementLayout.stageHeight)
    )

    let union = placements.map(\.frame).reduce(CGRect.null) { $0.union($1) }

    XCTAssertEqual(placements.count, 2)
    XCTAssertEqual(union.midX, 260, accuracy: 1.0)
    XCTAssertTrue(placements.allSatisfy { $0.frame.maxY <= FloatingMenuDisplayArrangementLayout.stageHeight })
}

func testDisplayArrangementLayoutPreservesMinimumReadableDisplaySize() {
    let placements = FloatingMenuDisplayArrangementLayout.placements(
        for: [
            FloatingMenuDisplayLayoutInput(
                displayID: "tiny",
                frame: DisplayFrame(x: 0, y: 0, width: 300, height: 200)
            ),
            FloatingMenuDisplayLayoutInput(
                displayID: "wide",
                frame: DisplayFrame(x: 1200, y: 0, width: 6000, height: 1440)
            )
        ],
        in: CGSize(width: 520, height: FloatingMenuDisplayArrangementLayout.stageHeight)
    )

    let tiny = placements.first { $0.displayID == "tiny" }!

    XCTAssertGreaterThanOrEqual(tiny.frame.width, FloatingMenuDisplayArrangementLayout.minimumDisplaySize.width)
    XCTAssertGreaterThanOrEqual(tiny.frame.height, FloatingMenuDisplayArrangementLayout.minimumDisplaySize.height)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter AppShellTests/testDisplayArrangementLayout
```

Expected: FAIL because `FloatingMenuDisplayArrangementLayout` and related types do not exist yet.

- [ ] **Step 3: Add the layout helper**

Add `import SidebyCore` at the top of `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift`, then add this helper before `FloatingMenuPanelLayout`:

```swift
public struct FloatingMenuDisplayLayoutInput: Equatable, Sendable {
    public let displayID: String
    public let frame: DisplayFrame

    public init(displayID: String, frame: DisplayFrame) {
        self.displayID = displayID
        self.frame = frame
    }
}

public struct FloatingMenuDisplayPlacement: Equatable, Sendable {
    public let displayID: String
    public let frame: CGRect

    public init(displayID: String, frame: CGRect) {
        self.displayID = displayID
        self.frame = frame
    }
}

public enum FloatingMenuDisplayArrangementLayout: Sendable {
    public static let stageHeight: CGFloat = 220
    public static let padding: CGFloat = 24
    public static let minimumDisplaySize = CGSize(width: 72, height: 46)

    public static func placements(
        for displays: [FloatingMenuDisplayLayoutInput],
        in size: CGSize,
        padding: CGFloat = Self.padding,
        minimumDisplaySize: CGSize = Self.minimumDisplaySize
    ) -> [FloatingMenuDisplayPlacement] {
        guard !displays.isEmpty else {
            return []
        }

        let minX = displays.map(\.frame.x).min() ?? 0
        let minY = displays.map(\.frame.y).min() ?? 0
        let maxX = displays.map { $0.frame.x + $0.frame.width }.max() ?? 1
        let maxY = displays.map { $0.frame.y + $0.frame.height }.max() ?? 1
        let unionWidth = max(maxX - minX, 1)
        let unionHeight = max(maxY - minY, 1)
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        let scale = min(
            availableWidth / CGFloat(unionWidth),
            availableHeight / CGFloat(unionHeight)
        )

        let rawPlacements = displays.map { display in
            let frame = display.frame
            let scaledFrame = CGRect(
                x: CGFloat(frame.x - minX) * scale,
                y: CGFloat(frame.y - minY) * scale,
                width: CGFloat(frame.width) * scale,
                height: CGFloat(frame.height) * scale
            )
            let fittedFrame = frameWithReadableMinimum(
                scaledFrame,
                minimumSize: minimumDisplaySize
            )
            return FloatingMenuDisplayPlacement(displayID: display.displayID, frame: fittedFrame)
        }

        let rawUnion = rawPlacements.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let overflowScale = min(
            1,
            availableWidth / max(rawUnion.width, 1),
            availableHeight / max(rawUnion.height, 1)
        )
        let scaledPlacements = rawPlacements.map { placement in
            FloatingMenuDisplayPlacement(
                displayID: placement.displayID,
                frame: scale(placement.frame, by: overflowScale, around: rawUnion.center)
            )
        }
        let scaledUnion = scaledPlacements.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let offset = CGPoint(
            x: (size.width - scaledUnion.width) / 2 - scaledUnion.minX,
            y: (size.height - scaledUnion.height) / 2 - scaledUnion.minY
        )

        return scaledPlacements.map { placement in
            FloatingMenuDisplayPlacement(
                displayID: placement.displayID,
                frame: placement.frame.offsetBy(dx: offset.x, dy: offset.y)
            )
        }
    }

    private static func frameWithReadableMinimum(
        _ frame: CGRect,
        minimumSize: CGSize
    ) -> CGRect {
        let width = max(frame.width, minimumSize.width)
        let height = max(frame.height, minimumSize.height)
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func scale(
        _ frame: CGRect,
        by scale: CGFloat,
        around center: CGPoint
    ) -> CGRect {
        CGRect(
            x: center.x + (frame.minX - center.x) * scale,
            y: center.y + (frame.minY - center.y) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
```

- [ ] **Step 4: Run tests to verify helper passes**

Run:

```bash
swift test --filter AppShellTests/testDisplayArrangementLayout
```

Expected: PASS for all three display arrangement layout tests.

### Task 2: Apply the Fit Helper to Move Targets

**Files:**
- Modify: `Sources/SidebyApp/SidebyApp.swift`

- [ ] **Step 1: Update `DisplayArrangementView` to use tested placements**

In `Sources/SidebyApp/SidebyApp.swift`, replace the geometry math inside `DisplayArrangementView.arrangedDisplays(in:)` with:

```swift
private func arrangedDisplays(in size: CGSize) -> some View {
    let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
    let placements = FloatingMenuDisplayArrangementLayout.placements(
        for: displays.compactMap { display in
            guard let frame = display.frame else {
                return nil
            }
            return FloatingMenuDisplayLayoutInput(displayID: display.id, frame: frame)
        },
        in: size
    )

    return ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))

        ForEach(placements, id: \.displayID) { placement in
            if let display = displaysByID[placement.displayID] {
                displayButton(
                    for: display,
                    size: placement.frame.size
                )
                .position(
                    x: placement.frame.midX,
                    y: placement.frame.midY
                )
            }
        }
    }
}
```

Also change the `GeometryReader` fixed height from `238` to:

```swift
.frame(height: FloatingMenuDisplayArrangementLayout.stageHeight)
```

Change the fallback background corner radius from `12` to `8` so it matches the arranged stage:

```swift
.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
```

- [ ] **Step 2: Soften thumbnail selection styling**

In `DisplayThumbnail.body`, reduce the selected glow so the map remains strong without overpowering the matrix:

```swift
.background {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .padding(-4)
}
.shadow(
    color: isSelected ? Color.accentColor.opacity(0.18) : .black.opacity(0.14),
    radius: isSelected ? 5 : 3,
    x: 0,
    y: isSelected ? 2 : 1
)
```

- [ ] **Step 3: Build SidebyApp**

Run:

```bash
swift build --product SidebyApp
```

Expected: build succeeds.

### Task 3: Make the Context Matrix Header Name-Forward

**Files:**
- Modify: `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift`
- Modify: `Sources/SidebyApp/SidebyApp.swift`
- Modify: `Tests/SidebyUITests/AppShellTests.swift`

- [ ] **Step 1: Write failing layout constant tests**

Update `testCompactContextMatrixUsesTwoThirdsContextColumnWidth` in `Tests/SidebyUITests/AppShellTests.swift` to assert the A2 widths:

```swift
func testCompactContextMatrixUsesReadableContextColumnWidth() {
    XCTAssertEqual(
        FloatingMenuContextMatrixLayout.contextColumnWidth(isCompact: true),
        156
    )
    XCTAssertEqual(
        FloatingMenuContextMatrixLayout.contextColumnWidth(isCompact: false),
        220
    )
}
```

Update `testCompactContextMatrixUsesShortSingleLineStatusLabels` to keep the status labels but remove the old header line limit assertion, then add:

```swift
func testContextMatrixHeaderNameLineLimitAllowsReadableNames() {
    XCTAssertEqual(FloatingMenuContextMatrixLayout.nameLineLimit(isCompact: true), 2)
    XCTAssertEqual(FloatingMenuContextMatrixLayout.nameLineLimit(isCompact: false), 2)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter AppShellTests/testCompactContextMatrixUsesReadableContextColumnWidth
swift test --filter AppShellTests/testContextMatrixHeaderNameLineLimitAllowsReadableNames
```

Expected: FAIL because the compact width is still old and `nameLineLimit` does not exist.

- [ ] **Step 3: Update matrix layout constants**

In `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift`, update the compact context width and add the name line limit helper:

```swift
public static func contextColumnWidth(isCompact: Bool) -> CGFloat {
    isCompact ? 156 : 220
}

public static func nameLineLimit(isCompact: Bool) -> Int {
    2
}
```

- [ ] **Step 4: Update `ContextsView` sizing**

In `Sources/SidebyApp/SidebyApp.swift`, update header height to make room for two-line names:

```swift
private var headerHeight: CGFloat { isCompact ? 92 : 98 }
private var rowHeight: CGFloat { isCompact ? 32 : 36 }
```

- [ ] **Step 5: Rewrite `contextHeader(_:)` as an A2 header**

Replace `contextHeader(_:)` in `Sources/SidebyApp/SidebyApp.swift` with:

```swift
private func contextHeader(_ column: ContextMatrixColumn) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
            Text(model.strings.contextOrder(column.order))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if let statusTitle = FloatingMenuContextMatrixLayout.statusTitle(
                for: column.state,
                isCompact: true,
                strings: model.strings
            ) {
                Text(statusTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(column.state == .needsSync ? .orange : Color.accentColor)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(column.state == .needsSync ? Color.orange.opacity(0.14) : Color.accentColor.opacity(0.14))
                    )
            }
        }

        TextField(
            model.strings.contextLabelPlaceholder,
            text: Binding(
                get: {
                    model.settings.contextPlan.contexts
                        .first { $0.id == column.id }?
                        .name ?? column.name
                },
                set: { model.setContextName(contextID: column.id, name: $0) }
            )
        )
        .textFieldStyle(.roundedBorder)
        .font(.caption.weight(.semibold))
        .lineLimit(FloatingMenuContextMatrixLayout.nameLineLimit(isCompact: isCompact))
        .help(column.name)

        Button(model.strings.goToContext) {
            model.activateContext(contextID: column.id)
        }
        .font(.caption2.weight(.semibold))
        .buttonStyle(.borderless)
        .lineLimit(1)
        .pointingHandCursor()
    }
    .frame(width: contextColumnWidth, height: headerHeight, alignment: .topLeading)
}
```

- [ ] **Step 6: Run focused UI tests**

Run:

```bash
swift test --filter AppShellTests
```

Expected: PASS.

### Task 4: Final Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Build product app**

Run:

```bash
swift build --product SidebyApp
```

Expected: build succeeds.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: app/UI layout files and UI tests only; no whitespace errors.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift Sources/SidebyApp/SidebyApp.swift Tests/SidebyUITests/AppShellTests.swift docs/superpowers/plans/2026-06-19-floating-menu-a2-context-matrix.md
git commit -m "feat: refine floating menu context matrix"
```

# Instant Context Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the context plan instantly by reading the per-display Space layout from SkyLight (read-only private API), with automatic fallback to the existing walk-based capture.

**Architecture:** A new `SpaceLayoutReading` protocol in SidebySystem wraps `SLSCopyManagedDisplaySpaces` behind a nil-on-failure reader; a pure SidebyCore planner converts per-display (count, current index) into `ContextDefinition`s; `startContextCapture` tries the instant path first and falls back to the unchanged walk pipeline.

**Tech Stack:** Swift Package (macOS), XCTest, dlopen/dlsym for SkyLight, CoreGraphics public APIs for display UUID mapping.

**Spec:** `docs/superpowers/specs/2026-06-13-instant-context-capture-design.md`

---

### Task 1: DisplaySpaceLayout model + payload parsing (pure)

**Files:**
- Create: `Sources/SidebySystem/Spaces/SpaceLayoutReader.swift`
- Test: `Tests/SidebySystemTests/SpaceLayoutReaderTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SidebySystem

final class SpaceLayoutReaderTests: XCTestCase {
    func testParsesManagedDisplaySpacesPayload() {
        let payload: [[String: Any]] = [
            [
                "Display Identifier": "29047B54-6562-49DE-AA42-F7A696BE4F6B",
                "Current Space": ["ManagedSpaceID": NSNumber(value: 959)],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: 1)],
                    ["ManagedSpaceID": NSNumber(value: 928)],
                    ["ManagedSpaceID": NSNumber(value: 959)]
                ]
            ],
            [
                "Display Identifier": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
                "Current Space": ["ManagedSpaceID": NSNumber(value: 932)],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: 941)],
                    ["ManagedSpaceID": NSNumber(value: 932)]
                ]
            ]
        ]

        let layouts = DisplaySpaceLayout.displays(fromManagedDisplaySpaces: payload)

        XCTAssertEqual(layouts, [
            DisplaySpaceLayout(
                displayUUID: "29047B54-6562-49DE-AA42-F7A696BE4F6B",
                spaceIDs: [1, 928, 959],
                currentSpaceID: 959
            ),
            DisplaySpaceLayout(
                displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
                spaceIDs: [941, 932],
                currentSpaceID: 932
            )
        ])
    }

    func testParsingFailsWhenAnyEntryIsMalformed() {
        let missingCurrent: [[String: Any]] = [
            [
                "Display Identifier": "A",
                "Spaces": [["ManagedSpaceID": NSNumber(value: 1)]]
            ]
        ]
        let emptySpaces: [[String: Any]] = [
            [
                "Display Identifier": "A",
                "Current Space": ["ManagedSpaceID": NSNumber(value: 1)],
                "Spaces": [[String: Any]]()
            ]
        ]

        XCTAssertNil(DisplaySpaceLayout.displays(fromManagedDisplaySpaces: missingCurrent))
        XCTAssertNil(DisplaySpaceLayout.displays(fromManagedDisplaySpaces: emptySpaces))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SpaceLayoutReaderTests`
Expected: compile error — `DisplaySpaceLayout` not defined (feature missing).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct DisplaySpaceLayout: Equatable, Sendable {
    public let displayUUID: String
    public let spaceIDs: [UInt64]
    public let currentSpaceID: UInt64

    public init(displayUUID: String, spaceIDs: [UInt64], currentSpaceID: UInt64) {
        self.displayUUID = displayUUID
        self.spaceIDs = spaceIDs
        self.currentSpaceID = currentSpaceID
    }

    /// Parses the bridged payload of SLSCopyManagedDisplaySpaces. Returns nil
    /// if any entry is malformed — never a partial layout.
    public static func displays(
        fromManagedDisplaySpaces payload: [[String: Any]]
    ) -> [DisplaySpaceLayout]? {
        var layouts: [DisplaySpaceLayout] = []
        for entry in payload {
            guard
                let uuid = entry["Display Identifier"] as? String,
                let current = entry["Current Space"] as? [String: Any],
                let currentID = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                let spaces = entry["Spaces"] as? [[String: Any]],
                !spaces.isEmpty
            else {
                return nil
            }

            var spaceIDs: [UInt64] = []
            for space in spaces {
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else {
                    return nil
                }
                spaceIDs.append(id)
            }
            layouts.append(
                DisplaySpaceLayout(
                    displayUUID: uuid,
                    spaceIDs: spaceIDs,
                    currentSpaceID: currentID
                )
            )
        }
        return layouts
    }
}

public protocol SpaceLayoutReading: Sendable {
    /// Returns the per-display Space layout, or nil when unavailable.
    func readLayout() -> [DisplaySpaceLayout]?
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SpaceLayoutReaderTests`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidebySystem/Spaces/SpaceLayoutReader.swift Tests/SidebySystemTests/SpaceLayoutReaderTests.swift
git commit -m "feat: parse managed display space layout payload"
```

---

### Task 2: SLSSpaceLayoutReader (SkyLight bridge)

**Files:**
- Modify: `Sources/SidebySystem/Spaces/SpaceLayoutReader.swift` (append)
- Test: `Tests/SidebySystemTests/SpaceLayoutReaderTests.swift` (append)

- [ ] **Step 1: Write the failing smoke test**

```swift
    func testSLSReaderReturnsCoherentLayoutOrNil() {
        guard let layouts = SLSSpaceLayoutReader().readLayout() else {
            // SLS unavailable on this machine/OS — acceptable per spec.
            return
        }

        XCTAssertFalse(layouts.isEmpty)
        for layout in layouts {
            XCTAssertFalse(layout.spaceIDs.isEmpty)
            XCTAssertTrue(layout.spaceIDs.contains(layout.currentSpaceID))
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testSLSReaderReturnsCoherentLayoutOrNil`
Expected: compile error — `SLSSpaceLayoutReader` not defined.

- [ ] **Step 3: Write minimal implementation (append to SpaceLayoutReader.swift)**

```swift
public struct SLSSpaceLayoutReader: SpaceLayoutReading {
    public init() {}

    public func readLayout() -> [DisplaySpaceLayout]? {
        guard let symbols = Self.symbols else {
            return nil
        }
        guard
            let raw = symbols.copyManagedDisplaySpaces(symbols.mainConnectionID())?
                .takeRetainedValue(),
            let payload = raw as? [[String: Any]]
        else {
            return nil
        }
        return DisplaySpaceLayout.displays(fromManagedDisplaySpaces: payload)
    }

    private struct Symbols {
        let mainConnectionID: @convention(c) () -> UInt32
        let copyManagedDisplaySpaces: @convention(c) (UInt32) -> Unmanaged<CFArray>?
    }

    private static let symbols: Symbols? = {
        guard
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                RTLD_NOW
            ),
            let mainPointer = dlsym(handle, "SLSMainConnectionID"),
            let copyPointer = dlsym(handle, "SLSCopyManagedDisplaySpaces")
        else {
            return nil
        }
        return Symbols(
            mainConnectionID: unsafeBitCast(
                mainPointer,
                to: (@convention(c) () -> UInt32).self
            ),
            copyManagedDisplaySpaces: unsafeBitCast(
                copyPointer,
                to: (@convention(c) (UInt32) -> Unmanaged<CFArray>?).self
            )
        )
    }()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testSLSReaderReturnsCoherentLayoutOrNil`
Expected: PASS (on this machine the reader returns real data; the probe already proved 5/3).

- [ ] **Step 5: Commit**

```bash
git add Sources/SidebySystem/Spaces/SpaceLayoutReader.swift Tests/SidebySystemTests/SpaceLayoutReaderTests.swift
git commit -m "feat: read space layout from SkyLight with nil fallback"
```

---

### Task 3: Display UUID → stableID mapping

**Files:**
- Modify: `Sources/SidebySystem/Displays/DisplayObserver.swift` (append to `DisplayLayoutMapper` area)
- Test: `Tests/SidebySystemTests/SystemAdapterTests.swift` (append)

- [ ] **Step 1: Write the failing test**

```swift
    func testStableIDsByUUIDMapsResolvableSnapshots() {
        let snapshotA = DisplaySnapshot(
            displayID: 2,
            name: "FA2440P",
            isPrimary: true,
            isBuiltin: false,
            vendorNumber: 23598,
            modelNumber: 9216,
            serialNumber: 0
        )
        let snapshotB = DisplaySnapshot(
            displayID: 1,
            name: "Built-in",
            isPrimary: false,
            isBuiltin: true,
            vendorNumber: 1552,
            modelNumber: 41038,
            serialNumber: 4251086178
        )

        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: [snapshotA, snapshotB],
            uuidForDisplayID: { displayID in
                displayID == 2 ? "UUID-EXT" : nil
            }
        )

        XCTAssertEqual(mapping, ["UUID-EXT": "23598-9216-0-2"])
    }
```

Note: check `DisplaySnapshot`'s memberwise init parameter order in
`Sources/SidebySystem/Displays/DisplayObserver.swift` before writing; adjust
labels to match (it includes `frame` with a default).

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testStableIDsByUUIDMapsResolvableSnapshots`
Expected: compile error — `stableIDsByUUID` not defined.

- [ ] **Step 3: Write minimal implementation (append to DisplayLayoutMapper)**

```swift
    public static func stableIDsByUUID(
        snapshots: [DisplaySnapshot],
        uuidForDisplayID: (CGDirectDisplayID) -> String?
    ) -> [String: String] {
        var mapping: [String: String] = [:]
        for snapshot in snapshots {
            guard let uuid = uuidForDisplayID(snapshot.displayID) else {
                continue
            }
            mapping[uuid] = stableID(for: snapshot)
        }
        return mapping
    }

    public static func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String?
    }
```

(If `snapshot.displayID` is not `CGDirectDisplayID`, match its actual type.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testStableIDsByUUIDMapsResolvableSnapshots`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidebySystem/Displays/DisplayObserver.swift Tests/SidebySystemTests/SystemAdapterTests.swift
git commit -m "feat: map display UUIDs to stable IDs"
```

---

### Task 4: Instant plan derivation (SidebyCore, pure)

**Files:**
- Create: `Sources/SidebyCore/Contexts/InstantContextCapturePlanner.swift`
- Test: `Tests/SidebyCoreTests/InstantContextCapturePlannerTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SidebyCore

final class InstantContextCapturePlannerTests: XCTestCase {
    func testAsymmetricDisplaysGetExactMembership() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 2),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ])

        XCTAssertEqual(plan?.contexts.count, 5)
        XCTAssertEqual(plan?.contexts[2].displayIDs.sorted(), ["builtin", "ext"])
        XCTAssertEqual(plan?.contexts[3].displayIDs, ["ext"])
        XCTAssertEqual(plan?.contexts[4].displayIDs, ["ext"])
        XCTAssertEqual(plan?.captureLimit, 5)
    }

    func testAgreedCurrentIndexIsSynchronizedCurrentContext() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 2),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ])

        XCTAssertEqual(plan?.currentContextID, "context-3")
        XCTAssertEqual(plan?.isSynchronized, true)
    }

    func testDisagreeingCurrentIndexesAreNotSynchronized() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 4),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1)
        ])

        XCTAssertEqual(plan?.currentContextID, "context-5")
        XCTAssertEqual(plan?.isSynchronized, false)
    }

    func testContextCountIsCappedAtTwelve() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 30, currentSpaceIndex: 0)
        ])

        XCTAssertEqual(plan?.contexts.count, 12)
        XCTAssertEqual(plan?.captureLimit, 12)
    }

    func testDefaultNamesAndIdentifiersFollowOrder() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "only", spaceCount: 2, currentSpaceIndex: 0)
        ])

        XCTAssertEqual(plan?.contexts.map(\.id), ["context-1", "context-2"])
        XCTAssertEqual(plan?.contexts.map(\.name), ["Context 1", "Context 2"])
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(InstantContextCapturePlanner.plan(for: []))
        XCTAssertNil(InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "x", spaceCount: 0, currentSpaceIndex: 0)
        ]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter InstantContextCapturePlannerTests`
Expected: compile error — types not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
public struct InstantCaptureDisplay: Equatable, Sendable {
    public let displayID: String
    public let spaceCount: Int
    /// 0-based index of the display's current Space.
    public let currentSpaceIndex: Int

    public init(displayID: String, spaceCount: Int, currentSpaceIndex: Int) {
        self.displayID = displayID
        self.spaceCount = spaceCount
        self.currentSpaceIndex = currentSpaceIndex
    }
}

public struct InstantCapturePlan: Equatable, Sendable {
    public let contexts: [ContextDefinition]
    public let currentContextID: String
    public let captureLimit: Int
    /// True when every display reports the same current Space index.
    public let isSynchronized: Bool

    public init(
        contexts: [ContextDefinition],
        currentContextID: String,
        captureLimit: Int,
        isSynchronized: Bool
    ) {
        self.contexts = contexts
        self.currentContextID = currentContextID
        self.captureLimit = captureLimit
        self.isSynchronized = isSynchronized
    }
}

public enum InstantContextCapturePlanner {
    public static let maxContexts = 12

    public static func plan(for displays: [InstantCaptureDisplay]) -> InstantCapturePlan? {
        guard !displays.isEmpty,
              displays.allSatisfy({ $0.spaceCount >= 1 })
        else {
            return nil
        }

        let contextCount = min(
            displays.map(\.spaceCount).max() ?? 1,
            Self.maxContexts
        )
        let contexts = (1...contextCount).map { order in
            ContextDefinition(
                id: "context-\(order)",
                order: order,
                name: "Context \(order)",
                displayIDs: displays
                    .filter { $0.spaceCount >= order }
                    .map(\.displayID)
            )
        }

        let firstIndex = displays[0].currentSpaceIndex
        let currentOrder = min(max(firstIndex + 1, 1), contextCount)
        let isSynchronized = displays
            .allSatisfy { $0.currentSpaceIndex == firstIndex }

        return InstantCapturePlan(
            contexts: contexts,
            currentContextID: "context-\(currentOrder)",
            captureLimit: contextCount,
            isSynchronized: isSynchronized
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter InstantContextCapturePlannerTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidebyCore/Contexts/InstantContextCapturePlanner.swift Tests/SidebyCoreTests/InstantContextCapturePlannerTests.swift
git commit -m "feat: derive instant capture plan from space layout"
```

---

### Task 5: App wiring with walk fallback

**Files:**
- Modify: `Sources/SidebyApp/SidebyApp.swift` — `startContextCapture()` (~line 965) and the private-state area (~line 697)

No new unit test (SidebyAppModel is app-private); covered by Tasks 1–4 plus the manual verification in Task 6. Keep this layer thin.

- [ ] **Step 1: Add the reader to the model (near `visibleAppSuggestionProvider`, ~line 697)**

```swift
    private let spaceLayoutReader: any SpaceLayoutReading = SLSSpaceLayoutReader()
```

- [ ] **Step 2: Add the instant-capture method (near `startContextCapture`)**

```swift
    /// Builds the context plan directly from the Space layout. Returns false
    /// when the layout is unavailable so the caller can fall back to the
    /// walk-based capture.
    private func startInstantContextCapture() -> Bool {
        guard let layouts = spaceLayoutReader.readLayout(), !layouts.isEmpty else {
            return false
        }

        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: MacDisplayObserver().currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )
        let layoutsByStableID: [String: DisplaySpaceLayout] = layouts.reduce(into: [:]) {
            result, layout in
            if let stableID = mapping[layout.displayUUID] {
                result[stableID] = layout
            }
        }

        var captureDisplays: [InstantCaptureDisplay] = []
        for display in displayLayout.displays where selectedDisplayIDs.contains(display.id) {
            guard let layout = layoutsByStableID[display.id],
                  let currentIndex = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
            else {
                return false
            }
            captureDisplays.append(
                InstantCaptureDisplay(
                    displayID: display.id,
                    spaceCount: layout.spaceIDs.count,
                    currentSpaceIndex: currentIndex
                )
            )
        }

        guard let instantPlan = InstantContextCapturePlanner.plan(for: captureDisplays) else {
            return false
        }

        let currentName = suggestedContextName(
            order: instantPlan.contexts.first { $0.id == instantPlan.currentContextID }?.order ?? 1
        )
        let contexts = instantPlan.contexts.map { context in
            context.id == instantPlan.currentContextID
                ? ContextDefinition(
                    id: context.id,
                    order: context.order,
                    name: currentName,
                    displayIDs: context.displayIDs
                )
                : context
        }

        contextsToCapture = instantPlan.captureLimit
        updateContextPlan { plan in
            plan.replaceContexts(
                contexts,
                currentContextID: instantPlan.currentContextID,
                captureLimit: instantPlan.captureLimit
            )
            if !instantPlan.isSynchronized {
                plan.markNeedsSync()
            }
        }
        contextCaptureStatus = strings.contextCaptureReadySummary(
            count: contexts.count,
            currentName: settings.contextPlan.currentContext?.name ?? currentName
        )
        Self.contextCaptureLog.notice(
            "instant-capture displays=\(captureDisplays.count, privacy: .public) contexts=\(contexts.count, privacy: .public) synchronized=\(instantPlan.isSynchronized, privacy: .public)"
        )
        return true
    }
```

- [ ] **Step 3: Call it from `startContextCapture()` after the existing guards**

Insert between the `guard !isSwitching, contextCaptureSession == nil` block and
the `contextCaptureSessionID += 1` line:

```swift
        if startInstantContextCapture() {
            return
        }
        // SLS unavailable — fall back to the walk-based capture below.
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass (300+).

- [ ] **Step 5: Commit**

```bash
git add Sources/SidebyApp/SidebyApp.swift
git commit -m "feat: instant context capture with walk fallback"
```

---

### Task 6: End-to-end verification on this machine

**Files:** none (verification)

- [ ] **Step 1: Rebuild the app bundle and relaunch**

```bash
osascript -e 'tell application "Sideby" to quit' 2>/dev/null; sleep 1
pkill -f "dist/Sideby.app" 2>/dev/null
bash scripts/build_app_bundle.sh && open dist/Sideby.app
```

- [ ] **Step 2: User runs capture**

Expected: completion is instant (no Space walking, no screen movement),
matrix shows external display in 5 contexts and built-in in 3 (contexts 1–3),
status line shows the ready summary, Move by Contexts is on.

- [ ] **Step 3: Check the log line**

```bash
/usr/bin/log show --last 5m --info --predicate 'subsystem == "dev.sideby.Sideby"' --style compact | tail -5
```

Expected: one `instant-capture displays=2 contexts=5 synchronized=...` line,
no align/forward press lines.

- [ ] **Step 4: Final commit if any fixups were needed**

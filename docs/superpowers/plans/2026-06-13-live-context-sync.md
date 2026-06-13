# Live Context Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-track the current context from the live Space layout, and add an "Align Displays" action that physically moves the other displays to the context of the Space the user is looking at.

**Architecture:** A pure SidebyCore matcher decides which context is on screen; the external-space-change handler tracks it (replacing the pause when the SLS reader is available); a SidebySystem step acknowledger verifies alignment presses by polling the CGS layout; buttons live in the capture controls and the needsSync diagnostic.

**Tech Stack:** Swift Package (macOS), XCTest.

**Spec:** `docs/superpowers/specs/2026-06-13-live-context-sync-design.md`

---

### Task 1: ContextCurrentMatcher (SidebyCore, pure)

**Files:**
- Create: `Sources/SidebyCore/Contexts/ContextCurrentMatcher.swift`
- Test: `Tests/SidebyCoreTests/ContextCurrentMatcherTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SidebyCore

final class ContextCurrentMatcherTests: XCTestCase {
    private let contexts = [
        ContextDefinition(id: "context-1", order: 1, name: "C1", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-2", order: 2, name: "C2", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-3", order: 3, name: "C3", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-4", order: 4, name: "C4", displayIDs: ["ext"]),
        ContextDefinition(id: "context-5", order: 5, name: "C5", displayIDs: ["ext"])
    ]

    func testMatchesWhenAllConnectedMembersAgree() {
        XCTAssertEqual(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["ext": 1, "builtin": 1]
            ),
            "context-2"
        )
    }

    func testNonMemberDisplayIsUnconstrained() {
        XCTAssertEqual(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["ext": 3, "builtin": 2]
            ),
            "context-4"
        )
    }

    func testMismatchedCombinationReturnsNil() {
        XCTAssertNil(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["ext": 2, "builtin": 1]
            )
        )
    }

    func testDisconnectedMembersAreIgnored() {
        XCTAssertEqual(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["builtin": 0]
            ),
            "context-1"
        )
    }

    func testNoConnectedMemberMeansNoMatch() {
        XCTAssertNil(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["other": 0]
            )
        )
    }

    func testEmptyInputsReturnNil() {
        XCTAssertNil(ContextCurrentMatcher.currentContextID(contexts: [], displayIndexes: ["ext": 0]))
        XCTAssertNil(ContextCurrentMatcher.currentContextID(contexts: contexts, displayIndexes: [:]))
    }
}
```

- [ ] **Step 2: Run to verify RED** — `swift test --filter ContextCurrentMatcherTests` → compile error (type missing).

- [ ] **Step 3: Minimal implementation**

```swift
public enum ContextCurrentMatcher {
    /// Returns the context whose connected member displays all sit at the
    /// context's Space index (order - 1). Displays that are not members of a
    /// context never constrain it; a context with no connected member cannot
    /// match. Membership is monotonic across orders, so at most one context
    /// matches.
    public static func currentContextID(
        contexts: [ContextDefinition],
        displayIndexes: [String: Int]
    ) -> String? {
        for context in contexts {
            let connectedMembers = context.displayIDs.filter { displayIndexes[$0] != nil }
            guard !connectedMembers.isEmpty else {
                continue
            }
            let expectedIndex = context.order - 1
            if connectedMembers.allSatisfy({ displayIndexes[$0] == expectedIndex }) {
                return context.id
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run to verify GREEN** — 6 passes, then `swift build`.
- [ ] **Step 5: Commit** (`git add` ONLY the two files)

```bash
git add Sources/SidebyCore/Contexts/ContextCurrentMatcher.swift Tests/SidebyCoreTests/ContextCurrentMatcherTests.swift
git commit -m "feat: match current context from live space indexes"
```

---

### Task 2: shouldTrackCurrentContext policy (SidebyCore)

**Files:**
- Modify: `Sources/SidebyCore/Contexts/ExternalSpaceChangeContextPolicy.swift`
- Test: `Tests/SidebyCoreTests/ContextPlanTests.swift` (append; existing shouldPauseContextMatching tests live near the end — Grep first)

- [ ] **Step 1: Write the failing tests** (append to the test class that covers ExternalSpaceChangeContextPolicy — find it with `grep -rn "shouldPauseContextMatching" Tests/`):

```swift
    func testShouldTrackCurrentContextRequiresEnabledAndPinned() {
        var plan = ContextPlan.default

        XCTAssertTrue(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: true, plan: plan)
        )
        XCTAssertFalse(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: false, plan: plan)
        )

        plan.setPinned(false)
        XCTAssertFalse(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: true, plan: plan)
        )
    }

    func testShouldTrackCurrentContextEvenWhenNeedsSync() {
        var plan = ContextPlan.default
        plan.markNeedsSync()

        XCTAssertTrue(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: true, plan: plan)
        )
    }
```

- [ ] **Step 2: RED** — `swift test --filter ShouldTrackCurrentContext` → compile error.
- [ ] **Step 3: Implementation** (append to the enum; keep `shouldPauseContextMatching` unchanged):

```swift
    /// Live tracking runs even when the plan needs sync (so it can
    /// self-heal), unlike pausing which only fires from a synchronized state.
    public static func shouldTrackCurrentContext(
        isSidebyEnabled: Bool,
        plan: ContextPlan
    ) -> Bool {
        isSidebyEnabled
            && plan.isPinned
            && !plan.contexts.isEmpty
    }
```

- [ ] **Step 4: GREEN** — both tests pass; full `swift test` still green.
- [ ] **Step 5: Commit**

```bash
git add Sources/SidebyCore/Contexts/ExternalSpaceChangeContextPolicy.swift Tests/SidebyCoreTests/ContextPlanTests.swift
git commit -m "feat: add live-tracking gate to external space change policy"
```

---

### Task 3: SpaceLayoutStepAcknowledger (SidebySystem)

**Files:**
- Create: `Sources/SidebySystem/Spaces/SpaceLayoutStepAcknowledger.swift`
- Test: `Tests/SidebySystemTests/SpaceLayoutStepAcknowledgerTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SidebySystem

final class SpaceLayoutStepAcknowledgerTests: XCTestCase {
    func testReturnsNewIndexOnceItChanges() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)
        var calls = 0

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 1.0
        ) {
            calls += 1
            return calls < 3 ? ["ext": 2] : ["ext": 3]
        }

        XCTAssertEqual(newIndex, 3)
    }

    func testTimesOutWhenIndexNeverChanges() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 0.05
        ) {
            ["ext": 2]
        }

        XCTAssertNil(newIndex)
    }

    func testUnavailableReaderTimesOut() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 0.05
        ) {
            nil
        }

        XCTAssertNil(newIndex)
    }
}
```

- [ ] **Step 2: RED** — compile error.
- [ ] **Step 3: Implementation**

```swift
import Foundation

/// Confirms a single space-switch press by polling current Space indexes
/// until the target display's index changes or the deadline passes.
/// Blocking — call off the main thread.
public struct SpaceLayoutStepAcknowledger: Sendable {
    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 0.05) {
        self.pollInterval = max(pollInterval, 0.001)
    }

    public func waitForIndexChange(
        of displayID: String,
        from previousIndex: Int,
        timeout: TimeInterval,
        readIndexes: () -> [String: Int]?
    ) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let index = readIndexes()?[displayID], index != previousIndex {
                return index
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                return nil
            }
            Thread.sleep(forTimeInterval: min(pollInterval, remaining))
        }
    }
}
```

- [ ] **Step 4: GREEN** — 3 passes; `swift build`.
- [ ] **Step 5: Commit**

```bash
git add Sources/SidebySystem/Spaces/SpaceLayoutStepAcknowledger.swift Tests/SidebySystemTests/SpaceLayoutStepAcknowledgerTests.swift
git commit -m "feat: acknowledge space steps by polling layout indexes"
```

---

### Task 4: Strings (SidebyUI)

**Files:**
- Modify: `Sources/SidebyUI/Shared/SBSStrings.swift`
- Test: `Tests/SidebyUITests/AppShellTests.swift` (append)

- [ ] **Step 1: Failing test** (append to AppShellTests):

```swift
    func testAlignAndTrackingStringsLocalize() {
        let korean = SBSStrings(language: .korean)
        let english = SBSStrings(language: .english)

        XCTAssertEqual(english.alignDisplays, "Align Displays")
        XCTAssertEqual(korean.alignDisplays, "컨텍스트 맞추기")
        XCTAssertEqual(korean.alignedToContext("Docs"), "Docs에 맞췄습니다")
        XCTAssertEqual(english.alignedToContext("Docs"), "Aligned to Docs")
        XCTAssertEqual(korean.alignFailed, "맞추지 못했습니다 — 컨텍스트를 다시 캡처해 주세요")
        XCTAssertEqual(english.followingContext("Docs"), "Following Docs")
        XCTAssertEqual(korean.localizedActionLabel("Align Displays"), "컨텍스트 맞추기")
    }
```

- [ ] **Step 2: RED** — compile error.
- [ ] **Step 3: Implementation** — add near the other context strings (e.g. after `contextCaptureReadySummary`):

```swift
    public var alignDisplays: String { text("Align Displays", "컨텍스트 맞추기") }

    public func alignedToContext(_ name: String) -> String {
        text("Aligned to \(name)", "\(name)에 맞췄습니다")
    }

    public var alignFailed: String {
        text("Couldn't align — capture Contexts again", "맞추지 못했습니다 — 컨텍스트를 다시 캡처해 주세요")
    }

    public func followingContext(_ name: String) -> String {
        text("Following \(name)", "\(name) 따라가는 중")
    }
```

And in `localizedActionLabel(_:)`, add a case BEFORE `case .some(let label)`:

```swift
        case "Align Displays":
            alignDisplays
```

- [ ] **Step 4: GREEN**; full `swift test` green.
- [ ] **Step 5: Commit**

```bash
git add Sources/SidebyUI/Shared/SBSStrings.swift Tests/SidebyUITests/AppShellTests.swift
git commit -m "feat: add align and tracking strings"
```

---

### Task 5: Extract layout helper + auto-tracking (SidebyApp)

**Files:**
- Modify: `Sources/SidebyApp/SidebyApp.swift` only.

No new unit test (app-private model); Tasks 1–3 cover the logic; Task 7 verifies E2E. Build + full suite must stay green.

- [ ] **Step 1: Extract the layout snapshot helper.** In `startInstantContextCapture()` (search for it), the block from `guard let layouts = spaceLayoutReader.readLayout()` through building `captureDisplays` becomes a reusable method on SidebyAppModel; `startInstantContextCapture` then starts with:

```swift
        guard let captureDisplays = selectedDisplaySpaces(), !captureDisplays.isEmpty else {
            return false
        }
```

New method (place directly above `startInstantContextCapture`):

```swift
    /// Reads the live Space layout for the selected displays, in layout
    /// order. Returns nil when the SLS reader is unavailable or any selected
    /// display cannot be mapped.
    private func selectedDisplaySpaces() -> [InstantCaptureDisplay]? {
        guard let layouts = spaceLayoutReader.readLayout(), !layouts.isEmpty else {
            return nil
        }

        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )
        let layoutsByStableID: [String: DisplaySpaceLayout] = layouts.reduce(into: [:]) {
            result, layout in
            if let stableID = mapping[layout.displayUUID] {
                result[stableID] = layout
            }
        }

        var displays: [InstantCaptureDisplay] = []
        for display in displayLayout.displays where selectedDisplayIDs.contains(display.id) {
            guard let layout = layoutsByStableID[display.id],
                  let currentIndex = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
            else {
                return nil
            }
            displays.append(
                InstantCaptureDisplay(
                    displayID: display.id,
                    spaceCount: layout.spaceIDs.count,
                    currentSpaceIndex: currentIndex
                )
            )
        }
        return displays
    }
```

(`startInstantContextCapture`'s own guards on planner nil etc. stay as they are.)

- [ ] **Step 2: Rewrite `handleExternalSpaceChange()`** — keep the first two guard blocks (isSwitching/capture ignore-extension, ignore window) byte-identical, then replace the pause-only tail with tracking + fallback:

```swift
        let plan = settings.contextPlan
        if ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(
            isSidebyEnabled: isEnabled,
            plan: plan
        ),
            let displays = selectedDisplaySpaces() {
            let indexes = Dictionary(
                uniqueKeysWithValues: displays.map { ($0.displayID, $0.currentSpaceIndex) }
            )
            if let matchedID = ContextCurrentMatcher.currentContextID(
                contexts: plan.contexts,
                displayIndexes: indexes
            ) {
                if matchedID != plan.currentContextID || plan.syncState != .synchronized {
                    updateContextPlan { plan in
                        _ = plan.setCurrentContext(id: matchedID)
                    }
                    lastSwitchResult = strings.followingContext(
                        settings.contextPlan.currentContext?.name ?? matchedID
                    )
                }
            } else if plan.syncState == .synchronized {
                updateContextPlan { plan in
                    plan.markNeedsSync()
                }
                lastSwitchResult = strings.contextMatchingPaused
            }
            diagnostics = currentDiagnostics()
            return
        }

        guard ExternalSpaceChangeContextPolicy.shouldPauseContextMatching(
            isSidebyEnabled: isEnabled,
            plan: settings.contextPlan
        ) else {
            return
        }

        updateContextPlan { plan in
            plan.pauseContextMatchingForUnsynchronizedMovement()
        }

        diagnostics = currentDiagnostics()
        lastSwitchResult = strings.contextMatchingPaused
```

- [ ] **Step 3: Verify** — `swift build && swift test 2>&1 | tail -3` (all green; this is a refactor + new branch, existing behavior covered by suite).
- [ ] **Step 4: Commit**

```bash
git add Sources/SidebyApp/SidebyApp.swift
git commit -m "feat: track current context from live space layout"
```

---

### Task 6: Align action + buttons (SidebyApp)

**Files:**
- Modify: `Sources/SidebyApp/SidebyApp.swift` only.

- [ ] **Step 1: Reference display helper** (near `selectedDisplaySpaces()`):

```swift
    /// Display hosting the Sideby window, falling back to the display under
    /// the cursor. Used as the alignment reference ("the screen the button
    /// was pressed on").
    private func alignmentReferenceDisplayID() -> String? {
        let snapshots = displayObserver.currentSnapshots()
        func stableID(for screen: NSScreen?) -> String? {
            guard
                let number = screen?.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber,
                let snapshot = snapshots.first(where: { $0.displayID == number.uint32Value })
            else {
                return nil
            }
            return DisplayLayoutMapper.stableID(for: snapshot)
        }

        if let windowScreen = NSApp.keyWindow?.screen, let id = stableID(for: windowScreen) {
            return id
        }
        let mouseLocation = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
        return stableID(for: cursorScreen)
    }
```

- [ ] **Step 2: The align action** (near `setCurrentContext`):

```swift
    func alignDisplaysToCurrentSpace() {
        guard !isSwitching, contextCaptureSession == nil else {
            return
        }
        guard let displays = selectedDisplaySpaces(), !displays.isEmpty else {
            lastSwitchResult = strings.alignFailed
            return
        }

        let referenceID = alignmentReferenceDisplayID() ?? displays[0].displayID
        let reference = displays.first { $0.displayID == referenceID } ?? displays[0]
        let targetOrder = reference.currentSpaceIndex + 1
        guard let target = settings.contextPlan.contexts.first(where: { $0.order == targetOrder }) else {
            lastSwitchResult = strings.alignFailed
            return
        }

        let moves = displays.filter { display in
            display.displayID != reference.displayID
                && target.displayIDs.contains(display.displayID)
                && display.currentSpaceIndex != targetOrder - 1
        }

        guard !moves.isEmpty else {
            updateContextPlan { plan in
                _ = plan.setCurrentContext(id: target.id)
            }
            lastSwitchResult = strings.alignedToContext(
                settings.contextPlan.currentContext?.name ?? target.name
            )
            diagnostics = currentDiagnostics()
            return
        }

        isSwitching = true
        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(30)
        switchSessionID += 1
        let sessionID = switchSessionID
        let reader = spaceLayoutReader
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )
        let targetIndex = targetOrder - 1

        DispatchQueue.global(qos: .userInitiated).async {
            func readIndexes() -> [String: Int]? {
                guard let layouts = reader.readLayout() else {
                    return nil
                }
                var indexes: [String: Int] = [:]
                for layout in layouts {
                    guard let stableID = mapping[layout.displayUUID],
                          let index = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
                    else {
                        continue
                    }
                    indexes[stableID] = index
                }
                return indexes
            }

            let acknowledger = SpaceLayoutStepAcknowledger()
            var didAlignAll = true

            for move in moves {
                var index = move.currentSpaceIndex
                while index != targetIndex {
                    let command: SwitchCommand = index < targetIndex ? .next : .previous
                    let targetProvider = CGDisplaySwitchTargetProvider(
                        includedStableIDs: [move.displayID]
                    )
                    let executor = HiddenCursorDisplaySpaceCommandExecutor(
                        baseExecutor: MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
                        targetProvider: targetProvider
                    )
                    guard executor.execute(command),
                          let newIndex = acknowledger.waitForIndexChange(
                              of: move.displayID,
                              from: index,
                              timeout: 1.0,
                              readIndexes: readIndexes
                          )
                    else {
                        didAlignAll = false
                        break
                    }
                    index = newIndex
                }
                if !didAlignAll {
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.switchSessionID == sessionID else {
                    return
                }
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)
                if didAlignAll {
                    self.updateContextPlan { plan in
                        _ = plan.setCurrentContext(id: target.id)
                    }
                    self.lastSwitchResult = self.strings.alignedToContext(
                        self.settings.contextPlan.currentContext?.name ?? target.name
                    )
                } else {
                    self.updateContextPlan { plan in
                        plan.markNeedsSync()
                    }
                    self.lastSwitchResult = self.strings.alignFailed
                }
                self.diagnostics = self.currentDiagnostics()
                Self.contextCaptureLog.notice(
                    "align-displays target=\(target.id, privacy: .public) moved=\(moves.count, privacy: .public) success=\(didAlignAll, privacy: .public)"
                )
            }
        }
    }
```

(`SwitchCommand` values: check the enum — the codebase uses `.next` / `.previous`. `HiddenCursorDisplaySpaceCommandExecutor`'s init takes `baseExecutor:targetProvider:` plus optional delays. Verify both before building; adapt minimally and report adaptations.)

- [ ] **Step 3: needsSync diagnostic action.** In `currentDiagnostics()` (search for `syncState == .needsSync`), replace the plain append with a copy carrying the action label:

```swift
        if settings.contextPlan.isPinned,
           settings.contextPlan.syncState == .needsSync,
           let diagnostic = settings.contextPlan.navigation(for: .next).diagnostic {
            values.append(
                DiagnosticState(
                    severity: diagnostic.severity,
                    title: diagnostic.title,
                    message: diagnostic.message,
                    actionLabel: "Align Displays"
                )
            )
        }
```

- [ ] **Step 4: Buttons.**

In `ContextCaptureControlsView.content(strings:)`, inside the HStack after the capture/stop button, add:

```swift
                Button(strings.alignDisplays) {
                    model.alignDisplaysToCurrentSpace()
                }
                .buttonStyle(.bordered)
                .disabled(model.isSwitching || model.contextCaptureSession != nil)
                .pointingHandCursor()
```

(`isSwitching` / `contextCaptureSession` must be readable from the view — check their access level on SidebyAppModel; they are used by views already via `model.` in this file. Adapt if needed.)

In `DiagnosticsView`, inside the `ForEach` row `VStack`, after the message `Text`, add:

```swift
                            if diagnostic.actionLabel == "Align Displays" {
                                Button(strings.alignDisplays) {
                                    model.alignDisplaysToCurrentSpace()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .pointingHandCursor()
                            }
```

- [ ] **Step 5: Verify** — `swift build && swift test 2>&1 | tail -3` all green.
- [ ] **Step 6: Commit**

```bash
git add Sources/SidebyApp/SidebyApp.swift
git commit -m "feat: align displays to the current space's context"
```

---

### Task 7: E2E verification (controller + user)

- [ ] Rebuild + relaunch: quit Sideby, `bash scripts/build_app_bundle.sh`, `open dist/Sideby.app`.
- [ ] User checks: (a) capture is instant with 5/3 membership; (b) moving Spaces with macOS gestures makes current follow (status "… 따라가는 중"); (c) moving only one display to a mismatched combination shows needsSync WITHOUT unpinning, with an "컨텍스트 맞추기" button in diagnostics; (d) pressing 컨텍스트 맞추기 moves the other display to the matching Space and synchronizes; (e) log lines `instant-capture …`, `align-displays …` appear.

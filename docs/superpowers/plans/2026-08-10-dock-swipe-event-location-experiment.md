# Dock Swipe Event-Location Experiment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test whether Sideby can switch every selected display through Dock swipe events whose synthetic event locations target display centers, while leaving the physical pointer stationary.

**Architecture:** Add a location-aware posting boundary beside the existing Dock swipe poster and a target-aware executor that posts once per selected display point. Wire only the experimental product branch to that executor; keep the existing Space observation and stable-layout acknowledgement unchanged so an ignored event location cannot produce false Context state.

**Tech Stack:** Swift 6, CoreGraphics `CGEvent.location`, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Work only on `codex/issue-3-event-location-experiment`; do not change `main`, publish a release, notarize, or edit the public Sparkle feed.
- Do not activate Sideby, create AppKit cursor shields, move the physical cursor, hide/show the cursor, or disconnect/reconnect mouse association in the experimental executor.
- Preserve the existing active-Space and stable-layout verification path.
- Do not fall back to physical cursor movement when event-location targeting fails.
- Before a local manual-verification build, read the published Sparkle build number and use exactly `N+1`.

---

### Task 1: Location-aware Dock swipe posting and target executor

**Files:**
- Modify: `Sources/SidebySystem/SpaceCommands/DockSwipeSpaceCommandExecutor.swift`
- Test: `Tests/SidebySystemTests/DockSwipeSpaceCommandExecutorTests.swift`

**Interfaces:**
- Consumes: `DockSwipeGestureDescriptor`, `DisplaySwitchTargetProviding`, and `SwitchCommand`.
- Produces: `LocatedDockSwipeEventPosting.post(_:at:)`, `AnyLocatedDockSwipeEventPoster`, and `TargetedDockSwipeSpaceCommandExecutor.execute(_:)`.

- [ ] **Step 1: Write failing tests for event location and per-target posting**

Add tests that express the public behavior before implementation:

```swift
func testLocatedDockSwipePosterAssignsTargetLocationBeforePosting() {
    let writer = RecordingCGDockSwipeEventWriter()
    let poster = CGDockSwipeEventPoster(
        writer: writer,
        hasOrRequestPostEventAccess: { true }
    )
    let point = CGPoint(x: 900, y: 400)

    XCTAssertTrue(poster.post(.make(for: .next), at: point))
    XCTAssertEqual(writer.locations, [point])
    XCTAssertEqual(writer.postedTaps, [.session, .session])
}

func testTargetedDockSwipeExecutorPostsOnceAtEveryTargetPoint() {
    let poster = RecordingLocatedDockSwipePoster()
    let points = [CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 100)]
    let executor = TargetedDockSwipeSpaceCommandExecutor(
        poster: poster,
        targetProvider: StaticDockTargetProvider(points: points)
    )

    XCTAssertTrue(executor.execute(.previous))
    XCTAssertEqual(poster.descriptors, [.make(for: .previous), .make(for: .previous)])
    XCTAssertEqual(poster.locations, points)
}
```

Update `RecordingCGDockSwipeEventWriter` with a `locations` array and a test-only `setLocation(_:)`; add `RecordingLocatedDockSwipePoster` and `StaticDockTargetProvider` test helpers.

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter DockSwipeSpaceCommandExecutorTests
```

Expected: compilation failure because `post(_:at:)`, `setLocation(_:)`, and `TargetedDockSwipeSpaceCommandExecutor` do not exist.

- [ ] **Step 3: Implement the minimal location-aware boundary**

Add a separate protocol so the existing non-targeted executor remains intact:

```swift
public protocol LocatedDockSwipeEventPosting: Sendable {
    func post(_ descriptor: DockSwipeGestureDescriptor, at location: CGPoint) -> Bool
}

struct AnyLocatedDockSwipeEventPoster: LocatedDockSwipeEventPosting {
    private let poster: any LocatedDockSwipeEventPosting

    init(_ poster: any LocatedDockSwipeEventPosting) {
        self.poster = poster
    }

    func post(_ descriptor: DockSwipeGestureDescriptor, at location: CGPoint) -> Bool {
        poster.post(descriptor, at: location)
    }
}
```

Extend `CGDockSwipeEventWritingEvent` with `setLocation(_:) -> Bool`. In `CGDockSwipeWritableEvent`, assign `event.location`, read it back, and return whether it matches. Make `CGDockSwipeEventPoster` conform to `LocatedDockSwipeEventPosting`; its located overload must set the location before writing the existing private Dock fields and posting the began/ended phases.

Add the executor without a cursor dependency:

```swift
public struct TargetedDockSwipeSpaceCommandExecutor<Poster: LocatedDockSwipeEventPosting>: SpaceCommandExecuting {
    private let poster: Poster
    private let targetProvider: any DisplaySwitchTargetProviding

    public init(poster: Poster, targetProvider: any DisplaySwitchTargetProviding) {
        self.poster = poster
        self.targetProvider = targetProvider
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        let points = targetProvider.targetPoints()
        guard !points.isEmpty else { return false }
        let descriptor = DockSwipeGestureDescriptor.make(for: command)
        return points.reduce(true) { result, point in
            poster.post(descriptor, at: point) && result
        }
    }
}
```

- [ ] **Step 4: Run the focused tests and confirm GREEN**

Run:

```bash
swift test --filter DockSwipeSpaceCommandExecutorTests
```

Expected: all `DockSwipeSpaceCommandExecutorTests` pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/SidebySystem/SpaceCommands/DockSwipeSpaceCommandExecutor.swift Tests/SidebySystemTests/DockSwipeSpaceCommandExecutorTests.swift
git commit -m "experiment: target Dock swipes by event location"
```

---

### Task 2: Wire the product experiment without cursor lifecycle operations

**Files:**
- Modify: `Sources/SidebySystem/SpaceCommands/ProductDockSpaceExecutorFactory.swift`
- Test: `Tests/SidebySystemTests/ProductDockSpaceExecutorFactoryTests.swift`

**Interfaces:**
- Consumes: `AnyLocatedDockSwipeEventPoster` and `TargetedDockSwipeSpaceCommandExecutor` from Task 1.
- Produces: an experimental `ProductDockSpaceExecutorFactory.make(includedStableIDs:)` that has only a located poster and display target provider as dependencies.

- [ ] **Step 1: Write the failing factory tests**

Change the recipe expectation and factory assembly test:

```swift
func testProductFactoryRecipeUsesEventLocationWithoutCursorLifecycle() {
    XCTAssertEqual(
        ProductDockSpaceExecutorFactory.recipe,
        ProductSpaceExecutorRecipe(
            backend: .dockSwipe,
            cursorVisibility: .none,
            cursorShield: .none
        )
    )
}

func testFactoryPostsDockGestureAtInjectedTargetPoint() {
    let poster = RecordingFactoryLocatedDockPoster()
    let point = CGPoint(x: 900, y: 100)
    let executor = ProductDockSpaceExecutorFactory.make(
        includedStableIDs: ["main"],
        dependencies: .init(
            poster: poster,
            targetProvider: StaticFactoryTargetProvider(points: [point])
        )
    )

    XCTAssertTrue(executor.execute(.previous))
    XCTAssertEqual(poster.descriptors, [.make(for: .previous)])
    XCTAssertEqual(poster.locations, [point])
}
```

Add `.none` to `ProductSpaceExecutorRecipe.CursorVisibility`. Replace the old recording poster with `RecordingFactoryLocatedDockPoster` conforming to `LocatedDockSwipeEventPosting`.

- [ ] **Step 2: Run the factory tests and confirm RED**

Run:

```bash
swift test --filter ProductDockSpaceExecutorFactoryTests
```

Expected: compilation failure because `.none` and the reduced experimental dependency initializer do not exist.

- [ ] **Step 3: Implement the minimal experimental factory wiring**

Reduce `ProductDockSpaceExecutorDependencies` to:

```swift
struct ProductDockSpaceExecutorDependencies: Sendable {
    let poster: any LocatedDockSwipeEventPosting
    let targetProvider: any DisplaySwitchTargetProviding

    static func live(includedStableIDs: Set<String>) -> Self {
        Self(
            poster: CGDockSwipeEventPoster(),
            targetProvider: CGDisplaySwitchTargetProvider(
                includedStableIDs: includedStableIDs
            )
        )
    }
}
```

Set the recipe cursor visibility to `.none`, and return:

```swift
TargetedDockSwipeSpaceCommandExecutor(
    poster: AnyLocatedDockSwipeEventPoster(dependencies.poster),
    targetProvider: dependencies.targetProvider
)
```

Do not retain any hidden-cursor, cursor-positioning, cursor-shield, or cursor-association dependency in this factory.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter ProductDockSpaceExecutorFactoryTests
swift test
```

Expected: focused tests pass and the complete suite reports zero failures.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/SidebySystem/SpaceCommands/ProductDockSpaceExecutorFactory.swift Tests/SidebySystemTests/ProductDockSpaceExecutorFactoryTests.swift
git commit -m "experiment: avoid physical cursor targeting"
```

---

### Task 3: Build and launch the local two-display experiment

**Files:**
- Generated only: `dist/Sideby.app`
- No source or public feed changes.

**Interfaces:**
- Consumes: experimental product factory from Task 2 and the published Sparkle feed.
- Produces: a signed local app bundle for manual verification only.

- [ ] **Step 1: Resolve the next safe local build number**

Run:

```bash
SIDEBY_APPCAST="$(curl -fsSL https://github.com/ethznn/sideby/releases/latest/download/appcast.xml)"
SIDEBY_LATEST_BUILD="$(printf '%s' "$SIDEBY_APPCAST" | perl -0ne 'print $1 if /<sparkle:version>(\d+)<\/sparkle:version>/')"
case "$SIDEBY_LATEST_BUILD" in
  ''|*[!0-9]*) exit 1 ;;
esac
SIDEBY_NEXT_BUILD=$((SIDEBY_LATEST_BUILD + 1))
printf 'Published build: %s\nLocal verification build: %s\n' "$SIDEBY_LATEST_BUILD" "$SIDEBY_NEXT_BUILD"
```

Read the single integer in `<sparkle:version>N</sparkle:version>` and use `N+1`. If the feed cannot be read or parsed, stop without building.

- [ ] **Step 2: Build with explicit version metadata**

Run with the verified value resolved in Step 1:

```bash
SIDEBY_VERSION=0.10.0 SIDEBY_BUILD_NUMBER="$SIDEBY_NEXT_BUILD" scripts/build_app_bundle.sh
codesign --verify --deep --strict --verbose=2 dist/Sideby.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' dist/Sideby.app/Contents/Info.plist
```

Expected: signing verification succeeds and `CFBundleVersion` equals `$SIDEBY_NEXT_BUILD`.

- [ ] **Step 3: Replace only the current Sideby process and launch the experiment**

Resolve the exact current Sideby executable path with `pgrep -afil Sideby`. Terminate only the verified Sideby product process, then launch the experimental `dist/Sideby.app` with `open -n`. Confirm the new process executable path points inside this experiment worktree.

- [ ] **Step 4: Perform manual verification**

Ask the user to keep the pointer on a visible landmark and exercise adjacent and multi-step fixed Context shortcuts on the two selected displays. Collect these outcomes independently:

- actual Space indexes changed as expected;
- Sideby's final Context state matches them;
- pointer position remained stationary;
- no pointer flash was visible;
- rapid repeated input stayed aligned.

Do not merge, publish, or update Issue #3 until the manual result is known.

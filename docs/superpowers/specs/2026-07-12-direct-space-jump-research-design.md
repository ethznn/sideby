# Direct Space Jump Research Design

Date: 2026-07-12

## Summary

Sideby's indexed Context activation currently moves each selected display one
Space at a time, acknowledging each intermediate index before continuing. This
is safe but slow when a target Context is several Spaces away.

This research will determine whether Sideby can move multiple displays almost
simultaneously to non-adjacent target Spaces without activating intermediate
Spaces. The product constraint is a normal Sideby installation: no partial SIP
disablement, Dock injection, privileged helper, or scripting addition.

The primary candidate is a complete SkyLight transition performed from the
Sideby process. The comparison candidate uses macOS's configured “Switch to
Desktop N” symbolic hotkeys. High-velocity synthetic gestures and parallel
stepwise movement remain useful baselines, but they do not satisfy the direct
jump requirement because they still activate intermediate Spaces.

## Goals

- Jump directly from each selected display's current Space to its target Space.
- Avoid observing or activating intermediate Space indexes.
- Make target displays arrive within 50 ms of one another.
- Reach a coherent, settled screen state within 300 ms.
- Keep SkyLight layout, visible windows, normal Space navigation, and Mission
  Control's selected Desktop consistent.
- Preserve a known recovery path using acknowledged normal macOS Space
  commands.
- Produce evidence strong enough to classify each candidate as product-ready,
  conditionally useful, or unsafe.

## Non-goals

- Disabling SIP or injecting code into Dock.
- Shipping a direct jump executor as part of this research change.
- Replacing Sideby's acknowledged stepwise executor before the research passes.
- Persisting private Space IDs or hidden Mission Control state.
- Treating rapid intermediate transitions as a direct jump.

## Current Evidence

The existing dev-only direct setter probe establishes that
`SLSManagedDisplaySetCurrentSpace` can update the SkyLight layout, and a
forward call can also change visible windows. The current probe declares the
private function with an `Int32` return value, while current external source
evidence declares it as returning `void`. The recorded `status 0` must not be
treated as success evidence until the ABI is reconciled. Independently of that
return-value ambiguity, the transition does not produce
`NSWorkspace.activeSpaceDidChangeNotification`, and a setter-based
restore has returned the SkyLight layout to the original Space while leaving
the target Space visible. A direct setter alone is therefore not a coherent or
recoverable product transition.

The current product executor remains the reference recovery path. It posts
normal previous/next Space commands and waits for layout acknowledgement before
advancing Context state.

## Candidate Strategies

### 1. Batch SkyLight transition

This is the primary research candidate. It extends the existing setter probe
with the visibility operations used by complete private Space transitions:

1. Read one layout snapshot and plan every selected display target.
2. Show all target Space IDs.
3. Hide all current Space IDs.
4. Set each managed display's current Space without intentional delay.
5. Measure the dispatch skew and observe system convergence.

Two dispatch shapes will be compared:

- `show-all -> hide-all -> set-all`, using arrays for the visibility phases.
- A tight per-display `show -> hide -> set` loop with no acknowledgement wait
  between displays.

The first shape is expected to provide the best simultaneity. The second checks
whether WindowServer requires visibility and current-Space changes to be
grouped per display.

This candidate can satisfy directness and simultaneity, but it expands Sideby's
private API use from read-only layout queries to mutating operations. It must
therefore pass every synchronization and recovery criterion before any product
proposal.

### 2. Desktop-number symbolic hotkeys

This comparison candidate discovers enabled macOS “Switch to Desktop N”
symbolic hotkeys and posts the configured command for each target display. A
display is targeted using the same hidden-cursor routing boundary as existing
Sideby switching.

This approach asks macOS to select a specific Desktop in one command and is
more likely to preserve system notifications and Mission Control state. Its
limitations are user configuration, the finite set of Desktop-number commands,
per-display numbering ambiguity, and uncertainty about whether multiple
display commands can be accepted close enough together.

The probe must not modify the user's symbolic hotkey preferences. Missing or
disabled target shortcuts make the strategy unavailable for that scenario.

### 3. Stepwise baseline

The existing acknowledged previous/next route and a parallelized variant serve
as timing and recovery baselines. Neither is a direct jump, so neither can be
the successful product result of this research.

## Research Architecture

All new behavior remains in `SidebyDevSupport` and is invoked explicitly from
`SidebyDevApp`. Product Context activation is unchanged during research.

### DirectJumpTargetPlanner

The planner consumes one live SkyLight layout snapshot and the requested
Context. It produces an immutable set of current and target Space IDs keyed by
stable display ID and display UUID. A plan includes a display-configuration
generation token so the runner can reject stale targets.

Space IDs exist only for the lifetime of the probe. They are not written to
settings, durable logs, or user-facing output.

### BatchSkyLightJumpStrategy

This strategy dynamically loads the show, hide, and managed-display setter
symbols. Before any mutating run, the research must reconcile each private
function's calling convention and return type for the tested macOS build and
architecture. A setter return value is not a success signal unless its ABI has
been independently confirmed; success is determined from observed system
state. The strategy reports symbol availability, monotonic timestamps for each
phase, and total dispatch skew. It does not perform restoration.

### DesktopHotkeyJumpStrategy

This strategy reads enabled symbolic hotkey definitions without changing them,
maps target indexes to available commands, routes the hidden cursor to each
target display, and posts exactly one target command per moving display. It
reports unavailable indexes, post results, and dispatch timing.

### DirectJumpStateVerifier

The verifier builds a time-ordered observation from:

- Per-display SkyLight current Space IDs and indexes.
- Per-display visible-window fingerprints.
- `NSWorkspace.activeSpaceDidChangeNotification` timestamps.
- Frontmost application and focused-window state when Accessibility permits.
- The success and expected destination of the next normal Space command.
- A manual Mission Control checklist for states that cannot be observed safely.

Layout polling is frequent enough to detect intermediate Space IDs. Visible
window polling may use a lower frequency because `CGWindowListCopyWindowInfo`
is more expensive. The verifier records the first target-layout time for each
display and computes maximum arrival skew.

### DirectJumpRecoveryCoordinator

Before any mutating probe, the coordinator proves that Post Events permission,
layout reading, and the acknowledged normal switching path are available. It
captures enough index information to return each moved display to its original
Space using previous/next commands.

If preflight fails, the mutating probe is blocked. If a candidate fails or only
partially moves displays, recovery uses normal commands plus per-step layout
acknowledgement. The coordinator never restores with a direct setter. A failed
recovery ends the run immediately and requires manual inspection before another
mutating probe.

## Probe Flow

1. Verify the run is explicit, no Context switch is active, and Mission Control
   is not open.
2. Verify permissions, layout readability, candidate symbols or symbolic
   hotkeys, and the acknowledged recovery path.
3. Capture the baseline snapshot and display-configuration generation.
4. Produce and validate the immutable target plan.
5. Start layout, notification, and visible-window observations.
6. Execute one candidate strategy.
7. Capture immediate and settled snapshots while retaining the observation
   timeline.
8. Reject results if the display generation changed or external Space activity
   invalidated the run.
9. Evaluate directness, simultaneity, coherence, and normal-navigation health.
10. Open the manual Mission Control inspection checkpoint.
11. Recover using the acknowledged normal path and verify the original layout
    and visible fingerprints.
12. Emit a structured result without persisting private Space IDs.

## Experiment Matrix

### Phase 0: non-mutating preflight

- Record OS and architecture.
- Record selected display topology and Space counts.
- Check Post Events and Accessibility permission.
- Check direct candidate symbol availability.
- Read, but do not change, Desktop-number symbolic hotkey availability.
- Check that normal acknowledged switching and recovery can operate.

### Phase 1: one display

For both Batch SkyLight dispatch shapes and every available Desktop-number
command path:

- Move to an adjacent Space in both directions.
- Move across at least two intermediate Spaces in both directions.
- Repeat each exploratory scenario three times.
- Promote only coherent candidates to ten-run repetition.

### Phase 2: two displays

- Both displays move in the same direction to different targets.
- Displays move in opposite directions.
- Displays move different distances.
- One display is already at its target while the other moves.
- Repeat each exploratory scenario three times.
- Promote only coherent candidates to ten-run repetition.

### Phase 3: special states

Only a candidate that passes the normal-Desktop phases proceeds to:

- Native full-screen Spaces.
- Stage Manager off and on.
- Space ordering changes between planning attempts.
- Display disconnect or configuration change between planning and execution,
  which must block or invalidate the run without using stale targets.

Mission Control being open is a blocked state, not a mutating test scenario.

## Success Criteria

A candidate run passes only when all of the following are true:

- No intermediate Space ID appears in the observed layout timeline.
- Every target display reaches its planned target.
- The difference between the first target-layout timestamps is at most 50 ms.
- The final visible-window state settles within 300 ms.
- Target layout and visible-window fingerprints agree.
- A normal active-Space notification is observed, or the complete equivalent
  acknowledgement bundle succeeds: target layout remains stable for 200 ms,
  visible fingerprints match, Mission Control selects the target Desktop, and
  the next normal adjacent command reaches the predicted Space and emits its
  normal active-Space notification.
- Mission Control's selected Desktop matches the visible Desktop.
- A following normal previous/next command moves to the expected adjacent
  Space.
- Recovery returns layout and visible state to the original Context.
- No desynchronization, stale screen, Dock restart, or persistent visual
  artifact occurs in the repeated run set.

The 50 ms simultaneity and 300 ms settling thresholds are initial research
limits. Results must include raw timings so the limits can be reviewed against
the displays' refresh rates instead of silently relaxed.

## Failure Handling

The probe treats any of the following as failure:

- A required symbol disappears, its ABI cannot be reconciled, or a confirmed
  failure result is returned.
- A target symbolic hotkey is unavailable.
- Only a subset of displays reaches its target.
- An intermediate Space is observed.
- Layout and visible windows disagree.
- Required acknowledgement evidence is absent.
- The display generation or Context target becomes stale.
- User or external Space activity overlaps the probe.
- Normal navigation does not behave as predicted afterward.
- Recovery cannot be verified.

A failed run cannot advance product Context state. During eventual product
integration, an unverified result would mark the Context plan `needsSync`,
disable the direct path for the session, and fall back only on a subsequent
explicit user action.

## Test Strategy

Unit tests use fake layouts, clocks, strategies, and observation timelines to
cover:

- Direct target planning for multiple displays.
- Rejection of stale display generations.
- No-op displays that are already at target.
- Intermediate-Space detection.
- Arrival-skew and settling-time calculations.
- Partial execution and missing acknowledgement.
- Recovery plans in both directions.
- Symbolic hotkey availability and unsupported target indexes.
- Structured Green, Yellow, and Red classification.

System tests verify symbol loading and non-mutating preflight only. Actual Space
movement is never run by an automated test or ordinary Sideby startup; it
requires an explicit DevApp probe.

## Product Decision Boundary

Research results are classified as follows:

- **Green:** Batch SkyLight passes every criterion. It may proceed to a separate
  product implementation design with a capability probe and automatic fallback.
- **Yellow:** Only Desktop-number symbolic hotkeys pass. Sideby may consider a
  conditional accelerator for environments where every required command is
  already configured, while retaining the acknowledged stepwise route
  elsewhere.
- **Red:** Neither candidate passes synchronization, directness, simultaneity,
  or recovery criteria. Sideby keeps its current product path and publishes the
  research result without a direct executor.

Even a Green result does not authorize implementation in this research change.
Product integration requires its own reviewed plan because it would introduce
mutating private API use and new failure modes into Context activation.

# Instant Context Capture via CGS Space Layout

Date: 2026-06-13
Status: Approved

## Problem

Walk-based capture (align to the first Space, press forward, infer movement)
exists only because the app could not read the Space layout directly. Its
sensing stack — the global `activeSpaceDidChange` notification attributed by
time windows, visible-app fingerprints, and the no-move grace policy — is
heuristic. It cannot be made fast without corrupting per-display attribution
(verified by log evidence on 2026-06-13: shortening waits caused another
display's late notification to bleed into the next press window), and a full
capture takes ~20 seconds.

A spike on the target machine proved that the private SkyLight call
`SLSCopyManagedDisplaySpaces(SLSMainConnectionID())` returns, per display, the
ordered Space list and the current Space ID — exactly matching the user's real
layout (external 5 Spaces / built-in 3) in milliseconds.

## Decision

Capture reads the Space layout directly and builds the context plan instantly,
without moving any Space. The walk-based pipeline stays as an automatic
fallback when the SLS symbols are unavailable. Switching/acknowledgment is NOT
in scope (next milestone). The private API is used read-only.

## Components

### 1. SpaceLayoutReading (SidebySystem)

```swift
public struct DisplaySpaceLayout: Equatable, Sendable {
    public let displayUUID: String      // CGS "Display Identifier"
    public let spaceIDs: [UInt64]       // ordered as Mission Control shows them
    public let currentSpaceID: UInt64
}

public protocol SpaceLayoutReading: Sendable {
    func readLayout() -> [DisplaySpaceLayout]?  // nil = SLS unavailable
}
```

`SLSSpaceLayoutReader` resolves `SLSMainConnectionID` and
`SLSCopyManagedDisplaySpaces` via `dlopen`/`dlsym` once (cached). Any missing
symbol, nil array, or unparseable payload returns `nil` — never a partial
layout. Parsing from the bridged `[[String: Any]]` payload lives in a pure
function so it is unit-testable with fixtures (keys: `Display Identifier`,
`Spaces[].ManagedSpaceID`, `Current Space.ManagedSpaceID`). Fullscreen-app
Spaces are included as-is — the walk-based capture also traverses them, so
behavior is equivalent.

### 2. Display ID mapping (SidebySystem)

CGS identifies displays by UUID; the app uses stable IDs (vendor-model-serial
form). Build the mapping with public APIs: `CGGetActiveDisplayList` →
`CGDisplayCreateUUIDFromDisplayID` per display → pair with the same stable-ID
derivation the app already uses. Mapping is a pure function over
(uuid, stableID) pairs; displays that cannot be mapped are treated as absent
from the layout (and if any SELECTED display is unmapped, instant capture
falls back to the walk).

### 3. Instant plan derivation (SidebyCore, pure)

Input: per selected display, `(stableID, spaceCount, currentSpaceIndex)`.
Rules:

- Context count = max space count across selected displays, capped at the
  existing capture limit maximum (12). At least 1.
- Context at order k (1-based) has `displayIDs` = displays with
  `spaceCount >= k`. Membership is exact by construction.
- Current: if every selected display has the same `currentSpaceIndex` i, the
  plan's `currentContextID` = context at order i+1 and the plan is
  synchronized (via the existing `replaceContexts`). If indexes differ,
  `currentContextID` = context at the first display's index and the plan is
  marked `needsSync` afterwards — the UI's existing Set Current affordance
  reflects reality.
- Names: the context at the current index of each display gets the existing
  visible-app suggested name (only currently visible Spaces can be named);
  all other contexts get the default "Context N". When displays disagree on
  the current index, only the first display's index gets the suggested name.

### 4. App wiring (SidebyApp)

`startContextCapture`:
1. Read layout; map selected displays. On success → derive contexts, call
   `updateContextPlan { $0.replaceContexts(...) }` (which auto-pins, from the
   2026-06-13 capture-completion spec), apply needsSync if indexes disagreed,
   set `contextCaptureStatus` via the existing
   `contextCaptureReadySummary`, and log one line
   (`instant-capture displays=N contexts=M`).
2. On any failure (reader nil, unmapped selected display) → existing
   walk-based capture, unchanged.

No `ContextCaptureSession` is created on the instant path; the session,
alignment, grace, and observer machinery remain fallback-only.

## Out of Scope

- Switching acknowledgment via CGS reads (next milestone).
- Removing the walk pipeline.
- Naming non-visible Spaces (requires deeper private APIs or a walk).

## Risks

- Private API drift on future macOS: mitigated by nil-fallback to the walk.
- Distribution: private API precludes App Store; the app ships as a DMG.

## Tests

- Payload parsing: fixtures for the happy path, missing keys, empty spaces.
- Display mapping: pairs → stableID resolution, unmapped display behavior.
- Plan derivation: 5/3 asymmetric case (orders 4-5 external-only), equal
  counts, single display, cap at 12, current-index agreement and
  disagreement (needsSync), name assignment rules.
- Reader smoke: on a real machine, `readLayout()` returns ≥1 display with
  ≥1 space and a current ID contained in `spaceIDs` (skipped if SLS absent).

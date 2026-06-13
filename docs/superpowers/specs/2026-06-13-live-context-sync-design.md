# Live Context Sync: Auto-Tracking + Align Action

Date: 2026-06-13
Status: Approved

## Problem

After instant capture, the plan's current context is a pointer the user must
maintain by hand: moving Spaces with macOS gestures pauses matching
(`pauseContextMatchingForUnsynchronizedMovement`: unpins + needsSync) and
requires a manual "Set Current". Now that the per-display Space layout is
readable (`SpaceLayoutReading`, 2026-06-13 instant-capture spec), the app can
know which context is actually on screen and keep itself in sync.

## Decision

Two behaviors, both gated on the SLS reader being available (reader nil →
existing pause behavior unchanged):

1. **Auto-tracking.** On every external space change, read the layout and
   match it against the plan. Match → `setCurrentContext` (stay pinned).
   No match → `markNeedsSync` only (stay pinned; needsSync already blocks
   context switching). Tracking also runs when the plan is already needsSync,
   so returning to a context auto-recovers.
2. **Align action ("Align Displays" / "컨텍스트 맞추기").** A button that
   reads the Space index of the display the user pressed it on (reference =
   display hosting the Sideby window, fallback: display under the cursor),
   takes that index as the target context order, and physically moves every
   other connected member display to that context's Space — each press
   verified by polling the CGS layout, not by notification heuristics. On
   success: current = target context, synchronized.

## Matching rule (the "연결된 디스플레이" rule)

Context k is current iff every display that is BOTH a member of context k AND
currently connected sits at Space index k-1 — and at least one such display
exists. Non-member displays are unconstrained (e.g. built-in with 3 Spaces
does not block context 4/5 on the external). Because membership is monotonic
(members of k+1 ⊆ members of k), at most one context can match.

## Components

### 1. ContextCurrentMatcher (SidebyCore, pure)

```swift
public enum ContextCurrentMatcher {
    /// displayIndexes: connected display stableID → 0-based current Space index.
    public static func currentContextID(
        contexts: [ContextDefinition],
        displayIndexes: [String: Int]
    ) -> String?
}
```

Returns the unique matching context's id per the rule above, nil otherwise
(including empty inputs).

### 2. Space index snapshot helper (SidebyApp)

`currentSpaceIndexesBySelectedDisplay() -> [String: Int]?` — reads
`spaceLayoutReader.readLayout()`, maps UUIDs → stableIDs (same path as
instant capture), returns indexes for the SELECTED displays present in the
layout; nil when the reader is unavailable. Shared by tracking, aligning,
and (already) instant capture — extract the layout+mapping portion from
`startInstantContextCapture` into a helper both call sites use.

### 3. Auto-tracking wiring (SidebyApp)

In the external-space-change handler (`handleExternalSpaceChange` /
the `pauseContextMatchingForUnsynchronizedMovement` call site):

- Keep the existing ignore-window and `isSwitching`/capture guards.
- Gate: `isEnabled && plan.isPinned` and plan has contexts. (The old
  policy's `syncState == .synchronized` gate is dropped for tracking so
  needsSync can self-heal; `ExternalSpaceChangeContextPolicy` gains a
  `shouldTrack` variant.)
- Read indexes (component 2). nil → existing pause behavior (fallback).
- `ContextCurrentMatcher` match → `updateContextPlan { $0.setCurrentContext(id:) }`
  (only when it differs from the current pointer; setCurrentContext also
  restores synchronized). No match → `updateContextPlan { $0.markNeedsSync() }`
  — note: do NOT unpin.
- Status line (`lastSwitchResult`) updated with a short "following context"
  / "needs alignment" string; one os.log notice per decision.

### 4. Align action (SidebyApp + SidebySystem)

`alignDisplaysToCurrentSpace()`:

1. Guards: not switching, no capture session, plan non-empty, reader
   available (else status message explains it's unavailable).
2. Reference display: the display whose frame contains the Sideby window
   (`NSApp` key window screen → CGDirectDisplayID → stableID); fallback to
   the display containing the mouse cursor.
3. Target order = reference display's current index + 1. If no context of
   that order exists (index beyond captured range), fail with a status
   message (no movement).
4. For each OTHER connected member display of the target context, in layout
   order: compute delta = (k-1) - currentIndex; press `.next`/`.previous`
   |delta| times via the existing single-display acknowledged switch
   machinery, but acknowledge each press by polling the CGS layout (50 ms
   interval, 1.0 s timeout per press) for that display's index change.
   First press that times out aborts the alignment (remaining displays
   untouched, plan marked needsSync, status message).
5. On success: `setCurrentContext(target)`, status message with the context
   name. The auto-tracker's ignore window must cover the alignment run
   (reuse `ignoresExternalSpaceChangesUntil`).

The per-press CGS acknowledgment lives in SidebySystem as
`SpaceLayoutStepAcknowledger` (pure-ish: takes a `SpaceLayoutReading`, a
display UUID/stableID resolver, polls until index change or deadline) so the
poll loop is testable with a scripted fake reader.

### 5. UI (SidebyApp + SBSStrings)

- Button "컨텍스트 맞추기" / "Align Displays" in `ContextCaptureControlsView`
  next to the capture button; disabled while switching/capturing.
- The needsSync diagnostic (`ContextPlan.navigation` / the pinned+needsSync
  diagnostic appended in `currentDiagnostics`) gains
  `actionLabel: "Align Displays"`, and `DiagnosticsView` renders a button for
  EXACTLY that label (other actionLabels keep rendering as text-only — no
  generic action framework in this change), wired to
  `alignDisplaysToCurrentSpace()`.
- New strings (EN/KO): align button label, align success
  ("Aligned to <name>" / "<name>에 맞췄습니다"), align failure
  ("Couldn't align — capture Contexts again" / "맞추지 못했습니다 — 컨텍스트를
  다시 캡처해 주세요"), tracking status ("Following <name>" / "<name> 따라가는 중").

## Out of Scope

- Replacing the walk-based capture fallback or its pause behavior (kept for
  SLS-unavailable environments).
- Replacing notification-based acknowledgment in the normal gesture switch
  path (separate milestone; this change only adds CGS acknowledgment for
  the align action's presses).
- Removing the manual "Set Current" buttons (still useful to re-point
  without moving displays).

## Risks

- Reentrancy: alignment presses trigger activeSpaceDidChange notifications;
  the existing `ignoresExternalSpaceChangesUntil` window plus the
  `isSwitching` flag must cover the run so the tracker doesn't fight the
  aligner.
- A display whose Space count changed since capture can make the target
  context unreachable; the per-press timeout + needsSync fallback bounds the
  damage and the failure string points to re-capture.

## Tests

- Matcher: unique match (asymmetric 5/3 at orders 1-3 both, 4-5 ext-only),
  no-match combination → nil, non-member display unconstrained, display
  beyond its captured count, empty inputs → nil.
- Policy: `shouldTrack` gating (enabled/pinned variants; needsSync still
  tracks).
- Step acknowledger: scripted fake reader — acknowledges on index change,
  times out without change, respects deadline.
- App-level behaviors verified manually (Task 6-style E2E): gesture move →
  current follows; mismatched combination → needsSync without unpinning;
  align button moves the other display and synchronizes.

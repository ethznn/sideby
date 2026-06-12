# Capture Completion: Auto-Pin + Current Context Announcement

Date: 2026-06-13
Status: Approved (Option A)

## Problem

After a context capture completes, users find "Move by Contexts" (isPinned)
turned off and believe they must press "Set Current" before switching works.
Capture commit already sets `currentContextID` to the last captured context and
marks the plan synchronized, but it never re-arms `isPinned`, and nothing on
screen tells the user the plan is ready.

## Decision

Completing a capture means the user intends to move by contexts. Make that an
invariant of the capture-commit API and announce the resulting state in the
existing capture status text. Applies to every successful capture (onboarding
and re-captures alike).

## Changes

1. **SidebyCore — `ContextPlan.replaceContexts(_:currentContextID:captureLimit:)`**
   also sets `isPinned = true`. This is the only capture-commit entry point, so
   the invariant lives at the right depth and is unit-testable.

2. **SidebyUI — `SBSStrings`** gains `contextCaptureReadySummary(count:currentName:)`:
   - EN: `Captured N contexts · Move by Contexts on · Current: <name>`
   - KO: `컨텍스트 N개 캡처됨 · 컨텍스트대로 움직이기 켜짐 · 현재: <name>`

   **`ContextCaptureStatusDisplay.statusText`** gains `currentContextName: String?`
   (default `nil`). `.completed` returns the new summary when a name is
   available; falls back to the existing `capturedContexts(count:)` otherwise.
   Other phases unchanged.

3. **SidebyApp — `finishContextCaptureIfNeeded`** passes
   `settings.contextPlan.currentContext?.name` (read after commit) into the
   status text.

## Out of Scope

- The pause-on-external-movement behavior (`pauseContextMatchingForUnsynchronizedMovement`)
  stays as designed; manually moving spaces after capture still pauses matching.
- Failed/stopped capture status texts are unchanged.

## Tests

- Core: a plan with `isPinned == false` becomes pinned after `replaceContexts`.
- UI: `.completed` status text includes the pin notice and current context name;
  falls back without a name.

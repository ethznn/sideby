# Dock Swipe Event-Location Experiment Design

## Purpose

Determine whether Sideby can target each display for Dock-based Space navigation without moving the physical mouse cursor. The experiment is successful only if Context transitions remain verified while the pointer stays at its original position without visible flashes.

## Hypothesis

The Dock gesture handler may select its target display from the synthetic `CGEvent` location. Sideby can set that location to the display center with `CGEvent.location` and post the existing private Dock gesture fields, avoiding `CGDisplayMoveCursorToPoint`, cursor hiding, and mouse/cursor disassociation.

## Scope

- Work only on the experimental branch; do not change `main` or publish a release.
- Exercise the real Sideby product shortcut path, not a standalone mock UI.
- Keep the existing active-Space and stable-layout verification unchanged.
- Do not add foreground activation, AppKit cursor shields, full-screen panels, or new private cursor APIs.
- Do not attempt to solve unrelated Context transition or capture behavior.

## Design

1. Extend the Dock swipe writer boundary so an event can receive a global target location before it is posted.
2. Add a target-aware Dock executor that obtains the selected display center points and posts one Dock gesture per target point.
3. In the experimental product factory, use the target-aware executor directly. It must not invoke the physical cursor positioner, cursor visibility controller, cursor shield, or mouse/cursor association controller.
4. Preserve the existing product transition runner and layout acknowledgement. A post alone is not success; Sideby accepts the Context only after observing the expected Space changes.
5. Keep the previous hidden-cursor executor intact so the experiment is easy to compare and discard.

## Failure Behavior

- If event creation, location assignment, field assignment, or posting fails, the executor reports failure.
- If Dock ignores the event location, the stable-layout verifier will reject the expected target state rather than updating Sideby's Context incorrectly.
- No fallback to physical cursor movement occurs inside the experiment. Falling back would make pointer results ambiguous.

## Automated Verification

- A writer-level test proves the requested global point is assigned to the synthetic event before posting.
- An executor test proves each target display point receives exactly one Dock gesture.
- A factory test proves the experimental product path selects event-location targeting and has no cursor lifecycle dependency.
- Run the focused tests first, then the complete Swift test suite.

## Manual Verification

Build a local app using the next Sparkle-safe build number, replace only the currently running Sideby validation process, and test on the user's two-display setup:

1. Record the pointer position and leave it over a visually identifiable location.
2. Use fixed Context shortcuts for adjacent and multi-step transitions while holding Option+Shift.
3. Verify both selected displays reach the expected Space indexes.
4. Verify the target Context HUD and final Context state remain correct.
5. Verify the pointer neither jumps to display centers nor flashes during the transition and returns/stays at its original position.
6. Repeat transitions in both directions and with rapid repeated input.

## Decision Rule

- **Adoptable candidate:** all selected displays switch reliably, Sideby's verified state matches the actual Spaces, and the physical pointer remains stationary without flashes.
- **Rejected hypothesis:** any selected display fails to switch because Dock ignores the synthetic event location, or the event location itself moves the physical pointer.
- A rejected experiment is not merged; Issue #3 is updated with the finding and the foreground-activation trade-off remains the only known public cursor-hiding route.

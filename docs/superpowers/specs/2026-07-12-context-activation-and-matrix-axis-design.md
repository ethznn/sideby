# Context Activation Guard and Matrix Axis Header Design

Date: 2026-07-12

## Goal

Make the Sideby master toggle authoritative for direct Context activation and
use the Context matrix's top-left header cell to explain its row and column
axes.

## Confirmed Behavior

- When Sideby is off, every Context `Go` / `이동` button is disabled and direct
  Context activation cannot execute.
- Context activation is also unavailable while a switch or Context capture is
  already in progress.
- The model checks the enabled state even if activation is invoked outside the
  visible button, so the UI is not the only safety boundary.
- A blocked programmatic activation records the existing Sideby-off diagnostic.
- Existing Previous/Next, Context capture, Context editing, drag-and-drop, and
  display-row reordering behavior remains unchanged.

## Availability Policy

Add a small pure policy in `SidebyCore` that answers whether direct Context
activation is available from three inputs:

- `isSidebyEnabled`
- `isSwitching`
- `isCapturing`

Activation is allowed only when Sideby is enabled and neither operation is in
progress. The matrix button and the model both consume this policy. The model
retains a separate Sideby-off branch so it can publish the correct diagnostic.

## Matrix Axis Header

Replace the current single `Displays` / `디스플레이` label in the matrix's
top-left header cell with a directional two-axis header:

- top-trailing: `Contexts →` / `컨텍스트 →`
- bottom-leading: `Displays ↓` / `디스플레이 ↓`

The cell keeps the current display-column width, matrix header height, resize
handle, and compact layout behavior. The two labels use secondary caption
styling so they clarify the matrix without competing with Context names and
Space cells.

## Files

- `Sources/SidebyCore/Contexts/ContextActivationAvailability.swift`: pure
  availability policy.
- `Tests/SidebyCoreTests/ContextActivationAvailabilityTests.swift`: enabled,
  disabled, switching, and capturing cases.
- `Sources/SidebyApp/SidebyApp.swift`: model guard, disabled Context buttons,
  cursor state, and directional top-left header.
- `Sources/SidebyUI/MenuBar/FloatingMenuPanelLayout.swift`: explicit
  top-trailing Context and bottom-leading Display axis roles.
- `Tests/SidebyUITests/AppShellTests.swift`: axis-role placement contract.

The view reuses the existing localized `contextPlanner` and `displays` strings;
no new user-facing copy is introduced.

## Verification

1. Add failing policy and localization tests before implementation.
2. Confirm the direct model path checks the availability policy and publishes
   the Sideby-off diagnostic.
3. Confirm matrix `Go` / `이동` buttons are disabled when Sideby is off,
   switching, or capturing.
4. Confirm the directional axis header fits compact and regular matrix widths.
5. Run the full Swift test suite.
6. Rebuild and relaunch `Sideby.app` for manual verification.

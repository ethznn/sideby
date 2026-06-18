# Floating Menu A2 Context Matrix Design

Date: 2026-06-19
Status: Approved for implementation planning

## Problem

The current floating menu exposes Sideby's core controls, but the hierarchy
does not fully match the product's strongest workflow. Users need to see their
real display arrangement, then directly edit how captured Contexts map to
per-display Spaces. Hiding the Context matrix behind a secondary view would
make the app feel simpler, but it would also hide the main setup surface.

## Decision

Use the A2 layout direction:

1. Keep **Move Targets** as a prominent visual display map. It should preserve
   the real display arrangement and scale it so the whole arrangement fits
   cleanly inside its card.
2. Keep **Context Matrix** visible by default as the main Context setup surface.
   Users should be able to drag Space cells between Context columns without
   opening an advanced view.
3. Strengthen Context column headers so captured names are easy to read.
   Headers show the Context order, status, and editable Context name with enough
   room for meaningful names such as `Codex / dist`.

This keeps Sideby honest about what it is: a compact menu bar utility for
moving displays together, with the matrix as the primary editing tool.

## Layout

The floating menu remains a vertical, scrollable panel:

1. Status header with Sideby name, on/off switch, and concise state text.
2. Switch controls for Previous and Next.
3. Move Targets card.
4. Contexts card containing capture controls and the always-visible matrix.
5. Existing collapsed sections for Input, Permissions, General, and Status.

The design keeps the current no-sidebar menu structure. It does not introduce a
settings-app split view.

## Move Targets

Move Targets should render as a responsive mini map:

- Compute a union rectangle from all display frames.
- Fit the union into the available card area while preserving aspect ratios.
- Center the scaled arrangement with consistent padding.
- Use stable max height so unusual monitor layouts do not make the menu jump.
- Preserve a minimum visible size for each display thumbnail where possible.
- Keep display labels inside each thumbnail, with one-line truncation and a
  tooltip/help value for the full display name.
- Keep selected targets visually strong, but avoid excessive glow that competes
  with the matrix.
- Handle 1 display, 2 displays, 3+ displays, vertical arrangements, ultrawide
  displays, and partially offset displays.

The goal is for the display map to look intentionally composed inside the card,
not merely mathematically scaled.

## Context Matrix

The matrix remains the primary editing surface:

- Context columns stay visible by default inside the Contexts card.
- Users can continue dragging display Space cells between Context columns.
- Users can continue dragging display rows to reorder the matrix.
- Column headers are redesigned around readability:
  - order label, such as `Context 1`
  - status chip, such as `Current`, `Sync`, or `Paused`
  - editable Context name
  - compact `Go` action
- Context names get more visual priority than today. They should support
  meaningful names with truncation behavior that feels deliberate.
- The horizontal matrix scroll remains available when there are more Contexts
  than fit in the panel.

## Capture Controls

Capture controls stay within the Contexts card above the matrix:

- `Move by Contexts` remains a checkbox/toggle.
- `Capture Contexts` and `Align Displays` remain adjacent actions.
- Capture status remains concise and should not push the matrix too far down.

The controls are supporting actions for the matrix, not a separate primary
section.

## Component Boundaries

Implementation should preserve existing SwiftUI boundaries where practical:

- `MoveTargetsView` and `DisplayArrangementView` own display map rendering.
- `ContextsView` owns matrix layout and interaction.
- `ContextCaptureControlsView` owns capture and align controls.
- Layout constants that affect cross-component sizing should live in
  `FloatingMenuPanelLayout` or a nearby menu layout helper.

If the current `SidebyApp.swift` view section becomes harder to read while
making these changes, extract focused private view helpers rather than
rewriting unrelated UI.

## Data Flow

No new domain data is required.

- Display map uses existing `DisplayInfo.frame`, `isPrimary`, `isBuiltin`, and
  selected display IDs.
- Matrix uses existing `ContextMatrixModel.matrix(...)`.
- Context names continue flowing through `model.setContextName(...)`.
- Matrix drag operations continue using the existing payloads and model
  methods.

This is a presentation and ergonomics change, not a change to Context semantics.

## Edge Cases

- No displays: show the existing no-displays summary.
- Missing display frames: keep the fallback display row, but use the same
  visual polish and label behavior as the arranged map.
- Very long display names: truncate inside the display thumbnail and expose the
  full name through help/accessibility.
- Very long Context names: allow useful width, then truncate or scale within
  the header without breaking the column width.
- Many Contexts: preserve horizontal scrolling.
- Capture in progress: progress and status should remain visible without
  obscuring the matrix.

## Out of Scope

- Changing Context capture semantics.
- Changing Space switching behavior.
- Hiding the matrix behind an advanced-only flow.
- Adding a sidebar or multi-page settings shell.
- Replacing the current display thumbnail illustration with real screenshots.

## Testing

Automated coverage should focus on layout policies where possible:

- Unit test any extracted display fit calculation for common and unusual
  monitor arrangements.
- UI smoke coverage should still instantiate the floating menu and matrix.
- Existing matrix model tests should remain valid.

Manual verification should cover:

- 1 display, 2 side-by-side displays, stacked displays, and 3+ displays.
- Long display names and long Context names.
- Matrix horizontal scrolling with many Contexts.
- Dragging a Space cell between Contexts.
- Dragging display rows.
- Capture and align controls in enabled, disabled, and in-progress states.

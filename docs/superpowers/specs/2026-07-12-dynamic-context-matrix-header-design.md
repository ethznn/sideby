# Dynamic Context Matrix Header Design

Date: 2026-07-12

## Goal

Remove the oversized fixed height from the Context matrix header while keeping
the frozen Display column aligned with the horizontally scrolling Context
columns.

## Confirmed Behavior

- Each Context header uses its natural SwiftUI content height.
- The matrix measures the tallest visible Context header and uses that shared
  height for the top-left axis header.
- The first Space row begins immediately after the measured header and the
  existing 8-point row gap.
- The top-left axis labels remain `Contexts →` / `컨텍스트 →` and
  `Displays ↓` / `디스플레이 ↓`.
- Display names and Space cells remain row-aligned.
- Compact and regular layouts, localization, and future header content changes
  do not require new hard-coded header-height constants.

## Layout Design

`contextHeader` no longer receives a fixed `height`. It keeps its existing
fixed column width and lays out the title/action row plus name field at its
intrinsic height.

Each Context header reports its rendered height through a SwiftUI preference.
The matrix reduces those values to the maximum and stores it as local view
state. The top-left axis header receives that measured height so both sibling
vertical stacks start their first data row at the same vertical position.

Before the first measurement arrives, the axis header uses its own intrinsic
height. Updating the stored value only when the measured value changes avoids
an unnecessary layout-update loop.

The display-column resize handle uses the same measured header height so its
visual span continues to cover the complete matrix. Data-row heights remain
fixed because those cells intentionally form a regular matrix.

## Components

- `FloatingMenuContextMatrixHeaderHeightPreferenceKey` collects Context header
  heights and returns their maximum.
- `ContextsView` owns the current measured header height and applies it to the
  axis header and resize handle.
- `FloatingMenuContextMatrixLayout` no longer exposes fixed compact and regular
  header-height values.

## Edge Cases

- With no Context columns, the axis header falls back to its intrinsic height;
  no stale fixed value is introduced.
- Longer localized labels or future controls can increase the shared header
  height naturally.
- A width change may produce a new measured height; the matrix updates to the
  new maximum without changing data-row sizing.

## Testing

- Replace the fixed-height layout test with a preference-reduction test that
  verifies the tallest reported Context header wins.
- Keep the existing axis-role test to preserve label direction.
- Run the complete Swift test suite.
- Build and relaunch `Sideby.app`, then verify the compact matrix visually and
  confirm the app remains menu-bar-only.

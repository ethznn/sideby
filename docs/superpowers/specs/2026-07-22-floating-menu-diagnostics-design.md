# Floating Menu Diagnostics Design

## Goal

Keep context-keyboard registration failures visible in the product floating menu and localized to the currently selected language, while continuing to show ordinary runtime diagnostics without making the menu visually heavy.

## Data flow

`SidebyAppModel` stores only base runtime diagnostics in an `@Published` property. Failed context-keyboard commands live in a separate `@Published` property. The public `diagnostics` getter combines both on demand with the model's current `SBSStrings`, so a language change immediately produces a warning in the new locale and no localized registration warning is retained in storage.

Runtime assignments continue to write through the `diagnostics` setter, which updates only the base runtime array. Changes to settings, runtime diagnostics, or failed commands all emit `ObservableObject` changes through their `@Published` storage.

## Presentation model

`FloatingMenuDiagnosticsContent` converts `[DiagnosticState]` into an optional section model containing severity, localized title, and localized message. It uses the existing `SBSStrings.localizedDiagnosticTitle(_:)` and `localizedDiagnosticMessage(_:)` APIs. Empty input returns `nil`, which is the testable contract for hiding the menu section.

Partial and total registration failures use the existing keyboard catalog and formatter, so the exact unavailable shortcuts reach the same presentation input as ordinary diagnostics.

## View

`ProductMenuContentView` requests the optional diagnostics section from `model.diagnostics` and places it immediately after the Contexts group and before the collapsible Input, Permissions, and General sections.

The section is a compact rounded card. Each diagnostic row shows a severity-specific SF Symbol and color plus a semibold title and secondary caption message. Multiple rows share the same card with dividers. There is no new heading or action UI, keeping the change small and avoiding new copy.

## Tests

Tests cover:

- exact partial registration shortcut warning in floating-menu content;
- exact total registration shortcut warning in floating-menu content;
- empty diagnostics producing no section;
- ordinary diagnostics preserved and localized;
- the same base diagnostics and failed commands recomputed English then Korean without retaining the English warning;
- existing merger persistence and duplicate behavior.

Verification includes focused UI/keyboard tests, the full Swift test suite, `swift build --product SidebyApp`, and `git diff --check`.

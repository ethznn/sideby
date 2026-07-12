# Dockless Sideby Apps Design

Date: 2026-07-11

## Goal

Run both `Sideby.app` and `SidebyDevApp.app` as menu-bar-only utilities. Neither
app should appear in the Dock or Command-Tab application switcher, regardless
of whether it is launched as a built app bundle or through `swift run`.

## Chosen Approach

Use both macOS agent-app configuration layers:

1. Add `LSUIElement = true` to the generated `Info.plist` in both app-bundle
   build scripts. This prevents a Dock icon from appearing during bundled app
   startup.
2. Set `NSApplication`'s activation policy to `.accessory` in both SwiftUI app
   entry points. This covers direct executable launches such as `swift run`,
   where the generated bundle `Info.plist` is not present.

The two layers intentionally overlap. The bundle setting avoids startup flicker,
while the runtime setting makes all supported launch paths consistent.

## UI and Window Behavior

- Existing `MenuBarExtra` scenes remain unchanged and continue to keep each app
  alive in the menu bar.
- Product onboarding, settings windows, Dev windows, floating panels, and HUDs
  remain available through their existing menu-bar actions.
- Both apps are absent from the Dock and Command-Tab, including while one of
  their windows is open.
- Quit remains available from the existing menu-bar controls.

## Files

- `scripts/build_app_bundle.sh`: emit `LSUIElement = true` for `Sideby.app`.
- `scripts/build_dev_app_bundle.sh`: emit `LSUIElement = true` for
  `SidebyDevApp.app`.
- `Sources/SidebyApp/SidebyApp.swift`: apply `.accessory` at startup.
- `Sources/SidebyDevApp/SidebyDevApp.swift`: apply `.accessory` at startup.

No Core, System, settings-model, or Space-switching behavior changes are in
scope.

## Verification

1. Before implementation, verify that the existing built product bundle lacks
   `LSUIElement`; this is the expected failing check.
2. Build both application bundles.
3. Verify `LSUIElement` is a Boolean `true` in both generated `Info.plist`
   files.
4. Run the full Swift test suite.
5. Launch each bundle and verify its process is running.
6. Verify neither running process owns a Dock tile through macOS application
   activation-policy inspection.
7. Re-verify code signatures after building.

## Release Baseline

Implementation starts from GitHub release `v0.5.0` (`dbab26b`). Existing local
Direct Space Jump research changes remain preserved and are not modified as part
of this work.

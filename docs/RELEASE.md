# Release

Use this checklist before publishing any public Sideby build.

## Packaging Guardrail

The release DMG must use the designed Finder installer window. A signed and
notarized DMG is not ready to publish if it opens as a plain file list.

Required installer presentation:

- Mounted volume and Finder window title should be `Sideby Installer`.
- Icon view should show `Sideby.app` on the left.
- An `/Applications` alias should appear on the right.
- A clear center affordance should point from `Sideby.app` to `/Applications`.
- No build folders, scripts, source files, or loose release artifacts should be visible.
- Window size, icon positions, background, and view options should be saved in the DMG.

Before uploading a release asset, mount the final DMG locally and visually verify
the installer window. If the Finder window does not match the designed app-to-
Applications layout, stop the release and rebuild the DMG.

## Checklist

1. Bump the public version in the app bundle scripts and README copy.
2. Run `swift test`.
3. Build `dist/Sideby.app` with `scripts/build_app_bundle.sh`.
4. Verify `CFBundleShortVersionString` and `CFBundleVersion`.
5. Sign and verify `dist/Sideby.app`.
6. Build the designed DMG installer, not a plain folder DMG.
7. Mount the DMG and verify the Finder installer window layout.
8. Sign, notarize, staple, and Gatekeeper-assess the DMG.
9. Compute and record the SHA-256 digest.
10. Create the Git tag and GitHub Release.
11. Upload the DMG asset and verify the published asset digest.

## 2026-06-03 Note

The `v0.2.1` release shipped with the app fixes, but the designed DMG installer
presentation was missed during packaging. Future releases must keep this file as
the packaging source of truth and must not publish until the designed DMG window
has been checked.

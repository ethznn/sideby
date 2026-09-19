# README media sources

These assets document Sideby 0.11.1. Screenshots use production views with sample data; animated desktop transitions are an explicitly labeled simulation.

Open [the visual preview](preview.html), [English README](../../README.md), or [한국어 README](../../README.ko.md).

## Reproduce

On macOS 14 or later, with the repository's Swift 6 toolchain:

```bash
bash scripts/render_readme_demo.sh
```

Run from a local graphical macOS session with no other SwiftPM build using this checkout. No external image packages, screen recording permissions, real external displays, or manual UI actions are required. The process takes these steps:

1. Run `ReadmeMediaRenderingTests` with `SIDEBY_RENDER_MEDIA=1` to render the production SwiftUI views offscreen.
2. Run `scripts/render_readme_demo.swift` to draw the sample desktops and encode the GIF with AppKit and ImageIO.
3. Run `scripts/verify_readme_media.swift` to check image dimensions, every GIF frame's duration, clean looping, size limits, and both READMEs' local links and asset references.

Set `SIDEBY_BUILD_PATH` to an absolute directory under a `.noindex` folder to keep build products and media intermediates outside the checkout. `SIDEBY_MEDIA_WORK_DIR` can independently redirect the intermediate media files.

The screenshot test defaults to `docs/images`; `SIDEBY_MEDIA_OUTPUT` can redirect the screenshots when running the test alone. The complete script deliberately writes to `docs/images` so its generated GIF and README references remain in sync.

This flow compiles tests and a renderer, not an installable app bundle. It does not change the product build number, sign, notarize, publish, or update the Sparkle feed.

## Data and provenance

[`demo-data.json`](demo-data.json) is the shared source for two simulated displays and two workspaces:

| Workspace | MacBook Pro | Studio Display |
| --- | --- | --- |
| Checkout / 결제 개발 | Checkout.swift | Checkout API |
| PR review / PR 리뷰 | Checkout PR #42 | Checkout preview |

- **Screenshots:** `ProductFloatingMenuPanelView`, `ProductSettingsView`, and `ProductOnboardingView` rendered using an in-memory `SidebyAppModel(testSettings:…)`, a discarding settings store, fake layout observations, and cached sample content names. No permission prompts, Space commands, input observers, app launch, or personal settings writes occur.
- **GIF matrix:** the same production `WorkspaceMatrixView`, rendered with the same data. Cursor and click emphasis are editorial overlays outside the app.
- **GIF desktops:** illustrated code, document, review, and preview windows drawn by the renderer. They are not screenshots of Xcode, a browser, or the user's work.
- **GIF movement:** sequential illustrative desktop movement. The timing does not measure Sideby's hardware performance or claim simultaneous macOS commands. Every frame is labeled `Simulated demo · Sample workspaces`.
- **Onboarding completion image:** a simulated successfully completed guide. It is not evidence that a hardware round trip was performed while generating media.
- **Icon:** the current repository asset, `Resources/AppIcon.icns`.

The fixtures belong to the test target and scripts. They are not a product demo mode and do not alter live display discovery or switching behavior.

## Output

| Asset | Size | Appearance |
| --- | --- | --- |
| `sideby-context-capture-{en,ko}.png` | 1360 × 1280 | Dark menu, including the default matrix |
| `sideby-settings-workspaces-{en,ko}.png` | 1680 × 1240 | Light Settings |
| `sideby-onboarding-workspaces-{en,ko}.png` | 1280 × 1520 | Light workspace preparation |
| `sideby-onboarding-roundtrip-{en,ko}.png` | 1280 × 1040 | Light completion and menu handoff |
| `sideby-demo-en.gif` | 960 × 640 | 62 frames, 22.04 seconds, infinite loop |
| `sideby-demo-poster-en.png` | 960 × 640 | Static alternative to the demo |

The historical `context-capture` filenames are retained so old links keep working. Their content is now the current everyday menu. Screenshots are generated at twice their logical view dimensions; README display widths are 640–720 pixels.

The GIF holds readable static scenes and adds frames only for cursor or desktop movement. Its size target is at most 5 MiB, with an enforced 8 MiB limit. The first and last encoded frames must match.

Intermediate files use `SIDEBY_MEDIA_WORK_DIR` when set. Their default paths are ignored by Git:

- `.build/readme-media/native/matrix.png`: native matrix source for the GIF.
- `.build/readme-media/frames/`: representative full-color animation frames for visual inspection.
- `.build/readme-media/timeline.json`: timing and scene manifest.
- `.build/readme-media/review/`: additional light/dark, single-display, unavailable-name, and long-content-name evidence.

## Verification and future edits

Inspect the English and Korean screenshots at their README display sizes. Read the Go/이동 buttons, workspace names, per-display content labels, and onboarding footer actions. Review the GIF's menu-click scene, both workspace results, repeated shortcut, and loop boundary. The [visual preview](preview.html) includes playback controls and defaults to a still image when reduced motion is requested.

Run `swift test` for product regressions. The media test is opt-in; the onboarding regression test runs normally and checks deferred content-name loading without changing saved work or round-trip progress.

When product UI changes, rerender native views first, then verify that the GIF's cursor still targets the real PR review **Go** button. Update both READMEs and the preview together when the main message changes. The version shown in the GIF comes from `demo-data.json`; keep it aligned with the release being documented.

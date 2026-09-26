# README media

The repository keeps the native screenshots, localized GIFs, and still images
used by the [English README](../../README.md), [한국어 README](../../README.ko.md),
and [visual preview](preview.html). Promotional MP4s are distributed as GitHub
Release attachments. Their editing, soundtrack, and rendering sources are
maintained locally and are not needed to build or test Sideby.

## Native screenshots

Screenshots use production `ProductFloatingMenuPanelView`, `ProductSettingsView`,
`ProductOnboardingView`, and `WorkspaceMatrixView` views with the fictional
two-display, two-workspace data in [demo-data.json](demo-data.json).
The in-memory model uses discarding settings stores, fake layout observations,
and sample content names. It does not request permissions, run Space commands,
launch Sideby, or write personal settings. The completed onboarding image
simulates a successful guide; it is not evidence of a real hardware round trip.

| Asset | Size | Appearance |
| --- | --- | --- |
| `sideby-context-capture-{en,ko}.png` | 1360 × 1280 | Dark menu with the matrix |
| `sideby-settings-workspaces-{en,ko}.png` | 1680 × 1240 | Light Settings |
| `sideby-onboarding-workspaces-{en,ko}.png` | 1280 × 1520 | Light workspace preparation |
| `sideby-onboarding-roundtrip-{en,ko}.png` | 1280 × 1040 | Light completion and menu handoff |

From a graphical macOS session with the repository's Swift toolchain:

```bash
SIDEBY_RENDER_MEDIA=1 swift test --filter ReadmeMediaRenderingTests/testRenderReadmeMedia
```

`SIDEBY_MEDIA_OUTPUT` redirects screenshots from `docs/images`;
`SIDEBY_MEDIA_WORK_DIR` redirects additional review images and intermediates
from `.build/readme-media`. Real external displays and Screen Recording
permission are not required. This command does not build an installable app,
sign, notarize, or publish.

## README loops and brand film

The English and Korean `docs/images/sideby-readme-loop-{en,ko}.gif` files are
960 × 540, with 100 frames over 10 seconds. Matching PNG files provide still
alternatives. The MacBook, two external displays, and desktop windows are
fictional illustrations of grouped switching, not recordings of macOS
performance. These are finished documentation assets; their production
pipeline is kept locally.

The 21-second v2 brand film uses actual Sideby views with sample data and
illustrated desktops. It contains no live action and uses an original,
synthesized score. The READMEs link to English and Korean MP4s in landscape
(1920 × 1080) and vertical (1080 × 1920) formats. The final films, including their original score, are attached to the
[0.12.0 release](https://github.com/ethznn/sideby/releases/tag/v0.12.0).
The linked README posters are `docs/images/sideby-brand-film-{en,ko}.png`
(1920 × 1080), taken from the finished films.

## Verification

```bash
swift scripts/verify_readme_media.swift
bash scripts/check_public_docs.sh
```

These checks use repository assets only. They verify image dimensions, GIF
timing and loop boundaries, local documentation links, and public-document
content. They do not verify Release download availability, MP4 playback, or
audio. Review those separately before publishing a release.

Run `swift test` for product regressions. Native screenshot rendering remains
opt-in. Review both languages at README display size, including workspace
names, Go/이동 buttons, desktop labels, and onboarding actions. Update both
READMEs and the preview together when changing the product message.

## Archived 0.11.1 demo

The older `docs/images/sideby-demo-en.gif` and `sideby-demo-poster-en.png` remain
for existing links. This two-display demo is 960 × 640, with 62 frames over
22.04 seconds. The existing `bash scripts/render_readme_demo.sh` reproduces it
from the two-display fixture and also regenerates native screenshots. It does
not reproduce the current three-display README loops or the brand film.

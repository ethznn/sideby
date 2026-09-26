# README media

The repository keeps the native screenshots, localized GIFs, and still images
used by the [English README](../../README.md), [한국어 README](../../README.ko.md),
and [visual preview](preview.html). Promotional MP4s and their editing,
soundtrack, and rendering sources are maintained locally and are not needed
to build or test Sideby. Release attachments are reserved for installers,
release notes, and update metadata.

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

## Current README showreel: Triptych

Both READMEs lead with a localized, silent 7.4-second Triptych preview:
[English GIF](../images/sideby-triptych-en.gif) ·
[한국어 GIF](../images/sideby-triptych-ko.gif).
Each is 960 × 540, with 74 frames at 10 fps, and loops continuously.
The cut shows displays switching separately, the keyboard shortcut, and all
three displays switching together and back. It omits the dense matrix scene
and the long logo ending. Fine film grain is omitted in the GIF to reduce size.

The 1920 × 1080 still alternatives show the three displays together:
[English PNG](../images/sideby-triptych-en.png) ·
[한국어 PNG](../images/sideby-triptych-ko.png).
The [visual preview](preview.html) has a playback toggle and starts with a still
image when reduced motion is requested. The READMEs link to their still images.

All desktops in this showreel are illustrations with fictional planning,
AI-agent and code content; they are not actual app captures or measurements of
macOS switching speed. The native screenshots below the showreel in each README
remain actual production views with sample data.

Full 15-second English and Korean MP4 exports with the original score stay in
the ignored local marketing directory, together with their production files.
The README uses only repository GIFs and PNGs, so its media can be viewed and
verified from a clean checkout without a release attachment or production files.

## Archived README loops and brand film

The English and Korean `docs/images/sideby-readme-loop-{en,ko}.gif` files are
960 × 540, with 100 frames over 10 seconds. Matching PNG files provide still
alternatives. The MacBook, two external displays, and desktop windows are
fictional illustrations of grouped switching, not recordings of macOS
performance. These are finished documentation assets; their production
pipeline is kept locally.

The 21-second v2 brand film uses actual Sideby views with sample data and
illustrated desktops. It contains no live action and uses an original,
synthesized score. The English and Korean MP4s in landscape (1920 × 1080)
and vertical (1080 × 1920) formats are kept locally. Promotional MP4 attachments
were removed from the 0.12.0 release; the repository previews remain available.
The archived `docs/images/sideby-brand-film-{en,ko}.gif` files are
7.6-second silent previews cut from the final film
(hook → shortcut and matrix → all three displays switching → brand and logo).
Each 960 × 540 GIF has 76 frames at 10 fps and loops continuously.
The 1920 × 1080 PNGs with the same names remain available as still alternatives.
These files and the 10-second loops are retained for existing links; the current
READMEs use only Triptych to avoid repeating the same switching explanation.

## Marketing workspace and publishing

Promotional films, their edit sources, scores, render scripts and full-resolution
renders live in the local `marketing/` directory at the repository root. The
whole directory is ignored by Git, so drafts and large files never enter history.

Publish a finished asset only when a document needs it:

| Asset | Where it goes | Tracked |
| --- | --- | --- |
| README preview GIF and still PNG | `docs/images/` | Yes |
| Full film MP4 (with sound, landscape or vertical) | Local `marketing/` directory | No |
| Edit sources, scores, stills, contact sheets, drafts | `marketing/` | No |

When you copy a GIF or PNG into `docs/images/`, add it to both READMEs, update the
expected sizes and frame counts in `scripts/verify_readme_media.swift`, and run
the checks below. Documentation must not link into `marketing/` or to promotional
MP4 release attachments. Keep app downloads and update metadata separate from
marketing media.

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
not reproduce Triptych, the three-display loops, or the brand film.

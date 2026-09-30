# README media

The current English and Korean READMEs explain the 0.13.0 workflow: save the
setup you are using, add another when needed, and choose a saved setup to
return. All current screenshots use actual production views backed by fictional
sample data. No live desktop, personal window title, or account is captured.

## Current walkthrough

[English GIF](../images/sideby-save-flow-en.gif) ·
[한국어 GIF](../images/sideby-save-flow-ko.gif) ·
[English still](../images/sideby-save-flow-en.png) ·
[한국어 정지 이미지](../images/sideby-save-flow-ko.png)

The 960 × 760 walkthrough lasts 15 seconds, with 75 GIF frames at 5 fps. Its five
scenes show an empty list, the save form, the first setup, a second setup,
and the first setup selected again. Crossfades explain the sequence; they do
not measure or reproduce actual macOS desktop-switching timing.

The [visual preview](preview.html) includes a playback toggle, starts with a still
when reduced motion is requested, and shows both languages. The native screenshots
below the preview cover the menu, save form, settings, and first-setup guide.

## Regenerate production views and video

Run from the repository root in a graphical macOS session:

```bash
SIDEBY_RENDER_MEDIA=1 swift test --filter ReadmeMediaRenderingTests
swift scripts/render_workspace_preview.swift
swift scripts/verify_readme_media.swift
bash scripts/check_public_docs.sh
```

The opt-in test renders SwiftUI/AppKit product views offscreen with discarding
settings stores. It does not launch the product, send global input, move desktops,
or request permissions. `docs/media/demo-data.json` supplies fictional names.
`SIDEBY_MEDIA_WORK_DIR` can override the default `.build/readme-media` directory;
use the same value for the test and the video renderer.

| Current PNG | Pixels | Appearance |
| --- | --- | --- |
| `sideby-context-capture-{en,ko}.png` | 1360 × 1280 | Dark menu |
| `sideby-save-workspace-{en,ko}.png` | 1060 × 960 | Light save form |
| `sideby-settings-workspaces-{en,ko}.png` | 1680 × 1240 | Light settings |
| `sideby-onboarding-saved-workspaces-{en,ko}.png` | 1280 × 1520 | Light first-setup guide |
| `sideby-save-flow-{en,ko}.png` | 960 × 760 | Walkthrough still |

Native views render at 2×. Additional fixture images under the work directory
cover dark appearance, one display, missing titles, and long content names.
The walkthrough renderer produces a silent H.264 MP4 at 960 × 760, 20 fps in the
ignored local marketing directory. It checks dimensions, duration, frame rate,
and absence of audio. The five source scenes are saved there for visual review.

## Marketing setup and publishing

| Asset | Location | Tracked |
| --- | --- | --- |
| Current README GIFs and PNGs | `docs/images/` | Yes |
| Full MP4 exports and scene review images | Local `marketing/` directory | No |
| Temporary native render fixtures | `.build/readme-media/` | No |

Keep installer, release notes, and signed update metadata as the release assets.
Documentation must not link into the ignored marketing directory or to promotional
MP4 release attachments. Inspect every new image and all video scenes before
publishing, and follow the maintainer’s image-approval instructions.

## Verification

The media verifier checks dimensions, GIF frame counts and timing, looping flags,
animation, size limits, localized README usage, and local documentation links.
It does not verify release download availability or establish visual correctness.
Review both languages at their README display sizes, including name fields,
setup labels, save actions, and the empty-state explanation. Review the MP4
separately from the GIF.

The opt-in UI renderer is separate from product regressions. Run `swift test`
and the native user-journey checks described in [Development](../DEVELOPMENT.md)
when changing product behavior.

## Archived media

Existing media remain for historical links, but the current READMEs use the
save-setup walkthrough:

- `sideby-triptych-{en,ko}.gif`: illustrated three-display sequence, 960 × 540,
  74 frames over 7.4 seconds; matching stills are 1920 × 1080.
- `sideby-readme-loop-{en,ko}.gif`: 960 × 540, 100 frames over 10 seconds;
  matching stills are 960 × 540.
- `sideby-brand-film-{en,ko}.gif`: 960 × 540, 76 frames over 7.6 seconds;
  matching stills are 1920 × 1080.
- `sideby-demo-en.gif`: the older two-display 0.11.1 demo, 960 × 640,
  62 frames over 22.04 seconds, with a matching poster.
- `sideby-onboarding-workspaces-{en,ko}.png` and
  `sideby-onboarding-roundtrip-{en,ko}.png`: earlier onboarding views.

Archived illustrated switching scenes do not measure macOS performance. Older
films’ full MP4s and production files remain local. The older
`scripts/render_readme_demo.sh` pipeline is for the archived demo; use the commands
above for the current product views and save-setup walkthrough.

# README media

The product views, usage tutorial, and promotional film describe Sideby 1.1.0.
The tutorial uses production UI; the promotional film uses illustrations.

## Current promotional film

The 22.5-second edit keeps the earlier Kinetic film’s three-panel opening,
scattered typography, physical keycaps, “Side / by / side” payoff, animated logo,
and original synthesized score. Its story now shows:

1. The friction of switching displays one by one.
2. `⌥⇧Space` and a circular-menu selection switching three displays together.
3. A Space dragged from its display’s list into the blank column, creating a connection immediately.
4. Same-display cells swapping when dragged, then `⌥ Option` held during a drop to copy.

The film uses simplified illustrations and fictional data. It is not a product
capture, a switching benchmark, or a demonstration of app/window restoration.
There is no naming dialog or separate save action in the current workflow.

[한국어 GIF](../images/sideby-connections-film-ko.gif) ·
[English GIF](../images/sideby-connections-film-en.gif) ·
[한국어 정지 이미지](../images/sideby-connections-film-ko.png) ·
[English still](../images/sideby-connections-film-en.png) ·
[Preview with playback controls](https://ethznn.github.io/sideby/#film)

| Export | Size | Timing |
| --- | --- | --- |
| README GIF, silent | 960 × 540 | 450 frames, 20 fps, 22.5 seconds |
| Poster | 1920 × 1080 | Synchronized-switching scene |
| Local MP4 with original stereo score | 1920 × 1080 | 1350 frames, 60 fps, 22.5 seconds |

The full MP4s, score, HTML source, and render tools remain in the ignored
`marketing/motion/showreel-connections-1.1.0/` and
`marketing/scripts/connections110/` directories. Earlier originals are preserved.
The README links to tracked GIFs and stills, with playback controls on the public site.
Portable local previews are also available as `preview.html` and `tutorial.html`.
The preview starts with a still and supports both languages and playback controls.
The site honors reduced motion and provides a stop button.

## Current usage tutorial

The 28-second tutorial uses current production views and fictional fixtures:

1. Drag one Space from each display into the same connection (0–3.2s).
2. Use ⌥⇧Space and Save current Spaces in the center to add the current combination (3.2–6.2s).
3. Switch from coding to PR review with the circular menu (6.2–11.2s).
4. Swap same-display cells, undo, and Option-drag to copy (11.2–16.6s).
5. Click the pencil to rename, switch together, and return with ⌥⇧Tab (16.6–25s).
6. Delete one connection immediately and restore it with Undo (25–28s).

[한국어 GIF](../images/sideby-tutorial-ko.gif) · [English GIF](../images/sideby-tutorial-en.gif) · [한국어 재생·정지](https://ethznn.github.io/sideby/ko/#tutorial) · [English playback controls](https://ethznn.github.io/sideby/#tutorial)

Both GIFs are 960 × 540, 20 fps, 560 frames, 28 seconds. Posters are 1920 × 1080.
There is no intro, outro, or music. Each drag takes 0.4 seconds. The first-drop
layout stays in place. A native pointing-hand image and sector hover identify
clickable targets without an extra floating rectangle around the name.
Pointer motion, hover, text entry, and screen transitions are explanatory
reconstructions, not live recordings or switching benchmarks.

Production sources and masters remain in ignored
`marketing/motion/tutorial-wheel-1.1.0/` and
`marketing/scripts/tutorial-wheel-1.1.0/`. Earlier cuts are archived there.
The public website starts with a still and supports playing, stopping, and reduced
motion. The local `tutorial.html` offers the same GIF controls.

Regenerate native scenes with isolated fictional data:

```bash
SIDEBY_RENDER_TUTORIAL_FAST=1 SIDEBY_MEDIA_OUTPUT=/tmp/sideby-tutorial-scenes swift test --filter ReadmeMediaRenderingTests.testRenderFastConnectionTutorialScenes
```

## Current product views

These 1.1.0 images render production SwiftUI/AppKit views using fictional fixtures.
Connected cards, dashed empty cells, and the explicit Go together action show
the difference between editing a connection and switching Spaces.
No personal desktop, window title, account, or Space configuration is captured.

| PNG | Pixels | Contents |
| --- | --- | --- |
| `sideby-connections-settings-{en,ko}.png` | 2080 × 1280 | Space list and directly editable connection table |
| `sideby-connections-{en,ko}.png` | 944 × 1136 | Transparent circular menu, center save, hover tools, Undo, and clear-all controls |
| `sideby-connections-onboarding-{en,ko}.png` | 1360 × 1280 | First-use guide |

Regenerate product views from a graphical macOS session:

```bash
SIDEBY_RENDER_MEDIA=1 SIDEBY_MEDIA_OUTPUT=/tmp/sideby-connections-media swift test --filter ReadmeMediaRenderingTests.testRenderCurrentConnectionsMedia
```

The opt-in renderer uses isolated settings stores. It does not launch the product,
change real connections, move Spaces, or request permissions. Review the output
before copying the six current PNGs into `docs/images/`.

## Verification and publication

```bash
swift scripts/verify_readme_media.swift
python3 scripts/build_site.py --output .build/website-media-check
python3 scripts/check_site.py .build/website-media-check
bash scripts/check_public_docs.sh
```

The media verifier checks current PNG dimensions, every current GIF frame,
timing, loop flags, animation, size limits, localized README references, and
local documentation links. It also retains checks on historical media. It does
not establish visual correctness or release availability. Inspect both language
versions at README display size. For promotional film exports, inspect the final
MP4 separately; the usage tutorial is a silent GIF.

The local film verifier decodes every MP4 video and audio frame, checks 60 fps,
duration, dimensions, stereo audio, clipping, and progressive playback metadata.
Keep its output and scene-review images locally.

Before external publication, open the new imagery, enumerate visible content,
and obtain the maintainer’s confirmation. Keep installers, release notes, and
signed update metadata as release assets; promotional MP4s are not release
attachments. Do not link public documentation into ignored production folders.

## Archived media

The earlier `sideby-kinetic-*`, `sideby-setups-film-*`, `sideby-save-flow-*`,
`sideby-save-workspace-*`, and dedicated setup-editor images describe the
previous save-centered design. They remain for historical links and are not
current usage instructions. `sideby-triptych-*`, `sideby-brand-film-*`,
`sideby-readme-loop-*`, and `sideby-demo-*` are earlier promotional edits.
Old onboarding and context-capture images are preserved as well.

The older `scripts/render_workspace_preview.swift` and
`scripts/render_readme_demo.sh` pipelines produce archived walkthroughs.
Use the current production-view renderer above for the current app.

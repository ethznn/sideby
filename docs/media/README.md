# README media

The current film and product views describe Sideby 1.0.0: connect existing
Spaces, switch displays together, and adjust connections in place.

## Current promotional film

The 22.5-second edit keeps the earlier Kinetic film’s three-panel opening,
scattered typography, physical keycaps, “Side / by / side” payoff, animated logo,
and original synthesized score. Its story now shows:

1. The friction of switching displays one by one.
2. `⌥⇧Space` and a column selection switching three displays together.
3. A Space dragged from its display’s list into the blank column, creating a connection immediately.
4. Same-display cells swapping when dragged, then `⌥ Option` held during a drop to copy.

The film uses simplified illustrations and fictional data. It is not a product
capture, a switching benchmark, or a demonstration of app/window restoration.
There is no naming dialog or separate save action in the current workflow.

[한국어 GIF](../images/sideby-connections-film-ko.gif) ·
[English GIF](../images/sideby-connections-film-en.gif) ·
[한국어 정지 이미지](../images/sideby-connections-film-ko.png) ·
[English still](../images/sideby-connections-film-en.png) ·
[Preview with playback controls](preview.html)

| Export | Size | Timing |
| --- | --- | --- |
| README GIF, silent | 960 × 540 | 450 frames, 20 fps, 22.5 seconds |
| Poster | 1920 × 1080 | Synchronized-switching scene |
| Local MP4 with original stereo score | 1920 × 1080 | 1350 frames, 60 fps, 22.5 seconds |

The full MP4s, score, HTML source, and render tools remain in the ignored
`marketing/motion/showreel-connections-1.0.0/` and
`marketing/scripts/connections100/` directories. Earlier originals are preserved.
The README links only to tracked GIFs, stills, and the portable preview page.
The preview starts with a still and supports both languages and playback controls.
The site honors reduced motion and provides a stop button.

## Current product views

These images render production SwiftUI/AppKit views using fictional fixtures.
No personal desktop, window title, account, or Space configuration is captured.

| PNG | Pixels | Contents |
| --- | --- | --- |
| `sideby-connections-settings-{en,ko}.png` | 2080 × 1280 | Space list and directly editable connection table |
| `sideby-connections-{en,ko}.png` | 1360 × 1160 | Menu-bar connection table |
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
versions at README display size and inspect the final MP4 separately.

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

#!/bin/bash
set -euo pipefail

# Native SwiftUI screenshots + an explicitly labeled desktop simulation.
# No screen recorder, real monitor setup, user settings, or external packages.
media_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$media_root"
mkdir -p .build/readme-media

SIDEBY_RENDER_MEDIA=1 SIDEBY_MEDIA_OUTPUT="$media_root/docs/images" \
  swift test --filter ReadmeMediaRenderingTests
swift scripts/render_readme_demo.swift
swift scripts/verify_readme_media.swift

printf '\nREADME draft: %s/docs/media/preview.html\n' "$media_root"

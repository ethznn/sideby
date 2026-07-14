#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${SIDEBY_VERSION:?error: SIDEBY_VERSION is required}"
BUILD_NUMBER="${SIDEBY_BUILD_NUMBER:?error: SIDEBY_BUILD_NUMBER is required}"
NOTES_PATH="${SIDEBY_RELEASE_NOTES_PATH:?error: SIDEBY_RELEASE_NOTES_PATH is required}"
TAG="${SIDEBY_RELEASE_TAG:-v$VERSION}"
DMG_PATH="${SIDEBY_DMG_PATH:-$ROOT_DIR/dist/Sideby-$VERSION.dmg}"
ACCOUNT="${SIDEBY_SPARKLE_ACCOUNT:-sideby-sparkle}"

"$ROOT_DIR/scripts/validate_release_metadata.sh" "$VERSION" "$BUILD_NUMBER"
[[ -f "$DMG_PATH" ]] || { echo "error: missing DMG at $DMG_PATH" >&2; exit 1; }
[[ -f "$NOTES_PATH" ]] || { echo "error: missing release notes at $NOTES_PATH" >&2; exit 1; }

codesign --verify --verbose "$DMG_PATH" >&2
SIGNING_DETAILS="$(codesign --display --verbose=4 "$DMG_PATH" 2>&1)"
printf '%s\n' "$SIGNING_DETAILS" >&2
if ! grep -q '^Authority=Developer ID Application:' <<< "$SIGNING_DETAILS"; then
  echo "error: release DMG must be signed with a Developer ID Application identity" >&2
  exit 1
fi
xcrun stapler validate "$DMG_PATH" >&2

GENERATE_APPCAST="$(find "$ROOT_DIR/.build/artifacts" -path '*/Sparkle/bin/generate_appcast' -type f -print -quit)"
SIGN_UPDATE="$(find "$ROOT_DIR/.build/artifacts" -path '*/Sparkle/bin/sign_update' -type f -print -quit)"
[[ -x "$GENERATE_APPCAST" && -x "$SIGN_UPDATE" ]] || {
  echo "error: resolve Sparkle tools with swift package resolve" >&2
  exit 1
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sideby-appcast.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cp "$DMG_PATH" "$WORK_DIR/Sideby-$VERSION.dmg"
cp "$NOTES_PATH" "$WORK_DIR/Sideby-$VERSION.md"

"$GENERATE_APPCAST" \
  --account "$ACCOUNT" \
  --download-url-prefix "https://github.com/ethznn/sideby/releases/download/$TAG/" \
  --release-notes-url-prefix "https://github.com/ethznn/sideby/releases/download/$TAG/" \
  --link "https://github.com/ethznn/sideby/releases/tag/$TAG" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$WORK_DIR/appcast.xml" \
  "$WORK_DIR" >&2

"$SIGN_UPDATE" --account "$ACCOUNT" --verify "$WORK_DIR/appcast.xml" >&2
mkdir -p "$ROOT_DIR/dist"
cp "$WORK_DIR/Sideby-$VERSION.md" "$ROOT_DIR/dist/Sideby-$VERSION.md"
cp "$WORK_DIR/appcast.xml" "$ROOT_DIR/dist/appcast.xml"

printf '%s\n' \
  "$DMG_PATH" \
  "$ROOT_DIR/dist/Sideby-$VERSION.md" \
  "$ROOT_DIR/dist/appcast.xml"

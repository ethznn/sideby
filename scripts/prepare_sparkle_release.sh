#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${SIDEBY_VERSION:?error: SIDEBY_VERSION is required}"
BUILD_NUMBER="${SIDEBY_BUILD_NUMBER:?error: SIDEBY_BUILD_NUMBER is required}"
NOTES_PATH="${SIDEBY_RELEASE_NOTES_PATH:?error: SIDEBY_RELEASE_NOTES_PATH is required}"
TAG="${SIDEBY_RELEASE_TAG-v$VERSION}"
DMG_PATH="${SIDEBY_DMG_PATH:-$ROOT_DIR/dist/Sideby-$VERSION.dmg}"
ACCOUNT="${SIDEBY_SPARKLE_ACCOUNT:-sideby-sparkle}"

"$ROOT_DIR/scripts/validate_release_metadata.sh" "$VERSION" "$BUILD_NUMBER"
if [[ "$TAG" != "v$VERSION" ]]; then
  echo "error: release tag must be v$VERSION" >&2
  exit 1
fi
[[ -f "$DMG_PATH" ]] || { echo "error: missing DMG at $DMG_PATH" >&2; exit 1; }
[[ -f "$NOTES_PATH" ]] || { echo "error: missing release notes at $NOTES_PATH" >&2; exit 1; }

codesign --verify --verbose "$DMG_PATH" >&2
DEVELOPER_ID_REQUIREMENT='=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
codesign --verify --verbose -R "$DEVELOPER_ID_REQUIREMENT" "$DMG_PATH" >&2
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

APPCAST_PATH="$WORK_DIR/appcast.xml"
/usr/bin/xmllint --noout "$APPCAST_PATH"
APPCAST_ITEM_COUNT="$(
  /usr/bin/xmllint --xpath \
    'count(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"])' \
    "$APPCAST_PATH"
)"
if [[ "$APPCAST_ITEM_COUNT" != "1" ]]; then
  echo "error: appcast must contain exactly one update item; found $APPCAST_ITEM_COUNT" >&2
  exit 1
fi

APPCAST_BUILD_NUMBER="$(
  /usr/bin/xmllint --xpath \
    'string((/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"][1]/*[local-name()="enclosure"]/@*[local-name()="version"])[1])' \
    "$APPCAST_PATH"
)"
if [[ "$APPCAST_BUILD_NUMBER" != "$BUILD_NUMBER" ]]; then
  echo "error: appcast build number $APPCAST_BUILD_NUMBER does not match requested build number $BUILD_NUMBER" >&2
  exit 1
fi

APPCAST_SHORT_VERSION="$(
  /usr/bin/xmllint --xpath \
    'string((/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"][1]/*[local-name()="enclosure"]/@*[local-name()="shortVersionString"])[1])' \
    "$APPCAST_PATH"
)"
if [[ "$APPCAST_SHORT_VERSION" != "$VERSION" ]]; then
  echo "error: appcast short version $APPCAST_SHORT_VERSION does not match requested version $VERSION" >&2
  exit 1
fi

EXPECTED_DMG_URL="https://github.com/ethznn/sideby/releases/download/v$VERSION/Sideby-$VERSION.dmg"
APPCAST_DMG_URL="$(
  /usr/bin/xmllint --xpath \
    'string((/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"][1]/*[local-name()="enclosure"]/@url)[1])' \
    "$APPCAST_PATH"
)"
if [[ "$APPCAST_DMG_URL" != "$EXPECTED_DMG_URL" ]]; then
  echo "error: appcast enclosure URL does not match expected versioned URL: $EXPECTED_DMG_URL" >&2
  exit 1
fi

EXPECTED_NOTES_URL="https://github.com/ethznn/sideby/releases/download/v$VERSION/Sideby-$VERSION.md"
APPCAST_NOTES_URL="$(
  /usr/bin/xmllint --xpath \
    'string((/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"][1]/*[local-name()="releaseNotesLink"])[1])' \
    "$APPCAST_PATH"
)"
if [[ "$APPCAST_NOTES_URL" != "$EXPECTED_NOTES_URL" ]]; then
  echo "error: appcast release notes URL does not match expected versioned URL: $EXPECTED_NOTES_URL" >&2
  exit 1
fi

"$SIGN_UPDATE" --account "$ACCOUNT" --verify "$APPCAST_PATH" >&2
mkdir -p "$ROOT_DIR/dist"
cp "$WORK_DIR/Sideby-$VERSION.md" "$ROOT_DIR/dist/Sideby-$VERSION.md"
cp "$APPCAST_PATH" "$ROOT_DIR/dist/appcast.xml"

printf '%s\n' \
  "$DMG_PATH" \
  "$ROOT_DIR/dist/Sideby-$VERSION.md" \
  "$ROOT_DIR/dist/appcast.xml"

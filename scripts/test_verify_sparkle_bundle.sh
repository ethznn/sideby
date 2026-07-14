#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$ROOT_DIR/scripts/verify_sparkle_bundle.sh"
TEMPORARY_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMPORARY_ROOT"' EXIT

app="$TEMPORARY_ROOT/Sideby.app"
framework="$app/Contents/Frameworks/Sparkle.framework"
info_plist="$app/Contents/Info.plist"
output="$TEMPORARY_ROOT/verifier-output"

write_plist_key() {
  local key="$1"
  local type="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$info_plist" >/dev/null
}

mkdir -p "$app/Contents/MacOS"
cp /usr/bin/true "$app/Contents/MacOS/Sideby"

write_plist_key CFBundleExecutable string Sideby
write_plist_key CFBundleIdentifier string io.github.ethznn.sideby.fixture
write_plist_key CFBundlePackageType string APPL
write_plist_key CFBundleVersion string 1
write_plist_key SUFeedURL string \
  "https://github.com/ethznn/sideby/releases/latest/download/appcast.xml"
write_plist_key SUPublicEDKey string \
  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
write_plist_key SUScheduledCheckInterval integer 86400
write_plist_key SUAllowsAutomaticUpdates bool false
write_plist_key SUVerifyUpdateBeforeExtraction bool true
write_plist_key SURequireSignedFeed bool true

mkdir -p "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
touch "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
chmod +x "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"

# A framework with only the required verifier paths is not a signable bundle.
# Add the smallest realistic Mach-O structure so deep verification remains strict.
mkdir -p \
  "$framework/Versions/B/Resources" \
  "$framework/Versions/B/Updater.app/Contents/MacOS"
cp /usr/bin/true "$framework/Versions/B/Sparkle"
cp /usr/bin/true "$framework/Versions/B/Autoupdate"
cp /usr/bin/true "$framework/Versions/B/Updater.app/Contents/MacOS/Updater"

/usr/libexec/PlistBuddy \
  -c 'Add :CFBundleExecutable string Sparkle' \
  -c 'Add :CFBundleIdentifier string io.github.ethznn.sideby.fixture.sparkle' \
  -c 'Add :CFBundlePackageType string FMWK' \
  -c 'Add :CFBundleVersion string 1' \
  "$framework/Versions/B/Resources/Info.plist" >/dev/null
/usr/libexec/PlistBuddy \
  -c 'Add :CFBundleExecutable string Updater' \
  -c 'Add :CFBundleIdentifier string io.github.ethznn.sideby.fixture.updater' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :CFBundleVersion string 1' \
  "$framework/Versions/B/Updater.app/Contents/Info.plist" >/dev/null

ln -s B "$framework/Versions/Current"
ln -s Versions/Current/Resources "$framework/Resources"
ln -s Versions/Current/Sparkle "$framework/Sparkle"
ln -s Versions/Current/Updater.app "$framework/Updater.app"
ln -s Versions/Current/Autoupdate "$framework/Autoupdate"

codesign --force --options runtime --sign - "$framework/Versions/B/Autoupdate" >/dev/null 2>&1
codesign --force --options runtime --sign - "$framework/Versions/B/Updater.app" >/dev/null 2>&1
codesign --force --options runtime --sign - "$framework" >/dev/null 2>&1
codesign --force --options runtime --sign - "$app" >/dev/null 2>&1

if ! "$VERIFIER" "$app" >"$output" 2>&1; then
  cat "$output" >&2
  exit 1
fi

ln -s Versions/Current/XPCServices "$framework/XPCServices"
codesign --force --options runtime --sign - "$framework" >/dev/null 2>&1
codesign --force --options runtime --sign - "$app" >/dev/null 2>&1

if "$VERIFIER" "$app" >"$output" 2>&1; then
  echo "expected verifier to reject framework-root XPCServices" >&2
  exit 1
fi
if ! grep -q 'non-sandbox app must not ship Sparkle XPC services' "$output"; then
  cat "$output" >&2
  exit 1
fi

rm -rf "$framework/XPCServices"
codesign --force --options runtime --sign - "$framework" >/dev/null 2>&1
codesign --force --options runtime --sign - "$app" >/dev/null 2>&1

/usr/libexec/PlistBuddy -c 'Set :SUPublicEDKey x' "$info_plist"
codesign --force --options runtime --sign - "$app" >/dev/null 2>&1

if "$VERIFIER" "$app" >"$output" 2>&1; then
  echo "expected verifier to reject an invalid SUPublicEDKey" >&2
  exit 1
fi
if ! grep -q 'invalid SUPublicEDKey' "$output"; then
  cat "$output" >&2
  exit 1
fi

/usr/libexec/PlistBuddy \
  -c 'Set :SUPublicEDKey AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
  "$info_plist"
codesign --force --options runtime --sign - "$app" >/dev/null 2>&1

/usr/libexec/PlistBuddy \
  -c 'Set :SUFeedURL https://example.invalid/appcast.xml' \
  "$info_plist"

if "$VERIFIER" "$app" >"$output" 2>&1; then
  echo "expected verifier to reject an unexpected SUFeedURL" >&2
  exit 1
fi
if ! grep -q 'unexpected SUFeedURL' "$output"; then
  cat "$output" >&2
  exit 1
fi

echo "Sparkle bundle verifier tests passed"

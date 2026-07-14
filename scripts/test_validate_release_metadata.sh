#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate_release_metadata.sh"

expect_pass() {
  local version="$1"
  local build_number="$2"
  local output

  if output="$("$VALIDATOR" "$version" "$build_number" 2>&1)"; then
    return
  fi

  echo "expected version $version and build $build_number to pass: $output" >&2
  exit 1
}

expect_fail() {
  local expected_message="$1"
  local version="$2"
  local build_number="$3"
  local output

  if output="$("$VALIDATOR" "$version" "$build_number" 2>&1)"; then
    echo "expected version $version and build $build_number to fail" >&2
    exit 1
  fi

  if [[ "$output" != *"$expected_message"* ]]; then
    echo "expected failure containing '$expected_message': $output" >&2
    exit 1
  fi
}

expect_pass 0.7.0 2
expect_pass 1.0.0 100
expect_fail "semantic version" 0.7 2
expect_fail "positive integer" 0.7.0 two
expect_fail "greater than shipped build 1" 0.7.0 1

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sideby-release-metadata-test.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p \
  "$TEST_ROOT/project/scripts" \
  "$TEST_ROOT/project/dist/Sideby.app/Contents" \
  "$TEST_ROOT/bin"
cp "$ROOT_DIR/scripts/build_release_dmg.sh" "$TEST_ROOT/project/scripts/"
cp "$VALIDATOR" "$TEST_ROOT/project/scripts/"

cat > "$TEST_ROOT/project/dist/Sideby.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>0.6.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST

cat > "$TEST_ROOT/bin/swift" <<'SWIFT'
#!/usr/bin/env bash
echo "unexpected: DMG tooling reached" >&2
exit 99
SWIFT
chmod +x "$TEST_ROOT/bin/swift"

BUILD_SCRIPT="$TEST_ROOT/project/scripts/build_release_dmg.sh"

if output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    SIDEBY_SKIP_APP_BUILD=1 \
    env -u SIDEBY_VERSION -u SIDEBY_BUILD_NUMBER \
    "$BUILD_SCRIPT" 2>&1
)"; then
  echo "expected release DMG build without metadata to fail" >&2
  exit 1
fi
if [[ "$output" != *"SIDEBY_VERSION is required for a release DMG"* ]]; then
  echo "expected missing release version failure: $output" >&2
  exit 1
fi

if output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    SIDEBY_SKIP_APP_BUILD=1 \
    SIDEBY_VERSION=0.7.0 \
    SIDEBY_BUILD_NUMBER=2 \
    "$BUILD_SCRIPT" 2>&1
)"; then
  echo "expected mismatched app metadata to fail" >&2
  exit 1
fi
if [[ "$output" != *"version 0.6.0 does not match requested version 0.7.0"* ]]; then
  echo "expected app version mismatch failure: $output" >&2
  exit 1
fi

/usr/libexec/PlistBuddy \
  -c 'Set :CFBundleShortVersionString 0.7.0' \
  "$TEST_ROOT/project/dist/Sideby.app/Contents/Info.plist"

if output="$(
  PATH="$TEST_ROOT/bin:$PATH" \
    SIDEBY_SKIP_APP_BUILD=1 \
    SIDEBY_VERSION=0.7.0 \
    SIDEBY_BUILD_NUMBER=2 \
    "$BUILD_SCRIPT" 2>&1
)"; then
  echo "expected mismatched app build number to fail" >&2
  exit 1
fi
if [[ "$output" != *"build number 1 does not match requested build number 2"* ]]; then
  echo "expected app build number mismatch failure: $output" >&2
  exit 1
fi

PREPARE_SCRIPT="$ROOT_DIR/scripts/prepare_sparkle_release.sh"
if [[ ! -f "$PREPARE_SCRIPT" ]]; then
  echo "expected release preparation script at $PREPARE_SCRIPT" >&2
  exit 1
fi

PREPARE_ROOT="$TEST_ROOT/prepare-project"
PREPARE_BIN="$TEST_ROOT/prepare-bin"
SPARKLE_BIN="$PREPARE_ROOT/.build/artifacts/sparkle/Sparkle/bin"
CALL_LOG="$TEST_ROOT/prepare-calls.log"
PREPARE_STDERR="$TEST_ROOT/prepare-stderr.log"
mkdir -p "$PREPARE_ROOT/scripts" "$PREPARE_ROOT/dist" "$PREPARE_BIN" "$SPARKLE_BIN"
cp "$PREPARE_SCRIPT" "$PREPARE_ROOT/scripts/"
cp "$VALIDATOR" "$PREPARE_ROOT/scripts/"
printf 'fake signed and stapled DMG\n' > "$PREPARE_ROOT/dist/Sideby-0.7.0.dmg"
printf '# Sideby 0.7.0\n\nRelease notes.\n' > "$TEST_ROOT/Sideby-0.7.0.md"

cat > "$PREPARE_BIN/codesign" <<'CODESIGN'
#!/usr/bin/env bash
printf 'codesign\t%s\n' "$*" >> "$CALL_LOG"
if [[ "$*" == *"--display"* ]]; then
  echo "Authority=${FAKE_SIGNING_AUTHORITY:-Developer ID Application: Sideby Test}" >&2
else
  echo "codesign validation output"
fi
CODESIGN

cat > "$PREPARE_BIN/xcrun" <<'XCRUN'
#!/usr/bin/env bash
printf 'xcrun\t%s\n' "$*" >> "$CALL_LOG"
echo "stapler validation output"
XCRUN

cat > "$SPARKLE_BIN/generate_appcast" <<'GENERATE_APPCAST'
#!/usr/bin/env bash
printf 'generate_appcast' >> "$CALL_LOG"
output_path=""
for argument in "$@"; do
  printf '\t%s' "$argument" >> "$CALL_LOG"
done
printf '\n' >> "$CALL_LOG"

while (( $# > 0 )); do
  if [[ "$1" == "-o" ]]; then
    output_path="$2"
    shift 2
  else
    shift
  fi
done

[[ -n "$output_path" ]] || { echo "missing appcast output path" >&2; exit 1; }
printf '<rss>signed appcast fixture</rss>\n' > "$output_path"
echo "generate_appcast output"
GENERATE_APPCAST

cat > "$SPARKLE_BIN/sign_update" <<'SIGN_UPDATE'
#!/usr/bin/env bash
printf 'sign_update' >> "$CALL_LOG"
for argument in "$@"; do
  printf '\t%s' "$argument" >> "$CALL_LOG"
done
printf '\n' >> "$CALL_LOG"
[[ -f "${!#}" ]] || { echo "missing appcast to verify" >&2; exit 1; }
echo "sign_update verification output"
SIGN_UPDATE

chmod +x \
  "$PREPARE_BIN/codesign" \
  "$PREPARE_BIN/xcrun" \
  "$SPARKLE_BIN/generate_appcast" \
  "$SPARKLE_BIN/sign_update"

if output="$(
  PATH="$PREPARE_BIN:$PATH" \
    CALL_LOG="$CALL_LOG" \
    FAKE_SIGNING_AUTHORITY="Apple Development: Sideby Test" \
    SIDEBY_VERSION=0.7.0 \
    SIDEBY_BUILD_NUMBER=2 \
    SIDEBY_RELEASE_NOTES_PATH="$TEST_ROOT/Sideby-0.7.0.md" \
    "$PREPARE_ROOT/scripts/prepare_sparkle_release.sh" \
    2>&1
)"; then
  echo "expected non-Developer-ID release preparation to fail" >&2
  exit 1
fi
if [[ "$output" != *"Developer ID Application"* ]]; then
  echo "expected Developer ID authority failure: $output" >&2
  exit 1
fi
if grep -Eq '^(xcrun|generate_appcast)' "$CALL_LOG"; then
  echo "stapler and Sparkle must not run for a non-Developer-ID DMG" >&2
  exit 1
fi

: > "$CALL_LOG"
if ! output="$(
  PATH="$PREPARE_BIN:$PATH" \
    CALL_LOG="$CALL_LOG" \
    SIDEBY_VERSION=0.7.0 \
    SIDEBY_BUILD_NUMBER=2 \
    SIDEBY_RELEASE_NOTES_PATH="$TEST_ROOT/Sideby-0.7.0.md" \
    "$PREPARE_ROOT/scripts/prepare_sparkle_release.sh" \
    2> "$PREPARE_STDERR"
)"; then
  echo "expected hermetic release preparation to pass" >&2
  cat "$PREPARE_STDERR" >&2
  exit 1
fi

expected_output="$PREPARE_ROOT/dist/Sideby-0.7.0.dmg
$PREPARE_ROOT/dist/Sideby-0.7.0.md
$PREPARE_ROOT/dist/appcast.xml"
if [[ "$output" != "$expected_output" ]]; then
  echo "expected exactly three release asset paths, got: $output" >&2
  exit 1
fi

if [[ "$(sed -n '1p' "$CALL_LOG")" != $'codesign\t--verify --verbose '* ]]; then
  echo "expected codesign verification first" >&2
  exit 1
fi
if [[ "$(sed -n '2p' "$CALL_LOG")" != $'codesign\t--display --verbose=4 '* ]]; then
  echo "expected Developer ID authority inspection second" >&2
  exit 1
fi
if [[ "$(sed -n '3p' "$CALL_LOG")" != $'xcrun\tstapler validate '* ]]; then
  echo "expected stapler validation before Sparkle generation" >&2
  exit 1
fi

generate_call="$(sed -n '4p' "$CALL_LOG")"
for expected_argument in \
  $'--account\tsideby-sparkle' \
  $'--download-url-prefix\thttps://github.com/ethznn/sideby/releases/download/v0.7.0/' \
  $'--release-notes-url-prefix\thttps://github.com/ethznn/sideby/releases/download/v0.7.0/' \
  $'--link\thttps://github.com/ethznn/sideby/releases/tag/v0.7.0' \
  $'--maximum-versions\t1' \
  $'--maximum-deltas\t0'; do
  if [[ "$generate_call" != *"$expected_argument"* ]]; then
    echo "missing safe generate_appcast arguments: $expected_argument" >&2
    exit 1
  fi
done
if [[ "$generate_call" == *"--ed-key-file"* || "$generate_call" == *$'\t-s\t'* ]]; then
  echo "generate_appcast must not receive private key material" >&2
  exit 1
fi

sign_call="$(sed -n '5p' "$CALL_LOG")"
if [[ "$sign_call" != $'sign_update\t--account\tsideby-sparkle\t--verify\t'* ]]; then
  echo "expected Keychain-backed appcast verification last: $sign_call" >&2
  exit 1
fi

cmp "$TEST_ROOT/Sideby-0.7.0.md" "$PREPARE_ROOT/dist/Sideby-0.7.0.md"
[[ -s "$PREPARE_ROOT/dist/appcast.xml" ]] || {
  echo "expected generated appcast in dist" >&2
  exit 1
}

echo "release metadata tests passed"

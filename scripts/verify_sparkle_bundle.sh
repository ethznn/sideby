#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:?usage: verify_sparkle_bundle.sh <app-bundle>}"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
EXPECTED_FEED_URL="https://github.com/ethznn/sideby/releases/latest/download/appcast.xml"

fail() {
  echo "error: $1" >&2
  exit 1
}

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

[[ "$(read_plist SUFeedURL)" == "$EXPECTED_FEED_URL" ]] || fail "unexpected SUFeedURL"
SPARKLE_PUBLIC_KEY="$(read_plist SUPublicEDKey)"
[[ -n "$SPARKLE_PUBLIC_KEY" ]] || fail "missing SUPublicEDKey"
[[ "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "invalid SUPublicEDKey"
[[ "$(read_plist SUScheduledCheckInterval)" == "86400" ]] || fail "unexpected schedule"
[[ "$(read_plist SUAllowsAutomaticUpdates)" == "false" ]] || fail "automatic updates must be disabled"
[[ "$(read_plist SUVerifyUpdateBeforeExtraction)" == "true" ]] || fail "pre-extraction verification must be enabled"
[[ "$(read_plist SURequireSignedFeed)" == "true" ]] || fail "signed feed must be required"
[[ ! -e "$FRAMEWORK/Versions/B/XPCServices" ]] || fail "non-sandbox app must not ship Sparkle XPC services"
[[ ! -e "$FRAMEWORK/XPCServices" && ! -L "$FRAMEWORK/XPCServices" ]] || fail "non-sandbox app must not ship Sparkle XPC services"
[[ -x "$FRAMEWORK/Versions/B/Autoupdate" ]] || fail "missing Autoupdate"
[[ -d "$FRAMEWORK/Versions/B/Updater.app" ]] || fail "missing Updater.app"
codesign --verify --deep --strict "$APP_DIR"

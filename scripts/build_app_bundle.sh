#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="SidebyApp"
APP_NAME="Sideby.app"
EXECUTABLE_NAME="Sideby"
APP_BUNDLE_ID="${SIDEBY_BUNDLE_ID:-io.github.ethznn.sideby}"
BUILD_NUMBER="${SIDEBY_BUILD_NUMBER:-1}"
VERSION="${SIDEBY_VERSION:-0.6.0}"
BUILD_CONFIGURATION="${SIDEBY_BUILD_CONFIGURATION:-release}"
# Protected product-bundle decision: keep sandbox off for the current direct
# distribution baseline unless the user explicitly approves a release-strategy change.
APP_SANDBOX="${SIDEBY_APP_SANDBOX:-0}"
APPLE_EVENTS_TEMPORARY_EXCEPTION="${SIDEBY_APPLE_EVENTS_TEMPORARY_EXCEPTION:-0}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
APP_ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"
SPARKLE_PUBLIC_KEY_FILE="$ROOT_DIR/Resources/SparklePublicKey.txt"

SPARKLE_PUBLIC_KEY="$(tr -d '\r\n' < "$SPARKLE_PUBLIC_KEY_FILE")"
if [[ ! "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "error: invalid Sparkle public key" >&2
  exit 1
fi

cd "$ROOT_DIR"

ENTITLEMENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/sideby-entitlements.XXXXXX.plist")"
trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT

swift build -c "$BUILD_CONFIGURATION" --product "$PRODUCT_NAME"
BUILD_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
SPARKLE_FRAMEWORK_SOURCE="$(
  find "$ROOT_DIR/.build/artifacts" \
    -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' \
    -type d -print -quit
)"

if [[ -z "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "error: resolved Sparkle.framework was not found" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

ditto "$SPARKLE_FRAMEWORK_SOURCE" "$SPARKLE_FRAMEWORK"
rm -rf "$SPARKLE_FRAMEWORK/Versions/B/XPCServices" "$SPARKLE_FRAMEWORK/XPCServices"

if [[ -f "$APP_ICON_FILE" ]]; then
  cp "$APP_ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Sideby</string>
  <key>CFBundleDisplayName</key>
  <string>Sideby</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Sideby sends a System Events command only when you request a Space switch, so selected displays can move to the next work context.</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>SUFeedURL</key>
  <string>https://github.com/ethznn/sideby/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUAllowsAutomaticUpdates</key>
  <false/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SURequireSignedFeed</key>
  <true/>
</dict>
</plist>
PLIST

SANDBOX_ENTITLEMENT=""
if [[ "$APP_SANDBOX" == "1" ]]; then
  SANDBOX_ENTITLEMENT='  <key>com.apple.security.app-sandbox</key>
  <true/>'
fi

APPLE_EVENTS_TEMPORARY_EXCEPTION_ENTITLEMENT=""
if [[ "$APP_SANDBOX" == "1" && "$APPLE_EVENTS_TEMPORARY_EXCEPTION" == "1" ]]; then
  APPLE_EVENTS_TEMPORARY_EXCEPTION_ENTITLEMENT='  <key>com.apple.security.temporary-exception.apple-events</key>
  <array>
    <string>com.apple.systemevents</string>
  </array>'
fi

cat > "$ENTITLEMENTS_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$SANDBOX_ENTITLEMENT
  <key>com.apple.security.automation.apple-events</key>
  <true/>
$APPLE_EVENTS_TEMPORARY_EXCEPTION_ENTITLEMENT
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${SIDEBY_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -p codesigning -v \
      | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
      | head -n 1
  )"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -p codesigning -v \
      | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
fi

codesign_component() {
  local component="$1"
  codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$component"
}

codesign_component "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
codesign_component "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
codesign_component "$SPARKLE_FRAMEWORK"
codesign --force --options runtime --entitlements "$ENTITLEMENTS_FILE" \
  --sign "$SIGNING_IDENTITY" "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
"$ROOT_DIR/scripts/verify_sparkle_bundle.sh" "$APP_DIR"

echo "$APP_DIR"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="SidebyApp"
APP_NAME="Sideby.app"
EXECUTABLE_NAME="Sideby"
APP_BUNDLE_ID="${SIDEBY_BUNDLE_ID:-dev.sideby.Sideby}"
BUILD_NUMBER="${SIDEBY_BUILD_NUMBER:-1}"
VERSION="${SIDEBY_VERSION:-0.1.0}"
# Protected product-bundle decision: keep sandbox off for the current direct
# distribution baseline unless the user explicitly approves a release-strategy change.
APP_SANDBOX="${SIDEBY_APP_SANDBOX:-0}"
APPLE_EVENTS_TEMPORARY_EXCEPTION="${SIDEBY_APPLE_EVENTS_TEMPORARY_EXCEPTION:-0}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"

cd "$ROOT_DIR"

ENTITLEMENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/sideby-entitlements.XXXXXX.plist")"
trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT

swift build --product "$PRODUCT_NAME"
BUILD_DIR="$(swift build --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

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
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Sideby sends a System Events command only when you request a Space switch, so selected displays can move to the next work context.</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
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

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_FILE" --sign - "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"

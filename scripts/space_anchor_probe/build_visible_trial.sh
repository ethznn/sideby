#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SOURCE_DIR/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/visible-space-trial.noindex"
APP="$BUILD_DIR/SpaceTransitionTrial.app"
mkdir -p "$APP/Contents/MacOS" "$BUILD_DIR/ModuleCache"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.ethznn.spacetransitiontrial</string>
<key>CFBundleName</key><string>SpaceTransitionTrial</string>
<key>CFBundleExecutable</key><string>SpaceTransitionTrial</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cat > "$BUILD_DIR/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$BUILD_DIR/ModuleCache" "$SOURCE_DIR/VisibleTransitionTrial.swift" \
  -o "$APP/Contents/MacOS/SpaceTransitionTrial"
codesign --force --sign - --entitlements "$BUILD_DIR/entitlements.plist" "$APP"
codesign --verify --strict "$APP"
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$SOURCE_DIR/ObserveSpaceState.swift" \
  -o "$BUILD_DIR/ObserveSpaceState"
printf '%s\n' "$APP"

#!/bin/bash
set -euo pipefail
# Keep this experiment disabled until its focus and recovery design is reviewed.
printf '%s\n' 'SpaceAnchorProbe build disabled after an input/focus failure. See README.md.' >&2
exit 1

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SOURCE_DIR/../.." && pwd)"
PROBE_BUILD_DIR="${PROBE_BUILD_DIR:-$ROOT_DIR/.build/space-anchor-probe.noindex}"
APP="$PROBE_BUILD_DIR/SpaceAnchorProbe.app"
mkdir -p "$APP/Contents/MacOS" "$PROBE_BUILD_DIR/ModuleCache"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.ethznn.spaceanchorprobe</string>
<key>CFBundleName</key><string>SpaceAnchorProbe</string>
<key>CFBundleExecutable</key><string>SpaceAnchorProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cat > "$PROBE_BUILD_DIR/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$PROBE_BUILD_DIR/ModuleCache" \
  "$SOURCE_DIR/AnchorModel.swift" "$SOURCE_DIR/SpaceAnchorProbe.swift" \
  -o "$APP/Contents/MacOS/SpaceAnchorProbe"
codesign --force --sign - --entitlements "$PROBE_BUILD_DIR/entitlements.plist" "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"

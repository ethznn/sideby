#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUILD_SCRIPT="$ROOT_DIR/scripts/build_app_bundle.sh"
APP_NAME="Sideby.app"
VOLUME_NAME="${SIDEBY_DMG_VOLUME_NAME:-Sideby Installer}"
WINDOW_WIDTH="${SIDEBY_DMG_WINDOW_WIDTH:-660}"
WINDOW_HEIGHT="${SIDEBY_DMG_WINDOW_HEIGHT:-420}"
ICON_SIZE="${SIDEBY_DMG_ICON_SIZE:-112}"
APP_ICON_X="${SIDEBY_DMG_APP_ICON_X:-170}"
APP_ICON_Y="${SIDEBY_DMG_APP_ICON_Y:-205}"
APPLICATIONS_ICON_X="${SIDEBY_DMG_APPLICATIONS_ICON_X:-490}"
APPLICATIONS_ICON_Y="${SIDEBY_DMG_APPLICATIONS_ICON_Y:-205}"

cd "$ROOT_DIR"

if [[ "${SIDEBY_SKIP_APP_BUILD:-0}" != "1" ]]; then
  "$APP_BUILD_SCRIPT"
fi

APP_DIR="$ROOT_DIR/dist/$APP_NAME"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: missing app bundle at $APP_DIR" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="${SIDEBY_DMG_PATH:-$ROOT_DIR/dist/Sideby-$VERSION.dmg}"
DMG_DIR="$(dirname "$DMG_PATH")"

if [[ -e "/Volumes/$VOLUME_NAME" ]]; then
  echo "error: /Volumes/$VOLUME_NAME is already mounted; detach it before building the release DMG" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sideby-release-dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
RW_DMG="$WORK_DIR/Sideby-rw.dmg"
BACKGROUND_SWIFT="$WORK_DIR/GenerateDMGBackground.swift"
BACKGROUND_PATH="$STAGING_DIR/.background/background.png"
APPLESCRIPT_FILE="$WORK_DIR/LayoutDMG.applescript"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/.background" "$DMG_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$BACKGROUND_SWIFT" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let width = Int(CommandLine.arguments[2]),
      let height = Int(CommandLine.arguments[3]) else {
    fputs("usage: GenerateDMGBackground.swift <output> <width> <height>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: width, height: height)
let rect = NSRect(origin: .zero, size: size)
let image = NSImage(size: size)

image.lockFocus()

NSGradient(
    starting: NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.97, alpha: 1),
    ending: NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.93, alpha: 1)
)?.draw(in: rect, angle: -90)

let center = NSPoint(x: size.width / 2, y: size.height / 2)
let arrow = NSBezierPath()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: center.x - 24, y: center.y + 34))
arrow.line(to: NSPoint(x: center.x + 16, y: center.y))
arrow.line(to: NSPoint(x: center.x - 24, y: center.y - 34))
NSColor(calibratedWhite: 0.15, alpha: 1).setStroke()
arrow.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("error: failed to render DMG background\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
SWIFT

swift "$BACKGROUND_SWIFT" "$BACKGROUND_PATH" "$WINDOW_WIDTH" "$WINDOW_HEIGHT"

hdiutil create "$RW_DMG" \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -quiet

hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -quiet
MOUNT_POINT="/Volumes/$VOLUME_NAME"

for _ in {1..40}; do
  if [[ -d "$MOUNT_POINT" ]]; then
    break
  fi
  sleep 0.25
done

if [[ ! -d "$MOUNT_POINT" ]]; then
  echo "error: failed to mount $VOLUME_NAME" >&2
  exit 1
fi

cat > "$APPLESCRIPT_FILE" <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 120 + $WINDOW_WIDTH, 120 + $WINDOW_HEIGHT}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME" of container window to {$APP_ICON_X, $APP_ICON_Y}
    set position of item "Applications" of container window to {$APPLICATIONS_ICON_X, $APPLICATIONS_ICON_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

osascript "$APPLESCRIPT_FILE"
rm -rf "$MOUNT_POINT/.fseventsd" "$MOUNT_POINT/.Trashes"
sync

for attempt in 1 2 3 4 5; do
  if hdiutil detach "$MOUNT_POINT" -quiet; then
    MOUNT_POINT=""
    break
  fi
  if [[ "$attempt" == "5" ]]; then
    echo "error: failed to detach $MOUNT_POINT" >&2
    exit 1
  fi
  sleep 1
done

rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" \
  -quiet

hdiutil verify "$DMG_PATH" -quiet

SIGNING_IDENTITY="${SIDEBY_DMG_SIGNING_IDENTITY:-${SIDEBY_SIGNING_IDENTITY:-}}"
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
  codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose "$DMG_PATH"
fi

echo "$DMG_PATH"

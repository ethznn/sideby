#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:?usage: verify_menu_bar_only_bundle.sh <app-bundle>}"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: missing Info.plist at $INFO_PLIST" >&2
  exit 1
fi

VALUE="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST" 2>/dev/null || true)"
if [[ "$VALUE" != "true" ]]; then
  echo "error: LSUIElement is not true in $INFO_PLIST" >&2
  exit 1
fi

echo "$APP_DIR: LSUIElement=true"

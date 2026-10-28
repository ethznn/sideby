#!/bin/bash
set -euo pipefail

# This compiles source and runs Foundation-only data checks. It never builds or
# launches an app bundle, initializes AppKit, or changes the current desktop.
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SOURCE_DIR/../.." && pwd)"
mkdir -p "$ROOT_DIR/.build"
CHECK_DIR="$(mktemp -d "$ROOT_DIR/.build/space-anchor-offline.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
mkdir -p "$CHECK_DIR/ModuleCache"

xcrun swiftc -swift-version 6 -parse-as-library -typecheck \
  -module-cache-path "$CHECK_DIR/ModuleCache" \
  "$SOURCE_DIR/AnchorModel.swift" "$SOURCE_DIR/SpaceAnchorProbe.swift"
printf '%s\n' 'PASS: disabled AppKit source type-checks (not executed)'

for trial_source in VisibleTransitionTrial.swift ObserveSpaceState.swift; do
  xcrun swiftc -swift-version 6 -parse-as-library -typecheck \
    -module-cache-path "$CHECK_DIR/ModuleCache" "$SOURCE_DIR/$trial_source"
done
printf '%s\n' 'PASS: public-API trial and observer type-check (not executed)'

xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path "$CHECK_DIR/ModuleCache" \
  "$SOURCE_DIR/AnchorModel.swift" "$SOURCE_DIR/ModelChecks.swift" \
  -o "$CHECK_DIR/ModelChecks"
"$CHECK_DIR/ModelChecks"
python3 "$SOURCE_DIR/supervise_trial.py" --self-test

printf '%s\n' 'Offline checks complete. These checks do not establish that Space switching or input is safe.'

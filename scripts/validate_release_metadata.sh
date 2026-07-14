#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: validate_release_metadata.sh <version> <build-number>}"
BUILD_NUMBER="${2:?usage: validate_release_metadata.sh <version> <build-number>}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be a three-part semantic version" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || (( BUILD_NUMBER <= 0 )); then
  echo "error: build number must be a positive integer" >&2
  exit 1
fi

if (( BUILD_NUMBER <= 1 )); then
  echo "error: Sparkle build number must be greater than shipped build 1" >&2
  exit 1
fi

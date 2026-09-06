#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="$ROOT_DIR/notifly-kmp-sdk"
SOURCE="$SUBMODULE_DIR/kmp/build/XCFrameworks/release/NotiflyKMP.xcframework"
OUTPUT_DIR="$ROOT_DIR/build/kmp"
OUTPUT="$OUTPUT_DIR/NotiflyKMP.xcframework"

if [[ ! -x "$SUBMODULE_DIR/gradlew" ]]; then
  echo "notifly-kmp-sdk is not initialized. Run: git submodule update --init --recursive" >&2
  exit 1
fi

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

if ! command -v java >/dev/null 2>&1; then
  echo "Java 17 or newer is required to build NotiflyKMP." >&2
  exit 1
fi

"$SUBMODULE_DIR/gradlew" \
  -p "$SUBMODULE_DIR" \
  :kmp:iosSimulatorArm64Test \
  :kmp:assembleNotiflyKMPReleaseXCFramework \
  --no-daemon

if [[ ! -d "$SOURCE" ]]; then
  echo "KMP build completed without producing $SOURCE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
TEMP_OUTPUT="$(mktemp -d "$OUTPUT_DIR/.NotiflyKMP.XXXXXX")"
trap 'rm -rf "$TEMP_OUTPUT"' EXIT
cp -R "$SOURCE" "$TEMP_OUTPUT/NotiflyKMP.xcframework"

rm -rf "$OUTPUT"
mv "$TEMP_OUTPUT/NotiflyKMP.xcframework" "$OUTPUT"

echo "$OUTPUT"

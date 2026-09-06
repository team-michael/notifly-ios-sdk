#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_COMMIT="5a2bff2ca515a1ab65ee2f644c73ffda99e23cd4"
SUBMODULE_DIR="$ROOT_DIR/notifly-kmp-sdk"
OUTPUT="$ROOT_DIR/build/kmp/NotiflyKMP.xcframework"

if [[ ! -f "$ROOT_DIR/.gitmodules" ]]; then
  echo "Missing .gitmodules" >&2
  exit 1
fi

if [[ ! -e "$SUBMODULE_DIR/.git" ]]; then
  echo "Missing initialized notifly-kmp-sdk submodule" >&2
  exit 1
fi

ACTUAL_COMMIT="$(git -C "$SUBMODULE_DIR" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]]; then
  echo "Expected KMP commit $EXPECTED_COMMIT but found $ACTUAL_COMMIT" >&2
  exit 1
fi

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

"$SUBMODULE_DIR/gradlew" \
  -p "$SUBMODULE_DIR" \
  :kmp:iosSimulatorArm64Test \
  --no-daemon

"$ROOT_DIR/scripts/build_kmp_xcframework.sh"

if [[ ! -f "$OUTPUT/Info.plist" ]]; then
  echo "Missing $OUTPUT" >&2
  exit 1
fi

DEVICE_BINARY="$OUTPUT/ios-arm64/NotiflyKMP.framework/NotiflyKMP"
SIMULATOR_BINARY="$OUTPUT/ios-arm64_x86_64-simulator/NotiflyKMP.framework/NotiflyKMP"

file "$DEVICE_BINARY" | grep -F "current ar archive" >/dev/null
file "$SIMULATOR_BINARY" | grep -F "current ar archive" >/dev/null

xcrun lipo -archs "$DEVICE_BINARY" | grep -F "arm64" >/dev/null
xcrun lipo -archs "$SIMULATOR_BINARY" | grep -F "arm64" >/dev/null
xcrun lipo -archs "$SIMULATOR_BINARY" | grep -F "x86_64" >/dev/null

echo "Pinned static NotiflyKMP XCFramework is valid."
